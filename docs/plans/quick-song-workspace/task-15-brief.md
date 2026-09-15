# T15 — Embed one permanent Quick workspace in the retained shell

## Context

Gate B's single outer adapter: `WorkspaceQuickHost` owns the one QQuickView
embedded via one QWidget::createWindowContainer in the retained QWidget shell.
Consumed by task16 (WorkspaceUi owns the adapter, central widget becomes
`host.widget()`), task18 (MainWindow focus commands call its entry points
through WorkspaceUi), and task21 (explicit outer focus entry replaces the
deleted per-song signal). Consumes task13's SongTabsModel and task14's
WorkspaceSongs.qml root.

## Exact write set

- `src/ui/workspacequick/workspacequickhost.h`
- `src/ui/workspacequick/workspacequickhost.cpp`

## Prerequisites

Interfaces from tasks 13 (SongTabsModel) and 14 (QML root properties, signals
and entry functions).

## Interface contract

Per spec S1, exactly:

- `WorkspaceQuickHost(SongTabsModel &, QWidget &parent)`
- `QWidget *widget() const`
- `QQuickWindow *window() const`
- `void focusEditor(Qt::FocusReason)`
- `void focusTabs(Qt::FocusReason)`
- Signals: `selectRequested(SongTab *)`, `closeRequested(SongTab *)`,
  `moveRequested(SongTab *, int finalRow)`

The QObject signal conversion at the QML seam checks type; live-membership
validation is WorkspaceUi's job (task16), not the adapter's. The adapter builds
the appearance QVariantMap using the frozen keys and sources in spec S1. The QML
root receives writable required `appearance` through initial properties; the
same value interface remains usable by a future Quick outer shell.

## Implementation steps

1. Implement the constructor: retain existing module registration, create the
   QQuickView, and set the actual WorkspaceSongs root initial properties (`tabs`
   and `appearance`), and wrap it in one StrongFocus
   `QWidget::createWindowContainer` under the given parent. The container takes
   ownership of the window; the QQuickView is created exactly once.
2. Build the exact spec-S1 appearance map; install an application-instance event
   filter for ApplicationPaletteChange/ApplicationFontChange, following the
   existing PitchBendEditor path. Replace the loaded root's writable
   `appearance` via setProperty when the value changes; ignore other events. Do
   not invent context-property names or a theme-provider QObject.
3. Convert the QML root's
   `selectRequested/closeRequested/moveRequested(QtObject …)` signals into the
   typed C++ signals with a type check at the seam; no policy, page registry,
   manual page creation, resize loop, or selection policy in the adapter.
4. Implement `focusEditor`/`focusTabs` as explicit entry only, invoking the
   root's `enterEditor(reason)`/`enterTabs(reason)`; `focusEditor` may enter the
   editor-area scope while a selected song is loading but never focuses an
   ineligible child (spec S4).

## Acceptance predicate

One actual QWidget container embeds all song tabs, native focus entry works, and
ownership is single. NAMED CHECKS:
`deno task verify --filter mainwindow-routing --filter host-` (controller-run at
gate B).

## Task-specific constraints

- No per-song window, page registry, focus history, or selection policy in the
  adapter.
- Widget-specific entry points are deletable when the outer shell converts; do
  not add speculative future-shell API beyond the frozen interface.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
