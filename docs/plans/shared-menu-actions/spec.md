# Shared menu actions and fixed shortcuts — specification

## Goal and authority

Unify application/editor command activation through canonical QActions, remove user shortcut remapping and Keyboard settings, and make ruler context commands use ordinary selection/edit-cursor state. This document records the user-approved behavior plus controller-resolved engineering decisions. It is a specification for future implementation, not a claim that the implementation or its checks have run.

The user delegated remaining engineering choices to the controller and required independent `plan`-agent challenges. The final review dispositions live in `plan.md`. Do not re-open settled product choices or import unrelated features from another plan.

## Vocabulary

- **Command:** an editing/application intention, independent of the key or menu row used to invoke it.
- **Canonical action:** the one live QAction used by all equivalent presentations of a command in its owning editor/window. An inactive tab must not register a competing window shortcut.
- **Window scope:** a shortcut available across the owning application window, subject to protected local input. It is not an operating-system-global hotkey.
- **Editor-routed scope (`Scope::EditorRouted`, called Editor scope below):** the existing editor key route invokes the action after local input arbitration. It is not a Qt shortcut installed on an editor widget. Incidental chrome focus does not change the selected target.
- **Target:** objects or time scope selected by the command's semantic policy, not the widget that happened to deliver the key.
- **Edit cursor:** stationary insertion/paste position, distinct from the moving playback head.
- **Time selection:** the existing half-open `[startTick, endTick)` interval plus track scope or lane identities and tempo participation.
- **Protected input:** text/IME, modal/popup interaction, deliberate local keyboard navigation, or an active gesture that owns the input under the existing precedence contract.

## Settled product behavior

1. Bindings are fixed platform-aware defaults. No user override reads/writes, remapping UI, reset controls, hidden rebinding path, or replacement shortcut browser. Old `keymap/` settings do not affect behavior; do not clear unrelated settings.
2. Keyboard, menu bar, and equivalent context/toolbar presentations invoke the same QAction. Labels, displayed bindings, enabled state and checked state derive from that action, not independently copied command metadata.
3. Keep unrelated existing File, View, Tools, and Help entries. Put newly exposed/consolidated commands under Edit using the menu inventory below. No Ableton documentation research or menu-layout imitation is part of implementation.
4. A/V/P drawer toggles and Space playback are window-scoped. Existing window commands keep their scope unless the inventory explicitly says otherwise. Editor commands have explicit editor scope; no `Both` delivery mode or second execution owner.
5. Preserve selection-based note/automation/time targeting across incidental drawer/chrome focus. Text, popup, event-list navigation, deliberate keyboard controls, audition surfaces, and gestures retain their documented local precedence. No new generic command bus, global focus framework, synthetic key forwarding, or remembered-last-focused-band state.
6. Automation selection remains lane identities plus the selected interval, including tempo when selected. No arbitrary/disconnected node-ID selection feature. Selecting a track-wide time interval continues to include its covered note and automation content.
7. Preserve current musical operations, scope boundaries, clipboard formats, undo granularity, scale-fold behavior, note audition, and repeat behavior unless a change is explicitly stated here. In particular, Duplicate Time does not become note duplication or contextual Duplicate Selection.
8. Modifier-hover/status-bar hints are deferred. Do not add infrastructure for them or change drag semantics to match illustrative hint wording.

## Ruler right-click and insertion

### Target establishment

The ruler has two terminal paths, evaluated on completed right-click:

1. **Selection path:** take the exact hit signature tick, or otherwise the raw unsnapped background coordinate, from the right press. If it lies in the active half-open `[startTick, endTick)` interval, open the selection menu and finish. This path never snaps, commits a cursor, or seeks.
2. **Cursor path:** reached only when the selection path did not apply. Clear the time selection, commit the exact chip tick or grid-snapped background tick, seek through the existing handoff, then open the cursor menu. Snapping cannot change the already-decided menu kind.

