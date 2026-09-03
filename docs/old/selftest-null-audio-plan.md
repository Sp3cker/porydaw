# Parallel Self-Test Audio Plan

**Date:** 2026-08-28  
**Status:** Implemented. Focused self-test processes use miniaudio's forced
null backend and retain the real callback-thread behavior.
**Scope:** `AudioEngine` backend selection, the large `selftest` harness, its check-catalog entries, and focused verification of real versus null audio backends.

## 1. Goal

Split the current stateful `selftest` into focused check processes that can run in parallel without opening several system audio devices.

Each split check must:

- own one `MainWindow`, one `AudioEngine`, and one private scratch project;
- use miniaudio's null backend, which is silent and does not open system audio hardware;
- retain the real audio callback thread and normal `AudioEngine` behavior;
- establish its own project, song, transport, and edit preconditions;
- report one focused failure instead of suppressing later checks behind an earlier failure.

Keep one existing check on the normal backend-selection path so the suite still exercises real device initialization when the host provides it.

## 2. Current evidence

### 2.1 Why `selftest` fails now

`src/checks/selftest.cpp` starts `mus_littleroot_test` once, then runs document edits, timeline replacement, preview, several asynchronous voicegroup rebuilds, settings replacement, seek behavior, sidecar persistence, and tab closure in one sequence.

The checked-in MIDI fixture contains 7.81 seconds of MIDI events. `AudioEngine::process()` adds a three-second tail before stopping a non-looping song, so the transport stops at about 10.81 seconds. The focused `selftest` currently takes about 34 seconds. Its later assertions therefore inherit a stopped transport even when the operation under test did not stop playback.

The failure is a harness-lifetime problem, not evidence that `updateVoicegroup()` or `updateSettings()` stops the transport.

### 2.2 Existing process isolation

`tools/run_checks.ts` already:

- launches each catalog row as a separate process;
- gives each row a unique scratch path;
- stages only that row's declared fixtures;
- gives each process isolated settings;
- runs rows through a parallel worker pool.

The missing step is to turn the independent behaviors inside the one `selftest` row into independent catalog rows.

### 2.3 Existing non-system audio backend

The bundled miniaudio already includes `ma_backend_null`. Its implementation:

- always initializes;
- owns a device thread;
- invokes the normal data callback;
- advances according to real wall time;
- discards rendered output instead of sending it to hardware.

`AudioEngine` already identifies this backend through `backendName()` and `usingNullBackend()`. No new audio-device interface or fake renderer is required for parallel integration checks.

## 3. Fixed design decisions

### 3.1 Force miniaudio's null backend for integration checks

Add one supported process setting:

```text
PORYDAW_AUDIO_BACKEND=null
```

`AudioEngine::init()` reads it before creating the miniaudio context.

- When its value is exactly `null`, initialize a context with only `ma_backend_null`, then initialize the existing `ma_device` against that context.
- When it is absent, retain the current production backend selection without changes.
- Do not add backend names other than `null` in this work.
- Do not add a public audio-device interface, fake `AudioEngine`, callback scheduler, or test-only subclass.
- A forced null-backend initialization failure is an initialization failure. Do not fall back to a system device, because that would defeat check isolation.

This is an internal backend choice. Timeline rendering, preview, transport transitions, cold device stop/start, bank replacement, telemetry, and auto-stop all continue through the production `AudioEngine` implementation.

### 3.2 Preserve a normal-backend smoke check

Leave `audiocheck` on the default production selection path. It continues to report the selected backend, sample rate, period size, and null-fallback state.

On a machine with working hardware, `audiocheck` opens the normal system backend. On a headless machine, its current null fallback remains valid. Do not make ordinary CI depend on physical audio hardware.

The split integration checks prove application behavior against the real callback contract. `audiocheck` proves that the production backend-selection path still initializes and reports its result. Neither check claims to prove audible output, device-loss recovery, underrun behavior, or host-driver latency.

### 3.3 Split `selftest` by behavior

Replace the single `selftest` catalog row with four rows:

