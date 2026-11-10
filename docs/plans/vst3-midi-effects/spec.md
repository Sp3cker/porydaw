# VST3 MIDI effects — shared specification (live inserts with an Effect Output pane)

## Product rule

A track can host one VST3 MIDI-producing plugin as a **live insert**. With Live on, the audio callback sends each chunk to the plugin's helper as that track's insert during song playback, and its notes drive the track's engine voice at the plugin's own timing, as a preview. The song never stores plugin output: the `.mid` holds only what the user writes or pastes. **Render** (offline, over a range) and **Grab played** (the live notes last heard) fill the session-only **Effect Output** drawer pane; both snap notes to the engine lattice on the way in, so pasted notes may shift by up to half a lattice step and some may merge or drop, as the pane and diagnostics show. The user selects notes there, copies them, and pastes them into real tracks with the normal roll paste. The `.mid`, WAV export, CPU profile, backups and every editing surface see the song only. While a track is Live, Porydaw plays notes the `.mid` does not contain; the track header shows a badge with the plugin's name, plus a "Live" caption while the effect is armed.

## Vocabulary

- **Song** — the editable `SongDocument` state: notes, lanes, tempo, config and effects. Plugin output is never part of it.
- **Live insert** — a plugin effect with Live armed: the audio callback runs the plugin as a track insert and dispatches its notes at their sample offsets.
- **Live arming** — session-only state in `TrackEffectsController`. It is never saved; every effect opens with Live off.
- **Effect Output** — session-only per-effect note data in `EffectOutputStore`: the last Render result or the last Grab played, with its origin. Lost on close; never in the document, never persisted.
- **Render** — an offline capture over a range, paced offline or realtime. Live is always realtime; pacing applies to Render only.
- **Grab played** — running `EngineNoteNormalizer.normalize` over the effect's `LiveTake` (the raw live events last heard) into Effect Output, with the take's tick span snapped outward to bars as the range.
- **Origin** — where an Effect Output came from: `.render` or `.grab`. Shown as "Rendered" or "Played".
- **Degraded** — the live take lost entries to take-ring overflow or its 65 536-event cap; shown with "some notes were dropped".
- **Capture** and **pacing** — how a hosted plugin is run to produce output (see "Swift host").

## Core (PorydawCore)

### EngineNoteLattice and EngineNoteNormalizer
Task 1 defines them, unchanged from the first design. `EngineNoteLattice` keeps the arpeggiator's lattice and duration fixed points, and `Arpeggiator` output stays byte-identical. `EngineNoteNormalizer.normalize(_:track:range:lattice:) throws -> (notes, report)` is the only normalizer; it turns `RawNoteEvent`s into lattice-exact, fixed-point `[NewNote]` by these rules, in order. Render and Grab both enter Effect Output through it.

1. stable sort, offs before ons at equal ticks;
2. pair by positive `noteID`, else FIFO per pitch;
3. snap onsets to the nearest lattice point, ties going later;
4. drop onsets outside the range;
5. pitch 0…127, velocity clamped to 1…127;
6. fixed-point durations, dropping notes too short to represent;
7. at the same onset and pitch the later event wins (different pitches remain a chord);
8. trim same-pitch overlaps;
9. throw `tooManyNotes` above 65 536 notes.

`NormalizationReport` counts each adjustment.

Canonical task-1 API (all properties and initializers below are public):

```swift
public struct RawNoteEvent: Equatable, Sendable {
    public var tick: Int64
    public var pitch: Int
    public var velocity: Int
    public var isOn: Bool
    public var noteID: Int32?
    public init(tick: Int64, pitch: Int, velocity: Int, isOn: Bool, noteID: Int32? = nil)
}
public struct EngineNoteLattice: Sendable {
    public let quantumTicks: Int64
    public let quantumClocks: Int64
    public init(ticksPerBeat: UInt32, playbackSettings: PlaybackSettings) throws
    public func snap(_ tick: Int64) -> Int64
    public func isOnLattice(_ tick: Int64) -> Bool
    public func durationTicks(target: Double, maximum: Int64) -> Int64?
}
public enum NormalizationError: Error, Equatable {
    case invalidRange, tooManyNotes
}
public enum EngineNoteNormalizer {
    public static let noteLimit = 65_536
    public static func normalize(
        _ events: [RawNoteEvent], track: Int, range: TimeRange, lattice: EngineNoteLattice
    ) throws -> (notes: [NewNote], report: NormalizationReport)
}
```

`NormalizationReport: Equatable, Sendable` has a public zero-argument initializer and public mutable `Int` counters, all initially zero: `notes`, `nonNoteEvents`, `droppedBeforeRange`, `droppedAfterRange`, `droppedPitch`, `droppedTooShort`, `orphanOffs`, `unterminatedNotes`, `snappedOnsets`, `adjustedDurations`, `velocityClamped`, `overlapsTrimmed`, `duplicatesSuppressed`. Capture supplies `nonNoteEvents`; normalization leaves it zero. Negative tracks, empty ranges and reserved endpoints throw `invalidRange`. Zero division throws `ArpeggiatorError.unsupportedTiming`.

Signed raw ticks preserve pre-roll. Velocity-zero ons are offs. Reused positive IDs consume pending onsets FIFO by ID, regardless of off pitch; nil and nonpositive IDs share FIFO queues per pitch. Unmatched offs increment `orphanOffs`; open onsets close at `range.endTick` and increment `unterminatedNotes`. Range rejection follows snapping; out-of-bounds pitches are dropped rather than clamped.

Duration target is paired off tick minus snapped onset, preserving absolute release, with maximum `range.endTick` minus snapped onset. Targets below one quantum drop as `droppedTooShort`; other targets choose the nearest fixed point, ties later, possibly extending past the raw release but never the range end. Overlaps retrim the previous same-pitch note with maximum at the next onset; no representable positive duration drops the previous note as `droppedTooShort`.

Each rejected onset increments at most one `dropped*` counter. Adjustment counters are computed after suppression and overlap trimming, only for surviving notes; `adjustedDurations` compares the final duration with the release target. `duplicatesSuppressed` counts discarded same-onset, same-pitch predecessors represented by each surviving winner. Output follows stable chronological onset-event order, and `report.notes` equals its count.

Live playback uses no normalizer: the insert returns raw events, and snapping happens only when notes enter Effect Output.

### Model — `src/swift/core/TrackEffect.swift`

```swift
public struct EffectID: Hashable, Sendable, Codable { public let raw: UInt64 }
public enum EffectInput: Int, Sendable, Codable { case none = 0, trackNotes = 1 }
public enum EffectPacing: Int, Sendable, Codable { case offline = 0, realtime = 1 }
public struct PluginEffectConfig: Equatable, Sendable, Codable {
    public var modulePath: String
    public var classUID: [UInt8]          // 16 bytes
    public var name: String               // catalog display name at selection time
    public var input: EffectInput, pacing: EffectPacing
    public var prerollBars: Int           // 0...2
}
public struct TrackEffectConfig: Equatable, Sendable {
    public var track: Int                  // engine track
    public var plugin: PluginEffectConfig
}
public struct PluginStateBlob: Equatable, Sendable, Codable {
    public var component: [UInt8], controller: [UInt8]
}
public struct TrackEffect: Equatable, Sendable {
    public let id: EffectID
    public var config: TrackEffectConfig
    public var pluginState: PluginStateBlob?
}
```

`SongState` gains `effects: [TrackEffect]`, sorted by `config.track`, with at most one effect per engine track. `SongState.init` defaults it to `[]`, and `differs(from:)` includes it.

### Document operations — `src/swift/core/TrackEffectEditing.swift`

```swift
extension SongDocument {
    public var effects: [TrackEffect] { get }
    public func effect(onTrack track: Int) -> TrackEffect?
    @discardableResult
    public func addEffect(_ config: TrackEffectConfig, replacing: EffectID?) throws -> EffectID
    public func removeEffect(_ id: EffectID) throws
    public func updateEffect(_ id: EffectID, config: TrackEffectConfig, group: HistoryGroup?) throws
    public func recordPluginState(_ id: EffectID, state: PluginStateBlob) throws  // one undo step; no-op when unchanged
}
public enum TrackEffectError: Error, Equatable {
    case invalidTrack(Int), trackHasEffect(Int), unknownEffect
}
```

