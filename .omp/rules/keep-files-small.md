---
name: keep-files-small
description: "Guard against oversized files — target 200-400L, ceiling 600L"
condition: "write|edit|ast_edit"
scope: tool
---

Porydaw's agent pain is oversized files: `songview.cpp:6676`, `mainwindow.cpp:3351`, `songdocument.cpp:2289`. Target 200–400L per file, 600L ceiling. One concept per file.

- When you add code, check the host file's line count. If it would exceed ~600L, split first: create a sibling file in the feature folder (e.g. `src/ui/songview/pianoroll.cpp` or `src/ui/shell/tabs.cpp`) instead of appending.
- `src/ui/editordrawer/` is the model — one gesture/model per file.
- Don't create 80L fragments either — 40 tiny files in one feature is also undiscoverable.
- New `*check.cpp` harnesses go in `src/checks/` (once that dir exists), not `src/` root. Until then, `src/*check.cpp` root is tech debt — don't add more there.
