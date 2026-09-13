# Keyboard Shortcuts

## Fixed shortcuts

Shortcuts are fixed platform defaults. There is no remapping interface, no
Keyboard settings page, and no shortcut browser: every menu, context menu,
and key press invokes the same underlying command, and menus always display
the real platform-native binding.

Each command has one of two scopes:

- **Window scope**: the shortcut works anywhere in the application window,
  including while timeline controls have keyboard focus.
- **Editor scope**: the key is routed to the active editor after local input
  arbitration. Text and IME entry, modal prompts, popup navigation,
  event-list row keys, deliberate keyboard controls, and audition surfaces
  keep their keys locally; an editor command only fires when no protected
  local input claims it.

Menu rows show a command's enabled state from the committed selection and
edit cursor. A context menu closes itself when the selection, track scope,
or edit cursor it was opened against changes; reopening it rebuilds the menu
from current state.

On macOS, `Ctrl` corresponds to the `Cmd` key (Command).

## Default shortcuts

### Piano Roll

| Command | Default Shortcut | Description |
| --- | --- | --- |
| Duplicate time | `Ctrl+D` | Duplicates active time selection and advances selection |
| Copy Selection | `Ctrl+C` | Copies selected notes or active time range; also preserves ordinary text copying |
| Cut Selection | `Ctrl+X` | Cuts selected notes or clears the **contents** of an active time range (contents-only; time never shifts) |
| Paste at Edit Cursor | `Ctrl+V` | Pastes clipboard content at the edit cursor |
| Select All Notes | `Ctrl+A` | Selects all notes on the active track |
| Delete Selection | `Delete` / `Backspace` | Deletes selected notes, or clears the **contents** of an active time range without shifting later events (contents-only; time never collapses) |
| Transpose Up (Semitone) | `Up` | Transposes selection up by 1 semitone |
| Transpose Down (Semitone) | `Down` | Transposes selection down by 1 semitone |
| Transpose Up (Octave) | `Shift+Up` | Transposes selection up by 1 octave |
| Transpose Down (Octave) | `Shift+Down` | Transposes selection down by 1 octave |
| Nudge Left | `Left` | Nudges active time selection left by grid step |
| Nudge Right | `Right` | Nudges active time selection right by grid step |
| Edit Note Pitch Bend | `G` | Opens the pitch-bend editor for the selected note |
| Mute Selected Tracks | `M` | Toggles mute on selected track(s) |
| Solo Selected Tracks | `S` | Toggles solo on selected track(s) |
| Toggle Pencil Mode | `B` | Toggles automation pencil drawing on the automation page |
| Move Event Up / Down (Same Tick) | `Alt+Up` / `Alt+Down` | Reorders the current event-list row within its tick |
| Clear Time Selection | *(unbound)* | Clears the active time selection band |
| Set Velocity… | *(unbound)* | Opens the velocity prompt for the resolved selected notes |
| Set Loop Start / End at Edit Cursor | *(unbound)* | Places loop markers at the edit cursor |
| Loop from Time Selection / Remove Loop Markers | *(unbound)* | Creates loop markers from the active interval, or removes them |
| Edit / Remove Time Signature at Edit Cursor | *(unbound)* | Edits the signature at the cursor, or removes an explicit signature event there |
| Adjust Velocity | `Ctrl` + vertical drag | Adjusts note velocity by holding the modifier and dragging a note |
| Unlock Detents | `Ctrl` (hold) | Unlocks continuous velocity detents in the velocity editor while held |

### Transport

| Command | Default Shortcut | Description |
| --- | --- | --- |
| Play/Pause | `Space` | Starts playback from the edit cursor, or pauses |
| Play | *(unbound)* | Transport button: resumes a paused transport |
| Go to Start | `Home` | Moves playhead to the beginning of the song |
| Pause / Stop / Toggle Loop / Follow Playhead | *(unbound)* | Transport bar and menu actions |

### Edit

| Command | Default Shortcut | Description |
| --- | --- | --- |
| Insert Time | `Ctrl+Shift+I` | With an active time selection, inserts a silent gap the length of the selection immediately; otherwise opens a bars/beats/fractions prompt that inserts across the whole song at the edit cursor, even while playing |
| Delete Time (Shift Left) | *(unbound)* | Removes the active time selection's span and shifts later scoped content left; no-op without a selection. Ordinary `Delete`/`Backspace` still clear selection **contents** without shifting time |
| Undo | `Ctrl+Z` | Undoes the last action |
| Redo | `Ctrl+Y` / `Ctrl+Shift+Z` | Redoes the previously undone action |
| Find Song | `Ctrl+F` | Focuses song search; also under Edit → Find Song |
| Preferences | `Ctrl+,` | Opens application preferences |
| Song Settings / Engine Settings | *(unbound)* | Open the respective settings dialogs |

### View

| Command | Default Shortcut | Description |
| --- | --- | --- |
| MIDI Event List | `Ctrl+Shift+E` | Toggles the MIDI event list view |
| Automation Drawer | `A` | Toggles the automation drawer |
| Velocity Drawer | `V` | Toggles the velocity drawer |
| Voice Changes Drawer | `P` | Toggles the voice-changes drawer |
| Polyphony Debugger | `Ctrl+Shift+P` | Toggles the polyphony debugger |
| Theme / Color Notes by Velocity / Show Note Names | *(unbound)* | View menu toggles |

### File

| Command | Default Shortcut | Description |
| --- | --- | --- |
| New Song | `Ctrl+N` | Creates a new song |
| Open Project | `Ctrl+O` | Opens an existing project |
| Save Song | `Ctrl+S` | Saves the current song |
| Close Tab | `Ctrl+W` | Closes the current song tab |
| Quit | `Ctrl+Q` | Quits the application |
| Import MIDI / Register Song / Export WAV | *(unbound)* | File menu actions |

### Tools and Help

| Command | Default Shortcut | Description |
| --- | --- | --- |
| Import Sample | *(unbound)* | Imports an audio sample |
| About porydaw | *(unbound)* | Shows the about dialog |
