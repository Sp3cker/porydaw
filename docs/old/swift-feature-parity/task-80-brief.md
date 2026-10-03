# Task 80 brief — velocity relative-drag latch and three-family transaction parity

# Context

Own the mounted Velocity drawer's relative drag: square, programmable wave and
noise must keep their press-time detent policy, preview without modifying the
song, and commit only the selected notes once. Existing family flows run, but
the ledger correctly withholds proof for missing per-family document, selection
and axis predicates. A policy-only wave fixture is not enough.

1. **Verified census: 20 PARTIAL behavior rows**, all in
   `src/checks/velocity/proof.velocitydetentdragging.txt`: A002, A003, A005,
   A006, A018, A019, A020, A023, A024, A025, A029, A032, A037, A038, A039,
   A045, A046, A048, A049, A062. Inspected with `deno task proof sites
   velocity/proof.velocitydetentdragging.txt --status PARTIAL` and its
   `--offset 20` page. No GAP rows are selected. A004/A009/A010/A012/A013
   are representation rows and remain untouched; do not expand this into
   the ramp or painting ledgers.
2. **Fork laws**, `git show fceecd88:src/checks/velocity/velocitydetentdragging.cpp`:
   - `:12-22,35-43`: square/wave/noise publish intrinsic axes and usable,
     checked detents. Different fixture program ordinals are not the law.
   - `:45-91`: origins are 33/87; unlock arrives only after the press. Preview
     stays snapped (square/noise 44/92, wave 64/127). The outside note has no
     preview; revision, undo depth, stored velocities, selection and playback
     remain frozen while held.
   - `:93-108`: release adds one revision/undo step, commits those exact
     values, keeps the outside note and selection, and clears previews.
   - `:123-141,149-189`: unlock present at press remains effective when absent
     on motion; a representable raw delta of seven yields 40/94 in every
     family. The axis remains intrinsic; it is the gesture's interpretation,
     not the displayed ruler, that unlocks.
3. **Current owner and mounted surface**:
   - `src/swift/app/drawer/velocity/VelocityInteraction.swift:38-114` captures
     unlock in `dispatchPointerPress`; `:119-156` consumes the frozen
     gesture on move. There is no move-time modifier argument, deliberately.
   - `src/ui/songview/quick/drawer/VelocityPage.qml:21-48` resolves the real
     document page and roll presenter. `src/swift/app/DocumentWorkspace.swift:
     116-118,226-228` mounts that same owner in the drawer.
   - `src/checks/velocity/VelocityPaintDetentChecks.swift:228-280` loads a
     real staged wave bank for program 6 and creates square/wave/noise page
     fixtures. `:281-322` asserts only wave axis availability explicitly,
     then checks released playback and publication counts. It does not read
     every family's held document values, undo depth or outside preview.
     `:324-359` exercises unlocked relative movement and 40/94, but similarly
     omits the selected rows' complete family-level predicates.
   - `src/checks/editorqml/tst_ShellDrawerParity.qml:69-74` already configures
     visible drawer pages in a real shell. Its registered lane is
     `ShellQmlTests.swift:95-96`; extend that fixture, not a fake VelocityPage.

# Exact write set

- `src/swift/app/drawer/velocity/VelocityInteraction.swift`
- `src/swift/app/drawer/velocity/VelocityTransactions.swift`
- `src/ui/songview/quick/drawer/VelocityPage.qml`
- `src/checks/velocity/VelocityPaintDetentChecks.swift`
- `src/checks/editorqml/tst_ShellDrawerParity.qml`
- `src/checks/velocity/proof.velocitydetentdragging.txt` — only the 20 selected rows and their predicates.

Production changes are limited to a demonstrated mismatch in this gesture's
capture, preview or commit; no change is required merely because a predicate
was missing. No hot file from sprint-3 §8 is owned. `tst_EditorDrawer.qml`,
`VelocityPageChecks.swift`, the shared document/session owners and task-78's
reserved files are outside the write set.

# Prerequisites

The split and ledger-path repair in sprint-3 §8 are settled. Existing loaded
bank, page and document history interfaces suffice. Group A: this task is
parallel with 79, 81 and 82 and consumes none of their new interfaces.

# Interface contract

- Preserve `dispatchPointerPress(x:y:surface:button:modifiers:) -> Bool`,
  `dispatchPointerMove(x:y:buttons:) -> Bool`, and
  `dispatchPointerRelease(x:y:button:) -> Bool`. Do not add a move-time
  modifier channel or change the intrinsic axis to emulate unlocking.
