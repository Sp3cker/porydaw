// Measured per-check walls, verbose suite run 2026-08-24 (M4, 10 cores).
// Used only for LPT ordering — heaviest first minimizes makespan — so coarse
// values are fine; they churn between machines and runs.
export const WALL_ESTIMATE: Record<string, number> = {
  "selftest-workspace": 0.3,
  samplecheck: 9.66,
  resonancecheck: 9.23,
  transportcheck: 3.77,
  vgsavecheck: 2.4,
  "automation-editing": 2.49,
  tabcheck: 2.35,
  "exportcheck-tail": 1.44,
  "exportcheck-loop": 1.3,
  // swiftcore family: split of the former bare-swiftcore single-process run
  // (all QTest slots via one unfiltered qExec) into per-suite entries. Each
  // entry stages the full swiftcore fixture union, so they schedule with the
  // export family instead of the 0.3 fallback. Re-measure per suite on the
  // next verbose run.
  swiftcore: 1.2,
  onboardcheck: 1.18,
  "host-integration": 1.1,
  rollcheck: 0.99,
  clickcheck: 0.84,
  polycheck: 0.83,
  sessioncheck: 0.8,
  rollwindowingcheck: 0.77,
  // mainwindow-routing (0.71) was retired by the input/state/lifecycle/native
  // split; its single measurement cannot transfer to four successors without
  // over-ordering them, so all four use the fallback until the next measured
  // verbose run.
  loopcheck: 0.65,
  roundtrip: 0.41,
  "velocity-page": 0.4,
  editcheck: 0.39,
  // Retired viewcheck/eventviewcheck rows measured 0.22/0.33; their coverage
  // is now the eventviews row family. The two direct successors inherit the
  // preserved measurements; the remaining family rows use the 0.3 fallback
  // until the first measured verbose run.
  "eventviews-chrome": 0.22,
  "eventviews-edits": 0.33,
  // velocity-editing: unmeasured (new pilot suite) — fallback-level estimate
  // until the first measured verbose run.
  "velocity-editing": 0.3,
  // Automation estimates measured during the offscreen migration verification.
  "automation-domain": 0.13,
  "automation-presentation": 0.37,
  "automation-hover": 0.31,
  vgcheck: 0.28,
  keymapcheck: 0.27,
  audiocheck: 0.25,
  smfcheck: 0.23,
  savecheck: 0.23,
  "host-seams": 0.23,
  mkcheck: 0.21,
  xcmdcheck: 0.2,
  primecheck: 0.2,
  "host-adapter": 0.2,
  "editor-drawer": 0.19,
  trackactivitymetercheck: 0.18,
  trackactivitycheck: 0.18,
  ignorecheck: 0.17,
  "velocity-model": 0.16,
  "trackactivitymetercheck-fractional-dpr": 0.16,
  selectioncheck: 0.16,
  scalecheck: 0.16,
  noteidcheck: 0.16,
  "production-startup": 0.14,
};

export function wallEstimate(name: string): number {
  const direct = WALL_ESTIMATE[name];
  if (direct !== undefined) return direct;
  // Family fallback: per-suite splits (e.g. `swiftcore-<suite>`) share the
  // measured family row so LPT still orders them as heavy. Only fires when
  // the pre-dash prefix is itself a table key; all other names keep 0.3.
  const dash = name.indexOf("-");
  if (dash > 0) {
    const family = WALL_ESTIMATE[name.slice(0, dash)];
    if (family !== undefined) return family;
  }
  return 0.3;
}