| Check name | Check argument | Behavior owned |
| --- | --- | --- |
| `selftest-timeline` | `--selftest-timeline` | song open, playback advance, live document edit, moved note, timeline handoff, undo, preview voice |
| `selftest-voicegroup` | `--selftest-voicegroup` | scalar voice edit, structural voice edit, shared-bank replacement, undo, dirty state, unchanged source file |
| `selftest-transport` | `--selftest-transport` | settings replacement while playing, paused playhead reconciliation, edit-cursor seek, stopped restart, Space-from-pause |
| `selftest-workspace` | `--selftest-workspace` | wizard/dialog construction, sidecar round trip, clean close, final-tab timer shutdown |

Each row uses:

```cpp
.environment = {
    {QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")},
}
```

Each row declares only the fixture files it uses. It may initially use the current self-test fixture set if narrowing those lists would mix fixture cleanup into this change.

Do not keep an aggregate `selftest` row that reruns all four scenarios serially. `deno task verify --filter selftest` already selects all four rows by name when a serial diagnostic run is wanted with `--pool=1`.

### 3.4 Keep each scenario state-independent

Every scenario must open the project and song through the production path. It must not depend on state produced by another check process.

Every assertion about preserving playback must follow this sequence:

1. Seek to the scenario's intended start point.
2. Start playback.
3. Wait until the callback has advanced the playhead and the transport reports `Playing`.
4. Perform exactly the operation whose playback behavior is under test.
5. Wait for that operation's own completion condition.
6. Assert that transport still reports `Playing` and the playhead advanced during that operation.

Do not assert that playback survived an earlier, unrelated scenario. Do not disable `AudioEngine` auto-stop. Do not lengthen the MIDI fixture merely to hide a long test sequence.

For the voicegroup scenario, re-establish playback immediately before each scalar edit, structural edit, or undo whose bank swap must preserve playback. This keeps the assertion tied to one bank operation rather than the total wall time of the scenario.

### 3.5 Keep true callback concurrency

The null backend's timer and callback thread remain active. Do not replace it with direct calls to `AudioEngine::process()` for these integration checks.

`transportcheck` may continue to stop its device and call `process()` directly for sample-exact DSP assertions. That is a different check surface: deterministic rendering rather than application/UI integration.

## 4. Target test module

Remove the public check entry point `MainWindow::runSelfTest()` from `src/mainwindow.h`. Replace it with one test-only friend module:

```cpp
namespace checks {

enum class SelfTestScenario {
    Timeline,
    Voicegroup,
    Transport,
    Workspace,
};

class SelfTestHarness
{
  public:
    static int run(MainWindow &window, SelfTestScenario scenario,
                   const QString &projectRoot, const QString &songLabel);

  private:
    explicit SelfTestHarness(MainWindow &window);

    bool openSong(const QString &projectRoot, const QString &songLabel);
    bool beginObservedPlayback(uint64_t samplePosition = 0);

    bool runTimelineScenario();
    bool runVoicegroupScenario();
    bool runTransportScenario();
    bool runWorkspaceScenario();

    MainWindow &m_window;
    QString m_projectRoot;
    SongInfo m_songInfo;
    SongTab *m_tab = nullptr;
    SongView *m_view = nullptr;
};

} // namespace checks
```

`MainWindow` declares only:

```cpp
friend class checks::SelfTestHarness;
```

The friend keeps check-only access out of the production interface. `SelfTestHarness::run()` is the only interface used by `checkcatalog.cpp`; setup and scenario methods remain private.

Suggested file ownership:

```text
src/checks/selftest/harness.h       declaration and SelfTestScenario
src/checks/selftest/harness.cpp     run dispatch, project/song setup, playback precondition
src/checks/selftest/timeline.cpp    timeline/edit/preview scenario
src/checks/selftest/voicegroup.cpp  voicegroup edit/reload/undo scenario
src/checks/selftest/transport.cpp   settings and transport/seek scenario
src/checks/selftest/workspace.cpp   dialog, sidecar, and close scenario
```

Delete `src/checks/selftest.cpp` after all behavior has moved. Add the six replacement sources to `porydaw_checks` in `CMakeLists.txt`.

