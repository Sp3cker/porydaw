# Task 162 brief — raster interaction residue: repeat leaves, hover clears and the voice cursor value

# Context

The mounted scrolled-phantom journey in
`src/checks/automation/presentation/painting_raster.swift` (executed by
`AutomationPageChecks` under `swiftcore-projectsession`) leaves five interaction clauses
from the deleted raster harness unproved: the second pointer leave's clear state, the
drag fixture's activation-distance precondition, post-commit hover clears (both the
release-without-leave case and the leave-after-commit case), and the voice cursor's
exact model value. All are model/state observations on the existing surface — no
framebuffer readback is claimed.

Selected **5 GAP rows** in `src/checks/automation/raster/proof.interaction.txt`
(pinned revision `c17d966f`, `src/checks/automation/raster/interaction.cpp`):

| Target A-ids | Fork lines / clause |
|---|---|
| A023 | 206 — a repeated pointer leave still observes the clear hover state |
| A026 | 246 — the drag fixture's vertical target exceeds the node-drag activation distance (staging validation) |
| A043 | 389 — releasing the drag without a leave leaves hover clear after commit |
| A046 | 413 — a pointer leave after commit clears hover state |
| A057 | 465 — the voice cursor's model value equals the original `cursorValue` |

Setup-only rows: A026 is a fixture-validation observation — report it as staging, not a
behavior A-id. The pixel-probe rows (A025's full-target pixel, A033's layer fill) stay
GAP: no Swift framebuffer readback exists, and this task must not fake one with
delegate-color sampling relabeled as raster equality.

# Exact write set

- `src/checks/automation/presentation/painting_raster.swift` — extensions to the existing scrolled-phantom and voice-cursor journeys only.
- `src/checks/automation/raster/proof.interaction.txt` — A023, A026, A043, A046, A057 only.

# Prerequisites

None. Read sprint-3 §18 for shared constraints.

# Interface contract

Consume the existing fixture/page APIs the file already drives (`AutomationPage`
`publishedNodes`, hover-ring and gesture state, cursor-value publication) unchanged.
Each clause gets one uniquely-anchored message on a fresh observation in the existing
journeys: the repeat-leave and post-commit hover clears observe the page's hover state
after the named input; A057 compares the published voice cursor value against the
independently staged `cursorValue` literal; A026 validates the staged drag target
against the production activation distance. No new page API, no QML edits.

# Implementation steps

1. Extend the scrolled-phantom journey: after the existing leave, leave again and
   assert hover stays clear (A023); after the commit-release leg, assert the hover-clear
   state without an intervening leave (A043); after the commit, leave and assert the
   clear (A046).
2. Validate the drag staging: the fixture's vertical target distance exceeds the
   production node-drag activation distance (A026, staging classification).
3. Extend the voice-cursor leg: compare the published cursor value with the staged
   literal (A057).
4. Close the five rows with executed anchors; leave A025/A033 GAP with their existing
   no-readback reasons unchanged.

# Acceptance predicate

The mounted interaction model proves repeated-leave stability, post-commit hover
clearing in both orders, fixture validity, and the exact voice cursor value — with the
pixel-probe residue explicitly left open.

Named checks under §18 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No framebuffer, layer-color or delegate-sampling predicate may stand in for A025/A033.
Do not touch `tst_EditorDrawer.qml` (its drawer-lane rows are separate),
`painting.swift`, or the raster painting ledger. `painting_raster.swift` stays one
cohesive scenario file; no new check file or manifest entry.
