# macOS Playhead Renderer Performance Report

**Date:** 2026-07-24  
**Candidate:** CALayer playhead working-tree changes atop `fb8f218`  
**Baseline:** `fb8f218726a36b9670c3f5089c57866b601ae7dd` (`Harden timeline cache updates`)

## Conclusion

The CALayer renderer materially reduces playback cost compared with the pre-CALayer QWidget renderer. Across matched visible-window measurements, process CPU fell by 56.0%, process cycles fell by 49.3%, main-thread cycles fell by 50.5%, and system-call count fell by 82.2%.

The implementation should retain its current hot path: two layer-position mutations in one disabled-action Core Animation transaction. Two additional micro-optimizations were measured and rejected because neither demonstrated a reliable improvement.

## Build configuration

All measured executables were configured as `RelWithDebInfo`, not pure `Release`:

| Build | CMake build type | Compiler flags |
|---|---|---|
| Active `build/porydaw.app/Contents/MacOS/porydaw` | `RelWithDebInfo` | `-O2 -g -DNDEBUG` |
| CALayer candidate | `RelWithDebInfo` | `-O2 -g -DNDEBUG` |
| QWidget baseline | `RelWithDebInfo` | `-O2 -g -DNDEBUG` |

For comparison, this repository's pure `Release` configuration uses `-O3 -DNDEBUG`. `RelWithDebInfo` was used deliberately so Instruments could retain useful symbols while measuring optimized code.

## Method

- Both variants were built from the same `fb8f218` revision; the candidate additionally contained the current CALayer working-tree changes.
- Candidate worktree: `.worktrees/playhead-candidate-benchmark`
- Baseline worktree: `.worktrees/playhead-baseline`
- Build system: CMake, `RelWithDebInfo`
- Fixture: `mus_lovely`
- Window state: native macOS window, confirmed `visible=1` and `exposed=1`
- Warmup: 2 seconds before measurement
- Clean CPU comparison: three interleaved 12-second runs per variant
- Instruments captures: CPU Profiler, CPU Counters, Core Animation signposts, Runloops, Thread State Trace, and System Call Trace
- Paint metrics were collected in a separate instrumented run so their event filter did not contaminate the clean CPU comparison.
- Temporary benchmark hooks were applied identically to both variants and removed after measurement.

## Clean process CPU

| Variant | Run 1 | Run 2 | Run 3 | Mean | Standard deviation | CV |
|---|---:|---:|---:|---:|---:|---:|
| CALayer | 8.366% | 8.662% | 8.528% | **8.518%** | 0.149 | 1.75% |
| QWidget baseline | 19.889% | 19.199% | 18.944% | **19.344%** | 0.489 | 2.53% |

**Difference:** -10.826 percentage points, or **-56.0% relative CPU**.

## CPU Counters

Ten-second CPU Counter captures produced the following process and main-thread totals:

| Metric | CALayer | QWidget baseline | Change |
|---|---:|---:|---:|
| Process cycles | 1,667,748,209 | 3,288,025,389 | **-49.3%** |
| Main-thread cycles | 1,420,069,706 | 2,866,111,973 | **-50.5%** |
| P-core cycles | 1,448,838,359 | 3,060,935,921 | **-52.7%** |
| E-core cycles | 218,909,850 | 227,089,468 | **-3.6%** |

The reduction is concentrated on the main thread and performance cores, which is consistent with removing QWidget repaint and composition work from each playhead tick.

## Scheduling and system-call demand

| Metric | CALayer | QWidget baseline | Change |
|---|---:|---:|---:|
| System calls | 53,296 | 299,180 | **-82.2%** |
| CPU time inside system calls | 950.0 ms | 2,601.2 ms | **-63.5%** |
| `sys_ulock_wait2` calls | 1,656 | 49,145 | **-96.6%** |
| `psynch_cvwait` calls | 1,421 | 43,765 | **-96.8%** |
| `sys_ulock_wake` calls | 2,104 | 62,774 | **-96.6%** |
| `psynch_cvsignal` calls | 1,428 | 43,772 | **-96.7%** |

This is the strongest evidence that the new renderer removes downstream backing-store and synchronization demand rather than merely moving CPU work to another application thread.

## Paint activity

A separate 12-second run counted real `QPaintEvent` traffic and dirty regions:

| Metric | CALayer | QWidget baseline | Change |
|---|---:|---:|---:|
| Paint events | 3,439 | 11,907 | **-71.1%** |
| Dirty pixels | 30,663,462 | 194,452,160 | **-84.2%** |
| Main-window paints | 636 | 1,285 | **-50.5%** |
| SongView paints | 1 | 706 | **-99.9%** |
| Piano-roll paints | 1 | 706 | **-99.9%** |
| Automation-area paints | 1 | 706 | **-99.9%** |
| Timeline content rebuilds | 3 | 3 | No change |

The equal content-rebuild count demonstrates that neither variant rebuilt cached timeline content because of playhead movement. The CALayer implementation additionally avoids the repeated QWidget presentation paints caused by the old renderer.

## Playhead hot path and Core Animation

- Candidate playhead synchronization intervals: 587 in ten seconds, or 58.7 Hz.
- Baseline playhead synchronization intervals: 586 in ten seconds, or 58.6 Hz.
- Candidate synchronization duration: 47.3 µs mean, 47.4 µs median, 72.5 µs p95.
- Baseline synchronization duration: 13.7 µs mean, 11.5 µs median, 27.3 µs p95.

The CALayer submission seam is locally more expensive, but it remains approximately 0.28% of one wall-clock second at 60 Hz and eliminates substantially more downstream repaint and scheduling work.

Whole-process Core Animation signposts showed:

| Metric | CALayer | QWidget baseline |
|---|---:|---:|
| Commit intervals | 897 | 828 |
| Mean commit duration | 113.5 µs | 159.0 µs |
| Total commit duration | 101.8 ms | 131.6 ms |

The commit counts include all application Core Animation work, not only the playhead. Playhead synchronization itself remained bounded to display cadence.

## Rejected optimization experiments

### Skip unchanged native-host synchronization

An early return was added when the native overlay frame was unchanged. It did not improve the measured synchronization interval:

| Variant | Mean | Median | p95 |
|---|---:|---:|---:|
| Current implementation | 47.294 µs | 47.417 µs | 72.500 µs |
| Host-frame early return | 48.118 µs | 47.000 µs | 72.709 µs |

The experiment was reverted.

### Remove the explicit Core Animation transaction

Relying on the run loop's implicit transaction produced highly variable clean CPU results: 4.12%, 7.40%, and 10.58%. It also removed the explicit atomic boundary around the two position updates. Because the result was not stable or demonstrably better, the explicit disabled-action transaction was retained.

## Allocation limitation

The position-only source path performs no explicit C++, Objective-C, Core Foundation, color, gradient, or path allocation. CPU Profiler samples attributed its work to Core Animation transaction and layer machinery rather than application allocation routines.

A zero-allocation claim could not be independently confirmed with the Instruments Allocations template: attaching to the running benchmark, launching through `xctrace`, and system-wide capture all failed because the template could not attach to this executable or does not support an all-process target. Therefore, zero steady-state allocation is source-verified but not Allocations-instrument verified.

## Artifact cleanup

The raw Instruments trace bundles and XML exports were removed after the measured results were transcribed into this report.
