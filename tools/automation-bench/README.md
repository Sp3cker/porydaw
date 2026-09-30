# Automation editing microbenchmark

macOS CLI benchmark linked against the real optimized Porydaw Swift modules.
A native `QGuiApplication` supplies the event loop and font services; **no QML
engine, window, rendering, or audio device is created**. The workload uses
`AutomationPage` → transactions/resolvers → `SongDocument` → history and
`DocumentSession` playback-timeline rebuilds. Swift display-list construction,
list-model updates, and queued QtBridge notification flushes are included.
This is the automation page/session path, not the entire workspace's sibling
presenters or actual playback-engine submission.

## Build and run

From the `automation-bench` worktree:

```sh
deno task automation-bench:build
build/release/automation-bench --list
build/release/automation-bench --iterations 100 --nodes 32,128,1024
build/release/automation-bench --filter node.moveOverwritesOccupied --lane pan --nodes 1024
```

The build uses the repository Deno build runner, production Release optimization,
and debug information, then emits `build/release/automation-bench.dSYM`.
The benchmark target is excluded from ordinary all-target builds. This worktree
also enables Swift debug symbols on the linked production modules for profiling.

Default: all five representative lane families (Pan, Volume, XCMD Echo volume,
Pitch bend, Tempo), 128 written nodes, 16 pointer samples, 5 warmups, 100 measured
repetitions. There are 64 scenarios; projected-origin and duplicate-CC cases run
only for Pan/Volume. These lane families
exercise CC, special XCMD encoding, signed bend, global tempo, neutral snapping,
and engine-default-node promotion. Not every individual catalog controller is
a separate lane selection.

## Instruments

```sh
cd /Users/sallegrezza/dev/cProjects/porydaw/.worktrees/automation-bench
xctrace record --template 'Time Profiler' \
  --output /tmp/automation-overwrite.trace \
  --launch -- "$PWD/build/release/automation-bench" \
  --filter nodeScaling.releaseOverwriteOccupied --lane pan --nodes 1024 \
  --notes 512 --tracks 4 \
  --iterations 100 --seconds 30
open /tmp/automation-overwrite.trace
```

For the Instruments GUI: choose **Time Profiler**, select
`build/release/automation-bench` as the launch target, and supply the same CLI
arguments. Keep the adjacent `.dSYM`; drag it into Instruments if symbols do not
resolve automatically. For allocation analysis use **Allocations** instead.

The `org.porydaw.automation-bench` / `PointsOfInterest` signpost category marks each measured
**Automation edit** interval with its scenario name. Select those intervals in
Instruments to exclude setup and validation; the process-wide profile includes
both. `--filter` isolates a scenario without needing signpost selection.
`--no-signposts` disables interval emission for standalone latency measurements.

## Scaling workloads

All dimensions are independent scalar CLI arguments, except `--nodes`, which
still accepts a comma-separated sweep. Notes are evenly distributed over the
same song duration; adding tracks does not change the active automation lane.
Each fixture verifies the requested engine-track and paired-note counts.

| Argument | Workload |
| --- | --- |
| `--notes N`, `--tracks N` | Paired notes per track and 1...16 tracks; defaults 1/1 |
| `--selected-nodes N` | Selected node block in the group-preview case, capped to `--nodes` |
| `--visible-nodes N` | Beat slots across the 480px plot, 1...100; default 0 preserves native zoom |
| `--duplicate-occupants N` | Same-tick CC destination occupants; default 2 |
| `--bulk-points N` | Identical clip size at track start/end, capped to `--nodes - 1` to keep positions distinct; default 32 |
| `--history-depth N` | Prior successful edits seeded outside timing in sustained cases; default 0 |
| `--edits N` | Successful operations/cycles within a retained-document batch; default 100 |

```sh
# One-node release versus unrelated notes/tracks. Repeat with other densities.
build/release/automation-bench --filter nodeScaling.releaseOverwriteOccupied \
  --lane pan --nodes 128 --notes 1000 --tracks 8 --iterations 200

# Pointer updates only: press/arming are untimed, no commit, exact preview checked.
build/release/automation-bench --filter nodeScaling.pointerCadenceSelectedGroup \
  --lane pan --nodes 1024 --selected-nodes 64 --visible-nodes 64 --samples 64

# Matched-size start/end paste, undo and redo against a dense note stream.
build/release/automation-bench --filter bulk. --lane pan --nodes 4096 \
  --notes 4096 --tracks 8 --bulk-points 512 --iterations 10

# One document retains history throughout each timed batch.
build/release/automation-bench --filter sustained. --lane pan --nodes 128 \
  --notes 1000 --tracks 8 --history-depth 500 --edits 1000 --iterations 1 --warmup 0
```