Capture the raw coordinate/exact chip identity in right-press gesture state, not the left-drag snapped anchor. Replace `TimeRuler::showRulerMenu(uint64_t clickTick, const QPointF &scenePos)` with `showRulerMenu(const QPointF &scenePos)`: a caller supplies presentation position, never a pre-snapped target. Discard right-press target state on release/cancellation; no clicked target survives menu opening. A nudged chip label still uses its exact event tick. Cancellation before release does not change selection/cursor or seek.

| Ruler click | Selection and cursor transition | Menu intent |
| --- | --- | --- |
| Inside an active time interval | Preserve time selection, stored track/lane scope, and edit cursor; do not seek | Selection-oriented commands |
| Outside an active time interval | Clear the time selection, commit the clicked edit-cursor tick, seek using the existing transport handoff | Cursor-oriented commands |
| No active time interval | Commit the clicked edit-cursor tick and seek using the existing handoff | Cursor-oriented commands |

The note grid does not acquire this behavior. Preserve its existing right-click selection/menu handling without moving the edit cursor or seeking. Do not implement ruler cursor placement in a shared pointer adapter.

Cursor placement is view/transport state, not an undoable document mutation. Escape after opening the ruler menu dismisses it but does not restore the old cursor/playback position. Playback may continue after the seek; commands still read the stationary edit cursor, not an advancing playback sample.

### Insert Time

- Eligible active time selection: preserve existing selection-first duration, start, track/lane/tempo scope, no-prompt insertion, selected blank interval, and cursor commit to its start.
- Active but unresolved selection: reject without prompting or changing document, undo, cursor, selection, or scope.
- No active selection: open the existing duration form at `editCursorTick()`, even while playing. Capture the cursor and local meter when the form opens; accepting after playback advances still inserts at that captured edit cursor.
- Keep the numeric form's own pending transaction/document guards; context-menu snapshot removal is not permission to remove modal draft validation.
- The cursor-oriented ruler menu exposes Insert Time even without a selection. Delete Time and Duplicate Time require their existing eligible time-selection scopes.

### Positional ruler commands

The inside-selection menu contains selection operations and nonpositional Remove Loop Markers, not Set Loop Start/End or time-signature rows. This also applies when the exact chip tick lies inside the selection: selection takes precedence and the cursor stays unchanged. Chip double-click editing is unchanged. The outside/no-selection menu contains Insert Time, Paste, loop-start/end-at-cursor, Remove Loop Markers, and edit/remove-time-signature-at-cursor. Remove Time Signature is eligible at an explicit event at the committed cursor, including a tick-row click at that event; it does not retain a chip-only eligibility flag. Preserve the existing two-command loop undo shape.

## Popup lifetime

A context menu closes synchronously when its relevant selection/track scope changes. Relevant edit-cursor movement closes positional menus. Document edits/replacement, tab teardown/deactivation, and existing session cancellation also retire the menu before a different target becomes actionable. Reopening builds the menu from current state.

Closing a selection menu is not cancellation of an unrelated modal form or an active pointer gesture. Use the existing popup session ownership/kind checks; do not broadcast blanket cancellation to foreign owners. Ordinary action activation settles/closes the menu before executing the QAction so a command may open a form safely. `stayOpen` local filter menus retain their existing behavior.

Remove obsolete pending note/time/ruler menu snapshots and activation-time stale comparisons only when this dismissal contract is established. Do not retain an artificial `activated(id)` route to execute rows from a closed menu. Do not remove the separate pending state used by numeric forms, drag transactions, or unrelated local tools.

## Menu inventory

Bindings below are the shipped defaults; `Ctrl` notation is interpreted through Qt's existing platform mapping and StandardKey alternatives. `—` means no default shortcut. Menu presentation must show the actual platform-native QAction shortcut text. IDs stay stable unless explicitly added below; do not rename existing `roll.*` IDs merely to match menu placement.

### Existing locations retained

