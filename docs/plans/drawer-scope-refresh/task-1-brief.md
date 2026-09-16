# Task 1 — Scope enum and SongView fan-out rewrite

## 1. Context

Introduce `DrawerScope`/`DrawerScopes` in `src/ui/editordrawer/drawerpage.h` and rewire every
`refreshDrawerPages`/`refresh*Page`/`refreshAllDrawerPages` call site to pass the scope set
named in plan.md's emission table. Pages keep their existing `refreshLiveState` bodies for
this task: each page gains a `refresh(DrawerScopes)` entry point that reconstructs the
current snapshot from live sources and forwards to `refreshLiveState`, so behavior is
bit-identical while the routing lands. Tasks 2 and 3 delete the forwarders and the snapshot.

## 2. Exact write set

- `src/ui/editordrawer/drawerpage.h`
- `src/ui/songview/drawercoordination.cpp`
- `src/ui/songview/camera.cpp`
- `src/ui/songview/grid.cpp`
- `src/ui/songview/viewstate.cpp`
- `src/ui/songview.cpp`
- `src/ui/songview.h`
- `src/ui/editordrawer/automationpage.h`, `automationpage.cpp` (forwarder only)
- `src/ui/editordrawer/velocityarea/velocityarea.h`, `velocityarea.cpp` (forwarder only)
- `src/ui/editordrawer/voicechangearea/voicechangearea.h`, `voicechangearea.cpp` (forwarder only)

## 3. Prerequisites

None.

## 4. Interface contract

```cpp
// drawerpage.h — DrawerPageLiveState/DrawerPagePlaybackState stay until tasks 2–3.
enum class DrawerScope : quint8 {
    Document         = 1u << 0,
    Content          = 1u << 1,
    Selection        = 1u << 2,
    HorizontalScroll = 1u << 3,
    Zoom             = 1u << 4,
    Playhead         = 1u << 5,
};
Q_DECLARE_FLAGS(DrawerScopes, DrawerScope)
Q_DECLARE_OPERATORS_FOR_FLAGS(DrawerScopes)
```

```cpp
// SongView (songview.h) — signatures change; names stay.
void refreshDrawerPages(DrawerScopes scopes);
void refreshAutomationPage(DrawerScopes scopes);
void refreshVelocityPage(DrawerScopes scopes);
void refreshVoiceChangePage(DrawerScopes scopes);
void refreshAllDrawerPages(DrawerScopes scopes);
bool playing() const noexcept { return m_playing; }   // new public accessor
```

```cpp
// Each page gains, beside the unchanged refreshLiveState:
void refresh(DrawerScopes scopes);   // builds the live snapshot, forwards
```

`drawerPageLiveState()` stays private to `drawercoordination.cpp` and is now called only by
the page forwarders' shared helper — or keep it as the forwarder body: `refresh(scopes)`
ignores `scopes` and calls `refreshLiveState(drawerPageLiveState())` via the owner. Either
shape is acceptable; the forwarder must not read `scopes` (tasks 2–3 consume it).

## 5. Implementation steps

1. Add the enum + flag operators to `drawerpage.h`; include `<QFlags>`/`<Qt>` as needed.
2. Add `SongView::playing()` next to `playheadTick()` (`songview.h:272`).
3. Change the five refresh signatures in `songview.h:805-808,667` and
   `drawercoordination.cpp:169-210` to take `DrawerScopes` and pass it through to the page
   `refresh` methods. Visibility gating in `refreshDrawerPages` is unchanged.
4. Update every call site per the plan.md emission table:
   `songview.cpp:257` (`HorizontalScroll|Zoom`), `:809` (`Document`), `:990` (`Selection`),
   `:999` (`Selection`), `:1002` (`Content`), `:1087-1090` (`Content`), `:1175` (`Content`);
   `camera.cpp:42,60` (`Zoom`), `:100` (`HorizontalScroll`); `grid.cpp:385` (`Content`);
   `viewstate.cpp:204` (`Content`), `:232` (`Content`);
   `drawercoordination.cpp:166` (`Content`).
   `refreshAllDrawerPages` callers (`automationpage.cpp:252`, `voicechangearea.cpp:554`,
   `voicechangemenu.cpp:263,317`) pass `Content` — those files join the write set only for
   the argument.
5. Add `refresh(DrawerScopes)` to each page: body calls `refreshLiveState` with the owner's
   current `drawerPageLiveState()` (or the per-page equivalent live reads). Do not touch the
   `refreshLiveState` bodies, `m_live`/`m_liveState`, `sameLiveState`, or `liveState()`.
6. `setPlayheadSample`'s direct `presentPlayhead` calls (`songview.cpp:1092-1095`) are
   unchanged.

## 6. Acceptance predicate

- `deno task build:checks` compiles.
- `deno task verify --filter editor-drawer --filter scrollbar --verbose` passes — covers
  drawer surface lifecycle and scroll routing through the rewired fan-out.
- `deno task verify --filter velocity-page --filter automation-presentation --verbose`
  passes — proves the forwarders preserve every existing refresh branch.
- No page stores new state; `refreshLiveState` bodies are byte-identical.

## 7. Task-specific constraints

- The forwarder is scaffolding for exactly one task boundary; tasks 2–3 delete it. Do not
  "improve" it into a real handler.
- `DrawerPageLiveState`, `DrawerPagePlaybackState`, `sameLiveState` remain in this task.
