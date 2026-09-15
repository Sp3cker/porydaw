# Task 5 — Workspace MIDI Drop Orchestration

## Context

Join raw content drops to pure MIDI projection and atomic document append in the canonical workspace policy layer. Task 3 has already isolated the MIDI/new-song flow in `workspaceui_midi.cpp`; Tasks 1, 2, and 4 provide the consumed interfaces. Read [plan.md](plan.md) Global Constraints and [spec.md](spec.md) in full.

## Exact write set

- `src/ui/workspaceui.h`
- `src/ui/workspaceui.cpp`
- `src/ui/workspaceui_midi.cpp`

## Prerequisites

Tasks 1, 2, 3, and 4.

## Interface contract

- Add private `void WorkspaceUi::handleDroppedUrls(const QList<QUrl> &urls, SongTab *target)`.
- `WorkspaceUi::wireTab` connects each tab's `urlsDropped` with that emitting tab as the captured target.
- A local tab-widget adapter handles eligible drops on empty/non-Quick content and leaves the tab bar unclaimed.
- The private chooser and commit behavior match [spec.md](spec.md); no public dialog interface is added.

## Implementation steps

1. Add the smallest local `QTabWidget` drop adapter needed for empty/non-Quick content, and connect `SongTab::urlsDropped` in `wireTab`; route both to `handleDroppedUrls` with explicit target identity.
2. At entry, validate exactly one local case-insensitive `.mid`/`.midi` URL, captured open-project identity, `!projectBusy()`, no existing dialog operation or load/save transition, parse success, and at least one note-bearing track; an entry rejection must not show a chooser or mutate state.
3. Use the existing balanced dialog-operation pattern around only the private chooser: require `WorkspaceUi::m_dialogOps == 0`, increment to 1 and call `WorkspaceUi::updateOpenGate()` immediately before `exec()`, require exactly 1 on every return, then decrement to 0 and call `updateOpenGate()`. Retain only accepted value data outside the scope; clean every early return through the same scope without a second flag. Use `layout::` metrics and stable test `objectName`s; populate every source-order track name/channel row, destination availability/default, capacity-bounded prefix selection, and live confirmation validity.
4. After guard release, perform one same-turn final revalidation of captured project identity, `!projectBusy()`, `m_dialogOps == 0`, load/save state, selected indices, and destination gates. Append also revalidates the original `QPointer<SongTab>`, readiness, `bankActionsEnabled()`, and hardware slots. Abort through the normal error path if any gate changed; never call `submitCreateSong`, launch `NewSongWizard`, or mutate `SongDocument` while the chooser guard is held.
5. New Song uses `selectedMidiForNewSong` plus existing `NewSongWizard`/`submitCreateSong`. Append uses `appendImportedTracks` on the captured target, then activates that tab, selects the returned track, inspects `notesForTrack`, and uses existing `SongView::revealNote`/`ensureTickVisible` to reveal the earliest imported note at its rescaled tick. Preserve current player-budget warnings and source-file immutability.

## Acceptance predicate

Controller runs `deno task build:app` and `deno task verify --filter onboardcheck --verbose`, then launches the actual app for the valid Quick-content Append, one-step Undo/Redo, tab-bar rejection, interlock-change no-op, and no-viable-target New Song scenarios recorded in [plan.md](plan.md). All pass with no mutation on entry rejection, pre-commit rejection, or stale-target paths.

## Task-specific constraints

- Keep `MainWindow` unchanged.
- Do not add `Q_OBJECT` or a public header for the chooser.
- A stale captured target must not silently switch to the currently active tab.
- Do not bypass `projectBusy()`, balanced `m_dialogOps` plus `updateOpenGate()` acquisition/release, `bankActionsEnabled()`, or current project/load/save identity.
- Do not add the source branch's player-budget capacity gate or `NewSongWizard` overload.
