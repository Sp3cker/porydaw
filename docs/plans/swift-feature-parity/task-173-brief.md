# Task 173 brief — showing the Event List removes the roll band from the published set

# Context

The mounted Event List toggle journey already observes that the roll plot and gutter
inputs hide, the velocity band stays available, and leaving Event List restores the
roll inputs — but the fork's stronger contract is that the roll band projection is
*removed* from the published band set while the Event List is shown, not merely
hidden, and the two rows that would anchor those existing observations
(A114/A118) carry no mapping. The missing observation is the published-band-set
absence; the existing predicates prove the rest.

Surface: the Event List toggle on the mounted roll window (band publication state,
not rendering).
Ledger spec: `src/checks/host/proof.tst_hostadapter.txt` A113 (PARTIAL), A114 (GAP),
A117 (PARTIAL), A118 (GAP), fork `eventListHidesOnlyRollProjection`
(`src/checks/host/tst_hostadapter.cpp:405,410,413,416` at pinned revision `c17d966f`):
the canonical band set excludes the roll band while Event List is shown; roll
input surfaces are hidden; velocity remains available; leaving Event List restores
the roll projection.
Verify lane: `deno task verify:qml-roll --filter swiftroll-window --verbose`.
Blocked rows left untouched: A079 (drawer-toggle centring parity decision), A140
(loop-marker raster), A026/A033–A038 (158's landed rows stay as landed).

# Exact write set

- `src/checks/rollqml/tst_SwiftRollPlots.qml` — `test_hostMountedBandsResizeHideAndEventList` Event List leg only: the published-band-set absence assertion plus anchored messages for the four clauses.
- `src/swift/app/` band-publication owner (`EditorDrawerLayout.swift` or the surface's published band-set property) — conditional repair only if the roll band is still published while hidden.
- `src/checks/host/proof.tst_hostadapter.txt` — A113, A114, A117, A118 only.

# Prerequisites

Task 158 landed (this ledger and `tst_SwiftRollTrackHeaders.qml` are free again; this
brief touches neither `tst_SwiftRollTrackHeaders.qml` nor any rendering file).
Disjoint from 167/168. Read sprint-3 §20.

# Interface contract

The published band state (the presenter/layout state the QML consumes —
`showEvents`, the surface's band set) must not list the roll band while Event List is
shown; the velocity band remains listed. The existing hidden-input/restoration
predicates get uniquely anchored messages so the four rows map to executed evidence.
Independent expectations; no pixel grabs.

# Implementation steps

1. Add the published-band-set absence observation to the Event List leg.
2. Anchor the existing hide/available/restore observations with unique messages.
3. Repair the publication seam only if the band set still lists the hidden roll band.
4. Close A113/A114/A117/A118 in the same commit. Compact form for closed rows:
   header + `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Showing the Event List removes the roll band from the published set and restores it
on exit, with the velocity band untouched — all observed on the mounted surface.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
deno task proof check --executed
```

# Task-specific constraints

No GridScene/PianoGrid/PianoRollCanvas/TimelineQuickItem/swiftroll-QML edits (the
forbidden rendering set); the observation uses presenter/layout state only. No
relabeling of 158's rows. A095-class same-GUI-pass claims stay out.
