# Right-drag chord audition

## Contract

Every eligible note entering the right-drag band captures its document track, pitch, velocity, and duration through the current tempo map, including distinct NoteIDs at identical track/pitch. Each occurrence releases after its own rendered sample duration; zero-sample spans stay silent. Unchanged identities do not reattack or extend/change their captured note. Departure, cancellation, demotion, hiding, and detach can release it earlier. Reentry creates a fresh full-duration occurrence even before the prior entrance reaches the callback. Normal instrument release tails remain.

Preserve selection, MIDI bytes, revision/history, combined-button gestures, native allocation/priorities/limits/portamento/debug rendering, mono retriggers, timed expiry, and isolated voice/sample preview. Never resurrect stolen/completed/cut voices. No extra engine, pitch deduplication, velocity aggregation, arbitrary band cap, callback allocation/deallocation/locking/logging, or unrelated timed/mono changes.

## Ownership

- `PorydawPlayback` owns device-independent scheduled and interactive event delivery: `Sequencer`, `PlaybackBridge`, and `audition/{AudioAudition,AudioBandAudition,AudioAuditionVoices,AudioSampleAudition}.swift`. `PorydawAppAudio` keeps engine ownership, callback composition, transport/fades, device lifecycle, mixing/output, timeline handoff, telemetry, suppression and WAV export.
- `BandAuditionNote` is immutable: `noteID/durationSamples: UInt64`, `track/key/velocity: UInt8`; duration is required, not a default.
- `PianoGrid.onBandAudition` forwards through `NativeAudio.updateBandAudition` to `AudioAudition.updateBandAudition`; `onAudition` remains the mono path.
- `AudioBandAudition` owns membership and immutable `Sendable` batches with `Array` payloads read through `Span` and typed `AtomicLazyReference` links. The producer retains a linked head and prunes only nodes strictly behind the acquired acknowledgement. The callback captures one finite cutoff; destruction requires a parked callback. Fresh batch/payload allocation and reclamation belong to the producer, replacing unsafe node recycling.
- Swift `AudioAuditionVoices` owns source/serial identities and rendered-sample budgets for the existing 57 primary/shadow/audition PCM+CGB slots. Original native note-on, priorities, stealing, portamento and DSP remain authoritative; host metadata observes actual accepted slots and clones without adding native fields or an engine. Host rendering splits at expiry and requests normal release after the samples. Held/timed lifetimes remain with their existing owners; every positive band duration, including `UInt64.max`, is finite.
- Checks reuse the existing native-owned PCM/CGB banks in `AuditionCheckEngines`; no second engine/bank fixture or callback-history oracle.

## Unchanged-engine cutover

The native extension was withdrawn at the user's request. `external/poryaaaa` is repinned to the unchanged `c504afebe5c56cf9393e6ae632b9cef632480ab6`; no native source patches or replacement owned-note APIs are required.

The former C++ `AudioEngine` (`97623751^`, `src/audio/audioengine.cpp` and `auditionslots.cpp`) used original note-on/off with host-owned held/timed queues and countdowns. Its same-pitch deduplication and callback-sized expiry are not copied: band occurrences keep independent NoteIDs and exact rendered-sample deadlines. Ordinary interactive sequencer ingress/off and idle DSP share the host ledger; absent an interactive context, offline sequencing retains the original native path.

The read-only ownership projection is coupled to this pinned allocator, including its distinct wrapper track-priority and driver player-plus-track-priority decisions. It observes rather than selects allocation, does not mutate emulated fields as tags, and explicitly rejects projection drift. Updating the dependency requires rechecking accepted/rejected slots, identical pre-DSP starts, portamento and shadow-copy ownership.

