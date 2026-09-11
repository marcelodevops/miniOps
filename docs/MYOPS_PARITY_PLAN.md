# miniOps: native myOps parity plan

Updated: 2026-09-11

## Objective and assumptions

Preserve myops-os capabilities in a native SwiftUI/AppKit application with a panels-based workspace inspired by Zed and VS Code. The user clarified that panels, including dedicated Tickets and Agents panels, are the desired layout. myops-os is the feature and behavior reference; its dashboard navigation and drawer geometry are not the target layout. Retain SwiftTerm and the existing native services.

Assume the current `/Users/mac/repos/myops-os` checkout is the reference. Before implementation, compare it with the user's familiar running myOps build and resolve any differences. Preserve existing miniOps capabilities, including Git safety, editor safeguards, terminal sessions, Herdr integration, and Keychain storage. This document authorizes no deployment or replacement.

## Findings from the current sources

| Area | myops-os reference | miniOps today | Work needed |
|---|---|---|---|
| Navigation | Overview, Focus, Repos, Tickets, Agents, Graph, Settings | Repository/file navigator; global tools inside a repository-dependent inspector | Introduce panel navigation; distinguish workspace-wide panels from repository-scoped tools |
| Overview | Summary tiles, attention lists, charts with filter links | Menu bar summary exists; no equivalent landing page in the main window | Build the dashboard from native models; port missing summary fields |
| Focus | Active ticket with repository, agent, and context cards | Tickets, repositories, and agents exist separately | Restore the connected active-work workflow |
| Repositories | Searchable/filterable cards, groups, health and sync information | Searchable repository/file tree and toolbar | Preserve browsing, grouping, filters, and health in a Repositories panel |
| Repository work | Editor above terminal on the left, repository detail drawer on the right | Tools replaces the editor/terminal canvas through `isGitInspectorOpen` | Keep workbench and repository details visible together |
| Changes, stash, worktrees, notes | Sections/actions in repository detail | Existing native feature views | Recompose existing views; audit individual action parity |
| Tickets | Workspace page with status/priority/type/project filters and details | Native ticket manager and sidebar; search/open filter; Jira service | Make accessible without selecting a repository; complete filters and detail actions |
| Agents | Workspace cards, attention state, repository links, context usage when available | Agent inspector and process/Herdr services | Expose a workspace-wide Agents panel; audit metadata and usage parity |
| Graph | Interactive graph, dataset selector, neighborhoods, node details | Native graph summary/community/node browsing | Audit and implement missing graph interactions natively |
| Status and settings | Refresh freshness, operation history, independent repo/Jira sync, paths and credentials | Native settings/services plus local banners | Unify status presentation and verify settings/data parity |

Presence in source is not proof of working parity. Each row needs runtime acceptance checks before it can be marked complete.

The earlier overlapping Changes layout has subsequent source fixes (`544c270`, `4876d22`, with `SplitPaneLayout` introduced in `f10028f`). Verify those fixes in the candidate build; do not redo them from the earlier diagnosis. They do not address the broader navigation and workbench mismatch.

## Target layout

Use one persistent workbench with a center and three dock areas. Proposed defaults (placement can change):

| Region | Default content | Behavior |
|---|---|---|
| Left dock | Repositories/Files, Tickets | Panel selectors; search, filters, trees/lists |
| Center | File editor, diff, ticket or agent detail | Detail tabs; opening a panel does not replace the active document |
| Right dock | Agents, Git Changes, Notes | Context tools beside the editor |
| Bottom dock | Terminal, operation output | Resizable, collapsible; sessions survive hiding |
| Status bar | Branch, refresh freshness, background activity | Compact status and access to relevant actions |

Tickets and Agents must be usable simultaneously, including alongside the terminal and editor. Workspace-wide panels work without a repository selection; repository-specific actions clearly show their target repository.

Panel behavior:

- Each dock can be opened, closed, and resized independently. Closing a panel hides its view without cancelling its underlying work.
- Panels can move between supported docks through a simple “Move Panel” menu. Start with explicit placement controls; drag-and-drop docking can follow after the layout is reliable.
- Tabs/selectors switch panels within a dock. A user can put Tickets on the left and Agents on the right to see both at once.
- Selecting a ticket shows its details in a center tab; opening a file or diff uses the same center area. Selecting an agent shows details and a route to its repository/session.
- Overview, Focus, and Graph remain available as center tabs rather than replacing the application shell. Settings uses a native settings surface.
- Preserve panel placement, dock sizes, and visibility per workspace; retain file/repository context separately. Provide Reset Layout.
- Keyboard commands toggle/focus panels. Active focus and unread/attention badges remain visible and accessible.
- For narrow windows, enforce tested minimums and offer explicit dock collapse. Never overlap docks or silently discard context.

Retain the familiar myOps status colors and information density where useful, with native controls and consistent spacing. Exact appearance is to be settled in the annotated layout review; this plan does not prescribe a new visual identity.

The first version needs predictable left/right/bottom docks, not a general-purpose window docking framework. Floating windows, arbitrary nested splits, and drag docking are outside the first milestone.

## Milestones and completion gates

### 1. Capture the reference and freeze the parity checklist

- Capture both apps at the same window sizes and with equivalent non-sensitive repository/ticket fixtures.
- Inventory every visible action in the reference, including menus, filters, keyboard shortcuts, loading/error states, and navigation/back behavior.
- Mark each item: verified equivalent, present but different, missing, or intentionally different. Record any intentional difference explicitly rather than silently dropping behavior.
- Use myOps captures to inventory content, then produce an annotated panel-workspace layout with Tickets and Agents visible together. Use the named editor references for the interaction direction, not assumed feature requirements.
- Record source revisions and running bundle provenance so comparison does not mix builds.

