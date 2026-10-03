# Task 156 brief — drawer-band resize, hide and restore geometry on the mounted roll

# Context

Close the mounted drawer-band geometry lifecycle that `tst_SwiftRollPlots.qml::
test_hostMountedBandsResizeHideAndEventList` already drives but leaves partly
unanchored. The journey exercises the production `EditorDrawerPresenter`/
`EditorDrawerLayout` owners through real `setSectionVisible(kind, visible, persist)`,
`adjustResizeHandle(kind, direction)` and `section(kind)` calls; most clauses already
have observations that only need uniquely-anchored messages, plus three missing
observations (initial per-band geometry anchor, published-section equality after
resize, restored visibility/input tiling).

Selected **9 open rows (3 GAP + 6 PARTIAL)** in `src/checks/host/proof.tst_hostadapter.txt`,
at pinned revision `c17d966f` (`src/checks/host/tst_hostadapter.cpp`):

| Target A-ids | Fork lines / clause |
|---|---|
| A093 (PARTIAL), A094 (PARTIAL), A096 (PARTIAL) | 316,320,327 — `bandGeometryPublishesWithTheChoreography`: initial mounted band geometry exists; the velocity body changes after a real resize; the resized body/handle geometry follows the published section |
| A101 (PARTIAL), A102 (GAP), A103 (GAP) | 365,366,367 — `hiddenBandsClearEveryProjection`: a hidden section has no active body extent, is no longer visible, and publishes an empty rect |
| A107 (PARTIAL), A108 (GAP), A109 (PARTIAL) | 387,388,389 — restoring the section regains its exact prior geometry, is visible again, and its plot/gutter inputs tile the published section geometry |

Setup-only rows: none selected. A095 (`:321`) stays PARTIAL — its same-GUI-pass
canonical publication clause cannot be proven through queued QtBridge notifications.
A097 (`:328`, MATCHED) and A098–A100 stay unchanged; A098 is `host.prepare()` setup,
A099/A100 are RETIRED-REPRESENTATION. The fork's root-property reads
(`root->property(...)`) are C++-harness projection; the Swift consumer equivalent is
the published section state and the physical QML items, which is what this journey
observes — do not restore old root aliases.

# Exact write set

- `src/checks/rollqml/tst_SwiftRollPlots.qml` — `test_hostMountedBandsResizeHideAndEventList` only: anchored messages for the existing observations plus the three missing ones.
- `src/checks/host/proof.tst_hostadapter.txt` — A093, A094, A096, A101, A102, A103, A107, A108, A109 only.
- Conditional production repair, only if the mounted journey exposes a real defect: `src/swift/app/drawer/EditorDrawerLayout.swift` or `src/swift/app/drawer/EditorDrawer.swift`.

# Prerequisites

None. Task 154's picker rows are disjoint. Read sprint-3 §18 for shared constraints and
native desktop requirements.

# Interface contract

Preserve `EditorDrawerPresenter.setSectionVisible(_:_:_)`, `adjustResizeHandle(_:_:)`,
`section(_:)`, `setSectionBodyHeight(_:_:)` and the published per-section
`visible`/`bodyWidth`/`bodyHeight` state. Each selected clause gets exactly one
uniquely-anchored message literal in the existing journey; the restore leg must observe
`sameRect(sceneRect(body), saved)` plus the section's restored visible state and the
plot/gutter inputs' effective visibility against the republished geometry. Independent
literals for expected geometry; no runtime read-back substitutions.

# Implementation steps

1. Anchor the initial-band observation (all three bands' published nonempty bodies, one
   message per fork clause A093) and the plot-input activation already in the journey.
2. Anchor the resize leg: body height change plus handle/body adjacency (existing
   `:343-346`) and add the published-section equality — `drawer.section(1)`'s
   bodyWidth/bodyHeight must equal the physical body rect after the resize settles.
3. Anchor the hide leg per variant: no active extent (`!g.visible && bodyWidth === 0 &&
   bodyHeight === 0`), physical body not visible, and physical body rect empty.
4. Anchor the restore leg: exact prior rect (existing `restoreMessage`), restored
   visible state, and plot/gutter effectively visible with the republished geometry
   (`hostBandGeometry()` after restore).
5. Update only the nine selected ledger rows with their executed message anchors.

# Acceptance predicate

The mounted drawer's resize/hide/restore lifecycle is proven on the production roll
surface with per-clause executed evidence; A095's queued-notification clause remains
PARTIAL by design. `RollQmlTests.swift` registers `swiftroll-window` and enumerates
`tst_SwiftRollPlots.qml` automatically; no manifest change.

Named checks under §18 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
deno task proof check --executed
```

# Task-specific constraints

No same-GUI-pass geometry claims (QtBridge queues notifications; settle through
`tryVerify` as the journey already does). No Event List clause relabeling, no
`tst_SwiftRollTrackHeaders.qml` edits (Task 158 owns that file), no service-level
substitute for mounted geometry. DPR-dependent literals gate on the lane's declared DPR.
