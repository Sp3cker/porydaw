# Keyboard note length editing

Status: production, checks, and documentation implemented. All five phase thermo-nuclear reviews passed after corrections. Formatting and all 76 non-windowing harnesses pass; the full 89-harness gate remains blocked on an unlocked macOS desktop.

Final verification note: targeted roll, shared routing, grid, event-edit, document-history, keymap, and Edit-menu checks passed. Native Cocoa menu presentation, exactly-once dispatch, and text-input checks also passed before the desktop locked. The final native selection-suite retry failed foreground-focus setup; `ioreg` confirmed `IOConsoleLocked = Yes` and `CGSSessionScreenIsLocked = Yes`. No assertions were weakened. Unlock the desktop, then run `deno task verify` to complete the full gate.

## 1. Goal and user contract

Add two selected-note commands:

- **Lengthen Note** — `Shift+Right`
- **Shorten Note** — `Shift+Left`

Both commands appear in the application's top-level **Edit** menu. They do not appear in the piano-roll note context menu, the time-selection context menu, the ruler context menu, or any drawer context menu.

Each invocation moves the selected notes' right edges by one boundary of the current editing grid. Grid selection and feel are read when the command executes. Zoom-dependent guide visibility does not affect the edit increment.

Success requires:

1. The top-level Edit menu and keyboard route invoke the same semantic operation exactly once.
2. Selected notes retain their starts, pitches, velocities, channels, tracks, `NoteId`s, and selection membership.
3. Musical grids respect the active time-signature segment. Clock mode uses `ticksPerClock`.
4. Repeated key presses and key auto-repeat form one undo entry. One undo restores the state before the sequence; a net-zero sequence leaves no entry.
5. Focused text/value editors, popups, advertised local arrow controls, the event list, and active pointer gestures preserve their established ownership.

## 2. Non-goals

- No note or time-selection context-menu entries.
- No left-edge resize command.
- No time-selection stretch operation.
- No per-note grid anchoring for mixed selections.
- No new grid state, grid arithmetic helper, focus memory, application-wide event filter, command bus, or shortcut system.
- No change to mouse resize behavior, new-note duration, visual grid detail, export quantization, or audition behavior.

## 3. Evidence and current architecture

### 3.1 Reserved behavior and key convention

- `docs/selection-keyboard-routing-plan.md:50-66,83-95` reserves `Shift+Left/Right` for selected-note shortening/lengthening and requires the later feature to decide increment, minimum duration, anchoring, mixed-selection behavior, and checks.
- `docs/grid-system-plan.md:9-32,68-75,116` defines the selected editing grid independently from visual detail and identifies that grid as the future note-length increment.
- `src/ui/keymap.cpp:107-118` assigns vertical arrows to pitch and horizontal arrows to time. `Shift+Up/Down` already transpose by octaves; `Shift+Left/Right` are available for time-domain length editing.

### 3.2 Keyboard routing seam

`SongView::handleEditKey` in `src/ui/songview/editkeyrouting.cpp:153-314` is the shared timeline keyboard seam. It resolves a keymap binding, applies pointer-gesture ownership, resolves the eligible selection target, and dispatches a semantic operation. The file explicitly routes commands rather than implementing edits.

Input precedence is:

1. Focused text/value entry, popup, or deliberately keyboard-operated control.
2. Active pointer gesture.
3. Shared `SongView::handleEditKey` policy.
4. Eligible semantic operation or terminal no-op.

`TimelineQuickView::dispatchSongKey` in `src/ui/songview/quick/timelinequickview_keyrouting.cpp:21-36` identifies timeline versus event-list origin before entering the shared policy. `TimelineInputItem::keyPressEvent` in `src/ui/songview/quick/timelineinputitem.cpp:286-297` gives a band its restricted local handling first.

### 3.3 Edit-menu ownership

`MainWindow::buildUi` in `src/mainwindow.cpp:249-324` constructs the top-level Edit menu. Existing song-scoped actions are retained as `MainWindow` members, connected to the selected tab's `SongView`, and enabled from `MainWindow::updateChrome` (`src/mainwindow.cpp:961-987`).

