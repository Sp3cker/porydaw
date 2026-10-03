# Task 160 brief — mounted scroll/zoom frame cadence closes the swiftrollbench ledger

# Context

The deleted native `swiftrollbench` lane left six GAP rows that are real render-liveness
obligations, not timing trivia: the mounted roll must publish its band rect, the render
loop must be live, and paced alternating wheel phases must swap a floor of frames while
actually moving the viewport. The roll QML lane now provides everything the old C++
harness lacked: a real window hosting the production `SwiftRollOverlay`, real wheel
input, and observable camera state. A new suite file is enumerated automatically
(`RollQmlTests.swift` spawns one child per `tst_*.qml` in the input directory), so no
manifest or runner edit is needed.

Selected **6 GAP rows (A009–A014)** — the entire open remainder of
`src/checks/swiftrollbench/proof.tst_swiftrollbench.txt` (pinned revision `65a72a95`,
`SwiftRollBenchTest::testScrollZoomFrameCadence`, `src/checks/swiftrollbench/tst_swiftrollbench.cpp`):

| Target A-ids | Fork lines / clause |
|---|---|
| A009 | 160 — the roll band rect is valid and nonempty before the cadence |
| A010 | 183 — the Quick window swaps at least one frame before the measured phases (warm-up) |
| A011 | 231 — the scroll phase swaps at least 24 frames |
| A012 | 233 — the zoom phase swaps at least 24 frames |
| A013 | 235 — the scroll phase moves the active roll's viewport |
| A014 | 236 — the zoom phase moves the active roll's viewport |

Fork pacing constants (independent literals, `65a72a95:tst_swiftrollbench.cpp:39-45`):
notch ±120, 120 scroll iterations, 60 zoom iterations, 16 ms pace, 250 ms settle,
5 s warm-up deadline, 24-frame floor. The fork alternated notch direction per iteration
because a single direction saturates the scroll/zoom clamp and would time an idle
window; preserve the alternation. **Whole-ledger closure**: the other eight rows are
RETIRED-REPRESENTATION; closing A009–A014 disposes every row, so the ledger is deleted
in the same commit (its C++ source was already deleted in `67544720`).

# Exact write set

- `src/checks/rollqml/tst_SwiftRollCadence.qml` — new suite file (bootstrap pattern from `tst_SwiftRollPlots.qml:24-119`).
- `src/checks/swiftrollbench/proof.tst_swiftrollbench.txt` — deleted (whole-ledger closure).

# Prerequisites

None. Disjoint from Tasks 156/158 (different suite files, same lane). Read sprint-3 §18
for shared constraints and native desktop requirements.

# Interface contract

The suite stages the `mus_route101` fixture through `RollQmlBootstrap` + `ApplicationSession`,
mounts the production `SwiftRollOverlay`, and observes: the mounted roll band rect
(A009); frame swaps on the window hosting the overlay (count `afterRendering` emissions
of the window resolved from the overlay — `Window.window`/`Item.window`, A010); the
camera/viewport movement token (published scroll/zoom state on the grid presenter,
A013/A014); and the per-phase frame counts over paced alternating `mouseWheel` notches
at the roll band center, Ctrl for the zoom phase (A011/A012). Constants are independent
literals from the fork; warm-up discards its stamps; each phase settles before the next.

# Implementation steps

1. Bootstrap and mount as `tst_SwiftRollPlots.qml` does; assert the band rect first.
2. Attach the frame counter; warm up until one swap lands inside the 5 s deadline.
3. Run the scroll phase (120 alternating notches, 16 ms pace), settle 250 ms, record
   frames and movement; repeat for the zoom phase (60 notches, Ctrl).
4. Assert the four cadence/movement clauses with uniquely anchored messages.
5. Close A009–A014 MATCHED with executed anchors and delete the ledger, citing the
   pinned revision and the `67544720` source deletion.

# Acceptance predicate

The mounted roll proves render liveness and viewport movement under real paced wheel
input, and the swiftrollbench ledger closes whole. One cadence run is the evidence;
per AGENTS.md do not re-stress the timing check repeatedly.

Named checks under §18 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
deno task proof check --executed
deno task proof list
```

`proof list` no longer reporting `src/checks/swiftrollbench/proof.tst_swiftrollbench.txt`
is part of the acceptance.

# Task-specific constraints

The 24-frame floor is a liveness floor, not a performance budget: do not lower it, and
do not add median/p95/max reporting obligations (those were the retired timing rows).
No presenter-only substitute; no `tst_SwiftRollPlots.qml`/`tst_SwiftRollTrackHeaders.qml`
edits. If the lane's declared DPR affects the band rect, gate literals on it.
