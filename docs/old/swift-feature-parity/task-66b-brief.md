# Task 66b brief — header→voice-picker + Add Track production mount

# Context

Task 66 closes everything in the trackheaders family except the header→voice-picker
journey: ~41 picker-journey rows in `proof.trackheadermutations.txt` keep their
dispositions with a named deferral, plus menu A035/A038 (change-voice opens the picker
after the menu closes) — **43 deferred rows** total. This task builds the deferred
mount and closes them. Fork oracle: `fceecd88`; pinned check sources at `f3069ef6`
(`git show f3069ef6:src/checks/trackheaders/<name>.cpp`).

1. **What is unwired (verified this freeze)**:
   - `TrackHeaders.activateAddTrack` sets `pendingVoice` (track −1) and fires
     `onAddTrackRequested` (`TrackHeaders.swift:283-288`), which `DocumentWorkspace`
     never wires — only `onChangeTrackVoiceRequested` is wired
     (`DocumentWorkspace.swift:123` → `ApplicationSession.changeTrackVoiceRequested`
     at `:566`, re-emitted at `:1099-1100`). No QML listens to that signal either,
     so both journeys end in the void. The only `completeTrackHeaderVoiceRequest`
     callers are checks (`tst_EditorDrawer.qml:2702`, `tst_SwiftRollWindowing.qml:284`).
   - The completion half already exists at presenter level:
     `completeTrackHeaderVoiceRequest(program:)` → `completeVoiceRequest`
     (`TrackHeaders.swift:374-389`) handles change-voice (track ≥ 0, `writeLane`)
     and add-track (track −1, `document.addTrack(voice:)` + select), with the
     pending-identity recheck (`PendingHeaderMenu.matches`, cancellation on
     negative program). Freeze must verify the `writeLane` change path is the
     behavioral equivalent of the fork's add/move-lane-point accept (below),
     especially the unchanged-accept no-op.
2. **Fork host contract — the spec** (`src/ui/songview.cpp:392-440`,
   `src/ui/songview/trackvoiceops.cpp:260-322`):
   - Single shared entry `requestVoicePicker(title, initialVoice, context,
     accepted, origin)`: snapshot staging gates (same quick view/session still
     current, document revision unchanged, no newer publication, session closed),
     replacement cancels the prior picker without focus restore.
   - Titles: `"Track %1 voice"` for change, `"New track voice"` for add.
     Initial voice: LAST change on the first change's tick (same-tick duplicates
     are last-wins, matching the header label); 0 when no changes; add-track is 0.
   - Accept routing: change → `addLanePoint` if no target else `moveLanePoints`
     only when `voice != initial`; add → recheck `canAddTrack`, `addTrack(voice)`,
     select the new track. Origin `TimelineBand::TrackHeaders`; focus returns to
     the header band on close/cancel.
   - Picker journey (`trackheadermutations.cpp:299-434`): open, search focus,
     filter, accept-disabled, audition payloads (program,key,velocity =
     127,60,112 hold / 127,60,0 release), dismiss/reopen, accept +1 revision
     +1 undo, rebuild sorted/unique, undo/redo, remap-phase teardown.
3. **Reuse targets (freeze re-snapshot; 60/62 own them)**:
   - Picker form: the fork form survives as `quick/VoicePickerPrompt.qml` (also
     mounted in the drawer at `VoiceChangesPage.qml:541`); `drawer/VoicePicker.qml`
     is the second form. Task 60 settles which form/model survives — 66b reuses
     the survivor wholesale, never a third picker implementation.
   - Audition observability precedent: `bootstrap.observeVoiceAudition` wraps the
     production `onAuditionVoice` closure (`VoiceChangesPage.swift:163-166`,
     `VoiceChangesInteraction.swift:223-233`, `tst_EditorDrawer.qml:4402-4425`).
     The roll lane mirrors this in its own bootstrap; no shared-test seam.
   - Mount pattern: presenter-flag-gated Loader with `Connections { target:
     applicationSession }`, per `EditorSurface.qml` (`timeSigMenuLoader:892`,
     focus-return bookkeeping `:132-178`).

# Exact write set

- `src/swift/app/DocumentWorkspace.swift` — wire `headers.onAddTrackRequested`
  to a new `addTrackVoiceRequested` callback alongside the existing change wiring.
- `src/swift/app/ApplicationSession.swift` — new `@QtSignal addTrackVoiceRequested`
  (parameterless) re-emitted from the workspace; a `headerVoicePickerOpen` flag
  (or reuse of one flag for both journeys) driving the QML Loader; route both
  journeys' completion through the existing `completeTrackHeaderVoiceRequest`.
- `src/swift/app/headers/TrackHeaders.swift` — **contingent only**: `pendingVoice`
  already covers both journeys; edit solely to expose the open flag or fix a
  divergence a new predicate exposes.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — presenter-flag-gated
  Loader mounting the task-60-settled picker form, origin header band, focus
  return to the band input on close/cancel.
- `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml` — **contingent only**:
  voice-cell double-click → `requestTrackVoice`, add-row → `activateAddTrack`;
  wire only what the fork input law requires and predicates prove missing.
- Checks: extend `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml` (mounted
  journey) + `src/checks/trackheaders/trackheadermutations.swift`-side presenter
  predicates; audition observation in the roll-lane bootstrap.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips only in `proof.trackheadermenu.txt` (A035/A038) and
  `proof.trackheadermutations.txt` (~41 picker rows); delete both files when closed.

