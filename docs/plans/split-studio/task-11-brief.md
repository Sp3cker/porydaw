# Task 11 — Voicegroup-switch sync: dropdown guard, slot follow, switch-back

## Context

Eleventh task of the Split Studio plan; the first half of the former task
10, split at the session-lifecycle seam (R17): everything triggered by the
voicegroup dropdown. Producer consumed: task 10's `KitStudioWorkflow` +
`KitStudioCloseGuard` (checkpointed at M4 before this task starts — it
re-edits `KitStudioWorkflow.swift` and `SplitStudioWindow.qml`). Task 3's
`KitUsageScanner` is not used here. Key decision text: the
voicegroup-selection code checks `hasUnsavedChanges(song:)` and prompts
Save/Discard/Cancel BEFORE switching, and the check stays at the dropdown,
not inside Split Studio; after switching the window follows the same slot
number in the new voicegroup, reloads, and shows `Voicegroup changed to X`
with `Switch back to Y`; switch back is unguarded (R21 — the draft has
just reloaded). Today's switch path: `VoicegroupPanel.qml`
`onActivated`/`onAccepted` → `VoiceListController
.commitVoicegroupSelection` (`VoiceListController.swift:270-278`) →
`onVoicegroupChangeRequested` (wired in
`ApplicationSession+Audio.swift:95-103`).

## Exact write set

- Edit `src/swift/app/ApplicationSession.swift` (`hasUnsavedChanges(song:)`
  beside the registry)
- Edit `src/swift/app/ApplicationSession+Audio.swift`
  (`onVoicegroupChangeRequested` guard + post-switch follow)
- Edit `src/swift/app/kitstudio/KitStudioWorkflow.swift` (slot-follow
  reload, switch-back bar state, guard queries)
- Edit `src/ui/shell/kitstudio/SplitStudioWindow.qml` (switch-back bar)

No `VoicegroupPanel.qml` edit: the guard is session-side and the prompt is
shell-owned (the `SongConfirmDialog` parenting pattern,
`src/ui/songview/quick/docks/SongConfirmDialog.qml`).

Controller-owned: none (all files exist from tasks 9–10; no new lanes).

## Prerequisites

Task 10 (interface + accepted files, M4).

## Interface contract

`spec.md → PorydawApp (task 11)`:

```swift
extension ApplicationSession {
    /// True iff the Split Studio window holds unapplied changes for `song`.
    @QtIgnored public func hasUnsavedChanges(song: SongTabSession) -> Bool
}
```

- **Dropdown guard**: `onVoicegroupChangeRequested` intercepts the change
  when `hasUnsavedChanges(song:)`: a shell-owned prompt (the
  `SongConfirmDialog` component pattern, parented to the shell window)
  offers Save to Song / Discard / Cancel. Save runs the full save pipeline,
  then switches; Discard drops the draft (window stays open, reverts to
  the clean snapshot) then switches; Cancel restores the dropdown to the
  pre-edit arg via `VoiceListController.setCurrentVoicegroupArg(_:)`
  (`VoiceListController+Bank.swift:133`) without switching — the combo
  text and the bound bank revert to the pre-edit arg.
- **Post-switch follow**: after `selectVoicegroup` succeeds and the bank
  rebinds, the workflow reloads the same slot number in the new
  voicegroup; a non-kit or missing slot shows the picker's empty-slot
  state. The presenter shows the switch bar
  `Voicegroup changed to X` with `[Switch back to Y]`.
- **Switch back** (R21): the button calls
  `selectVoicegroup(previousArg)` directly — unguarded; the draft has just
  reloaded from the new voicegroup, so the dirty guard must not fire. If
  the switch fails asynchronously, the bar reverts to its previous text
  and a status line reports the failure; no prompt loop is possible.
- The guard decision stays at the dropdown handler — never inside
  `KitStudioPresenter` or the window.

## Implementation steps

1. Add `hasUnsavedChanges(song:)` (window open + dirty + bound-song match)
   to `ApplicationSession`.
2. Add the guard + prompt to the `onVoicegroupChangeRequested` handler;
   wire the three answers per the contract.
3. Add the post-switch follow and switch-back bar state to the workflow +
   window QML; reload goes through task 10's load closure with the new
   voicegroup's lease.
4. Verify the named lanes stay green; the added behaviors are
   temporary-smoke-verified (Acceptance names the gap).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks:shell --filter shell-split-studio`
  — must stay green: the guard runs only on the dropdown path, which the
  lane does not exercise.
- `uv run --no-sync dev checks --filter swiftcore-projectsession`
  — regression: the session's voicegroup-change routing is untouched for
  the unguarded path.
- `uv run --no-sync dev checks:shell --filter shell-voicegroup`
  — regression: the voicegroup panel's own flows (row derivation, selector
  semantics) unaffected.

Coverage gap (named): the guard prompt flows, slot-follow reload,
switch-back bar, and Cancel-restores-arg behavior have NO permanent rows
(decisions' budget); they are verified by the temporary controller smoke
below. A passing `shell-split-studio` run is not evidence for them.

Runtime prerequisites: none for the named checks; smoke needs a native
desktop session.

## Task-specific constraints

- Re-edits task 10's `KitStudioWorkflow.swift` and
  `SplitStudioWindow.qml` only — no other files, no new dependencies.
- The prompt is one shell-owned component instance; do not add a second
  prompt framework.
- Switch-back is unguarded by contract; do not route it through
  `hasUnsavedChanges`.

## Controller verification

1. `uv run --no-sync dev build:checks` then the three named lanes.
2. Temporary smoke (removed after), on the fixture project with a real
   desktop session: (a) dirty window + dropdown switch ⇒ prompt; each
   answer produces the decided outcome (Save: save-then-switch, draft
   clean; Discard: switch with clean snapshot; Cancel: combo text and bank
   revert, no switch); (b) clean window switch ⇒ silent follow +
   switch-back bar; (c) switch-back returns to the previous voicegroup
   with no prompt; (d) non-kit slot in the new voicegroup ⇒ empty-slot
   picker; (e) a failed switch (rename the target voicegroup file) reverts
   the bar with a status line.
3. `uv run --no-sync dev format --check` on changed lines.