- Focused `deno task checks --filter swiftcore-playback --filter swiftcore-playback-controller --filter swiftcore-playback-audition --filter samplecheck-editor --verbose`: all seven selected suites passed against the original native revision.
- Real PCM/CGB stereo and release tails match independently dispatched original native calls, including normal/invert modes, nonzero player priority, portamento and 17/2048-frame callback partitions. Same-track/same-pitch occurrences expire independently at frames 1025 and 2051.
- A new comparison initially failed only on CGB `MO_VOL`: native per-process song-volume refresh sets that dirty latch, while VBlank consumes it. The callback-partition-dependent volume latch is not a semantic state equality; pitch/duty latches, actual volume, envelope, ownership, priority, controls, clocks and complete future output remain checked. No native state was normalized.
- Calibrated disposable measurement: 4096 warmups and 20,000 captures per workload; all seven real apply + host main DSP16 + original preview DSP16 consumer workloads measured **zero allocations, requested bytes and frees**, including queued-discard traversal.

| Producer workload | Allocations/update | Requested bytes/update |
| --- | ---: | ---: |
| Unchanged / post-change no-op | 0 | 0 |
| One / two commands | 1 | 96 |
| Eight commands | 2 | 704 |
| 96-note replacement / 192 commands | 2 | 4736 |

The 32-publication burst measured 64 allocations and 22,528 requested bytes per burst: two allocations and 704 bytes per eight-command publication, not two allocations per burst. Its consumer also measured zero allocations, bytes and frees. All disposable measurement code was removed after capture.

These measurements are on the synchronous native check caller, not the CoreAudio hardware callback. Hook-distorted CPU time is not a CPU-performance claim. Unchanged native source and direct-native self-baselines are not an observed mGBA/ROM differential-fidelity proof.

### Final cutover gate

- `deno task checks --filter swiftcore-playback --filter swiftcore-projectsession --filter samplecheck-editor --verbose`: **8/53 passed**, 45 intentionally skipped, after disposable probe removal and the callback-order correction. This includes ordinary project-session behavior, audition/controller, sequencing, suppression, resonance and sample-editor coverage.
- Actual production `tst_SwiftRollSelection.qml` / `swiftroll-window`: **1/1 passed**. The resize fixture's ordinary opt-out lane also passed **1/1** without loading the recorder. `deno task checks:bridge` reported zero baselined findings; `deno task build:app` and changed-Swift/TypeScript formatting checks passed.
- Review found a same-callback debug transition defect: the original native invert setter resets sidecars, so applying it after queued audition starts silenced the new entrance. A real PCM regression failed before the correction; applying debug configuration before audition commands fixed it. Cold PCM and CGB one-second finite entrances now sound and expire in the same-transition regression. Its CGB attack-7 fixture starts at zero volume, so the audibility observation uses the full envelope window; the independent 1025/2051-frame deadline checks remain unchanged.
- Independent native implementation and check reviews: **APPROVE**, including the corrective delta. Native sidecar-reset, wrapper-rejection and PCM/CGB clone asymmetry advisories were adjudicated against the pinned original source, not addressed with guards, metadata resets or dependency changes.


## Isolation

Worktree: `.worktrees/right-drag-chords`, branch `feature/right-drag-chords`, base `c33a17a5f6bd5ac6f557d58fc95d1956a0ad7d42`. Its independent `external/poryaaaa` clone starts at `c504afebe5c56cf9393e6ae632b9cef632480ab6`. Main and its canonical dependency remain untouched.

The resolver selects one validated root. Empty linked-worktree gitlinks fall back to the strict canonical source; populated local checkouts require matching local gitlink HEAD and allow tracked development changes. Invalid present local paths never fall back. Cache matching uses the chosen source.

## Verification

Historical verification for the earlier native duration extension, before the unchanged-engine cutover:

