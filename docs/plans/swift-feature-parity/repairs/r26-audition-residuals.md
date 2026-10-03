# Context

R26: the qtbridge cleanup (`91727ce7`, brief 07) removed the unreachable ramp presentation path — confirmed landed: `AutomationRampHandle`, `syncRamps`, `automationRampItems()` and the `ramps` model/Repeater are deleted; `.ramp` math is retained (`AutomationParameter.swift:135-146,164-165,195`; `AutomationProjection.swift:300-306` segment kind; `AutomationDrawingTransactions.swift:108` live consumer). What remains is the residual assessment:

- **Hidden-tab lifetime — NO demonstrated risk.** `selectTab` → `deactivateSelection` → `DocumentWorkspace.deactivate` orders cancel(hidden) → gesture/audition teardown → detach → audio stop/unload → `onPlayback=nil`; `installPlaybackPublication` is `isActive`-guarded; teardown nils `grid.onAudition`. Hidden grid is unreachable by input. Recorded assessment only — do not nil `onAudition` in deactivate (unrequested hardening).
- **Repeated clipping — NO demonstrated risk.** `rebuildKeyboardText` runs only inside `rebuildStatic`, gated by `staticSceneDirty`/`staticInputsChanged`; per-pointer-sample path runs `rebuildNotes`/`rebuildHover` only; `syncText`/`sync` are equality-gated; clip math is O(visible). Recorded assessment only.
- **Band/keyboard audition projection — demonstrated defect.** `PianoGrid.stopAudition` (`src/swift/app/roll/PianoGrid.swift:885-889`) releases `keyboardAuditionKey` on the *current* `trackIndex`, but the press (~824-828) stores only the key, not the track. `trackIndex` is `@QtTracked` public and `refreshFromSession` (:198-204) silently rewrites it mid-hold (undo shrinking tracks, external selectedTrack change). Releasing after a track switch note-offs the wrong track → stuck preview note until engine stop. Reachable: hold gutter audition → switch track → release.

This task repairs the one demonstrated defect and records the two assessments. Read plan.md Global constraints and verification.md.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift`
- `src/checks/swiftbandkeys/tst_swiftbandkeys.swift` (or the existing roll-Swift check file that owns audition predicates — pick the registered file, do not create one)
- `src/checks/swiftbandkeys/proof.tst_swiftbandkeys.txt` — only the row(s) covering audition release; touch nothing else

If the audition predicate belongs in `note_rendering.swift` or another already-registered file instead, that file substitutes; ledger row goes in the matching proof file.

# Prerequisites

None beyond landed cleanup. `stopAudition`/`releaseBandAudition`/`auditionBandEntrants`/`cancelInput` symbols exist at the listed locations; `bandAuditioned`/`keyboardAuditionKey` fields at :55/:67.

# Interface contract

- `PianoGrid` stores the auditioned track alongside `keyboardAuditionKey` at press (e.g. a private `keyboardAuditionTrack`); `stopAudition` note-offs on the stored track; both fields clear together on release/cancel. `trackIndex` rewriting mid-hold must not redirect the release.
- Public/QML surface unchanged; `GridCancelReason`, `inputCancelled`, `cancelInput` semantics unchanged. Band audition (`auditionBandEntrants`/`releaseBandAudition`) already stores per-note track — untouched.
- New predicate: press audition on track A → session/document switches track → release → assert note-off targeted track A and no stuck audition on track B. Observable via `lastCancelReason`-style state or audition-slot emptiness on the engine-facing boundary (`grid.onAudition`/`NativeAudio.previewNote` interception — however existing check files observe audition).

# Implementation steps

1. Add the track pin at the keyboard-audition press site; release reads the stored track; clear both on `cancelInput`/`stopAudition`. Mirror the release path's existing key-release order.
2. Add the regression predicate in the owning registered check file: press → mutate `trackIndex` (or the document shape causing `refreshFromSession` to rewrite it) → release → assert the note-off went to the original track. Assert the pre-repair failure shape if feasible (wrong-track note-off) as the failing-before evidence; the controller confirms by running before the fix lands is NOT required — assert correct behavior and keep the predicate honest.
3. Ledger: the covering row in `proof.tst_swiftbandkeys.txt` (or the substitute file's ledger) cites the new executed predicate with a message anchor; unrelated rows (A105–A107 XButton-decline GAPs) untouched.

# Acceptance predicate

Track-pinned release is proven by an executed predicate; the two no-defect assessments are recorded in this brief's outcome (the commit message carries them — no ledger rows exist to update for them).

Controller-run named checks after the writer freezes:
- `deno task verify --verbose` — swiftbandkeys/roll Swift suites incl. the new predicate.
- `deno task verify:qml-roll --verbose` — roll regression incl. keyboard labels.
- `deno task proof check --executed` and `deno task proof check --strict-mappings`.

# Task-specific constraints

This runs after R23's `PianoGrid.swift` changes settle — rebase onto them. One defect, one fix: no listener bookkeeping, no tab-lifetime changes, no clip-path edits. Do not touch `GridScene.swift`, `SongTabsController.swift`, `DocumentWorkspace.swift` or `NativeAudio.swift`.
