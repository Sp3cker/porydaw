---
name: scope-searches
description: "Require scoped search — never grep without path"
condition: "grep|ast_grep|glob.*pattern|\\bsearch"
scope: tool
---

Always scope searches. Porydaw has 34 harness files (`*check.cpp`), `external/poryaaaa`, and `build-*/`, that drown root scans.

- NEVER call `grep`/`ast_grep`/`glob` without `path`. `path="."` or omitted is a bug.
- NEVER use `path="src"` or `path="."` — use `src/core`, `src/project`, `src/audio`, `src/ui/editordrawer`, `src/ui/theme`, `src/ui/songview.cpp`, or `src/checks` for harnesses.
- NEVER include `external/`, `build-*/`, `.worktrees/`, `.omp/` in a search root.
- Workflow: `glob` to discover → scoped `grep`/`ast_grep` → `lsp definition/references` for symbols → `read file:50-120` ranges.
- For renames/callsites use `lsp` — it follows re-exports that text search misses. Don't do cross-file text renames.
