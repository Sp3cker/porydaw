# Task 12 — Close prompts + orphan cleanup (session registry, quit sequencing)

## Context

Twelfth task of the Split Studio plan; the second half of the former task
10 (R17 split): the close-path integration and the destructive-but-guarded
orphan cleanup. Producers consumed: task 10's `KitStudioWorkflow` +
`KitStudioCloseGuard` and the `ApplicationSession` registry (R6 —
`orphanSplitStudioSamples()` / `deleteOrphanSamples(_:)`), task 3's
`SampleRegistrar.deleteRegistration` + `KitUsageScanner` (re-checked at
delete time), task 11's accepted workflow edits (checkpoint with other
ready work before this task starts — it re-edits the same files).
Decisions: closing with unapplied changes prompts on every close path;
clean closes silently; project close/app quit close the window; quit waits
for a pending save (R23); orphan cleanup is offered on song tab close and
project close/app quit for session-created samples no voicegroup
references at check time, as a checklist (all checked) with Delete / Keep;
window close never offers it.

## Exact write set

- Edit `src/swift/app/ApplicationSession+Close.swift` (tab/project close
  consultation + orphan offering point)
- Edit `src/swift/app/ApplicationSession+ProjectOpening.swift` (project
  switch/quit closes the window via the same guard)
- Edit `src/swift/app/ApplicationSession.swift` (registry delete
  implementation: `deleteOrphanSamples` re-checks usage per name)
- Edit `src/swift/app/SongTabsController+Close.swift` (tab-close prompt
  sequencing before `confirmSave`)
- Edit `src/swift/app/kitstudio/KitStudioWorkflow.swift` (close-answer
  continuations, orphan candidate listing)
- Edit `src/ui/shell/kitstudio/SplitStudioWindow.qml` (orphan checklist
  dialog surface)
- Create `src/ui/shell/kitstudio/OrphanCleanupDialog.qml`

Controller-owned: CMake source line for the new QML file, baselines.

## Prerequisites

Tasks 10 and 11 (interfaces + accepted files; the between-checkpoint from
plan.md applies).

## Interface contract

`spec.md → PorydawApp (task 12)` (§23, §25, R6, R23):

- **Close sequencing** (R23): the Split Studio prompt runs BEFORE the
  song's own save prompt on tab close and close-all/project close. The
  seams: `saveTabBeforeClose` (`ApplicationSession+Close.swift:44`),
  `closeAllResolved` (`:118`), `hostClosingImpl` (`:151`), and
  `SongTabsController+Close`'s `confirmSave` flow. Answering **Save**
  suspends the close until the save task settles (the seams already
  operate asynchronously around `DocumentSession.save`; the guard holds
  the same suspension for the kit save task); **Cancel** aborts the close;
  **Discard** proceeds. On app quit, the app waits for the save to settle;
  there is no abandon path. A clean draft closes silently on every path.
- **Orphan cleanup**: on song tab close and project close/app quit, AFTER
  the close prompts resolve and before the tab/project state is torn down,
  present `OrphanCleanupDialog` when
  `session.orphanSplitStudioSamples()` is non-empty: a checklist of names
  (all checked) with **Delete** / **Keep**. `deleteOrphanSamples(_:)`
  re-runs `KitUsageScanner.usage` per name at delete time — a sample that
  gained a reference since listing is skipped and named in the status
  line; Delete removes the `.wav` and the registration block via
  `SampleRegistrar.deleteRegistration`. Empty candidate list ⇒ no dialog.
  Window close never offers cleanup (the song may still want the files).
- Orphan candidates = names recorded by `recordCreatedSample` this app
  session AND referenced by no voicegroup section at check time (the kit's
  own saved symbols count as references; undo'd-away and renamed-away
  names are eligible once unreferenced, R4).

## Implementation steps

1. Thread `KitStudioCloseGuard` into `saveTabBeforeClose` /
   `closeAllResolved` / `hostClosingImpl` and the tab-close sequencing in
   `SongTabsController+Close` per the R23 contract, preserving the
   existing save-conflict ordering (Split Studio prompt first).
2. Implement `deleteOrphanSamples` on `ApplicationSession` with the
   at-delete-time usage re-check.
3. Add the checklist dialog QML per the text-contrast and geometry rules;
   hook it into the two offering points (tab close, project close/quit).
4. Verify the named lanes stay green; the added behaviors are
   temporary-smoke-verified (Acceptance names the gap).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks:shell --filter shell-split-studio`
  — must stay green: the lane's clean-draft close path must be unaffected
  by the guard integration.
- `uv run --no-sync dev checks --filter swiftcore-projectsession`
  — regression: session close/save interplay (the guard hooks live in the
  session's close paths).
- `uv run --no-sync dev checks:shell --filter shell-tabs-open-select`
  — tab-close sequencing regression.

Coverage gaps (named): the close-prompt flows, quit-wait behavior, orphan
checklist UX, and at-delete re-check have NO permanent rows (decisions'
budget); they are verified ONLY by the temporary controller smoke below. A
passing `shell-split-studio` run is not evidence for these behaviors. The
dialog's contrast surface is reached by the `split-studio` audit state
only via the window's own labels; its standalone opening path is
smoke-verified here (plan.md gap 3).

Runtime prerequisites: none for the named checks; smoke needs a native
desktop session.

## Task-specific constraints

- Orphan deletion is destructive: delete only names that (a) the session
  registry recorded as created this app session AND (b) the at-delete-time
  usage scan proves unreferenced. Never offer files the app did not create
  this session.
- Prompt order is contract: Split Studio prompt before song save prompt;
  orphan checklist after close prompts resolve, before teardown.
- No new permanent checks (budget); do not extend `shell-split-studio`
  with close/orphan scenarios.
- Re-edits only the listed files; the workflow/window changes stay within
  task 11's accepted shape.

## Controller verification

1. CMake line for `OrphanCleanupDialog.qml` (QML module files list).
2. `uv run --no-sync dev build:checks` then the three named lanes.
3. `uv run --no-sync dev checks:bridge` (no surface change expected).
4. Temporary smoke (removed after), on the fixture project with a real
   desktop session: (a) dirty window + tab close / project close / quit ⇒
   prompts in the decided order; Save suspends the close until the save
   settles (quit included); Cancel aborts; Discard proceeds; (b) clean
   window ⇒ silent close; (c) create slices, save, delete their zones,
   save again, close the tab ⇒ checklist lists exactly the unreferenced
   slices (undo'd-away and renamed-away names included); Delete removes
   wav + registration (verify on disk); Keep leaves them; (d) a sample
   that gained a reference between listing and Delete is skipped with a
   status line; (e) window close never offers the checklist.
5. `uv run --no-sync dev format --check` on changed lines.
