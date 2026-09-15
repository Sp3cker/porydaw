# T16 — Cut workspace collection and selection over atomically

## Context

Gate B's core cutover: WorkspaceUi stops using QTabWidget and becomes the sole
owner of the session vector, the SongTabsModel, and the WorkspaceQuickHost.
Produces the WorkspaceUi interface consumed by task17 (SongTab becomes a
window-free QObject session — task17's new parent/ownership shape is what
enables task22's fixture migration), task18 (MainWindow registry actions call
`selectAdjacentSongTab`/`focusSongTabs`), and task15's host (constructed and
destroyed here). Also owns the explicit accepted user-open focus entry:
`openSongFromList` (in workspaceui_tabs.cpp) enters the editor area even while
loading, with no delayed ready-focus.

## Exact write set

- `src/ui/workspaceui.h`
- `src/ui/workspaceui.cpp`
- `src/ui/workspaceui_tabs.cpp`

## Prerequisites

Interfaces from tasks 13 (SongTabsModel notifications) and 15
(WorkspaceQuickHost).

## Interface contract

Per spec S1/S2, exactly:

- Owns `std::vector<std::unique_ptr<SongTab>> m_tabPages` and
  `SongTab *m_selectedTab` — the one display/persistence order; constructs
  SongTab without a QObject parent (unique_ptr owns it).
- Retains `selectSongTab(SongTab *)`; adds
  `moveSongTab(SongTab *, int finalRow)`, `selectAdjacentSongTab(int step)`,
  `focusSongEditor(Qt::FocusReason)`, `focusSongTabs(Qt::FocusReason)`.
- Grants `SongTabsModel` friendship; adds private
  `QString tabTitle(const SongTab &) const` (exact document-dirty label in S2).
- Keeps existing private `selectTab`, create/remove/close helpers, persistence
  and staged-update handlers. `publishSelectedIfChanged` may be removed once it
  has no widget-derived input; no compatibility alias.
- Mutation choreography per spec S2 verbatim: ordinary switch (cancel outgoing
  transient input/popup without forced focus restoration; change m_selectedTab;
  synchronously emit selectedSongTabChanged; notify model identity/index;
  rebuild dependent chrome and persist under existing suppression; no scene
  detach); selected close (cancel transient input; successor = next row else
  previous else null; synchronous successor/audio handoff while old
  session/lease is live; detach old scene; beginRemove, retire unique_ptr to a
  local, erase row, endRemove, publish successor index, then destroy retired
  session); full teardown (publish null/unload audio first; suppress
  intermediate selection/persistence; detach all scenes while models live;
  remove rows under valid notifications; destroy sessions; only then destroy
  workspace window/engine). Never a model reset for ordinary close/reorder.

## Implementation steps

1. In workspaceui.h: replace QTabWidget-era members with the vector/selected
   pointer, SongTabsModel and WorkspaceQuickHost members; add the new public
   helpers, `tabTitle`, and model friendship.
2. In workspaceui.cpp buildUi/destructor: construct model then host; central
   widget becomes `host.widget()`; teardown follows the S2 ordering above
   (sessions/scenes before the adapter).
3. In workspaceui_tabs.cpp: rewrite
   createTab/removeTab/destroyAllTabs/selectTab/persistTabs over vector identity
   with model notifications bracketing each actual mutation; vector order drives
   persistence.
4. Implement `moveSongTab`, `selectAdjacentSongTab`, `focusSongEditor`,
   `focusSongTabs`; adjacent window commands wrap cyclically as S4 specifies.
   Selection requests validate live QObject membership before dereferencing a
   possibly stale pointer.
5. Update restore/cancel/save/staged-update paths without changing project
   policies; `openSongFromList` performs explicit accepted user-open editor
   entry via `focusSongEditor` (enter editor-area scope even while loading; no
   delayed ready focus). Background open and late readiness never steal
   selection or focus. Emit audio selection synchronously before old lease
   destruction.

## Acceptance predicate

Background/selected close, dirty cancellation, restore and reorder preserve
selection/session/audio/persisted state. NAMED CHECKS:
`deno task verify --filter tabcheck --filter sessioncheck --filter selftest-workspace --filter mainwindow-routing`
(controller-run at gate B).

## Task-specific constraints

- No new focus dispatcher, reason flag, or queued focus repair; explicit
  user-open entry only.
- Existing restore, replacement/new-tab, dirty-close/save cancellation,
  closed-load tombstones and bank handoff remain unchanged.
- No selection signal on reorder of the same selected object.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