- `deno task format`, `deno task format --check`, `deno task build:checks`, and final `deno task build:app`: passed. `open -n build/debug/porydaw.app` launched the updated app; its worktree-bundle process was observed.
- `deno task checks --filter swiftcore-playback --filter swiftcore-projectsession`: five lanes passed; two failed on waveform observations that mixed stereo samples with frames and ended before the existing PCM DMA delay. Corrected observations without changing 1025/2051-frame budgets or the 2048-frame callback. `deno task checks --filter swiftcore-playback-audition --filter swiftcore-playback-controller` then passed both. All seven selected lanes have passing evidence.
- Native predicates cover exact velocities, independent same-pitch owners and sample gates, penultimate/exact expiry, no extension/resurrection, fresh reentry, zero-sample rejection, source isolation, PCM/CGB steal/drop/shadow ownership, and cut/reset/defer. Production grid proves a duration crossing tempo changes; production renderer's complete waveform and tail match manual release at frame 1025. Existing pointer cancellation, history/bytes, and native interlock predicates remain.
- `PORYDAW_ROLL_QML_SUITE=tst_SwiftRollSelection.qml deno task checks:qml-roll --filter swiftroll-window`: passed 1/1 production pointer/render lane.
- `deno task checks:bridge`: zero baselined findings.
- Disposable resolver smoke: all 12 root/cleanliness/revision/sentinel/symlink/cache cases passed.
- `thermo-nuclear-reviewer` audited the complete parent, new-file, and isolated-native diff: APPROVE, no pertinent major blockers. No silent queue-invariant fallback or extra fast-path state was added for advisory suggestions.

No proof ledgers exist in this revision; no parity claim. Production QML input/render and real native waveform/state checks supply interaction evidence, not speaker listening. macOS desktop shielding prevents accessibility capture.

`deno task lsp:swift` indexed zero targets because the generated Ninja file lacks the expected `SWIFT_SOURCES` fields. Local diagnostics are not semantic proof; configured compilation supplies type checking. The full build reported 13 warnings in unchanged check files.

Check build modularity is unchanged: Debug Swift compilation is incremental/batched, but native Swift suites still share `SwiftCoreCheck`; filters select execution, not independent domain build targets. QML lanes already have separate targets.

## Safe-buffer correction

The requested BPM simplification was withdrawn; current tempo-map duration integration and native behavior remain unchanged. `AudioBandAudition.swift` shrank from 182 to 161 lines. Swift-owned unsafe buffers and raw object-pointer links are gone; the remaining engine pointer is mandatory native interop.

Disposable 200,000-iteration native audition profiling used 4,096 warmup iterations, twelve-note bands with eight shared identities, 32-publication bursts, and pending-discard transitions. The safe workload passed a final native predicate that no held occurrences remained. The original workload completed, but its temporary harness initially failed the zero-assertion guard; the safe harness added the actual final-departure predicate. All benchmark gates/helpers and profiling-tool modifications were removed afterward.

- One Debug CPU pair: callback-inclusive cycle weight `8,945,226,807 -> 9,163,412,437` (+2.44%); whole process `14,854,630,137 -> 15,371,351,498` (+3.48%). This is a measured tradeoff, not an improvement or a statistical no-regression claim.
- Actual Allocations captures: whole-process heap counts `20,987,740 -> 21,855,331`; total allocated bytes `972,917,744 -> 1,188,038,432`. Immutable producer batches cost more allocation than the unsafe recycled queue.
- Exported persistent callback records were the same two cold metadata allocations (96 bytes) in unchanged `AudioSampleAudition.apply`. The default Allocations List exposed persistent backtraces only; Statistics exposed aggregate transient counts, not callback attribution. No measured zero-transient-allocation/free claim follows from these captures. Queue reclamation placement is established by its retained-head/acknowledgement ownership contract, not these persistent rows.
- After benchmark removal, `deno task checks --filter swiftcore-playback-audition --filter swiftcore-playback-controller --filter swiftcore-projectsession`: passed all three selected lanes (50 skipped).
- Production pointer/render lane (`tst_SwiftRollSelection.qml` / `swiftroll-window`): passed 1/1; `deno task checks:bridge`: zero baselined findings; `deno task format --check`: passed.
- Scoped `sdd-task-reviewer` gate: Approved, no critical or important issues. Confirmed the raw-storage violation is eliminated and retained-head/ACK ownership, finite cutoff, and Array/Span lifetime preserve the callback contract.
- Final `deno task build:app` passed; `open -n build/debug/porydaw.app` launched the corrected worktree application, observed as PID 96442.

## Playback module placement

