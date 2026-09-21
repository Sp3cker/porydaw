# automationquick removal — plan

Excise the dead C++ automation drawer surface so no C++ touches the QML
automation seam. Two tasks: paint-path removal first (it owns the only
`rebuildQuickScene` implementation and the QML band), then the
`AutomationCanvas` family and its dead check twins. Hygiene gate last.

## Global Constraints

- Read `spec.md` (vocabulary, boundary rule, non-goals) first; briefs carry
  deltas only.
- Every file in the write sets is uncompiled dead code. Deletion is the
  change; there is no behavior to preserve. Edits to referencing dead files
  remove references only — no redesign, no drive-by cleanup of unrelated
  dead code.
- Live files that MUST NOT be touched: everything under
  `src/swift/app/drawer/automation/`, `src/ui/songview/quick/drawer/`,
  `velocityquick.cpp`, `voicechangequick.cpp`, `VelocityArea`,
  `VoiceChangeArea`, all `.swift` files under `src/checks/`, and all
  `proof.*.txt` fixtures.
- `TimelineQuickView`, `TimelineCanvas.qml`, `timelinequickscene.h`, C++
  `AutomationPage`, `EditorDrawer`, `SongView` stay; edit only the lines
  that reference the removed surface.
- Workarounds require approval per AGENTS.md: stop, name root cause, wait.
- Implementers run the Verification policy below as written; reassess only
  if scope changes or a command proves stale or unavailable, reporting the
  mismatch and revised verification.

## Verification policy

Run when the desktop is idle; human-input harnesses flake under desktop use —
do not stress-repeat. A pass under load is not failure evidence; re-run once
idle before reporting.

- `deno task build:checks` — proves no compiled target references removed
  symbols (the live `.swift` check twins still compile).
- `deno task verify --filter swiftcore --verbose` — covers
  `AutomationPageChecks.swift` plus the `automation/*.swift` and
  `drawerpresentation/*.swift` lanes; proves the live automation suite is
  untouched.
- `deno task verify:qml --filter editorqml-drawer --verbose` — covers the
  production QML drawer (`AutomationPage.qml`, `AutomationPrompt.qml`,
  `AutomationMenu.qml`, `AutomationTabs.qml` inside `EditorDrawer`).
- `deno task format --check` — formatting gate.
- Grep predicates per task (in briefs) — the real proof, since deleted code
  was uncompiled.

## Tasks

| # | Task | Route + justification | Files |
|---|------|-----------------------|-------|
| 1 | Remove automation QSG paint path | SDD-track — multi-file deletion + edits to shared dead files (timelinequickview, timelinequickscene.{h,cpp}, TimelineCanvas.qml, DrawerChromeLayer.qml) need reference-tracing judgment; seat `sdd-implementer` | delete `automationquick.cpp`, `automationnodelanequick.{h,cpp}`; edit `automationcanvas.h`, `timelinequickview.{h,cpp}`, `timelinequickscene.{h,cpp}`, `TimelineCanvas.qml`, `DrawerChromeLayer.qml` |
| 2 | Remove AutomationCanvas family + dead check twins | SDD-track — ~50-file deletion surface with a live-twin exclusion predicate; seat `sdd-implementer` | delete `automationcanvas*` family (9 C++ files), `CcDeleteConfirm.qml`, listed dead check files; edit `automationpage.{h,cpp}`, `drawerchrome.{h,cpp}`, `drawersections.cpp`, `songview.cpp`, `editactions.cpp`, `editkeyrouting.cpp`, `timelinequickview.{h,cpp}`, `timelinequickview_window.cpp`, `cclanes.cpp`, `tempolane.cpp`, `nodelane/tempoadapter.cpp`, `nodelane/gesture.h`, `DrawerChromeLayer.qml`, `promptappearance.h` |
| 3 | Boundary-rule hygiene gate | Direct — grep predicates + formatter, fully reversible. Target: no file under `src/` (excluding `proof.*.txt` frozen logs) references `AutomationCanvas`, `automationquick`, `NodeLaneQuickPaint`, `CcDeleteConfirm`, `automationCanvas`, `automationBand`, or `Automation*` members of `TimelineQuickScene`. Change: fix violations by completing the removal, never by widening the rule. Acceptance: all greps empty + four-command pass. | (no brief; dispatch quotes this cell) |

Briefs: `task-1-brief.md`, `task-2-brief.md` (each cites the Verification
policy above and names only its task-specific grep predicates).

## Checkpoints

- Milestone A: after task 1 — paint path gone, `build:checks` green.
- Final handoff: after task 3 — four-command pass + boundary greps empty +
  `git status` shows only the listed write sets.
