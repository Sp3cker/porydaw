# Undo History window — spec

Status: agreed behavior for implementation planning. Touches the song history model
(`PorydawCore`), the application session bridge, and shell chrome. Self-contained: every
requirement below is expressed against existing Porydaw symbols only.

## 1. Goal

A read-only Undo History window listing the selected song's recorded edit steps, newest
first. Activating a step — click or keyboard selection — rewinds or advances the document to
exactly that point in one operation. The list is a live projection of the history stack: it
updates as edits land and as undo/redo runs, marks the current position and the last-saved
position, and dims steps that are currently undone.

## 2. Vocabulary

- **Step** — one recorded history entry (document change-set or bank action) in
  `SongHistory.entries`.
- **Cursor** — `SongHistory.undoIndex`: the count of applied steps. Steps at offsets
  `..< undoIndex` are applied; steps at offsets `>= undoIndex` are recorded but undone
  (redoable).
- **Current step** — the applied step at offset `undoIndex - 1`, i.e. the edit whose effect
  the document currently shows.
- **Saved position** — the step whose `afterIdentity` equals `savedIdentity` (the state on
  disk), or the base state when nothing was saved since open.

## 3. Current model (facts this builds on)

`SongHistory` already provides the cursor semantics the window needs:

- `undoIndex` / `undoCount` mirror applied-entry cursor and total recorded entries.
- `undo()` / `redo()` (async) replay one step; document entries apply synchronously through
  `applyDocument`, bank entries replay through `BankHistoryAction.apply(direction:)` under a
  transition token; stale bank entries self-heal by dropping from the log.
- Gesture merging coalesces repeated edits into the last entry (document: same
  `HistoryGroup` + `matchesGesture`; bank: `merged(with:)` + `rebaseCurrent`); a cancelled
  gesture that returns to origin removes its entry.
- `currentIdentity` vs `savedIdentity` drives `isDirty`.
- Recording discards the redo tail; `markSaved` seals the adjacent merge boundary.

The window adds: a step cap, step labels, a read-only projection, one coalesced change
signal, a jump API, and the surface itself.

## 4. Core changes — `src/swift/core/SongHistory.swift`

### 4.1 Step limit and eviction

- Add `public static let stepLimit: Int = 512`.
- After every append (the non-merge tail of `record` and `recordConfirmedBankOwned`), evict
  from the front while `entries.count > stepLimit`, decrementing `index` by the number
  removed. Eviction never touches the redo tail: a redo tail only ever disappears wholesale
  on the next record, as today.
- `isDirty` remains correct without extra bookkeeping: it compares identities, not
  reachability, so losing evicted steps cannot flip the dirty flag.
- Rationale: a bounded log makes a full-list projection cheap (no row windowing or paging
  machinery) and bounds memory for long sessions. 512 covers deep editing sessions while
  keeping the window list trivially scrollable.

### 4.2 Step labels

- Each entry stores one immutable label, built once when the entry is appended and replaced
  only when a gesture merge replaces the entry's operation. Labels are never recomputed on
  projection or per frame.
- Track-scoped note and event operations produce rows of the form
  `Track <name> - edited <N> notes` / `Track <name> - edited <N> events`:
  - `<name>` is the affected track's name at record time, falling back to its 1-based
    position when unnamed; the label keeps the historical name even if the track is later
    renamed.
  - `N` counts the affected notes or automation events, computed once from the entry's
    change set, or from the operation's id payload where it carries one
    (`.moveNotes`, `.nudgeNotes`, `.resizeNotes`, …).
  - an operation touching more than one track drops the track prefix (`Edited N notes`).
- Track-management, time, tempo, and song-config operations use fixed phrases: "Add track",
  "Duplicate track", "Delete track", "Move track", "Rename track", "Set song end",
  "Change tempo", "Set loop", "Set time signature", "Move time signature",
  "Delete time signature", "Remove time", "Insert time", "Duplicate time", "Move range",
  "Range edit", "Edit song config".
