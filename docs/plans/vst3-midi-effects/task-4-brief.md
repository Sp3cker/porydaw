# Context

Song playback must sound plugin output that the `.mid` never contains. Define the callback-side insert seam and sample-exact Sequencer dispatch, independent of the plugin host. Task 7 implements the insert; task 9 owns its lifetime. Read plan.md Global Constraints and spec.md "Live playback engine".

# Exact write set

- `src/swift/playback/live/LiveInsertSlot.swift` (new): slot, plain input/output events and per-call transport/discontinuity data
- `src/swift/playback/Sequencer.swift`: input windows, output dispatch and output-held ledger, `liveMask`, `TimelineSource.tick(for:)`
- `src/swift/app/audio/AudioRenderEngine.swift`: 16 atomic slots, `liveMask`, callback transport and discontinuity plumbing
- `src/swift/app/NativeAudio.swift`: `attachLiveInsert` / `detachLiveInsert`
- `src/checks/playback/LiveInsertChecks.swift` (new; `runLiveInsertChecks`, called from `runPlaybackSuite`)

Registration (controller): new playback source and check source entries; call the checks from `runPlaybackSuite` (`src/checks/support/corecheck/CoreCheckDispatch.swift` maps `swiftcore-playback` to that suite); no catalog change.

# Prerequisites

None (plan table Depends: —). Task 7 consumes the seam types; task 9 consumes the attach/detach API.

# Interface contract

- **Seam.** Follow spec.md "Live insert (audio callback)": `LiveInsertSlot` has an `@convention(c)` process pointer plus opaque context, with plain per-call data and no closures. `LiveInputEvent { sampleOffset, key, velocity, noteId }` and `LiveOutputEvent { sampleOffset, key, velocity, noteId }` use 1…127 velocity for on and 0 for off. Preallocate 4096 input and 4096 output events per chunk and count overflow. Keep host and SDK imports out of Playback.
- **Missed result.** The slot result includes `missed`. On `missed`, release that track's live-held output keys and flag input discontinuity on its next call; do not dispatch a late reply.
- **Render.** Before synthesis for each live-track chunk, gather exactly that track's notes in `[position, position + frames)` from the immutable timeline without allocating, call the slot, and feed returned notes into the existing `next` boundary split (`src/swift/playback/Sequencer.swift:576-637`). Split at loop end. Provide the actual transport, position, loop, timeline and flags, including seek, stop, wrap, timeline adoption, arm and pattern return; the insert's owner signals restore atomically. Call each attached insert while stopped with playing clear. No live preroll.
- **Dispatch.** Track the owning output `noteId` for each track/key. On a held key, release before a new on. Swallow an off if its ID is not the owner; a velocity-zero on is an off. Honor `muteMask`; `wrapNotes` releases live notes at loop end. Existing seek, mute and stop release paths also clear the corresponding live state. Add `TimelineSource.tick(for:)` beside `sample(for:)` so output clocks and `keyedOnTick` come from the actual sample.
- **Mask.** `liveMask` suppresses sequenced note-on and note-off dispatch and key-state updates for live tracks; CC, program, bend and tempo still pass. Keep it independent of `muteMask`.
- **Take feedback.** Use the optional C-convention take-sink function/context from the borrowed call record to report only actually dispatched live notes and segment boundaries into the insert-owned ring; no closure, allocation or waiting. Task 7 supplies the sink. Do not record swallowed or muted notes.
- **Engine and lifetime.** `AudioRenderEngine` owns 16 atomic slot pointers plus `liveMask`. `NativeAudio.attachLiveInsert(track:slot:)` and `detachLiveInsert(track:)` validate the track and run under `withRenderingStopped` (`src/swift/app/audio/AudioDevice.swift:88-103`); detach calls `m4a_engine_all_notes_off(main, track)` and clears that track's live key state in the same body, and attach starts clean. The owner reclaims slots only after detach. WAV export and the pattern player pass no inserts. Pattern audition owns the callback exclusively (`src/swift/app/audio/AudioRenderEngine.swift:416-421`); signal discontinuity on return.

# Implementation steps

1. Add the slot, event and per-call plain-data types; allocate event buffers outside the callback.
2. Extend `Sequencer` with input gathering, sample-boundary output dispatch, ID ownership, mask gating, wrap release, missed-result release and next-call discontinuity, and tick conversion.
3. Add engine slots, stopped calls, and per-call transport/discontinuity flags; preserve audition exclusivity.
4. Add attach/detach under `withRenderingStopped` with track note release and state clearing.
5. Add scripted fake-insert checks: a C-convention function and test context, no plugin or device. Assert exact input windows; exact output samples; mask suppression with CC/program/bend passing; same-key ID pairing and retrigger; velocity-zero on as off; wrap releases; seek/wrap/adoption flags; a fake slot returning `missed` releases only its track's live-held keys and flags the next call's input discontinuity; detach release and clean reattach; stopped transport; unchanged WAV export and pattern audition.

# Acceptance predicate

NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-playback`: scripted fake-insert checks above.
- `uv run --no-sync dev checks --filter swiftcore-playback-controller`: song render path.
- `uv run --no-sync dev checks --filter swiftcore-playback-audition`: pattern audition unchanged.
- `uv run --no-sync dev checks`: full run, including WAV export with Live on (song only).

# Task-specific constraints

- This alone edits `Sequencer` or `AudioRenderEngine`; `AudioDevice` is untouched. Porydaw's callback-side code allocates, locks and dispatches nothing; its only deliberate blocking call is the bounded bridge reply wait in task 7's slot.
- No host implementation, take storage, arming policy or UI here (tasks 7, 9).
- WAV export and pattern audition pass no inserts; preserve their behavior.
