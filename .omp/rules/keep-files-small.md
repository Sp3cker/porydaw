---
name: keep-files-small
description: "Guard against oversized files — target 200-400L, ceiling 600L"
condition: "write|edit|ast_edit"
scope: tool
---

Porydaw's agent pain is oversized files: `songview.cpp:6676`, `mainwindow.cpp:3351`, `songdocument.cpp:2289`. One concept per file.

- When you add code, check the host file's line count. If it would exceed ~600L, split first: create a sibling file in the feature folder (e.g. `src/ui/songview/pianoroll.cpp` or `src/ui/shell/tabs.cpp`) instead of appending.
- `src/ui/editordrawer/` is the model — one gesture/model per file.
- Don't create 80L fragments either — 40 tiny files in one feature is also undiscoverable.
- New `*check.cpp` harnesses go in `src/checks/` — never add one to `src/` root. `src/` top-level should stay 3 files (`main.cpp`, `mainwindow.cpp`, `porydaw_scale.cpp`).
