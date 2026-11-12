# Stopped plugin MIDI audition

## Task

1. Implement stopped/paused plugin MIDI audition and its regression coverage. **SDD-track**, user-selected Claude Opus 5.5 implementation seat: real-time timing, voice ownership and transport transitions are coupled. One independently verifiable behavior justifies a write set larger than three files. See [task-1-brief.md](task-1-brief.md).

## Spec

With an effect Live-armed, MIDI notes returned by its plugin while the song is stopped or paused sound through that effect track's existing engine voice. Render returned events at their sample offsets; song sample position and musical time stay fixed, and the plugin continues to receive transport-playing false. Do not feed or chase song notes into the plugin while stopped.

Use the existing callback, live-note identity/release ownership, and engine audition rendering. A replaced same-pitch note cannot be released by an old owner's off. Muting/solo changes and lifecycle transitions release affected notes. Going between playing, paused, stopped, seeking, pattern audition, detach and replacement cannot leak or retain inappropriate voices. Pattern audition remains exclusive. Other keyboard/roll previews retain their existing lifetimes and sounds.

Stopped audition is not recording: its note ons/offs do not enter LiveTake or Effect Output, dirty the document, or create history. Preserve the final note-offs and endpoint of the preceding actual-playback take. Render/Grab played behavior otherwise stays unchanged. Scaler-specific audio output and stopped-time recording are non-goals.

## Global Constraints

- Work only in `/Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects` on the existing branch. BASE and CHECKPOINT are `290d15671db8d3e8f2e49d63ecc9579e1ea2d5a0`. Do not commit, push, merge, switch branches, or restart the user's running application.
- Existing dirty menu redesign, default-setting changes and their documentation/checks are locked prior work. Do not edit, revert, reformat or include them in this task's patch. This plan's new Markdown files are controller-owned.
- Swift owns behavior. No C/C++, SDK, native bridge/protocol, QML, module, build configuration, or persisted-format changes. No new public subsystem, event dispatcher, timer, processing thread or implicit state machine.
- Real-time implementation performs no avoidable allocation, buffer copying, heap-backed collection construction, string work, locks or control-thread dispatch. Borrow and reuse existing buffers. MainActor remains intent/control only.
- Reuse the existing live dispatch/release implementation rather than copying its MIDI ownership loop into a second stopped implementation. Keep sample offset within the audio block distinct from frozen song position; do not simulate playback or temporarily advance/restore song state.
- Keep declarations, scopes and non-task behavior intact. No file splitting for line-count compliance, shims, silent fallbacks, unrelated cleanup, SDK tests, or incidental-default/source-text tests.
- SHARED_TREE: implementer performs before/after read-only local inspection, but defers all builds, tests, index generation and format/lint commands to the controller. Report these as `DEFERRED_TO_CONTROLLER`, not passed. The controller reuses the exact brief commands on settled sources; reassess only for a concrete scope/command mismatch. Each command has a hard bound of at most 180 seconds.
- No proof ledgers exist in the two owned check directories, and the affected check IDs are `no-row/playback/live-insert` and `no-row/pluginhost/runtime`. If a covered ledger is discovered, freeze source work and report exact affected sites to the controller; do not edit proofs.

## Acceptance and checkpoint

The controller builds and runs the brief's focused checks after implementation, refreshes the Swift index, then obtains independent spec-compliance and code-quality verdicts over the complete feature patch. The same complete frozen package is the final feature acceptance surface; unrelated accepted VST work is not reopened. Fixes remain with the implementation owner. No Git checkpoint is authorized by this task.
