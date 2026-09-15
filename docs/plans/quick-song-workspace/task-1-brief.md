# T01 — Extract the explicit borrowed scene lifecycle

## Context

`TimelineQuickView` currently sole-owns a `QQuickView` per song and hands the
window to `SongTabQuickHost` via `takeWindowForEmbedding()`. This task converts
it into a borrowed-scene coordinator per [spec.md](spec.md) S3: the engine,
window and viewport item are supplied by an outer host; the coordinator owns
only its child context, popup session and canvas. Produces the
attach/detach/eligibility interface consumed by tasks 2 (viewport geometry), 3
(provider registration), 4 (popup session construction), 7
(`windowAboutToDetach`/item geometry), 8 (`isInputEligible`), 9 (explicit attach
in the retained adapter) and 10 (`checks::QuickSceneHost` uses S3 verbatim).

## Exact write set

- `src/ui/songview/quick/timelinequickview.h`
- `src/ui/songview/quick/timelinequickview.cpp`
- `src/ui/songview/quick/timelinequickview_window.cpp`

## Prerequisites

Frozen spec S3–S6.

## Interface contract

Per spec S3, `TimelineQuickView` gains exactly:

- `void attachScene(QQmlEngine &engine, QQuickItem &viewport)` — requires a live
  window on `viewport` and at most one attachment; duplicate attachment to the
  same viewport is inert; attaching elsewhere without detach is a programming
  error diagnosed through the existing construction-failure policy, never a
  silent fallback.
- `Q_INVOKABLE void attachToPage(QQuickItem *viewport)` — QML adapter only:
  obtains `qmlEngine(viewport)`, requires a completed item with window, calls
  `attachScene`; not a second implementation.
- `void detachScene()` — idempotent; reattachment supported.
- `QQuickItem *viewportItem() const` and `bool isInputEligible() const` —
  eligibility reads attached viewport + canvas effective enabled/visible/window
  association per S4, not a stored ready/selected flag.
- `windowAboutToDetach()` retains its spelling, now emitted once per live
  association before window/native teardown, reentry-safe; `viewportChanged()`
  retains its meaning for item geometry/association changes.

Removed declarations: `takeWindowForEmbedding()`, `detachWindow()`, the
owned-window members (`m_quickView`, `m_view` and the unhosted-window ownership
path), and root-window `setSource` unload behavior. The window-level
KeyPress/KeyRelease no-activeFocus fallback is deleted here per S4 (task 8 owns
the QML-side scope; nothing re-adds a dispatcher).
`embeddingFocusRequested(Qt::FocusReason)` is preserved unchanged for task 9;
task 21 deletes it — do not add a replacement signal.

`focusBand(TimelineBand, Qt::FocusReason)` and
`focusEventListInput(Qt::FocusReason)` retain names and parameters but return
false — emitting no focus or activation request — when the target item does not
exist OR the scene is not input-eligible; an actual eligible request still
returns true. This keeps background `setEventListVisible`/reload from stealing
focus.

## Implementation steps

1. Replace the owned-window construction path with nonvisual coordination only:
   constructor keeps existing parameters and creates no
   `QQuickView`/`QQmlEngine`. Add the S3 members above; `rootObject()` returns
   the canvas, `quickWindow()` borrows `viewport.window()` and is null while
   detached.
2. Implement `attachScene`: create a child `QQmlContext` parented to
   `engine.rootContext()` and QObject-owned by the coordinator; install the
   exact existing canvas context properties before `QQmlComponent` creation
   (never write page values into the shared rootContext); create
   `TimelineCanvas` as a coordinator-owned `QQuickItem` visually parented to
   `viewport`; match viewport dimensions and emit geometry updates from item
   width/height, association, screen/DPR.
3. Implement `detachScene` with the S3 ordering: stop scene timers; cancel
   popup/gestures/audition without focus restoration; clear key callbacks and
   interaction borrows; disconnect window/item associations; destroy popup
   session (including deferred popup QObjects) and canvas while model borrows
   live; clear the drawer provider borrow and remove the provider (task 3's
   contract); destroy the child context; clear root/viewport/window borrows.
   Never destroy the shared engine/window. Emit `windowAboutToDetach()` before
   losing the live native window.
4. Preserve detached-update semantics: retain/OR dirty domains and current
   domain state, suppress only publication without a scene, and perform a
   complete current-state publication on attachment. Window hide/deactivate and
   viewport effective hide/disable cancel page transients; reparenting to
   another window detaches the old association; viewport destruction is a
   guarded fallback detach.
5. Update `focusBand`/`focusEventListInput` per the interface contract and
   remove the window-level key fallback branch; keep all
   dirty-domain/layer/input-binding algorithms and domain-update entry points
   unchanged.

## Acceptance predicate

Detached updates reattach correctly and destroying one canvas leaves a borrowed
engine/window live; named checks `host-seams` and `host-integration` pass under
the gate-A run below. Local structural inspection is not a behavioral pass.

## Task-specific constraints

- No scene pooling, transfer machinery, lazy loading framework, or second
  attachment path beyond `attachToPage`'s adapter role.
- `attachToPage` is invoked once after component completion AND window
  association, independent of readiness; loading pages still have scenes but are
  disabled.
- Do not remove `embeddingFocusRequested` (task 21) and do not delete
  `quickengine.h` (task 6).

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
