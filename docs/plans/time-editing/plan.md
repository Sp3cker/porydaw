# Time editing implementation plan

## Status

Planning only; this rewrite does not authorize implementation, commits, pushes or worktree operations. Proposed behavior below resolves the three requested outcomes: time deletion, consolidated insertion and context-menu placement. Execution and any SDD checkpoint commits require the corresponding user authorization.

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Rename insertion command](task-1-brief.md) | Direct / inline | Reversible same-shape rename; mechanical four-file exception, no behavior change. | None |
| 2 | [Make insertion selection-first](task-2-brief.md) | SDD-track / sdd-implementer | Command policy changes across API, implementation and consumer checks. | 1 |
| 3 | [Expose Delete Time in Edit](task-3-brief.md) | SDD-track / qt-cpp-reviewer | QAction ownership and window-input routing span three files. | 2 |
| 4 | [Prove window command routing](task-4-brief.md) | SDD-track / qt-cpp-reviewer | Cross-task QAction and native input contracts need behavioral proof. | 2, 3 |
| 5 | [Unify guarded context menus](task-5-brief.md) | SDD-track / sdd-implementer | Two guarded dispatch paths consume a shared command and registry interface. | 2, 3 |
| 6 | [Defend live and stale menu insertion](task-6-brief.md) | SDD-track / sdd-implementer | Distinct pointer-entry paths must preserve stale-target safety. | 5 |
| 7 | [Document verified time editing](task-7-brief.md) | SDD-track / sdd-implementer | User-facing claims consume verified contracts across command surfaces. | 4, 6 |

The rename is a mechanical preparation batch, not a separately invented feature. It cannot absorb semantic edits under the file-cap exception. Tasks 3/4 and 5/6 share verification surfaces, but merging either pair exceeds the three-file cap (five and six files respectively); their boundaries are production interfaces versus consumer proof. Task 2 already includes its existing consumer checks. Seven tasks remain; no task exists solely for formatting, a report or a checkpoint.

Main owns integration. Tasks 4 and 5 have disjoint writes and may overlap after Tasks 2/3, subject to the execution loop's in-flight limit. All other overlapping write sets are serialized. Direct Task 1 uses inline Target/Change/Acceptance derived from its requirement brief; SDD dispatch/review envelopes and progress tracking belong to `rule://sdd-execution-loop`, not these files.

## Global Constraints

- Every brief inherits this section. Write sets are closed; preserve unrelated changes. Refresh source sections before editing, use LSP references for exported API changes and LSP rename for symbol cutovers. Newly discovered consumers require resizing the task, not a shim.
- Reuse existing SongView scope resolution, SongDocument mutations, history and prompt ownership. No new production module, harness, domain algorithm, deletion prompt, shared-key dispatcher, focus memory or unrelated refactor.
- The behavior section owns shared semantics. Briefs specify only their produced interfaces and task-local edge cases; no compatibility aliases or duplicate implementations.
- Extend existing behavioral fixtures. Preserve meaningful coverage, remove touched wording/plumbing assertions, and do not duplicate domain seam matrices or cosmetically rename test slots. No production test-access API.
- At most three files, five steps and one acceptance predicate per task; only the pure Task 1 rename uses the mechanical exception. Prefer existing-file edits over new abstractions.
- Design pressure: reshape existing seams before adding machinery. Task 1 is Rename Function; Task 5 redirects callers to the canonical command and hides its selection-only helper. Only Task 2 changes insertion policy; Task 3 exposes existing removal through one Qt action. Tasks 4/6 extend existing fixtures; Task 7 updates existing documentation.
- Keep derivation at command time rather than adding cached selection/capability state. Reuse Qt action ownership, the keymap registry and current scope/prompt/history owners; introduce no new threading or lifetime boundary. Each interface contract names its reuse owner, and each task-specific constraint names the residual risk its checks must cover.

## Behavior and interfaces

### Insert Time