- **Errors.** `addEffect` throws `.trackHasEffect` unless `replacing` names that track's effect; with `replacing`, the removal and the insertion are one entry. `config.track` must map to an engine track.
- **Effect IDs.** The counter (`nextEffectID`, stored beside `nextNoteID`) lives outside undoable state and never rolls back on undo or redo, so an ID is never reused within a session. `init(effects:)` starts it past the restored maximum.
- **Undoable deltas.** `DocumentChangeSet` gains `insertEffect(TrackEffect)`, `removeEffect(TrackEffect)`, `effectConfig(EffectID, before, after)` and `pluginState(EffectID, before: PluginStateBlob?, after: PluginStateBlob?)`. A config delta replays onto the current effect's config and leaves its `pluginState` untouched, so undo never rolls back plugin state. Insert and remove deltas restore the whole effect, plugin state included.
- **History operations.** `HistoryOperation` gains `.addEffect`, `.removeEffect`, `.updateEffect(EffectID)` (gesture-coalescable within one `HistoryGroup`) and `.editPluginState(EffectID)`. `HistoryStepLabel` phrases: "add MIDI effect", "remove MIDI effect", "edit MIDI effect", and "edit plugin settings" for `.editPluginState`.
- **Remap.** Every structural track mutation in `EventEditing.swift` (add, duplicate, delete, move) maps `config.track` through its `TrackRemap.engineTrackMap` inside the same mutation. A nil destination removes the effect in that mutation, and undo restores it.
- **Record.** `recordPluginState` commits one history entry through the normal `commit` path with a `pluginState` delta. It is a no-op when `after == before`.
- **Dirty.** `SongDocument.isDirty = history.isDirty`, with no special case: a recorded plugin edit dirties through history like any other step, and undoing it clears that dirt.
- **`DocumentChange.effectsOnly`.** True when every delta of the change is an effect delta (insert/remove/config/pluginState). Such a change publishes `[.effects, .dirty, .history]`, skips the timeline rebuild, and skips selection reconciliation.

### SongSnapshot — not kept

There is no `SongSnapshot`. Offline `CaptureRequest` takes an immutable `PlaybackTimeline` value plus the input notes instead of an eager document copy. Live reads the callback-adopted immutable timeline.

### Sidecar codec — `src/swift/core/EffectsSidecar.swift`

```swift
public struct EffectsSidecar: Equatable, Sendable, Codable {
    public var version: Int                 // 2
    public var effects: [StoredEffect]      // Codable mirror of TrackEffect
}
```

`StoredEffect` holds track, modulePath, classUID as 32 lowercase hex characters, name, input, pacing, prerollBars, and component/controller state as base64. Codable, deterministic key order.

## Session and persistence (PorydawDocument, PorydawProject)

Task 3 owns this section.

- **Session.**
  - `SessionChangeDomains` gains `.effects`. A change with `effectsOnly` publishes `[.effects, .dirty, .history]`, skips the timeline rebuild, and skips selection reconciliation.
  - The session timeline is built from the song unchanged. There is no playback-only timeline variant; the live path suppresses the live track's sequenced notes with `liveMask` instead.
- **Save.** `SaveSnapshot` gains `effectsSidecar: EffectsSidecar?`. `ProjectService.save` and `forkSongAs` (see `ProjectService+Bank.swift:133,179` for the `openSong`/`save` pair) write `<label>.mid`, then `<projectRoot>/.porydaw/midi-effects/<label>.json` atomically. With no effects they remove any existing json. File operations use the `ProjectFileStore` statics `mkpath`/`move`/`remove`/`writeAtomic`/`exists`.
- **Open.** `ProjectService.openSong` reads the json when it exists. `LoadedSong.effects: LoadedEffects?` is `restored(EffectsSidecar, dropped: Int)` or `corrupt(movedTo: String)`.
  - Effects whose track is ≥ the engine track count, or duplicates per track, are dropped. A notice goes through `ShellPresenter.criticalRequested`: title "MIDI effects", message "<label>: N MIDI effect(s) referred to missing tracks and were removed."
  - A corrupt json is renamed `<label>.corrupt-<yyyyMMdd-HHmmss>[-N].json` (the smallest free `N` on a collision; never overwrite), with title "MIDI effects" and message "<label>: the MIDI-effects sidecar was corrupt and was moved aside."
- **Song deletion.** The `SongRegistration+Store.swift` delete path removes the json. Backups keep only the `.mid`. No rename path exists; any future one must move the json.
- **Unchanged paths.** WAV export, CPU profile and backups are unchanged (song only). No flattening anywhere.

## Plugin bridge (out-of-process)

Task 13 owns the bridge. `porydaw-vst3-host`, built from `src/pluginhost/` with C++, the SDK and Qt6::Gui, ships in `Contents/MacOS/` on macOS and beside the executable elsewhere. `scan <modulePath>` retains the scanner JSON contract; `host --channel <name>` hosts exactly one plugin instance, with control frames over stdin/stdout. Each `PluginInstance` lazily spawns its own helper. Porydaw never loads a VST3 module or links the SDK; `porydaw_pluginhost` links only into the helper and checks. The helper's Qt main thread dispatches controls, editor windows, Linux `IRunLoop` and key interception; a realtime thread processes requests and a stdin reader posts frames to the main thread with a queued invoke. Stdin EOF exits the helper. On macOS it sets `NSApplicationActivationPolicyAccessory` at startup, without a Dock icon; verify window focus and menu-bar behavior in the final smoke.

- **Build and packaging (task 6).** The same CMake builds `porydaw-vst3-host` (`.exe` on Windows) on every platform and architecture, following `CMAKE_OSX_ARCHITECTURES` (release macOS builds arm64 and x86_64 separately). It is written to the runtime directory beside the check hosts and the non-Apple app (`PROJECT_BINARY_DIR`, per configuration for multi-config generators, as the fonts are at `CMakeLists.txt:559-574`); on Apple a `POST_BUILD` copy also places it in `porydaw.app/Contents/MacOS/`. `porydaw`, `porydaw_checks` and the QML check hosts depend on it, so `build:app` (target `porydaw` only, `tools/porydaw_dev/cli.py:330-333`) and every check lane build it.
  - Windows: `WIN32_EXECUTABLE`, because Porydaw is GUI-subsystem (`CMakeLists.txt:696`) and a console child would open a console window; stdio uses the inherited pipes. `install(TARGETS porydaw-vst3-host RUNTIME DESTINATION .)` places it beside `porydaw.exe`, where windeployqt's Qt DLLs and `platforms/` already serve it.
  - macOS: `macdeployqt … -executable=build/porydaw.app/Contents/MacOS/porydaw-vst3-host` in `build.yml` and `release.yml`, so its Qt references resolve to the bundle's frameworks and `-codesign=-` signs it before the existing `codesign --verify --deep --strict`.
  - Linux: release `linuxdeploy` gains `-e build/porydaw-vst3-host` beside `-e build/porydaw`; the `build.yml` Linux artifact uploads both binaries.
  - Each packaging job runs the packaged helper with `scan` on a nonexistent path and expects exit 1 with a one-line reason, proving it starts without loader errors and with no Qt paths set. Qt platform-plugin loading in packages is proven only by the final macOS smoke.
  - Resolution: `HelperProcess.executableURL` is `Bundle.main.executableURL`'s directory plus the platform file name; no search path or fallback. A missing file fails scan with "Plugin scanner is missing from this installation." and instance creation with "Plugin unavailable: Plugin scanner is missing from this installation."