Do not expose `AudioEngine`, `WorkspaceUi`, or `SongTab` through public harness accessors. Scenario methods are members of the friend harness and use the stored `MainWindow` reference internally.

## 5. Scenario contracts

### 5.1 `selftest-timeline`

After common song setup:

- start observed playback;
- capture the current timeline and playhead;
- add the note and automation point used by the current check;
- require the tab's rebuilt timeline to become the engine's active timeline;
- move the note and require a distinct replacement timeline;
- undo all three edits;
- require a clean document and the restored timeline installed in the engine;
- preview a voice through the preview engine and release it;
- require the main transport to remain playing for operations explicitly covered by this scenario;
- close cleanly.

Do not carry voicegroup editing, application settings, sidecar state, or later seek assertions into this scenario.

### 5.2 `selftest-voicegroup`

After common song setup:

- locate the same editable DirectSound slot and distinct donor slot as the current check;
- capture the source bytes and original tone/name;
- establish observed playback immediately before the scalar edit;
- apply the release edit and wait for the bank-actions gate plus installed-bank value;
- assert playback preservation for that bank replacement;
- if the donor path is available, establish observed playback again, apply the structural edit, wait for the installed donor, and assert playback preservation;
- establish playback before each undo whose bank replacement is part of the contract;
- undo all voice edits;
- require the exact original source bytes, tone, name, clean shared-bank state, and clean document state;
- close cleanly.

Keep the current supported skip behavior for a missing donor or unavailable picker. A missing editable DirectSound slot remains a skip only if that is still an accepted fixture property; otherwise fail the fixture explicitly.

### 5.3 `selftest-transport`

After common song setup:

- establish observed playback;
- apply the tweaked `SongSettings` and require the exact settings plus advancing playhead and `Playing` transport;
- restore original settings after capturing the result, then log the captured failing values rather than the restored values;
- pause and reconcile view playhead with engine playhead;
- commit the paused edit cursor and require both immediate view movement and eventual engine seek;
- resume playback;
- test edit-cursor seek while playing;
- stop and test play-from-cursor;
- pause and test Space-from-pause returning to the edit cursor;
- restore loop state and close cleanly.

This scenario must not depend on voicegroup edit duration.

### 5.4 `selftest-workspace`

After common song setup:

- construct `NewSongWizard` and the unified settings dialog from the live project state;
- write and load the sidecar view-state round trip;
- verify registration metadata coexists with the sidecar;
- restore temporary view changes and remove the sidecar;
- require the song to be clean;
- close the final tab and require the playhead timer to stop.

This scenario does not need to start playback unless final-tab timer behavior requires it. If it does, start playback immediately before that assertion.

## 6. Production changes

### `src/audio/audioengine.cpp`

- Read `PORYDAW_AUDIO_BACKEND` once in `AudioEngine::init()`.
- For `null`, create `m_context` with the one-element backend list `{ma_backend_null}` on every supported desktop OS.
- Preserve the existing Linux PulseAudio/ALSA preference when the variable is absent.
- Preserve the current default-context behavior on other platforms when the variable is absent.
- Preserve `backendName()`, `usingNullBackend()`, period diagnostics, shutdown, and error reporting.

### `src/audio/audioengine.h`

No new public method is required. Update comments only if they currently imply that null can occur solely as fallback.

### `src/mainwindow.cpp`

No special check path. `MainWindow` still initializes its owned `AudioEngine` normally. The forced null backend may show the existing non-modal silent-output warning; suppress it only if it makes a focused check fail or changes the widget behavior being tested. Do not add a new public flag preemptively.

### `src/mainwindow.h`

- Remove `runSelfTest()` from the public interface.
- Forward-declare and friend `checks::SelfTestHarness`.

### `src/checks/checkcatalog.cpp`

- Replace the one `selftest` definition with the four exact rows in section 3.3.
- Each handler constructs and shows one `MainWindow`, then calls `SelfTestHarness::run()` with its fixed enum value.
- Set `PORYDAW_AUDIO_BACKEND=null` on all four rows.

### `tools/run_checks.ts`

No scheduling change. The runner already provides isolated processes, scratch roots, settings, and parallel execution.

### `tools/checks_walls.ts`

