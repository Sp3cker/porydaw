# task-4-brief.md — Enforce the frozen Songs-panel visual pins

## Context

The frozen comparator and legacy `songlist/{vanilla,darkneutralhigh}` fixtures already exist. Make them executable against the QML panel at native 2x scale and both retained font profiles. Extract the window's existing theme-to-`GridPalette` mapping so production and visual checks push identical colors; do not alter the comparator or fixtures.

## Exact write set

- `CMakeLists.txt` — add the shared palette helper to `porydaw_app`.
- `src/ui/theme/gridpalette.h` / `.cpp` — new `themes::pushGridPalette(QObject *)` implementation.
- `src/app/RewriteWindow.cpp` — replace the inline palette mapping with the shared helper.
- `src/checks/visual/visualbaseline.h` — declare the new visual-suite runner.
- `src/checks/visual/swiftpanels.cpp` — new Songs-panel visual scenarios and QML-local fixture.
- `src/checks/checkcatalog.cpp` — register the two visual-swift profiles.
- `src/checks/CMakeLists.txt` — compile `visual/visualbaseline.cpp` and `visual/swiftpanels.cpp` into `porydaw_checks`.

## Prerequisites

Task 3's production `SongsPanel.qml`, item-view `GridPalette` properties, and host palette updates. It shares `CMakeLists.txt`, `src/checks/CMakeLists.txt`, and `RewriteWindow.cpp` with task 3; run it after task 3 rather than concurrently.

## Interface contract

- `themes::pushGridPalette(QObject *palette)` moves the existing mapping and its `withRelativeAlpha`, `mixToward`, and color-format helpers from `RewriteWindow::applyGridPalette` without changing values or behavior. Keep the host's null/session guards and `reloadVisuals` tail; `applyGridPalette` calls the shared helper.
- `runVisualSwiftPanelsCheck(QApplication &application, const QStringList &qtArguments)` owns `checks::visual::prepare(application)` and the QtTest run. On `__APPLE__`, catalog entries `visual-swift-12` and `visual-swift-16` use `HandlerOwned`, `WindowSystem`, `ScratchKind::Unused`, and `FixtureRootKind::None`; both pass `--visual-swift-panels`, set `PORYDAW_AUDIO_BACKEND=null` and `PORYDAW_VISUAL_SCREEN_DPR=2`, and set `PORYDAW_VISUAL_FONT_PX` to their respective profile. The entries use the frozen `macos-dpr2-font12` and `macos-dpr2-font16` fixtures, respectively.
- The visual-only inline QML fixture supplies the panel's rows and category model with the exact legacy `visualSongs()` data from `src/checks/visual/chrome.cpp`: IDs 0–9 in order for `mus_route101`, `mus_petalburg`, `mus_gym`, `mus_surf`, `mus_victory_wild`, `se_fanfare_1trk`, `se_pc_login`, `se_use_item`, `mus_stray_unregistered` (unregistered, no registration gaps), and `mus_partial_entry` (registered, gap `song_table.inc`). All are playable, constants are uppercased labels, player is `MUSIC_PLAYER_BGM`, and ID 1 is selected/current. Match `SongListPresenter`'s initial visible state: category choices `All (10)`, `Music (mus_) (7)`, `Sound effects (se_) (3)`, category All, ID sort, empty search, and count `10 songs`; use its exact warning and gap row roles. Use a real `ApplicationSession` palette; do not add a production presenter-seeding API for screenshots. The existing SwiftCore presenter proofs cover behavior.
- Pass production `SongsPanel` a check-local inline-QML `QtObject` as its `applicationSession` input: `songList` is the static visual fixture and `palette` forwards from a real `ApplicationSession`. This exercises the production visual component without seeding or faking the service/presenter.
- Capture at the exact frozen image dimensions: `visual-swift-12` / `macos-dpr2-font12` uses 280×480, and `visual-swift-16` / `macos-dpr2-font16` uses 348×480; both use native DPR 2. Compare both `songlist/vanilla` and `songlist/darkneutralhigh` with initial unfiltered, ID-sorted list state.
- Produce the exact frozen 14-region name set: `songList`, `songListCategory`, `songListCount`, `songListSearch`, `songListSort`, `songs.search`, `songs.category`, `songs.sort`, `songs.list`, `songs.count`, `songs.row.first`, `songs.row.second`, `songs.row.unregistered`, and `songs.row.partial`. The first five names and row indices are grounded in the legacy region builder at `src/checks/visual/chrome.cpp:224-256`; preserve every frozen bound.

## Implementation steps

1. Move the complete `RewriteWindow::applyGridPalette` color mapping and its helper calculations into `src/ui/theme/gridpalette.cpp`; preserve the host guard, null-palette failure behavior, and visual reload after the push. Register the source/header in the root `porydaw_app` target.
2. Add `visual/visualbaseline.cpp` and `visual/swiftpanels.cpp` to `porydaw_checks`. Declare `runVisualSwiftPanelsCheck` in `visualbaseline.h`, include that header from `checkcatalog.cpp`, and add the two `__APPLE__` catalog entries there.
3. In `swiftpanels.cpp`, define QtTest slots `songPanelVanilla` and `songPanelDark`. Prepare the canonical Fusion/font environment, apply vanilla or dark-neutral-high theme, instantiate production `SongsPanel.qml` at its profile's frozen capture dimensions (280×480 at font 12; 348×480 at font 16) with the check-local presentation adapter, show the native `QQuickView`, await a frame, derive regions from the named controls and four visible rows, then call `checks::visual::compare` with the frozen IDs. Keep this render fixture local to the visual check; do not alter production service/presenter behavior.
4. Register `visual-swift-12` and `visual-swift-16` as separate native-windowed handlers with the profile environment above. `deno task verify --filter visual-swift --verbose` must select both entries and run both slots at each font profile.

## Acceptance predicate

- `deno task verify --filter visual-swift --verbose` selects `visual-swift-12` and `visual-swift-16`; each runs `songPanelVanilla` and `songPanelDark`, passing all four comparisons: vanilla and dark-neutral-high at font 12 and font 16, each at native DPR 2. The checks enforce exact image size/DPR, exact region-name set and bounds, channel tolerance 2, per-region 0.5% mismatch budget capped at 64 pixels, and uncovered-area 0.5% budget capped at 256 pixels. A connected native 2x display is required.

## Task-specific constraints

- Do not edit `visualbaseline.cpp` comparison policy or any frozen `src/checks/fixtures/visual/**/songlist/{vanilla,darkneutralhigh}.{json,png}` fixture. Never set `PORYDAW_RECORD_VISUAL_BASELINES` for acceptance.
- Do not claim the visual fixture exercises service/presenter behavior; the existing SwiftCore checks own those contracts.
- Keep the palette extraction behavior-only: no role rename or changed theme mapping beyond the item-view roles task 3 adds.