| Existing command IDs | Location and binding policy | Scope |
| --- | --- | --- |
| `file.open_project`, `file.new_song`, `file.import_midi`, `file.save_song`, `file.register_song`, `file.close_tab`, `file.export_wav`, `file.quit` | Existing File entries/defaults | Window |
| `edit.preferences`, `edit.song_settings`, `edit.engine_settings` | Existing Edit settings entries/defaults | Window |
| `view.event_list`, `view.theme`, `view.velocity_colors`, `view.note_names` | Existing View entries/defaults | Window |
| `view.automation_drawer`, `view.velocity_drawer`, `view.voice_changes_drawer` (new catalogue IDs) | Existing View entries, A / V / P | Window |
| `view.polyphony_debugger` (new catalogue ID) | Existing View entry, Ctrl+Shift+P | Window |
| `tools.import_sample`, `help.about` | Existing Tools/Help entries/defaults | Window |
| `songs.find` | Existing song-search command, StandardKey Find; additionally expose Edit → Find Song | Window |
| `transport.follow_playhead` | Existing View action and transport state, no new shortcut | Window |

Remove `edit.keyboard_shortcuts` and its menu/Settings entry; it is not retained as an alias.

### Edit groups

| Edit presentation | Command ID | Default | Activation scope |
| --- | --- | --- | --- |
| Undo / Redo | `edit.undo`, `edit.redo` | Qt Undo / Redo | Window; preserve protected local undo |
| Copy | `roll.copy` | Qt Copy | Window; preserve native text Copy |
| Cut | `roll.cut` | Qt Cut | Editor: timeline shared selection policy |
| Paste at Edit Cursor | `roll.paste` | Qt Paste | Editor: existing song paste eligibility |
| Delete Selection | `roll.delete` | Delete / Backspace | Editor: timeline selection; event-list row Delete stays local |
| Select All Notes | `roll.select_all` | Qt SelectAll | Editor: timeline; event-list Select All remains row-local |
| Time → Insert Time | `edit.insert_time` | Ctrl+Shift+I | Window; eligible active song |
| Time → Delete Time (Shift Left) | `edit.delete_time` | — | Window; eligible selected time scope |
| Time → Duplicate Time | `roll.duplicate_time` | Ctrl+D | Editor: existing time-range policy |
| Time → Clear Time Selection | `edit.clear_time_selection` (new) | — | Editor |
| Notes → Transpose Up / Down (Semitone) | `roll.transpose_up`, `roll.transpose_down` | Up / Down | Editor: timeline |
| Notes → Transpose Up / Down (Octave) | `roll.transpose_up_octave`, `roll.transpose_down_octave` | Shift+Up / Shift+Down | Editor: timeline |
| Move → Nudge Left / Right | `roll.nudge_left`, `roll.nudge_right` | Left / Right | Editor: timeline |
| Notes → Edit Pitch Bend | `roll.pitch_bend` | G | Editor: timeline |
| Tracks → Mute / Solo Selected Tracks | `roll.mute_tracks`, `roll.solo_tracks` | M / S | M: editor; S: existing window scope |
| Automation → Pencil Mode | `automation.pencil_mode` | B | Editor: automation available/visible; preserve text/IME protection |
| Events → Move Event Up / Down (Same Tick) | `eventlist.move_up`, `eventlist.move_down` | Alt+Up / Alt+Down | Editor: event-list page, not cell editing |
| Notes → Set Velocity… | `edit.set_velocity` (new) | — | Editor: resolved selected notes |
| Loop → Set Loop Start at Edit Cursor / Set Loop End at Edit Cursor | `edit.set_loop_start`, `edit.set_loop_end` (new) | — | Editor: active song |
| Loop → Loop from Time Selection / Remove Loop Markers | `edit.loop_from_selection`, `edit.remove_loop` (new) | — | Editor: eligible interval / existing markers |
| Time → Edit Time Signature at Edit Cursor… / Remove Time Signature | `edit.edit_time_signature`, `edit.remove_time_signature` (new) | — | Editor: active song / explicit signature at cursor |
| Transport → Go to Start / Play / Play-Pause / Pause / Stop / Loop | existing `transport.*` IDs | Home / — / Space / — / — / — | Window; reuse existing actions |

Play and Play/Pause remain separate actions: the Play button resumes a paused transport, whereas Space retains its edit-cursor restart behavior. Do not alias their handlers just because both can start playback.

Set Velocity uses one static action label; remove the context-row-only velocity suffix. Its existing guarded form supplies the initial value. These additions reuse existing operations and introduce no new default keys.