1. If a time selection is **active**, its half-open span supplies the insertion duration and start; its existing resolved track/lane/tempo/whole-song scope supplies the affected content. This wins over both edit cursor and playhead, including while playback is active.
2. An active but unresolved selection is a rejected command: no document/revision/undo/cursor/selection change and no duration prompt. Test selection activity first; do not write `if (resolveTimeSelectionScope()) ... else openPrompt()`.
3. If there is **no active selection**, preserve the current bars/beats/quarter-beat-fractions prompt and its whole-song insertion at the playhead/edit cursor. Prompt ownership, numeric bounds, tick arithmetic, stale document/revision rejection and cancellation stay unchanged.
4. Successful selection insertion retains the time selection over the new blank span and commits the edit cursor to the start, as the current selection-only implementation does. One mutation creates one undo transaction; existing domain no-op/rejection results do not fabricate an undo entry.
5. Public policy entry point: `SongView::insertTime()`. `insertBlankTime()` remains its private selection-only implementation after the context-menu cutover. The old exported `insertTimeAtPlaybackCursor()` name is removed, not kept as an alias.

### Delete Time versus clearing contents

- **Delete Time (Shift Left)** uses the active selection's span and resolved scope through `removeTimeSelectionContents()` and `SongDocument::removeTimeRange()`. On successful removal, later scoped content shifts left, the selection clears, and the edit cursor moves to the start seam. Undo restores the previous song bytes in one step.
- No selection or unresolved scope means no mutation and no prompt. Preserve the current silent early rejection; a new notification policy is not part of this feature.
- Whole-song behavior is selected only by the existing scope resolver, never by failed resolution or by a click location. Existing note, automation, tempo, signature, marker, XCMD and track-end semantics are unchanged.
- **Delete range / ordinary Delete / Backspace / Cut** keep their contents-only behavior. Later event positions do not shift because these commands ran. This distinction must be stated in the manual.
- No typed-duration Delete Time prompt and no default destructive shortcut. Register `edit.delete_time` as Global/Edit with an empty default binding so the existing registry remains authoritative. The plan does not ship `Ctrl+Shift+Delete`.

### Placement and ownership

| Surface | Insert | Ripple removal |
| --- | --- | --- |
| Edit menu | Existing `insertTimeWindowAction`, `edit.insert_time`; Fixed `Insert &Time` | New `deleteTimeWindowAction`, `edit.delete_time`; `Delete &Time (Shift Left)` |
| Window input | Existing configured Insert shortcut; one owner and one dispatch | No default shortcut; ordinary Delete is not reassigned |
| Selection context menu, including drawer-origin selections | Keep `InsertBlank` ID; display `Insert Time`; derive shortcut from `edit.insert_time` | Keep `RemoveContents` ID; display `Delete Time (Shift Left)`; derive shortcut from `edit.delete_time` |
| Ruler context menu | Same selection-scoped semantics and label, independent of click tick | Same selected-span removal, independent of click tick |

Keep both context-menu paths as pointer affordances, not parallel implementations. Retain unrelated menu rows and their order. Freshness checks must run **before** dispatch into the unified insertion command so an expired selection cannot accidentally open the global prompt.

MainWindow owns its QActions; SongView owns command policy; SongDocument owns musical mutations. Do not route a second Insert/Delete Time shortcut through each band or `handleEditKey`. Text inputs and popup-local keys retain their ownership. Keep a fixed Insert caption; do not add menu-show caption updates, selection observers or stored capability state.

Both Edit actions use the existing tab-readiness enablement pattern. Triggering Delete Time without a selection is inert; do not add a status tip solely for this command. This plan deliberately does not introduce persistent selection-dependent QAction enablement, since that would require another synchronization boundary. Command-time scope guards remain authoritative even for programmatic or rebound activation.

## Verification policy

Implementers format their own changed code files with `deno task format <explicit slice files>` before reporting; never run a repository-wide formatter or format another task's files. They run applicable diagnostics and the named focused checks in their brief, returning command/output evidence. Verification may be narrowed to the changed surface, never waived. Documentation-only Task 7 uses its named documentation checks rather than an unrelated application build.

When concurrent edits share a build/check surface, mark the dispatch `SHARED_TREE`: implementers still format their own slices and run applicable file diagnostics, but return build/check evidence as `tests: DEFERRED_TO_CONTROLLER`. The controller runs the required focused checks and runtime proof on the settled merged tree at checkpoint, before the review gate. Tasks 4 and 5 use this exception if overlapped; independent file ownership alone does not make their shared build safe to run concurrently.

Use `deno task` for repository formatting, builds and harnesses. One check invocation may satisfy multiple predicates only when it exercises their completed changes at an allowed settled boundary; never carry pre-change evidence forward or defer a required task gate merely to save a build.

Tasks 1 and 2 name the same check command, but each must supply evidence for its own changed state unless the shared-tree checkpoint legitimately covers both. Tasks 3 and 5 require native smoke proof of their production surfaces before acceptance; Tasks 4 and 6 add only the retained regressions that catch plausible routing bugs. Keep temporary smoke artifacts out of the repository and remove them after proof.