**Gate:** a reviewable screen map and action checklist, with the target panel workspace shown before implementing it. This is the first product checkpoint.

### 2. Restore the native application shell

- Add panel/dock state and center-tab selection independently of the selected repository.
- Rework `MainWindowView` into persistent left/center/right/bottom regions; Tickets and Agents do not require `selectedRepo`.
- Introduce a single owner for each split's geometry, minimum sizes, and collapse behavior. Reuse the existing split geometry where appropriate; use AppKit split hosting only if a focused native layout experiment proves it necessary.
- Keep terminal session identity and editor buffer lifetime outside conditional screen composition.
- Place refresh/freshness and operation status in the shared status bar and output panel.

**Gate:** show Tickets and Agents together, switch center tabs, select/close a repository, move panels, resize, and toggle docks without clipping or losing state. Existing Git/editor/terminal behavior still works. Empty/loading/error states are deliberate.

### 3. Deliver one complete repository workflow

- Populate Repositories/Files, Tickets, and Agents panels using existing native services; preserve repository health fields, filters, and grouped navigation.
- Compose editor/diff/detail tabs in the center, SwiftTerm in the bottom dock, and Git/Notes in side panels. Keep stash/worktree actions accessible from Git.
- Keep repository actions grouped by purpose, with scope clear for selected-file commits versus stage-all actions.
- Persist dock placement, sizes/visibility, selected file, and repository context. Preserve current state decoding when adding fields.
- Verify secondary actions: external editor, Finder/remote navigation, clone/create/import/hide, and batch action scope. Port missing reference actions such as batch stash only after the inventory confirms the gap.

**Gate:** browse a repository → inspect changes → edit/save → use terminal → selectively commit → return to browse. Tickets, Agents, editor, and terminal coexist; Git details do not replace the workbench. Switching between two repositories restores the correct state. Excluded staged changes remain excluded.

This is the first useful native parity release; complete it before spreading effort across all dashboard pages.

### 4. Restore Overview and Focus as center tabs

- Build attention lists and summary tiles with the same definitions as the reference; add charts and their filter navigation.
- Add active-ticket selection and related repository/agent/context cards using the reference association logic.
- Preserve active work across refresh/relaunch, and show missing associations as unavailable instead of guessing.

**Gate:** counts match the reference for identical fixtures; clicking summaries opens the expected filtered panel; Focus links to the correct repository and agents.

### 5. Complete the remaining feature parity

- Tickets: full filtering, details, Jira/local links, branch workflow, freshness and sync errors.
- Agents: attention state, repository links, notifications, and available context usage; retain Herdr capabilities. Unknown usage remains unknown.
- Graph: datasets, search, neighborhood focus, pan/zoom, selection, report/source links, using native drawing.
- Settings: workspace and ticket paths, connection verification, theme/refresh choices, and import of useful existing configuration.
- Audit notes/settings compatibility before import. Preview mappings, preserve existing miniOps values on conflicts, back up destination state, and leave myOps data intact. Browser-local layout state may need an explicit export; do not assume it is in server data files. Handle credentials through supported Keychain/connection flows.

**Gate:** all inventory items are verified equivalent or have a recorded product decision. Partial views do not count as feature parity.

### 6. Validate and transition

- Exercise 1000×680, 1280×800, and a large desktop window, plus repeated resizing and split dragging. Reconcile the smallest size with the accepted layout minimum.
- Cover clean/dirty/large repositories, long paths, large counts, no tickets, unavailable integrations, slow Git operations, and stale refreshes.
- Test repository locks, literal filenames, selective commits with already-staged excluded files, external editor modifications, and unsaved-buffer transitions using temporary repositories.
- Verify terminal survives dock toggles and center-tab changes within the running app; separately define expected shell behavior after quit/relaunch.
- Run `swift run miniOpsTests`, targeted UI checks, and `graphify update .` after code changes.
- Package a candidate, verify the exact candidate app at runtime, then use it for a normal daily workflow before replacing an installed build. Keep the previous build and data backup available for rollback.

**Gate:** the user can complete the reference's daily workflows without returning to myOps because a feature or layout is missing.

## Implementation boundaries

Reuse `MiniOpsCore` services and existing native feature views. Restructure UI composition and state ownership first; port only missing data/behavior after comparing the actual reference implementation. No wholesale backend rewrite, browser wrapper, new terminal engine, or unrelated feature expansion is needed for this plan.

Deliver each milestone as a small reviewable change with before/after captures and its acceptance results. Avoid fixed calendar estimates until milestone 1 establishes the action inventory and milestone 2 validates the layout approach.

## Source anchors

- myops-os: `dashboard/index.html` (navigation and panel structure), `dashboard/style.css` (visual values and drawer/workbench geometry), `dashboard/app.js` (`openRepoDrawer`, Focus, filters, graph, refresh), `dashboard/README.md` (workflow descriptions).
- miniOps: `Sources/MiniOpsApp/MainWindowView.swift` (conditional Tools/workbench composition), `SplitWorkspaceCanvasView.swift`, `TerminalSessionManager.swift`, `WorkspaceViewModel.swift`, and existing tool views.
- miniOps state/core: `Sources/MiniOpsCore/WorkspaceStateStore.swift`, `Models.swift`, `SplitPaneLayout.swift`, and the existing Git/Jira/agent/graph services.
