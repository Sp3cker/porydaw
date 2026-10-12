# Right-drag chord audition

## Contract

Every eligible note entering the right-drag band captures its document track, pitch, velocity, and duration through the current tempo map, including distinct NoteIDs at identical track/pitch. Each occurrence releases after its own rendered sample duration; zero-sample spans stay silent. Unchanged identities do not reattack or extend/change their captured note. Departure, cancellation, demotion, hiding, and detach can release it earlier. Reentry creates a fresh full-duration occurrence even before the prior entrance reaches the callback. Normal instrument release tails remain.

Preserve selection, MIDI bytes, revision/history, combined-button gestures, native allocation/priorities/limits/portamento/debug rendering, mono retriggers, timed expiry, and isolated voice/sample preview. Never resurrect stolen/completed/cut voices. No extra engine, pitch deduplication, velocity aggregation, arbitrary band cap, callback allocation/deallocation/locking/logging, or unrelated timed/mono changes.

## Ownership

- `PorydawPlayback` owns `Sequencer`, `PlaybackBridge`, and `audition/{AudioAudition,AudioBandAudition,AudioAuditionVoices,AudioSampleAudition}.swift`. `PorydawAppAudio` retains engine ownership, callback composition, transport/fades, device lifecycle, mixing/output, timeline handoff, telemetry, suppression and WAV export.
- `BandAuditionNote` is immutable: `noteID/durationSamples: UInt64`, `track/key/velocity: UInt8`; duration is required.
- `PianoGrid.onBandAudition` forwards through `NativeAudio.updateBandAudition` to `AudioAudition.updateBandAudition` only while its workspace owns the shared engine. Deactivation releases the outgoing band before removing the callback; inactive teardown cannot clear the survivor's band. `onAudition` remains the mono path.
- `AudioBandAudition` owns membership and immutable `Sendable` batches, with two inline commands and array overflow read through `Span`. Typed `AtomicLazyReference` links publish batches; the producer retains a head and prunes only nodes strictly behind the acquired acknowledgement. The callback captures one finite cutoff; destruction requires a parked callback. Allocation and reclamation belong to the producer.
- `AudioAuditionVoices` owns source/serial identities and rendered-sample budgets for the existing 57 primary/shadow/audition PCM+CGB slots. Original native note-on, priorities, stealing, portamento and DSP remain authoritative. Host rendering splits at expiry and requests normal release; every positive band duration, including `UInt64.max`, is finite.
- The UI gathers coverage into retained scratch storage using one viewport-camera overlap predicate for selection and audition. Release recomputes coverage from its own coordinates. Captured metadata, zero-duration filtering and tempo-map sample integration are unchanged.
- Checks reuse the existing native-owned PCM/CGB banks in `AuditionCheckEngines` through `SwiftCoreCheckLogic`; no second engine/bank fixture or callback-history oracle.

## Native engine

The native extension was withdrawn. `external/poryaaaa` remains pinned to the unchanged `c504afebe5c56cf9393e6ae632b9cef632480ab6`; no native source patches or replacement owned-note APIs are required.

The read-only ownership projection is coupled to this allocator, including its distinct wrapper track-priority and driver player-plus-track-priority decisions. It observes rather than selects allocation and does not mutate emulated fields as tags. Dependency updates require rechecking accepted/rejected slots, identical pre-DSP starts, portamento and shadow-copy ownership.

Ordinary interactive sequencer ingress/off and idle DSP share the host ledger. Without an interactive context, offline sequencing retains the original native path. Debug configuration applies before queued audition commands: the native invert setter resets sidecars and would otherwise silence a new entrance in the same callback.

`Sequencer.releaseSequencedNote` owns the interactive-ledger/native note-off choice for pending releases, loop wraps and MIDI note-off events. The producer command builder is local to each coverage update, not persistent state. Live rendering retains metronome mixing after the main engine and preserves mono velocity-drag replay independently of band membership.

## Scope and isolation

The cleaned `feature/right-drag-chords` worktree, originally based on `c33a17a5f6bd5ac6f557d58fc95d1956a0ad7d42`, is integrated into `fork-main` without importing the allocation-recording commits.

Allocation recorders, allocation/CPU benchmark runners, profiling fixtures, opt-in suite registrations and their command entries are removed. Chord delivery, source identity/lifetime management and behavioral audio/roll checks remain. The experimental worktree-local native-source resolver is reverted; builds use the original canonical dependency resolver.

Payload transition checks retain counts 1, 2 and 3: inline, full-inline and first overflow. Redundant counts 8 and 9 are removed. The focused audition suite and scoped Swift formatting passed after this reduction.

## Verification

Historical feature verification recorded passing native audition/controller, sequencing, project-session, sample-editor and production `tst_SwiftRollSelection.qml` checks. Native checks cover exact velocities, independent same-pitch occurrences, sample deadlines at frames 1025/2051, normal release tails, no extension/resurrection, fresh reentry, source isolation, stealing/shadow ownership, cut/reset/defer, and native PCM/CGB waveform equivalence. The production grid checks cover tempo-map durations, pointer cancellation and unchanged history/MIDI bytes. These observations are not speaker-listening or ROM differential-fidelity claims.

Covering commands on `fork-main`:

```sh
uv run --no-sync dev build:checks
uv run --no-sync dev checks:run build/debug/porydaw_checks --filter swiftcore-playback --filter swiftcore-projectsession --filter samplecheck-editor
PORYDAW_ROLL_QML_SUITE=tst_SwiftRollSelection.qml uv run --no-sync dev checks:qml-roll --filter swiftroll-window
uv run --no-sync dev checks:bridge
uv run --no-sync dev format --check --base HEAD
```

Integration verification on 2026-10-12: the app/check build passed; all 8 selected native suites and the production roll lane passed; the bridge guard reported zero baselined findings; formatting passed. The existing workspace check now proves that inactive teardown preserves the survivor's native band voice and that its own cancellation releases it; the preservation assertion failed before the callback-lifecycle fix and passed afterward. The merged executable launched and its loaded production window was captured. Existing Qt header-import and missing-font warnings remain.

No proof ledgers cover these checks; no new parity claim is made. Swift indexing completed for all 23 targets; declaration inspection and compilation cover the merged structure. Semantic LSP reference queries were unavailable.
