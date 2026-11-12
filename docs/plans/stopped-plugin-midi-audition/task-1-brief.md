# Context

Implement [the stopped plugin MIDI audition spec and Global Constraints](plan.md). The host already processes Live inserts while stopped, but `Sequencer.prepareLive` zeroes their output count. Simply deleting that line is insufficient: dispatch currently schedules against advancing song position and publishes played-note capture. This task is the complete behavior change, consumed by the existing `AudioRenderEngine` callback and verified through native playback/check interfaces.

# Exact write set

Paths are relative to the VST worktree:

- `src/swift/playback/Sequencer.swift`
- `src/swift/app/audio/AudioRenderEngine.swift`
- `src/swift/playback/audition/AudioAudition.swift` — only if integrating existing audition ownership requires it.
- `src/swift/playback/audition/AudioAuditionVoices.swift` — only if integrating existing audition ownership requires it.
- `src/checks/playback/LiveInsertChecks.swift`
- `src/checks/pluginhost/PluginHostChecks.swift`

No new implementation files. All other files, including existing dirty files and this plan's documentation, are read-only. Escalate a necessary expansion before editing it.

# Prerequisites

None. Existing Live inserts, sample-offset output buffers, live held-note IDs, callback-owned audition voices, transport cleanup, and Darwin allocation checks are the production mechanisms to extend.

# Interface contract

Replace the public `Sequencer.processStoppedLive` method with:

```swift
public mutating func renderStoppedLive(
    engine: UnsafeMutablePointer<M4AEngine>, timeline: borrowing PlaybackTimeline,
    left: UnsafeMutableBufferPointer<Float>, right: UnsafeMutableBufferPointer<Float>,
    looping: Bool, muteMask: UInt32, liveMask: UInt32,
    liveSlots: UnsafeBufferPointer<UnsafeMutablePointer<LiveInsertSlot>?>,
    audition: AudioAudition? = nil
)
```

It renders the borrowed output spans, including engine release tails and existing auditions, with plugin events applied at their block-local sample offsets. Its output-span preconditions follow `Sequencer.render`; the caller supplies a callback-capacity-sized span. It never advances or temporarily changes the song's `position`, timeline cursor, pending song event schedule or musical time. It calls armed plugins with playing false and never supplies song notes. No stopped audition note enters the played take. All real playback input, dispatch, capture, discontinuity and timing behavior remains valid.

Migrate all consumers: the stopped branch of `AudioRenderEngine.render` and the two `PluginHostChecks.checkTakeEndpoints` call sites. Delete the old method, without a compatibility wrapper. `AudioRenderEngine` uses its current applied mute/solo mask and actual output buffers. Render the main engine once per audio span; do not run a second audition render over already rendered samples. The branch without an active timeline or armed insert retains its normal audition rendering.

Preserve all other exported declarations and signatures, native interfaces, `Sequencer` ownership scope, existing playing/render/pattern branches and normal auditions. Internal factoring of live dispatch and release is permitted. If audition ownership changes are necessary, keep them internal to the existing audition module; do not add another public audition interface.

# Implementation steps

1. Inspect complete affected methods and existing release/voice metadata before edits; resolve callers of the removed exported method. Factor one live note dispatch/ownership implementation usable with a playback position or a stopped block-local offset, rather than duplicating loops or inventing a persistent stopped-audition mode.
2. Implement stopped rendering at event boundaries using the existing engine/audition rendering. Preserve positive onset/zero-velocity-off handling, current note-owner identity, replacement releases, multiple tracks, mute/solo, and bounded missed-helper handling. Honor nonzero offsets across successive callbacks although song position is fixed.
3. Maintain transport/lifecycle cleanup and take semantics. Prior playing notes must close at their authoritative playback endpoint; newly auditioned stopped notes must not pollute capture, including on later play/resume/stop/seek/disarm. Old note-offs cannot release a new owner. Pattern audition stays exclusive and normal preview ownership remains independent.
4. Update the existing stopped-silence expectation in `checkLiveEngineLifetime` into audible stopped behavior. Extend the existing playback checks with deterministic coverage of nonzero sample offsets, note-off and repeated pitches, stationary stopped and paused position, mute/solo, transport transitions, missed reply and detach, pattern coexistence, and unchanged take content. Add only distinct consumer-visible invariants, not repetitive event matrices or incidental/source/SDK assertions.
5. Migrate `checkTakeEndpoints`, preserve its previous playback endpoint assertions, and extend the existing Darwin allocation measurement to exercise the warmed stopped render path with nonempty note output. Use a nonallocating producer for measured note dispatch; do not measure the existing recording fake that appends Swift arrays. Keep the existing real-helper allocation/processing checks. Do not claim SDK fixture output while stopped if that fixture intentionally produces none; actual Scaler verification owns that vendor behavior.

# Acceptance predicate

The stopped/paused path audibly synthesizes plugin MIDI at correct sample offsets with stationary song time, no song input and no audition take events; note ownership and all named cleanup/transitions remain correct; warmed stopped dispatch allocates zero host bytes under the existing Darwin logger.

The controller runs these NAMED CHECKS on frozen sources:

1. `uv run --no-sync dev build:checks` — compile application, changed playback and native harnesses.
2. `uv run --no-sync dev checks --filter swiftcore-playback --filter swiftcore-pluginhost --exclude swiftcore-playback-resonance --exclude swiftcore-playback-suppression-start-stop --exclude swiftcore-playback-suppression-replacement --exclude swiftcore-pluginhost-abi --exclude swiftcore-pluginhost-editor --no-windowing-checks --pool=3` — the registered playback, playback-controller, playback-audition and pluginhost harnesses, including stopped timing/cleanup and allocation checks.
3. `uv run --no-sync dev lsp:swift` — refresh the sourcekit index after settled Swift edits.
4. `uv run --no-sync dev format --check src/swift/playback/Sequencer.swift src/swift/app/audio/AudioRenderEngine.swift src/swift/playback/audition/AudioAudition.swift src/swift/playback/audition/AudioAuditionVoices.swift src/checks/playback/LiveInsertChecks.swift src/checks/pluginhost/PluginHostChecks.swift` — configured changed-line Swift formatting.

# Task-specific constraints

Ruling: the user selected `leave_app` in the native-test authorization form. Do not restart or drive their app. Finish automated verification and independent review only; the actual Scaler chord-click test is explicitly deferred and must be reported as unobserved. A future authorized manual check must use the built VST-worktree application, preserve unsaved song/plugin settings, and confirm stopped and paused chord audition with a stationary playhead. Never infer vendor MIDI emission from a fake or change plugin preferences/transport to hide a failure.