No new C++; no CMake changes (no new files unless the flag needs a new source —
then amend the write set at freeze). NOT touched: `tst_EditorDrawer.qml`,
`VoiceChangesPage.qml`, drawer picker sources (60 owns), voicegroup QML/controllers
(62 owns), `ShellWindow.qml`/`ShellPresenter.swift`/`PianoGrid.swift` (54/58/65 own),
`SessionChecks.swift` dispatch (already reaches the suites).

# Prerequisites

Serial after **60** (settled picker form + model + audition precedent), **62**
(picker model/controller reuse target), and **66** (deferral evidence, stable
headers/menu surface) land. Re-snapshot every line reference and the surviving
picker form at freeze; 66b consumes 60/62's interfaces directly. Hot-file overlaps:
`EditorSurface.qml` (56 in flight, 66 in flight), `TrackHeaderBand.qml` +
`src/swift/app/headers/*` (66 in flight), `ApplicationSession.swift` +
`DocumentWorkspace.swift` (65 queued) — serialize, do not parallelize.

# Interface contract

New/changed anchors (verbatim once written; one per fork clause family); every
existing message in touched files stays verbatim.

- `addTrackVoiceRequested()` signal + `headerVoicePickerOpen` flag (or the single
  flag name freeze chooses): set on either request, cleared on
  completion/cancel/remap-teardown; the Loader's `active` binds to it.
- Mounted journey anchors in `tst_SwiftRollTrackHeaders.qml`:
  - "double-clicking a voice cell opens the Track N voice picker" — title
    "Track N voice", initial = last change on the first change's tick (seeded
    duplicate-tick fixture proves last-wins), search field focused.
  - "the add row opens the New track voice picker" — title "New track voice",
    initial 0; accept adds one track, selects it, +1 revision +1 undo.
  - "typing in the picker filters to matching voices" and "accept stays disabled
    with no selection".
  - "auditioning a row previews program/key/velocity and releases to silence" —
    hold (127,60,112), release (127,60,0) via the roll-lane audition observer.
  - "dismissing the picker writes nothing and reopens cleanly"; "accepting writes
    the voice, rebuilds sorted/unique, undo restores and redo re-applies".
  - "accepting the unchanged voice writes nothing" (fork `voice != initial` guard).
  - "a structural remap with the picker open tears it down and returns focus to
    the band" (presenter `pendingVoice` nil + flag cleared + band input focused).
  - "closing the picker returns focus to the header band" (both journeys).
  - Menu A035/A038: "Change voice closes the menu before the picker request,
    no revision change" — the existing five-actions anchor extended with the
    picker-open conjunct now that the request mounts.
- Presenter anchors (mutations swift): stale-request guards (completion after
  remap/document swap writes nothing), cancellation (-1 releases once).

# Implementation steps

1. After 60/62/66 land: re-snapshot the surviving picker form, its model owner,
   and the audition-observer shape; record the reuse mapping (form path, model
   accessor, observer hook) before editing.
2. Wire `DocumentWorkspace` add-track callback → new session signal + open flag;
   mount the Loader in `EditorSurface.qml` with band focus return; no band edits
   until a predicate proves one missing.
3. Add presenter predicates first (expected GREEN — completion exists; RED exposes
   a `writeLane`-vs-fork-accept divergence to fix in the contingent files), then
   the mounted journey functions reusing the file's lookup/wait helpers.
4. Run the lanes below; the evidence JSONs feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml-roll --verbose` — new picker/add-track journey predicates
  plus header regressions (`tst_SwiftRollTrackHeaders`, `tst_TimelineScrollbar`,
  `tst_TimelinePan`).
- `deno task verify --filter swiftcore-projectsession --verbose` — headers suites
  with the new stale/cancel/no-op predicates plus session-suite regressions.
- Runtime prerequisite: the roll lane's usual offscreen-capable Qt windowing;
  no native audio (audition observed, not heard).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants in production; Typography/LayoutSpace + Atkinson roles per
  binding rulings; WCAG AA beats parity.
- Real user path only: the Loader mount is the production picker both journeys
  complete through (`completeTrackHeaderVoiceRequest`); no test-only bridge seam.
  If the 60/62-settled picker model cannot be shared into the roll scene, the
  fallback is a headers-owned presenter over the same catalog with the affected
  rows left PARTIAL-mounted — decided at freeze, never silently.
- Implementers never edit ledgers. Mapping (agent; re-verify each row against the
  evidence JSONs and the fork sources at `f3069ef6`):
  - menu A035/A038 → picker-open-after-close anchor (MATCHED). Delete the file.
  - mutations ~41 picker rows (GAP A075/A098/A108/A117/A119/A128/A147/A152 +
    the 33 PARTIAL journey rows; enumerate at freeze) → journey anchors above
    (MATCHED). Delete the file. Do not weaken spec text; no picker-window
    conjunct closes on presenter-only evidence.
- RETIRED-REPRESENTATION only for rows pinning C++/QWidget internals,
  fork-verified at the ledger's Reference revision; setup guards with
  `report.fail` may cite that predicate. Keyboard priority: no second
  dispatcher, synthetic forwarding, or focus memory — the band input is the
  single focus owner the picker returns to.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check --executed`
   (pre-deletion state shows menu/mutations fully closed with executing anchors),
   then `deno task proof sites --area trackheaders` confirms both deletions and
   zero survivors — the family is gone (fork C++ sources already deleted per
   task-66), so this is the trackheaders deletion certificate.
2. Visual smoke (desktop): double-click a voice cell — "Track N voice" picker
   with the current voice initialed and search focused; type to filter, audition
   a row, accept — label updates, undo restores; Escape — nothing written, focus
   back in the band; trigger the add row — "New track voice", accept adds and
   selects; right-click → Change voice — menu closes first, then the picker.
