# miniOps

**miniOps** is a genuinely native macOS workspace and repository manager built with SwiftUI, AppKit, and SwiftTerm.

Inspired by [Ghostty](https://ghostty.org)'s approach to deep platform integration, miniOps is designed for developers who demand responsive interaction and native macOS system integration—with **zero WebViews, zero Electron, zero Tauri, and zero browser-based terminals**.

---

## Architecture & Principles

miniOps is structured into cleanly isolated layers:

* **`MiniOpsCore`**: Pure Swift business logic framework handling Git operations, repository locks, process discovery, ticket parsing, and knowledge graph ingestion. Completely decoupled from UI frameworks.
* **`MiniOpsApp`**: Native SwiftUI and AppKit application implementing the split canvas, window management, Menu Bar Extra status item, and system notifications.
* **`SwiftTerm` Integration**: Native Metal-accelerated PTY terminal emulator running `/bin/zsh -l` with `MYOPS_TERMINAL=1`, loading user Starship prompts (`~/.config/starship.toml`) and resolving installed fonts (such as `JetBrains Mono Nerd Font Mono`) via macOS `NSFontManager`.
* **Non-Destructive Concurrency**: `RepoLockManager` serializes operations on a per-repository basis to prevent concurrent Git operations and index corruption.

---

## Features

### 1. Split Canvas Workspace
* **Collapsible Dual-Pane Canvas**: Seamlessly toggle the native code editor (`Cmd+E`) and embedded terminal (`Cmd+J`) with a draggable divider.
* **Per-Repository Layout Persistence**: Remembers split proportions and pane collapse states individually for each repository via `RepoLayoutState`.
* **Native File Tree**: Hierarchical repository browser with file status badges and quick opening.

### 2. Native Code Editor
* **AppKit `NSTextView`**: Lightweight, responsive native text editor with native find/replace, undo, and syntax styling.
* **Safety Guards**: Detects unsaved modifications with confirmation prompts before quitting, closing, changing workspaces, or switching files; refuses saves when the file has changed on disk.

### 3. Native Embedded Terminal
* **High-Performance PTY**: Powered by SwiftTerm with true VT100/Xterm emulation.
* **Session Persistence**: Terminal sessions are preserved across pane collapse and view transitions via `TerminalSessionManager`.
* **Full Developer Shell**: Preserves custom user environments (`/bin/zsh -l`), path resolution, and prompt themes.

### 4. Advanced Git Operations & Safety
* **Selective Staging & Commits**: Staging specific files via `git commit --only -- <paths>` with `--literal-pathspecs`, preventing accidental commits of unrelated staged changes.
* **Branch Switcher (`Cmd+B`)**: Fast branch switching, remote tracking branch checkout, and safe branch creation with refname validation.
* **Stash Manager (`Cmd+Shift+S`)**: Stash working changes with custom messages, preview unified diffs, and safe stash pop guarded against dirty trees.
* **Worktree Manager (`Cmd+Shift+W`)**: Porcelain parser for `git worktree list`, seamless creation with new or existing branches, and removal.
* **Batch Git Actions (`Cmd+Shift+B`)**: Concurrently fetch, pull (`--ff-only` on clean tracking branches), or reconcile across all workspace repositories.
* **Porcelain Status Parser**: Accurately differentiates between staged, unstaged, untracked, and untracked-in-staged states without trimming whitespace.

### 5. Repository Scratchpad & Notes (`Cmd+Shift+N`)
* Auto-saving per-repository notes stored in `~/Library/Application Support/miniOps/repo-notes.json`.
* Markdown preview and quick-capture interface for meeting notes, PR drafts, or task checklists.

### 6. Menu Bar Extra & System Notifications
* **macOS Menu Bar Status**: Visual indicator displaying repository health:
  * Green checkmark: All repositories clean.
  * Dirty badge (`● X`): Uncommitted changes counter across workspaces.
  * Attention badge (`▲`): Autonomous agent requires user input.
* **Quick Menu Actions**: Reconcile all, fetch all, and one-click window activation.
* **Native Notifications**: Real-time alerts dispatched via `UNUserNotificationCenter`.

### 7. Autonomous Agent Detection & Attention Queue (`Cmd+Shift+A`)
* **Process Scanner**: Discovers background AI coding agent CLIs including Claude Code, OpenAI Codex, Aider, Antigravity, and OpenClaw via process table inspection (`ps -axo`).
* **Working Directory Resolution**: Correlates process working directories using `lsof -a -d cwd -p <pid> -Fn`.
* **Attention Queue**: Heuristically detects when an agent is sleeping on a TTY waiting for user input and dispatches a notification with a jump-to-repo action.

### 8. Task & Ticket Tracking (`Cmd+Shift+T`)
* **Ticket Scanner**: Ingests local markdown tickets (`tickets/*.md`) and `jira-cache.json`.
* **Feature Branch Generation**: Create and checkout standardized feature branches (e.g. `feat/TICK-101-auth-flow`) directly from a ticket.

### 9. Knowledge Graph & Architecture Visualizer (`Cmd+Shift+G`)
* **Graphify Ingestion**: Automatically reads `graphify-out/graph.json` and `GRAPH_REPORT.md`.
* **God Node Identification**: Ranks core architectural components and god nodes by degree centrality.
* **Community Filtering & Search**: Explore modules grouped by community clusters and jump directly into the source file within the native code editor.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Cmd + E` | Toggle Code Editor Pane |
| `Cmd + J` | Toggle Embedded Terminal Pane |
| `Cmd + S` | Save Current File in Editor |
| `Cmd + B` | Open Branch Switcher & Creator |
| `Cmd + Shift + S` | Open Git Stash Manager |
| `Cmd + Shift + W` | Open Git Worktree Manager |
| `Cmd + Shift + B` | Open Batch Git Operations |
| `Cmd + Shift + A` | Open Agent Inspector & Attention Queue |
| `Cmd + Shift + T` | Open Task & Ticket Manager |
| `Cmd + Shift + G` | Open Knowledge Graph Visualizer |
| `Cmd + Shift + N` | Toggle Repository Notes Scratchpad |

---

## Requirements

* **macOS**: macOS 14.0 (Sonoma) or newer.
* **Swift**: Swift 5.9 or newer (via Apple Command Line Tools or Xcode).
* **Terminal Font (Recommended)**: `JetBrains Mono Nerd Font Mono` (or any monospace font configured on macOS).

---

## Building, Testing & Installing

### 1. Run Automated Test Suite
miniOps includes a standalone regression test runner validating Git safety, concurrency serialization, workspace scanning, process discovery, and ticket parsing:

```bash
swift run miniOpsTests
```

### 2. Build Release Application Bundle
Compile and package `.build/miniOps.app` with native macOS bundle metadata and app icon:

```bash
./scripts/build-app.sh
```

### 3. Create Distributable DMG Disk Image
Generate a compressed `.dmg` installer with an `Applications` symlink:

```bash
./scripts/package-dmg.sh
```
The resulting disk image will be placed at `dist/miniOps-1.0.0.dmg` (and `dist/miniOps.dmg`).

### 4. Install into `/Applications`
Install the application directly to `/Applications/miniOps.app`:

```bash
./scripts/install-app.sh

# Or install and launch immediately:
./scripts/install-app.sh --launch
```

---

## Data & Configuration Locations

* **Application Identifier**: `com.marcelodevops.miniOps.dev`
* **Repository Notes**: `~/Library/Application Support/miniOps/repo-notes.json`
* **Layout State**: Per-repository window split ratios cached automatically in application state.

---

## License

Internal Developer Tool. All rights reserved.

## Current iteration

Repository scanning and agent discovery run off the main UI thread. The sidebar includes a repository filter, and the editor uses the macOS Find bar (Command-F) for highlighting, next/previous matches, and replacement.

Reconcile in the changes panel requires a nonempty file selection. Git status preserves Unicode, whitespace, and newline filenames. Editor paths are checked against resolved repository boundaries, including symlinks.

Remaining work includes enforcing Git subprocess deadlines, editor line numbers, and more complete UI automation. Long-running Git actions retain their repository lock; there is no unsafe force-unlock mechanism.