- Chose the existing Playback module over a new audition-only target: song sequencing and interactive preview delivery both borrow native engines; the application audio renderer remains their composition/lifetime owner. No shared event abstraction, wrapper, alias or re-export was added.
- Moved all three audition implementation files byte-identically. The extraction itself changed no allocation algorithms, queue capacities, engine ordering or native APIs; the following allocation pass is recorded separately below.
- Playback grows from two to five sources; AppAudio drops from ten to seven. Sequencing edits now share a larger batch, and cross-module callback optimization is unmeasured. A broader audio-engine extraction would mostly rename the current owner and remove only the device source.
- Identical private-comment edit, `deno task build:checks`: before, ten-source AppAudio and its archive rebuilt in 1.6 s; after, five-source Playback and its archive rebuilt in 0.8 s. Both relinked app/check binaries; neither rebuilt the UI or shared Swift check module. One Debug pair proves target isolation, not a statistical speedup or Release performance claim. Temporary probe removed.
- Existing click-transport predicates still execute through gated `-enable-testing` and `@testable import PorydawPlayback`; no visibility widening or assertion rewrite.
- `deno task checks --filter swiftcore-playback --filter swiftcore-projectsession --filter samplecheck-editor`: 8/53 passed, 45 skipped. Production `tst_SwiftRollSelection.qml` / `swiftroll-window`: 1/1 passed. Bridge guard: zero baselined findings; format check passed.
- Final `deno task build:app` passed and launched the worktree application, observed as PID 6757. Swift LSP index generation still reports zero targets; configured compilation/checks, scoped caller search and exact moved-source hashes establish this cutover, not empty reference results.
- Independent standards and spec gates: both Approved, no critical, important or minor findings. Historical feature-parity inventory/archived brief paths remain initial research snapshots, not current ownership documentation.

## Warmed allocation reduction

The UI gathers directly into retained high-water scratch storage using the same strict overlap predicate as release selection. RELEASE still recomputes coverage from its own coordinates. Metadata, zero-duration filtering and tempo-map sample integration are unchanged. Array traversal uses borrowed spans: diagnostic-only backtraces identified transient Swift `Array` read-accessor/iterator allocations, not native engine allocations.

Immutable batches carry two commands inline, spilling larger deltas into one array-backed batch without splitting or dropping publications. An eight-slot prototype used 240 bytes for a one-command update versus the 160-byte baseline, so two slots were selected. Published overflow storage leaves the producer; retaining its capacity would force COW on reset, including a subsequent no-op. Checked `Sendable`, typed atomic links, finite callback cutoff and strict producer-head `< ACK` reclamation remain unchanged.

Disposable macOS libmalloc-hook measurements count transient allocations and frees, not just surviving objects. Calibration covered malloc/free, calloc, realloc, segmented capture, thread exclusion and unavailable-hook failure; invalid captures report null counters, not zero. Setup, assertions, output, native buffer creation and worker synchronization are outside capture. Native scenarios use fresh engines per path, 4,096 warmups and 20,000 measured iterations; UI scenarios use 4,096 warmups and 50,000 iterations.

Per warmed producer update, requested bytes rather than allocator-rounded/live bytes:

| Path | Allocations before → after | Bytes before → after | Frees before → after |
| --- | ---: | ---: | ---: |
| Direct held note on/off | 0 → 0 | 0 → 0 | 0 → 0 |
| Unchanged twelve-note band | 48 → 0 | 1,536 → 0 | 48 → 0 |
| One-command delta | 4 → 1 | 160 → 96 | 4 → 1 |
| Two-command delta | 6 → 1 | 248 → 96 | 6 → 1 |
| Eight-command delta | 50 → 2 | 2,016 → 704 | 50 → 2 |
| 192-command delta | 386 → 2 | 19,488 → 4,736 | 386 → 2 |
| Burst with pending discard | 50 → 2 | 2,016 → 704 | 50 → 2 |
| No-op immediately after change | 49 → 0 | 1,976 → 0 | 48 → 0 |
| UI coverage forwarding unchanged band | 34 → 0 | 1,827 → 0 | 34 → 0 |
| UI-only unchanged coverage | 26 → 0 | 1,571 → 0 | 26 → 0 |
| UI-only alternating coverage | 23 → 0 | 1,258 → 0 | 23 → 0 |

