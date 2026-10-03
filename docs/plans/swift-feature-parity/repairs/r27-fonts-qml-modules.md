# Context

R27 remaining obligations after task 10 (linking accepted): zero-pixel font warnings, missing fonts, QTP0004 module coverage, and usable qmllint/QMLLS imports. Confirmed root cause for the zero-size warnings: `TrackHeaders.refreshFromDocument` (`src/swift/app/headers/TrackHeaders.swift:176`) appends the add-track `TrackHeaderSnapshot` whose `titleFont`/`subtitleFont` keep `TrackHeadersGeometry.swift:33-34` struct defaults (family `""`, pixelSize 0); `makeSnapshot` (:227-236) assigns real fonts only to normal rows; `TrackHeaderBand.qml` (:303-314, :323-332) constructs hidden `Text` items whose `Qt.font(trackHeaderRow.titleFont)` evaluates the zero map at add-track time. Missing faces: Atkinson Hyperlegible Next Bold/700 (EngineSettingsPage/SongSettingsPage `Font.Bold` requests) and Mono Semibold/600 (GridTypography bold ruler faces) — only Regular/SemiBold-600 Next and Mono-Regular ship in `resources/`; `editor_qml_tests` links no `fonts.qrc` (roll/shell/`porydaw_checks` do) and no editor-lane bootstrap calls `addApplicationFont`. QTP0004: every `src/ui` QML is in `Porydaw.Ui` except `src/ui/shell/PorydawApplication.qml` (loaded by URL) and the 33 `tst_*.qml`/`DrawerTestPage.qml`/`BridgeProbe.qml` check inputs (loaded by input-dir URL); `import PorydawApp` has no qmldir/qmltypes artifact (QtBridge runtime registration). No qmllint/QMLLS config exists anywhere. Read plan.md Global constraints and task-10 brief for the accepted link work.

# Exact write set

- `src/swift/app/headers/TrackHeadersGeometry.swift`
- `src/swift/app/headers/TrackHeaders.swift`
- `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml`
- `src/checks/CMakeLists.txt`
- `src/checks/support/checkstartup.cpp`

`CMakeLists.txt` (root) only if the QTP0004 scope decision adds `PorydawApplication.qml` to a module target — prefer recording scope, not restructuring the entry-point load path.

# Prerequisites

R17 must have landed first — it also edits `src/checks/CMakeLists.txt` and the roll lane. Task 10's link work is accepted. The controller will capture the actual warning text at build/lane time before dispatch proceeds past step 1's isolation — the implementer does not build.

# Interface contract

- The add-track snapshot carries real font maps: either the same normal-title/subtitle fonts as data rows, or a dedicated add-row font — never `{family:"", pixelSize:0}`. Hidden delegate `Text` items must evaluate a valid font. Decide by the cheaper honest fix: assigning the model's `normalTitleFont`/`subtitleFont` to the add-track row costs nothing and keeps one font path.
- `editor_qml_tests` resolves bundled faces the same way sibling lanes do: link `resources/fonts.qrc` into the lane target and (matching `checkstartup.cpp`'s `:/fonts` bootstrap) register the faces, so VoicePicker's hardcoded Next family and applicationFont users resolve in the editor lane.
- Warning-absence is the evidence: the roll lane asserts the add-track row's font maps are non-zero and (where the harness can observe it) that no `pixelSize <= 0` font warning is emitted; the editor lane resolves Next/Mono like the others.
- QTP0004 + lint imports: produce the decision, not churn — `PorydawApplication.qml` and check inputs are legitimately outside a `QML_FILES` module (URL-loaded); record that classification. If a minimal config (e.g. a checked-in qmllint/qmlls import-path file pointing at the build-tree `Porydaw/Ui` module) makes editor linting usable without restructuring, add it; if `PorydawApp` has no resolvable artifact, document it as a known runtime-registration limit rather than fabricating a module.

# Implementation steps

1. Give the add-track snapshot real fonts (model `normalTitleFont`/`subtitleFont`); confirm by source-level read that no other `TrackHeaderSnapshot` path can still emit a zero map.
2. Extend `tst_SwiftRollTrackHeaders.qml` with an add-track-row case asserting non-zero pixelSize/family on its title/subtitle font maps — the warning-absence proxy the lane can observe.
3. Link `fonts.qrc` into `editor_qml_tests` in `src/checks/CMakeLists.txt` and register faces in `checkstartup.cpp` if the bootstrap is shared — mirror exactly what the roll/shell lane targets do.
4. For QTP0004/lint: inspect the actual build output the controller captures. Add only the minimal module-membership or config change the diagnostics support; if `import PorydawApp` is unresolvable to qmllint because QtBridge registers types at runtime, record that in the brief outcome — no fake module, no qmldir stub.
5. Missing fonts: do NOT add font binaries in this task (bundling is a product decision — ship-vs-synthesize is the user's call). The repair is making every *lane* resolve the shipped faces; the Bold/700-vs-SemiBold/600 and Mono-600 gaps get recorded as remaining obligations in the outcome.

# Acceptance predicate

The roll lane asserts valid add-track font maps; the editor lane resolves bundled faces; the zero-pixel warnings' source path is closed; QTP0004/lint obligations are either resolved by minimal config or recorded as classified limits with the captured diagnostic.

Controller-run named checks after the writer freezes:
- `deno task build:checks` — capture warning text (QTP0004, font warnings) before/after.
- `deno task verify:qml-roll --verbose` — add-track row + header regression.
- `deno task verify:qml --verbose` — editor lane font resolution regression.
- `deno task verify:shell --verbose` — ShellWindow FontLoader surface regression.
- `deno task verify --verbose` — native runner regression.

# Task-specific constraints

Do not add font files or change visual font choices (Bold→SemiBold downgrades are product decisions). Do not create a QML module for check inputs merely to silence QTP0004. `resources/fonts.qrc` edits only if linking requires it. Runs after R17 lands (shared `src/checks/CMakeLists.txt`).
