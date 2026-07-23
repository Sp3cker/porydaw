# Keyboard Shortcuts: Clean-Base Implementation Plan

## Purpose

Implement the agreed Ableton-inspired keyboard shortcuts from a clean porydaw base without carrying forward the current shortcut branch's registry, runtime audit, `SongView` source split, or unrelated behavior changes.

This document is intentionally prescriptive. On implementation day, treat its file limits, ownership rules, shortcut scopes, omissions, and verification requirements as acceptance criteria.

## Starting Point

1. Start from the intended clean base branch.
2. Do not build on, merge, or cherry-pick the current keyboard-shortcut branch.
3. Confirm the base still has the consolidated `src/ui/songview.cpp` containing the private `PianoRoll`, `TimeRuler`, `AutomationArea`, and `NoteContextMenu` classes.
4. Record the base commit before editing so the final diff can be reviewed against an exact fixed point.
5. If the base has moved, adapt symbol locations but preserve the ownership and scope rules below.

The forensic worktree used to prepare this plan had missing Git worktree metadata. Its physical baseline snapshots showed the relevant pre-existing seams, but implementation day must pin a real merge-base before making changes.

## Design Decision

Use owner-local, persistent `QAction` instances. Do not add a shortcut framework.

The seam is `QWidget::addAction()` on the widget whose state the command affects:

- `MainWindow` owns window, transport, and active-tab commands.
- `PianoRoll` owns note-selection editing and piano-roll zoom commands.
- `AutomationArea` owns time-range editing commands while its canvas has focus.
- `TimeRuler` owns loop-selection and grid callbacks, even when its actions are associated with `SongView` for editor-wide reach.

A single `QAction` must represent each local command path. The same action is reused by shortcut dispatch, context menus, menus, or toolbars. Do not create one action for the menu and another for the shortcut.

Representative pattern:

```cpp
auto *duplicate = new QAction(SongView::tr("Duplicate"), this);
duplicate->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_D));
duplicate->setShortcutContext(Qt::WidgetShortcut);
addAction(duplicate);
connect(duplicate, &QAction::triggered,
        this, &PianoRoll::duplicateSelection);
noteMenu->addAction(duplicate);
```

A short private installation method such as `PianoRoll::installActions()` is acceptable if it keeps the constructor readable. A local lambda that removes repeated `QAction` setup is also acceptable. Neither is a public interface or a new module.

## Hard Guardrails

### Production diff limits

The intended production patch touches only:

- `src/mainwindow.cpp`
- `src/mainwindow.h`, only if another persistent action pointer is required
- `src/ui/songview.cpp`
- `src/ui/songview.h`, only if shared snap/grid state is genuinely absent

The verification patch may also touch:

- `src/rollcheck.cpp`
- `src/tabcheck.cpp`

### Files and systems that must remain untouched

- `CMakeLists.txt`
- `src/main.cpp`
- Project loading or saving
- Shortcut preferences or persistence
- `SongDocument`, unless a separately demonstrated missing behavior requires a focused change
- Audio engine, playback engine, project builder, and polyphony code

### Files that must not be created

- `liveshortcuts.hpp` or `liveshortcuts.cpp`
- `shortcutcheck.cpp`
- `checkinput.hpp`
- A shortcut manager, command dispatcher, command registry, binding registry, or runtime action scanner
- New `songviewpianoroll*`, `songviewtimeruler*`, or `songviewautomation*` extraction files
- New test executables or scripts

### Metadata that must not be introduced

- A `Command` enum
- Stable shortcut string IDs
- `liveShortcutId` or equivalent `QObject` properties
- Descriptor arrays or descriptor-count invariants
- Translation contexts stored separately from the action owner
- Runtime discovery of actions for completeness or conflict auditing

## Shortcut Inventory

There are 35 shortcut commands in this plan. The pre-existing MIDI Event List shortcut remains porydaw-specific and is not counted among the 35.

Qt portable `Ctrl` must be used for Ableton's Command key. Do not use `Meta` to represent Command on macOS.

### MainWindow: 7 commands

Associate these actions with `MainWindow` and use `Qt::WindowShortcut`.