Every captured native consumer path recorded zero allocations, requested bytes and frees before and after, including transient pairs. The named `pory-audition-consumer` worker executes real `AudioAudition.apply` and both native engines' sixteen-frame DSP calls. It is not the actual CoreAudio hardware callback thread; these results do not establish whole-application or hardware-callback allocation freedom. UI capture covers synchronous coverage publication, not input dispatch, queued QML notification/render work or fixture assertions.

Separate no-malloc-hook thread-CPU measurements, three runs per version with common endpoint/worker overhead, gave producer medians: unchanged 2,200 → 1,180 ns/update; one-command 1,156 → 901; two-command 1,458 → 1,184; eight-command 4,066 → 3,390; large 44,922 → 41,252; burst 3,541 → 2,755; post-change no-op 2,612 → 1,301. UI forwarding was 4,708 → 3,517 ns/update. Direct held producer was 129 → 134 (+3.4%). Consumer medians ranged from −4.0% to +9.0% (two-command path), with before/after sample ranges overlapping. These are instrumented Debug observations, not statistical no-regression or universal CPU-improvement claims.

- Added native snapshot/order regression across one/two/three/eight/nine-command payload boundaries: queued departure/reentry, one-note departure, mixed small/large tail, final release. Existing 96-occurrence burst, duration, cut and release predicates remain.
- After removing all temporary check sources, env gates and CMake entries: `deno task checks --filter swiftcore-playback --filter swiftcore-projectsession --filter samplecheck-editor --verbose`: 8/53 passed, 45 skipped. Production `PORYDAW_ROLL_QML_SUITE=tst_SwiftRollSelection.qml deno task checks:qml-roll --filter swiftroll-window`: 1/1 passed. Bridge guard: zero baselined findings; explicit changed-Swift format check and app build passed.
- Independent standards/spec reviews passed. A proposed overflow-capacity retention was withdrawn after ownership/COW adjudication. `deno task lsp:swift` still indexed 0/0 targets; configured compilation and actual checks establish this change, not empty LSP references.
- `open -n build/debug/porydaw.app` launched PID 41573; PID-specific capture showed the loaded production piano roll, note geometry and automation curve. The production QML lane exercised pointer behavior; the launch/capture alone does not prove audible playback.

## Reusable allocation macrobenchmarks

The audition win landed first: Porydaw `5f87933f`, native engine `c35c61b`, both pushed on `feature/right-drag-chords`. The reusable tooling changes check targets only; normal application startup does not load or compile the recorder.

```sh
deno task bench:allocations --scenario note-draw --output /tmp/note-draw-allocations.json
deno task bench:allocations --scenario automation-commit --output /tmp/automation-allocations.json
deno task bench:allocations --scenario window-resize --output /tmp/resize-allocations.json
deno task bench:allocations --scenario note-draw --mode cpu --output /tmp/note-draw-cpu.json
deno task bench:allocations --help
deno task bench:allocations:check
```

Defaults are 64 warmups, 1,000 measured operations and three independent process samples; override with `--warmup`, `--iterations` and `--runs`. Repeat each scenario with `--mode cpu` for an independent no-malloc-hook CPU comparison. JSON retains raw JSONL and parsed records, compiler/check diagnostics and failed-sample errors before temporary files are removed. Each successful sample also retains its validated, mode-discriminated `capture`; raw input is validated once, then `summarize(Capture[], Options)` aggregates those typed captures without decoding or revalidating JSON.

In `summary.phases`, `operations` and `capturedsegments` are scalar numbers, each equal to the requested `iterations`, not redundant distributions. `cpu_ns` and allocation-mode `heap` counters retain `total` and `per_operation` objects with `median`, `min` and `max`; heap keys are exactly `allocations`, `allocatedbytes`, `frees`, `reallocations`, `reallocinplace`, `failedallocations` and `failedreallocations`. `threadids` preserves per-process diagnostics, and a chained previous malloc logger still produces a warning. CPU-only captures and summaries have no heap fields. Failed runs retain raw evidence and diagnostics with `summary: null`; invalid/null counters never become zero. Compare identical scenario, build configuration, fixture and parameters before/after; allocation-mode CPU is hook-distorted and must not substitute for independent CPU runs.

