# Keyboard shortcut audit

Audit of `feature/swift-qml-grid` on Windows, October 3, 2026, using Swift 6.4.0 and Qt 6.11.2. This covers the shipped command catalogue, shell registration and enablement, editor routing, local text commands, event navigation, scrollbar keys, and modal shortcut ownership.

## Findings and changes

- **Numeric Undo targeted the song.** With a note edit in history, typing in master volume and pressing Ctrl+Z undid the note while leaving the number unchanged. `DragInput.qml` now claims its implemented text shortcuts during Qt's ShortcutOverride phase. Undo, Redo and clipboard operations use `StandardKey` matching, including platform alternates; Ctrl+Shift+Z no longer falls through the raw Ctrl+Z Undo branch. Bare Space still reaches transport.
- **Event-list Home conflicted with transport Home.** A selected middle row did not move. The list now handles Home locally under its existing navigation gate; its duplicate window Shortcut was removed. End followed by Home visibly selects the last and first rows.
- **Scrollbar Home had the same ownership risk.** Scrollbars already implement Home locally, but the window binding would precede that handler. They now claim Home when scrollable. A regression scenario mounts them inside the production shell, where the transport shortcut also exists. This change was reviewed and built; the mounted scrollbar scenario was not executed on Windows.

Document Undo/Redo after both arrow transposition and mouse dragging worked in the tested feature-branch build. Returning focus from the numeric field to the roll restores song Undo. A focused text field owns its text history even when song history is available.

## Verification

The rebuilt production executable was launched and used. Observed Windows results:

- Drag a note in time and pitch, Ctrl+Z restores it, Ctrl+Y reapplies it.
- With song history enabled, numeric Ctrl+Z restores the draft and Ctrl+Shift+Z redoes it without changing the note.
- Numeric Select All, Copy, Cut and Paste retain text ownership with a note selected.
- Space starts and pauses playback from the numeric field. Numeric Home preserves the paused transport position.
- Ctrl+Shift+E switches to events; End selects the last event, Home selects the first.
- Ctrl+3 toggles triplet/straight grid; Ctrl+F focuses song search; S in search types text without Solo; search Ctrl+Z restores text.
- A, V and P toggle their respective drawers and toggle back.
- Ctrl+, opens Settings; Escape dismisses it.

`deno task build:app --release`, `deno task checks --verbose`, and `deno task format --check` succeeded. The Windows check runner reports **1 passed, 36 platform-skipped**; the supported check is production startup via `--version`. That check alone does not prove the GUI launches. UI verification above was performed separately.

New regression coverage is in `tst_ShellWindowShortcuts.qml`, `tst_ShellEventListKeyboardSelection.qml`, and `KeybindingRegistryChecks.swift`. The QML targets are currently built only on macOS; the Swift core harness is platform-limited. These new scenarios were not executed by the Windows runner. Existing suites cover the remaining editor operations, focus/selection ownership, gestures, and modal surfaces; their presence is not a claim that every shortcut was exercised here.

On a supported host, run:

```sh
deno task checks --filter swiftcore --verbose
deno task checks:shell --filter shellwindow-shortcuts --verbose
deno task checks:shell --filter shellwindow-editor-keys --verbose
deno task checks:shell --filter shell-event-list-keyboard-selection --verbose
deno task checks:shell --filter shellwindow-focus --verbose
deno task checks:qml-roll --filter swiftroll-window --verbose
```

## Catalogue review

All 67 registry entries were inspected against `ShellPresenter` and the editor router: 42 declare shortcut bindings, two are held modifiers, and 23 are unbound. No duplicate literal command sequences were found. Every command with a declared shortcut has a shell action. The held modifiers are consumed by gesture policies. The unbound `view.theme` entry has no shell action; it does not register a shortcut. The shell's extra `transport.resonance` action is also unbound.

`StandardKey` entries resolve Qt's platform bindings and alternatives at runtime. In the inspected Windows File menu, Close Tab shows Ctrl+F4 and Quit shows no shortcut; Ctrl+Q did not activate Quit. Native window closing uses Alt+F4. The table records the declarations rather than inventing bindings for unbound actions. Window shortcuts use Qt's native arbitration; editor commands use the selected tab's shared key router and command availability rules.

