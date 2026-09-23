# Automation/domain C++ check retirement — task plan

Spec: `docs/plans/automation-domain-proof-retirement/spec.md` (read first;
it owns disposition semantics, the certificate format, the suite map,
per-site audited verdicts with fixed fixture values, and reachability
evidence). Route: SDD-track (`sdd-execution-loop`, seat `sdd-implementer`)
for every task except Task 2 (Direct — single-file proof edit with the
disposition pre-decided in spec §5.2). This is judgment work on
observable-contract equivalence, not mechanical migration.

## Baseline policy (start after editcheck completion)

Complete and checkpoint the editcheck proof-retirement plan before
implementing this folder. Its tasks modify `src/checks/CMakeLists.txt` and
`src/checks/editcheck/TimeChecks.swift`, which Task 5 also needs. At dispatch,
record the then-current HEAD and source SHAs; the original C++ proof's
`Reference revision` and `Original SHA-256` remain their independently
verified historical pins, not the dispatch HEAD. If unrelated edits touch
one of this plan's files, re-read before editing and do not revert them.

## File-ownership policy (AGENTS file-size discipline)

- `gestures.swift` (774 lines) and `tst_automationdomain.swift` (760) are
  NOT edited by any task — eight other proofs cite their line anchors and
  the two proofs pin their SHAs (spec §5.1, §10). Tasks 1-2 are proof-only.
- `xcmd.swift` (90 lines) grows to roughly 400 lines (Tasks 3-4:
  canonical/sweep/opaque slots, entry `drawerAutomationXcmdLaneEdits` in
  the projectSession suite). Edits are **append-only**: new functions and
  new sections inside the entry function go after existing lines so every
  existing line anchor cited by `proof.xcmd.txt` and the
  `automationgesturecheck` proofs stays valid.
- The range/time slots (cuts, removeOnly, rangeMoves, expansion) land in a
  new `src/checks/automation/domain/xcmdRanges.swift` (~350 lines) wired
  into the timeEdits suite — a real ownership seam (suite boundary +
  document time-family ops, where `coreTimeXcmdTimeTraffic` already
  lives), not a line-count split. Registered by one line in
  `src/checks/CMakeLists.txt` beside `automation/domain/xcmd.swift:154`.
- `AutomationPageChecks.swift` (397 lines) takes exactly one wiring line
  (Task 3, after `drawerAutomationXcmdParity` at line 366).
- One writer at a time per file; `src/checks/CMakeLists.txt` and
  `TimeChecks.swift` have no other writer in this plan.

## Dispatch table

