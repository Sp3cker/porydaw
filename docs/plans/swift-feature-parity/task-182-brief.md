# Task 182 brief — every drawer band publishes its geometry through show, hide and Event List swap

# Context

Four hostadapter rows pin the published band-layout contract that the mounted
drawer must satisfy and currently has no executed predicate for: hiding a
drawer section clears every projection including the chrome handle rect
(A098), showing the Event List removes the roll from the canonical band layout
(A113's unproved conjunct) and restores it on dismissal (A118), and the
other-events band keeps a published geometry after a loop-marker timeline
update (A140). The mounted lane already proves the neighboring rows
(`test_rollBandGeometryAndLifecycle`, `otherEventsProjectionHoverAndWheel`), so
these are missing observations on a working surface, not missing features —
except possibly the hidden-band chrome-handle projection itself.

Surface: the mounted drawer's published band geometry — the band-layout rects
every page, the scrollbar and the Event List swap all read.
Ledger spec: `src/checks/host/proof.tst_hostadapter.txt` —
A098 (GAP, fork `tst_hostadapter.cpp:357` `hiddenBandsClearEveryProjection` at
`c17d966f`), A113 (PARTIAL conjunct, fork `:405`), A118 (GAP, fork `:416`), A140
(GAP, fork `:507` `loopMarkersReachTimelineButNotTheOtherEventsRaster`).
Incidental anchor landings while the tooltip surface is being re-pinned in the
same commit: A123, A129, A131, A132, A133 (the OtherEvents tooltip predicates
S069/S074–S076 already execute; their Swift `tryCompare` assertions carry no
message anchor — give them the source literals so those conjuncts close inside
this surface's commit).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose` and
`deno task verify:qml --verbose` (editorqml-drawer) plus
`deno task verify --filter swiftcore-projectsession --verbose` for the
other-events model leg.
Blocked rows left untouched: A079 (centring parity decision), A095 (QtBridge
queued same-GUI-pass residue), A096/A097 and all matched neighbors.

# Exact write set

- `src/checks/rollqml/tst_SwiftRollPlots.qml` — extend `test_rollBandGeometryAndLifecycle` (or a sibling journey in the same file): hiding each drawer section empties the published band rect and hides its plot/gutter inputs; showing the Event List removes the roll band from the published set and restores it on dismissal; independently computed rect expectations.
- `src/checks/editorqml/tst_EditorDrawerChrome.qml` — the other-events band's published geometry survives a loop-marker timeline update (A140), and the chrome handle rect clears when its section hides (A098's chrome-handle conjunct).
- `src/checks/drawerpresentation/other_events_band.swift` — conditional model predicate for the post-update band geometry if the mounted probe needs a model-level conjunct.
- `src/swift/app/drawer/EditorDrawerLayout.swift` — conditional repair only if a hidden band leaks a rect or the Event List swap does not restore the roll band.
- `src/swift/app/drawer/EditorDrawer.swift` / `EditorDrawerTypes.swift` — conditional repair only, same condition.
- `src/checks/host/proof.tst_hostadapter.txt` — A098, A113, A118, A140, and the tooltip anchor rows A123/A129/A131/A132/A133.

# Prerequisites

Tasks 173/177's landed band-set and header rows are consumed unchanged. All
write-set files are clean at `0504b68b`. Read sprint-3 §22.

# Interface contract

Predicates observe only published presenter/layout state and mounted item
visibility/geometry — no rendering, no `timelineBandLayout` replica. Band
identity comes from the published layout enumeration; expected rects are
computed independently from the mounted geometry. The tooltip anchor landings
change only the message anchors of predicates that already execute; no new
tooltip behavior is claimed.

# Implementation steps

1. Add the hide-every-projection predicates per band (velocity, automation,
   voice changes): published rect empty, inputs hidden, chrome handle cleared.
2. Add the Event List remove/restore band-layout predicates.
3. Add the post-loop-update other-events band geometry predicate.
4. Add the five tooltip message anchors to the executing Swift/QML predicates.
5. Repair `EditorDrawerLayout` only where a published rect actually diverges.
6. Close the named rows in the same commit, compact form.

# Acceptance predicate

Every drawer band's published geometry tracks show/hide and the Event List
swap, and the other-events band keeps its rect after a loop-marker timeline
update, with executed evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No `timelineBandLayout` reimplementation in the check — observe the published
surface. Anchor landings stay inside the five named tooltip rows; no other
re-pinning. Do not touch `tst_EditorDrawerAutomation*` files (tasks 180/183/184)
or `GridScene`/`PianoGrid` internals. This task is the sole wave-22 writer of
the hostadapter ledger.
