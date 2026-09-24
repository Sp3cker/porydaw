# rollcheck Swift migration — spec

Shared vocabulary and forward interfaces for
[plan.md](plan.md). The [Swift backend charter](../swift-backend-charter.md)
remains normative where it applies (especially S-1: never alter reference
expectations to conceal a port mismatch).

## Objective

Re-point every addressable original C++ piano-roll assertion recorded in
`src/checks/rollcheck/proof.*.txt` (including `static/`) at executing Swift
assertions, and record that coverage in the proof ledgers. Addressable today:
**979 of 1253 sites** (799 GAP + 180 PARTIAL). The remaining **274 NATIVE
sites stay NATIVE** (see Blockers).

## Proof vocabulary (existing corpus contract)

Each `proof.<stem>.txt` ledger audits one original C++ check source:

- **Site** `A###` — one original assertion anchor: an `A### | <original C++
  expression/context>` line followed by `Disposition:` and
  `Mapping`/`Mapping/reason` lines, plus verbatim source context.
- **Predicate** `S### | <swift function> | <path>:<line>` — one Swift
  assertion block quoted from the counterpart Swift check, with its
  `report.expect(..., cppID:, message:)` text.
- **Tally** — trailing per-file disposition counts; must reconcile with the
  site list (`deno task proof check` validates structure).
- Dispositions:
  - `MATCHED` — an equivalent Swift predicate exists **and** a Swift run
    executed it green. Must cite the `S###` predicate in the Mapping line.
  - `PARTIAL` — a related Swift predicate exists but carries an explicit
    unproved condition in `Mapping/reason`. Flipping to MATCHED requires
    discharging exactly that named condition.
  - `GAP` — no replacement Swift assertion.
  - `NATIVE` — retained native obligation (framebuffer grabs, native window,
    native fixture setup). Not addressable in this plan.

Tooling (implementer-local; scoped to `src/checks`, no shared build):
`deno task proof show|sites|list|search`, `deno task proof check`, and
`deno task proof:edit <path> <A###> --before ... --after ... --apply`
(a disposition change must also change that site's Mapping/Mapping-reason
line; entry IDs are preserved).

## Forward interfaces produced by this plan

### New Swift check stems

One new Swift file per audited C++ stem, in the same directory. The
authoritative list (counterpart naming is binding — do not deviate, and do
not rename existing files):

- `src/checks/rollcheck/pencil.swift`
- `src/checks/rollcheck/resize.swift`
- `src/checks/rollcheck/note_commands.swift`
- `src/checks/rollcheck/keyboard.swift`
- `src/checks/rollcheck/selection.swift`
- `src/checks/rollcheck/identity.swift`
- `src/checks/rollcheck/interlock.swift`
- `src/checks/rollcheck/remap.swift`
- `src/checks/rollcheck/presentation.swift`
- `src/checks/rollcheck/time_signature_prompt.swift`
- `src/checks/rollcheck/timemenu.swift`
- `src/checks/rollcheck/ruler_loop_menu.swift`
- `src/checks/rollcheck/scale_fold.swift`
- `src/checks/rollcheck/scale_editing.swift`
- `src/checks/rollcheck/note_rendering.swift`
- `src/checks/rollcheck/static/geometry.swift`
- `src/checks/rollcheck/static/gate.swift`

Existing files kept as-is: `velocity_prompt.swift`, `static/camera.swift`,
`EditorGridCameraChecks.swift` (extended, never renamed).

### Check function shape

```swift
@MainActor
func run<Stem>Checks(_ report: CheckReport, session: DocumentSession) { ... }
```

- Private `check<Scenario>` functions, one per original C++ scenario,
  preserving original fixture values, action sequence, and transaction
  boundaries.
- Assertion ids: `cppID: "swiftcore/<Owner>::<scenario>"` where `<Owner>`
  mirrors the original C++ test-class name recorded in the proof header
  (`Assertion correspondence:`), matching the existing
  `swiftcore/EditorGridCamera::*` convention.
- File layout per charter: public/entry declarations first, private helpers
  and bodies after.

### Registration (two integration points, no C++ permitted)

1. `src/checks/CMakeLists.txt` — append the stem to the `swift_core_check`
   target's Swift source list (beside `rollcheck/static/camera.swift`,
   `rollcheck/velocity_prompt.swift`, `rollcheck/EditorGridCameraChecks.swift`).
2. `src/checks/workspace/SessionChecks.swift` — call `run<Stem>Checks` from
   `runProjectSessionSuite` at the original C++ suite position (the order of
   the slots in the audited `tst_pianoroll*.h`), following the existing
   `runEditorCameraChecks` / `runEditorGridCameraChecks` calls (lines 11/45).

