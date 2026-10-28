# Context
Add sample-accurate solo looping preview of an immutable generated timeline without replacing the song timeline. Presenter consumes the interface in plan.md; no UI or generator dependencies. Read plan.md Global Constraints and audio interface first.

# Exact write set
- src/swift/app/audio/AudioRenderEngine.swift
- src/swift/app/NativeAudio.swift
- src/swift/app/audio/AudioTransport.swift (cold immediate-pause seam only)

# Prerequisites
None; consumes existing PlaybackTimeline/Sequencer/AudioDevice and voicegroup lease patterns.

# Interface contract
NativeAudio.startPatternAudition(_ timeline: PlaybackTimeline), stopPatternAudition(), patternAuditionPositionSamples: UInt64. Start replaces an existing pattern, pauses normal song playback, retains song timeline/playhead, and auditions only the pattern on the existing preview engine. Stop silences pattern notes and leaves song paused; subsequent normal playback uses the original song timeline. Normal play/stop, bind/unload, voicegroup and config changes stop pattern audition. Renderer timeline/sequence mutations use existing AudioDevice.withRenderingStopped cold seam, never race the callback. Position getter uses atomic telemetry, not a shared unsynchronized mutable Sequencer field.

Add internal cold `AudioTransport.pauseImmediately()` to clear a pending seek/cut and set requested/applied to paused while retaining sequencer position. Renderer calls only while device rendering is stopped. Preserve normal transition/fade behavior everywhere else.

# Implementation steps
1. Inspect AudioDevice, renderer, Sequencer loop behavior, AudioTransport and AudioAudition ownership/cut semantics. Resolve exported symbol references via LSP before modifying existing signatures (none expected).
2. Add separate preview-pattern sequencer/timeline cold ownership to renderer, with accurate loop restart and position telemetry. Render overrides song audio during pattern audition, uses already allocated output buffers, no realtime allocations/locks/ARC destruction. Preserve existing ordinary previewNote/sample/wave paths when no pattern is active.
3. Expose NativeAudio cold start/stop/getter and stop on relevant existing owner transitions without introducing synthetic dispatchers or timer MIDI scheduling.
4. Perform file-local diagnostic/symbol inspection; report any unverified threading or lifecycle assumptions explicitly.

# Acceptance predicate
Pattern loops sample-accurately and alone; replacing/stopping/bank unload releases held notes, does not overwrite the song timeline or mutate a document, and normal playback remains usable afterward. NAMED CHECKS: controller `uv run --no-sync dev build:checks`, focused new arpeggiator renderer checks where possible, and actual production tool audition/stop smoke.

# Task-specific constraints
SHARED_TREE: do not run builds/tests/formatters/linters; report DEFERRED_TO_CONTROLLER. No commits, new C/C++, new third-party dependencies or edits to checks/proofs. Add no avoidable allocation or synchronization to the realtime callback. Existing song, sample, voice and band audition contracts must remain unchanged. Read rule://swift-standards and swift-typecheck-complexity.
