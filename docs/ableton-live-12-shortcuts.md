# Ableton Live 12 shortcut research for porydaw

## Scope and evidence

This note covers shortcuts that map to porydaw's current transport, piano-roll,
selection, loop, grid, and zoom concepts. It does not propose copying Ableton
features that porydaw does not have.

Primary sources:

- [Live 12 Keyboard Shortcuts](https://www.ableton.com/en/live-manual/12/live-keyboard-shortcuts/), especially §§41.5, 41.8–41.15, 41.20, and 41.28.
- [Editing MIDI](https://www.ableton.com/en/live-manual/12/editing-midi/), especially §§10.5.4–10.5.5.
- [Arrangement View](https://www.ableton.com/en/live-manual/12/arrangement-view/), especially §§6.2, 6.3, 6.6, 6.9, and 6.10.
- [Accessibility and Keyboard Navigation](https://www.ableton.com/en/live-manual/12/accessibility-and-keyboard-navigation/), especially §§40.1.1 and 40.4.
- [Qt keyboard modifiers](https://doc.qt.io/qt-6/qt.html#KeyboardModifier-enum) and [Qt's macOS Ctrl/Meta remapping](https://doc.qt.io/qt-6/qt.html#ApplicationAttribute-enum).

Local installation inspected read-only:

- `/Applications/Ableton Live 12 Beta.app/Contents/Info.plist` identifies Live
  12.4.5b4, executable `Live`, bundle identifier `com.ableton.live`, and main
  nib `MainMenu` (lines 234–247, 263–264, 281–282 in the extracted plist).
- `Contents/Resources/English.lproj/MainMenu.nib/designable.nib` contains only
  the static Cocoa application and Help menus. The application menu includes
  About Live, Settings (`Cmd+,`), Hide Live (`Cmd+H`), Hide Others
  (`Cmd+Option+H`), Show All, and Quit (`Cmd+Q`) (XML lines 47, 65–87,
  105–113, 133–153, 171–192). `keyedobjects.nib` strings corroborate those
  labels and key-equivalent fields.
  These Live key equivalents document the source application only; porydaw retains
  the corresponding File-menu commands and main-window actions without assigning
  those keys.
- The dynamic Live/Edit/View/Options/Navigate menus and their shortcut
  assignments are not present in readable nib resources; Live builds them at
  runtime. A runtime accessibility menu tree was not observed because Live was
  not running. All non-static mappings below therefore come from Ableton's
  official manual, not reverse engineering.

## Recommended organization

Use a focused `live_shortcuts` metadata seam, not a command dispatcher:

1. The `live_shortcuts::Command` enum and its 35 `Descriptor` entries are the
   central catalogue of stable action IDs. Each descriptor supplies the
   `liveShortcutId`, translated label, key sequence, and shortcut context. A
   canonical descriptor may configure one or more `QAction` instances,
   including multiple widget-scoped instances; each call to `configureAction`
   applies that metadata to one instance.
2. Metadata does not own behavior. The UI component that owns the affected
   state creates the action and connects its direct callback locally:
   `MainWindow` owns application, view, and transport callbacks; `PianoRoll`
   owns note-edit callbacks; `AutomationArea` owns range-edit callbacks; and
   `TimeRuler` owns loop-selection and grid callbacks. Its
   `SelectLoopContents`, `NarrowGrid`, `WidenGrid`, `TripletGrid`,
   `ToggleSnapToGrid`, and `FixedAdaptiveGrid` actions are configured from
   their descriptors without moving their callbacks elsewhere.
3. The Song Browser remains dock-owned: `MainWindow` adds the
   `QDockWidget::toggleViewAction()` to View as its clickable menu action. It
   has no `live_shortcuts` descriptor or keyboard binding.
4. Window commands use `Qt::WindowShortcut`. Widget-scoped commands use
   `Qt::WidgetShortcut`; range commands use that canonical descriptor context
   on each `AutomationArea` State widget instance, so plain editing keys do not
   fire while another editor has focus.
5. Standard operations use `QKeySequence::StandardKey`. Ableton-specific
   defaults use portable sequences such as `Ctrl+D`; Qt renders and handles
   that as Command on macOS.
6. Shortcuts stay `QAction`-backed rather than becoming shortcut-only
   `keyPressEvent` branches.

`live_shortcuts` is intentionally metadata-only: it gives registration and the
audit one stable vocabulary without taking callback ownership away from the
editor that changes state. A shortcut-preferences system remains out of scope.

`shortcutcheck` is descriptor-driven. It requires every descriptor to have at
least one action instance, allows multiple valid scoped instances, and validates
every action carrying that descriptor ID against the expected shortcuts and
context. Unknown IDs, missing descriptors, shortcut or context mismatches, and
overlapping-scope conflicts fail the audit. `ableton_shortcut_matches` counts
unique descriptors whose discovered action instances all pass validation. A
nonzero conflict count reports the colliding IDs and also fails the process; zero
conflicts is required.

`Ctrl` below is Qt portable notation; it displays and behaves as Command on
macOS. `Alt` displays and behaves as Option.

## Current shortcut map

### Window and transport

| Command | macOS | Qt portable | Ableton alignment |
|---|---|---|---|
| Open project / New song / Save / Close tab / Quit | — | — | Clickable File-menu commands; no keyboard binding |
| Undo / Redo | `Cmd+Z` / `Cmd+Shift+Z` | Qt standard keys | Exact |
| Find song | — | — | Main-window action; no keyboard binding |
| Play/Pause | `Space` | `Space` | Exact key; porydaw starts from the edit cursor |
| Continue playback | `Shift+Space` | `Shift+Space` | Exact |
| Go to start | `Home` / `Fn+Left` | `Home` | Exact |
| Loop | `Cmd+L` | `Ctrl+L` | Exact |
| Follow playback | `Option+Shift+F` | `Alt+Shift+F` | Exact |
| Song Browser | — | — | Clickable View-menu/dock toggle; no keyboard binding |
| MIDI Event List | `Cmd+Shift+E` | `Ctrl+Shift+E` | Porydaw-specific; Live uses this key for Export MIDI |

### Piano roll

| Command | macOS | Qt portable | Behavior |
|---|---|---|---|
| Cut / Copy / Paste / Select All | `Cmd+X/C/V/A` | Qt standard keys | Acts on the note selection |
| Delete | `Delete` or `Backspace` | both keys | Deletes selected notes |
| Duplicate | `Cmd+D` | `Ctrl+D` | Copies the selected notes one selection span to the right |
| Split / Join | `Cmd+E/J` | `Ctrl+E/J` | Splits selected notes at every current-grid boundary and unselected notes crossed by the playhead / joins adjacent same-pitch notes |
| Move notes by grid | `Left/Right` | `Left/Right` | Moves to the adjacent absolute grid line |
| Transpose semitone | `Up/Down` | `Up/Down` | Moves selected notes by one semitone |
| Transpose octave | `Shift+Up/Down` | `Shift+Up/Down` | Moves selected notes by one octave |
| Shorten / Lengthen | `Shift+Left/Right` | `Shift+Left/Right` | Moves selected note ends by one grid line |
| Decrease / Increase velocity | `Cmd+Down/Up` | `Ctrl+Down/Up` | Changes selected note velocity by one |
| Zoom in / out | `=` (or `+`) / `-` | `=` (or `+`) / `-` | Horizontal zoom around the visible center without requiring Shift for zoom-in |
| Zoom to selection / Full song | `Z` / `X` | `Z` / `X` | `Z` frames the active time or note selection; `X` frames the complete song |

### Time ruler

| Command | macOS | Qt portable | Behavior |
|---|---|---|---|
| Select loop contents | `Cmd+Shift+L` | `Ctrl+Shift+L` | Creates a time selection from the song loop |
| Finer / Coarser grid | `Cmd+1/2` | `Ctrl+1/2` | Steps through `1/4`, `1/8`, `1/16`, `1/32`, and adaptive resolution |
| Triplet grid | `Cmd+3` | `Ctrl+3` | Toggles straight/triplet feel |
| Snap to grid | `Cmd+4` | `Ctrl+4` | Toggles snapping without losing the chosen grid |
| Fixed / Adaptive grid | `Cmd+5` | `Ctrl+5` | Toggles adaptive density and the last fixed resolution |

The remaining note-editing and zoom actions live in the persistent piano-roll
context menu, including its Edit Notes submenu. Quantize, Quantize Settings,
Invert Selection, and Fit Notes to Time Range are not registered context
actions or keyboard shortcuts. In the ruler gutter, `Grid` is a static label
for the adjacent resolution and feel controls rather than another menu.

## Deliberate omissions and conflicts

- A prior `O` action merely toggled the selected track's mute bit. It was
  removed rather than mislabeled as Live's Activate/Deactivate Track command.
- The `Cmd+O/N/S/W/Q` (Open project, New song, Save, Close tab, Quit) and
  `Cmd+F` (Find song) mappings are deliberately omitted. Their File-menu
  commands and main-window action remain available, but have no keyboard binding.
- The `Cmd+Option+B` (Song Browser) mapping is deliberately omitted. Its
  View-menu dock toggle remains clickable, but has no keyboard binding.
- `Cmd+U` / `Cmd+Shift+U` (Quantize / Quantize Settings), `Cmd+Shift+A`
  (Invert Selection), and `Cmd+Option+J` (Fit Notes to Time Range) are
  deliberately omitted from the piano-roll shortcut and context-action
  catalogue. These omissions concern only porydaw registration; they do not
  claim that Ableton's corresponding standard menu features were removed.
- Global single-letter commands such as `B`, `F`, and `W` are not copied.
  Live's surrounding draw, automation, and computer-MIDI modes do not exist in
  porydaw, so those keys would steal ordinary input without the same model.
- `Cmd+Shift+E` for MIDI Event List remains an application-specific mismatch.
  Remap it before adding an Export MIDI command.
- Text fields and table editors keep their normal keys. Space is the one
  intentional window-wide exception for transport.

## Runtime audit

`autoresearch.sh` builds the Release application and runs the descriptor-driven
action registration audit. It can be reproduced from any caller directory:

```sh
/absolute/path/to/porydaw/autoresearch.sh
```

The script derives the repository root from its own path, uses that root's
`build-autoresearch` directory by default, and accepts
`PORYDAW_AUTORESEARCH_BUILD_DIR` as an explicit build-directory override.

The preceding runtime audit directly observed:

```text
METRIC ableton_shortcut_matches=35
METRIC shortcut_bindings=54
METRIC shortcut_conflicts=0
```

These directly observed audit metrics mean 35 unique stable command descriptors
have at least one valid registered action instance and all discovered instances
for each matched descriptor pass ID, shortcut, and context validation; 54
physical non-empty `QKeySequence` instances exist across the discovered
actions; and no overlapping scoped bindings conflict. A missing descriptor or
action, unknown ID, mismatched registration, or conflicting registration
produces a nonzero exit status. The audit does **not** by itself prove behavior.

Behavior is checked independently:

| Harness | What it actually exercises |
|---|---|
| `--rollcheck … mus_shop` | Synthesized `Cmd+C/X/V/A/D`, Delete, all arrow-modifier families, `Cmd+1/2/3/4/5`, `+/-`, and `Z/X`; it verifies `Z` against both time and note selections and `X` against the full song, then checks Split and Join through their registered actions with document-state and undo restoration. |
| `--tabcheck … mus_shop mus_dewford` | Synthesized Space, Shift+Space, Home, `Cmd+L`, `Cmd+Shift+E`, `Option+Shift+F`, `Cmd+Z`, and `Cmd+Shift+Z`; it checks transport, MIDI event-list visibility and focus, per-tab document/audio/session routing, and active-tab undo routing. |

File-dialog commands are covered by registration and existing application
paths, not by these offscreen behavioral harnesses; the audit does not claim
otherwise.

