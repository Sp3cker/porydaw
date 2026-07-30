# Task 11 — Final integration verification and evidence

**Blocked by:** Reviewed and integrated Task 10.

**Runtime worktree:** `11-final-verification`

**Branch:** `task/editor-drawer/11-final-verification`

**Target boundary:** No commit by default.

## Start rule

Fast-forward this clean verification worktree to the accepted Task 10
integration SHA and record it as `START_SHA`. This task audits only the
integrated branch.
Before running checks, read the root plan, full specification, repository
instructions, and this plan in full.

## Objective

Prove the complete implementation meets the specification, preserves a clean
history with all ten slices traceable in order, and improves the oracle where
the specification requires.

## Work

### Automated matrix

Build the final application and run the required native suite on fresh fixture
copies:

```text
<porydaw> --editcheck <scratch-project>
<porydaw> --rollcheck <scratch-project> mus_lovely <roll-screenshot>
<porydaw> --eventviewcheck <scratch-project> mus_lovely <event-screenshot>
<porydaw> --keymapcheck
<porydaw> --sessioncheck <scratch-project> mus_lovely
<porydaw> --tabcheck <scratch-project> mus_lovely <second-valid-song>
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Also run the configured test runner, `git diff --check`, all focused acceptance
harnesses, and the strict twelve-result PSG check.

### Manual matrix

Record **UX-01...UX-11** on fresh reflinks made from Task 00's pinned fixture
manifest. Use `mus_lovely` as the primary song and `mus_poke_center` for the
second-tab and mixer-independence cases. Follow Task 00's exact prepared
scratch recipe and song/track/tick/program/key matrix for tempo, voice,
controller, DirectSound, Square, Noise, Wave, and key-split contexts. Include:

- drawer open/switch/resize/close/restore;
- focus, active-tab routing, event-list blocking, and announcements;
- every automation lane action and gesture;
- automation Undo, cancel, reorder, and delete;
- shared note selection;
- continuous velocity selection, drag, freehand, band, cancel, exact entry,
  and Undo;
- Square, Noise, Wave, exact restoration, and mixer independence;
- playback smoothness and counter evidence;
- sidecar restoration with no MIDI diff; and
- second-base-font visual/hit alignment.

### Final audits

- Map every automated and manual ID to evidence.
- Verify all eight source defects are fixed or contained.
- Verify every explicit exclusion is absent.
- Compare final failures with Task 00's exact baseline.
- Inspect each commit for buildability, focus, and unrelated churn.
- Confirm no oracle commit or wholesale oracle file was ported.
- Confirm the integration worktree is clean.
- Confirm each integration commit's tree matches its recorded approved tree
  and every split slice retains its A transport, B transport, and combined
  Review evidence. Task-local transport branches need not be integration
  ancestors.

For **PERF-01**, record fixture, warmup, 120 updates, branch SHA, final tick,
content-build counts, invalidation counts, and presentation counts.

## Defect routing

Do not make a miscellaneous final cleanup change.

If verification fails:

1. Map the failure to its owning task in the root acceptance table.
2. Reopen that task on the current integration tip.
3. Add a focused regression.
4. Run the task's full Review loop.
5. Commit a focused reviewed correction or resynthesize the owning boundary.
6. Replay all dependent checks and this final matrix.

If a cross-cutting correction cannot fit an existing boundary, write a short
focused plan note and obtain Review approval before editing.

## Handoff and review

Write a final evidence report outside the Git diff containing:

- final integration SHA and ordered commits;
- baseline and final command table with exits;
- all acceptance IDs and evidence;
- twelve PSG result names;
- manual UX results and screenshots;
- PERF counters;
- source-defect and exclusion audit;
- remaining baseline-attributed failures; and
- cleanup eligibility for each disposable worktree.

The final Review agent rereads the full specification and reviews the complete
`BASE_SHA..HEAD` diff plus history. `APPROVED` requires no open normative,
correctness, UX, lifecycle, Undo, layout, performance, exclusion, or history
finding.

## Completion

After final approval, the coordinator follows the root cleanup sequence:
archive coordination evidence; prove every candidate is stored in a transport
or integration commit; clean generated state; validate each exact new path;
and use scoped `git worktree remove --force <exact-created-path>` only for
Git's initialized-submodule restriction. Do not deinitialize the shared
submodule registration. Delete branches only when non-forced deletion
succeeds. Preserve non-ancestor transport branches, the integration and plan
branches, and all coordination evidence. Do not push without a separate user
request.
