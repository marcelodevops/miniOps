# Global Antigravity Configuration & Rules

## Graphify Python Version and Source

- **Do NOT change the current Python graphify installation.** This is the correct version.
- **Source repository**: https://github.com/Graphify-Labs/graphify
- **NEVER replace, reinstall, upgrade, downgrade, or overwrite the installed graphify binary or Python environment.**
- Always use the installed graphify binary (`/Users/mac/.local/bin/graphify` running via `/Users/mac/.local/share/uv/tools/graphifyy/bin/python`).
- For codebase and architecture questions, when `graphify-out/graph.json` exists, first run `graphify query "<question>"` (CLI) or use graph traversal. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- If `graphify-out/wiki/index.md` exists, navigate it instead of reading raw files.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code files, run `graphify update .` to keep the graph current (AST-only, no API cost).