| Command ID | Binding declaration | Delivery |
| --- | --- | --- |
| `file.open_project` | Qt StandardKey open | Window |
| `file.new_song` | Qt StandardKey new | Window |
| `file.import_midi` | Unbound | Window |
| `file.save_song` | Qt StandardKey save | Window |
| `file.register_song` | Unbound | Window |
| `file.close_tab` | Qt StandardKey close | Window |
| `file.export_wav` | Unbound | Window |
| `file.quit` | Qt StandardKey quit | Window |
| `edit.undo` | Qt StandardKey undo | Window |
| `edit.redo` | Qt StandardKey redo | Window |
| `edit.insert_time` | Ctrl+Shift+I | Window |
| `edit.delete_time` | Unbound | Window |
| `edit.clear_time_selection` | Unbound | Editor router |
| `edit.preferences` | Qt StandardKey preferences; fallback Ctrl+, | Window |
| `edit.song_settings` | Unbound | Window |
| `edit.engine_settings` | Unbound | Window |
| `edit.set_velocity` | Unbound | Editor router |
| `edit.set_loop_start` | Unbound | Editor router |
| `edit.set_loop_end` | Unbound | Editor router |
| `edit.loop_from_selection` | Unbound | Editor router |
| `edit.remove_loop` | Unbound | Editor router |
| `edit.edit_time_signature` | Unbound | Editor router |
| `edit.remove_time_signature` | Unbound | Editor router |
| `view.theme` | Unbound | Window |
| `view.event_list` | Ctrl+Shift+E | Window |
| `view.note_names` | Unbound | Window |
| `view.automation_drawer` | A | Window |
| `view.velocity_drawer` | V | Window |
| `view.voice_changes_drawer` | P | Window |
| `view.polyphony_debugger` | Ctrl+Shift+P | Window |
| `tools.import_sample` | Unbound | Window |
| `transport.go_to_start` | Home | Window |
| `transport.play` | Unbound | Window |
| `transport.play_pause` | Space | Window |
| `transport.pause` | Unbound | Window |
| `transport.stop` | Unbound | Window |
| `transport.loop` | Unbound | Window |
| `transport.follow_playhead` | Unbound | Window |
| `songs.find` | Qt StandardKey find | Window |
| `help.about` | Unbound | Window |
| `roll.copy` | Qt StandardKey copy | Window |
| `roll.cut` | Qt StandardKey cut | Editor router |
| `roll.duplicate_time` | Ctrl+D | Editor router |
| `roll.split` | Ctrl+E | Editor router |
| `roll.join` | Ctrl+J | Editor router |
| `roll.paste` | Qt StandardKey paste | Editor router |
| `roll.select_all` | Qt StandardKey selectAll | Editor router |
| `roll.delete` | Delete or Backspace | Editor router |
| `roll.pitch_bend` | G | Editor router |
| `roll.transpose_up` | Up | Editor router |
| `roll.transpose_down` | Down | Editor router |
| `roll.transpose_up_octave` | Shift+Up | Editor router |
| `roll.transpose_down_octave` | Shift+Down | Editor router |
| `roll.nudge_left` | Left | Editor router |
| `roll.nudge_right` | Right | Editor router |
| `roll.lengthen_note` | Shift+Right | Editor router |
| `roll.shorten_note` | Shift+Left | Editor router |
| `roll.grid_widen` | Ctrl+2 | Editor router |
| `roll.grid_narrow` | Ctrl+1 | Editor router |
| `roll.grid_triplet` | Ctrl+3 | Editor router |
| `roll.mute_tracks` | M | Editor router |
| `roll.solo_tracks` | S | Window |
| `roll.velocity_drag` | Hold Control | Gesture modifier |
| `velocity.detent_unlock` | Hold Control | Gesture modifier |
| `automation.pencil_mode` | B | Editor router |
| `eventlist.move_up` | Alt+Up | Editor router |
| `eventlist.move_down` | Alt+Down | Editor router |

## Local keys and ownership

| Surface | Local keys and policy |
| --- | --- |
| Event list | Up/Down, Shift+Up/Down, Left/Right, Home/End, PageUp/PageDown, F2, Return/Enter. Navigation is disabled during cell editing and menus. Select All/Delete target event rows; Alt+Up/Down reorder eligible same-tick events. |
| Numeric inputs | Digits and leading minus where permitted, selection/caret movement, Backspace/Delete, platform text clipboard and history commands. Adjusting inputs also handle arrows and page steps. Return/Enter commits. Bare Space yields to transport. |
| Literal text fields | Qt owns text editing, clipboard, text history and literal Space. |
| Timeline scrollbars | Axis arrows and PageUp/PageDown scroll; cross-axis arrows are consumed without editing notes; Home/End move to bounds. Home overrides transport only while this scrollable control has focus. |
| Persistent buttons and drawer chrome | Enter/Return activate; bare Space reaches transport. |
| Menus and prompts | Their modal key handlers arbitrate local navigation, acceptance and cancellation. They intentionally prevent background edits. |
| Pitch-bend popup | Local popup keys; song Undo/Redo may pass through when a numeric editor does not own them. |
| Sample Studio | Its separate modal window has its own standard Undo/Redo and explicit audition keys. |

## Scope limits

The user's previously open executable came from `feature/v7`; this audit rebuilt `feature/swift-qml-grid`. The relevant history and key catalogue code agreed between those worktrees when inspected. Changes are committed to the feature branch and need to be pulled and rebuilt by another worktree before that executable contains them.