- **Wire layout.** `src/pluginhost/pluginbridge.h` is C without SDK includes, imported via the `PorydawPluginBridge` module map; `pluginhost.h` includes it. It owns `pdph_midi_event`, `pdph_process_context`, `PDPH_EVENT_*` and `PDPH_CTX_*`. Constants: `PDPB_VERSION 1`, `PDPB_MAX_EVENTS 4096`, `PDPB_MAX_CHUNK 8192`. Per-instance `pdpb_shared` contains magic and version, `_Atomic uint32_t request_seq, reply_seq`, wait words `request_word`, `reply_word`, and `_Atomic uint64_t heartbeat`; the RT thread increments heartbeat each loop, including 100 ms idle wakeups. The request contains `frames`, `pdph_process_context ctx`, `in_count`, and `pdph_midi_event in[4096]`; the reply contains `status`, `out_written`, `out_total`, and `pdph_midi_event out[4096]`, with chunk-relative offsets.
  ```c
  typedef struct { uint32_t state_flags; /* PDPH_CTX_* = SDK ProcessContext::StatesAndFlags:
                       PLAYING, CYCLE_ACTIVE, CYCLE_VALID, TEMPO_VALID, TIME_SIG_VALID,
                       PROJECT_TIME_MUSIC_VALID, BAR_POSITION_VALID */
                   double sample_rate, tempo, ppq_position, bar_start_ppq, cycle_start_ppq, cycle_end_ppq;
                   int32_t time_sig_num, time_sig_den; int64_t project_samples; } pdph_process_context;
  typedef struct { int32_t sample_offset, note_id; uint8_t kind /* PDPH_EVENT_NOTE_ON|NOTE_OFF|OTHER */,
                   channel, pitch; float velocity /* 0…1 */; } pdph_midi_event;
  ```
- **Wait/wake.** `pluginbridge_wait.c` is compiled into the PorydawPluginBridge module target and the helper; it allocates nothing and never locks. API: `pdpb_channel_create(name, out)`, `pdpb_channel_open(name, out)`, `pdpb_channel_close`, `pdpb_post_request`, `pdpb_wait_reply(timeout_us)`, `pdpb_wait_request(timeout_ms)`, `pdpb_post_reply`. macOS uses `shm_open`/`mmap` and `os_sync_wait_on_address_with_timeout` / `os_sync_wake_by_address_any` with `OS_SYNC_WAIT_ON_ADDRESS_SHARED` / `OS_SYNC_WAKE_BY_ADDRESS_SHARED`; Linux uses `shm_open`/`mmap` and a non-private futex on the shared word. Windows uses named `CreateFileMappingW` and `CreateSemaphoreW`, `OpenSemaphoreW` in the helper and `WaitForSingleObject(timeout)`, with names `Local\porydaw-<pid>-<n>-{shm,req,rep}`. POSIX shared memory is unlinked as soon as the helper reports Ready.
- **Control protocol.** Little-endian frames are `[u32 type][u32 requestId][u32 length][payload]`. Requests: `CreatePlugin(modulePath, classUID[16])`, `SetupProcessing(realtime, sampleRate, maxBlock, periodFrames)`, `SetActive(on)`, `SetProcessing(on)`, `GetState(which)`, `SetState(which, bytes)`, `GetStateDigest`, `GetLatency`, `OpenEditor(title)`, `RaiseEditor`, `CloseEditor`, `SetShortcuts(strokes[])`, `Quit`. Replies carry requestId, `ok`/`error(text)` and payload. Helper events: `Ready(version)`, `EndEdit(paramId)`, `RestartComponent(flags)`, `SetDirty(on)`, `EditorClosed`, `Shortcut(index)`. Swift waits 5 s per control request, 30 s for `CreatePlugin`.
- **RT protocol.** Once per live render chunk (at most 8192 frames, split at loop end), the audio thread writes events and context, increments `request_seq`, wakes the helper and waits `max(1 ms, 0.5 × chunk duration)` for a reply. The helper sub-blocks into at most 1024 frames per plugin call and returns all output in one reply. On timeout the slot returns `missed`; if `reply_seq != request_seq` at the next call, it posts nothing and returns `missed` immediately. Ignore a late reply whose sequence does not match. On `missed`, Sequencer releases the track's live-held output keys and the next posted chunk carries input discontinuity. Render uses the same channel only with live detached, waiting at most 10 s per request. It returns a typed timeout; the MainActor helper owner records stopped-responding before terminating the helper and before asynchronous Render cleanup. The worker never kills the helper.
- **Priority.** The helper RT thread uses macOS `THREAD_TIME_CONSTRAINT_POLICY` with period `periodFrames` / rate; Windows MMCSS `AvSetMmThreadCharacteristicsW(L"Pro Audio")`; Linux `SCHED_FIFO` priority 80, then `SCHED_RR`, then normal.
- **Crash and hang.** Foundation `Process.terminationHandler`, stdout EOF, a control-request timeout or the RT watchdog detects failure. While armed, the main-thread watchdog polls `reply_seq` and `heartbeat`; no completed request or a stalled heartbeat for 2 s declares a hang. MainActor commits the typed failure before SIGKILL or `TerminateProcess`; later EOF cannot replace its cause. The controller enqueues control-owned detach to release engine notes, marks `.crashed(reason)`, cancels Render and awaits owned cleanup before dropping storage. The document is unchanged and saving writes the last recorded `pluginState`.
- **Recovery.** With no modal dialog, Effect Output and the panel show "<name> stopped working." for an unexpected exit or "<name> stopped responding." for a hang. Effect Output offers **Reload Plug-in** (`effectOutputReload`); the panel offers Reload (`midiEffectsReload`); the track badge caption is "Stopped" instead of "Live". Reload is always manual: spawn a helper, create the plugin, restore the document's current `pluginState` and re-arm Live if armed at failure. At most one in-flight gesture is lost.

## Live playback engine (PorydawPlayback + app audio)

Task 4 owns this section. It is the only task that edits `Sequencer` or `AudioRenderEngine`; `AudioDevice` is untouched.

### Live insert (audio callback)

Task 4 defines the PorydawPlayback seam; task 7 implements it in PorydawPluginHost. Playback never imports the host or SDK.

- **Slot and events.** A `LiveInsertSlot` holds an `@convention(c)` process function pointer and an opaque context pointer, not a closure; the function takes opaque context and a pointer to a borrowed plain-data call record. The call carries the chunk, real transport and timeline context, discontinuity flags, and an optional C-convention take-sink function/context supplied by the insert. Sequencer reports actual note dispatches, completed-chunk positions and segment boundaries through one borrowed `LiveTakeEvent` with kind `note`, `position` or `boundary`. `LiveInputEvent { sampleOffset, key, velocity, noteId }` and `LiveOutputEvent { sampleOffset, key, velocity, noteId }` cross the seam through preallocated arrays, each holding 4096 events per chunk; excess input and output events are counted. Offsets are relative to the chunk, keys are 0…127, velocity is 1…127 for on or 0 for off, and note IDs pair ons and offs. No callback allocation, locking, dispatch or closure capture.
- **Chunk procedure.** `AudioRenderEngine` renders chunks of at most 8192 frames (`src/swift/app/audio/AudioRenderEngine.swift:48,429-442`). Before synthesizing each song chunk, `Sequencer` gathers only the live track's note events in `[position, position + frames)` from the callback-adopted immutable timeline without allocating and invokes its slot once per contiguous chunk; split the chunk at a loop end before invoking a slot so plugin blocks never span the boundary. `LiveInsert` makes one bridge round trip per chunk, returning chunk-relative output; the helper subdivides it into at most 1024-frame blocks at the device sample rate (`kRealtime`, `maxSamplesPerBlock = 1024`). Build context from actual position, timeline tempo/meter/bar/cycle and transport flags. While stopped invoke the insert from each callback with `kPlaying` clear. There is no live preroll.
  The slot result includes `missed`; Sequencer releases live-held output keys and flags input discontinuity for the next call as specified in the bridge protocol. Task 4 checks this with a fake slot.