- Extend `public protocol BankHistoryAction` with `var historyLabel: String { get }`;
  conformers capture their label — including their subject (voicegroup/slot) — when the
  action is constructed. A merged bank action reports its own `historyLabel`.
- The row answers *where, what kind, how many* — track, note-vs-event, count — never the
  delta values. Deltas are the document's business; the log's is discoverability.

### 4.3 Step projection

```swift
public struct HistoryStep: Sendable {
    public let label: String
    public let applied: Bool       // offset < undoIndex
    public let isCurrent: Bool     // offset == undoIndex - 1
    public let isSaved: Bool       // this step is the on-disk state
}
```

- `public func step(at offset: Int) -> HistoryStep?` — offset `0` is the oldest step;
  `nil` outside `0..<undoCount`. The log stays private; the UI never sees entries, changes,
  or actions. This is a projection, not an enumeration of the engine.

### 4.4 Change notification

- Add `public private(set) var revision: Int`, incremented exactly once per mutation that
  changes `entries` or `index`: record, merge (including cancelled-gesture removal), undo,
  redo, each jump iteration, eviction, stale-entry removal. `markSaved` does not bump (no
  list change); `sealMergeBoundary` does not bump.
- No per-entry callbacks and no insert/remove ranges. Consumers re-read the whole projection
  when `revision` changes; at the cap this is a ≤512-row rebuild at interaction cadence.
- One revision per logical mutation (not per internal store touch) keeps bulk operations
  from degenerating into per-row signals — the bridge coalesces per event-loop turn anyway,
  and mid-jump the panel may legitimately show intermediate cursor positions.

### 4.5 Jump

```swift
@discardableResult
public func jump(toIndex target: Int) async throws -> Int
```

- Clamp `target` to `0...entries.count`. While `index > target`, run `undo()`; while
  `index < target`, run `redo()`. Return the index actually reached.
- Every iteration is a full `undo()`/`redo()`: bank transition tokens, `applyDocument`
  remaps, and stale-entry healing apply per step, so a jump is exactly a batched sequence of
  the existing single-step operations — no snapshot/restore path, no second replay engine.
- Stop early (return current index) when a step returns `false` (transition guard refused).
- Non-stale errors abort the loop and propagate; the log is consistent at every instruction
  boundary because each step commits atomically. Stale-entry errors are consumed internally
  per step, as today.
- Refuses to start while a bank transition is in flight (same guard as `undo`/`redo`) and
  returns the current index.

### 4.6 Saved position

- `public var savedStepIndex: Int` — offset of the step whose `afterIdentity` equals
  `savedIdentity`, else `0` (base state, incl. "saved with no steps"). Linear scan is
  acceptable: called at revision-change cadence against a capped log.
- Drives the saved marker; after `markSaved` the marker sits on the then-current step and
  moves with the cursor's history, not with subsequent saves-on-undo (identity comparison
  decides, so re-saving after undo still lands on the matching step or base).

## 5. Session and bridge — `src/swift/app`

- `ApplicationSession`: add `@QtTracked public var undoHistoryOpen = false` and an
  `UndoHistoryPanel` presenter owned by the session.
- `UndoHistoryPanel` (new file under the shell/presentation area, one concept per file):
  - Rows ride a `QListModel` (`label`, `applied`, `isCurrent`, `isSaved`) — synchronous row
    updates keep list and cursor consistent within a frame; no second dispatcher.
  - Rebuild rows for the selected tab's document whenever its `history.revision` changes;
    hidden-tab history changes do not rebuild. Tab switches repopulate, matching how
    transport views follow the selected tab.
  - `jump(to:)` mirrors `requestUndoImpl` gating: require an open session, clear
    `canUndo`/`canRedo`, `publishLastSaveError("")`, run `session.document.history.jump`,
    route thrown errors to `publishLastSaveError`, then refresh document state. While a
    jump is in flight, further panel jumps are ignored (the cleared gates already provide
    this on the menu path; the panel checks the same flag).
  - Row activation maps offsets to targets: activating the row at offset `o` means "this
    step is applied afterwards", i.e. `jump(toIndex: o + 1)`. There is no base-state row;
    activating the oldest row rewinds as far back as the log goes.
