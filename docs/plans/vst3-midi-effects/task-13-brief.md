# Context

Build the per-instance out-of-process VST3 bridge. Task 7 consumes `HelperProcess` and `BridgeChannel`; task 8 adds editor and shortcut control; task 9 wires crash and hang handling. Read plan.md Global Constraints and spec.md process model, wire format and RT protocol.

# Exact write set

- `src/pluginhost/pluginbridge.h` (new): SDK-free C wire format and wait/wake API
- `src/pluginhost/scanner/scanner_main.cpp`: dispatch scan and host modes from the existing executable entry point
- `src/pluginhost/helper/host.h` (new): helper-private host and control interfaces
- `src/pluginhost/pluginbridge_wait.c` (new): shared-memory lifecycle and cross-process wait/wake
- `src/pluginhost/bridge.modulemap` (new): `PorydawPluginBridge` C module
- `src/pluginhost/pluginhost.h`: move shared POD definitions into `pluginbridge.h` and include it
- `src/pluginhost/helper/host_main.cpp` (new): helper host mode, Qt main thread and stdin reader
- `src/pluginhost/helper/host_rt.cpp` (new): helper processing thread, priority and chunk sub-blocking
- `src/pluginhost/helper/host_control.cpp` (new): control dispatch, replies and events
- `src/pluginhost/helper/host_mac.mm` (new): macOS accessory activation policy
- `src/pluginhost/CMakeLists.txt`: helper host sources, wait/wake, platform dependencies and Qt6::Gui linkage (output location and packaging are task 6's)
- `src/swift/pluginhost/CMakeLists.txt` (new): `PorydawPluginBridge` module target and `PorydawPluginHost` Swift module
- `src/swift/pluginhost/HelperProcess.swift` (new): process and control channel; `static var executableURL: URL` per spec.md "Build and packaging"
- `src/swift/pluginhost/BridgeChannel.swift` (new): shared-memory RT channel
- `src/checks/pluginhost/BridgeChecks.swift` (new): real-helper bridge checks

Registration (controller): new suite `swiftcore-pluginbridge`, CMake source lists and module subdirectory.

# Prerequisites

Task 6 (`pdph_` engine, scan-mode helper with its build and packaging, and the fixture's `fault` state field). Task 6 initially defines the shared POD types in `pluginhost.h`; this task moves them into `pluginbridge.h` and makes `pluginhost.h` include that header.

# Interface contract

- **Wire format.** `pluginbridge.h` has no SDK includes. Move `pdph_midi_event`, `pdph_process_context`, `PDPH_EVENT_*` and `PDPH_CTX_*` without changing their ABI. Define `PDPB_VERSION 1`, `PDPB_MAX_EVENTS 4096`, `PDPB_MAX_CHUNK 8192` and `pdpb_shared`: magic/version, atomic `request_seq`, `reply_seq`, request/reply wait words, atomic 64-bit `heartbeat`; request `frames`, `ctx`, `in_count`, `in[4096]`; reply `status`, `out_written`, `out_total`, `out[4096]`, with chunk-relative output offsets.
- **Wait/wake.** Implement `pdpb_channel_create(name, out)`, `pdpb_channel_open(name, out)`, `pdpb_channel_close`, `pdpb_post_request`, `pdpb_wait_reply(timeout_us)`, `pdpb_wait_request(timeout_ms)` and `pdpb_post_reply`. Compile the C implementation into the bridge module target and helper. macOS uses `shm_open`/`mmap` and `os_sync_wait_on_address_with_timeout` / `os_sync_wake_by_address_any` with `OS_SYNC_WAIT_ON_ADDRESS_SHARED` / `OS_SYNC_WAKE_BY_ADDRESS_SHARED`; Linux uses `shm_open`/`mmap` and non-private futexes; Windows uses named `CreateFileMappingW`, named `CreateSemaphoreW` / `OpenSemaphoreW` and `WaitForSingleObject`, with `Local\porydaw-<pid>-<n>-{shm,req,rep}` names. Unlink POSIX shm after `Ready`.
- **Control.** `HelperProcess` launches `porydaw-vst3-host host --channel <name>`, uses little-endian `[u32 type][u32 requestId][u32 length][payload]` frames on stdin/stdout, matches replies by request ID, reports termination and EOF, and waits 5 s per request or 30 s for `CreatePlugin`. Support `CreatePlugin(modulePath, classUID[16])`, `SetupProcessing(realtime, sampleRate, maxBlock, periodFrames)`, `SetActive(on)`, `SetProcessing(on)`, `GetState(which)`, `SetState(which, bytes)`, `GetStateDigest`, `GetLatency`, `OpenEditor(title)`, `RaiseEditor`, `CloseEditor`, `SetShortcuts(strokes[])` and `Quit`; replies carry request ID and `ok`/`error(text)` plus payload. Events are `Ready(version)`, `EndEdit(paramId)`, `RestartComponent(flags)`, `SetDirty(on)`, `EditorClosed`, `Shortcut(index)` and `Log(text)`. Task 8 implements the editor and shortcut actions. `GetStateDigest` is FNV-1a 64 over component state; full state gets component and controller, restores component then controller.
- **RT.** `BridgeChannel` posts one request per chunk and ignores mismatched late replies. A live wait is bounded by `max(1 ms, 0.5 × chunk duration)`; timeout returns `missed`, and an outstanding request immediately misses without another post or wait. Render uses the detached channel with a 10 s wait. Task 14 supersedes worker-side termination: return a distinct typed timeout and let the MainActor helper owner record stopped-responding before killing the helper or awaiting Render cleanup. Preserve the armed watchdog: no completed request or stalled heartbeat for 2 s declares a hang.
- **Helper.** Host exactly one plugin per process. Qt main handles control dispatch, editor windows, Linux `IRunLoop` and key interception; a stdin reader posts frames to it by queued invoke; EOF exits the helper. The RT thread wakes at least every 100 ms while idle, increments heartbeat each iteration, sub-blocks each chunk into plugin blocks ≤ 1024 frames, and returns one reply. Set macOS `THREAD_TIME_CONSTRAINT_POLICY` period to `periodFrames` / rate, Windows MMCSS `AvSetMmThreadCharacteristicsW(L"Pro Audio")`, Linux `SCHED_FIFO` priority 80 then `SCHED_RR` then normal. On macOS set `NSApplicationActivationPolicyAccessory` at startup. Preserve scan mode and JSON contract.

# Implementation steps

1. Move the task-6 POD definitions; implement the shared layout, platform primitives, module map and CMake linkage without importing SDK types into Swift.
2. Add helper host mode, Qt main/control dispatch, RT chunk processing and priority, EOF exit and macOS activation policy. Package the same executable as scan mode.
3. Create the Swift module, `HelperProcess` control lifecycle, `BridgeChannel` sequence/wait handling and the reusable armed watchdog; task 9 owns the controller response.
4. Add real-helper fixture checks, setting the fixture's fault field with `SetState`: create and Ready; input echo in a process round trip; state get/set, changed digest and latency; `Fault=1` termination and reported reason; `Fault=2` bounded `missed`, immediately missed busy channel and watchdog kill within 2 s; stdin close exits; stale sequence ignored; POSIX shm unlinked after Ready.

# Acceptance predicate

All real-helper checks above pass in Debug and ASAN. NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-pluginbridge`
- `uv run --no-sync dev build:checks --asan && uv run --no-sync dev checks --asan --filter swiftcore-pluginbridge`

# Task-specific constraints

- Audio-thread functions in `pluginbridge_wait.c` and `BridgeChannel` never allocate or lock; only the bounded reply wait blocks.
- Shared-memory and Windows object names are unique per pid and instance. One helper hosts one instance; no SDK link or module load in Porydaw's process.