- **Input rule (live and Render).** With `EffectInput.trackNotes`, pass only the effect track's notes, channel 0, velocity / 127 and positive note IDs shared by on/off pairs (FIFO per pitch). With `EffectInput.none`, pass no notes. Song CC, program and bend never enter the plugin but continue to the GBA engine; output channel is ignored. `LiveInsert` owns a counted input-held ledger per pitch and note ID, like Ardour's `MidiNoteTracker` (`libs/ardour/midi_state_tracker.cc:93-116,132-158`, research/hosts/held-notes.md).
- **Input discontinuities.** Seek, stop, loop wrap, callback timeline adoption, arm, state restore and return from pattern audition signal the insert through plain per-call flags (restore may set an atomic input-discontinuity flag). At each discontinuity send an explicit off for every held count at offset 0 of the next plugin block, then chase notes sounding at that position from offset 0. At loop wrap both occur at offset 0 of the first wrapped block, offs before chased ons; both use the new loop context. This preserves exact boundary timing and one bridge request per chunk, without an early off or an extra zero-sample call. Adoption re-derives sounding notes from the newly adopted timeline. Stopped processing has `kPlaying` clear; resume starts at the real play position.
- **Output-held ledger.** `Sequencer` holds the owning `noteId` per track and key. A note-on for a held key releases it first; an off whose ID does not own the key is swallowed. A velocity-0 NoteOn is an off. Dispatch output at its exact sample via the existing next-boundary split (`src/swift/playback/Sequencer.swift:611-637`), honoring `muteMask`; derive `polyEventClock` and `keyedOnTick` through `TimelineSource.tick(for:)`. `wrapNotes` releases live notes at loop end; existing seek, mute and stop paths release engine voices and clear corresponding live ownership.
- **Mask and lifetime.** `liveMask` suppresses sequenced note-on and note-off dispatch and key-state updates for live tracks, not CC, program, bend or tempo. `AudioRenderEngine` owns 16 atomic slot pointers and the mask. `NativeAudio.attachLiveInsert(track:insert:)` and `detachLiveInsert(track:insert:)` synchronously enqueue `AudioControl` cold commands and return `AudioOperation<Void>` receipts. Control applies renderer changes under `withRenderingExcluded`, retains installed `LiveInsert` owners and acknowledges only after mutation. Detach checks exact owner identity, releases track notes and clears live key/take state before releasing its borrow. Host awaits that receipt before changing producer ownership or reclaiming storage. WAV export and pattern audition pass no slots; pattern audition owns the callback exclusively and returning signals a discontinuity.
- **Audio ownership.** MainActor owns intent and asynchronous helper IPC; the existing `AudioControl` executor owns device/renderer work. Cold operations exclude callback blocks without stopping/restarting the device or blocking MainActor. Host's `armLive(input:sampleRate:periodFrames:attach:detach:)` takes two escaping `@MainActor (LiveInsert) async -> Void` callbacks carrying exact owner identity; detach acknowledgment precedes Render reservation and reclamation. Telemetry is cached/generation-matched, and requested transport is not callback acknowledgment.
- **Take.** `LiveInsert` writes every output note actually dispatched, completed-chunk position records and segment markers at seek, wrap, stop and discontinuities to a preallocated 8192-entry callback→main SPSC `LiveTakeRing`. Sequencer resolves each position's sample and tick on the callback's applicable timeline before any wrap or adoption. Discontinuity-generated note-offs carry explicit flags; the drain closes these old-segment notes at its last authoritative completed position, not at a seek/adoption's new position. Position records preserve silent tails and are never interpreted as notes. Swallowed or muted events are not recorded. Full ring: drop and count entries, mark take degraded; never wait. A 50 ms main-thread timer drains it while armed and commits segments to `LiveTake`, closing open notes at exact old endpoints before starting the new segment. Each new segment replaces earlier take events whose onsets fall within its tick span. Zero-duration intermediate boundaries commit no span. The 65 536-event cap also drops excess and marks degraded. Grab normalizes the take over its span, snapped outward to bars; correctness does not depend on a later main-thread transport snapshot.
- **Latency and risks.** Plugin-reported latency is not compensated live; most MIDI effects report zero. Render still compensates it. Slow plugins or helper scheduling can cause missed chunks and audio dropouts; RT wake latency is not guaranteed without an IO workgroup join. The helper's buffers, `EventList`s and parameter changes are preallocated at setup; plugin behavior inside `process()` is the plugin's responsibility.
- **CPU meter.** Plugin execution time is not included: the existing live meter reports modeled GBA SoundMain costs, not callback wall time. `AudioRenderEngine.swift:436-448` collects driver cycle estimates, `AudioCpuTelemetry.swift:4-12,55-72` reads `M4AFrameCost`, and `CpuMeterPresenter.swift:96-109,117-127` publishes those values. No meter feature is added.

## App (PorydawApp)

### TrackEffectsController — `src/swift/app/miditools/TrackEffectsController.swift`

Task 9 owns this file. Workspace-owned as `DocumentWorkspace.effects` and `@MainActor`.
The application session owns the sole plugin catalog and injects it into each workspace/controller; the presenter reuses it. Construction reads the platform-data `porydaw/Plugins` cache without scanning. The session owns the catalog's change callback and fans updates out to its consumers.

- **Instances.** Owns one `PluginInstance` per `EffectID`, loaded lazily when the panel opens, Live is armed or Render runs. On creation the instance restores `pluginState`; an unknown or skipped module yields `.unavailable(reason)`. `shutdown() async` runs the lifecycle ordering for every instance.
- **Live arming.** `isLive(_:)` / `setLive(_:_:)` are session-only, off on open. Set realtime processing true before acknowledged attachment; await cold detach before setting processing false. Removal, undo of add and track delete disarm identically. A 50 ms timer drains the take while armed.
- **Timelines.** Document changes publish the normal playback timeline; callback adoption signals the insert to flush and chase.
- **Render.** `render(_:range:)` captures the time selection covering the track, else the valid song loop, else `[0, song end)`, snapped outward to bars. While armed and playing it refuses with "Stop playback to render". While armed and stopped, detach, stop processing, re-setup offline, render on the instance worker via the helper, then re-setup realtime, start processing and re-attach. Restore the realtime insert after cancellation or failure if still armed, the workspace is active and the helper is healthy. Live and Render never overlap. Progress reports each bar; realtime pacing sleeps to wall clock. A new render supersedes an in-flight one and discards its result.
- **Grab.** `grabPlayed(_:)` runs `EngineNoteNormalizer.normalize` over the effect's `LiveTake`, with the take's tick span snapped outward to bars as the range, and stores the notes with their `NormalizationReport`. The Effect Output pane therefore always shows lattice notes.
- **Crash, watchdog and Reload.** Track `.crashed(reason)` and remember whether Live was armed. Run the armed watchdog and failure response defined in Plugin bridge; do not change document state. Manual Reload creates a fresh helper, restores the current document state and re-arms when appropriate.
- **Plugin-state recording.** Finished plugin edits become one "edit plugin settings" undo step via `recordPluginState`. There is no output refresh; nothing is read back from the song.
  - Baseline: after creation and restore, request the helper's component digest as the baseline. No history, no dirty. A plugin that re-serializes its restored state differently never creates a spurious step. Each successful record moves the baseline.
  - Detection: parameter gestures record on `onEdit` (the plugin's end of gesture), debounced 300 ms: request `GetStateDigest` and, if it differs from baseline, read full `GetState` and record it. Non-parameter edits use a 500 ms helper digest poll while the editor is open: once the digest has changed and then stayed stable for one poll, read full state and record the burst as one step. The helper computes FNV-1a 64 over component bytes only, so plugin-UI-only controller changes never create steps.
  - An internal per-effect `PluginStateRecorder` owns the baseline, restore suppression, gesture debounce and editor-only stable-digest observation. Its asynchronous IPC never runs inline in the independent 50 ms Live/take/watchdog pump. Digest observation is quiescent while inactive, rendering, retired or editor-closed; finished gestures pending at Render resume afterward. Lifecycle cleanup cancels and joins recorder tasks.
  - Applying undo/redo: when a foreign document change alters an effect's `pluginState`, restore it through the helper while live processing continues, component then controller, then set the atomic input-discontinuity flag. Cancel and supersede an in-flight Render before restore. An unloaded instance picks up the blob when created.
  - Suppression: from restore start until the controller has requested the helper digest and adopted it as the new baseline, `onEdit`/poll recording is suppressed. Restore therefore never records a step and never breaks redo.

**Lifecycle ordering (main actor intent, control-owned audio mutation).** Closing the panel keeps instances, editors and Live arming. Deactivation or suspension cancels Render, closes editors and enqueues detach before stop/unload/new bind, disarming Live while retaining instances. Removal, replacement, track delete and tab close await detach, stop processing, cancel and await the worker, close the editor and shut down the helper. Shutdown also awaits the workspace's queued audio release before document retirement. Attach rejects stale generations; cleanup always targets its immutable old insert identity, so late detach cannot remove a successor. Owned asynchronous failure/cleanup tails retain storage until acknowledgment; no completion writes the document after teardown.

Cleanup dependencies are per effect, including retired helpers. Live, Render, editor open and Reload await only their effect's transitions; workspace shutdown joins all outstanding tails. The Live pump runs only while active effects are armed and is canceled and joined when no longer needed.

### PluginEffectRenderer — the controller's plugin seam

`src/swift/app/miditools/PluginEffectRenderer.swift` stays as the controller's plugin seam: it builds `CaptureRequest`s, runs the offline render through the instance worker, normalizes with `EngineNoteNormalizer` (taking the report's `nonNoteEvents` from the capture), and hands the notes to the controller for the store. The completion applies only if the effect still exists and the workspace generation is unchanged, else it is discarded.

