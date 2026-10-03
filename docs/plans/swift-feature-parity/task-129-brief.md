# Task 129 brief — live timeline edits and transport changes preserve actual audio progress

# Context

Complete the existing selected-workspace audio surface: note edit/move/Undo during playback, independent audition, pause stability and settings replacement. The production NativeAudio already exposes the real renderer's timeline, sample counter and settings. Use that seam, not a fake transport or a new diagnostic property.

Verified planning selection: **20 open rows (16 GAP + 4 PARTIAL)** from sprint-3 §14.

- `src/checks/workspace/proof.selftest_timeline.txt` — A005, A006, A007, A009, A010, A011, A013, A014, A015, A016, A017, A020, A021.
- `src/checks/workspace/proof.selftest_transport.txt` — A005, A007, A008, A011, A015, A019, A020.

Oracle: `fceecd88`; source pins respectively `85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`, `c1f165eb1aa49af49c72a3e4f15cf6d9f23b6735`. Transport A009/A010/A013 remain untouched: their ledger records the user's 2026-09-26 cursor-never-seeks decision.

# Exact write set

- `src/swift/app/NativeAudio.swift`
- `src/swift/app/audio/AudioRenderEngine.swift`
- `src/swift/app/audio/AudioTimelineHandoff.swift`
- `src/swift/app/audio/AudioTransport.swift`
- `src/swift/app/ApplicationSession+Audio.swift`
- `src/swift/app/timeline/SharedPlayhead.swift`
- `src/swift/app/transport/TransportBarPresenter.swift`
- `src/checks/workspace/session_playback.swift`
- `src/checks/workspace/transport_checks.swift`
- `src/checks/editorqml/tst_ShellTransportSession.qml`
- The two selected proof files, owned only by the separate ledger writer.

Closed list. Only selftest_timeline is a conditional whole-ledger closure. Keep selftest_transport and its three decision-related PARTIAL rows. No C++ production deletion follows yet: miditimeline.cpp/h and songdocument_tempo.cpp retain host/automation/geometry blockers; timelineplayer.cpp/h retain host, routing-state and transport blockers.

# Prerequisites

The existing selected-workspace publication and split audio extension. Independent of 118/119; their main ApplicationSession, DocumentWorkspace, DocumentSession and tab-state files are read-only. Preserve the current cursor-never-seeks behavior throughout.

# Interface contract

- Use a real initialized ApplicationSession/NativeAudio and copied project fixture. While Playing, add the fork note at tick 0/key 60, move it to tick 24/key 61, then Undo to the original clean document. At each operation the real audio timeline contains the independently expected changed/restored event schedule, agrees with the selected document's published timeline, remains Playing, and advances strictly beyond the sample captured before that operation. Pointer inequality of old C++ timeline objects is representation; semantic timeline replacement is not.
- Prove dirty state and exact note location after edit/move; full MIDI bytes and history return after Undo. Audition through the existing voice control while Playing must not pause/restart the song and its sample counter continues. Audition while Stopped leaves transport Stopped. Stop and close the final tab through real controls; no tab remains and the stopped engine does not retain an advancing retired song.
- Transport A005 compares all changed PCM mixer/max-channel/mix-rate/filter settings on the real engine, concurrently with Playing and strictly increased sample count. Preserve the current control-thread parking/handoff design; no new thread or rendering callback allocation.
- A007 samples a stable paused playhead for the original 100 ms interval. A008 compares the presented paused tick to timeline.tick(forSample:) within 0.25 tick. A011 captures immediately before Resume and requires a strict sample increase beyond that captured value, not merely beyond an older edit cursor. A015 requires progress of at least sampleRate * 0.25 samples beyond the actual Play start target.
- Pair registered full-state/audio observations with mounted toolbar, roll-edit, audition and final-tab-close input. Do not replace a real pointer/key event by calling a presenter solely to satisfy a GUI row. Never restore the fork's superseded cursor-seek behavior to obtain a passing transport row.

# Implementation steps

1. Extend the existing session playback/transport entrypoints with real-audio timeline replacement, settings, paused-window and exact progress predicates; restore fixture/preferences and callbacks after each scenario.
2. Extend the split shell-transport-session journey with actual edit/Undo, audition and close input at the same observable boundaries.
3. Repair only demonstrated audio handoff/presentation defects in the listed owners, preserving current cursor/toolbar semantics and native runtime failure reporting.
4. Give the separate ledger writer the selected executed clauses; delete only the completed timeline ledger and leave the excluded transport decisions unchanged.

# Acceptance predicate

The real device/renderer advances through edit/settings/audition transitions, stays stable while paused, and stops on final close. Both exact sample thresholds and mounted control consequences execute; a Null or unavailable backend cannot silently stand in for claimed physical-device behavior.

The implementer runs, with the lane's normal audio runtime available:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport-session --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No reserved session/workspace source, audio C ABI, fixture, runner or renderer-thread architecture changes. No timers that fabricate advancement and no relaxed 100 ms/0.25-tick/quarter-second clauses. Every code file stays at most 600 lines; extend the existing playback scenario owner rather than adding another audio fixture subsystem.
