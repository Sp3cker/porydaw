---
name: keep-files-small
description: "Guard against oversized and fragmented files — review cohesion above 600L"
condition: "write|edit|ast_edit"
scope: tool
---

Porydaw's agent pain is both oversized files and concepts scattered across
arbitrary fragments. Optimize for cohesion and discoverability; line count is
only a review signal.

- Around 600L, file size becomes a review signal. If a change would materially
  grow the file, consider whether its responsibilities are still cohesive.
  A cohesive file may exceed 600L. Never move or split code solely to satisfy
  a line-count target.
- Split when the resulting code has a real ownership boundary, independent
  reason to change, meaningful abstraction, or useful test seam.
- Prefer one feature directory with a small public surface when one concept
  needs several private implementation files.
- `src/ui/editordrawer/` is the model: related concepts stay together in a
  discoverable module, with file boundaries following meaningful ownership
  or implementation seams.
- Don't create tiny fragments merely to reduce line counts. Many small files
  can be less discoverable than one larger cohesive file.
- New `*check.cpp` harnesses go in `src/checks/` — never add one to `src/`
  root. `src/` top-level should stay 3 files (`main.cpp`, `mainwindow.cpp`,
  `porydaw_scale.cpp`).