Because adding a suite slot or `PDC_SUITE_*` enum would be new C++, **every
new stem registers into the existing `projectSession` suite (10)**.

### QML surface (adapt only, never create)

- Check lane: `src/checks/rollqml/RollQmlTests.swift` plus existing
  `tst_SwiftRoll.qml`, `tst_SwiftRollAutomation.qml`, `tst_SwiftRollPlayhead.qml`,
  `tst_SwiftRollPlots.qml`, `tst_SwiftRollWindowing.qml`, `tst_TimelinePan.qml`.
- Production QML may be adapted only when a Swift backend requires it:
  `src/ui/songview/quick/PianoRollCanvas.qml`,
  `src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml`,
  `src/ui/songview/quick/swiftroll/TimelineQuickItem.qml`,
  `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml`,
  `src/ui/songview/quick/VelocityPrompt.qml`,
  `src/ui/songview/quick/TimeSignaturePrompt.qml`,
  `src/ui/songview/quick/InsertTimePrompt.qml`,
  `src/ui/songview/quick/QuickMenuPanel.qml`,
  `src/ui/songview/quick/RulerControls.qml`.

## Swift owner map (per inventory; read paths, not write licenses)

| Family | Swift owners | Existing checks | QML |
| --- | --- | --- | --- |
| Camera/viewport/scroll/zoom | `src/swift/app/timeline/EditorCamera.swift`, `GridGeometry.swift`, `src/swift/app/roll/PianoGrid.swift` | `static/camera.swift`, `EditorGridCameraChecks.swift` | `tst_TimelinePan.qml` |
| Pencil/velocity painting | `roll/GridGesture.swift`, `roll/PianoGrid.swift`, `src/swift/core/NoteEditing.swift` | `EditorGridCameraChecks.checkDrawLatchAndCancel` | `tst_SwiftRoll.qml` |
| Edge resize | `roll/GridGesture.swift`, `core/NoteEditing.swift` | `EditorGridCameraChecks.checkEdgeResize` | `tst_SwiftRoll.qml` |
| Note commands / keyboard | `roll/NoteCommands.swift`, `src/swift/app/commands/EditKeyArbiter.swift`, `src/swift/app/commands/EditCommands.swift`, `core/NoteMovement.swift` | `EditorGridCameraChecks.checkCommandRouting` | `tst_SwiftRoll.qml`, `swiftroll/SwiftRollOverlay.qml` |
| Selection/identity/interlock | `roll/GridGesture.swift`, `roll/PianoGrid.swift`, `DocumentSession.selectedNotes` | `EditorGridCameraChecks.checkOrderedSelection` | `tst_SwiftRoll.qml` |
| Remap/presentation/headers | `src/swift/app/headers/TrackHeaders.swift`, `src/swift/app/DocumentSession.swift` | `EditorGridCameraChecks.checkTrackOwnerRemap` | `tst_SwiftRollWindowing.qml` |
| Prompts & menus | `src/swift/app/drawer/velocity/VelocityPage.swift`, `drawer/PromptAppearance.swift`, `src/swift/core/TimeEditing.swift` | `rollcheck/velocity_prompt.swift` | production prompt QML above |
| Scale fold/editing | `roll/PianoGrid.swift`, `src/swift/core/NoteProjection.swift` | `static/camera.swift` (folded-projection S018/S019) | `tst_SwiftRoll.qml` |
| Note rendering | `roll/GridScene.swift`, `timeline/GridPalette.swift`, `timeline/GridTypography.swift` | — | `tst_SwiftRollPlots.qml` |
| Ready/gated transitions | gate slot model in `static/gate.cpp` audit | — | `tst_SwiftRollWindowing.qml` |

## Blockers — never flip these

1. `proof.header_reconciliation.txt` **A002, A006** — require the retired
   native `SongView`/`TrackHeaderModel` viewport; source deleted in `91cab247`.
2. `static/proof.gate.txt` **A076–A082** — ruler-tooltip floating hover/leave
   geometry; no existing rollqml QML mounts the popup and new QML files are
   prohibited.
3. All framebuffer-pixel / native-window NATIVE sites (the full 274 NATIVE
   population), e.g. `note_rendering` A017/A031–A033/A036,
   `scale_projection` A017–A030, `static/geometry` A001/A005–A008.

## Non-goals

- No C++ check retirement or deletion (later plan, after MATCHED evidence).
- No edits to C++ check sources, `harness.cpp`, `rollcheck.h`, or the
  `tst_pianoroll*.h` headers.
- No new lanes, suites, dispatchers, or proof-file formats.