| Scenario / phase | Captured work | Predicate outside capture |
| --- | --- | --- |
| `note-draw.stroke` | Real piano-grid press, move and release | Exact tick/pitch/duration/velocity, one revision/history transition, cleared preview, exact MIDI/history restoration through undo |
| `note-draw.release-commit` | Independently prepared draw, release and synchronous commit only | Same committed-note and restoration predicates |
| `automation-commit.release-commit` | Existing pan-node drag prepared outside capture; release and synchronous document/publication work | Exact changed lane/playback values, one revision/history transition, cleared gesture/preview, exact undo restoration |
| `window-resize.geometry-event-turn` | Real native `ApplicationWindow` alternates 960×640 and 1120×760 around the production roll, plus one bounded Qt event turn | Native/content/overlay/plot geometry, matching document camera, advanced production display revision |
| `window-resize.empty-event-turn` | Identical capture bridge and event turn without geometry changes | Geometry/camera still match; reported separately, never blindly subtracted |

The two note phases overlap conceptually but execute independent loops: do not sum them. Native editor scenarios cover synchronous GUI-thread Swift/presenter work, excluding OS input dispatch and queued QML/rendering. Resize includes GUI-thread bridge/event-turn overhead, not render-thread/GPU work, frame completion, physical window dragging or all-process allocations. Its fixture establishes asynchronous song-catalog readiness before capture and uses production tab/page destruction acknowledgments during teardown.

`src/app/allocation_probe.c` is compiled into a private checks-only dylib. `AllocationProbe.swift` loads it explicitly and leaves it loaded for process lifetime so the installed callback cannot dangle. The allocation mode uses the macOS libmalloc logger ABI with runtime transient malloc/free and realloc calibration; unknown events, replaced/unavailable hooks, nested capture, overflow, missing records, mismatched operation/segment counts or failed scenario checks fail closed, never becoming zero. The recorder counts requested bytes, allocation/free events and reallocations, not rounded/live memory or RSS. CPU mode installs no heap hook and reports current-thread CPU time with common capture endpoint overhead.

To add a macrobenchmark:

1. Name its thread, exact production boundary and observer exclusions. Reuse `AllocationBenchmarkOptions` and `AllocationProbe` in a checks-only, explicitly opt-in driver; never load the recorder through normal application startup.
2. Prepare fixtures/coordinates outside capture. Warm the same operation and discard warmup counters with `reset`; bracket each measured production operation with `begin`/`pause`, then run predicates, output and restoration outside capture. Use one measured segment per operation and report the exact operation count with a stable scenario-prefixed label. Capture unavoidable event-loop overhead in an identical, separate empty control, never subtract it.
3. Add one `SCENARIOS` registry entry in `tools/allocation_bench.ts` containing the complete phase labels, scope, Deno check task, exact filter and extra environment. CLI membership, the `Scenario` type, usage names, routing and validation labels derive from that registry. Native editor scenarios use `checks --filter swiftcore-allocation-editor`; window resize uses `checks:qml-roll --filter swiftroll-window` with `PORYDAW_ROLL_QML_SUITE=tst_AllocationWindowResize.qml`. Add the corresponding raw identity to the shared Swift `AllocationScenario` enum and its opt-in driver gate.
4. Keep editor profiling in `runEditorAllocationMacrobenchmarkSuite`, separate from ordinary project-session assertions; window recorder lifetime/count/error state belongs to `WindowResizeAllocationFixture`, not the shared checks-only `RollQmlBootstrap`. Register a new surface's own opt-in check entry when necessary rather than diverting a shared suite.
5. Add consumer-visible corruption tests at `validateCapture` and aggregation tests using its typed output. Verify the actual production state transition and ordinary opt-out lane, then run both calibrated allocation mode and independent no-hook CPU mode before interpreting counts.