### Non-command local input retained

Text/IME editing, modal accept/cancel, popup navigation, event-list row navigation/selection/delete, graph-local point editing/audition, and pointer-gesture cancellation remain local. Held gesture modifiers `roll.velocity_drag` and `velocity.detent_unlock` retain fixed Ctrl defaults but are not QActions. No menu-item fiction is introduced for holding a modifier while dragging. Sample-editor local Undo/Redo retain their separate dialog document target and fixed Qt standard keys.

## Implementation contracts

### Fixed catalogue and action ownership

- `keymap::Scope { Window, EditorRouted }` describes physical delivery, not QObject ownership. Registry owns fixed IDs, labels, bindings and scope, not selection targets or dynamic eligibility. Keep Context/category descriptive only and cache StandardKey alternatives/held modifiers once. `Registry::attach` configures QAction sequences and context once: Window uses `Qt::WindowShortcut`; EditorRouted uses `Qt::WidgetShortcut` as native-menu containment, not as widget shortcut registration.
- `SongView::EditCommand` is the closed semantic enum. `bool SongView::editCommandAvailable(EditCommand) const` reports current domain eligibility; `void SongView::executeEditCommand(EditCommand)` is the single semantic dispatch, with gesture/readiness protection. Keyboard-origin eligibility remains in `handleEditKey`; it is not stored on the action or in focus history.

`songview::EditActions` in `src/ui/songview/editactions.{h,cpp}` owns the enum-indexed QAction set. It is a concrete QObject, not an extensible command bus.

| Public interface | Responsibility |
| --- | --- |
| `explicit EditActions(QObject *parent = nullptr)` | Own the canonical actions and their callbacks. |
| `QAction *action(SongView::EditCommand) const` | Borrow an existing action for presentation or activation. |
| `void installWindowShortcuts(QWidget &window)` | Register only Window actions; call once from MainWindow. |
| `std::optional<SongView::EditCommand> editorCommandForKey(int key, Qt::KeyboardModifiers modifiers) const` | Recognize an EditorRouted binding without triggering or checking enablement. |
| `void rebind(SongView *)` | Perform the entire old-target retirement and new-target binding transaction. |
| `SongView *target() const` | Read the guarded current target. |
| `void refresh()` | Synchronize action metadata from current model state, without executing edits. |

One enum-to-catalogue-ID association serves construction, Window installation and cached Editor recognition. Plain Up returns `EditCommand::TransposeUp`; Cmd+C and unassigned chords return `std::nullopt`.

- MainWindow owns one EditActions for its lifetime, calls `installWindowShortcuts(*this)` once, and adds actions borrowed through `action(...)` to native QMenu groups. The installer alone selects Window actions for QWidget association; EditorRouted actions are excluded. Other widget/Quick consumers borrow without QWidget::addAction, even with the same pointer. EditorRouted actions have only QMenu associations. Qt shortcut registration depends on associations, not QObject ownership: sharing an object does not make another association safe. Actions survive tab changes, target the ready view, and have no per-tab clones or separate MainWindow mutation callbacks.
- `SongView::editActions() const` exposes a non-owning guarded borrow. There is no public binding setter. `songview::EditActions` is a friend of SongView and alone writes the private borrow as part of `rebind`. MainWindow and standalone fixtures call that one operation, not two coordinated setters. Isolated fixtures construct the same production action set parented to the view and bind before command-bearing input; no implicit factory, alternate owner mode, fake callback or window-key fallback.
- Existing application/transport QActions remain with their existing owners. Menu and toolbar projections borrow those exact objects. Undo/Redo retain the existing `WorkspaceUi::requestUndo/requestRedo` history routing; Find Song retains its existing search handler; Play and Play/Pause stay distinct.
- Availability is shared and semantic, not ready-only: eligible time scopes, selected notes, existing loop/signature events, Pencil page availability, and usable note-or-range clipboard payloads govern their respective actions. Loop From Selection requires a valid active interval, not resolution of the note/lane edit scope. Copy availability and callbacks preserve supported native QWidget text copying even without musical selection; use the live text-target check and existing focus notifications, not remembered focus. Solo's text protection remains. Clipboard eligibility refreshes on clipboard change, not by reparsing payloads on every key event; execution reads the current clipboard.
- Refresh from selection/context, document, committed cursor, readiness, active-tab, drawer/page, and mute/solo transitions, never playback frames. Owned actions have two one-way flows: `triggered → semantic edit`, and `model → setChecked → changed + toggled → presentation`. A real checked-state flip emits both changed and toggled, but not triggered. There is no toggled-to-edit connection; remove AutomationPage's old one. Only the bound active page synchronizes Pencil. Borrowed View/transport actions retain their existing owners and toggled semantics; EditActions does not synchronize them.