For the Edit menu, launch the app, inspect placement/labels, activate ripple deletion on a selection, undo, then activate without a selection and observe no edit. For both context menus, activate Insert and Delete with fresh selected spans and undo; selection, not click position, supplies the range. Caption strings and QAction plumbing do not warrant permanent assertions.

After Tasks 4 and 6, run the integration gate once:

```sh
deno task verify --filter rollcheck --filter mainwindow-routing-input --filter mainwindow-routing-native --filter editcheck --filter automation-domain --verbose
```

Native input must actually execute on its registered native backend; skipped/offscreen results do not satisfy it. Any failure must be reported and resolved. The unchanged domain suites control ripple semantics; they are not an invitation to rewrite those algorithms. Task 7 requires this runtime evidence and documentation inspection, not another application build. Final review follows the execution loop; do not copy its report schemas, checkpoint mechanics or fix-loop instructions into briefs.

## Source anchors

| Owner | Verified current behavior |
| --- | --- |
| [SongView range commands](../../../src/ui/songview/rangeedit.cpp), `deleteTimeSelection`, `removeTimeSelectionContents`, `insertBlankTime` | Contents clearing, ripple removal and selection-span insertion are already separate operations. Ripple removal calls `SongDocument::removeTimeRange`; selection insertion calls `SongDocument::insertBlankTime`. |
| [SongDocument contracts](../../../src/core/songdocument.h), `TimeRange`, `TimeScope` | Existing half-open ranges, explicit scope and undoable domain operations are the authoritative musical semantics. Do not recode them in the UI. |
| [Time editor](../../../src/core/songdocument_timeeditor.cpp) and [insertion implementation](../../../src/core/songdocument_timeeditor_insert.cpp) | Removal/insertion already own note and value-stream seams, track/global event handling and rejection paths. Existing domain checks remain the control. |
| [SongView declaration](../../../src/ui/songview.h), `insertTimeAtPlaybackCursor` | The current global command always opens the duration prompt. A live playhead is its anchor while playing; otherwise the edit cursor is used. |
| [MainWindow](../../../src/mainwindow.cpp), action setup and `updateChrome` | Insert Time has a registry-backed WindowShortcut QAction and tab-readiness enablement. There is no corresponding Delete Time QAction. |
| [Keymap](../../../src/ui/keymap.cpp), `edit.insert_time` | Existing insertion binding is `Ctrl+Shift+I`; Qt's platform convention makes this Command on macOS. |
| [Selection menu](../../../src/ui/songview/rangeedit.cpp), `buildTimeSelectionItems`/`handleTimeSelectionAction`; [ruler menu](../../../src/ui/songview/timeruler_interaction.cpp), `showRulerMenu`/`handleRulerMenuAction` | Both expose Insert blank time and Remove contents (shift left), with guarded open-time document/selection targets. They already share semantic methods. |
| [Shared edit routing](../../../src/ui/songview/editkeyrouting.cpp) | Ordinary Delete/Cut on a time selection clear contents rather than closing the selected time interval. Keep this routing and precedence. |
| [Selection model](../../../src/ui/songview/editorselectionmodel.h), `TimeSelection::active` | Active means `endTick > startTick`, not that scope resolution succeeded. Scope rejection must be distinct from absence of a selection. |
| [Roll insertion checks](../../../src/checks/rollcheck/keyboard.cpp), `timelineInsertBlankTimeTracks`/`timelineInsertBlankTimeLanes` | Existing consumer assertions cover selected-scope insertion, unaffected tracks/notes, selection/cursor state and undo. Migrate these to the unified command instead of duplicating them. |
| [Window input checks](../../../src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp), `insertTimeRoutesActiveSongAndRestoresUndoBytes` | Existing prompt integration covers active-song routing, playback/stopped anchors, acceptance/cancellation and undo. Preserve the no-selection behavior. |
| [Check catalog](../../../src/checks/checkcatalog.cpp) | The registered suites include rollcheck, mainwindow-routing-input, mainwindow-routing-native, editcheck and automation-domain. Native routing is explicitly WindowSystem. |

Sources can change between authoring and execution. Read the named sections again and use LSP references; do not apply recorded line numbers as patches. The existing automation parameter-tab plan is separate and is not a dependency or authorization for this work.