Lengthen Note and Shorten Note are editor commands rather than new context-menu tools. Their menu actions are presentation/invocation adapters over the shared semantic operation, not a second implementation:

- `SongView::handleEditKey` remains the only active shortcut owner for `Shift+Left/Right`, preserving Quick local-input precedence.
- The Edit-menu `QAction`s invoke the same public, guarded `SongView::resizeSelectedNotes(bool)` entry when clicked.
- The actions remain shortcut-free: do not call `QAction::setShortcut(s)` and do not pass them to `keymap::Registry::attach`. This prevents Cocoa from installing `NSMenuItem` key equivalents that can preempt `QQuickItem` and QWidget text selection.
- The actions have bare titles in a native menu bar. In a non-native/widget menu bar, append a tab-separated native binding label and refresh it from `keymap::Registry::bindingsChanged`. Never put the tab suffix into a native macOS menu item: Cocoa renders it as title text because the action has no shortcut. The Keyboard Shortcuts dialog remains the binding presentation on native macOS.

Add `QAction *m_lengthenNoteAction` and `QAction *m_shortenNoteAction` to `MainWindow`. Put them after Copy and before track/time structural operations. Enable them only when a ready selected tab has selected notes. There is no existing selection-change signal reaching `MainWindow`: add `SongView::noteSelectionChanged(bool)`, emit it from the existing `coordinateSelectionChange` note-selection branch, and retain a selected-view connection in `MainWindow` that calls `updateChrome()` and is replaced when the selected tab changes. Do not poll or cache a parallel selection.

### 3.4 Grid module

`songview::Grid` in `src/ui/songview/grid.h:42-133` is the sole grid arithmetic module. `SongView` owns it and `PianoRoll` reads it.

Use existing operations:

- `Grid::nextEditingTick(tick, limit, fine)` finds the first editing boundary strictly after a tick and honors time-signature boundaries (`grid.h:107-109`, `grid.cpp:281-300`).
- The established strictly-before operation is `snapTickDown(double(tick) - 1.0)`, already used by note and range nudging (`pianoroll_commands.cpp:179-206`, `rangeedit.cpp:594-629`).
- Musical grids restart their lattice at signature segments (`grid.cpp:248-265,291-295`).
- Clock selection uses the absolute clock lattice and `ticksPerClock` (`grid.cpp:239-245,287-305`).

No new `Grid` interface is needed.

### 3.5 Existing note mutation and history

`PianoRoll::nudgeSelectedNotes` in `src/ui/songview/pianoroll_commands.cpp:179-206` is the semantic-operation model: resolve selected notes, derive one grid delta, enter `DocumentSwapHintScope`, invoke one document command with `mergeable=true`, keep the result visible, and request the existing Quick mutation refresh.

`SongDocument::resizeNotes` in `src/core/songdocument.cpp:1207-1243` already rewrites note-offs, preserves note-ons and identities, resolves overlaps, and enforces a one-tick minimum. Its current generic `SongEditCommand` never merges.

`MoveNotesCommand` in `src/core/songdocument.cpp:164-260` is the mergeable-history model. It merges only when the next command's inputs match the preceding output state, rebuilds operations from the original state, and marks a net-zero command obsolete.

Mouse resize commits one uniform duration delta for the selected notes through `PianoRoll::commitResizeDrag` in `src/ui/songview/pianoroll_gestures_active.cpp:274-284`. Its call must continue using non-mergeable behavior.

## 4. Interaction decisions

