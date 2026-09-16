# Scope-refresh × salvage — comparison and integration position

Two plans, one direction, one real conflict. For the integrating agent.

## Plans

- **Salvage** (`state-tree-simplification` worktree, `docs/plans/state-tree-salvage/`):
  deletes `DrawerLiveDelta`/classifiers, keeps `DrawerPageLiveState` snapshots +
  `refreshLiveState` signatures, replaces `trackColor` with `int primaryTrack`,
  splits canvas geometry from adapter reconstruction. Written pre-camera-commits,
 VC aware of `c7a6d081`/`d3945f3d` as a newer baseline to preserve at integration.
- **Scope-refresh** (main checkout, `docs/plans/drawer-scope-refresh/`, anchors
  spot-verified): deletes snapshots AND delta, passes `DrawerScopes` flag-args on
  the existing `refreshDrawerPages` fan-out, pages read live sources in handlers.
  No Qt signals added; `TimeCamera` stays bool-return.

## Agreement (no action)

- Delete the delta/classifiers; page-owned refresh decisions.
- No new dispatcher, bus, or notification convention. Scope-refresh's scopes ride
  existing fan-out arguments — this already satisfies salvage's "no event bus /
  alternate dispatcher" constraint. Only the word "observers" in that clause
  needs narrowing: page handlers are existing callees with a new parameter, not
  subscribers.
- Scroll-frame budget: scroll shifts presentation only, proven by
  `contentBuildCount` counters + timelinepan/scrollbar harnesses.
- Priority (user-defined, both plans consistent): structural
  (`Document`/`Content`/`Selection`) > geometry (`Zoom`/`HorizontalScroll`) >
  transient (`Playhead`). Simultaneous multi-scope refreshes are defined-ordered,
  not preserved; rebuilds re-read live so misordering costs at most one wasted
  presentation shift.
- Salvage task 2 (geometry vs adapter-storage split) is orthogonal; untouched by
  either side of this dispute. Keep as-is.

## Conflicts and positions

1. **Snapshots: delete.** Salvage's "keep `DrawerPageLiveState`" clause goes;
   scope-refresh's live-source map replaces it (anchors verified:
   `drawercoordination.cpp:122-132` publisher,
   `songdocument.h:144`, `songview.h:272,278`, `timecamera.h:40-43`). The
   user's stated position is no stored per-page state; the gesture-start
   revision capture is the one permitted retained value (gesture state, not a
   snapshot — scope plan Global Constraints already draw this line).
2. **trackColor: take salvage's version.** Salvage replaces the color proxy with
   `int primaryTrack` identity and constrains fixtures to tracks 0–15; scope
   plan reads `SongView::trackColor(primaryTrack())` live, which preserves the
   proxy salvage explicitly kills on ownership grounds. Adopt identity in the
   scope arms; derive color at paint time only (velocity already resolves
   through its own path — salvage source-evidence section).
3. **Baseline / execution order.** Scope-refresh is written at main `d3945f3d`.
   The worktree predates the camera commits and holds dirty Task 3/4 work in
   `automationpage.cpp`, `voicechangearea*.cpp`, `velocityarea.cpp`,
   `drawerpage.h` — the exact files scope tasks 2–3 rewrite. Scope task 1
   (fan-out: `drawercoordination.cpp`, `camera.cpp`, `songview.cpp`, `grid.cpp`,
   `viewstate.cpp`, `songview.h`) touches files that are clean in the worktree
   and can land on main first. Tasks 2–3 must sequence after the worktree's
   dirty files settle or be integrated file-by-file; do not run a parallel
   batch against the dirty baseline (salvage plan already prohibits this).

## Suggested integration sequence

1. Contract-correct salvage: strike keep-snapshots, narrow the observers clause,
   adopt positions 1–2 above. One-paragraph correction, not a rewrite.
2. Execute scope task 1 on main (merge-clean vs worktree).
3. Settle worktree Tasks 3/4, integrate with camera commits + scope task 1.
4. Execute scope tasks 2–3 on the single baseline, then salvage task 2.