| Command | Qt binding | Existing/local action | Required behavior |
|---|---|---|---|
| Undo | `QKeySequence::Undo` | `QUndoGroup::createUndoAction()` result | Routes to the active tab's undo stack |
| Redo | `QKeySequence::Redo` | `QUndoGroup::createRedoAction()` result | Routes to the active tab's redo stack |
| Play/Pause | `Space` | Existing play/pause action | Pauses while playing; otherwise starts from the edit cursor |
| Continue Playback | `Shift+Space` | Existing play/continue action | Continues from the stopped transport position |
| Go to Start | `Home` | Existing go-to-start action | Moves transport/edit position according to existing behavior |
| Loop | `Ctrl+L` | Existing loop action | Toggles the same checkable loop state used by the toolbar |
| Follow Playback | `Alt+Shift+F` | Existing follow action | Toggles the same checkable follow state used by the View menu |

Requirements:

- Explicitly associate menu/toolbar actions with `MainWindow` using `addAction()` when required for reliable shortcut dispatch.
- Keep enabled and checkable state on these same action objects.
- Continue using existing active-tab and transport state refresh paths.
- `Space` is the sole intentional window-wide exception while a text editor has focus.

### PianoRoll: 22 commands

Associate these actions with the focusable piano-roll canvas and use `Qt::WidgetShortcut`.

| Command | Qt binding(s) | Required behavior |
|---|---|---|
| Cut | `QKeySequence::Cut` | Copy selected notes, delete them, clear/update selection |
| Copy | `QKeySequence::Copy` | Copy selected notes |
| Paste | `QKeySequence::Paste` | Paste at the edit cursor using existing clipboard semantics |
| Select All | `QKeySequence::SelectAll` | Select all applicable notes |
| Delete | `Delete`, `Backspace` | Delete selected notes |
| Duplicate | `Ctrl+D` | Duplicate by one selection span and select the duplicate |
| Split | `Ctrl+E` | Split selected notes at current-grid boundaries; when no notes are selected, split notes crossed by the playhead |
| Join | `Ctrl+J` | Join eligible adjacent same-pitch notes |
| Move Left | `Left` | Move notes to the previous absolute grid line |
| Move Right | `Right` | Move notes to the next absolute grid line |
| Transpose Up | `Up` | Move selected notes up one semitone |
| Transpose Down | `Down` | Move selected notes down one semitone |
| Transpose Octave Up | `Shift+Up` | Move selected notes up twelve semitones |
| Transpose Octave Down | `Shift+Down` | Move selected notes down twelve semitones |
| Shorten | `Shift+Left` | Move selected note ends left by one grid line |
| Lengthen | `Shift+Right` | Move selected note ends right by one grid line |
| Decrease Velocity | `Ctrl+Down` | Decrease selected note velocity by one |
| Increase Velocity | `Ctrl+Up` | Increase selected note velocity by one |
| Zoom In | `=`, physical/keypad `+` forms needed by Qt | Horizontally zoom around the visible center without requiring Shift on the `=` key |
| Zoom Out | `-` | Horizontally zoom out around the visible center |
| Zoom to Selection | `Z` | Frame the active note or time selection |
| Zoom to Full Song | `X` | Frame the full song |

Requirements:

- Preserve click-to-focus behavior on the piano roll.
- Keep key-release handling used by note audition local to `PianoRoll`; do not create an application event filter.
- Standard edit commands must use `QKeySequence::StandardKey` forms where listed.
- Delete must use only literal Delete and Backspace, not a broader platform-standard Delete mapping.
- Zoom In must be verified using the physical `=` key without Shift on macOS. Add only the alternative `QKeySequence` forms proven necessary by the runtime test.
- Action callbacks must retain document, selection, pitch-range, and velocity-range guards.
- Repeated note moves must preserve the existing undo coalescing behavior.

### AutomationArea: focused range variants

Time-range selection reuses appropriate edit keys while the automation/range canvas has focus:

- Cut, Copy, Paste, Delete, and Backspace
- Left and Right range movement
- Up and Down transposition
- Shift+Left and Shift+Right note-end resizing within the range
- Shift+Up and Shift+Down octave transposition
- Ctrl+Up and Ctrl+Down velocity changes

Create separate `AutomationArea` action instances with `Qt::WidgetShortcut` and direct range callbacks. These actions may share bindings with `PianoRoll` because their shortcut scopes do not overlap: focus selects the active owner.

Do not share one `QAction` between piano-note and time-range editing. Their labels, enablement, and callbacks differ.

### TimeRuler/SongView: 6 commands

`TimeRuler` creates and connects these actions. Associate them with `SongView` using `Qt::WidgetWithChildrenShortcut` so they work while the piano roll or lanes are focused without becoming window-global.

