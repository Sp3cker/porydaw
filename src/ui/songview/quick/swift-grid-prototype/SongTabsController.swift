import QtBridge

@MainActor
@QtBridgeable
public final class SongTabSession {
    public let tabId: Int
    public let title: String
    @QtTracked public var grid: PianoGrid

    init(tabId: Int) {
        self.tabId = tabId
        title = "Song \(tabId)"
        grid = PianoGrid()
    }
}

@MainActor
@QtBridgeable
public final class SongTabsController {
    // Only this controller writes these properties. QtBridge does not expose
    // private(set) properties, so their setters must remain public.
    public var tabs: QListModel<SongTabSession> = QListModel()
    public var selectedId: Int = -1
    public var selectedIndex: Int = -1
    public var tabCount: Int = 0
    public var pendingCloseId: Int = -1

    private var nextTabId = 1

    @QtIgnored
    var selectedGrid: PianoGrid? {
        guard let index = index(of: selectedId) else { return nil }
        return tabs[index].grid
    }

    // Demo bootstrap seeds every session's grid (audio fixture + notes); the
    // app owns demo initialization, never the controller. Migration-only
    // (charter demo-lane row): retires with the standalone lane's gate.
    @QtIgnored
    var grids: [PianoGrid] {
        tabs.map { $0.grid }
    }

    public init() {
        openTab()
    }

    public func openTab() {
        let session = SongTabSession(tabId: nextTabId)
        nextTabId += 1
        tabs.append(session)
        tabCount = tabs.count
        selectTab(tabId: session.tabId)
    }

    public func selectTab(tabId: Int) {
        guard tabId != selectedId, let index = index(of: tabId) else { return }
        deactivateSelectedGrid()
        publishSelection(index: index)
    }

    public func moveTab(tabId: Int, destinationIndex: Int) {
        guard let sourceIndex = index(of: tabId),
            tabs.indices.contains(destinationIndex), sourceIndex != destinationIndex
        else { return }
        tabs.move(from: sourceIndex, to: destinationIndex)
        // Read the resulting order: native beginMoveRows can reject a move.
        publishSelection(index: index(of: selectedId) ?? -1)
    }

    public func requestClose(tabId: Int) {
        guard let index = index(of: tabId) else { return }
        if tabs[index].grid.canUndo {
            if pendingCloseId != tabId { pendingCloseId = tabId }
        } else {
            closeTab(index: index)
        }
    }

    public func confirmDiscard() {
        guard pendingCloseId != -1 else { return }
        let closingIndex = index(of: pendingCloseId)
        pendingCloseId = -1
        if let closingIndex { closeTab(index: closingIndex) }
    }

    public func cancelClose() {
        if pendingCloseId != -1 { pendingCloseId = -1 }
    }

    private func index(of tabId: Int) -> Int? {
        tabs.firstIndex { $0.tabId == tabId }
    }

    private func deactivateSelectedGrid() {
        guard let grid = selectedGrid else { return }
        grid.audio.stop()
        grid.inputCancelled(reason: GridCancelReason.hidden.rawValue)
    }

    private func publishSelection(index: Int) {
        let tabId = index == -1 ? -1 : tabs[index].tabId
        if selectedId != tabId { selectedId = tabId }
        if selectedIndex != index { selectedIndex = index }
    }

    private func closeTab(index: Int) {
        let tabId = tabs[index].tabId
        let closingSelected = tabId == selectedId
        if closingSelected { deactivateSelectedGrid() }
        if pendingCloseId == tabId { pendingCloseId = -1 }
        tabs.remove(at: index)
        tabCount = tabs.count
        let survivorIndex = closingSelected
            ? min(index, tabs.count - 1)
            : self.index(of: selectedId) ?? -1
        publishSelection(index: survivorIndex)
    }
}
