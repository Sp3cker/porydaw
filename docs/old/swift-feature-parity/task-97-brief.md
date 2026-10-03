# Task 97 brief — roll band, modifier velocity and resize commit boundaries

# Context

Own roll pointer outcomes from provisional selection through release: band
preview/audition, pending draw readout, modifier velocity selection/toggle,
non-Scale move/nudge and grouped resize. Consume 93's painted-note contract;
this task is not custom cursor artwork or task 86's selected menu/pencil rows.

Verified selection: **35 open rows (20 GAP + 15 PARTIAL)**:

- `src/checks/rollcheck/proof.selection.txt`: 26 — A002, A003, A009, A014,
  A022, A024–A026, A028, A037, A039, A040, A044, A046, A049, A051,
  A057–A059, A061–A064, A070, A073, A074.
- `src/checks/rollcheck/proof.resize.txt`: 9 — A001, A007–A010, A016,
  A018, A020, A026.

Oracle: `fceecd88:src/checks/rollcheck/selection.cpp` and `resize.cpp`.
Current checks are `checkSelectionBandSweep`, `checkSelectionBandAudition`,
`checkGroupedVelocityDrag`, `checkThresholdDrawCell`,
`checkSelectionNonScaleMove` and `runResizeChecks`. Existing mounted journeys
in `tst_SwiftRollSelection.qml` and `tst_ShellGridInput.qml` already drive the
production pointer surface. The missing laws are individual outcomes, not a
reason to replace the gesture state machine.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift` — conditional pointer transition repair.
- `src/swift/app/roll/PianoGrid+Gestures.swift` — conditional gesture result repair.
- `src/swift/app/roll/GridScene+Notes.swift` — conditional provisional-ring/draw-preview repair.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — conditional existing pointer ingress repair.
- `src/checks/rollcheck/selection_band.swift`
- `src/checks/rollcheck/selection_audition.swift`
- `src/checks/rollcheck/selection_editing.swift`
- `src/checks/rollcheck/resize.swift`
- `src/checks/rollqml/tst_SwiftRollSelection.qml`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/rollcheck/proof.selection.txt` — selected 26 rows only.
- `src/checks/rollcheck/proof.resize.txt` — selected nine rows only.

No shared fixture/helper, router, ShellWindow, velocity-drawer or automation
owner edits. `selection.swift` and check registrations stay unchanged; extend
already registered functions. No checked-in MIDI or project-fixture changes.

# Prerequisites

Start after accepted Group A checkpoint. Rebase `GridScene+Notes.swift` and
`proof.resize.txt` over 93, `tst_ShellGridInput.qml` over 92,
`selection_editing.swift` and `EditorSurface.qml` over 86. Preserve 86's
press-focus fix. Reread 84's workspace/session restore, 87's keyboard pair
routing and 89's `DocumentSession.swift`; all four ongoing tasks must have
landed before this wave. Task 95 owns keyboard authority in Group B, not this
pointer ingress, and the write sets are disjoint.

# Interface contract

- Preserve `PianoGrid` pointer/right-pointer/command entry signatures, NoteID
  identity and the scene models. A swept note shows its provisional ring
  during right drag, but committed selection is unchanged until release.
  A zero-length note is not auditioned by the sweep.
- Pending draw-note rendering is unchanged by note-name mode. Undo/unwind
  restores exact MIDI bytes for the selected draw/readout journeys. Keep
  minimum-distance behavior and task 86's rows unchanged.
- Modifier velocity drag re-anchors to only its grabbed note where specified.
  A subsequent Ctrl+click still toggles; sub-threshold Ctrl jitter is still a
  toggle click. At the threshold, the drag has the specified anchor selection.
  A chord-held drag leaves the previously selected note's velocity unchanged.
- Repeating the grouped velocity drag restores each selected note's original
  velocity, with exactly one undo command for that repeated gesture. Preserve
  the existing grouped-selection semantics; do not collapse the anchor and
  other-note clauses into one message.
- A non-Scale move release and subsequent Right nudge each push exactly one
  command while retaining the same note identity, and unwind restores the
  original bytes. Grouped Ctrl+edge resize pushes exactly one command;
  a too-narrow note body presents the arrow rather than an edge grip.
- Retire only selection A014/A024/A028/A046/A051/A061–A064 and resize
  A001/A007–A010/A018/A026: deleted native free-cell/seed/fixture-add
  prerequisites. These are not new standalone fixture assertions. The
  remaining **19 behavioral rows** require executing predicates; the **16
  retirements** accompany those same mounted gesture journeys. Existing
  custom left/right cursor-image rows remain open, not silently retired.

# Implementation steps

1. Extend the registered selection/resize checks with one anchored predicate
   per selected behavioral clause: exact undo count/index, each note identity /
   velocity, pre-release selection, zero-length audition exclusion and byte
   restoration. Keep old messages and existing runtime fixture builders.
2. Extend `tst_SwiftRollSelection.qml`'s band preview and ShellGridInput's
   modifier/toggle/draw/resize journeys with actual pointer events. Observe
   the provisional ring and pending face while held, and the committed state
   after release; a presenter-only successful return is insufficient.
3. Repair only demonstrated owner defects and retain 93's raster behavior.
   **RED may be absent if production already matches; then the check is the
   deliverable.** Do not invent a second cancellation or keyboard dispatcher.
4. Update only the 35 selected rows, with fresh same-change evidence and the
   16 precisely bounded native fixture retirements.

# Acceptance predicate

Controller-run after Group B settles. `runSelectionChecks`/`runResizeChecks`
execute in `swiftcore-projectsession`; the selected roll QML suite proves
held-band rendering, and shell-grid-input proves the production shell ingress.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
PORYDAW_ROLL_QML_SUITE=tst_SwiftRollSelection.qml /usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Each process has the 175 s alarm and must finish within 180 s after serialized
lock acquisition. Require fresh `swiftcore-projectsession.json`,
`swiftroll-window.json` and `shell-grid-input.json` under `build/proof-evidence`.
Full shell runs all 26 lanes (~40 s warm), and full verify (~10 s warm) is
mandatory. Offscreen raster is not a physical custom-cursor screenshot.

# Task-specific constraints

Carry sprint-3 §10: no new C++; touched Swift uses Swift 6.4 idioms; comments
≤2 lines; base-font sizing; WCAG AA over pixel parity. One keyboard authority:
no second dispatcher, synthetic forwarding, focus memory or bare-Space chrome
capture. No `Qt.callLater` coalescing or new idempotence guards. One message
anchor per fork clause; preserve old messages verbatim; real fixtures and no
test-only seams. Settings setup uses CFPreferences/UserDefaults, never plist
bytes. Fixture-content edits require every exact-content consumer in an
approved expanded write set; none is authorized here. Workarounds need user
approval. Parked areas, deferred menus and savecore A016–A026 stay out.
