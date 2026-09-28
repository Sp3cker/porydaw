# Task 183 brief — mounted automation raster completes the pointer-visible pixel contract

# Context

The raster ledgers' open rows were recorded when "no Swift framebuffer readback"
existed. That is stale: `tst_EditorDrawerAutomationCurves.qml`,
`AutomationPreview.qml` and `AutomationHover.qml` already grab mounted frames
(`grabImage` + `PixelSupport.regionOf`) and assert ink at independently mapped
positions. What remains open is a bounded set of pixel conjuncts the executing
predicates never covered: the same-pixel idle comparison (A012), the second
leave restoring the full target pixel (A025), the origin phantom's center fill
(A033), the Pan+Tempo two-lane coverage of the drag raster (A037), the
post-leave complete snapshot (A044), the negative/away node-color probes
(painting A018, A023, A024, A026, A027), the transient-layer clears after an
activated-drag Escape and parameter switch (nodedrag A056/A057/A067, ownership
A103/A104), the isolated node-ring pixels (painting A018/A038, selection
reticle A048) and the DPR-2 pencil ink pixel (presentation A037).

Surface: the mounted automation drawer's rendered output — what the user sees
painted while hovering, dragging, selecting and cancelling.
Ledger spec:
`src/checks/automation/raster/proof.interaction.txt` A012/A032/A037/A044
(PARTIAL) and A025/A033 (GAP), fork `interaction.cpp:357,436,463,482,397,439` at
`c17d966f`;
`src/checks/automation/raster/proof.painting.txt` A018/A027 (PARTIAL) and
A023/A024/A026 (GAP), fork `painting.cpp:360,397,388,390,394` at `c17d966f`;
`src/checks/automation/proof.automationnodedrag.txt` A056/A057/A067 (PARTIAL),
fork `automationnodedrag.cpp:555,561,636` at `c17d966f`;
`src/checks/automation/proof.automationownership.txt` A103/A104 (PARTIAL), fork
`automationownership.cpp:425,434` at `c17d966f`;
`src/checks/automation/proof.automationpainting.txt` A018/A038/A048 (PARTIAL),
fork `automationpainting.cpp:98,183,235` at `c17d966f`;
`src/checks/automation/presentation/proof.tst_automationpresentation.txt` A037
(PARTIAL — DPR-2 pencil ink; the task-111 one-off PNG observation at
`/tmp/task111-dpr2-font12.png` is recorded in the ledger and is the mapping
oracle), fork `tst_automationpresentation.cpp:145`.
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose` (editorqml-drawer) and
`deno task verify --filter swiftcore --verbose` (painting_raster model legs).
Blocked rows left untouched: the retired layer-revision-counter conjunct inside
raster painting A018 stays representation — prove only its reticle endpoint
behavior conjunct; automationgesturecheck hover A030's framebuffer clause
(owned by task 184's snapshot surface) is not claimed here.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawerAutomationCurves.qml` — origin-phantom center fill, second-leave pixel restoration, hovered-vs-idle annulus comparison, Pan+Tempo drag raster.
- `src/checks/editorqml/tst_EditorDrawerAutomationPreview.qml` — transient-ink disappearance after activated-drag Escape and after parameter switch (nodedrag A056/A057, ownership A103/A104).
- `src/checks/editorqml/tst_EditorDrawerAutomationHover.qml` — second-leave and lane-transition clearing pixel conjuncts (interaction A025/A032 legs).
- `src/checks/editorqml/tst_EditorDrawerAutomationPresentation.qml` — DPR-2 pencil ink pixel (presentation A037), gated on the lane's declared DPR.
- `src/checks/automation/presentation/painting_raster.swift` — model-level conjuncts the mounted lane cannot see: post-leave complete snapshot (A044), retained-selection lane switch (painting A027).
- `src/checks/editorqml/EditorDrawerPixelSupport.js` — conditional shared probe helpers only.
- `src/ui/songview/quick/drawer/AutomationPage.qml`, `src/swift/app/drawer/automation/AutomationScene.swift`, `AutomationContentPublication.swift`, `AutomationOverlayPublication.swift` — conditional repairs only where a probe proves ink missing.
- The six ledgers above — named rows only.

# Prerequisites

The performance wave is committed at `0504b68b`; all write-set files are clean.
Existing `grabImage`/`PixelSupport` probes in the same files are the pattern.
Read sprint-3 §22.

# Interface contract

Every pixel expectation is computed from an independently projected position
(the existing `regionOf`/`nodeProbe` discipline), compared against a captured
idle or pre-gesture frame where the fork clause demands it. DPR-dependent
assertions gate on the lane's declared DPR; `verify:qml` runs DPR 1, so the
DPR-2 conjunct needs the lane's declared-DPR mechanism or stays in the
model-level host if no DPR-2 surface exists — decide before writing, escalate
if neither exists.

# Implementation steps

1. Extend the mounted pixel journeys with the missing conjuncts, one predicate
   per fork clause carrying its unique complete literal.
2. Add the model-level snapshot predicates in `painting_raster.swift`.
3. Repair production rendering/publication only where a probe proves ink
   missing.
4. Close the named rows across the six ledgers in the same commit, compact
   form — one task, one commit series, six ledgers.

# Acceptance predicate

Every named raster/painting/transient conjunct has executed mounted or
model-level evidence and the editorqml-drawer lane stays green.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

No framebuffer readback API, no baseline-image files, no `QImage` persistence —
`grabImage` on the mounted surface only. Do not touch `AutomationInteraction`/
`AutomationPointerDispatch`/`EditorDrawer.swift` (task 180's conditional set),
`tst_EditorDrawerAutomationCamera.qml`/`AutomationFocus.qml` (task 180), the
domain/gesture check files or `automationselection*.swift` (task 184), or
`tst_ShellWindow*.qml` (tasks 179/181/186).