Target selection is owned by existing semantic operations, not by Registry, QAction construction or menu code:

| Command family | Single target authority |
| --- | --- |
| Musical Copy | `SongView::copySelection()` retains its existing time-selection-first branch; only absence of a time selection reaches selected notes. The canonical callback handles native text Copy before delegating to this operation; no second precedence implementation |
| Event Move Up/Down | `EventListController::canMoveCurrentRow(int delta) const` reports the visible, non-editing current row's legal same-tick move. `moveCurrentRow(delta)` performs it. Note/time selections do not participate |
| Other note/time edits | Existing selection resolver and editing operations retain their command-specific scope rules; action availability consumes those rules rather than adding a second target policy |

The event predicate encapsulates the existing destination lookup: a negative result is invalid and destination zero is valid. Keep `moveDestForRow` for its existing direct consumers, but action code uses the bool predicate and does not interpret destinations or inspect unrelated timeline selections.

### Single binding operation

`EditActions::rebind` owns both sides of the binding and menu retirement. Callers only provide the next ready SongView, or null.

- Disconnect old target observations and clear the guarded action target and old view borrow before any menu-close callback can re-enter command delivery.
- Retire the old target's menus without focus restoration, then install the new guarded target/borrow and refresh availability. No caller manually clears a borrow or closes menus to complete a bind.
- At the start of SongView teardown, the bound view calls its action set's `rebind(nullptr)` before popup or child teardown. Clearing only the view's borrow is not unbinding; no action may still target the partially destroyed view.
- A defensive destroyed-target callback still clears/disables/refreshes if QPointer has already cleared. Null-to-null must not skip that refresh, and no destroyed SongView is queried.

### Physical activation and local priority

Shortcut scope selects the physical delivery owner; QAction ownership and menu placement do not select scope.

| Scope | Physical key delivery | Shared edit execution |
| --- | --- | --- |
| Window (Copy, Space, Solo, Undo, A/V/P) | Qt matches the QAction's installed shortcut; no application `Registry::matches` pass handles these keys | That Window QAction's existing/canonical callback |
| Editor (Cut, transpose, Pencil, event moves) | Suppress native preemption, let protected local input run, then use the existing Quick fallback where eligible | `handleEditKey` triggers the canonical QAction |

Keep real sequences on Editor actions and associate them with QMenu only using `Qt::WidgetShortcut`. The existing SongView application filter checks `ShortcutOverride` and bound-target identity, then asks `EditActions::editorCommandForKey` whether this is an Editor binding. A match calls `event->accept()` and returns true, independently of action enablement and whether a menu is open. This is protocol arbitration on all platforms, not a macOS-only or menu-open handler. The filter contains no command table, scope matcher or execution; it never claims Window bindings, intercepts KeyPress, forwards or changes focus. Its shortcut branch is outside the `watched == application` appearance guard and checks event type before recognition.

Ordinary key delivery then lets text/IME, popup, cell editing, row navigation and deliberate controls act locally. A foreign non-modal window keeps its local key and does not gain song editing merely because an Editor action is enabled. Only an eligible editor's existing Quick fallback reaches `handleEditKey`. It uses the same `editorCommandForKey` result, then applies existing origin/repeat/gesture rules to three terminal outcomes:

| Outcome | Result |
| --- | --- |
| No shared Editor match, or local origin owns the key | Decline; no shared action activation |
| Recognized command is blocked by a gesture or unavailable under its existing terminal-consumption policy (including Duplicate Time without a range) | Consume without triggering or substituting another operation |
| Recognized, locally eligible, enabled command | Trigger its canonical QAction once and consume |

Recognition in ShortcutOverride does not depend on enablement; execution does. Do not call `trigger()` on disabled actions to implement a no-op. Preserve G/B non-repeat, Escape behavior, key-release audition and AutomationPage's unrelated WindowDeactivate draft cancellation. Remove `SharedShortcutOwner`, the manual Pencil matcher/KeyPress interceptor and event-list Move's independent edit dispatch. Commands without default keys remain ordinary executable menu actions.

Source verification: Qt's [QMenu platform projection](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/widgets/qmenu.cpp) copies QAction shortcuts without filtering by shortcut context. The [Cocoa menu delegate](https://raw.githubusercontent.com/qt/qtbase/6.9/src/plugins/platforms/cocoa/qcocoansmenu.mm) probes ShortcutOverride before a native key equivalent and returns ordinary key delivery when accepted. The [Cocoa menu item](https://raw.githubusercontent.com/qt/qtbase/6.9/src/plugins/platforms/cocoa/qcocoamenuitem.mm) turns displayed accelerators into real equivalents; do not fake display-only shortcuts with tab-suffixed labels.

