# Context

R15 + R18: the timeline ruler menus are proven only at model/presenter level, never through the rendered panel. `RulerMenuPresenter` (`src/swift/app/timeline/RulerMenuPresenter.swift`) backs one `QuickMenuPanel` (`rowObjectNamePrefix rulerMenuRow_`) mounted by `src/ui/songview/quick/swiftroll/EditorSurface.qml`; it serves three menus: cursor menu (menuKind 1), in-selection menu (menuKind 1), and time-selection menu (menuKind 2). Today no mounted check drives a ruler menu row click; `proof.ruler_loop_menu.txt` rows A004–A050 are MATCHED off `document.setLoop`/`insertBlankTime` model calls (S001–S013) — an overclaim the `proof check --strict-mappings` flag cannot catch because the anchors are message-anchored but model-direct. `proof.timemenu.txt` A088 has the same defect. This task proves the surface through mounted QML and repairs the ledger rows in the same commit, including the three chip fixtures and clipboard-availability rows owned by R18. Read plan.md Global constraints and verification.md; proof rows change only with executing predicates in this commit.

# Exact write set

- `src/checks/editorqml/tst_ShellGridMenu.qml`
- `src/checks/rollcheck/ruler_loop_menu.swift`
- `src/checks/rollcheck/timemenu.swift`
- `src/checks/rollcheck/proof.ruler_loop_menu.txt`
- `src/checks/rollcheck/proof.timemenu.txt`

`src/swift/app/timeline/RulerMenuPresenter.swift` only if a needed observation is genuinely unreachable from QML; prefer observe-only.

# Prerequisites

None. Existing lanes already mount the production surface: `shell-grid-menu` (tst_ShellGridMenu.qml, fixture mus_route101) drives `timelineRulerInput` right-click, `quickMenuPanelRoot`, `rulerMenuRow_` items and `clickRow(actionId)`; `shell-transport` drives mounted ruler seeks; swiftcore `projectSession` runs `ruler_loop_menu.swift` + `timemenu.swift` presenter predicates (S001–S019/S001–S013).

# Interface contract

- Preserve `RulerMenuPresenter` public surface and the `RulerMenuRow(actionId/text/enabled/separator)` contract; action ids: insertTime=1, setLoopStart=2, setLoopEnd=3, removeLoop=4, loopFromSelection=5, duplicate=6, deleteTime=7, clearTimeSelection=8, editTimeSignature=9, removeTimeSignature=10, copy=11, cut=12, paste=13, deleteSelection=14.
- New mounted predicates must assert through the rendered panel: open via `mouseClick(timelineRulerInput, RightButton)` or the sweep path, read `rulerMenuRow_<id>` items, `clickRow`, then assert `isOpen`, document bytes/revision, cursor/selection and focus post-conditions. Every new S anchor must be a message anchor.
- Existing presenter predicates stay as model-level evidence; they stop being cited as surface proof for rows the mounted checks now cover.
- Chip fixtures (R18): F1 snap-aligned 5/4 chip (seed `doc.setTimeSignature(chipTick,5,2)`, chipTick 90 ≈ rulerSeedTick 84 + snapCell 6); F2 off-grid 7/2 chip (`chipTick+1`, `setTimeSignature(chipTick+1,7,2)`); F3 no-chip tick-row press (`chipTick+2*snapCell`, row fraction ≈0.75). F1/F2 commit the exact chip tick and enable RemoveSig (id 10); F3 leaves RemoveSig disabled.
- Clipboard rows (R18): Paste (id 13) enablement follows `canPaste` = clipboard holds a decodable non-empty clip; Copy (id 11)/Cut (id 12) follow `selectionCommandAvailable`; a disabled Paste click neither dispatches nor dismisses. Clipboard seeding goes through `GridClipboard`/`ClipboardCodec`, not a presenter backdoor.

# Implementation steps

1. In `tst_ShellGridMenu.qml`, extend the ruler tests to cover the rendered-panel paths the ledgers claim: SetLoopEnd (id 3) isolated click with two-step undo; RemoveLoop (id 4) presence/enablement flip with loop state; EditTimeSignature (id 9) and RemoveTimeSignature (id 10) enablement and click; disabled-row click stays open and writes nothing; outside-press and Escape dismissal; stale-revision guard (mutate selection/cursor between open and click → no write). Assert `isOpen==false` after activation, revision/bytes changed where expected, and ruler focus/cursor invariants.
2. Add mounted chip presses for F1/F2/F3 through `EditorSurface` ruler input: press at chip tick on the marker row commits that exact tick and opens menuKind 1 with RemoveSig enabled (F1/F2); F3 press opens the menu with RemoveSig disabled. Correct the S014 wrong-chip mapping by splitting snap-chip vs off-grid-chip predicates in `ruler_loop_menu.swift` and citing the mounted cases.
3. Add mounted clipboard cases: seed a non-empty range clip → Paste row enabled in both cursor and time-selection menus; poison/empty clip → Paste present but disabled and a disabled click is a no-op that leaves the menu open; Copy/Cut rows enabled iff an active time selection exists. Cover reopen-after-state-change.
4. In `ruler_loop_menu.swift`/`timemenu.swift`, keep the model predicates but split/rename only where a mapping needs an exact fixture (F1 vs F2 vs F3). Do not delete executing predicates; demoted citations are ledger edits, not check deletions.
5. Ledger repairs in this commit via `deno task proof:edit`: in `proof.ruler_loop_menu.txt`, rows whose MATCHED rested only on model calls (A004, A009, A015, A017, A022, A024–A026, A030, A032, A033, A037, A050, A108, A109) either cite new mounted predicates (keep MATCHED only where the mounted case executes the same clause) or drop to PARTIAL/GAP; correct the A039 wrong-chip S014 mapping; leave A051/A104-style undo-depth conjuncts unproved (no history-depth predicate exists). In `proof.timemenu.txt`, remap A088 off the bare insertBlankTime model call; close A006–A008, A018, A020–A023, A030–A032 only where the mounted Paste/Copy/Cut cases execute the clause. Chip rows A036–A061 resolve only through the F1/F2/F3 mounted presses.

# Acceptance predicate

The mounted cases execute the claimed clauses; no MATCHED row remains whose only evidence is a direct model/presenter call for a menu-surface clause. Rows still lacking evidence stay GAP/PARTIAL — this task does not chase disposition counts.

Controller-run named checks after the writer freezes:
- `deno task verify:shell --filter shell-grid-menu --verbose` — every rendered-panel row/click/dismissal case.
- `deno task verify:shell --filter shell-transport --verbose` — mounted ruler seek guards (S020–S024 regression).
- `deno task verify:shell --filter shell-menus --verbose` — Edit-menu loop-from-selection adjacency.
- `deno task verify --filter swiftcore --verbose` — presenter predicates S001–S019/S001–S013 unchanged.
- `deno task proof check --executed` and `deno task proof check --strict-mappings` — ledger structure, execution and meaningful-mappings after remap.

# Task-specific constraints

No new lane registration. Do not restructure `tst_ShellGridMenu.qml` — append cases beside the existing ruler tests. Do not touch `RulerMenuPresenter.sweepTrackScope` (R23 locks it separately), `EditorSurface.qml`/`QuickMenuPanel` imports or the `timeSigHost` prompt path (F4 3/4-prompt chip belongs to the prompt surface, out of scope). Do not re-pin undo counts or incidental enablement orders that have no predicate. Keep unrelated GAP/PARTIAL rows untouched.
