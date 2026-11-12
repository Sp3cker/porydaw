# Context
Implement the in-helper VST3 engine behind the `pdph_` C ABI: module loading, class enumeration, instances, processing and state. Add deterministic fixtures and headless ABI checks in the checks process. Task 13 builds the bridge and helper host mode; task 7 owns offline capture, `LiveInsert` and `LiveTake`; task 8 adds the editor. Read plan.md Global Constraints and spec.md "Native boundary".

# Exact write set

- src/pluginhost/pluginhost.h: spec ABI without the editor half; define `pdph_midi_event`, `pdph_process_context`, `PDPH_EVENT_*` and `PDPH_CTX_*` here initially. Task 13 moves these POD types and constants into `pluginbridge.h` and makes this header include it.
- src/pluginhost/pluginhost.cpp: modules, factory, `PlugProvider` instances, host application, component handler, parameter queue, state
- src/pluginhost/pluginhost_process.cpp: setup, activation, processing, event conversion
- src/pluginhost/pluginhost_internal.h: controller-authorized private declarations shared by the two implementation translation units; no `.cpp` inclusion.
- src/pluginhost/module.modulemap: `module PorydawPluginHostNative { header "pluginhost.h" export * }`
- src/pluginhost/scanner/scanner_main.cpp (new): `porydaw-vst3-host scan <modulePath>` prints one JSON document per spec
- src/pluginhost/CMakeLists.txt: target `porydaw_pluginhost` (static, linking `porydaw_vst3_sdk` PRIVATE), linked only by `porydaw-vst3-host` and the checks binary; the helper executable's output directory, Apple bundle copy (`POST_BUILD` into `$<TARGET_BUNDLE_CONTENT_DIR:porydaw>/MacOS`), `WIN32_EXECUTABLE` and Windows install rule, exactly per spec.md "Build and packaging"
- CMakeLists.txt (root): `add_dependencies(porydaw porydaw-vst3-host)` after `qt_add_executable(porydaw)` (`:548`), the first point where both targets exist; the helper's Apple `POST_BUILD` creates `Contents/MacOS` first, because it builds before the bundle
- `.github/workflows/release.yml`: macOS `macdeployqt -executable=` for the helper, Linux `linuxdeploy -e build/porydaw-vst3-host`, and a packaged-helper `scan` start check in the macOS, Linux and Windows jobs (Windows: `Start-Process -Wait -PassThru`, since a GUI-subsystem exe does not block `&`)
- `.github/workflows/build.yml`: the same macOS `-executable=` and packaged-helper start checks, and the Linux artifact upload adds `build/porydaw-vst3-host`
- src/checks/vstfixture/CMakeLists.txt (new) and src/checks/vstfixture/porydawtestgen.cpp (new)
- src/checks/vstfixture/porydawtestcrash.cpp (new): a `porydawtestcrash.vst3` fixture that aborts inside `GetPluginFactory`
- src/checks/vstfixture/porydawtesthang.cpp (new): a `porydawtesthang.vst3` fixture that sleeps forever there
- src/checks/pluginhost/PluginHostABIChecks.swift (new; `public func runPluginHostABIChecks(_ report: CheckReport)`)

Registration (controller): `add_subdirectory(vstfixture)` in `src/checks/CMakeLists.txt`, plus dependencies of `porydaw_checks` and the QML check hosts on `porydaw-vst3-host` and the fixture targets. The ABI check file goes into a check lane importing `PorydawPluginHostNative`. New suite `swiftcore-pluginhost-abi` across `core_check.h`, `tst_swiftcore.cpp`, `checkcatalog.cpp` and `CoreCheckDispatch.swift`.

# Prerequisites
Task 5 (`porydaw_vst3_sdk`, vendored `external/vst3sdk`).

