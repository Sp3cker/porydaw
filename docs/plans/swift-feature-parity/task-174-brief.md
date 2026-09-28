# Task 174 brief — band geometry exists and survives appearance changes

# Context

Two service-observable band-geometry outcomes from the deleted host-integration
suite are unproved: the automation band's layout geometry is present during steady
playback (A008), and an appearance change preserves the automation band's presented
geometry (A142) — a user switching themes must not lose or corrupt the drawer band
layout. The existing `HostBehaviorChecks` band-geometry function measures origin and
edge relations but neither asserts presence during steady playback nor re-measures
across an appearance change.

Surface: drawer band geometry across playback and theme changes (published layout
state, not rendering).
Ledger spec: `src/checks/host/proof.tst_hostintegration.txt` A008 (GAP, fork
`steadyPlaybackIsPresentationOnly`, `src/checks/host/tst_hostintegration.cpp:184`)
and A142 (GAP, fork `appearanceNotificationPreservesAutomationRaster`, `:606`), at
pinned revision `c17d966f`. A142's raster half is already RETIRED; the surviving
clause is the geometry-preservation outcome.
Verify lane: `deno task verify --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: A162 (fixture fingerprint), A174–A185 (real window
close and teardown ordering), A083–A098 focus/grabber rows.

# Exact write set

- `src/checks/host/HostBehaviorChecks.swift` — `hostBandGeometry` only: presence-during-playback and appearance-change re-measurement predicates.
- `src/checks/host/proof.tst_hostintegration.txt` — A008 and A142 only.

# Prerequisites

Task 161's predicates in this file are consumed unchanged. Disjoint from every
sibling. Read sprint-3 §20.

# Interface contract

During steady playback (the existing playback-driving helpers in the lane's
fixtures), the automation band's layout entry exists with its measured geometry;
after applying a different appearance through the production appearance path
(`ShellAppearance.apply` via the presenter's restore/appearance entry point), the
band's measured geometry is identical to the pre-change capture. Independent literal
expectations for the measured values; comparisons only against pre-change captures.

# Implementation steps

1. Add the steady-playback presence assertion beside the existing geometry checks.
2. Apply an appearance change through the production path and assert the re-measured
   geometry equals the capture; repair the layout owner only if geometry is actually
   lost (conditional: `src/swift/app/drawer/EditorDrawerLayout.swift`).
3. Close A008 and A142 in the same commit. Compact form for closed rows: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

The band layout is present during playback and an appearance change leaves it
identical, with executed evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No rendering files, no raster/pixel obligations, no window-close claims. Physical
audio output is not claimed — playback is driven through the lane's existing
null-backend fixtures, and the predicates observe layout state only.
