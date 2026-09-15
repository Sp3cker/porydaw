# T18 — Preserve native window commands without queued focus repair

## Context

Gate B keeps MainWindow's window-level command surface working over the new
workspace while deleting QTabWidget-era focus repair. Produces the Registry
window commands consumed by task20 (real QAction/tab/text precedence checks) and
task24 (documented gestures); consumes task15's host entry points, task16's
`selectAdjacentSongTab`/`focusSongTabs`, and task17's window-free sessions.
Scope is MainWindow/Registry only: the explicit accepted user-open focus entry
belongs to WorkspaceUi (task16, `openSongFromList`), not here — no new focus
dispatcher or reason flag.

## Exact write set

- `src/mainwindow.cpp`
- `src/ui/keymap.cpp`

## Prerequisites

Interfaces from tasks 15 (focus entry), 16 (adjacent selection and audio
handoff), and 17 (window-free SongTab).

## Interface contract

Per spec S4, exactly:

- New keymap Registry window commands: `view.next_song_tab`
  (QKeySequence::NextChild), `view.previous_song_tab`
  (QKeySequence::PreviousChild), `view.focus_song_tabs` (F6).
- Their QActions attach to the existing MainWindow; the first two call
  `selectAdjacentSongTab(+1)`/`selectAdjacentSongTab(-1)`, the third
  `focusSongTabs`. They replace QTabWidget's implicit next/previous navigation
  and provide explicit accessible strip entry.
- No duplicate QML shortcuts. Existing `file.close_tab` and transport actions
  stay unchanged. Popup/text ShortcutOverride arbitration remains intact.
  Empty/single-tab navigation is inert as appropriate.

## Implementation steps

1. In keymap.cpp: register the three window commands with the exact ids and
   QKeySequence standard keys above.
2. In mainwindow.cpp: create/attach the three QActions to MainWindow and wire
   them to the WorkspaceUi helpers; keep the existing selected/audio/ready
   handlers and registry actions.
3. Remove the QTabWidget-era singleShot focus restoration; explicit user
   browser-open/selection editor entry uses the WorkspaceUi focus seam (task16
   owns `openSongFromList`), never late/background-ready restoration.
4. Preserve startup song-list focus and the existing QWidget text/popup
   arbitration; do not alter EditActions or
   `EditActions::installWindowShortcuts(QWidget&)` — the outer shell still
   contains QWidget controls.

## Acceptance predicate

Real QAction Space vs text exception, F6/arrows/Enter, and selected audio
handoff work without timers. NAMED CHECKS:
`deno task verify --filter mainwindow-routing --filter selectionkey`
(controller-run at gate B).

## Task-specific constraints

- No queued focus repair, focus dispatcher, or new reason flag; no
  forceActiveFocus on selection/ready/reorder/popup-cancel/activation/timer
  paths.
- Existing MainWindow widget text controls, transport actions, QWidget
  dialogs/docks intentionally unchanged (plan non-changes).

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
