## 1. Context

Task 13 projected core actions; Task 24 supplies positional/velocity commands. This completes the agreed Edit inventory without reorganizing unrelated menus.

## 2. Exact write set

- `src/mainwindow.cpp`
- `src/ui/transportbar.h`
- `src/ui/workspaceui.h`

## 3. Prerequisites

- [Task 24](task-24-brief.md).

## 4. Interface contract

Add narrow borrowed accessors TransportBar::goToStartAction/playAction/pauseAction/stopAction/loopAction and WorkspaceUi::findSongAction/transportBar, retaining existing playPauseAction/followPlayheadAction. MainWindow inserts those exact objects and the new EditActions commands into the specified groups.

## 5. Implementation steps

1. Expose only missing existing QAction getters; no new transport/search action construction or mirror callbacks. Add the borrowed WorkspaceUi::transportBar() accessor to reach TransportBar.
2. Complete Time, Notes, Loop, Events and Transport Edit groups and Find Song. Preserve existing locations for already exposed View/File/Help commands and native platform shortcut text.
3. Keep Play and Play/Pause distinct: Play resumes paused playback; Space restarts at edit cursor. Preserve transport priority over persistent Quick chrome.

## 6. Acceptance predicate

Every spec inventory command appears in its declared group and existing buttons/menu/keys share actual actions; Play versus Space retains its distinct paused behavior. Named checks: `deno task verify --filter mainwindow-routing --filter transportcheck --filter selftest-transport --filter selectionkey-window --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No Ableton research, shortcut browser or unrelated menu reorganization.