| Command | Qt binding | Required behavior |
|---|---|---|
| Select Loop Contents | `Ctrl+Shift+L` | Create a time selection from the valid loop range |
| Finer Grid | `Ctrl+1` | Step toward finer fixed/adaptive grid resolution |
| Coarser Grid | `Ctrl+2` | Step toward coarser fixed/adaptive grid resolution |
| Triplet Grid | `Ctrl+3` | Toggle straight/triplet feel |
| Snap to Grid | `Ctrl+4` | Toggle snapping without discarding the chosen grid |
| Fixed/Adaptive Grid | `Ctrl+5` | Toggle adaptive density and the last fixed resolution |

Requirements:

- Keep `Grid` as a static gutter label; do not create a Grid dropdown or menu.
- Reuse existing grid setters and `TimeRuler::syncGridControls()`.
- Checkable actions and visible combo-box state must stay synchronized after either mouse or keyboard changes.
- Enable Select Loop Contents only when a valid loop range exists.

## Persistent Piano-Roll Context Menu

`NoteContextMenu` remains responsible only for popup presentation, velocity text, and retargeting an already-open popup. `PianoRoll` owns the reusable command actions.

The persistent note context menu must include:

- Cut, Copy, Paste, Delete, Select All
- Duplicate
- Split and Join
- Move Left and Move Right
- Transpose Up/Down and Octave Up/Down
- Shorten and Lengthen
- Decrease and Increase Velocity
- Zoom In, Zoom Out, Zoom to Selection, Zoom to Full Song

Grouping those actions into an `Edit Notes` submenu is acceptable if it matches the existing UI decision. The menu must reuse the exact actions installed on `PianoRoll`.

The menu must not include:

- Quantize
- Quantize Settings
- Invert Selection
- Fit Notes to Time Range

## Deliberate Omissions

Keep the ordinary menu actions clickable but assign no keyboard shortcut to:

- Open Project (`Cmd+O`)
- New Song (`Cmd+N`)
- Save (`Cmd+S`)
- Close Tab (`Cmd+W`)
- Quit (`Cmd+Q`)
- Find Song (`Cmd+F`)
- Song Browser (`Cmd+Option+B`)
- Quantize (`Cmd+U`)
- Quantize Settings (`Cmd+Shift+U`)
- Invert Selection (`Cmd+Shift+A`)
- Fit Notes to Time Range (`Cmd+Option+J`)

Also omit:

- The old `O` mute action
- Global `B`, `F`, and `W` bindings
- Any shortcut for a feature porydaw does not already model

Retain the existing porydaw-specific MIDI Event List action at `Ctrl+Shift+E`. It is outside the 35-command Ableton-aligned inventory and must not be added to a new catalogue.

## Implementation Waves

### Wave 1: Pin and inspect

Use one `scout` subagent for read-only reconnaissance if symbol locations differ from this document. The primary agent owns the plan and decisions.

1. Pin the fixed point and confirm a clean tree.
2. Locate `MainWindow::buildUi()`, `PianoRoll`, `NoteContextMenu`, `AutomationArea`, `TimeRuler`, `SongView::handleEditKey()`, `rollcheck`, and `tabcheck`.
3. Record existing action instances and behavior methods.
4. Confirm which requested behaviors already exist before adding any action.

Acceptance: a file/symbol map proving that no new architectural seam is needed.

### Wave 2: MainWindow actions

Dispatch to one `task` implementation agent only if another independent implementation wave is running concurrently; otherwise implement inline.

1. Remove the deliberately omitted File/Find shortcuts.
2. Configure the seven window commands on their existing actions.
3. Reuse the same actions in menus and toolbars.
4. Preserve active-tab routing and enabled/checkable refresh behavior.

Acceptance: the seven bindings work and all deliberately omitted MainWindow actions report empty shortcuts.

### Wave 3: editor actions

This can run in parallel with Wave 2 through a separate `task` agent because it is confined to `SongView` files.

1. Add persistent piano-roll actions beside their callbacks.
2. Rework `NoteContextMenu` to display those action pointers rather than create duplicate edit actions.
3. Add separate focused range actions to `AutomationArea`.
4. Add the six ruler/grid actions with editor-wide `SongView` association.
5. Keep all implementation in the consolidated `songview.cpp` unless the clean base is already intentionally split for unrelated reasons.

Acceptance: shortcut and menu activation use the same callback path; piano and range scopes do not collide.

### Wave 4: behavioral verification

Use a dedicated `reviewer` subagent after implementation to inspect scope, focus behavior, omissions, and accidental architectural growth. Run verification once from the primary agent.

Extend existing harnesses rather than creating a metadata audit.

