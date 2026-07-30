# 12 — Layout resolver and geometry gate

Packets 12A and 12B start independently from `INFRA_SHA` and run in parallel with
10A and 13. They are a resolver/checker mini-wave: 12A owns semantic resolution and
clean-process 12/16 checks; 12B owns only the audit tool and its self-test. Neither
migrates product call sites. Task agents write implementation, focused coverage, and
one commit but do **not** run builds, tests, formatters, or linters. The coordinator
runs each focused proof once after the mini-wave commits; reviewers inspect committed
ranges before ordinary integration merges.

## 12A — Semantic layout resolver

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/layout-resolver`  
**Worktree:** `12a-layout-resolver`  
**Base:** `INFRA_SHA`.

`git-operations-runner` creates/verifies the `12a-layout-resolver` worktree and `task/psg-velocity/layout-resolver` branch from the exact `INFRA_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

### Exclusive paths

1. `src/ui/layout.h`
2. `src/ui/layout.cpp`
3. `src/ui/theme/themecheck.h`
4. `src/ui/theme/themecheck.cpp`
5. `src/ui/theme/themechecks_main.cpp`

Do not edit typography, UI call sites, `SongView`, drawer, automation, velocity UI,
model/axis, registration, or the geometry checker.

### Contract

Publish semantic `layout` accessors plus a resolved editor-geometry value. Future
consumers receive those resolved values, never feature-local `k...Px` constants or
numeric `fontPx` calls. At base font 12, the resolver explicitly covers:

- track header 210 and piano keyboard 52;
- drawer handle 4 and minimum roll 120;
- automation default/minimum/maximum row 48/28/128, row wheel 4, and add-lane strip
  20;
- automation hit/neutral/delete 7/8/9 and detail threshold 24;
- continuous-axis density thresholds 72/100/144/288; and
- velocity start/stem-vertical/stem-horizontal/relative/freehand 6/4/2/1/6.

Resolve every semantic input before derived calculations. Plot origin is the resolved
track-header plus keyboard widths; the first tab gets integer half of the resolved
header width and the second gets the remainder; minimum open drawer height is the
resolved default row plus add-lane strip. At base fonts 12 and 16, every positive
font-relative factor is `qMax(1, qRound(baseFontPx * factor))`; `Space::Zero` stays
zero and `layout::singlePixel()` stays one. Each value is either deliberately scaled
or deliberately invariant at both scales.

Preserve the generic layout API and stylesheet behavior. This packet defines values
and resolver coverage only: it does not migrate a caller, change UX, add a literal
scanner/allowlist, or add a broad source gate.

### Focused evidence and handoff

Extend the existing `porydaw_themechecks` harness; 12A has no packet-05
conditional registration because all of its owned paths already exist on
`INFRA_SHA`. In separate clean processes, the coordinator runs:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks --editor-layout-check --base-font-px 16
```

Those cases assert every declared value, scaling/invariance, rounding,
plot-origin sum, tab partition, and minimum-open-height derivation. After the
task commit, the coordinator runs each command once. A `reviewer` reviews the
exact committed range against `INFRA_SHA` and, after approval, the coordinator
merges it normally into `feature/psg-velocity-history-upstream` for later
foundation integration.

## 12B — Geometry audit gate

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/layout-gate`  
**Worktree:** `12b-layout-gate`  
**Base:** `INFRA_SHA`.

`git-operations-runner` creates/verifies the `12b-layout-gate` worktree and `task/psg-velocity/layout-gate` branch from the exact `INFRA_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

### Exclusive paths

1. `tools/check_editor_layout_geometry.py` (new checker)
2. `tools/check_editor_layout_geometry_test.py` (new narrow self-test)
3. `tools/check_editor_layout_geometry_fixtures.py` (new self-test fixtures)

This task owns the repository-wide source audit implementation, but not its normal
repository-wide execution until the final packet. It must not edit production source,
layout resolver code, registration, or any product call site.

### Contract and edge cases

Implement the LAY-01 checker against the final target set. It must accept
focused file arguments and `--self-test` while product files are absent, so its
new direct command is runnable on its own branch without a packet-05 CMake
registration. Its default invocation audits the full final target set and
detects violations the semantic resolver is intended to replace. Self-test
fixtures cover an accepted semantic use and rejected local/raw geometry forms,
including exact diagnostics and focused-file selection.

12B is a checker, not a migration. It must not change an allowlist, scatter exceptions
through product owners, weaken the default target set, or run a repository-wide audit
as a per-module substitute for a focused geometry/hit-test command. The default,
repository-wide invocation is **final-only**. Product and host waves run only their
module command's focused geometry/hit-test behavior; the final packet runs the
checker once on the integrated candidate.

### Focused evidence and handoff

After the task commit, the coordinator runs
`python3 tools/check_editor_layout_geometry.py --self-test` once. It does not run the
default repository scan at this stage. A `reviewer` checks the exact range against
`INFRA_SHA`, including final-target defaulting and focused/self-test behavior. After
approval, merge normally into `feature/psg-velocity-history-upstream`; no
cherry-pick, staged-tree transport, or call-site migration.

## Foundation handoff

Approved 12A and 12B heads remain independent ordinary merges. They do not establish
a SHA of their own: their accepted work joins 13, 14A, and 14B only after the
`CONTRACT_SHA` work is approved. The coordinator then records the completed
foundation integration as `FOUNDATION_SHA`. The final packet—not 12A, 12B, a
product packet, or a host packet—runs the default repository-wide LAY-01 audit.
