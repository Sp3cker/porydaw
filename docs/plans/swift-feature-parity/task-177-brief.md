# Task 177 brief — the track-header input binds to the published headers geometry

# Context

The headers geometry probes landed with tasks 158/173, but the fork's header-surface
binding rows remain open: the track-headers quick surfaces (band, input, rows,
scrollbar) must be discovered and the header input item must be bound to the headers
presenter's published geometry — the input tiles exactly the published band, not a
stale or independent rect. These are the last hostadapter rows whose owners are the
clean track-header files.

Surface: the mounted track-header column's input surface (its geometry binding to
the published headers state).
Ledger spec: `src/checks/host/proof.tst_hostadapter.txt` A080 and A082 (2 GAP), fork
`drawerChromeAndQuickHeadersFollowCanonicalGeometry`
(`src/checks/host/tst_hostadapter.cpp:288,292` at pinned revision `c17d966f`): the
headers band/input/rows/scrollbar surfaces exist and the headers input is bound to
the presenter's geometry.
Verify lane: `deno task verify:qml-roll --filter swiftroll-window --verbose`.
Blocked rows left untouched: A079 (centring parity decision), A098 (hidden-band
chrome handle staging row), A118 (its mounted host is foreign-modified), A140
(OtherEvents raster, foreign).

# Exact write set

- `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml` — header input/rows/scrollbar discovery assertions and the input-geometry binding observation in the existing mounted journey.
- `src/swift/app/headers/TrackHeadersGeometry.swift` — conditional repair only if the input's geometry diverges from the published band.
- `src/checks/host/proof.tst_hostadapter.txt` — A080 and A082 only.

All three files are clean in `git status`.

# Prerequisites

Tasks 158/173's landed header rows are consumed unchanged. Disjoint from every
foreign file (no rendering files: the observations use item geometry and published
presenter state only). Read sprint-3 §21.

# Interface contract

The mounted journey resolves the real header surfaces (band, input, rows, scrollbar
object names) and asserts the input item's mapped geometry equals the published
headers band geometry — independently computed expectations, settle-based
observation (no same-GUI-pass claims). Discovery assertions carry no A-ids; the
binding observation carries A082's clause.

# Implementation steps

1. Add the surface-discovery assertions (setup, no A-ids).
2. Add the input-geometry binding observation against the published band.
3. Repair the geometry owner only if the binding actually diverges.
4. Close A080 (discovery, setup classification inside the mapping reason) and A082
   in the same commit. Compact form: header + `Disposition` + one S-citing mapping
   line; no pasted code.

# Acceptance predicate

The header input provably tiles the published headers geometry on the mounted
surface.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
deno task proof check --executed
```

# Task-specific constraints

No `tst_SwiftRollPlots.qml` (foreign-modified), no GridScene/PianoGrid/swiftroll
rendering files, no `ShellQmlEntries.swift`. DPR-dependent literals gate on the
lane's declared DPR.
