# Context
Implement the real Swift tab collection consumed by task 2 and the existing native host. Read plan.md Global Constraints and Spec first.

# Exact write set
- src/ui/songview/quick/swift-grid-prototype/SongTabsController.swift (new)
- src/ui/songview/quick/swift-grid-prototype/App.swift

# Prerequisites
Frozen task 4 collection move interface; tasks can be written concurrently.

# Interface contract
@MainActor @QtBridgeable final class SongTabSession exposes tabId: Int, title: String, and @QtTracked grid: PianoGrid. IDs monotonic, never reused. SongTabsController exposes tabs: QListModel<SongTabSession>, selectedId: Int (-1 empty), selectedIndex: Int (-1 empty), tabCount: Int, pendingCloseId: Int (-1 none). These are controller-written observable properties. Public slots: openTab(), selectTab(tabId: Int), moveTab(tabId: Int, destinationIndex: Int), requestClose(tabId: Int), confirmDiscard(), cancelClose(). QML calls remain positional; Swift labels follow the supported existing QtBridge macro pattern. QListModel.move(from:to:) accepts final destination index. Controller starts with one fixture-backed session, never a dummy hidden session. Read-only native selectedGrid accessor may be optional and @QtIgnored; it is not a QML object registry.

# Implementation steps
1. Own each grid in its session, reuse PianoGrid initializer/fixture unchanged. Publish collection/selection once per semantic operation. IDs rather than indices identify requests. Do not duplicate the tab list.
2. Use real move notifications from task 4, not remove/insert/reset. Keep selected identity and update selectedIndex after moving.
3. Close clean pages immediately; grid.canUndo denotes dirty relative to initial demo state. Dirty pages expose pendingCloseId and await Discard/Cancel. No simulated Save. Closing background leaves current identity; current close selects next at same index or previous last. Closing last yields genuinely empty collection. Selection change stops outgoing audio and calls existing inputCancelled(hidden). No window/item access or focus code.
4. App initialProperties supplies songTabs controller. App bootstrap opens two additional existing fixture-backed sessions after the controller's initial one, then selects the original first session. This is unconditional demo fixture setup, not a new user-facing feature or a smoke-environment branch. Existing native cancel callback calls current selected grid with original reason. Preserve math/policy/grid-smoke initialization, no second event filter. No grid type or audio engine rewrites.

# Acceptance predicate
Host fixture open/reopen and real UI select/reorder/close/discard/cancel/empty preserve live per-page grid state and selected identity, while existing native cancellation tests still pass. Opening is not tab-strip UI. Main runs deno task prototype:swift-grid --smoke after tasks 1–4 settle. No author builds/tests/linters/formatters; read-only local inspection only.

# Task-specific constraints
Production document persistence/audio routing remain untouched. No controller hooks or fake readiness for tests. Avoid optional custom QObject bridge properties; nullable active page is derived in QML.
