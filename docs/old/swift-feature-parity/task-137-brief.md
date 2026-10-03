# Task 137 brief — editor bands share physical geometry and Other Events hover lifecycle

# Context

Complete the mounted editor host-composition surface: canonical plot/gutter tiling, drawer visibility and the Other Events tooltip. These clauses share the production band tree and one geometry verification surface; they are deliberately one task, not separate ledger-cleanup slices.

Selected **45 open rows (29 GAP + 16 PARTIAL)** in `src/checks/host/proof.tst_hostadapter.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A025, A026, A030, A031, A032, A033, A034, A035, A036, A037, A038, A039, A041 | `src/checks/host/tst_hostadapter.cpp:130,131,139,140,141,169,170,171,173,176,179,183,190` — `canonicalGeometryProjectsToQuick` |
| A069, A070, A080, A081, A082 | `src/checks/host/tst_hostadapter.cpp:256,259,288,291,292` — `drawerChromeAndQuickHeadersFollowCanonicalGeometry` |
| A093, A094, A095, A096, A097 | `src/checks/host/tst_hostadapter.cpp:316,320,321,327,328` — `bandGeometryPublishesWithTheChoreography` |
| A098, A101, A102, A103, A104, A105, A106, A107, A108, A109 | `src/checks/host/tst_hostadapter.cpp:357,365,366,367,382,383,384,387,388,389` — `hiddenBandsClearEveryProjection` |
| A113, A114, A116, A117, A118 | `src/checks/host/tst_hostadapter.cpp:405,410,412,413,416` — `eventListHidesOnlyRollProjection` |
| A123, A128, A129, A130, A131, A132, A133 | `src/checks/host/tst_hostadapter.cpp:437,456,457,464,478,480,481` — `otherEventsTooltipUsesTheQuickInputAndClearsOnLeave` |

# Exact write set

- `src/swift/app/drawer/EditorDrawerLayout.swift`
- `src/swift/app/drawer/otherEvents/OtherEventsBandPresenter.swift`
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`
- `src/ui/songview/quick/drawer/EditorDrawer.qml`
- `src/ui/songview/quick/drawer/OtherEventsBand.qml`
- `src/checks/rollqml/tst_SwiftRollPlots.qml`
- `src/checks/editorqml/tst_EditorDrawerChrome.qml`
- `src/checks/host/proof.tst_hostadapter.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted/checkpointed 130 before tst_SwiftRollPlots.qml reuse; accepted 123/124 and 119 before any shared drawer composition work. No change to their velocity/automation/raster rows.

# Interface contract

Use EditorDrawerLayout and the existing production QML band geometry, not obsolete host root-property aliases. For ruler, roll, Other Events and velocity prove plot origin at the shared split, right edge at the actual band edge, header nonintersection and mapped input bounds; include automation, voice changes and track headers in visibility/rect publication. Track headers have no timeline plot. Resize/reorder the existing drawer and prove the changed velocity band and adjacent chrome handle remain aligned. Hide/restore velocity, automation and voice changes one at a time: both input surfaces disappear, no stale active geometry remains, and exact geometry returns. Event List hides roll plot and gutter while velocity stays available, then restores the roll. Hover an actual Other Events marker: initially hidden tooltip, pointer-position projection, visible rendered label/scope/time, then pointer leave to ruler clears both text and visibility and hides the mounted tooltip. Repeat with cancellation. Retire only old item-pointer/interaction-pointer discovery and duplicate root-property plumbing, paired with actual mapped geometry and behavior; do not retire visibility or layout outcomes.

# Implementation steps

1. Extend the mounted plot-band table across all original bands and independent mapToItem coordinate calculations, retaining task-130 raster predicates unchanged.
2. Extend test_otherEventsProjectionHoverAndWheel with rendered tooltip text/position and pointer-leave clearing; use real pointer events rather than direct presenter hint assignment.
3. Repair only the declared layout/mount/tooltip owners; prove hidden sections cannot intercept input, then restore and interact again.

# Acceptance predicate

Mounted production bands and their physical inputs match independently calculated geometry through hide/restore/Event List transitions; real hover/leave clears the rendered tooltip. The selected roll suite covers canonical geometry; the drawer lane runs EditorDrawerChrome and the real OtherEventsBand.

Under sprint-3 §15 execution ownership, run:

```sh
PORYDAW_ROLL_QML_SUITE=tst_SwiftRollPlots.qml /usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
```

# Task-specific constraints

Set PORYDAW_ROLL_QML_SUITE=tst_SwiftRollPlots.qml for the roll command. This is geometry/tooltip proof, not framebuffer/DPR2 or native macOS host equivalence. Leave hostadapter A079 centring policy and all velocity gesture, solo/remap, automation transaction and loop-raster rows unchanged. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
