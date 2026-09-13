# Task R9 — Fixture EditActions bind helper and per-site mechanical migration

## 1. Context

Task 11 patched identical construction pairs across 23 fixture files, each pasting the
same two lines (`new songview::EditActions(&view); editActions->rebind(&view);`
with view-dependent receiver expressions). The sign-off on Q-F1 records: this
is copy-paste of production wiring order that lives in `SongTab`/test rigs, the
next bind-order or lifetime change would touch 23 files, and site ownership is
raw `new` with parent-ownership-by-convention. The remedy is one helper where
the concept already lives — `checks::support` beside `EditorRig`/`SongViewRig` —
plus a Direct mechanical migration of every site. The per-site list in §2 is
grep-exact (29 construction sites across 23 files as of ac0979b); the
signoff's "25 sites / 23 files" shorthand was acknowledged as immaterial
there. File-size rule: `editorrig`/`songfixture`/`checks::support` stay
cohesive single-concept modules; `quickmenuhost.cpp` is not touched by this
task.

Cross-cutting gate (recorded once): E-M3 is decided — option (b), the narrowed
`bind(this)` / `unbind()`-class contract in Task R7, not direct SongView
ownership (option (a)) — so the test-helper seam continues to be the single
fixture-side construction seam for R7's contract. Only the call form changes
here. No helper is built on top of, or conditional on, option (a).

## 2. Exact write set

Add the helper to `src/checks/support/`, then replace the sites enumerated
below. No other files. Fixture `src/checks/` files only — not the production
`src/ui` area.

Helper location (new, 2 files):
- `src/checks/support/support.h` (or the existing shared-support header if
  `songfixture`/`editorrig` already include one — match the rig factories'
  current include shape; if two headers exist, the new function goes next to
  `showQuickViewport`'s home)
- `src/checks/support/support.cpp`

Implementation shape (from Q-F1 remedy, no fragment directory):
`SongView &bindEditActionsForTest(SongView &view)` or equivalent value-bearing
wrapper — parents the `EditActions` to `&view`, calls `rebind`, and exists so
future bind-order changes touch exactly this function. Naming may follow
whatever `checks::support` already exposes; the observable slots are: built
once beside the rig factories, and called from every site below.

Per-site list (27 sites below + 2 rig-factory sites = 29 total construction
sites across 23 files; each site = the `new songview::EditActions(...)` +
`rebind(...)` pair, replaced by one `checks::support` call):
1. `src/checks/rollcheck.cpp:54-55`
2. `src/checks/automation/automationfixture.cpp:202-203`
3. `src/checks/automation/raster/rasterfixture.cpp:410-411`
4. `src/checks/clipboard/clipcheck_fixture.cpp:99-100`
5. `src/checks/drawerpresentation/fixtures.cpp:203-204`
6. `src/checks/drawerpresentation/fixtures.cpp:390-391`
7. `src/checks/drawerpresentation/fixtures.cpp:507-508`
8. `src/checks/drawerpresentation/velocity.cpp:105-106`
9. `src/checks/eventviews/eventview_fixture.cpp:203-204`
10. `src/checks/host/tst_hostseams.cpp:143-144`
11. `src/checks/host/tst_hostseams.cpp:193-194`
12. `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:162-163`
13. `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:191-192`
14. `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:244-245`
15. `src/checks/pitchbend/fixture.cpp:95-96`
16. `src/checks/rollcheck/identity.cpp:65-66`
17. `src/checks/rollcheck/remap.cpp:39-40`
18. `src/checks/rollcheck/static/fixtures.cpp:117-118`
19. `src/checks/rollcheck/static/fixtures.cpp:187-188`
20. `src/checks/rollcheck/static/geometry.cpp:34-35`
21. `src/checks/scrollbar/tst_scrollbar.cpp:195-196`
22. `src/checks/timelinepan/timelinepanfixture.cpp:93-94`
23. `src/checks/trackheaders/trackheaderfixture.cpp:104-105`
24. `src/checks/trackheaders/trackheaderinput.cpp:352-353`
25. `src/checks/trackheaders/tst_trackactivitymeter.cpp:95-96`
26. `src/checks/trackheaders/tst_trackheadermodel.cpp:284-285`
27. `src/checks/velocity/tst_velocityediting.cpp:111-112`

Rig-factory sites (call the helper too, keeping the factory as owner):
- `src/checks/support/editorrig.cpp:43-44`
- `src/checks/support/songfixture.cpp:114-115`

Note: 29 construction sites total (27 above + 2 rig factories) across 23
files — `grep`-exact as of ac0979b. The signoff's "25 sites / 23 files"
shorthand was acknowledged as immaterial there; this list is the
authoritative per-site enumeration.

## 3. Prerequisites

- [Task 11](task-11-brief.md) — this is remediation of Task 11's hunks, not a
  new feature.
- [Task R7](task-R7-brief.md) — the narrowed rebind contract it names is the
  form this helper forwards to; the helper does not depend on R7 landing
  first, only on the option (b) direction already fixed here.

## 4. Interface contract

The helper is test-support only: no production `src/ui` behavior changes, no
new ownership concept, no spec text change. It replaces every enumerated
instance of the
identical construction/rebind pair with one call per site. Parent and rebind
target stay the exact object each site names today. Route: **Direct** (same-
shape mechanical migration with an exact file list), exact per-file list below.
Gates honored: cross-cutting gate (1) — the window-delivered vs
EditorRouted/manually-delivered split is untouched (the helper changes how
construction is spelled, not what is constructed); cross-cutting gate (2) —
E-M3 option (b) decided as above, stated here so a later contributor cannot
re-open it silently.

## 5. Implementation steps

1. Add the single `checks::support` helper (declare + define once).
2. Call it from both rig factories first (`editorrig`, `songfixture`), then
   from every remaining bespoke site in the per-file list, deleting the two
   pasted lines at each site and any local `editActions` variable that no
   longer needs a name (the helper deduplicates the name away).
3. Leave asserted behavior at each site untouched; this task adds/removes no
   test scenario. Formatting is validation-owned.

## 6. Acceptance predicate

Zero remaining `new songview::EditActions` construction sites outside
`checks::support` (`grep` is empty in `src/checks` except the helper's own
definition). The two rig factories and every listed site compile with the
helper in place; the controller batches a focused verify once for the settled
batch (per-site compile-by-file is the in-flight check). For this docs-only
drafting step, acceptance is "brief exists and names every construction site
except the two support targets".

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No LSP is needed —
this is a text-shape migration across `src/checks` only; do not touch
`src/ui`. If a future task confirms production wiring does not use
`EditActions`, no extra helper work is owed here. Exception note: this brief
exceeds the 3-file cap by the explicit mechanical-migration carve-out in
Global Constraint 4 (tasks 3/6/11 pattern; R9 is the same shape).