# Interface contract
Exactly spec.md "Native boundary" minus the editor half (task 8 adds the editor in the helper), plus the mechanics below:
- **Signatures and threading.** Setup, activation, bus activation, latency and state run on the helper's main thread. `process` runs on its processing thread for live and Render, never concurrently. Setup and `set_processing` run through the helper's control path. Document each rule in the header.
- **Errors.** Errors fill `pdph_error.message` with the SDK/loader reason. Null handles return `PDPH_ERR_ARGUMENT`.
- **ABI constants (controller ruling).** `PDPH_OK=0`, `PDPH_ERR_ARGUMENT=-1`, `PDPH_ERR_STATE=-2`, `PDPH_ERR_SDK=-3`, `PDPH_ERR_INTERNAL=-4`; reserve `PDPH_ERR_NO_EDITOR=-5` and `PDPH_ERR_UNSUPPORTED_PLATFORM=-6` for task 8. `PDPH_EVENT_NOTE_ON=0`, `PDPH_EVENT_NOTE_OFF=1`, `PDPH_EVENT_OTHER=2`. Context and restart flags use the SDK values unchanged. Task 13 moves these POD declarations/constants unchanged.
- Standard plugin roots are owned by Swift `PluginCatalog`; the native engine accepts explicit module paths. Task 17 removes the unused native path-enumeration API.
- **`pdph_module_class_info`** lists only classes of category `kVstAudioEffectClass`. `pdph_module_class_count` counts the same set.
- **`pdph_plugin_create`.**
  - Host context: installs the host context with `PluginContextFactory::instance().setPluginContext(host)` (once per process) before `PlugProvider::initialize`. `host` is a `HostApplication` subclass overriding `getName` to return "Porydaw".
  - Wiring: `PlugProvider` creates, initializes and connects the component and controller (connection proxies). It does not sync state, so create then streams component `getState` into controller `setComponentState` and installs the component handler on the controller.
  - Failure: `initialize` returning false, a null controller, or a failed connection fails creation, with the reason in `pdph_error`.
- **Component handler.** UI-thread `performEdit` values enter a preallocated atomic SPSC; the processing thread drains it into parameter changes preallocated per parameter ID, delivered at sample offset 0 of the next `pdph_plugin_process`. SDK `ParameterChangeTransfer` uses volatile indices without C++ inter-thread synchronization (`public.sdk/source/vst/hosting/parameterchanges.h:116-117`, `parameterchanges.cpp:219-251`), so use an atomic SPSC with release/acquire ordering instead. No host lock on any audio-thread path. `endEdit`, `restartComponent` and `IComponentHandler2::setDirty` invoke matching callbacks; handle `kReloadComponent`, `kIoChanged`, `kLatencyChanged`, `kParamValuesChanged`, `kParamTitlesChanged`, `kMidiCCAssignmentChanged`.
- **`setup_processing`.** Calls `setupProcessing` (kSample32, `kOffline`/`kRealtime`); if calling `setBusArrangements`, pass the plugin's own current arrangements, never null. Activate every event bus and default-active audio bus, allocate silent scratch buffers for all declared audio buses. Only while inactive; otherwise return `PDPH_ERR_STATE`. Live is `kRealtime` at device rate with `max_block` 1024; Render is `kOffline` at 48 kHz with `max_block` 256. Re-setup is `set_active(0)` → `setup_processing` → latency read → `set_active(1)`, only for rate/mode change or IO/latency restart. Redo bus activation.
- **`pdph_plugin_process`.** Convert input notes to bus-0 `NoteOnEvent`/`NoteOffEvent` at `sample_offset`, with channel, pitch, velocity, noteId, zero tuning/length; Swift supplies channel 0. Convert output notes to `PDPH_EVENT_NOTE_ON`/`NOTE_OFF` with velocity 0…1 and noteId; pair by ID with FIFO-per-pitch fallback and preserve overlapping IDs. Other output is `PDPH_EVENT_OTHER`; excess output increments `out_total`. Preallocate input/output buffers, `EventList`s (`setMaxSize(4096)`) and parameter changes at setup; clear per block. Map context flags one-to-one to SDK flags. Stopped calls still process with `PLAYING` clear. Helper host code remains allocation-, lock- and dispatch-free on its processing path; plugin behavior is its own responsibility.
- **`pdph_plugin_latency_samples`.** Valid only after `setup_processing` (SDK: UI-thread & Setup Done). Before that it returns `PDPH_ERR_STATE`.
- **`get_state`/`set_state`.** Use `MemoryStream` on the component (`which=0`) or the controller (`1`). Component `set_state` also calls `setComponentState` on the controller.
- **`pdph_plugin_destroy`.** The owner detaches the insert before shutting down the helper, then stops processing. Detach the callback table without a host lock on any processing path; guarantee no callback after destroy returns. Deactivate, terminate and disconnect.
- **State restore order.** `set_state` applies component bytes via `IComponent::setState`, then the same bytes via `IEditController::setComponentState`, then controller bytes via `IEditController::setState`. Main-thread state reads never become a second consumer of the processing thread's parameter SPSC.
- **Scanner.** `porydaw-vst3-host scan <modulePath>` probes exactly that module and prints the spec JSON document; exit 0 on success, non-zero with a one-line stderr reason on load failure. Fixture additions in the same fixture CMake: `porydawtestcrash.vst3` (aborts inside `GetPluginFactory`) and `porydawtesthang.vst3` (sleeps forever there).
- **Fixture module `porydawtestgen.vst3`.** Built with SDK plugin sources (`vstsinglecomponenteffect`, `vstbus`, `vstcomponent`, `vstcomponentbase`, `vsteditcontroller`, `vstparameters`, `vstaudioeffect`, `vstinitiids`, `main/pluginfactory`, `main/moduleinit` and the platform main). It uses the platform VST3 bundle layout and lands in `$<TARGET_FILE_DIR:porydaw_checks>/vstfixtures/`. IPO is disabled for it. Its `SingleComponentEffect` subclass overrides `setState`/`getState`, `setProcessing`, `process`, `getLatencySamples` and `setupProcessing`; the base stubs return `kNotImplemented` or 0. Its four classes share "Pitch Offset" (0…12 semitones). Component state is four `int32 LE` fields: `pitchOffset` at byte 0, `latencySamples` at 4, reserved `keysReceived` at 8 (zero until task 8), and `fault` at 12. Both the old 8-byte state and task-8-extended 12-byte state decode with `fault = 0`; new state is 16 bytes.
  - `TestGen`: 1 event-in bus, 1 event-out bus, no audio. While `kPlaying` it emits, at every 1/16-note boundary derived from `ppq_position` and tempo, a note at pitch `60 + offset + 2·(step % 4)`, velocity 0.8, length 1/32 note. Note-offs are emitted across block boundaries when due. At the first playing block it emits one `LegacyMIDICCOut` (CC1). Each input note-on echoes at pitch +12 with the matching off. No output when not playing. `setState` reads the `fault` field: 0 = none, 1 = abort in the next `process`, 2 = sleep forever in the next `process`. Task 13 sets the field with `SetState`; tasks 9 and 12 use `PluginInstance.restore(_:)` through a real helper. ABI checks never set it.
  - `TestGenAudio`: `TestGen` plus a stereo audio output bus. It reports `latencySamples` from state (default 128) and shifts its own output later by that many samples. `setState` changing the latency calls `restartComponent(kLatencyChanged)`.
  - `TestGenRealtimeOnly`: `TestGen`, but emits nothing in `kOffline`.
  - `TestAudioOnly`: audio in/out, no event bus. Emits nothing; it exists so the panel filter checks can prove audio-only plugins stay hidden.