#### `rollcheck.cpp`

Exercise and assert observable state for:

1. Cut, Copy, Paste, Select All
2. Delete and Backspace
3. Duplicate
4. Split with selected notes
5. Split with no selection and the playhead crossing notes
6. Join success and ineligible-join no-op
7. Left/Right movement on-grid and initially off-grid
8. Semitone and octave transposition, including range limits
9. Shorten/Lengthen, including minimum duration
10. Velocity increase/decrease, including 1/127 limits
11. Zoom In using unshifted `=`, plus-key alternatives, and Zoom Out
12. Z with a note selection
13. Z with a time selection
14. X for the full song
15. Ctrl+1 through Ctrl+5 and Ctrl+Shift+L
16. Equivalent context-menu activation for representative note commands
17. Undo restoration for every mutating command family
18. Repeated movement retaining the intended single/coalesced undo behavior

Focus-safety checks:

1. Focus the piano roll and prove plain arrows edit notes.
2. Focus `AutomationArea` and prove the same keys edit the range instead.
3. Focus an inline `QLineEdit` or table editor and prove arrows, typing, Cut/Copy/Paste, Delete, Z, and X remain local to that editor as appropriate while `SongDocument` remains unchanged.
4. Prove ruler/grid shortcuts work from piano-roll and lanes focus but not from unrelated docks or another window.

#### `tabcheck.cpp`

Exercise and assert:

1. Undo and Redo route to the active tab
2. Space toggles play/pause
3. Shift+Space continues playback
4. Home goes to start
5. Ctrl+L toggles loop
6. Alt+Shift+F toggles follow playback
7. Ctrl+Shift+E retains MIDI Event List behavior
8. Switching tabs updates enabled and checkable action state
9. Space remains the intentional transport shortcut while a text widget is focused
10. Open, New, Save, Close, Quit, Find, and Song Browser actions have no assigned shortcut

Acceptance: tests observe behavior and focus routing, not descriptor contents or source text.

## Review Checklist

The final `reviewer` must reject the patch if any answer is wrong.

### Architecture

- [ ] No global shortcut manager, registry, dispatcher, or scanner exists.
- [ ] No `Command` enum or shortcut ID property exists.
- [ ] No production source file was created solely for shortcut metadata.
- [ ] `SongView` was not split or broadly refactored for this work.
- [ ] Menus and toolbars reuse the actions that own the shortcuts.
- [ ] Behavior callbacks remain with the state owner.

### Scope

- [ ] Exactly 35 planned Ableton-aligned commands are implemented.
- [ ] MIDI Event List remains the separate existing porydaw-specific binding.
- [ ] Every deliberate omission remains unbound.
- [ ] Quantize, Quantize Settings, Invert Selection, and Fit Notes to Time Range remain absent from the note context menu.
- [ ] No unrelated feature, preference, persistence, audio, project, or document refactor is present.

### Qt behavior

- [ ] Standard keys use `QKeySequence::StandardKey` where specified.
- [ ] Ableton-specific Ctrl bindings render and behave as Command on macOS.
- [ ] MainWindow commands use `Qt::WindowShortcut`.
- [ ] Piano and range commands use non-overlapping `Qt::WidgetShortcut` scopes.
- [ ] Ruler/grid commands are editor-wide but not window-global.
- [ ] Text widgets retain normal editing keys except for the deliberate window-wide Space transport behavior.
- [ ] Unshifted `=` zooms in on macOS.

### Verification

- [ ] Existing runtime harnesses were extended; no metadata audit executable was added.
- [ ] Every mutating shortcut has an observable state assertion and undo restoration.
- [ ] Both positive and focus-safety scenarios pass.
- [ ] The application was smoke-tested with real focus changes, the persistent note context menu, transport, and grid controls.
- [ ] Final diff contains no CMake change and stays within the intended file set unless a deviation is explicitly justified.

## Definition of Done

The implementation is complete only when:

1. All 35 commands behave as specified through real keyboard dispatch.
2. The MIDI Event List binding still behaves as before.
3. Every deliberate omission remains unbound and clickable where applicable.
4. Piano-roll, range, ruler, text-editor, and window scopes behave correctly.
5. Menu or toolbar activation and keyboard activation share the same `QAction` and callback path.
6. Existing behavioral harnesses pass with the new scenarios.
7. A runtime smoke test confirms focus routing, context-menu actions, transport, grid changes, and unshifted `=` zoom.
8. The final diff is a surgical shortcut patch rather than an architectural rewrite.