| Question | Decision |
|---|---|
| Direction | `Shift+Right` lengthens; `Shift+Left` shortens. |
| Edited edge | Right edge only; note start stays fixed. |
| Grid anchor | Maximum end tick among the selected notes. |
| Mixed selection | Compute one delta from that anchor and apply it uniformly to every selected note. |
| Lengthen step | `Grid::nextEditingTick(maxEnd, UINT64_MAX)`. |
| Shorten step | `Grid::snapTickDown(double(maxEnd) - 1.0)`. |
| Minimum duration | One document tick. Clamp the shared shortening delta to `1 - min(selected duration)` before calling the document. A selection containing an unterminated note is a consumed no-op because that note has no editable right edge. |
| Off-grid end | Lengthen reaches the next boundary; shorten reaches the previous boundary. |
| Signature change | A step first lands on the signature boundary; the following step uses the new segment lattice. |
| Clock selection | One `ticksPerClock` boundary on the absolute clock lattice. |
| Upper bound | No arbitrary cap. Checked arithmetic rejects the whole command — a consumed no-op — when a lengthen step would carry any selected note's duration outside the `uint32_t` duration field. |
| Selection | Preserve `NoteId`s and selection membership. |
| Undo | Keyboard calls are mergeable; mouse resize remains non-mergeable. |
| Auto-repeat | Allowed and absorbed into the merged undo command. |
| Empty note selection | Recognized command is a terminal no-op in timeline origin. |
| Active time selection | Terminal no-op; do not resize hidden/unselected notes or stretch the range. `EditorSelectionModel` normally makes note and time selections mutually exclusive; if a corrupted/transitional state presents both, the time selection wins and the command does nothing. |
| Unterminated selected note | Terminal no-op for the whole selection; preserve selection and history. Do not reinterpret `DocNote::duration == 0` as a one-tick or positive shortening clamp. |
| Terminated zero-duration note | Shortening is a consumed no-op: the `1 - min(selected duration)` clamp collapses the shared delta to zero before the document call. Lengthening proceeds normally. |
| Event-list origin | Decline; preserve table-local behavior. |
| Active pointer gesture | Consume without mutation. |
| Text/local control | Preserve local Shift+Arrow behavior. |
| Audition | None. |
| Context menus | No entries anywhere. |
| Top-level menu | Both commands appear in Edit and invoke the same semantic operation as the keyboard route. |

The shortening clamp is required for exact merged replay. If the document independently floors different notes, replaying the accumulated delta from the original state can differ from sequential presses. Clamping once against the shortest selected duration makes the uniform delta valid for every note.

## 5. Phased implementation

### Phase 1 — Deepen the document resize command

Files:

- `src/core/songdocument.h`
- `src/core/songdocument.cpp`

Steps:

1. Extract the operation-building body of `SongDocument::resizeNotes` into a private const `buildResizeNotesOps(notes, dDuration)` helper beside `buildMoveNotesOps`.
2. Add `ResizeNotesCommand` beside `MoveNotesCommand`. Store the original notes, accumulated duration delta, mergeability flag, built operations, initial-redo state, and mutation remap.
3. Give mergeable resize commands a unique command ID. Non-mergeable commands return `-1`.
4. Match the next command against the outputs of this command's own edited notes only, using the `MoveNotesCommand::movesMyOutputs` shape: same `NoteId`, engine track, unchanged note fields, and duration equal to the original duration plus the accumulated clamped delta. Neighbor notes trimmed by overlap resolution are not part of this predicate.
5. On merge, revert both applied operation sets, accumulate the delta, rebuild from the original notes, apply the replacement operations, and rebuild the track map. `mergeWith` must not publish a mutation.
6. Mark the command obsolete when accumulated `dDuration == 0`.
7. Extend `SongDocument::resizeNotes(notes, dDuration, bool mergeable = false)`. Keep the existing changes/no-op guard. After pushing the command, publish exactly once from this wrapper, mirroring `SongDocument::moveNotes`; initial `redo()` and `mergeWith()` do not publish.
8. Leave `PianoRoll::commitResizeDrag` unchanged so mouse resize continues through the default `mergeable=false` path.

Acceptance:

- Non-mergeable resize retains existing byte-for-byte behavior.
- Consecutive compatible keyboard resizes merge.
- Incompatible note state or selection does not merge.
- Undo/redo reproduces exact note durations and identities.
- Net-zero merged sequences do not occupy history.

