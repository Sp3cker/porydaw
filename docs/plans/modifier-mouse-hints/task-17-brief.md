# Context

Integrate source/scoping interfaces and guarded window recovery in the existing view without mirrored popup state. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/songview/quick/timelinequickview.h`
- `src/ui/songview/quick/timelinequickview.cpp`
- `src/ui/songview/quick/timelinequickview_window.cpp`

# Prerequisites

Tasks 4+15 and 16; dispatch with Task 5 under its fixed owns/isOpen contract.

# Interface contract

Move creation of the existing QuickPopupSession before setSource. Set mouseHints and quickPopupSession root-context properties there. Use existing borrowed m_inputItems, m_gutterInputItems, m_eventListInput and five m_drawerChromeInputs. Add only private requestMouseHintRecovery(ui::MouseHints *) and m_mouseHintRecoveryQueued; the exact queue, lifetime and delivery guards are in spec.md's Guarded Quick membership recovery contract. No public view API or new item list.

# Implementation steps

1. Create the session against the already-created QQuickView before root QML loading; preserve parent, existing focus/session connections and later teardown.
2. Expose both real QApplication-owned service and existing session through the root context before setSource; no SongView/MainWindow ancestry lookup or optional missing-context fallback.
3. Connect isOpenChanged to mute/unmute every existing borrowed physical host. On unmute resync current idle hover and request guarded recovery; on MouseHints::scopeRefresh do both through the same existing hosts. Native recovery must also reach owned children of a surviving Quick popup.
4. Implement the private recovery helper in timelinequickview_window.cpp: coalesce one context-bound queued callback; capture a guarded service borrow; use m_view and m_detachStarted; recheck every specified guard/current cursor immediately before stack-local sendEvent. Never post a prevalidated event, force lower-item membership, restore cached targets or retry by polling.
5. Keep connections tied to the view/guarded borrows so detach/destruction cannot call stale items. Preserve scene/provider wiring, popup ownership and every existing view interface.

# Acceptance predicate

The atomic 5+17 wave loads existing main/popup QML without missing context, suppresses covered hints and restores the actual C++/QML target after ordinary stationary dismissal, preserving higher-leaf ownership and existing drag behavior. The guarded callback mechanism remains specified; an artificially interleaved gesture is not a mandatory permanent case. Controller: deno task verify --filter host-seams --filter host-integration --filter mainwindow-routing --filter selectionkey --verbose, plus popup/lifecycle native rows.

# Task-specific constraints

No mirrored popupHintBlocked property, dynamic discovery/registry, source string relay or active pointerMove. Only the spec's guarded idle MouseMove exception is allowed; no click/press/release/wheel/key replay.