### EffectOutputStore — `src/swift/app/miditools/EffectOutputStore.swift`

Task 9 owns this file. Session-only, workspace-owned:

```swift
public enum EffectOutputOrigin: Sendable { case render, grab }
public struct EffectOutput: Sendable {
    public var range: TimeRange
    public var notes: [NewNote]
    public var origin: EffectOutputOrigin
    public var report: NormalizationReport?
    public var degraded: Bool
}
```

One entry per `EffectID`. Cleared on effect removal and workspace teardown. It is never in the document.

### MidiEffectsPresenter — `src/swift/app/miditools/MidiEffectsPresenter.swift`

Task 10 owns this file. `@MainActor @QtBridgeable`, workspace-owned, QML-uncreatable. It edits the plugin effect of one track through `SongDocument` and the controller.

- **QML-facing properties:** `isOpen`, `trackLabel`, `status`, `diagnostics: String`, `plugins: QListModel<MidiEffectPluginRow>` (row: `name`, `vendor`, `detail`, `blocked: Bool`; the list shows only MIDI producers plus blocked entries, hidden audio-only plugins never appear), `selectedPlugin: Int` (−1 = none), `hasEffect`, `isScanning`, `isLoading`, `canOpenEditor`, `isEditorOpen`, `canReload`, `inputMode: Int`, `pacing: Int`, `prerollBars: Int`, `folders: [String]`, `baseFontPx`, `promptStyle`, `colors: GridPalette`, `bodyFont`.
- **Slots:** `open(track: Int)`, `close()`, `selectPlugin(index: Int)`, `rescan()`, `cancelScan()`, `retryBlocked(index: Int)`, `addFolder(path: String)`, `removeFolder(index: Int)`, `setInputMode(value: Int)`, `setPacing(value: Int)`, `setPrerollBars(value: Int)`, `removeEffect()`, `openEditor()`, `closeEditor()`, `reloadPlugin()`, `configure(fontPx: Double)`. `open(track:)` runs `scan(folders:force: false)`; `rescan()` runs `scan(folders:force: true)`. Reload delegates to the controller.
- **Selecting a plugin.** `selectPlugin` adds the effect, or replaces the track's effect (`addEffect(replacing:)`, one undo step), with default settings. Setting changes call `updateEffect` with one `HistoryGroup` per panel session.
- **Status strings** (exact): "Plugin unavailable: <reason>" (unavailable), "<name> stopped working." or "<name> stopped responding." (crashed). Empty-list text (exact): "No MIDI-producing VST3 plugins found. Add a folder or Rescan."
- **Header effects button.** Every real track header has an always-visible button beneath its retained voice subtitle, using the row-local `effectRect`; Add Track has no effects target. The label is "MIDI Effects..." without an effect, otherwise the plugin's `config.plugin.name`, elided to the available width. While armed, the static "Live" caption shows beside it; when crashed, "Stopped" replaces it. Preserve `timelineHeaderEffect_<track>` and `timelineHeaderEffectCaption_<track>` for these text items; the button is `timelineHeaderEffectsButton_<track>`.
- **Header state and geometry.** Row fields: `effectName: String` (empty = no effect; assigned from the config, never formatted per frame), `liveArmed: Bool`, `effectStopped: Bool`, `effectHovered: Bool` and `effectPressed: Bool`, published like the M/S pointer flags. Swift derives the nonzero third-line rectangle from resolved font metrics, using the measured subtitle-line height as the effects target height within the existing row height. Title, voice and effects targets do not overlap; row height, grid alignment and M/S geometry stay unchanged, without clamping or fallback geometry. The button uses appearance `buttonBackground`/`buttonText`, hover/pressed pairs, `buttonOutline` and `focusOutline`; plugin name and Live/Stopped meet WCAG AA in every theme.
- **Header activation.** `TrackHeadersPresenter.activateMidiEffects(track: Int)` validates the track against the attached current document, selects it and invokes the existing `onMidiEffectsRequested` callback. Pointer, Return/Enter, accessibility press and context action 7 use this action. Append `HeaderHitTarget.effects` after `addTrack` (raw 6), preserving prior target values. The existing Swift pointer state machine requires matching left press/release on the same valid target/document revision, cancels release outside or cancelled input, and never arms reorder for effects hits. The button is tab-focusable, exposes `Accessible.Button` with a meaningful per-track MIDI-effects name/description, shows focus/hover/press feedback and has no hover tooltip. It never claims bare Space: the window transport shortcut wins while the button is focused.
- **Editor and closing.** `openEditor()` while open raises the window. On macOS, editors remain above their owning Porydaw's ordinary windows while that app or any of its sibling editor helpers is foreground; clicking Porydaw retains keyboard focus there without covering its editors. Switching to an unrelated app lets that app cover them, not a global always-on-top policy. Open/raise explicitly activate; ordering alone never takes focus or restores hidden/minimized editors. The panel closes on `.bank`, suspension, deactivation, teardown, after Remove, and when its effect disappears. Closing the panel alone keeps the editor and Live; suspension, deactivation and removal follow the controller lifecycle.
- **Folders.** `PreferencesStore` key `vst3PluginFolders`, using the `SampleLibraryModel` pattern. Catalog cache directory: platform data `porydaw/Plugins`, resolved like `MidiBackupStore`'s root.
- **Accessor.** `SongTabSession`/`ApplicationSession` gain `midiEffectsPresenter()`, mirroring `arpeggiatorPresenter()`. `EditorSurface.qml` binds it as `midiEffectsModel`; `EditorSurfacePrompts.qml` mounts `MidiEffectsPanel` beside `ArpeggiatorPanel`; `hintScopeCovered` includes it.
- **objectNames:** `midiEffectsPanel`, `midiEffectsPluginList`, `midiEffectsRescan`, `midiEffectsCancelScan`, `midiEffectsAddFolder`, `midiEffectsFolderPicker`, `midiEffectsOpenEditor`, `midiEffectsReload`, `midiEffectsInput`, `midiEffectsPacing`, `midiEffectsPreroll`, `midiEffectsRemove`, `midiEffectsClose`.
- **Menu.** The track header menu retains action 7, "MIDI Effects...", after "Arpeggiator...", as an optional alternate entry to the direct button beneath the voice name.

### MidiEffectsPanel.qml

Task 11 owns `MidiEffectsPanel.qml`, mounted beside `ArpeggiatorPanel` in `EditorSurfacePrompts.qml`, with a shell check and contrast. The panel picks and configures the plugin: plugin list, Rescan/Cancel Scan, Add Folder/folder rows, Retry, Open Editor, Input, Pacing, Pre-roll, Remove, Close, unavailable status, and crash status with Reload (`midiEffectsReload`).

### Effect Output drawer section

Task 12 owns this section.

