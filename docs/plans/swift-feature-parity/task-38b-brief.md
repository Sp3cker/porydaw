# Context

Part 2 of the task-38 split (see task-38a-brief.md for the boundary): the
session-owned time selection 38a publishes now drives the **shared time menu
and the ruler menu** with fork semantics — canonical enablement, paste
eligibility with live menu retirement, no-dispatch/no-write on stale and
cancelled menus, the two-command loop undo shape, insert-time laws, and the
rejected-paste invariant set. Fork originals: read via the ledger reference
revisions (`git show 90446f5d:src/checks/rollcheck/timemenu.cpp`,
`git show a1244957:src/checks/rollcheck/ruler_loop_menu.cpp`; production
laws at `fceecd88` paths below).

1. **Fork time menu** (roll band right-click on empty space inside an active
   selection; `fceecd88:src/ui/songview/rangeedit.cpp:814-855`,
   `songview.h:97-104` ids Copy/Cut/Delete/InsertBlank/Duplicate/
   RemoveContents/Paste/Clear = 1…8): every row projects the canonical
   `EditActions` QAction — label, shortcut text, and enablement come from
   the shared command table, and a changed or destroyed action **retires the
   open menu**. Laws pinned by `timemenu.cpp` (rows A001–A100):
   - Paste is enabled exactly while the clipboard holds a non-empty clip;
     eligibility is re-read fresh on every clipboard change, and an
     eligibility flip **retires the open menu** (:159-199). Copy and Clear
     never pre-disable while the menu is open (:160-166).
   - A real click on a disabled row neither dispatches nor dismisses — the
     menu stays open, document and undo stack untouched (:200-211).
   - The Copy row restores the copied range payload (span + notes) without
     mutating the document or undo stack (:168-196).
   - Escape dismisses without a command, keeps the selection, returns focus
     to the roll band (`timeSelectionMenuStaleAndCancelNoOp`, A065–A076).
     Clearing the selection while the menu is open retires it immediately
     with no write (:412-424).
   - Insert Time (`timeSelectionMenuInsertTimeAndStaleNoOp`, A077–A088):
     one undo transaction, notes after the span shift by it, the edit
     cursor commits to the selection start seam, the selection is retained
     over the blank span, one undo restores the bytes.
   - Sweep (`timeSelectionMenuSweepKeepsCanonicalEnablement`, A089–A100):
     a live Shift+right-drag commits through the selection model while the
     gesture is live, and canonical availability describes the committed
     selection, never the gesture — Copy/Duplicate/Clear stay enabled
     mid-sweep; Duplicate also enables for a note-only selection (notes
     arm) with no time selection.
2. **Rejected paste preserves view state** (`rejectedNotePastePreservesViewState`,
   A025–A064), for both note clips (span 0) and range clips, each with and
   without an active time selection, entered by key and by the menu Paste
   row: a conflicting incoming span rejects the paste with **zero** change
   to document bytes, revision, undo index/count/canRedo, note selection,
   time selection (start/end/scope), stored track scope, edit cursor,
   camera scroll x/y — and zero `editCursorMoved` and zero status
   announcements. Removing the conflicting span admits the same command:
   pasted note content/duration/velocity land at the snapped cursor, cursor
   advances past the pasted span, a range clip clears the time selection
   while a span-0 clip selects the inserted notes, exactly one undo entry,
   undo/redo round-trips. An empty-content nudge (arrow key with an empty
   band selection past the song end) moves the band without publishing an
   edit.
3. **Fork ruler menu** (built in `fceecd88:src/ui/songview/timeruler_
   interaction.cpp:344-365` from the same canonical actions): cursor rows
   Insert Time, Paste, Set Loop Start, Set Loop End, Remove Loop Markers
   (enabled iff any marker exists), Edit Time Signature, Remove Time
   Signature (enabled iff an explicit signature sits at the committed
   cursor tick); selection rows Loop from Selection, Insert Time,
   Duplicate, Delete Time, Clear Time Selection, separator, Remove Loop
   Markers — no positional or signature rows inside. Laws pinned by
   `ruler_loop_menu.cpp` (A001–A113):
   - Set Loop Start/End each push **one** command and refocus the ruler
     band (A001–A033); Remove Loop Markers and Loop from Selection each
     push **exactly two** commands with undo restoring one marker at a
     time (end first); Loop from Selection brackets the selection,
     pressed strictly inside the half-open interval.
   - Enablement context (A034–A068): no markers + no selection → Remove
     disabled, scoped rows absent, Insert Time enabled at the cursor; an
     explicit chip press commits the chip's exact tick (even off-grid) and
     enables Remove Time Signature (one command), an implicit/cursor-only
     tick disables it; disabled-row clicks neither dispatch nor dismiss;
     Clear Time Selection drops the scoped rows on rebuild.
   - Stale/cancel (A069–A092): Escape no-write with focus back to the ruler
     band and the committed cursor kept; a document edit after the open
     retires the menu (no loop write); a selection change retires it; an
     outside left press dismisses without retargeting the popup.
   - Insert Time from the selection menu (A093–A113): a raw press inside
     the interval finishing before snapping leaves selection and cursor
     untouched, and the row inserts over the selection (one undo, cursor to
     the seam, selection retained); a press exactly at the interval end is
     outside the half-open selection — it clears the selection, commits the
     snapped end tick, and opens the cursor menu.
