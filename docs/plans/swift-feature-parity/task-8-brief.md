# Context
Repair R12: shell contrast checks observed C5 ink #1A1A1A on #424242 and #363941. The label is keyboard text; sibling scene rectangles may be omitted by the audit. Establish the real backing surface, then repair the responsible production rendering or measurement, never suppress the assertion. Read plan.md Global constraints, spec.md and rule://text-contrast.

# Exact write set
- src/checks/editorqml/TextContrastAudit.js
- src/checks/editorqml/tst_TextContrast.qml
- src/ui/songview/quick/PianoRollCanvas.qml
- src/swift/app/roll/GridScene.swift
- src/checks/rollqml/tst_TimelinePan.qml

# Prerequisites
None. Do not edit unrelated palette/theme owners without reporting a precise scope need.

# Interface contract
Every visible keyboard label is tested against its actual composited key surface, including clipping/scroll boundaries and dark themes. Preserve scene-graph siblings and shared label models; do not add arbitrary backing rectangles merely to fool the audit. No exemptions keyed on text/name/theme and no hard-coded replacement expected ratio. WCAG AA remains 4.5 normal / 3 large text.

# Implementation steps
1. Trace audit surface resolution and keyboard label/key layer coordinates and clipping. Determine whether failure is real rendering or measurement.
2. Repair the root cause in the owning layer, preserving natural/black key colors and font-derived geometry.
3. Add or adjust behavior checks for the actual failing clipping/compositing case, not source-text tests.
4. Report exact visible observation needed from controller and final predicate paths.
5. Remove the obsolete fixed-keyboard-label parent-chain assertion in `test_hoverChipOverlay`: it pins the out-of-gutter placement this bug repairs. Preserve hover-chip overlay and rendered text behavior checks; do not replace it with an inverse parent-chain assertion.

# Acceptance predicate
All empty/loaded shell contrast presets pass with measured real backing surfaces and no hidden exemption: controller runs `deno task verify:shell --filter shell-text-contrast --verbose` and performs a native screenshot inspection, plus `deno task verify:qml-roll --verbose` for any rendering change.

# Task-specific constraints
SHARED_TREE. Skip builds/tests/lint/formatters; edit only. No comments, commits, scratch reports, palette fallbacks or workarounds.
