# Task 72 brief — keyboard-transpose audition (key-down start, autorepeat hold, physical key-up release)

# Context

Task 72 closes the drawer-transpose audition gap: editor-routed Up/Down on
selected notes auditions the transposed pitch on key-down, holds the preview
while autorepeat, and ends it on physical key-up. Swift today transposes
silently and has no key-release channel through the router at all.

1. **Census (verified this freeze)** — `awk -F'|' '/^A[0-9]+ \|/'` over the
   Disposition lines of `src/checks/selectionkey/proof.coreediting.txt`
   (Reference revision `c17d966f`, header counts MATCHED 9 / PARTIAL 9 /
   GAP 0 / RETIRED-REPRESENTATION 35):
   - Audition family `drawerTransposeAuditionReleasesOnPhysicalKeyUp`
     (A001–A008): A001/A002/A003/A005/A007 are RETIRED-REPRESENTATION
     (fixture-creation guard, Quick-window focus/input plumbing, native
     `deliverKeyEvent` delivery — the mounted lanes deliver real input).
   - **A004 / A006 / A008 are PARTIAL — this task's scope**: key-down starts
     one live audition (velocity > 0); autorepeat key-up must not end it;
     physical key-up ends it with one velocity-0 emission. Each PARTIAL
     reason names the existing observable (`PianoGrid.onAudition`, wired to
     the audio engine and asserted for pointer flavors by S046/S047 in
     `rollcheck/selection.swift`) and records the gap verbatim: the Swift
     app has no keyboard-transpose audition path.
   - The other 6 PARTIALs (range-boundary, paste-cursor, clipboard
     conjuncts) belong to tasks 58/69 territory, not this brief.
