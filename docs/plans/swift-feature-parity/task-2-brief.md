# Existing ghost-note and selection rendering parity

Route: SDD-track, shared tree. Base `1096534c7d3e97c17a785625a93a215459c39d6e`.

## Surface and spec

Current roll scene. `src/checks/rollcheck/proof.note_rendering.txt` and `proof.keyboard.txt`, using their pinned original C++ checks, define other-track ghost visibility and time-selection highlights. New display modes landed at base and must be preserved. No newly designed UI or unrelated ledger reconciliation.

## Write set

- src/swift/app/roll/PianoGrid.swift
- src/swift/app/roll/GridScene.swift
- src/checks/rollcheck/note_rendering.swift
- src/checks/rollcheck/keyboard.swift
- src/checks/rollcheck/EditorGridCameraChecks.swift
- src/checks/editorqml/tst_ShellGridInput.qml

The first four form the cohesive projection/render/check unit; the last two are required consumers whose former primary-only assumptions must migrate with the projection contract. No production QML edits: use the existing ghost rendering pass. Other paths need controller approval; proofs exclusively belong to later ledger agent.

## Contract

Project required other-track notes through the existing scene authority. Ghosts remain noneditable/non-hit-test targets. Honor original range/scope highlighting while preserving primary track selection, note remaps, voice boundaries, clipping, folded rows and newly integrated velocity colors/note labels. Reuse existing selection and camera authorities; do not modify ruler APIs or add parallel model state. Avoid avoidable allocation/copying/rebuilds. Only cover edge behavior established by original checks.

Selection bridge ruling: the existing AutomationPage owns time selection. PianoGrid reads one provider; the ruler lane owns its ApplicationSession wiring and refresh hook. Do not add a snapshot fallback or test-only selection authority. Checks supply the same provider seam. This is required highlight integration, not a new UI feature.

Extend registered existing behavioral predicates to exercise projection, ghost edit exclusion and scoped highlight outcomes. Report exact A sites/S predicates. Native-only observations or unrelated missing behaviors remain GAP/PARTIAL; no weak equivalence claims.

## Acceptance and inspection

Controller: `deno task verify --filter swiftcore --verbose`; `deno task verify:qml-roll --verbose`; `deno task verify:shell --filter shell-grid-input --verbose`; production cocoa screenshot/interaction with both primary and ghost notes visible. Implementer supplies deterministic fixture coordinates/track choice for visual acceptance.

Shared builds/tests/formatters deferred to controller. Follow local inspection in `rule://sdd-execution-loop`: baseline/final file-local symbols and diagnostics where supported, complete changed boundaries, reference resolution before exported-signature changes, compare allowed versus actual scope changes. Report unavailable tools honestly. Return full result contract and final proof handoff; no commits or scratch reports. Sources freeze before ledger agent, then review complete code/check/proof unit.