- **Kind and registration.** `DrawerSectionKind.effectOutput = 3` (`src/swift/document/view/EditorDrawerTypes.swift:6-14`, PorydawDocument; automation 0, velocity 1, voiceChanges 2). Stack and toggle order place it last (`stackOrder`/`toggleOrder`, same file `:33-40`). Page presenter `EffectOutputPage` (`src/swift/app/drawer/effectoutput/`) and `EffectOutputPage.qml` (`src/ui/songview/quick/drawer/`). Registration: `DocumentWorkspace` passes it to `drawer.attachSections` (`src/swift/app/DocumentWorkspace.swift:264-267`); `EditorDrawer.qml` kind/key/icon/loader switches and a `DrawerSection` instance (`src/ui/songview/quick/drawer/EditorDrawer.qml:24-70,330-420`); kind-indexed layout state and persisted preferences (`src/swift/app/drawer/EditorDrawerLayout.swift:20-24,65-79,148-162`).
- **Section header controls.** The section header gains a Live toggle, Render, Cancel Render with a determinate progress bar, Grab played, Open Editor, Reload Plug-in, Copy and Clear, all driven through `TrackEffectsController` for the selected track's effect. Reload appears for a crashed effect. Status and diagnostics lines live here too.
- **Status strings** (exact): "Live — play the song; the plugin drives this track.", "Stop playback to render", "Rendering..." (Offline), "Rendering in real time (about N s)" (Realtime only), "Rendered N notes.", "Grabbed N played notes.", "Nothing heard yet — play with Live on, then grab.", "No notes captured — try Realtime pacing.", "No source notes in range.", "Plugin unavailable: <reason>", "<name> stopped working.", "<name> stopped responding.", plus the `NormalizationReport` diagnostics line (one line of the non-zero counters, e.g. "12 notes · 3 snapped · 1 dropped before range").
- **objectNames:** `effectOutputLive`, `effectOutputRender`, `effectOutputCancelRender`, `effectOutputGrabPlayed`, `effectOutputOpenEditor`, `effectOutputReload`, `effectOutputCopy`, `effectOutputClear`, `effectOutputAddEffect`.
- **Empty state with no effect.** "No MIDI effect on this track" plus an "Add MIDI Effect..." button (`effectOutputAddEffect`) that opens the panel for the selected track through a workspace-wired callback (`DocumentWorkspace` connects `EffectOutputPage.onAddEffectRequested` to `midiEffects.open(track:)`). No second dispatcher.
- **Content.** The selected track's effect output as note rectangles on the roll camera (the `viewport.camera` precedent from the automation publications), with the pitch axis auto-fit to the output's pitch span and a range band. The other empty state (exact): "Render or grab played to see output here" (effect with no stored output).
- **Selection.** Click, shift-click, box drag, Select All; the selection is page-held, never in the document. Copy (a button, plus `roll.copy`/`roll.select_all` through `EditorCommandRouter` the way the automation section's commands go) writes a zero-span `PorydawClip` through `ClipboardSemantics.copyNotes` + `GridClipboard`. No selection copies everything. The page owns those commands only while its section body holds keyboard focus and no time selection is active; otherwise the existing automation and roll routes keep them.
- **Paste and Clear.** Paste is the normal roll paste at the edit cursor. Clear empties the effect's store entry and selection; it is session-only, with no undo.
- **Origin label** (exact): "Rendered" / "Played", plus "some notes were dropped" when degraded. Colors come from `GridPalette` pairs; geometry from the font-derived layout.

### Space and transport

The play/pause binding always reaches Porydaw, including from a focused plugin editor window (plan D6). `PluginEditorShortcuts.install` broadcasts `SetShortcuts` with the single-stroke `KeybindingRegistry().sequences("transport.play_pause")` strokes to every live helper; new helpers receive it right after `Ready`. The helper's macOS NSEvent local monitor, Windows native event filter or X11 grabs swallow matching key-downs (with repeats and key-ups) aimed at editor windows and send `Shortcut(index)`. Swift runs `ShellPresenter.activate(id: "transport.play_pause")` (`src/swift/app/shell/ShellPresenter.swift:169`). Plugin views never receive those keystrokes. The helper's top-level editor window has no cross-process owner; `RaiseEditor` brings it forward.

## Native boundary — helper-internal `pdph_` engine

Task 6 owns `src/pluginhost/pluginhost.h` and the headless engine; task 8 adds the editor half. The `porydaw_pluginhost` static library links only into the helper and the checks binary. Swift does not import this ABI. The helper and headless ABI checks use opaque handles `pdph_module`, `pdph_plugin`, `pdph_editor`. `pdph_result` is `int32_t` (`PDPH_OK = 0`, negative `PDPH_ERR_*`); `pdph_error` is `{ char message[512]; }`. No SDK types cross the ABI.

ABI constants: `PDPH_OK=0`, `PDPH_ERR_ARGUMENT=-1`, `PDPH_ERR_STATE=-2`, `PDPH_ERR_SDK=-3`, `PDPH_ERR_INTERNAL=-4`; task 8 reserves `PDPH_ERR_NO_EDITOR=-5` and `PDPH_ERR_UNSUPPORTED_PLATFORM=-6`. Event kinds are `PDPH_EVENT_NOTE_ON=0`, `PDPH_EVENT_NOTE_OFF=1`, `PDPH_EVENT_OTHER=2`. `PDPH_CTX_*` and `PDPH_RESTART_*` retain the SDK bit values unchanged.

```c
typedef struct { uint8_t uid[16]; char name[128], category[128], sub_categories[128],
                 vendor[128], version[128], sdk_version[128]; } pdph_class_info;
typedef struct { int32_t event_in, event_out, audio_in, audio_out; } pdph_bus_counts;
/* pdph_process_context, pdph_midi_event and their flags are declared in pluginbridge.h */
typedef struct { void* user;   /* plugin-chosen threads: callbacks only flip atomics / enqueue */
                 void (*end_edit)(void*, uint32_t param_id);
                 void (*restart_component)(void*, int32_t flags /*PDPH_RESTART_* = SDK RestartFlags*/);
                 void (*set_dirty)(void*, int32_t dirty);
                 void (*editor_closed)(void*); } pdph_host_callbacks;

/* main thread */
pdph_result pdph_module_open(const char* utf8_path, pdph_module*, pdph_error*);
void        pdph_module_close(pdph_module);
int32_t     pdph_module_class_count(pdph_module);
pdph_result pdph_module_class_info(pdph_module, int32_t index, pdph_class_info*);
pdph_result pdph_plugin_create(pdph_module, const uint8_t uid[16], pdph_host_callbacks,
                               pdph_plugin*, pdph_error*);
void        pdph_plugin_destroy(pdph_plugin);
pdph_result pdph_plugin_buses(pdph_plugin, pdph_bus_counts*);
pdph_result pdph_plugin_setup_processing(pdph_plugin, int32_t realtime, double sample_rate, int32_t max_block);
int32_t     pdph_plugin_latency_samples(pdph_plugin);
pdph_result pdph_plugin_set_active(pdph_plugin, int32_t active);
pdph_result pdph_plugin_get_state(pdph_plugin, int32_t which /*0 component, 1 controller*/,
                                  uint8_t** bytes, int64_t* size);
pdph_result pdph_plugin_set_state(pdph_plugin, int32_t which, const uint8_t*, int64_t);
void        pdph_free_buffer(uint8_t*);
/* helper main thread */
pdph_result pdph_plugin_set_processing(pdph_plugin, int32_t processing);
/* helper realtime processing thread, for both live and Render */
pdph_result pdph_plugin_process(pdph_plugin, int32_t frames, const pdph_process_context*,
                                const pdph_midi_event* in, int32_t in_count,
                                pdph_midi_event* out, int32_t out_capacity,
                                int32_t* out_written, int32_t* out_total);
/* main thread */
pdph_result pdph_editor_open(pdph_plugin, const char* utf8_title, pdph_editor*, pdph_error*);
void        pdph_editor_raise(pdph_editor);
void        pdph_editor_close(pdph_editor);
/* main thread: app-wide editor key interception */
pdph_result pdph_editor_set_shortcuts(const int32_t* qt_strokes, int32_t count,
                                      void (*on_shortcut)(void* user, int32_t index), void* user);
/* index = position in qt_strokes; macOS: NSEvent local key monitor; Windows: QAbstractNativeEventFilter
   on "windows_generic_MSG" (also accept dispatcher messages with the same editor-root guard);
   Linux/X11: xcb_grab_key on each editor window for every lock-modifier variant */
```

- Scanner: `porydaw-vst3-host scan <modulePath>` opens the module, lists `kVstAudioEffectClass` classes, creates each class, reads its bus counts, destroys it, and closes the module. Its only stdout output is one JSON document: `{version: 1, modulePath, classes: [{uid (32 lowercase hex), name, vendor, version, sdkVersion, category, subCategories, eventIn, eventOut, audioIn, audioOut}]}`. Exit 0 on success; non-zero with a one-line reason on stderr on load failure. It never writes files or makes policy decisions.
- Host context: `PluginContextFactory::instance().setPluginContext(host)` before `PlugProvider::initialize`. The host is a `HostApplication` subclass whose `getName` returns "Porydaw"; the SDK default is "My VST3 HostApplication".
- Instance wiring: SDK `PlugProvider` creates and connects the component and controller (connection proxies). `PlugProvider` does **not** sync state, so `pdph_plugin_create` then copies the component `getState` stream into controller `setComponentState` and installs the component handler on the controller. `initialize` failure, a missing controller, or a connection failure fails creation, with the reason in `pdph_error`.
- Buses and buffers: if `setBusArrangements` is called at all, it passes the plugin's own current arrangements — never null pointers (JUCE: "Some plug-ins will crash if you pass a nullptr to setBusArrangements!", research/hosts/juce-tracktion.md). Activation covers event buses and default-active audio buses, plus silent audio scratch buffers. Bus activation is redone after every re-setup.
- Re-setup: only on device sample-rate change, processing-mode flip, or a `kIoChanged`/`kLatencyChanged` restart (Tracktion: shutting buses down on VST3 can lose MIDI input buses irrecoverably, research/hosts/juce-tracktion.md). No needless `setActive(false)`/re-setup cycles otherwise.
- Events: `EventList` conversion.
- Parameters: `performEdit` on the UI thread enqueues to a preallocated atomic SPSC. Each `pdph_plugin_process` call acquires the published write endpoint once and consumes only that FIFO batch into preallocated `IParameterChanges` at offset 0; edits published later wait for a later call, including zero-sample idle flushes. The RT thread remains the sole consumer, with no host allocation, lock or dispatch. SDK `ParameterChangeTransfer` uses volatile rather than atomic indices (`public.sdk/source/vst/hosting/parameterchanges.h:116-117`, `parameterchanges.cpp:219-251`), so it does not establish C++ inter-thread ordering and is not used for this queue.
- Idle editor changes are flushed by the same RT parameter-queue consumer before edit publication or component state/digest reads. A parameter-only zero-sample SDK call carries no MIDI and creates no bridge request; a state snapshot before the first Render must already include the editor change.
- Allocation: parameter-change storage is prepared at creation for idle flushes; audio/event buffers and `EventList`s are prepared at setup and cleared per block. Porydaw's own processing path is allocation-free after warmup.
- Latency: read on the main thread only after `setup_processing`, and again after every re-setup.
- Destroy: Porydaw awaits control-owned callback-excluded detachment before reclaiming the slot or shutting down its helper. No host lock is entered on any audio-thread path, including callback handling; no callback fires after destroy returns.
- Callback integrity: exhaustion of the helper's bounded callback queue sets a sticky atomic failure; enqueue never logs, allocates or dispatches. When the main-thread drain observes that failure it writes a concrete stream-integrity reason to stderr and stops the helper with nonzero status, rather than clearing the fault or publishing a log-only healthy state. Existing EOF/termination handling and manual Reload own recovery; there is no additional wire message or automatic restart.
- Output events: note offs pair by `noteId`, else FIFO per pitch. Overlapping same-pitch notes keep distinct `noteId`s (JUCE drops them to plain MIDI; we do not, research/hosts/juce-tracktion.md).
- Editor (task 8): a recursive-resize guard applies a constrained size only when it differs (JUCE); `IPlugViewContentScaleSupport` sets the content scale on Windows/Linux; Linux `IRunLoop` maps to `QSocketNotifier` + `QTimer` (ossia, MuseScore and Qtractor precedent, research/hosts/qt-hosts.md).
  Editor control requests are decoded by the helper's canonical `Payload` parser and call editor operations directly; every helper links editor support, with only Linux run-loop initialization retained in editor setup. Result-returning editor exports contain exceptions as `PDPH_ERR_INTERNAL`, initialize output handles before work, and preserve available diagnostics. A newly created `IPlugView` is owned before window construction; failed opens retain their original result while no-throw detach independently attempts shortcut/window refresh, `removed()`, frame reset, view release and close notification. An attempted attachment is removed even if `attached()` throws or fails. Programmatic close never emits user-close; native user-close emits it once, including when cleanup throws.
  On macOS, `refreshMacEditorWindows()` owns one main-queue workspace activation observer only while live editors exist and enumerates current attached handles, without a second window registry. Refresh after showing an opened editor, after detach clears its plugin, and on explicit raise/show applies the current foreground policy. Foreground ownership means the helper itself, its captured direct parent PID, or the same helper executable with that parent PID verified through `proc_pidinfo(PROC_PIDTBSDINFO)`; query failure and another Porydaw instance are not verified family members. Use `NSFloatingWindowLevel` for that family and `NSNormalWindowLevel` plus nonactivating back-ordering for unrelated apps. Activation notifications use their supplied application, not a potentially stale frontmost property. Ordering never activates, changes key/main windows, shows hidden windows or deminiaturizes editors; shortcut interception remains separate. Windows/Linux ordering and the wire/C ABI are unchanged.

In the helper, setup, activation, bus activation, latency, state and `setProcessing` calls run on the Qt main thread; `process` runs on the helper RT thread, never concurrently for live and Render. Live setup is `kRealtime`, device rate, max block 1024; Render is `kOffline`, 48 kHz, max block 256. A re-setup is `set_active(0)` → `setup_processing` → latency read → `set_active(1)`, never while active. Swift decides policy and context.

## Swift host (PorydawPluginHost) — `src/swift/pluginhost/`

Depends on PorydawCore, PorydawPlayback (insert slot and event types) and the `PorydawPluginBridge` C module, with no C++ interop or SDK linkage.

- `HelperProcess.swift` (task 13) launches one helper, frames controls, correlates replies, applies control timeouts and reports termination and stdout EOF.
- `BridgeChannel.swift` (task 13) owns shared memory, RT post/wait and sequence handling as specified in Plugin bridge.

- `PluginCatalog` (`@MainActor`).
  - API: `init(cacheDirectory: URL, scannerURL: URL)`; `func scan(folders: [String], force: Bool = false) async`, which enumerates the roots (stat only) on every call and launches `porydaw-vst3-host scan <modulePath>` through Foundation `Process`, one child per module, in parallel up to `min(4, activeProcessorCount)`, with a 10 s timeout per module: with `force: false` only for new or changed modules (path+mtime+size), dropping entries whose module is gone; with `force: true` for every module, re-probing cached successes. Blocked entries are re-probed only through `retry(modulePath:)`/`retryAll()` or `force: true`. Entries publish progressively as each child finishes; `isScanning` covers the run and the list stays usable. `cancelScan()` stops launching new children and terminates running ones at the next module boundary; `entries: [PluginCatalogEntry]`; `entry(modulePath:classUID:) -> PluginCatalogEntry?`; `retry(modulePath:)` clears one block; `retryAll()` clears all.
  - Entries: `{ modulePath, classUID: [UInt8] (16), name, vendor, version, isMidiProducer, blockedReason: String? }`; `isMidiProducer` means `event_out ≥ 1`. The panel list shows only `isMidiProducer` entries, plus blocked entries (capability unknown) shown distinct with Retry. Plugins without MIDI output are hidden.
  - Roots and cache: Swift supplies the platform standard VST3 paths plus user folders, without loading the SDK. macOS: `~/Library/Audio/Plug-Ins/VST3`, `/Library/Audio/Plug-Ins/VST3`, `/Network/Library/Audio/Plug-Ins/VST3`, and app bundle `Contents/VST3`. Windows: `FOLDERID_UserProgramFilesCommon/VST3`, `FOLDERID_ProgramFilesCommon/VST3`, and app directory `VST3`. Linux: `$HOME/.vst3`, `/usr/lib64/vst3`, `/usr/lib/vst3`, `/usr/local/lib64/vst3`, `/usr/local/lib/vst3`, and app directory `vst3`. A `.vst3` bundle or file is a module. Results are cached in `cacheDirectory/PluginCatalog.json`, keyed by module path, modification date and size; both successful entries and blocked entries persist there.
  - Containment: a crash, non-zero exit, timeout or unparseable output blocks the module with a reason: "Porydaw's plugin scanner crashed while loading this plugin.", "Loading this plugin took longer than 10 seconds.", or "The plugin could not be loaded: <stderr line>." On timeout the child is terminated. If the scanner executable is missing, `scan` fails with "Plugin scanner is missing from this installation." There is no in-process fallback.
- `PluginInstance` (`@MainActor`) owns its `HelperProcess` and `BridgeChannel`; all plugin operations use control messages or the bridge.
  - Members: `init(entry:) throws` (lazy helper startup), `buses`, `state() async throws -> PluginStateBlob`, `restore(_ state: PluginStateBlob) async throws`, `stateDigest() async -> UInt64?` (requests helper `GetStateDigest`), `onEdit: (() -> Void)?`, `needsSetup`, `shutdown() async` (the lifecycle ordering above; idempotent), and `deinit`, which asserts that shutdown happened. Control IPC never blocks the main actor.
  - `PluginHostError` distinguishes `.stoppedResponding(String)` from `.native(String)`, preserving diagnostic text. Watchdog and control-request timeouts normalize to the typed hang case; EOF and abrupt termination remain native failures. `init(bridging:)` preserves classified errors and lifts unclassified errors to `.native` with the original diagnostic; transport classification and App-facing recovery wording retain their separate owners. Consumers switch on the type, never diagnostic substrings.
  - `onEdit` fires on `end_edit`, `set_dirty(1)` and the `restart_component` parameter-value/title flags (`kParamValuesChanged`, `kParamTitlesChanged`, `kMidiCCAssignmentChanged`). The latency/IO flags (`kLatencyChanged`, `kIoChanged`) advance the setup invalidation revision; `kReloadComponent` recreates the instance and clears its configured setup. `needsSetup` derives from absent configuration or a configured revision differing from the current invalidation revision.
  - Restore through the helper while live processing continues, then flag an input discontinuity. Cancel and await an in-flight Render before restore, superseding its result. The helper applies component state first (`IComponent::setState` → `IEditController::setComponentState` with the same bytes), then controller `IEditController::setState`. State reads on the helper main thread never become a second consumer of the processing thread's parameter SPSC.
  - Task 8 adds `openEditor(title:) async throws`, `closeEditor() async`, `isEditorOpen` and `onEditorClosed`, routed through `HelperProcess`; opening an already open editor sends `RaiseEditor`. Lifecycle consumers await close before shutdown; synchronous UI slots launch owned, generation-guarded tasks rather than blocking.
- `CaptureRequest` is `{ timeline: PlaybackTimeline, track: Int, range: TimeRange, input: EffectInput, pacing: EffectPacing, prerollBars: Int }`.
- `CaptureTransport` is pure, with no C import, at 48 000 Hz with 256-frame blocks. It maps samples to ticks through the timeline tempo map, using the same segment math as `PlaybackTimeline` (`src/swift/core/PlaybackTimeline.swift:220,230` for `sample(for:)`/`tick(for:)`). It produces per-block context values: `ppq = tick/ticksPerBeat`, tempo of the segment containing the block start, meter at the block start, bar start in quarters, and cycle = the capture range. `PLAYING|CYCLE_ACTIVE|CYCLE_VALID|TEMPO_VALID|TIME_SIG_VALID|PROJECT_TIME_MUSIC_VALID|BAR_POSITION_VALID` is set on every block. Pre-roll starts `prerollBars` bars before the range, clamped at tick 0. Input notes that overlap `[prerollStart, range.end)` become note on/off events with positive note ids. A note already sounding at pre-roll start begins at block 0, offset 0.
- `CaptureDriver`: one dedicated `Thread` per `PluginInstance`, with an `NSCondition` mailbox.
  - API: `func render(_ request: CaptureRequest, progress: @escaping @MainActor (CaptureProgress) -> Void) async throws -> CaptureResult` (where `CaptureResult = { events: [RawNoteEvent], nonNoteEvents: Int }` and `CaptureProgress = { fraction: Double }`), `cancel()`, and `func idle() async`, which returns once the worker is not processing.
  - Setup: on first use, after invalidation, or when the requested realtime flag, sample rate or period changes, the main actor re-runs the inactive re-setup sequence. After stopping processing, it captures the revision and clears the old configured setup immediately before awaiting deactivation/setup/activation/latency. Failure or interruption leaves it unconfigured; success stores the captured revision with the request key, never the revision at completion, so a restart during reconfiguration still requires setup again. Pacing remains a request/execution choice, not a result field.
  - Worker: requests `SetProcessing(1)` through the main actor, runs the block loop over `BridgeChannel`, then requests `SetProcessing(0)`; the helper executes all VST3 calls.
  - Outputs: shifted earlier by the latency, clamped at pre-roll start. Each output's block start plus `sample_offset` converts to a tick. `OTHER` events and overflow (`out_total − out_written`, with a 4 096-event buffer) count as `nonNoteEvents`. Capture results retain all raw note events, including preroll and latency-tail events: only Core pairs them, snaps them and rejects out-of-range note pairs. Dropping an onset before pairing while retaining its off would corrupt ID-less FIFO overlaps across the range boundary.
  - Progress: both pacings publish percentage-only progress on the main actor at each completed bar, without cumulative note snapshots. `.realtime` sleeps to wall clock per block.
  - Cancellation: a cancel flag is checked between blocks. A render request supersedes an in-flight one, and superseded results are discarded.

### LiveInsert and LiveTake — `src/swift/pluginhost/`

Task 7 implements `LiveInsert` and `LiveTakeRing` as specified in "Live insert (audio callback)". The insert owns callback-side buffers, context conversion and the input-held ledger; it uses task 4's slot and event types and task 13's `BridgeChannel`. It maps velocity > 0 to 1…127, treats zero as off, clamps pitch to 0…127 and pairs output by note ID, with FIFO-per-pitch fallback when an ID is absent. The sequencer owns the output-held ledger and reports which notes were dispatched.

Offline input remains in `CaptureInput` domain records through the capture worker. `LiveInsert` owns the single held-note ingest and domain-to-wire encoding operation shared by the live and offline adapters; the worker does not pre-encode native events.

`LiveTake` is a main-thread value of `RawNoteEvent`s whose ticks were resolved against the callback's applicable timeline. Its `commitSegment(span:events:)` replaces earlier events whose onsets fall in the span, appends the new segment and closes open notes at a segment end. A 50 ms drain consumes ordered note, completed-position and boundary records from `LiveTakeRing`; it never reinterprets an old sample using a newly adopted timeline. Ring overflow and the 65 536-event cap are the only degradation causes.
Grab range snapping, normalization and publication belong only to the App's `TrackEffectsController`/`PluginEffectRenderer` path, not to the raw take accumulator.

### Limits — snapshot undo (accepted risks)

Task 9 owns this section.

- A plugin that does not fully restore from its own `getState` blob gives a partial undo, with no detection.
- History holds the before/after blobs, so large plugin states make undo memory heavier.
- Cmd-Z typed inside the plugin window still goes to the plugin's own undo, if it has one. Those plugin-side changes are then detected like any edit and become Porydaw steps too.
- Precedent: Tracktion `ExternalPlugin::flushPluginStateToValueTree` stores plugin state through its UndoManager (research/hosts/juce-tracktion.md).

## Non-goals

Persisting Effect Output; the arpeggiator as a track effect (it keeps its own panel, Copy Notes and solo audition, and is not a track-effect kind); effect chains or more than one effect per track; CC or pitch-bend output into lanes (counted as `nonNoteEvents`); forwarding the song's CC, pitch bend or program changes into a plugin; playing a MIDI keyboard or other live MIDI input into a plugin; editing output notes except by pasting them into real tracks; plugin parameter UI inside Porydaw; presets; importing MIDI dragged out of a plugin; backups of the sidecar (backups keep only the `.mid`); AU/CLAP/AAX; joining the CoreAudio IO workgroup (`os_workgroup_create_with_port` requires a Mach send right passed to the child, and Porydaw has no Mach-port channel).
