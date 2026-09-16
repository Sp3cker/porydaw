# Keep rejected edits truthful in the UI

## 1. Context

Consume Task 1's unchanged-revision rejection contract from [spec.md](spec.md). Inherit [Global Constraints](plan.md#global-constraints). The document fix alone is insufficient: current paste callers clear selection, advance the edit cursor and announce success after a rejected void mutation. This package owns those consumer effects, shown-UI evidence and the user-facing explanation.

## 2. Exact write set

- `src/ui/songview/rangeedit.cpp`
- `src/checks/rollcheck/timemenu.cpp`
- `src/checks/rollcheck/tst_pianoroll.h`
- `docsrc/manual/piano-roll.md`

## 3. Prerequisites

Task 1: colliding semantic document edits refuse atomically without changing revision; per-pitch moves return false; successful Delete Time collision resolution trims the stationary head.

## 4. Interface contract

Public SongView signatures stay unchanged. Edit bodies of `pasteRangeAtEditCursor`, `pasteFromClipboard`, `nudgeTimeSelection`, and `transposeTimeSelection` only. Retain clipboard decoding, DestinationMapper, scope resolution, DocumentSwapHintScope, cursor placement and successful-edit announcements.

Capture revision immediately before each document mutation and gate success-only view effects on revision change. For `nudgeTimeSelection`, continue moving the selection band when the gathered edit is genuinely empty; when nonempty content is rejected, keep the band unchanged. Do not replace existing scope rules with revision checks.

No rejection dialog, new status channel, synthetic key routing, or public result type. Rejected paste retains note/time selection, edit cursor and camera and emits no successful-paste announcement. Accepted paste keeps existing tiling and selection behavior. `foldTransposeSelection` and piano-roll resize/nudge already have boolean/revision gates and stay unchanged.

Add the slot `rejectedNotePastePreservesViewState` to the existing rollcheck class, implemented in `timemenu.cpp`. Reuse its shown fixture, `clipcheck_support::ClipboardStateGuard`, typed clip writer, and existing menu/key routing. No test-only SongView accessor.

## 5. Implementation steps

1. Apply the revision gates to both paste paths, then range transpose/nudge with the explicit empty-content exception. Keep each check adjacent to the existing mutation; do not extract a generic UI mutation wrapper.
2. Add the shown-UI regression for plain-note and range clips containing conflicting same-pitch spans. Drive the real Paste command, observe unchanged document/undo, selection and cursor, and no success announcement. Use existing public signals/state, not literal message matching. A subsequent valid paste must advance/select normally and undo normally; clipboard state must be restored on all exits. Extend the scenario to distinguish empty-band nudge from rejected nonempty mutation where reachable through the UI, without forcing an impossible gesture or inventing a private-access hook.
3. Perform the native smoke below after core/UI checks pass. Confirm rejected grouped resize returns to actual unchanged notes, accepted adjacency remains editable, and ripple collision trims rather than leaves a stray event. Inspect the actual Event List after these actions; do not infer release integrity from note rectangles alone.
4. Update the existing manual's note editing and Delete Time sections with the rejection policy and crossing-note trimming. Explain that a conflicting group edit leaves the selection's notes unchanged, whereas collision with unselected notes retains the existing edited-note-wins rule. Do not describe cleanup/import repair as shipped. Remove temporary smoke files after proof; no new changelog file or placeholder docs.

## 6. Acceptance predicate

Task 1's refusal reaches users without fake cursor movement/selection changes/success messages, accepted commands retain their existing behavior, and the manual matches the observed surface.

NAMED CHECKS (implementer on its settled tree; otherwise controller):

```sh
deno task verify --filter rollcheck --exclude rollcheck-static --qt rejectedNotePastePreservesViewState
deno task verify --filter rollcheck --verbose
```

The first command exercises the new shown-UI rejection/accepted-paste boundary. The second preserves existing pointer, keyboard, selection, time-menu and static roll behavior. `rollcheck` requires an available native desktop for its shown checks; a skipped native scenario does not count as proof.

## 7. Task-specific constraints

- A document no-op must not be reported as a successful insertion. Do not preserve the planner proposal's suggested false-success paste behavior merely because overflow rejection had the same wart.
- Preserve intentional empty time-selection movement. Revision alone cannot distinguish that case from refused content.
- This is not a preview redesign: a provisional drag may show attempted geometry before release; the committed view must return to unchanged geometry after rejection.

## Controller verification

Run final settled-tree checks once both tasks settle:

```sh
deno task verify --filter editcheck --filter rollcheck --verbose
```

Format only the changed C++ files with `deno task format <explicit changed C++ paths>` under the plan-wide ownership policy.

Launch the built Porydaw app through the supervised process tool with a visible native window. Create a new song, draw two separated same-pitch notes, select both and extend the first past the second's start. Release: both original spans and undo state remain. Repeat at exact adjacency: accepted, undo/redo correct. Exercise convergent pitch movement if available in the current scale-fold surface. For Delete Time, use same-pitch `[0,100)` and `[110,120)` or grid-scaled equivalents and delete `[20,50)`; inspect the expected trimmed head and moved note, then undo/redo. Inspect raw release rows in the Event List to ensure each belongs to one visible note. Finally attempt conflicting plain/range paste through the real command and confirm no cursor advance, selection loss or success report; valid paste still tiles. Record actual observations and a native-window screenshot; do not claim this smoke ran during planning.