- Command surface: window-scope command `view.undo_history` ("Undo History") in
  `KeybindingRegistry`, `ShellActionCatalog` View section, `ShellPresenter` dispatch
  (toggles `undoHistoryOpen`), and `ShellPresenter+ActionPolicy`
  (`session.songOpen`). Toggle only — the panel has no other commands.
- `edit.undo` / `edit.redo` paths are unchanged; their steps bump `revision`, so the panel
  tracks menu-driven undo/redo and direct edits live.

## 6. Window behavior — `ui/shell`

- Newest step at top; the list scrolls, it never pages lazily (capped log).
- Row text is exactly the entry label captured under §4.2 — the view composes nothing and
  formats nothing.
- Rows above the current position (undone, redoable) render dimmed; the current row carries
  a position marker; the saved row carries a saved marker. Both markers can sit on the same
  row.
- Pointer click on a row activates it; keyboard: Up/Down move selection, Enter activates,
  Esc closes the window. The panel never handles `Space` (window shortcut priority rule);
  persistent chrome activation stays pointer/Enter.
- Selection follows the cursor on external changes (undo/redo/menu) unless the user has
  moved it, in which case it clamps into range.
- Text contrast follows the standard palette pairing rule for dimmed rows.

## 7. Invariants and edge cases

- `index ∈ [0, entries.count]` holds after every operation, including eviction and any
  mid-jump interruption (per-step atomicity).
- Eviction only removes the oldest applied steps, only on append, and only down to
  `stepLimit`; it never fires during undo/redo/jump.
- Merging behavior is unchanged apart from labels following the newest operation.
- Labels are immutable snapshots: a row names the track and count as of its record time;
  later renames or edits never rewrite existing rows. A merged entry re-captures from the
  newest operation, updating the count of the single remaining row for that gesture.
- A stale bank entry dropping mid-jump shrinks `entries`; the jump loop re-clamps `target`
  each iteration and returns the reached index.
- Opening or creating a document yields a fresh `SongHistory`; the window clears with it.
- Multi-tab gating stays session-owned: pending bank transitions on any tab still clear
  `canUndo`/`canRedo` and the panel's jump gate reads the same state
  (`ApplicationSession.refreshDocumentState`).

## 8. Non-goals

- Persisting history across sessions or documents; disk spill or paging.
- Per-parameter or per-surface undoability policy.
- Localized labels; user preference for the step cap.
- Progress affordance for long jumps (in-memory replay is fast; revisit if bank-heavy jumps
  prove slow in practice).
- Nested or grouped step trees; applying the same window to the sample-studio history
  stack (`SampleStudioHistory` is a separate stack and stays internal to its surface).

## 9. Verification

- Core contracts (extend the edit-lane history checks): eviction preserves cursor, redo
  tail, and dirty state; `jump` across mixed document/bank entries, incl. early stop and
  stale-entry shrink mid-jump; label content — track-scoped note/event counts (`Track <name>
  - edited <N> notes/events`), unnamed-track fallback, multi-track fallback, capture-time
  name stability across a later rename, and count refresh on gesture merge — plus `revision`
  monotonicity and no-bump on `markSaved`; `savedStepIndex` after save, save-then-undo, and
  eviction.
- Commands: `deno task build:app`; `deno task checks --filter swiftcore`;
  `deno task checks:shell`; `deno task checks:bridge` (new tracked surface);
  `deno task checks:qml-aot` (new `src/ui` file); `deno task format --check`.
