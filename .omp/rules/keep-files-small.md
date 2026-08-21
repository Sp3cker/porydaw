---
name: keep-files-small
description: "Guard against oversized and fragmented files — review cohesion above 600L"
condition: "write|edit|ast_edit"
scope: tool
---

Porydaw's agent pain is oversized files and concepts scattered across arbitrary
fragments. Keep ownership clear; line count is a warning, not a design rule.

- When you add code, check the host file's line count. Above ~600L, review the
  file's responsibilities before adding more. Split only when the code has a
  real ownership, change-reason, or test seam. Do not split solely to get below
  the threshold; a cohesive file may exceed it.
- Prefer one feature directory with a small public surface when one concept
  needs several private implementation files.
- `src/ui/editordrawer/` is the model — keep one cohesive gesture or model per
  file, and group its private implementation files under the same module.
- Don't create 80L fragments merely to reduce line counts — 40 tiny files in
  one feature is also undiscoverable.
- New `*check.cpp` harnesses go in `src/checks/` — never add one to `src/` root. `src/` top-level should stay 3 files (`main.cpp`, `mainwindow.cpp`, `porydaw_scale.cpp`).