4. **Current Swift**: menus already exist with fork-shaped topology
   (`RulerMenuPresenter.swift:81-176`; Swift labels stay — task-46
   normalizes wording) and activation already re-validates captured
   revision/cursor/selection before dispatching (:176-189); loop writes
   already push two commands (`:191-195`;
   `AutomationSelectionCommands.swift:47-51`); insert/delete/paste bodies
   exist (`AutomationSelectionCommands.swift:53-158`); `canPaste` requires
   selection-command availability plus a decodable payload with notes, lane
   points, or tempo (:155-163). Missing: live menu retirement on clipboard
   / selection / document change while open; the observable paste
   eligibility law (fork: clipboard presence alone with a song open — the
   active-parameter conjunct must not disable the row); the Escape
   focus-return contracts; the rejected-paste invariant set and
   empty-content nudge; rendered-row proofs for insert-time and the
   disabled-click no-write. Mounted anchors already executing:
   `tst_ShellGridMenu.qml` `test_shiftRightRollSweepOpensCanonicalTimeMenu`,
   `test_rulerLoopAndSelectedTimeRowsExecuteFromRenderedPanels`,
   `test_actionRowsCloseBeforePromptAndDisabledRowsStayOpen`.

# Exact write set

- `src/swift/app/timeline/RulerMenuPresenter.swift`* (hot via 38a chain) —
  paste eligibility law; live retirement observers (clipboard change,
  selection transition, document revision) closing an open menu; Escape
  focus return.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — retirement +
  focus plumbing for the shared menu panel. *Hot file.*
- `src/swift/app/drawer/automation/AutomationSelectionCommands.swift` —
  rejected-paste invariants (no cursor move, no announcement, no camera
  reveal on rejection); empty-content nudge without an edit; verify
  insert-time cursor/seam/selection retention.
- `src/swift/app/ApplicationSession.swift`* — only if router paste
  availability must change for the eligibility law. *Hot file.*
- `src/checks/rollcheck/timemenu.swift` — presenter-level predicates:
  eligibility flip retirement, rejected-paste invariant set, insert-time
  one-undo law, sweep canonical availability.
- `src/checks/rollcheck/ruler_loop_menu.swift` — two-undo shape, stale
  retirement, enablement-context predicates.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — mounted predicates:
  disabled Paste click keeps the menu open with no write; clipboard flip
  retires the open menu; Escape returns focus; insert-time from the
  rendered row.
- `src/checks/editorqml/tst_ShellClipboard.qml` — mounted rejected-paste
  predicate (document/cursor unchanged through a conflicting paste).
