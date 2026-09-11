# Shared menu actions — progress and problems (2026-09-11)

Executed tasks 1–11 on `feature/time-editing`. Tasks 1–10 review-gated clean
(SPEC YES / PASS); task 11 is Direct, covering checks green. Full suite runs
once at final integration (task 32 / plan constraint 6).

## Where things stand

- Committed per-task (old policy): tasks 1–9 (`08fee420` … `39720d28`).
- Uncommitted, accepted: task 10 (r0 package `task-10-review-r0.diff`,
  review clean) + task 11 (23 fixture files, 29 EditActions/rebind roots).
- Next: task 12 (Direct), then 13. Milestones per plan Checkpoint cadence:
  T17, T31, T33+final. No per-task commits going forward.
- CHECKPOINT for BASE purposes: `39720d28`.

## Problems encountered

1. **Deletion-task build breakage (3×).** Task 2 dropped a closing brace,
   task 3 deleted a header declaration while keeping its definition, task 19
   dropped a `struct MenuMetrics;` forward declaration. Cause: deletion-heavy
   edits + SHARED_TREE deferred builds, so syntax errors surface only at
   controller verify. Fix cost was low every time (`hub send` to the original
   implementer, one-line restoration). Expected cost of batching, not a plan
   defect — but reviewers should keep checking declaration inventories, and
   the r0 packages caught nothing here; only the controller build did.
2. **`outputSchema` array footgun.** First dispatch failed all three agents:
   `changedFiles` array schema missing `items`. Always declare
   `{"type":"array","items":{"type":"string"}}`.
3. **Empty reviewer yields.** Two reviewers first yielded bare verdict words
   (`approved`, `complete`) without the required SPEC/QUALITY report; each
   needed one `hub send` follow-up to the same reviewer. Instruct reviewers
   to yield the FULL report in the task result (now in the dispatch text).
4. **Format hook vs SHARED_TREE.** The pre-commit `format --check` hook
   blocked nearly every checkpoint commit, forcing controller-side
   `deno task format` + re-verify per batch (~1–2 min each). Unavoidable
   under the no-implementer-format rule; budget it per batch. Note
   clang-format 21 vs CI-pinned 22 drift warnings — cosmetic only so far.
   Never pass `CMakeLists.txt` to `deno task format` (unsupported file type
   aborts the run); format C++ files only.
5. **Focus flakes, not regressions.** `selectionkey-gesture` failed twice and
   `automation-editing` once with focus-ownership errors while the desktop
   was in use; all passed on identical-tree rerun. Do not chase these, do
   not stash-baseline them — one identical rerun is the exoneration. A
   `git stash` baseline is for failures that reproduce in isolation.
6. **Task 8 review findings (adjudicated).**
   - Always-terminal Insert/DeleteTime/ClearTimeSelection: brief-mandated
     interim contract ("terminal consumption until Task 15"), not a gap.
     If task 15 leaves it in place, it becomes a real bug (swallowed keys).
   - `executeEditCommand` caller-side availability gating: real consumption
     contract, carried into task 9 and implemented there (every callback
     checks `editCommandAvailable()` first). Re-verify at task 15 cutover.
7. **Task 10 review ⚠️ (ruled, not a gap).** No SongView-side
   `invalidateContextMenus` emission on cursor movement in the task-10 diff.
   Ownership belongs to task 18 (ruler-menu dismissal on cursor/document
   transitions) subscribing to the existing `editCursorMoved` seam. If task
   18 does not publish retirement there, positional menus go stale — check
   at task 18 review.
8. **Mid-run rule changes.** `.omp/rules/*` (local-inspection section,
   checkpoint policy, r0 packages, no per-task commits) and plan constraints
   5–6 plus Checkpoint cadence changed mid-execution. Adapted without
   touching completed work: tasks 1–9 commits stand; packages from task 10
   use `-r0` naming and worktree-vs-CHECKPOINT diffs. Dispatches now carry
   the inspection section verbatim and put evidence in
   `selfReviewFindings` (Direct: in summary).
9. **Subagent has no LSP device.** Task 11 reported `xd://lsp` unavailable
   and fell back to scoped search + six-mission manual review, which is the
   prescribed UNAVAILABLE path — but it weakens reference-closure claims on
   a 23-file migration. The covering build (all fixtures compile, checks
   green) is the backstop. Watch for missed call sites in later
   SongView/MainWindow work; prefer controller-side `lsp references`.
10. **Known reuse hazard ahead.** Plan flags task 26 → 30 sharing
    `rangeedit.cpp`. Per checkpoint policy, task 26 must be reviewed and
    checkpointed before task 30 touches those files. Same for any task that
    re-edits `songview.h/.cpp` or `editactions.cpp` before the T17
    milestone (tasks 15–17 are the likely candidates — check write sets at
    dispatch).

## Deferred / parked

- No parked Critical/Important findings. No Deferred-phase minors yet.
- Visual walkthrough evidence (shown app, native priority, ruler semantics)
  is intentionally deferred to tasks 32–33 + final integration.
- Task 4/5 acceptance app-launch inspections were deferred the same way;
  menu-route behavior is covered by `mainwindow-routing` + `settings-dialog`
  harnesses in the meantime.