Replace the old `selftest` estimate with measured estimates for the four new rows after the first successful run. Do not guess final values.

## 7. What the null backend does not cover

The split checks will not prove:

- that Core Audio, WASAPI, ALSA, or PulseAudio initializes on a particular host;
- that speakers produce audible output;
- device-loss and reconnect behavior;
- real driver latency, underruns, or period negotiation;
- timing bugs caused only by a host backend implementation.

Those are not claims made by the current `selftest`. Keep `audiocheck` on production backend selection, and use targeted native/manual or performance checks for driver-specific behavior. Do not make the full automated suite require physical audio hardware.

## 8. Implementation phases and gates

### Phase 1: forceable null backend

1. Add the exact `PORYDAW_AUDIO_BACKEND=null` branch.
2. Add focused `audiocheck` coverage that launches once with the forced value and requires `backendName() == "Null"` and `usingNullBackend()`.
3. Run the ordinary `audiocheck` without the value and confirm its current contract remains intact.

Gate:

```sh
deno task build:checks
deno task verify --filter audiocheck --verbose
```

### Phase 2: harness extraction without behavior changes

1. Introduce `SelfTestHarness` and move common project/song setup.
2. Move the current assertions into the four scenario methods.
3. Keep the single catalog row temporarily and run the four scenarios serially only during this extraction phase, or land the scenario rows in the same compile-safe change if the catalog cannot represent the temporary state cleanly.
4. Delete `MainWindow::runSelfTest()` and the old source after all assertions have owners.

Gate:

```sh
deno task build:checks
deno task verify --filter selftest --pool=1 --verbose
```

All four named rows must pass. The old aggregate row must no longer exist.

### Phase 3: parallel proof

1. Run the four split rows through the normal pool.
2. Run them repeatedly to catch cross-process device or fixture interference.
3. Compare the maximum row duration and total `verify` wall time with the recorded pre-split baseline.

Gate:

```sh
deno task verify --filter selftest --verbose
deno task verify --filter selftest --verbose
deno task verify --filter selftest --verbose
deno task verify
```

Success requires:

- all repetitions pass;
- every split row reports `Null` as its backend;
- no split row skips for lack of an audio device;
- no row reads or writes another row's scratch project;
- the full suite passes;
- the normal parallel run is not slower than the old aggregate self-test baseline by more than normal run-to-run variance.

If four concurrent project opens increase total wall time, keep the semantic split but measure pool sizes before changing the global pool. Do not add a self-test-only scheduler unless measurement proves the existing pool cannot handle the workload.

## 9. Deletion and non-goals

Delete:

- `MainWindow::runSelfTest()`;
- the aggregate `selftest` catalog row;
- `src/checks/selftest.cpp` after extraction;
- assertions that depend on elapsed time from an unrelated prior scenario;
- the stale `selftest` wall estimate.

Do not add:

- a general audio-device abstraction;
- a fake `AudioEngine`;
- a fake callback clock for these integration checks;
- shared process-wide test state;
- a second check scheduler;
- retries that hide timing failures;
- a longer fixture used only to keep one oversized sequence alive;
- production behavior that disables auto-stop under test.

## 10. Review questions

The design review must answer these before implementation:

1. Does forcing miniaudio's null backend preserve the callback, cold-swap, and thread-handoff behavior that these checks intend to cover?
2. Does retaining ordinary `audiocheck` give enough coverage of production backend selection, or is one existing check more appropriate as the normal-backend smoke path?
3. Are the four scenario boundaries cohesive, or does any assertion depend on state that this plan incorrectly separates?
4. Can every playback-preservation assertion re-establish its precondition without masking the operation it claims to test?
5. Does the friend `SelfTestHarness` remove test code from the production interface without becoming a shallow access wrapper?
6. Will four concurrent project/song loads contend on any resource outside their private scratch paths and per-process settings?
7. Is any proposed code present only to protect against a flow the check runner cannot create?

## 11. Unrelated working-tree change

`tools/cli.ts` was already modified for terse build output before this plan was created. It is not part of this plan and must not be edited, staged, committed, or reverted as part of the self-test work.