### Phase 2 — Add one guarded semantic note-length operation

Files:

- `src/ui/songview.h`
- `src/ui/songview/editkeyrouting.cpp`
- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll_commands.cpp`

Steps:

1. Add `PianoRoll::resizeSelectedNotes(bool longer)` beside `nudgeSelectedNotes`.
2. Resolve notes with the existing `resolveSelection()` path and return when empty.
3. Reject the entire operation when any resolved `DocNote` is unterminated. Its stored duration is zero and it has no editable right edge; applying the normal shortening clamp would be incorrect.
4. Compute `maxEnd` and `minDuration` for terminated notes in one pass without allocating another collection. Use checked/saturating addition for end ticks.
5. Derive the adjacent editing boundary only through `Grid`.
6. Compute the uniform signed duration delta and clamp shortening against the shortest selected note.
7. Return on zero delta.
8. Use `DocumentSwapHintScope`, then call `SongDocument::resizeNotes(notes, dDuration, true)`.
9. Recompute the selected span, call `ensureRangeVisible`, and request `cNoteMutationDirty`.
10. Add public `SongView::resizeSelectedNotes(bool longer)` as the semantic seam shared by keys and menu actions. It returns without mutation when the document/roll is unavailable, a timeline pointer gesture is active, or a time selection is active; otherwise it forwards to `PianoRoll`.

Acceptance:

- Aligned, off-grid, musical, Clock, and signature-boundary steps follow the live grid.
- All selected terminated notes receive the same delta.
- A selection containing an unterminated note remains byte-identical.
- No note crosses the one-tick floor.
- Starts, pitches, velocities, tracks, identities, and selection remain stable.

### Phase 3 — Bind and route Shift+Left/Right

Files:

- `src/ui/keymap.cpp`
- `src/ui/songview/editkeyrouting.cpp`

Steps:

1. Register `roll.lengthen_note` with `Shift+Right` and `roll.shorten_note` with `Shift+Left`, both in `keymap::Context::Timeline` and the Piano Roll category.
2. Add `EditCommand::LengthenNote` and `EditCommand::ShortenNote`.
3. Add both IDs to `kSharedBindings`.
4. Resolve both commands to `SelectionTarget::Notes` whenever origin is Timeline, regardless of `timeSelectionActive`. This makes an empty/time selection a consumed no-op instead of falling through `SelectionTarget::None`.
5. In the Notes dispatch arm, call the guarded `SongView::resizeSelectedNotes(command == EditCommand::LengthenNote)` and return consumed.
6. Preserve event-list decline, active-gesture consumed no-op behavior, local input precedence, and release-tail behavior.

Acceptance:

- Each keystroke executes once from the roll, ruler, track headers, velocity lane, automation lane, voice-change lane, and incidental drawer chrome.
- Event-list and protected local controls retain their keys.
- No focus memory or parallel dispatcher is introduced.

### Phase 4 — Add Edit-menu actions, not context-menu items

Files:

- `src/mainwindow.h`
- `src/mainwindow.cpp`
- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`

Steps:

1. Add retained `m_lengthenNoteAction` and `m_shortenNoteAction` members plus a `QMetaObject::Connection` for the currently selected view's note-selection notification.
2. Create `tr("&Lengthen Note")` and `tr("Sho&rten Note")` actions in the top-level Edit menu after Copy. The distinct mnemonics avoid the existing `&Solo Selected Tracks` mnemonic.
3. Connect menu activation to the selected tab's guarded `SongView::resizeSelectedNotes(bool)` entry. Do not duplicate grid or document logic in `MainWindow`.
4. Do not register active shortcuts on these actions. When `menuBar()->isNativeMenuBar()` is false, refresh their tab-separated native shortcut labels from `keymap::Registry::bindings(id)` initially and on `bindingsChanged`. When it is true, retain bare action titles; configurable bindings remain visible in Keyboard Shortcuts.
5. Add `SongView::noteSelectionChanged(bool)`, emitted only when `coordinateSelectionChange` reports a changed note selection.
6. In `MainWindow::onSelectedTabChanged`, disconnect the old selected-view connection, connect the new selected view's signal to `updateChrome()`, and then recompute chrome. `updateChrome` enables both actions only when the selected tab is ready and its note selection is nonempty.
7. Keep the guarded semantic entry authoritative even when an action was enabled just before selection or gesture state changed.
8. Do not add rows to `PianoRoll::showNoteMenu`, `SongView::buildTimeSelectionItems`, `TimeRuler::showRulerMenu`, event-list menus, or drawer menu builders.

