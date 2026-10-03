# Proof-ledger process review — 2026-09-28

Discussion record. Status: **proposal, not adopted.** Nothing below changes
`.omp/rules/proof-ledger-workflow.md` until the user rules on it.

## Question

Is the per-assertion proof ledger the best way to preserve features across
the Swift rewrite? It feels slow.

## Findings (measured on `feature/swift-qml-grid` at `63f492d8`)

| | |
|---|---|
| Ledgers | 37 files, 33,015 lines |
| Assertion rows | 5,290 |
| Distinct C++ test functions behind them | ~250–400 |
| Commits touching a ledger | 361 of 1,648 on the branch |
| Ledger corpus age | 2026-09-21 → 2026-09-28 |

Disposition split: MATCHED 2,312 (44%), GAP 1,498 (28%),
RETIRED-REPRESENTATION 1,044 (20%), PARTIAL 222 (4%), NATIVE/NATIVE-SETUP 214 (4%).

GAP concentrates in surfaces that are not yet ported, not in defects:
`samplecheck` (365 rows across decoder/editor/integration/project/dsp),
`project/workspace` (58), `onboardcheck/import` (33), `themelayout` (33),
`mainwindowrouting` (28), `nativegraphics/nativewindowing` (27), `visual/dialogs` (24).

## Assessment

The ledger is the right tool for *not forgetting* a behavior and the wrong
unit of work. It preserves assertions, not features:

1. Granularity is the C++ harness's `QCOMPARE` count, ~20× the behavior count.
   A fifth of all rows are paperwork explaining why a widget-representation
   assertion no longer applies.
2. MATCHED is a judgment, not an execution. `deno task proof` checks structure
   and hashes; the A→S mapping is an agent's opinion. The voicegroupbank
   "ledger-only exception" (`e24ceefc`) closed rows by argument. Once that
   door exists the ledger stops being proof.
3. It protects only what the fork happened to assert. Cursor work
   (`1d164dbc`, `418bef68`) came from using the app, not from a GAP row.
4. The per-commit ritual (ledger agent pass, controller verifies A→S links,
   hashes, tallies, `proof check`) is sized for assertion granularity.

Calendar-wise the corpus was built in a week; the cost is per-commit overhead.

## What I would do

1. **Keep closed ledgers as-is.** MATCHED/RETIRED rows are a record, not a
   workload. No rewrite, no re-pin; the surface-first rule already forbids
   standalone reconciliation.
2. **Behavior-level rows for unported surfaces.** One row per C++ test
   function: disposition, the Swift check that executes it, one line stating
   the behavior. Assertion detail only inside a PARTIAL row, listing what is
   still missing. Applies to `samplecheck`, `project`, `onboardcheck`,
   `themelayout`, `visual`, `mainwindowrouting`, `nativegraphics`.
3. **No ledger-only closures.** A row closes only when a running check closes
   it. Representation-only assertions are RETIRED with a reason; behavioral
   ones stay open until a Swift check executes them.
4. **Differential checks for deterministic domains.** SMF round-trip,
   `mid2agb` output, project I/O, sample DSP/decoder: fixture → output compared
   against golden output captured from the fork. One check per fixture set;
   that surface's ledger collapses to "golden parity holds". First candidates:
   `samplecheck/proof.dsp.txt`, `proof.decoder.txt` (154 GAPs).
5. **Tooling change is format-additive.** `tools/proof_{reader,editor,compact,anchor}.ts`
   accept both row formats so roll/drawer ledgers edited on the grid branch
   keep validating. Land as one small commit and merge into
   `feature/swift-qml-grid` before the renderer's next ledger commit.
6. **Shrink the ritual to match.** Controller verifies "does this Swift check
   exercise this behavior", not per-line hashes.

## Worktree plan

Split by surface, not by file type. The grid branch's in-flight renderer work
owns `src/render/`, `src/swift/app/{roll,drawer,timeline}`,
`src/ui/songview/quick/`, and the `editorqml`/`rollcheck`/`rollqml`/
`velocity`/`drawerpresentation` checks and ledgers. The process branch never
touches those.

- `deno task worktree:create -- proof-behaviors --base feature/swift-qml-grid`
  (base on `63f492d8`, not `fork-main`).
- Tooling commit first (item 5), merged immediately.
- Merge `feature/swift-qml-grid` into the process branch daily; the only
  expected conflicts are appended lines in `src/checks/CMakeLists.txt` and
  `CMakeLists.txt`.
- Never merge the other direction until a surface is complete.
- Before assigning `samplecheck`, inspect `feature/sample-editor-library-view`:
  it is 1,004 commits behind the grid branch's merge-base and nominally covers
  that surface.