- Ledgers (controller-delegated ledger agent, this task's commit):
  `src/checks/rollcheck/proof.timemenu.txt`,
  `src/checks/rollcheck/proof.ruler_loop_menu.txt`.

`ShellWindow.qml` and `PianoGrid.swift` are not edited. Sizing exception: one
behavior family over 8 files with one verification-surface set — named for
the dispatch table.

# Prerequisites

38a (`session.timeSelection`, `onSelectionTransition`, the release-timed
ruler open). Tasks 36/37 settle the shared hot files first.

# Interface contract

- Paste eligibility (both menus): the Paste row is enabled exactly while
  `session` has a song open and the clipboard decodes to a clip with at
  least one note, lane point, or tempo item; a decode failure disables the
  row (the existing "Cannot paste: clipboard clip could not be decoded"
  announcement stays on execution, not on menu build). Internal conjuncts
  may remain only if this observable law holds in every mounted state.
- Retirement: an open ruler/time menu closes without dispatch when (a) the
  clipboard content changes, (b) a selection transition or `.selection`
  publication arrives, or (c) the document revision changes while open.
  Rows keep their existing ids/labels/enabled sources.
- Escape on an open menu: dismisses, no command, no write, and focus
  returns to the band that opened it (roll band for the time menu, ruler
  band for the ruler menu); the committed edit cursor is not restored.
- Disabled-row click: consumed, menu stays open, no command, no write
  (already guarded at activation — the mounted predicate proves the full
  path).
- Rejected paste (key or menu row): zero mutation of document bytes,
  revision, history, note selection, time selection, track scope, edit
  cursor, camera scroll; no cursor-move or status announcements. Accepted
  paste keeps the existing contract (cursor advances; range clip clears
  the time selection; span-0 clip selects inserted notes; one undo).
- Insert Time row (both menus, selection-scoped): one undo transaction;
  notes at/after the span shift by it; cursor commits to the selection
  start seam; the selection is retained over the blank span; one undo
  restores the bytes. The cursor-menu Insert Time keeps the existing
  bars/beats prompt path (`openInsertTimePrompt`,
  `acceptInsertTimePrompt`) with its revision and span guards.
- Loop rows: Set Loop Start/End one command each; Remove Loop Markers and
  Loop from Selection exactly two commands each, undo restoring one marker
  at a time; row enablement per Context ¶3.

# Implementation steps

1. RED: presenter + mounted predicates for the missing laws (anchors
   below). Record RED.
2. `RulerMenuPresenter`: eligibility law + retirement observers + Escape
   focus return.
3. `AutomationSelectionCommands`: rejection invariants + empty-content
   nudge; audit insert-time law against the contract.
4. Mounted predicates in `tst_ShellGridMenu.qml` / `tst_ShellClipboard.qml`.
5. GREEN on the lanes below with regressions green.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-grid-menu --verbose` — menu
  topology, retirement, disabled-click, insert-time, sweep regression.
- `deno task verify:shell --filter shell-clipboard --verbose` —
  rejected-paste invariants, copy/paste round-trips.
- `deno task verify --filter swiftcore --verbose` — presenter-level
  eligibility/retention/undo predicates.
- `deno task verify:qml-roll --verbose` — EditorSurface touched.
- `deno task verify:bridge`

# Task-specific constraints

- No new C++; no code comments; no palette/label changes (labels are
  task-46's); no menu-row additions or reorderings; task-38a's gesture laws
  are not re-opened here.
- Implementers never edit ledgers. Ledger mapping (agent; re-verify every
  row at freeze against the landed anchors):
  - `proof.timemenu.txt` (A-row groups by function): A001–A024 → mounted
    anchors "Paste is enabled exactly while the clipboard holds a
    non-empty clip", "the Paste eligibility flip retires the open time
    menu", "Copy and Clear never pre-disable", "a disabled Paste click
    keeps the menu open without a write", "the Copy row restores the range
    payload without mutating the document". A025–A064 → "a conflicting
    paste preserves every view-state invariant" (+ cursor/camera/
    announcement/undo sub-anchors), "removing the conflict admits the
    paste", "an empty-content nudge moves the band without an edit".
    A065–A076 → "Escape dismisses the time menu without a command",
    "clearing the selection retires the open time menu", "dismissal returns
    focus to the roll band". A077–A088 → "the Insert Time row commits one
    undoable insertion at the seam", "the insertion retains the selection",
    "one undo restores the bytes". A089–A100 → the existing sweep anchors
    plus "Duplicate stays enabled for a note-only selection".
    Seed/fixture-guard rows → the counterpart function's setup anchor,
    else `RETIRED-REPRESENTATION` following the ledger's existing ten.
  - `proof.ruler_loop_menu.txt`: A001–A033 → "Set loop start pushes one
    command", "Set loop end pushes one command", "Remove loop markers
    pushes exactly two commands", "undo restores one marker at a time",
    "loop from selection brackets the selection". A034–A068 → "Remove loop
    markers stays disabled without markers", "scoped rows are absent
    without a selection", "the chip press commits the exact chip tick",
    "Remove time signature is enabled only at an explicit chip", "Clear
    time selection drops the scoped rows on rebuild". A069–A092 → "Escape
    dismisses the ruler menu without a write", "a document edit retires the
    open ruler menu", "a selection change retires the open ruler menu",
    "an outside press dismisses without retargeting". A093–A113 → "the
    in-selection insert commits at the seam in one transaction", "the
    exact-end press clears the selection and opens the cursor menu".
    Rows 38a already closed keep their anchors; menu rows pinning
    QQuickWindow/QPointer popup internals → `RETIRED-REPRESENTATION`.
  - Blocked rows left untouched: none known; anything the freeze
    re-verification cannot execute stays as-is.

# Controller verification

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — both rollcheck ledgers show
   executing anchors and no unmapped MATCHED sites.
2. Visual (desktop smoke): right-click inside a swept band → Copy copies
   without dirtying the title; clearing the clipboard retires the open
   menu; a greyed Paste click leaves it open; Escape returns to the roll;
   Insert Time shifts later notes, parks the cursor at the seam, one ⌘Z
   restores; loop-marker commands undo one marker at a time; an
   overlapping paste leaves song, cursor, and scroll untouched.