| # | Task | Brief | Write set (files) | Depends | Narrow check (controller) |
|---|------|-------|-------------------|---------|---------------------------|
| 1 | gestures: A048-A051 STALE→MATCHED, A052→RETIRED-REPRESENTATION, certificate, delete | task-1-brief.md | `proof.gestures.txt`, delete `gestures.cpp` | — | full swiftcore |
| 2 | tst_automationdomain: A001→RETIRED-REPRESENTATION + certificate (Direct; file already deleted) | inline below | `proof.tst_automationdomain.txt` | — | full swiftcore |
| 3 | xcmd lane CRUD: fixture + helpers + `xcmdCanonicalEdits` (A001-A009) + `xcmdSweepPreservesNotes` (A040-A042) | task-3-brief.md | `xcmd.swift` (append), `AutomationPageChecks.swift` (1 line) | — | `--qt projectSession` |
| 4 | xcmd opaque epochs: `xcmdOccurrencesAndOpaqueProtection` (A010-A028) | task-4-brief.md | `xcmd.swift` (append, inside Task 3's entry function) | 3 + C1 | `--qt projectSession` |
| 5 | xcmd range family: new `xcmdRanges.swift` — cuts (A029-A039), removeOnly (A043-A048), rangeMoves (A049-A056), expansion (A057-A062) | task-5-brief.md | new `xcmdRanges.swift`, `TimeChecks.swift` (1 line), `src/checks/CMakeLists.txt` (1 line) | editcheck plan complete | `--qt timeEdits` |
| 6 | xcmd certificate: reclassify all 62 GAP→MATCHED, preamble, delete | task-6-brief.md | `proof.xcmd.txt`, delete `xcmd.cpp` | 3, 4, 5 + C2 | full swiftcore |
| 7 | Shared header deletion + engine reachability gate (spec §7-§8) | task-7-brief.md | delete `tst_automationdomain.h`, new `engine-reachability.md` (plan folder) | 1 + 6 | full `deno task verify --verbose` |

## Parallel waves and file-reuse checkpoints

First parallel wave (disjoint write sets): **1, 2, 3, 5** — proofs/
`gestures.cpp` (1) / `proof.tst_automationdomain.txt` (2) / `xcmd.swift` +
`AutomationPageChecks.swift` (3) / `xcmdRanges.swift` + `TimeChecks.swift`
+ CMake (5). Task 4 follows Task 3 (same file, append-only).

Checkpoint milestones (authorize later reuse of an accepted writer's
files; the execution loop owns staging/diff packaging):

- **C1 — first certificates** (after 1, 2, 3, 5 accepted): gestures and
  tst_automationdomain retired; xcmd lane-CRUD and range families landed.
  Commits Task 3's `xcmd.swift` state → authorizes Task 4's append into
  it; freezes Task 5's counterpart files at the SHAs Task 6 will cite.
- **C2 — xcmd predicates complete** (after 4 accepted): commits the final
  `xcmd.swift` → authorizes Task 6's certificate (final SHA refresh) and
  frees the proof for terminal tally.
- **C3 — final handoff** (after 6, 7 accepted): full
  `deno task verify --verbose` + `deno task proof list --area
  automation/domain` — all 24 registered native, Swift and QML harnesses
  pass; three terminal certificates, zero PARTIAL/GAP/NATIVE-SETUP. No
  empty checkpoints; serial same-file tasks never force extra commits
  between C1-C3.

## Global constraints (once — briefs carry deltas only)

- Read `spec.md` §2-§5 before starting any task. Disposition semantics
  (including the hard rules: no argument echo, non-throwing construction
  never MATCHes setup sites, no synthetic parameter fabrication, revision
  is not history depth), the SHA-pinning protocol (§2.2 — keep the
  existing `Reference revision f3069ef6…`; verify SHAs against disk/git
  before use; no placeholders), the per-slot fixture tables (§5.3), and
  the certificate format (§3) live there and are not repeated in briefs.
- Implementers do NOT run `deno task verify`, `build:*`, `format`, or
  `lsp:swift`; the controller runs the recorded commands after the task
  settles. Read-only `deno task proof show|list` and `shasum` are
  implementer-available; `deno task proof:edit … --apply` is the
  sanctioned disposition-change mechanism.
- Every verify command in this plan is bounded well under 180 s (spec
  §2.4 records full-lane build ≈32 s + run ≈8.5 s). If a recorded command
  goes stale or exceeds the budget, report the mismatch and the revised
  verification instead of silently narrowing it.
- Never relabel a site without an executing Swift predicate under the
  original observable or the named no-ingress proof (spec §2.1/§7). The
  honest weaker label wins; a site stays GAP and the file stays unretired
  rather than being forced green. Report — never code around — the two
  §5.3 behavioral risks if they fire.
- `xcmd.swift` edits are append-only (line anchors in `proof.xcmd.txt`,
  `automationgesturecheck/proof.contract.txt` S015-S019,
  `proof.crosslane.txt` S006-S008). `gestures.swift` and
  `tst_automationdomain.swift` are never edited. No test-only accessors,
  production hooks, or new C++ support code.
- New predicates use the cppID `"automation-domain/AutomationDomainTest::
  <slotName>"` and the `CheckReport` idioms of the paired files (spec §4).
- After any Swift edit the task is done only when `deno task proof show
  automation/domain/xcmd.cpp` still parses and the affected proof tallies
  are exactly what the brief's acceptance states.
- The controller pushes accepted checkpoints per AGENTS Git
  synchronization.

## Direct task 2 (inline)

# Target
`src/checks/automation/domain/proof.tst_automationdomain.txt` reclassified
to a deletion certificate; disposition A001 made terminal. No file
deletions (`tst_automationdomain.cpp` was deleted at `31ea635f`;
`tst_automationdomain.h` is Task 7's, not this task's).

# Change
1. Reclassify A001 NATIVE-SETUP→RETIRED-REPRESENTATION via `deno task
   proof:edit`, with a mapping line carrying the spec §5.2 no-ingress
   proof (non-throwing `SongDocument(file:)` construction; C++ file
   deleted and uncompiled; postconditions live in A002/A003).
2. Rewrite the preamble to the certificate format (spec §3): retain
   `Reference revision f3069ef6…` and `Original SHA-256 50413de5…`
   (verify `git show f3069ef6:src/checks/automation/domain/
   tst_automationdomain.cpp | shasum -a 256` first); `Swift counterpart:
   tst_automationdomain.swift` with its on-disk SHA (verify — do not
   edit that file); `Covered native implementation: src/core/
   songdocument*.cpp :: SongDocument lane/tempo editing, adoptSmf` +
   `src/ui/editordrawer/nodelane/* :: CCLaneAdapter/NodeLane`;
   `Registered run path: runAutomationPageChecks → projectSession
   (suite 10)`; Verification line records the controller's post-edit full
   swiftcore PASS.
3. Preserve the site inventory and every existing MATCHED mapping
   unchanged; keep the fixture/loop inventory section.

# Acceptance
`deno task proof show automation/domain/tst_automationdomain.cpp` parses
with 107 sites terminal (106 MATCHED + 1 RETIRED-REPRESENTATION);
`deno task proof list --area automation/domain` shows PARTIAL 0, GAP 0,
NATIVE-SETUP 0 for this proof. Controller runs
`deno task verify --filter swiftcore --verbose` and records the Result
line.