2. **Fork laws** (`git show fceecd88:<path>`):
   - `src/ui/songview/pianoroll_commands.cpp` `transposeSelection` — after
     `moveNotes`, calls `auditionKey(front.key + dKey, front.velocity)` and
     sets `m_auditioned = true`. The start pitch is the moved front note,
     the velocity is that note's own velocity.
   - `src/ui/songview/pianoroll_commands.cpp:73-92` — `keyRelease` never
     ends the audition itself ("ends through `finishKeyboardAudition()` on
     the shared release path"); `finishKeyboardAudition` stops only a live
     keyboard audition (`dragLive() || !m_auditioned` → false), else the
     release propagates normally.
   - `src/ui/songview/editkeyrouting.cpp:512-517` —
     `handleEditKeyRelease` ignores autorepeat releases
     (`input.autoRepeat` → false) and is key-agnostic: any physical release
     ends the latched audition via `m_roll->finishKeyboardAudition()`.
   - `src/ui/songview/quick/timelinequickview_keyrouting.cpp:38-41,174-179`
     — `dispatchSongKeyRelease`/`forwardUnhandledKeyRelease` give every
     attached input the same release policy, so the chord can come up over
     another band or the Quick root and still end the preview.
3. **Swift current state — the gap is structural, not a missing conjunct**:
   - `PianoGrid.performCommand` (`PianoGrid.swift:496-511`) handles the
     four transpose commands with document move + camera reveal only; no
     `onAudition` emission, no latch.
   - `stopAudition` (`PianoGrid.swift:998-1003`) is private with
     pointer-only callers (press/move/keyboard-pointer paths); the
     `keyboardAuditionKey/Track` latch exists but no key path sets it.
   - No release channel exists: `SongTabs.qml:49-55` has `Keys.onPressed`
     only; `ShellPresenter.routeEditorKey` (`ShellPresenter.swift:365-397`)
     is press-only; `ApplicationSession.routeGridKey`/`performGridCommand`
     take no release. Verified: no `releaseGridKey`/`releaseEditorKey`/
     `finishKeyboard` symbol in `src/swift/` or `src/ui/`.
   - Mounted nearby behavior: `tst_ShellWindow.qml` `test_m` already drives
     Up/Down/Shift+Up/Down transpose through real `keyClick` and asserts
     pitch outcomes — the audition journey extends that area.
4. **Overlap ruling**: task 65 (in flight) owns `ApplicationSession.swift`,
   `DocumentWorkspace.swift`, `ShellPresenter.swift`,
   `EditorViewStateCodec.swift`, `tst_ShellWindow.qml`, `tst_ShellTabs`.
   This brief touches `ShellPresenter.swift`, `ApplicationSession.swift`,
   and `tst_ShellWindow.qml` — **serialize after 65 lands**; rebase the
   write set onto its settled funnel before implementing.

# Exact write set

- `src/ui/songview/quick/swiftroll/SongTabs.qml` — add `Keys.onReleased`
  beside `Keys.onPressed`, calling the single release funnel (no key match,
  no focus memory; same `focusOwnsLocalKeys` guard as press).
- `src/swift/app/shell/ShellPresenter.swift` — add `releaseEditorKey(
  autoRepeat: Bool) -> Bool`: sceneActive + songOpen gate, autorepeat →
  false, else forward to the session release funnel; return whether a
  latched audition stopped.
- `src/swift/app/ApplicationSession.swift` — add `releaseGridKey(
  autoRepeat: Bool) -> Bool` funneling to the workspace grid's finisher
  (nil-workspace → false).
- `src/swift/app/roll/PianoGrid.swift` — start: in the
  `performCommand` transpose branch, after a successful edit, latch
  `keyboardAuditionKey/Track` to (edge pitch, selected track) and emit
  `onAudition?(track, edgePitch, frontVelocity)`; stop: add public
  `finishKeyboardTransposeAudition() -> Bool` (guard: latched pair present,
  else false) calling `stopAudition()`.
- `src/checks/rollcheck/selection.swift` — new `transposeAudition` block
  next to S046/S047 asserting the three predicates over `grid.onAudition`.
- `src/checks/editorqml/tst_ShellWindow.qml` — extend the `test_m`
  transpose area: Up key-down moves the note AND sounds it; physical
  key-up ends the preview (assert via the grid's published audition
  surface used by S046/S047, not a new seam).
- Ledger: `src/checks/selectionkey/proof.coreediting.txt` row flips only
  (controller-delegated ledger agent, this task's commit scope).

No new C++; no CMake; `DocumentWorkspace.swift`,
`EditorViewStateCodec.swift`, `EditorCommandRouter`,
`EditKeyArbiter`, `NoteCommands`, PreferencesStore untouched.

# Prerequisites

Task 65 landed (its `ShellPresenter`/`ApplicationSession`/`tst_ShellWindow`
edits settle first; this task rebases onto them). No other interface
consumed.

# Interface contract

- `PianoGrid.finishKeyboardTransposeAudition() -> Bool` — ends the latched
  transpose preview with the existing velocity-0 `onAudition` emission;
  true only when a latch was present. Pointer drags keep their own preview:
  the finisher touches only the `keyboardAuditionKey/Track` latch, never
  gesture state.
- `ApplicationSession.releaseGridKey(autoRepeat: Bool) -> Bool` — false
  when autorepeat or no workspace; else the grid finisher's result.
- `ShellPresenter.releaseEditorKey(autoRepeat: Bool) -> Bool` — false when
  the scene is inactive or the song closed; key-agnostic (mirrors the fork:
  any physical release ends the latched preview; the latch makes it safe).
- Transpose-start semantics: only a successful edit auditions (empty
  selection / clamped-at-0..127 no-op emits nothing — `performCommand`
  returns before the branch on `didEdit == false`); pitch = the moved
  selection's edge in the transpose direction (fork: front note + dKey);
  velocity = the moved front note's velocity (fork, not a constant).
  Autorepeat key-down re-executes transpose and re-emits (holds by
  re-latching); autorepeat key-up never releases.
- Message-anchored predicates (one per fork clause; `message:` strings are
  the ledger anchors and stay verbatim once written):
  - "transpose key-down auditions the transposed pitch above zero velocity"
    (A004).
  - "autorepeat key-up holds the transpose audition" (A006).
  - "physical key-up ends the transpose audition with a zero-velocity
    release" (A008).
- Preservation contract: `performCommand` document/camera behavior,
  `stopAudition` pointer paths, press routing, and every existing S-message
  in touched files stay verbatim (contingent edits only if a RED predicate
  exposes a real divergence — record RED→GREEN for that fix only).

# Implementation steps

1. `PianoGrid`: latch + emit in the transpose branch (edge pitch over
   `session.selectedNoteOrder` on `session.selectedTrack`, velocity from
   the moved front note); add the public finisher over `stopAudition`.
   RED first: existing transpose moves silently.
2. `ApplicationSession` + `ShellPresenter` release funnel + `SongTabs`
   `Keys.onReleased`. No keybinding match on release (key-agnostic per the
   fork); no second dispatcher — press routing is untouched.
3. Swift checks in `selection.swift` over `grid.onAudition`: down emits
   once above zero; autorepeat-up emits nothing further; physical-up emits
   exactly one zero-velocity release. RED first for each.
4. QML journey in `test_m`: real key delivery proving pitch move +
   preview start on down and preview end on up. Real fixture data; no
   synthetic forwarding.
5. Run the lanes below; hand predicate messages + file:line to the
   controller's ledger agent for the A004/A006/A008 flips.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — new transposeAudition
  predicates + regressions (evidence `build/proof-evidence/
  swiftcore-projectsession.json`).
- `deno task verify:shell --filter shellwindow --verbose` — extended
  `test_m` journey + regressions (evidence `build/proof-evidence/
  shellwindow.json`).
- `deno task verify:bridge`, `deno task format --check`.
- RED evidence for each of the three predicates before it passes.

# Task-specific constraints

- No new C++; no code comments; one message-anchored predicate per fork
  clause; real key delivery only — no second dispatcher, no synthetic
  forwarding, no focus memory (keyboard priority ruling). The release
  funnel carries only `autoRepeat`, never key identity.
- No test-only seams: checks observe the production `onAudition`
  callback; the QML journey uses the same published surface as S046/S047.
- WCAG AA beats parity; base-font sizing only; Atkinson Next 400/600 +
  Mono 400 unchanged; no new persisted settings (PreferencesStore ruling
  N/A — nothing here persists).
- Implementers never edit ledgers; the controller's ledger agent flips in
  the same commit: A004/A006/A008 → MATCHED to the new anchors (only with
  executed evidence for the exact clause, else the PARTIAL residue stays
  named). A001/A002/A003/A005/A007 stay RETIRED-REPRESENTATION. The ledger
  file stays (other PARTIALs open). No row is deleted here.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`, `deno task proof
   check --executed` (pre-flip state shows A004/A006/A008 PARTIAL with
   executing anchors), then `deno task proof sites --area selectionkey`
   confirms only those three rows moved.
2. Store-level smoke (headless, same lanes): no lane regresses against the
   pre-task run; pointer-audition journeys (S046/S047 owners) still green.
3. Confirm serialization: task-65 files (`DocumentWorkspace.swift`,
   `EditorViewStateCodec.swift`) show no diff from this task.
