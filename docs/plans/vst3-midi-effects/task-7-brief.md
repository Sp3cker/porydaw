# Context
Extend the Swift hosting module: discovery and scan containment, helper-backed instance lifecycle, offline capture on the worker, and the live callback insert. Task 8 adds the editor; task 9 owns arming, Render and Grab played. Offline input is a `PlaybackTimeline` value plus track notes, not a `SongSnapshot`. The take only feeds Grab played. Read plan.md Global Constraints and spec.md "Swift host" and "Live insert (audio callback)".

# Exact write set
- `src/swift/pluginhost/CMakeLists.txt` (extend task 13's `PorydawPluginHost` module: links `PorydawCore`, `PorydawPlayback` and `PorydawPluginBridge`, no C++ interop)
- `src/swift/pluginhost/PluginCatalog.swift`
- `src/swift/pluginhost/PluginInstance.swift`
- `src/swift/pluginhost/CaptureTransport.swift` (pure over `PlaybackTimeline`)
- `src/swift/pluginhost/CaptureDriver.swift`
- `src/swift/pluginhost/LiveInsert.swift`
- `src/swift/pluginhost/LiveTakeRing.swift`
- `src/swift/pluginhost/LiveTake.swift`
- `src/checks/pluginhost/PluginHostChecks.swift` (new; `@MainActor public func runPluginHostChecks(_ report: CheckReport)`)
- `src/checks/pluginhost/PluginCatalogChecks.swift` (catalog slice called by the same host suite)
- `src/swift/pluginhost/HelperProcess.swift` (existing `HelperBuses` and immutable fields become public; no duplicate bus model)
- `src/checks/vstfixture/porydawtestgen.cpp` (controller-assigned native slice: fault code 3 is one healthy 100 ms delay; fault-word bit 30 enables the 112-byte SDK-observation controller snapshot, preserving the 16-byte component format and byte 8 for task 8's `keysReceived`)
- `src/swift/playback/live/LiveInsertSlot.swift`, `src/swift/playback/Sequencer.swift`, `src/checks/playback/LiveInsertChecks.swift` (bounded root correction: one shared take-event type, exact completed positions and explicitly flagged discontinuity releases; migrate all consumers)
- `docs/BUILDING.md`: add PorydawPluginHost to the module notes (depends on PorydawCore + PorydawPlayback + `PorydawPluginBridge`; PorydawApp never imports the engine ABI or links the SDK), with the edit-floor numbers from implementation step 8

Registration (controller): task-9 owner link. New suite `swiftcore-pluginhost` (lane links PorydawPluginHost; the fixture is resolved beside the check executable). Task 13 registers the module subdirectory.
The endpoint correction also requires `uv run --no-sync dev checks --filter swiftcore-playback`. Controller registrations include the host module source list and the existing core-check suite dispatch/catalog.

# Prerequisites
Task 1 (`RawNoteEvent`, `NewNote`, normalizer and lattice), task 2 (effect model), task 4 (Playback slot, input/output event types and per-call flags), task 13 (`HelperProcess`, `BridgeChannel` and fixture). No `SongSnapshot` exists or is used.

# Interface contract
Exactly spec.md "Swift host". Additions only where the spec is silent:
- `CaptureRequest` is `{ timeline: PlaybackTimeline, track: Int, range: TimeRange, input: EffectInput, pacing: EffectPacing, prerollBars: Int }`. Input notes are the timeline's events for `track` overlapping `[prerollStart, range.end)`; a note already sounding at pre-roll start begins at block 0, offset 0.
- `CaptureTransport` is pure at 48 000 Hz with 256-frame blocks, mapping through the timeline tempo map with the same segment math as `PlaybackTimeline`. Per-block contexts and flags, latency shift, `OTHER`/overflow counting into `nonNoteEvents`, pre-roll onset drops, and per-bar progress (`.realtime` sleeps to wall clock and includes events so far) are per spec.
- `CaptureDriver` uses `BridgeChannel` and keeps the `render(_:progress:) async throws -> CaptureResult` / `cancel()` / `idle()` API (`CaptureResult = { events: [RawNoteEvent], nonNoteEvents: Int, pacing }`). The main actor re-runs setup via `HelperProcess` on first use, when `needsSetup` is set, when pacing changed, and when the realtime flag or sample rate changed (re-setup sequence only, never setup while active). A render supersedes an in-flight one; superseded results are discarded; `render` throws `CancellationError` when cancelled or superseded, `PluginHostError.native(String)` on host failures.
- **Exclusivity.** Render uses the bridge on its worker only while live is detached; the callback uses it for live. Render waits up to 10 s per request; a timeout kills the helper and fails Render with crash status. Render while armed and playing is refused with "Stop playback to render". While armed and stopped the controller detaches, stops processing, re-setups offline, renders, then re-setups realtime and re-attaches, including after cancellation or failure if still armed and active.
- **`LiveInsert`.** Implement task 4's C-convention slot over `BridgeChannel` with preallocated input/output/event buffers. Once per callback chunk (≤ 8192 frames, split at loop end), send its inputs and context and wait at most `max(1 ms, 0.5 × chunk duration)`; the helper sub-blocks into plugin blocks ≤ 1024. A timeout returns `missed`; if an older request is outstanding, return `missed` immediately without posting or waiting; ignore stale replies. Stopped callbacks run with `kPlaying` clear. Build context from actual transport, position and timeline: ppq, tempo, meter, bar start and loop. No live preroll; no live latency compensation.
- **Input.** Apply the spec's input rule to live and Render: only track note on/off, channel 0, velocity / 127 and positive paired note IDs; no CC, bend or program. A check exercises the scheduler with mixed events and the fixture verifies echo. Keep a counted input-held ledger; on seek, stop, wrap, timeline adoption, arm, restore or pattern return send an off for each held count at offset 0 of the next block, then chase sounding notes at offset 0. At loop wrap offs precede chased ons at offset 0 of the first wrapped block, both using the new loop context; retain exact boundary timing and one bridge request per chunk. Never depend on CC123.
- **Output and take.** Return chunk-relative output notes with their IDs, treating velocity-zero NoteOn as off and mapping positive velocity to 1…127. Pair by ID, else FIFO per pitch; task 4's output-held ledger decides which notes actually dispatch. `LiveTakeRing` is a preallocated 8192-entry callback→main SPSC carrying one `LiveTakeEvent` type with `note`, `position` and `boundary` kinds. Sequencer emits completed-chunk sample/tick positions on the old applicable timeline before wrap/adoption, even for silent chunks, and explicitly flags discontinuity-generated release notes. On overflow drop/count entries and mark degraded, never wait. No Swift array append on the callback.
- **`LiveTake`.** Main thread drains the ring on the owner's 50 ms armed timer, commits segments with span replacement and closes old open notes at the last authoritative completed position, including silent tails. Explicitly flagged discontinuity releases must not extend the old segment to a seek/adoption's new tick. Boundaries then start the new segment; zero-duration intermediate boundaries commit no span. Position records are not notes and Grab does not depend on a later main-thread transport snapshot. Cap 65 536 events; ring overflow and the cap alone mark degraded. Grab normalizes its span snapped outward to bars.
- **`PluginInstance`.** Owns one lazily spawned `HelperProcess` and its `BridgeChannel`; provide `init(entry:)`, `buses`, `state()`/`restore()`, `stateDigest()` via helper `GetStateDigest` (FNV-1a over component bytes), `onEdit`, `needsSetup`, idempotent `shutdown() async`, and deinit assertion. Restore through control frames while live processing continues, then set the atomic input-discontinuity flag; cancel and await a Render before restoring, superseding its result. Detach before shutdown. Main hops hold weak instance and generation guards.

# Implementation steps
1. **`PluginCatalog`.** `scan(folders:force:)` enumerates `.vst3` entries in the spec's Swift-owned platform-standard roots plus user folders (stat only, no bundle recursion) on every call and publishes entries progressively as each child finishes; `isScanning` covers the run and the list stays usable. With `force: false` launch one `porydaw-vst3-host scan <modulePath>` child per new or changed module (path+mtime+size) and drop entries whose module is gone; with `force: true` re-probe every module, ignoring cached successes. Blocked entries re-probe only through Retry/Retry all or `force: true`. Children run through Foundation `Process`, in parallel up to `min(4, activeProcessorCount)`, with a 10 s timeout per module. Crash, non-zero exit, timeout or unparseable output blocks the module with the spec reason; on timeout terminate the child. Cache successful and blocked entries in `PluginCatalog.json` keyed by path, mtime and size. `retry(modulePath:)`/`retryAll()` clear blocks; `cancelScan()` stops new launches and terminates running children at module boundaries. If the helper executable is missing, `scan` fails with "Plugin scanner is missing from this installation." Yield between modules; sort by name.
2. **`PluginInstance`.** Helper lifecycle, `GetStateDigest`, event marshalling per contract. Setup gains the realtime flag and sample rate; mode/rate flips re-run setup via control frames.
3. **`CaptureTransport`.** Pure segment math over the request timeline; per-block contexts, input scheduling, sample/tick conversion per spec.
4. **`CaptureDriver`.** Main-actor setup, worker job loop, supersede-and-cancel mailbox, realtime deadline against a `ContinuousClock`, results resumed on the main actor.
5. **`LiveInsert` and `LiveTakeRing`.** Implement the slot, context, one bounded bridge round trip per chunk and event conversion, discontinuity-held ledger, dispatch feedback and preallocated SPSC.
6. **`LiveTake`.** Main-side 50 ms drain, timeline conversion, segment replacement, cap and degraded flag.
7. **Checks:**
   - fixture scan finds the 3 MIDI producers (`TestAudioOnly` scanned but hidden from the panel list path); `porydawtestcrash` is blocked with the crash reason and the check process survives; `porydawtesthang` is blocked after the timeout (inject a short timeout for the check) and the child is terminated; `retry`/`retryAll` clear blocks; a second scan after adding a fixture module launches exactly one child, a removed module's entry disappears, `force: true` re-probes all, and an unchanged second scan launches none; a missing scanner gives the exact error;
   - transport golden contexts over a timeline: 120->90 BPM change mid-range, 3/4 bar starts, pre-roll clamped at tick 0, sample<->tick round trip within 1 sample;
   - offline `TestGen` render normalized via `EngineNoteNormalizer` equals a golden `[NewNote]`; normalized preroll onsets are dropped after Core pairing, including ID-less same-pitch overlaps across the range boundary; raw capture retains their matching context; `.trackNotes` echo present; CC counted in `nonNoteEvents`;
   - `TestGenAudio` aligns with `TestGen` after latency compensation, including after a latency state change (`needsSetup`);
   - `TestGenRealtimeOnly` empty offline, non-empty realtime; progress partial at bar end; cancel mid-realtime throws within 100 ms and next Render succeeds; shutdown waits for idle and discards completion; post-shutdown hop no-ops; state round-trip changes pitch; restore during Render cancels and supersedes it;
   - scripted fixture chunks through `LiveInsert` match offline capture of the same range within one sample with preroll 0 and zero reported latency; overlapping same-pitch IDs pair correctly; timeout or an older outstanding request returns `missed`, and stale replies are ignored;
   - all input discontinuities flush every held count before chase, including repeated same-key notes; seek, loop-end wrap, adoption, arm, restore, stop and pattern return leave no stuck echo;
   - contexts reflect playing, stopped and loop; helper blocks are ≤ 1024 frames, chunks split at loop end, and stopped callbacks keep processing;
   - take-ring overflow drops/counts and marks degraded; main drain preserves span replacement and the 65 536 cap;
   - check no host allocation on insert path after warmup using the existing Darwin `malloc_logger` counting pattern (`src/checks/projectstore/VoicegroupParityChecks.swift:80-100,117-165`), honoring its ASAN/platform availability; do not invent another mechanism;
   - Render refused while armed and playing, allowed stopped with detach/re-setup/re-attach and no concurrent processing.
8. Measure PorydawApp's one-file edit floor with the "Swift incremental floor" procedure in docs/BUILDING.md, before and after this task, and record both numbers there.

# Acceptance predicate
All checks pass. NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-pluginhost`
- `uv run --no-sync dev checks --filter swiftcore-pluginhost-abi`: regression.
- `uv run --no-sync dev lsp:swift`

# Task-specific constraints
- Every SDK call runs in the helper; Porydaw's main actor sends control frames. Render and Live use the same channel exclusively, never concurrently.
- The worker never touches `SongDocument`; it reads only the capture request timeline and fields.
- `@unchecked Sendable` only for audited cross-thread handle, insert or ring ownership, each with a 2-line invariant comment.
- Porydaw's callback-side code allocates, locks and dispatches nothing; its only deliberate blocking call is the bounded bridge reply wait.
