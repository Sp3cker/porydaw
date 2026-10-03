# Task 109 brief — ready ruler controls expose bounded hover help

# Context

Mount the existing RulerToolTip on the real division/feel controls and prove ready-editor ruler, scroll and control behavior. Close the obsolete staged-native gate inventory alongside this visible change. Swift installs a tab only after DocumentSession.open has loaded the document; it has no publicly interactive MIDI-only half-ready tab. Do not reconstruct that deleted state to imitate the old fixture.

Verified planning selection: **61 open rows (55 GAP + 6 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/rollcheck/static/proof.gate.txt` — A001, A002, A003, A004, A005, A006, A009, A010, A011, A012, A013, A014, A017, A018, A019, A020, A022, A023, A024, A025, A026, A027, A028, A030, A031, A033, A034, A035, A036, A037, A038, A039, A040, A041, A042, A043, A044, A046, A047, A049, A050, A051, A054, A055, A057, A058, A061, A063, A066, A069, A072, A073, A074, A075, A076, A077, A078, A079, A080, A081, A082.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `90446f5dbbb9f9d9f9000d7819c42c1b8b2c5389`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift`
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`
- `src/ui/songview/quick/RulerToolTip.qml`
- `src/checks/rollcheck/static/gate.swift`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/rollcheck/static/proof.gate.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 precede Group A. Rebase PianoGrid and the shell-grid lane over 102/105. Read SongTabsController.install and DocumentSession.open as the loading boundary; do not edit their lifecycle in this task. The tooltip becomes part of the EditorSurface consumed by 114 after the Group A checkpoint.

# Interface contract

- Reuse `RulerToolTip.qml`; mount it outside the clipped `rulerControls` item in `EditorSurface.qml`. Add the inline `GridRowControl.controlToolTip` contract and bind its actual hover state, anchor rectangle and font/palette to the tooltip. Division help is the fork literal: `Editing snap grid. Auto follows the zoom one step finer than the drawn grid; a fixed division snaps to that note value; Clock snaps to the mid2agb clock grid.` Feel help is `Straight or triplet beat subdivisions.` Do not invent a parallel tooltip component.
- Tooltip geometry stays inside the real canvas, below the row when room exists, with bounded width/height and no clipped overlay. Leaving either control hides its tooltip. Replace touched tooltip padding/gap constants with base-font-scaled geometry; keep palette-owned text/background contrast and the existing above-row fallback. Preserve grid-menu activation and single window key authority.
- Preserve behavioral rows A042/A043/A044/A049/A051/A057/A058/A063/A075/A077/A078/A079/A082: a completely loaded editor is ready; division/feel text and help match their canonical state; roll/ruler/scrollbars/headers/Event List/drawer controls are live; ready ruler clicks change the edit cursor and finish without a gesture; ready scrollbar wheels change scroll; real hover shows the correct tooltip at the prescribed bounds and leave hides it. Enumerate each fixed surface, not a generic root-enabled assertion.
- The other 48 selected rows pin deleted native fixture setup, half-ready fresh/MIDI-only stages, their no-input transitions, or native window/item guards. Account for them explicitly as retired staged representation, citing SongTabsController's install-after-load boundary and DocumentSession.open. Ready-wheel tests do not prove a nonexistent gated stage. Retain a mounted no-song → loaded-song journey to verify the replacement architecture exposes no editing surface before load; do not invent asynchronous partially-bound tabs, MIDI-only state or test flags.

# Implementation steps

1. Add the production tooltip bindings to the inline GridRowControl and reuse RulerToolTip at the unclipped overlay level; retain existing menu routing and replace only touched tooltip geometry constants with base-font ratios.
2. Extend runGateChecks in static/gate.swift for the loaded-state/ruler/scroll domain consequences and tst_ShellGridInput for no-song→ready presentation, each fixed input surface and both real hover tooltips.
3. Repair any selected ready-input defect in PianoGrid without altering loading ownership. Explicitly inventory the 48 retired native/staged rows against the current install boundary; do not map them to unrelated ready-state anchors.
4. Close and delete the gate ledger with executing mounted tooltip and ready-editor predicates, preserving existing ready-wheel checks and the loaded-state behavior.

# Acceptance predicate

SessionChecks already registers runGateChecks in swiftcore-projectsession. The shell-grid-input lane must execute both tooltip hovers/leaves and the ready input journey, not merely compile RulerToolTip. All 61 selected rows are explicitly matched or retired on their own terms and the gate inventory closes.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No SongTabsController, DocumentSession, loading pipeline or fixture-content writes. Do not claim that absence of a partially loaded page is a behavioral replay of the deleted QWidget staged test; record the architecture retirement explicitly.