The [Qt widget shortcut-context implementation](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/kernel/qshortcut_widgets.cpp) establishes association-based scope; the [QAction implementation](https://raw.githubusercontent.com/qt/qtbase/6.9/src/gui/kernel/qaction.cpp) establishes checked-state notification and trigger ordering. Synthetic QKeyEvent delivery does not traverse Cocoa menu equivalents; execution proof must distinguish Qt protocol checks from real native input. A non-modal foreign window is required to test override isolation without automatic modal-menu disabling.

### Action-backed Quick rows

`QuickMenuItem::fromAction(QAction &, int id)` snapshots presentation text/enabled/checked at
open time, retains a guarded non-owning identity the host triggers, requires the QAction to
outlive the open menu, and retires the level on `changed()`. A menu caller supplies an existing
action and lookup ID; the helper produces a tagged action-backed row with `QPointer<QAction>`
and open-time scalar roles: text (remove mnemonic markers while preserving escaped `&&`),
primary native shortcut, enabled, checkable and checked. No label/enablement override API
exists. A distinct tag prevents a destroyed action from becoming a value row.

QuickMenuHost retires an open action-backed level when a represented QAction changes
metadata/eligibility or is destroyed. Observe each open level on its own existing Level:
collect only that level's own action-backed rows at push and store the connections in the
level's `actionConnections`; detach each level's connections at its teardown; retirement on
`changed()` is level-scoped. An action-backed level resets in place like any value-only level;
value-only roots retain their existing reset/stayOpen behavior. Destruction handlers never
dereference the destroyed action.

This deliberately includes a clipboard transition that changes Paste eligibility; valid-to-valid payload changes need not close it. This avoids a second live metadata model while keeping reachable submenu rows accurate. Local value rows and lazy submenus retain their behavior; action-backed stayOpen rows are not supported.

`QuickMenuHost::activateRow` owns one terminal action-backed branch: capture guarded action/source/host, close synchronously, then recheck those lifetimes and the action's enabled state. If any guard fails, return without activation, retry, deferred work or focus-completion notification. Otherwise trigger once; emit `actionActivated(QAction*)` only if the host/action survive. This branch never pre-toggles or reaches legacy `activated(int)` dispatch. Menu callers only handle the focus-only completion, restoring their surface if no new form/session opened. Value-row activation remains in its separate existing branch; keyboard/menu-bar activation does not focus a band.

### Selection, forms, and positional semantics

Add `SongView::selectionContextChanged()` at the existing `coordinateSelectionChange` seam for primary track, stored track scope, note selection and time selection changes. Add `invalidateContextMenus(bool restoreFocus)` and `contextMenusInvalidated(bool restoreFocus)` for the separate menu-lifetime notification. Publish menu invalidation before action-state refresh; each menu owner subscribes once and cancels only its own relevant menu. Session ownership alone is insufficient for shared hosts: the ruler requires `rootModel() == m_rulerMenuModel`, preserving grid-division/feel menus; the automation fallback uses presence of the stable typed `CanvasMenuAction::ClearTimeSelection` row, preserving independent lane menus. Document lifecycle and committed-cursor invalidation use existing seams. Ordinary invalidation restores focus; teardown/rebinding does not. Do not use blanket closePopups to cancel another owner's form.

The inactive automation fallback builds its Clear row locally, so it must explicitly use `fromAction` with the canonical Clear Time Selection action and retain `int(CanvasMenuAction::ClearTimeSelection)`. No active interval means disabled Clear, not a parallel no-op callback. Remove that fallback's PendingMenu population and legacy Clear case; retain the real lane menu's lane/row-ID target re-resolution and local handlers. Active shared range menus still use the SongView row producer.

Retire `PendingTimeSelectionMenu`, `PendingNoteMenu`, `PendingRulerMenu`, their revision/selection/track snapshots, and obsolete menu execution switches after the owners adopt dismissal plus action rows. Forms retain `PendingInsertTimePrompt`, `PendingVelocityPrompt`, `PendingTimeSigPrompt` and corresponding automation drafts. Live document errors and transaction validation remain real safeguards.

Expose `PianoRoll::openSelectedVelocityPrompt()` and `TimeRuler::editTimeSignatureAtCursor()` as narrow semantic entries; their existing private form implementation and guarded lifetime remain. SongView's semantic dispatcher accesses its owned roll/ruler; the action set does not inspect private widgets. Loop marker actions read the document/current cursor or authoritative time interval; signature removal reads the explicit event at the cursor. Shared ruler/time/note command menus retain no clicked-tick snapshot after opening; local point/lane targets and guarded forms retain the identities their distinct operations require.

Event-list Move Up/Down delegates eligibility to `canMoveCurrentRow(-1/+1)` and execution to `moveCurrentRow(-1/+1)`. The current row is established before its menu opens; row/chunk/filter/selection/document changes retire that row menu. Its Move rows share the canonical actions, while local Insert/type/voice/Delete/filter operations retain their distinct semantics. Refresh Move availability from current-row, chunk, filter, selected-row, visibility and editing state changes.

## Source evidence

- `src/ui/keymap.{h,cpp}`: current defaults, mutable overrides, contexts, modifier bindings, attachment and conflict machinery.
- `src/mainwindow.cpp`: current window/menu commands, direct A/V/P/polyphony bindings, ready-state action enablement, selected-tab and cursor-to-audio handoff.
- `src/ui/songview/editkeyrouting.cpp`: shared key matching plus selection policy and Copy/Solo dual-ownership flag.
- `src/ui/songview/quick/timelinequickview_keyrouting.cpp`, `timelineinputitem.cpp`, `eventlistcontroller.cpp`: Quick delivery/local input and event-list origin.
- `src/ui/editordrawer/automationpage.cpp`, `automationcanvas_input.cpp`: Pencil QAction interception and no-selection hover-delete precedence.
- `src/ui/songview/rangeedit.cpp`, `timeruler_interaction.cpp`, `pianoroll_commands.cpp`: menu snapshots, independent command switches, cursor/time prompt and musical operations.
- `src/ui/songview.cpp`: authoritative selection observer, document lifecycle, popup cancellation and edit-cursor commit.
- `src/ui/songview/quick/quickmenumodel.{h,cpp}`, `quickmenuhost.cpp`, `quickmenulayout.cpp`: value-row projection, close-before-activation, submenus and stay-open filters.
- `src/ui/transportbar.{h,cpp}`, `workspaceui.{h,cpp}`: existing transport action ownership and menu projection.
- `src/ui/settingsdialog.{h,cpp}`, `keyboardshortcutsdialog.{h,cpp}`: Keyboard tab and immediate remapping/rollback.
- `src/checks/checkcatalog.cpp`: actual named suites; `src/checks/keyboard`, `selectionkey`, `rollcheck`, `mainwindowrouting` hold affected behavioral proofs.
