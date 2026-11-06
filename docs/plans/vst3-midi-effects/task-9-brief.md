# Context
Live inserts need an owner: `TrackEffectsController` holds one `PluginInstance` per `EffectID`, arms/disarms Live, runs offline Render, normalizes the live take on Grab played, and publishes session-only output into `EffectOutputStore`. Renders go through the `PluginEffectRenderer` seam. Consumer: task 10 (presenter drives this controller) and task 12 (drawer page reads the store). Read plan.md Global Constraints and spec.md "App" (`TrackEffectsController`, `PluginEffectRenderer`, `EffectOutputStore`).

# Exact write set
- `src/swift/app/miditools/TrackEffectsController.swift` (new)
- `src/swift/app/miditools/PluginEffectRenderer.swift` (new)
- `src/swift/app/miditools/EffectOutputStore.swift` (new)
- `src/swift/app/ApplicationSession+Tabs.swift:84-93` (`retire`; `await effects.shutdown()` before `workspace.teardown()`)
- `src/swift/app/DocumentWorkspace.swift` (own `let effects: TrackEffectsController`; publish timelines normally; tab deactivation and workspace suspension cancel renders, close editors and detach inserts first. The `EffectOutputPage.onAddEffectRequested` → `midiEffects.open(track:)` connection is task 12's)
- `src/checks/miditools/TrackEffectsControllerChecks.swift` (new; `@MainActor func runTrackEffectsControllerChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService)`, called from `runProjectSessionSuite` in `src/checks/workspace/SessionChecks.swift:123-125`; the fixture plugin is resolved beside the check executable)

Registration (controller): new Swift sources into `src/swift/app/CMakeLists.txt` and `src/checks/CMakeLists.txt`; the `runTrackEffectsControllerChecks` call in `src/checks/workspace/SessionChecks.swift:123-125`; `bridge:baseline` if the surface needs it.

# Prerequisites
Task 2 (effect model and plugin-state undo), task 3 (sidecar), task 4 (slot, `liveMask`, `NativeAudio.attachLiveInsert`/`detachLiveInsert`), task 7 (`PluginInstance`, `CaptureDriver`, `LiveInsert`, `LiveTakeRing`, `LiveTake`), task 13 (`HelperProcess` termination and watchdog).

# Interface contract
Exactly spec.md "TrackEffectsController", "PluginEffectRenderer" and "EffectOutputStore", plus:
- Controller is workspace-owned as `DocumentWorkspace.effects`, `@MainActor`. Instances load lazily when the panel opens, Live is armed, or Render runs; on creation the instance restores `pluginState`; unknown/skipped module yields `.unavailable(reason)`.
- `isLive(_:)` / `setLive(_:_:)`: session-only, off on open. Arm by setting realtime processing true, then attaching the insert and setting `liveMask`. Disarm, removal, replacement, undo of add and track delete detach under `withRenderingStopped`, releasing engine notes and clearing track key state, then set processing false. Re-arm on device rebind.
- Timelines: document changes publish through the normal playback handoff; callback adoption signals the insert. No transport-start hook or live preroll.
- `render(_:range:)`: time selection covering the track, else valid song loop, else `[0, song end)`, snapped outward to bars. Refuse while armed and playing with "Stop playback to render". While armed and stopped, detach and stop processing, re-setup offline, render on the worker, then re-setup realtime, start processing and re-attach, including after cancellation or failure if still armed and active. Never process on two threads at once. Progress each bar; realtime pacing sleeps to wall clock. New requests supersede old and discard their results.
- While armed, a 50 ms main-thread timer drains `LiveTakeRing`, converts samples on the session timeline and commits segments to `LiveTake`; overflow or the take cap marks it degraded.
- `grabPlayed(_:)`: runs `EngineNoteNormalizer.normalize` over the effect's `LiveTake`, with the take's tick span snapped outward to bars as the range, and stores the notes with their `NormalizationReport`. The pane shows lattice notes; the page surfaces the grab status with the report on the diagnostics line.
- Plugin-state recording: finished plugin edits become one "edit plugin settings" undo step via `recordPluginState`. No output refresh; nothing is read back from the song.
  - Baseline: right after an instance is created and restored, read `state()` and keep its component digest as the baseline. No history, no dirty. Each successful record moves the baseline.
  - Detection: parameter gestures record on `onEdit`, debounced 300 ms: read `instance.state()` and record it if its component digest differs from the baseline. Non-parameter edits record through the 500 ms component-digest poll while the editor is open: once the digest has changed and stayed stable for one poll, record the burst as one step. The digest covers component bytes only, so controller-only changes record nothing.
  - Applying undo/redo: for a foreign `pluginState` change, restore on the main thread while live processing continues, then set the insert's atomic input-discontinuity flag. Cancel and await an in-flight Render before restore, superseding its result. Suppress `onEdit`/poll recording from restore until `state()` is re-read as the new baseline. An unloaded instance picks up the blob on creation.
- `EffectOutputStore`: `EffectOutput { range, notes, origin (.render/.grab), report, degraded }`, one entry per `EffectID`. Cleared on effect removal and workspace teardown. Never in the document.
- **Crash and hang.** Wire `Process.terminationHandler`, stdout EOF, control-request timeout and the task-13 armed watchdog to a single main-actor path. If no request completes for 2 s or heartbeat stalls for 2 s while armed, kill the helper and use reason `stopped responding`; unexpected exit uses `stopped working`. Detach the insert, kill the helper if still alive, set `.crashed(reason)`, cancel Render and drop the instance. Keep the document unchanged; saving writes the last recorded `pluginState`. Remember whether Live was armed at failure.
- **Reload.** Manual Reload spawns a new helper, creates the plugin and restores the document's current `pluginState` (the last recorded undo step; at most one in-flight gesture is lost). Re-arm Live only if it was armed at the crash. Never reload automatically.
- **Instance access.** `TrackEffectsController.instance(for: EffectID)` is the internal accessor for the controller's existing instance; checks reach it with `@testable import` to set the fixture state through `PluginInstance.restore(_:)` without changing the document.
- Lifecycle ordering (main actor): panel close keeps instances, editors and Live arming. Tab deactivation and workspace suspension cancel Render, close editors and detach inserts first; instances stay. Removal, replacement, track delete and tab close detach first, stop processing, cancel and await worker idle, close the editor programmatically and shut down the helper. Weak instance plus generation guards discard late hops; completions never touch the document after teardown.

# Implementation steps
1. Build the store: value type plus per-`EffectID` map, clear on removal/teardown.
2. Build the controller skeleton: instance map, lazy creation with state restore, `.unavailable` path, `shutdown()` running the full ordering.
3. Add Live arming: set processing true then attach via `NativeAudio`; detach then set false. Cover explicit disarm, removal, replacement, undo of add and track delete. Drain take every 50 ms while armed.
4. Add Render through the renderer seam, with offline setup, stopped-armed detach/re-attach, progress and completion guards; refuse while armed and playing.
5. Add Grab: normalize the take into the store with its report; empty take is a status, not an error.
6. Add plugin-state recording: baseline, debounced `onEdit`, stable-poll detection, main-thread restore with discontinuity flag and suppression.
7. Wire workspace construction, tab-close ordering and deactivate/suspend paths; panel close keeps editor and Live.
8. Wire termination, EOF, control timeout and armed watchdog into one main-actor crash path; implement manual Reload and conditional re-arm. Check both fixture fault modes through a real helper.

# Acceptance predicate
NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-projectsession`: track-header menu regression (`trackheadermenu.swift` runs in this suite; rows stay `[1…6]` at `:18`, count 6 at `:234`, until task 10).
- `uv run --no-sync dev checks --filter swiftcore-projectsession`: controller suite — processing-before-attach and detach-before-processing-off, mask and key release; undo of add and track delete detach; Render range fallbacks and bar snap; refusal while armed/playing; stopped-armed offline re-setup and realtime re-attach without concurrent process; 50 ms take drain and degraded status; Grab normalization; baseline, gesture/poll coalescing, live restore plus discontinuity and suppression; controller-only state changes record nothing; teardown detaches before shutdown, waits for worker and closes editor, and discards late completion. With a real helper and fixture `Fault=1`, assert the app survives, the insert detaches and releases notes, `.crashed` reports stopped working, Render is cancelled and document state is unchanged. With `Fault=2`, assert bounded misses and watchdog kill with stopped-responding status. For each, Reload spawns a new helper, restores the last recorded state and re-arms only if armed at failure; other tracks continue.
- `uv run --no-sync dev checks --filter swiftcore-pluginhost`: regression (no seam change in host).
- `uv run --no-sync dev checks:bridge` (only if the surface needs it)

# Task-specific constraints
- Never call `pdph_*` directly; go through PorydawPluginHost.
- No `Sequencer`/`AudioRenderEngine`/`AudioDevice` edits (task 4 owns them); only call the attach/detach entry points.
- No QML, no presenter strings, no header menu rows in this task.
- QML-facing members in the class body (rule://qtbridge-surface). Comments at most 2 lines.