The node-scaling cases separate pointer cadence, repeated identical/sub-cell
input, release-only overwrite and dense duplicate-destination overwrite.
Selected blocks use a coarse-snap-aligned grab so normal press arbitration
does not clear the selection at low zoom. Unpickable configurations fail
descriptively rather than silently benchmarking another gesture.

Bulk placements use identical clips and file shapes. The timed paste includes
the production cursor/selection refresh and camera reveal: end placement can
also pay for scrolling. Undo checks complete saved-song restoration; paste/redo
check exact lane contents and preservation of other lanes and every track's notes.

Sustained cases cover accumulated commits, edit/undo/redo, edit/undo with redo
branch replacement, and traversal of retained undo/redo history. Draft text and
pointer paths are prepared outside timing. New pointer and sustained batches
flush queued QtBridge notifications after every operation, not only at batch end.

For memory analysis, launch `sustained.prompt.commit` with **Allocations**;
compare retained allocations before/after a batch and after fixture teardown.
Preparation/validation buffers and history seeding are visible process-wide,
outside the edit signposts. Increasing `--history-depth` also increases untimed
setup; do not interpret setup allocations as editing leaks.

Allocations capture requires debugger attachment authorization. On the current
workstation, a 15-second bounded CLI capture reports “Failed to attach to target
process”; `DevToolsSecurity -status` reports developer mode disabled. Time
Profiler capture succeeds. Authorize developer debugging before retrying
Allocations; no machine security settings are changed by the benchmark.

Time Profiler call stacks expose resolver, event-array mutation, history,
`PlaybackTimeline.build`, projection and display-list work without production
timing hooks. Workspace sibling presenters, QML and engine submission remain
excluded: this harness cannot establish whole-application frame latency.

## Timing and correctness

CSV output reports min/p50/p95/max/mean **microseconds per whole sample/batch**.
`operations` counts pointer updates, commits, undo/redo calls, or one atomic edit.
`p50_amortized_us`/`p95_amortized_us` divide batch percentiles by this count;
they are **not individual-operation latency percentiles**. Use `--samples 1`
for one-update pointer samples. Dimension columns record the workload settings
and effective camera pixels per beat. Node gestures use `--samples`; drawing gestures interpolate
that many pointer moves across a fixed visible span. `--nodes` scales document
size, not the drawing viewport or pointer travel.
Prompt acceptance, undo, redo, rejection, and cancellation scenarios are single
operations. `--seconds` is a minimum wall-time per scenario/lane/size, **including
untimed fixture work**; it is not the reported edit duration.

Each repetition starts with a fresh synthetic document/session/page. Fixture
construction, synthetic-project/bank loading, scenario preparation, correctness
validation, and teardown are outside the timer. Warmups use the same path but
are not recorded. The production action and a QtBridge event-loop flush are
timed. A validation failure terminates with a nonzero exit, naming the scenario,
lane, and dataset size; timings are never silently accepted for the wrong action.
A scratch project is created in the OS temporary directory and removed on exit.
No user project/preferences or system clipboard are edited.

Coverage includes node value/time edits, fine/neutral-snap modes, occupied-tick
collision and selected-group movement/clamping, stationary delete/no-op,
projected-origin promotion/no-op, existing/empty/occupied prompt edits, duplicate
occurrence editing versus whole-tick overwrite,
invalid/stale/same-value rejection, snapped/freehand/locked pencil, sweep/ramp
with held-tail preservation, multi-lane range deletion, lane clear/replacement,
range-paste overwrite, undo/redo/cycle for node overwrite and drawing, cancellation,
and stale commit rejection.
Use `--list` for the exact runnable scenario names.

Range clipboard data is extracted, encoded, decoded, rescaled and pasted in
memory through production semantics. Lane clipboard scenarios use the page's
local clipboard. The OS clipboard transport and QML menu/input controls are
intentionally excluded. Stale page-input cases measure rejection after the
session's document-change callback invalidates the capture; the separate frozen
commit case exercises the commit revision gate directly.

Smoke verification:

```sh
build/release/automation-bench --iterations 1 --warmup 0 --nodes 4,128 --edits 5 --history-depth 3
```

This exercises all 64 scenarios across 610 applicable scenario/lane/size combinations.