Acceptance:

- Edit contains both actions. Widget menus show current configurable shortcut presentation; the native macOS menu shows clean bare titles without a literal tab suffix.
- Clicking either action invokes the same guarded semantic operation as its key.
- Menu invocation operates on the selected tab only.
- Selection and tab changes immediately update enablement.
- Rebinding updates shared routing and widget-menu presentation; native macOS continues to present the binding in Keyboard Shortcuts.
- Keyboard input produces exactly one command; neither menu action is an active shortcut owner.
- Focused QWidget or Quick text input retains Shift+Arrow selection.
- Note, range, ruler, event-list, and drawer context menus contain no resize rows.

### Phase 5 — Add permanent checks and update specifications

Files:

- `src/checks/editcheck/tst_songdocument.h`
- `src/checks/editcheck/tst_songdocument_songnotes.cpp`
- `src/checks/rollcheck/tst_pianoroll.h`
- `src/checks/rollcheck/keyboard.cpp`
- `src/checks/selectionkey/tst_selectionkeycore.h`
- `src/checks/selectionkey/corearrows.cpp`
- `src/checks/selectionkey/gesturecheck.h`
- `src/checks/selectionkey/gesturecommands.cpp`
- `src/checks/selectionkey/tst_localinputtier.h`
- `src/checks/selectionkey/localinputtier_eventlist.cpp`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`
- `src/checks/keyboard/tst_keymapcheck.h`
- `src/checks/keyboard/keymapregistry.cpp`
- `docs/selection-keyboard-routing-plan.md`
- `docsrc/manual/shortcuts.md`
- `docsrc/manual/piano-roll.md`
- `CHANGELOG.md`

Implement the checks in section 6. Update the routing plan's future-feature and deferred-decision text to the settled contract. Document Shift+Left/Right in the shortcut table and piano-roll editing instructions. Record the user-visible feature in the changelog.

Acceptance:

- Every observable contract below is pinned at the narrowest existing harness seam.
- No test asserts private implementation, source text, or incidental pixel geometry.
- Existing `rollcheck` pointer-resize slots in `resize.cpp`, `selectionkey-window`'s `resizeDragProtectsSelectedNotes`, and `view-buckets-grid` continue to pass unchanged.

## 6. Required permanent checks

### 6.1 Document history — `editcheck`

Add `resizeNotesMergeableHistory` in `src/checks/editcheck/tst_songdocument_songnotes.cpp`.

Set up two identified notes, then assert:

1. Two compatible `resizeNotes(..., true)` calls create one history entry.
2. Both notes have the expected uniform final duration delta.
3. One undo restores exact original SMF bytes and the same `NoteId` mapping.
4. Redo restores the final bytes and identities.
5. An equal positive/negative pair leaves the history count unchanged.
6. A later call whose inputs do not match the preceding output state does not merge.
7. A non-mergeable resize remains a separate entry, protecting mouse-resize behavior.

This check defends document/history semantics independently of keyboard routing.

### 6.2 Grid-driven keyboard behavior — `rollcheck`

Add `keyboardResize` in `src/checks/rollcheck/keyboard.cpp` and declare it in `src/checks/rollcheck/tst_pianoroll.h`. The fixture starts at musical 1/16 straight (`rollcheck/harness.cpp:34-35`).

Scenarios:

1. **Aligned end:** `Shift+Right` advances one cell; `Shift+Left` returns it.
2. **Off-grid end:** lengthen reaches the next boundary and shorten reaches the previous boundary rather than adding a fixed raw cell.
3. **One-tick floor:** shortening a one-tick note leaves SMF bytes and history count unchanged.
4. **Mixed selection:** notes with different durations/end alignments receive the same delta; the shortest note limits shortening.
5. **Identity and selection:** starts and all non-duration fields remain unchanged; selected `NoteId`s remain selected.
6. **Live grid change:** call `SongView::setGridSelection` with a different musical division, then prove the next resize uses it. Keyboard narrow/widen routing is covered separately by the grid suites.
7. **Clock terminal:** call `view.setGridSelection(GridSelection::clock())`, following `rollcheck/pencil.cpp:445-447`, and prove one `ticksPerClock` boundary.
8. **Signature boundary:** seed `doc.setTimeSig(signatureTick, numerator, denomPow2)` following `rollcheck/time_signature_prompt.cpp:56-58`, process the timeline update, end a note one tick before that boundary, and prove the first press lands on it while the next uses the new segment lattice.
9. **Time-selection terminal no-op:** stage `EditorSelectionModel::setTimeSelection`; its invariant clears note selection. The key is accepted while document, history, and time selection remain unchanged. Also assert the model cannot retain simultaneous nonempty note and time selections.
10. **Unterminated note:** stage an unterminated selected note and prove the command is consumed with byte-identical document/history state.

Close by undoing to byte-identical fixture state.

### 6.3 Keyboard merge behavior — `rollcheck`

Add and declare `keyboardResizeUndoMerge`.

Assert:

1. Five Shift+Right presses add one undo entry.
2. At least one press is delivered through `checks::rollcheck::sendKeyStroke(..., autoRepeat=true)`, which reaches `checks::events::sendKey` and constructs a production `QKeyEvent` carrying the auto-repeat flag.
3. One undo restores the pre-sequence document.
4. Redo restores the final duration.
5. A lengthen/shorten net-zero sequence creates no lasting entry.
6. A selection change separates undo gestures rather than merging across targets.

### 6.4 Shared routing — `selectionkey-core`

Add and declare `arrowsResizeSelectedNotesAcrossBands_data()` and `arrowsResizeSelectedNotesAcrossBands()` beside `arrowsMoveSelectedNotesAcrossBands`. Reuse the existing five-band probe table, but generate only two direction rows per band: Shift+Left and Shift+Right. Do not add vertical-arrow resize rows.

Prove for each row:

- The selected note length changes exactly once.
- No other note changes.
- The key is accepted by the shared policy.
- The result is independent of incidental drawer focus.

Use semantic document assertions, not focus-state assertions. No new `selectionkey-window` row is required: Timeline-context editor bindings continue through the existing `SongView` seam, and the window tier's grip/scrollbar ownership remains covered by its current plain-arrow tests.

### 6.5 Active gestures — `selectionkey-gesture`

There is no single shared-command gesture matrix. Extend the existing staged ownership slots instead:

- In `velocityStemDragGuardsEdits`, deliver Shift+Left or Shift+Right during the active selected-stem drag and prove consumed/no mutation.
- In `rollNoteMoveGridChangesStayLive`, add one resize command beside the existing blocked Delete/Triplet deliveries while the note move is active.
- In `automationPanGuardsSharedCommands`, deliver one resize command during the range sweep and one during the automation pan.
- In `scrollbarThumbGuardsSharedCommands`, deliver one resize command in each existing root/drawer thumb data row.

These slots collectively cover note resize/move, time selection, automation, drawer/root scrollbar ownership without inventing duplicate staging. Preserve the captured gesture and selection in every case.

### 6.6 Event-list and protected local input — `selectionkey-local-input`

Declare new slots in `src/checks/selectionkey/tst_localinputtier.h` and implement them in the corresponding existing source:

1. Extend `eventListKeepsRowLocalKeys` so Shift+Left/Right leave notes unchanged and plain Left/Right still navigate columns.
2. Extend one real QML text-input slot and `songSearchLineEditOwnsKeys` so Shift+Arrow changes text selection and produces no song mutation.
3. Use the existing scrollbar ownership check rather than duplicating it here.

### 6.7 Edit-menu integration — `mainwindow-routing-input`

Extend `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`:

1. Locate the Edit menu and both actions.
2. Verify labels/mnemonics, selected-tab ownership, ready/no-song enablement, and immediate selected-note enablement.
3. Trigger each menu action directly and assert the selected note changes by the live grid step.
4. Switch tabs and prove activation affects only the newly selected tab.
5. Under a scoped `keymap::Registry::OverrideSnapshot` restore guard, change each binding and prove the widget-menu label formatter updates. On a native menu bar, assert the action keeps its bare title without a literal tab or binding suffix. Routing under a rebound key stays in `selectionkey-core`.
6. Deliver Shift+Right through the production input surface and use history-count/document assertions to prove exactly one resize occurs.
7. Focus protected text input, spy both menu actions, and prove Shift+Right changes text selection, both `triggered` counts remain zero, and notes remain unchanged.

No native routing check is required because the menu actions have no registered key equivalents.

### 6.8 Keymap defaults — `keymapcheck`

Extend `KeymapCheckTest::shippedTable` or add a declared slot in `src/checks/keyboard/tst_keymapcheck.h`, implemented in `keymapregistry.cpp`, to assert:

- `roll.lengthen_note` defaults to Shift+Right.
- `roll.shorten_note` defaults to Shift+Left.
- Both are Timeline/Piano Roll commands.
- The existing all-default conflict check remains clean.

Keep keymap override isolation in this suite's existing `init()`/`cleanup()`. Menu presentation rebinding belongs to `mainwindow-routing-input`, whose new check must take and restore an explicit `Registry::OverrideSnapshot`.

### 6.9 Context-menu exclusion

This is an explicit manual implementation-review gate, not a brittle source-text or row-count test. Inspect `PianoRoll::showNoteMenu`, `SongView::buildTimeSelectionItems`, `TimeRuler::showRulerMenu`, event-list menus, and drawer menu builders in the final diff and confirm no resize rows were added. Existing note/range/ruler behavioral checks must remain unchanged.

## 7. Smoke verification

1. Build and launch the application with a song containing notes.
2. Select one note. Press Shift+Right twice and Shift+Left twice; confirm one live-grid boundary per press and exact return.
3. Hold Shift+Right for auto-repeat, then use one Undo; confirm the original duration returns.
4. Change grid fineness and repeat; confirm the increment changes immediately.
5. Select Clock and confirm one-clock increments.
6. Resize across a time-signature change; confirm boundary landing and the next segment's spacing.
7. Select differently sized notes; shorten until the shortest reaches one tick and confirm all notes stop together.
8. Invoke Lengthen Note and Shorten Note from the top-level Edit menu; confirm they match the keyboard behavior. On macOS, confirm the native menu uses bare titles with no literal tab or appended binding text; the binding remains visible in Keyboard Shortcuts.
9. Confirm those commands are absent from note, time-selection, ruler, event-list, and drawer context menus.
10. Focus text/value input and confirm Shift+Arrow remains local.
11. Focus the event list and confirm no note resize.
12. Begin a pointer gesture and confirm Shift+Arrow is consumed without mutation.
13. Mouse-resize a note and confirm one independent undo entry.

## 8. Verification commands

Run focused suites as their phases land:

```bash
deno task verify --filter editcheck --verbose
deno task verify --filter rollcheck --verbose
deno task verify --filter selectionkey-core --verbose
deno task verify --filter selectionkey-gesture --verbose
deno task verify --filter selectionkey-local-input --verbose
deno task verify --filter mainwindow-routing-input --verbose
deno task verify --filter keymapcheck --verbose
```

On macOS, prove the Edit-menu integration against the native Cocoa menu bar, where both actions must keep their bare titles with no literal tab or binding suffix:

```bash
deno task verify --filter mainwindow-routing-input --verbose --qt -platform cocoa
```

`--qt` is terminal: everything after it is forwarded verbatim to the Qt test binary, and the filter must select exactly one qt-test harness.

Run named adjacent regressions:

```bash
deno task verify --filter selectionkey-window --verbose
deno task verify --filter view-buckets-grid --verbose
deno task verify --filter eventviews-edits --verbose
```

Run formatting and the full gate once:

```bash
deno task format --check
deno task verify
```

Commands must run with a timeout below 180 seconds. Native human-input checks can fail when the desktop steals activation; do not weaken assertions or repeatedly stress them. Re-run a setup/focus failure once with the desktop idle, then distinguish environment failure from a semantic assertion failure.

## 9. Risks and resolved tradeoffs

1. **Duplicate shortcut ownership and native presentation:** Cocoa native menus can intercept a `QAction` key equivalent before Quick or QWidget text input, while a tab suffix on a shortcut-free native action renders as literal title text. The Edit-menu actions are deliberately shortcut-free display adapters; native menus use bare titles, widget menus may append the binding label, and `SongView` is the sole active key owner.
2. **Merged shortening replay:** document-level per-note floors can make accumulated replay differ from sequential presses. Clamp the uniform UI delta against the shortest selected terminated note before mutation.
3. **Unterminated notes:** `DocNote::duration == 0`, so normal clamp arithmetic is invalid and the note has no defined editable right edge. Any selected unterminated note makes the command a consumed no-op.
4. **Signature boundaries:** raw `snapTicksAt` arithmetic would skip boundary semantics. Use `nextEditingTick` and `snapTickDown` only.
5. **Selection-driven menu enablement:** no signal currently reaches `MainWindow`. Add the narrow `SongView::noteSelectionChanged(bool)` signal and a replaceable selected-view connection; do not poll or cache selection.
6. **Menu bypass of routing guards:** direct menu activation must enter guarded `SongView::resizeSelectedNotes(bool)`, not call `PianoRoll` directly.
7. **Mutation publication:** the merge command must not publish from initial `redo()` or `mergeWith`; the public document wrapper publishes exactly once per invocation after `pushEdit`.
8. **Large tick values:** calculate note ends and deltas with checked/saturating unsigned arithmetic before converting to `int64_t`; do not allow `tick + duration` or signed conversion overflow. A lengthen step outside `uint32_t` duration representability is rejected as a no-op — there is no arbitrary cap.

## 10. Independent audit record

Three independent reviewers audited the first draft:

- Qt/C++ architecture reviewer: **FAIL**, corrected. It found the missing selection-change signal, missing guarded `SongView` menu entry, ambiguous mutation publication, incomplete merge predicate, time-selection consume path, and native-menu presentation issue.
- GUI behavior reviewer: **FAIL**, corrected. It found Cocoa shortcut interception risk, stale menu enablement, unterminated-note clamp corruption, and missing menu mnemonics.
- Checks reviewer: **FAIL**, corrected. It found omitted slot headers, underspecified fixture staging and auto-repeat delivery, a nonexistent generic gesture matrix, ambiguous keymap rebind ownership, and overly broad/unrelated verification filters.

All three reviewers re-audited the corrected plan. The GUI behavior and checks axes passed without further findings. The Qt/C++ axis found one native-menu presentation issue; that correction is incorporated above. All actionable findings are now incorporated. Implementation review must re-check:

- Edit-menu actions remain presentation-only and never become shortcut owners.
- Selection changes immediately update menu enablement.
- Both keyboard and menu activation enter the same guarded semantic operation.
- `ResizeNotesCommand` publishes once per call and merges only its own edited-note outputs.
- Grid stepping is correct at off-grid ends, signature boundaries, Clock mode, minimum duration, unterminated notes, and integer limits.
- Required checks cover document semantics, keyboard behavior, routing tiers, menu integration, and regressions without testing implementation details.
- No context-menu work is present.