- No proof-ledger rows: this is new behavior with no retired native counterpart; no
  standalone ledger work.

## 10. Review notes (open questions before planning)

Items marked *bug* break the behavior described above as written; the rest are decisions
to settle.

1. *Bug: jump bypasses `DocumentSession.stepHistory`.* §5 calls
   `session.document.history.jump`, but menu undo/redo go through
   `DocumentSession.stepHistory`. That path loads the next voicegroup bank before crossing
   a `-G` change, drains bank results, publishes the change, and re-highlights duplicated
   time ranges. Proposal: `DocumentSession.jump(toIndex:)` loops `stepHistory`; the panel
   calls that, and `SongHistory.jump` is not needed.
2. *Bug: `savedStepIndex` uses `0` for two states.* §4.3 makes offset `0` the oldest step;
   §4.6 returns `0` for the base state. "Saved after the first edit" and "saved with no
   edits" both mark the oldest row. It also needs a value for "saved step evicted by the
   cap". Proposal: `Int?` (or a distinct base value), `nil` when no step matches.
3. *Bug: the opened state is unreachable.* Row `o` jumps to `o + 1` and there is no base
   row, so the oldest step can never be undone from the window. Proposal: a pinned
   "Opened" row below the oldest step that jumps to `0` and can carry the saved marker.
4. *Bug: a forward jump can overshoot when it drops a stale bank entry.* Redo removes a
   stale `entries[index]` without moving the cursor (`SongHistory.swift`, stale redo
   path), so every later step shifts down one place. Clamping `target` to the new count
   applies one extra step; `target` should drop by one per entry removed below it.
5. *Bug: bank steps share their identity with the step before them.* A bank entry records
   `currentIdentity` at record time, so a document step and the bank steps after it can
   all match `savedIdentity`. Decide which row carries the saved marker (e.g. the last
   applied match, or bank rows never carry it).
6. Window shortcuts while the window has focus. Shell commands use `Qt.WindowShortcut`
   (`ShellContent.qml`). If this is a separate `DialogWindow`, Cmd+Z / Cmd+Shift+Z do
   nothing while it is focused. Either host it in the shell window or give it its own
   undo/redo shortcuts, as `SampleStudioDialog.qml` does.
7. Jumps during a live gesture or prompt. A note drag, the velocity prompt, or the pitch
   bend popup holds a document snapshot; a jump underneath leaves that snapshot stale.
   Menu undo has the same exposure, but the window makes it easier to hit. Simplest rule:
   disable jumps while any of them is open.
8. Tab switch mid-jump. The panel follows the selected tab, but an in-flight jump belongs
   to the document it started on. Pin the jump to that session so the gate and the
   refresh afterwards do not act on the new tab.
9. Rebuild cost on long jumps. Every jump iteration bumps `revision` and awaits, so the
   bridge may flush between steps, and `QListModel` row updates are synchronous: a
   300-step jump could rebuild 512 rows 300 times. Undo/redo only flip `applied`/
   `isCurrent` on the rows crossed, a record appends one row, and eviction removes rows
   from the bottom; patching those rows avoids the cost. Otherwise measure it first.
10. Redo tail loss is easier to hit from the window. Jump back 40 steps, nudge a note,
    and 40 steps disappear. That matches standard undo, but a cheap signal helps (status
    text such as "Discarded 40 redo steps" when a record drops a long tail).
11. Eviction and session-side per-step state. `DocumentSession.duplicatedSelections`
    keys duplicated-range highlights by history identity and is never pruned. When the cap
    evicts steps, their entries should go too. That needs eviction to report the removed
    identities, or the ranges to live on the history entries themselves.
12. Additional verification: a jump across a `-G` change through the session path; the
    saved marker after the saved step is evicted; first-edit vs no-edit save marker; a
    forward jump that drops a stale entry lands on the clicked step; Cmd+Z while the
    window has focus.