- The gesture freezes selected identities, origin values/maps and unlock at
  press. Preview owns only selected notes and never writes the document,
  history or session playback. Release commits one transaction; cancel does
  not. Test expectations are fixture literals, never copied from the preview.
- Add distinct literal message anchors for each row's clause:
  - A002/A045: detents available in each actual PSG family context.
  - A003/A046: intrinsic axis before the corresponding locked/raw drag.
  - A005/A048: enabled detent control and checked preference agree after
    enabling; observe the rendered control too, not a retired chrome widget.
  - A006/A049: enabled policy readback in every family.
  - A018/A062: outside note has no preview while locked/raw drag is held.
  - A019/A020: unchanged held revision and exact undo depth.
  - A023/A024/A025: unchanged held quiet/later/outside document velocities.
  - A029: exact captured selection while held.
  - A032: one released revision.
  - A037/A038/A039: exact released quiet/later/outside document values.
- Every applicable anchor runs for square, wave and noise; an assertion inside
  `if program == 6` cannot prove all three. Keep the existing playback reads
  and publication counts as independent consumers of the document changes.
- Existing messages stay verbatim, including “a late unlock keeps the gesture
  snapped to the level bands”, “an unlocked press keeps per-note offsets under
  a raw delta”, and “a released drag republishes the staged velocities into
  the timeline projection”. Do not convert `currentIdentity` inequality into
  a claim about undo depth: read `document.history.undoCount` directly.

# Implementation steps

1. **RED first:** extend `drawerVelocityProgramFlowChecks` at the existing
   held/released boundaries with the selected row predicates, before any
   production edits. Keep a full before-state including stored velocities,
   revision, undo depth and selected identities. Record already-green
   baseline clauses honestly; do not manufacture a failure.
2. Add mounted locked and unlocked drag cases to ShellDrawerParity using
   actual page delegates. Deliver unlock after the locked press, and release
   the modifier after the unlocked press. Observe drawn handle values,
   the unchanged roll notes while held, exact committed velocities and the
   unchanged outside note. Use the published axis/handle geometry rather
   than fixed pointer pixels.
3. If RED identifies a defect, fix the existing page/transaction owner or
   its real QML input boundary only. Preserve press-time latching, context
   resolution, pending selection and all paint/ramp behavior outside this
   relative-drag slice. Do not add callbacks just for observation.
4. Run the two covering lanes after writers settle. Map each selected clause
   to its own executed anchor; keep the family matrix visible in the checks
   and in the row's mapping, not merely in a test name.

# Acceptance predicate

Controller-run on the settled built tree; each command has a 180 s ceiling:

- `deno task verify --filter swiftcore-projectsession --verbose` — all three
  real family fixtures, document/undo/selection/preview/playback predicates;
  `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shell-drawer-parity --verbose` — mounted
  delegate input, detent control readback and late/early modifier journeys;
  `build/proof-evidence/shell-drawer-parity.json`.

`src/checks/workspace/SessionChecks.swift:82` registers the Swift family suite;
`src/checks/checkcatalog.cpp:107-125` names its runner. Shell registration is
`src/checks/editorqml/ShellQmlTests.swift:95-96`; evidence filenames follow
`tools/run_checks.ts:426-434`. Swift checks alone do not prove late physical
modifier delivery; the mounted journey is mandatory.

# Task-specific constraints

All **sprint-3 §8 Wave constraints** apply: Swift 6.4 idioms (borrowed spans,
InlineArray and ownership types where appropriate), strict concurrency and
typed throws, no hot-path temporaries, comments at most two lines, base-font
geometry and WCAG AA, existing keyboard priority/no bare Space, one clause
per message, real fixtures/no test seams, no `Qt.callLater` coalescing or
idempotence workaround, approval before workarounds, deferred menus and parked
areas unchanged. No new C++.

Do not substitute policy-only wave notes for the loaded wave fixture. Do not
broaden this task to detent painting/ramp, unsupported-context policy, bank
loading, or widget geometry. Preserve the full word-for-word existing messages.

# Controller verification

After fresh lane evidence, run `deno task proof check --executed`, followed by:

- `deno task proof sites --area velocity --status PARTIAL`
- `deno task proof sites --area velocity --status GAP`
- `deno task proof sites velocity/proof.velocitydetentdragging.txt --status PARTIAL`

Only the 20 selected rows are expected to become MATCHED. No representation row
changes and no ledger is deleted. A surviving missing family or missing held
boundary keeps its row PARTIAL; related square-only evidence cannot close it.