# Implementation steps
1. Write the header with per-function thread and ownership comments. No SDK includes.
2. Implement modules, instances and state with SDK hosting classes. Reuse `PlugProvider`, `HostApplication`, `EventList`, `ParameterChanges`, `ProcessData` and `MemoryStream`; do not reimplement them.
3. Implement processing as specified. The host computes no musical time; `pdph_process_context` maps field-for-field onto `ProcessContext` and its state flags.
4. Build the fixture and its bundle layout per platform.
5. Write the ABI checks, which call the C functions from Swift with `process` on a dedicated `Thread`:
   - scanner run on the fixture prints `version: 1` JSON with the 4 classes, 32-lowercase-hex uids and bus counts;
   - class enumeration and bus counts for the four classes (`TestAudioOnly` has audio in/out, no event bus);
   - create/destroy ×4;
   - offline 48 kHz/256 processing at 120 BPM yields golden sample offsets and pitches;
   - not playing yields nothing;
   - realtime setup at the device rate with max block 1024 followed by a process loop emits events; stopped calls have `PLAYING` clear;
   - input echo;
   - CC counted as `OTHER`;
   - a small `out_capacity` reports `out_total > out_written`;
   - component state set changes output pitch;
   - the `TestGenAudio` latency state change fires `restart_component` with the latency flag;
   - overlapping same-pitch notes with distinct `noteId`s keep their pairing;
   - setup while active returns `PDPH_ERR_STATE`.

# Acceptance predicate
All ABI checks pass in Debug and ASAN. NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-pluginhost-abi`
- `uv run --no-sync dev build:checks --asan && uv run --no-sync dev checks --asan --filter swiftcore-pluginhost-abi`: lifetime and leak safety.

Coverage gap: the `performEdit` queue has no GUI driver until task 8, whose fixture editor performs an edit on attach; task 8's checks cover it.

# Controller verification
After `uv run --no-sync dev build:app`, confirm `build/debug/porydaw.app/Contents/MacOS/porydaw-vst3-host` and `build/debug/porydaw-vst3-host` exist and both run `scan` on the fixture. Windows install, Linux AppImage and macOS deploy/signing are proven by the CI packaging jobs and their helper start checks on push; a `release.yml` dry run (`dry_run: true`) covers the release jobs.

# Task-specific constraints
- Native code decides no policy: no pacing, no tick math, no event filtering beyond the kind mapping.
- No Qt usage in this task.
- Exceptions never cross the C ABI: catch and map them to `PDPH_ERR_INTERNAL`.
- SDK sources stay unmodified.