Counts locate costly phases, not allocation call sites. Stack attribution is a separate diagnostic run: retaining/collecting backtraces changes allocation and CPU behavior. Do not compare its timing with calibrated count or no-hook CPU runs, and do not treat surviving-object backtraces as proof about transient allocation/free pairs.

### Reworked harness verification

- `deno task bench:allocations:check`: both TypeScript files typechecked; eight corruption/aggregation consumer tests passed.
- All three actual CLI scenarios passed in allocation and independent no-hook CPU modes with `--warmup 4 --iterations 8 --runs 1`; calibrated records and scalar summary counts were validated. Editor runs execute their own `swiftcore-allocation-editor` entry, not normal session assertions.
- Both recorder modes compiled with `-std=c11 -O2 -Wall -Wextra -Werror`. CPU captures contain no heap fields or installed heap hook; the resize control remains separate and unsubtracted.
- Three independent thermo-nuclear profiling gates (runner/consumer/recorder, editor/entry and window fixture) returned **APPROVE**, closing all five major and five advisory findings with no remaining critical or important findings. Runtime evidence remains the controller's observed captures and checks; reviewers did not rerun gates.

### Historical pre-rework baseline

At `bd6e7873`, before the harness rework and unchanged-engine cutover, all three scenarios passed in allocation and independent CPU modes with `--warmup 64 --iterations 1000 --runs 3`: eighteen fresh measured processes, in addition to six successful four-operation smoke runs. Below are medians of each process's phase total divided by its operation count, not distributions of individual operations. Debug, current GUI-thread scopes; requested bytes are cumulative, not retained memory.

| Phase | Allocations/op | Requested bytes/op | Frees/op | Independent CPU µs/op |
| --- | ---: | ---: | ---: | ---: |
| Note stroke | 9,019.001 | 372,386.912 | 9,017.001 | 426.23 |
| Note release/commit | 4,681 | 198,120 | 4,679 | 231.41 |
| Automation release/commit | 3,437.002 | 308,613.560 | 3,409.002 | 482.68 |
| Resize + bounded event turn | 44,556.210 | 8,112,145.756 | 42,607.197 | 6,927.27 |
| Empty event turn | 1.023 | 1,532.984 | 15.472 | 2.41 |

The resize control also captures pending GUI-thread event/deallocation work; its frees are not paired only with that segment's allocations. Preserve it as a separate result. Independent CPU ranges were 425.05–435.18 µs/stroke, 230.89–233.20 µs/note release, 475.80–491.99 µs/automation release, 6,916.11–7,003.44 µs/resize turn and 2.34–2.70 µs/empty turn. JSON preserves every allocation/byte/free range and raw phase record. These are a reusable baseline, not new optimization or statistical performance claims.

- `deno task bench:allocations:check`: seven parser/report consumer-contract tests passed; both TypeScript files typechecked. Profiling dylib compiled with `-std=c11 -O2 -Wall -Wextra -Werror` in both modes.
- Normal `deno task checks --filter swiftcore-projectsession --filter swiftcore-playback-audition --verbose`: 2/53 passed, 51 skipped. Production `tst_SwiftRollSelection.qml` / `swiftroll-window`: 1/1 passed. New resize fixture without allocation environment: 1/1 passed in its ordinary opt-out path, without loading the recorder.
- The first resize capture passed geometry/capture but failed teardown's catalog-retention predicate. Restored the existing fixture's catalog-readiness/persistence prerequisites and production page-release acknowledgment; amended allocation/CPU smoke and all warmed resize runs passed. No failed predicate was removed or hidden.
- Bridge guard: zero baselined findings. Explicit changed-Swift format check passed. Swift LSP index still reports 0/0 targets; actual compilation and state predicates, not empty references, establish correctness.
- Independent recorder/runner and scenario/spec gates: Approved, no critical or important findings. Kept the fixed per-process output binding, standard cwd-relative output paths and intentionally symmetric empty-turn signature; no extra abstraction or observer work was added for advisory polish.
