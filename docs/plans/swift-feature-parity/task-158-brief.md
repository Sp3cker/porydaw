# Task 158 brief — mounted band plot/visibility projection completes canonical geometry

# Context

Finish the canonical band-geometry projection residues the mounted ruler/roll/Other
Events journey already half-proves. `tst_SwiftRollTrackHeaders.qml::
test_mountedRulerRollVelocityAndDrawerChromeGeometry` is the existing mounted host for
per-band geometry (it anchors S078–S092); the unproved residues are the track-header
band's empty plot, the per-band plot and visibility projection, the ruler gutter
bounds, the roll gutter vertical bounds, and the Other Events physical input
visibility. The fork's `canonicalGeometryProjectsToQuick` read C++ root properties;
the Swift consumer equivalents are the published per-section/per-band state and the
physical input items the mounted surface actually renders.

Selected **7 open rows (3 GAP + 4 PARTIAL)** in `src/checks/host/proof.tst_hostadapter.txt`
(pinned revision `c17d966f`, `src/checks/host/tst_hostadapter.cpp`,
`canonicalGeometryProjectsToQuick`):

| Target A-ids | Fork lines / clause |
|---|---|
| A026 (GAP) | 131 — the TrackHeaders band's plot rect is empty (headers own their layout, no plot projection) |
| A033 (PARTIAL) | 169 — every band's geometry entry exists once mounted |
| A034 (GAP), A035 (GAP) | 170,171 — each band's plot rect and visibility are projected for consumption |
| A036 (PARTIAL) | 173 — ruler gutter existence/bounds and mapped geometry (origin/edge/containment already proved by S079/S082/S085/S088) |
| A037 (PARTIAL) | 176 — roll gutter vertical bounds (split origin/edge/containment/width proved by S080/S083/S086/S089/S092) |
| A038 (PARTIAL) | 179 — Other Events physical input visibility (origin/edge/containment/gutter dimensions proved by S081/S084/S087/S090/S091) |

Setup-only rows: none selected (A031/A032 fixture guards and the capture preamble stay
unselected). The fork's `physicalInputsMatchCanonical` root-property comparison retires
as harness representation inside the mapping reasons; the observable contract — each
band's plot input and gutter input exist, are effectively visible while the band is
visible, and map inside the band's published geometry — is what gets proved.

# Exact write set

- `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml` — `test_mountedRulerRollVelocityAndDrawerChromeGeometry` only.
- `src/checks/host/proof.tst_hostadapter.txt` — A026, A033–A038 only (shares the ledger with Task 156 over disjoint rows).
- Conditional production repair, only if the journey exposes a real defect: `src/swift/app/headers/TrackHeadersGeometry.swift`.

# Prerequisites

Task 156's accepted `proof.tst_hostadapter.txt` rows land first (single ledger writer
applies disjoint accepted subsets serially); the QML work may proceed in parallel. Read
sprint-3 §18 for shared constraints.

# Interface contract

Preserve `TrackHeadersPresenter`/`TrackHeadersGeometry` publication and the mounted
input object names the journey already resolves (`timelineRulerInput`,
`timelineRulerGutterInput`, `timelineRollInput`, `timelineRollGutterInput`,
`timelineOtherEventsInput`, `timelineOtherEventsGutterInput`). A026 observes the
track-headers band's plot region as empty/absent through the published geometry; A034/
A035 observe per-band plot rect and visibility through the published section state and
the physical items; the three PARTIAL upgrades add the named gutter/input bounds and
visibility observations. Independent literal expectations for bounds; no canonical
C++-layout type, no root-property aliases, no same-GUI-pass claims.

# Implementation steps

1. Add the track-header plot observation (A026): the headers band publishes no plot
   extent while its own layout renders.
2. Extend the per-band loop with plot-rect and visibility observations anchored one
   message per clause (A033–A035).
3. Add the ruler gutter bounds, roll gutter vertical bounds, and Other Events input
   visibility observations (A036–A038 residues).
4. Update only the seven selected rows; retire the root-property projection note inside
   the mapping reasons.

# Acceptance predicate

Every mounted band's plot and visibility is observably projected, the headers band has
no plot, and all three gutters/inputs are bounded and visible on the production
surface. `RollQmlTests.swift` registers `swiftroll-window` and enumerates the file
automatically; no manifest change.

Named checks under §18 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
deno task proof check --executed
```

# Task-specific constraints

No `tst_SwiftRollPlots.qml` edits (Task 156 owns that file). No framebuffer readback,
no DPR-dependent literals beyond the lane's declared DPR, no hostadapter rows outside
the seven selected. A079's drawer-toggle centring and A140's loop-marker raster stay
untouched.
