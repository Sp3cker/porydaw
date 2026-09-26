import Foundation
import PorydawCore
import QtBridge
import PorydawAppEventList

/// The QML-facing value for one event-list row. Policy stays in
/// `EventListModel`; this handle only publishes the values a delegate renders.
@MainActor
@QtBridgeable
public final class EventListRowHandle {
    public var row: Int = -1
    public var eventIndex: Int = -1
    public var tick: Int = 0
    public var typeKind: Int = EventListEventType.endOfTrack.rawValue
    public var isEndOfTrack: Bool = false
    public var rowTint: String = ""

    init(_ source: EventListRow, tint: String) {
        row = source.index
        eventIndex = source.eventIndex ?? -1
        tick = Int(source.tick)
        typeKind = source.typeKind
        isEndOfTrack = source.isEndOfTrack
        rowTint = tint
    }
}

/// Document-bound event-list publication and playhead interaction policy.
///
/// The presenter owns no view, window, or geometry. It exposes stable row
/// values, keeps edit focus separate from transport tint, and emits a scroll
/// request only when native follow-playhead suppression permits it.
@MainActor
@QtBridgeable
public final class EventListPresenter {
    private static let defaultWidthSeeds = [70.0, 120.0, 36.0, 56.0, 56.0, 140.0]
    public var rows: QListModel<EventListRowHandle> = QListModel()
    @QtTracked public var tableRevision = 0
    @QtTracked public var visible = false
    @QtTracked public var chunk = -1
    public var chunkLabels: [String] = []
    @QtTracked public var filterMask = 127
    @QtTracked public var filterSummary = "All events"
    @QtTracked public var countText = ""
    @QtTracked public var headerLabels = ["Tick", "Type", "Ch", "Data 1",
                                          "Data 2", "Data", "Summary"]
    @QtIgnored public var columnWidths: [Double] = [] {
        didSet { columnWidthsRevision &+= 1 }
    }
    @QtTracked public var columnWidthsRevision = 0
    @QtIgnored var resizedColumns: Set<Int> = []
    @QtIgnored public var selectedRows: [Int] = [] {
        didSet { selectionRevision &+= 1 }
    }
    @QtTracked public var selectionRevision = 0
    public var menuItems: QListModel<EventListMenuItem> = QListModel()
    @QtTracked public var menuShortcutText = ""
    @QtTracked public var menuSeparatorCount = 0
    @QtTracked public var menuX = 0.0
    @QtTracked public var menuY = 0.0
    public var appearance: [String: QVariantSettable] = [:]

    @QtTracked public var attached = false
    @QtTracked public var chunkIndex = -1
    @QtTracked public var rowCount = 0
    @QtTracked public var currentRow = -1
    @QtTracked public var playRow = -1
    @QtTracked public var followPlayhead = true
    @QtTracked public var editing = false
    @QtTracked public var editingRow = -1
    @QtTracked public var editingColumn = -1
    @QtTracked public var menuOpen = false
    /// Monotonically increments for each permitted follow-scroll request.
    @QtTracked public var scrollToRowRequested = 0

    /// Swift checks and the host can observe the exact row of the last request.
    public private(set) var lastScrollToRow = -1
    public private(set) var playheadTick = -1.0
    public private(set) var playing = false
    public private(set) var pointerDown = false
    /// Qt's mouse-button bit mask. Zero is the native `NoButton` state.
    public private(set) var mouseButtons = 0
    @QtIgnored public internal(set) var model = EventListModel()
    @QtIgnored public var onScrollToRow: ((Int) -> Void)?
    @QtIgnored public var onRevealVoiceRequested: ((Int) -> Void)?
    @QtIgnored public var onPerformEventListCommand: ((Int) -> Void)?

    @QtIgnored var selectionAnchor = -1
    @QtIgnored var menuKind: EventListMenuKind?
    @QtIgnored var menuRow = -1
    @QtIgnored weak var session: DocumentSession?
    private var appearancePalette: GridPalette
    private var typography: Typography

    public init(palette: GridPalette = GridPalette(),
                typography: Typography = Typography(baseFontPx: 13)) {
        appearancePalette = palette
        self.typography = typography
        appearance = EventListAppearance.roles(palette: palette, typography: typography)
    }

    public func refreshAppearance() {
        appearance = EventListAppearance.roles(palette: appearancePalette, typography: typography)
    }
    public func configureTypography(typography: Typography) {
        guard self.typography.baseFontPx != typography.baseFontPx else { return }
        self.typography = typography
        refreshAppearance()
        columnWidthsRevision &+= 1
    }

    /// Installs one document and rebuilds its configured chunk synchronously.
    @QtIgnored
    public func attach(session: DocumentSession, chunkIndex: Int = 0) {
        if self.session !== session { detach() }
        self.session = session
        visible = false
        self.chunkIndex = chunkIndex
        attached = true
        rebuildFromDocument(preservingCurrentRow: false)
    }

    /// Drops the document and clears all published rows and transient state.
    @QtIgnored
    public func detach() {
        session = nil
        attached = false
        model.detach()
        rows.reset(to: [])
        chunkIndex = -1
        rowCount = 0
        currentRow = -1
        playRow = -1
        playheadTick = -1
        playing = false
        pointerDown = false
        mouseButtons = 0
        selectedRows = []
        selectionAnchor = -1
        chunk = -1
        chunkLabels = []
        menuItems.reset(to: [])
        menuKind = nil
        visible = false
        clearEditing()
        menuOpen = false
        lastScrollToRow = -1
        scrollToRowRequested = 0
        onScrollToRow = nil
    }

    /// Rebuilds rows only after a document publication. Cursor, selection,
    /// dirty, history, bank, and mix-state publications do not rebuild rows
    /// unless selection changes the mapped chunk.
    @QtIgnored
    public func documentDidChange(_ change: SessionChange) {
        if change.domains.contains(.document) || change.trackRemap != nil {
            invalidateRowMenu()
        }
        guard attached, let session, !session.isClosed else { return }

        if change.domains.contains(.bank) {
            model.voiceNames = voiceNames()
            tableRevision &+= 1
        }

        let documentChanged = change.domains.contains(.document) || change.trackRemap != nil
        if documentChanged, let remap = change.trackRemap {
            remapCurrentChunk(using: remap)
        }

        var chunkChangedBySelection = false
        if change.domains.contains(.selection), visible,
           let selectedChunk = mappedChunk(for: session.selectedTrack, in: session.document),
           selectedChunk != chunkIndex {
            invalidateRowMenu()
            chunkIndex = selectedChunk
            chunkChangedBySelection = true
        }

        guard documentChanged || chunkChangedBySelection else { return }
        rebuildFromDocument(preservingCurrentRow: documentChanged && !chunkChangedBySelection)
    }

    /// Explicit refresh hook for a host that changed the selected chunk.
    @QtIgnored
    public func refresh() {
        guard attached else { return }
        invalidateRowMenu()
        rebuildFromDocument(preservingCurrentRow: true)
    }
    /// Selects a document chunk and resets row focus as the native controller
    /// does when its source changes. When requested, the first engine track
    /// mapped to the chunk becomes the session's selected track.
    public func setChunk(index: Int, followTrack: Bool = false) {
        guard attached else {
            chunkIndex = index
            return
        }
        guard let session, !session.isClosed else { return }
        let target = session.document.rawChunks.indices.contains(index) ? index : -1
        guard target != chunkIndex else { return }
        invalidateRowMenu()
        chunk = target

        chunkIndex = target
        rebuildFromDocument(preservingCurrentRow: false)

        guard followTrack, target >= 0,
              let track = firstEngineTrack(for: target, in: session.document),
              session.selectedTrack != track else { return }
        session.selectPrimaryTrack(track)
    }


    /// Updates transport state, tinting the model row even when follow-scroll
    /// is suppressed by pointer, editing, menu, or mouse-button state.
    public func setPlayheadTick(tick: Double, playing: Bool) {
        guard attached else { return }
        guard self.playheadTick != tick || self.playing != playing else { return }
        self.playheadTick = tick
        self.playing = playing
        let oldPlayRow = model.playRow
        model.setPlayheadTick(tick)
        publishPlayheadTransition(from: oldPlayRow)
        guard oldPlayRow != model.playRow,
              playing, model.playRow >= 0, followPlayhead, !pointerDown,
              !editing, !menuOpen, mouseButtons == 0 else { return }
        requestScroll(to: model.playRow)
    }


    public func setFollowPlayhead(enabled: Bool) {
        followPlayhead = enabled
    }

    public func setPointerDown(down: Bool) {
        self.pointerDown = down
    }

    public func setMouseButtons(buttons: Int) {
        mouseButtons = buttons
    }

    public func setMenuOpen(open: Bool) {
        menuOpen = open
    }

    /// Focuses a valid row and commits that row's tick to the document cursor.
    /// The sentinel commits `endTick`, while transport state remains separate.
    public func focusRow(row: Int) {
        guard attached, let session, !session.isClosed,
              let tick = model.rowTick(row: row) else { return }
        let oldRow = currentRow
        let oldPlayRow = model.playRow
        model.setCurrentRow(row)
        currentRow = model.currentRow
        if currentRow != oldRow { invalidateRowMenu() }
        session.editCursor = tick
        publishPlayheadTransition(from: oldPlayRow)
    }

    /// Starts an in-cell edit when the model exposes that cell as editable.
    public func beginEditing(row: Int, column: Int) -> Bool {
        guard attached, !editing, model.isCellEditable(row: row, column: column) else {
            return false
        }
        editing = true
        editingRow = row
        editingColumn = column
        return true
    }

    /// Invalid commits keep the editor open so the user can correct the text.
    public func finishEditing(text: String, commit: Bool) -> Bool {
        guard editing else { return false }
        if commit && !commitCellEdit(row: editingRow, column: editingColumn, text: text) {
            return false
        }
        clearEditing()
        return true
    }


    public func rowTick(row: Int) -> Int {
        guard let tick = model.rowTick(row: row) else { return -1 }
        return Int(tick)
    }

    public func rowType(row: Int) -> Int {
        model.rowType(row: row) ?? EventListEventType.endOfTrack.rawValue
    }

    /// Returns an empty string for untinted rows because optional colors are not
    /// a stable Qt bridge type; the pure model retains the optional API.
    public func rowTint(row: Int) -> String {
        model.rowTint(row: row) ?? ""
    }

    public func isRowTinted(row: Int) -> Bool {
        model.rowTint(row: row) != nil
    }

    // QML bridge methods must be declared on the annotated class itself;
    // the document policy and interaction implementations live in extensions.
    public func isSelected(row: Int) -> Bool { dispatchIsSelected(row: row) }
    public func selectRow(row: Int, modifiers: Int) {
        let previous = selectedRows
        let previousRow = currentRow
        dispatchSelectRow(row: row, modifiers: modifiers)
        if selectedRows != previous || currentRow != previousRow { invalidateRowMenu() }
    }
    public func selectAll() {
        let previous = selectedRows
        dispatchSelectAll()
        if selectedRows != previous { invalidateRowMenu() }
    }
    public func setVisible(visible: Bool) { dispatchSetVisible(visible: visible) }
    public func isCellEditable(row: Int, column: Int) -> Bool {
        dispatchIsCellEditable(row: row, column: column)
    }
    public func cellDisplay(row: Int, column: Int) -> String {
        dispatchCellDisplay(row: row, column: column)
    }
    public func cellEdit(row: Int, column: Int) -> String {
        dispatchCellEdit(row: row, column: column)
    }
    public func tickString(row: Int) -> String { dispatchTickString(row: row) }
    public func rowKind(row: Int) -> Int { dispatchRowKind(row: row) }
    public func headerAlignment(column: Int) -> Int {
        dispatchHeaderAlignment(column: column)
    }
    func defaultColumnWidth(column: Int) -> Double {
        guard Self.defaultWidthSeeds.indices.contains(column) else { return 0 }
        return Double(typography.fontPx(Self.defaultWidthSeeds[column] / 13.0))
    }
    public func savedColumnWidth(column: Int) -> Double {
        resizedColumns.contains(column) && columnWidths.indices.contains(column)
            ? columnWidths[column] : defaultColumnWidth(column: column)
    }
    public func resizeColumn(column: Int, width: Double) {
        dispatchResizeColumn(column: column, width: width)
    }
    public func isLegalDrop(fromRow: Int, gap: Int) -> Bool {
        dispatchIsLegalDrop(fromRow: fromRow, gap: gap)
    }
    public func commitDrop(fromRow: Int, gap: Int) {
        dispatchCommitDrop(fromRow: fromRow, gap: gap)
    }
    public func canStepEditing() -> Bool { dispatchCanStepEditing() }
    public func steppedEditingText(currentText: String, delta: Int) -> String {
        dispatchSteppedEditingText(currentText: currentText, delta: delta)
    }
    public func addEvent() { dispatchAddEvent() }
    public func deleteSelected() { dispatchDeleteSelected() }
    public func openChunkMenu(x: Double, y: Double) {
        dispatchOpenChunkMenu(x: x, y: y)
    }
    public func openFilterMenu(x: Double, y: Double) {
        dispatchOpenFilterMenu(x: x, y: y)
    }
    public func openRowMenu(x: Double, y: Double) {
        dispatchOpenRowMenu(x: x, y: y)
    }
    public func openTypeMenu(x: Double, y: Double) {
        dispatchOpenTypeMenu(x: x, y: y)
    }
    public func dismissMenu() { dispatchDismissMenu() }
    public func activateMenuAction(actionId: Int) {
        dispatchActivateMenuAction(actionId: actionId)
    }

    @QtSignal public func scrollToRow(row: Int)

    func clearEditing() {
        editing = false
        editingRow = -1
        editingColumn = -1
    }

    private func remapCurrentChunk(using remap: TrackRemap) {
        guard chunkIndex >= 0 else { return }
        chunkIndex = remap.chunkMap.indices.contains(chunkIndex)
            ? remap.chunkMap[chunkIndex] ?? -1
            : -1
    }

    func mappedChunk(for selectedTrack: Int?, in document: SongDocument) -> Int? {
        guard let selectedTrack else { return nil }
        let map = document.engineTracks
        guard (0..<map.usedTrackCount).contains(selectedTrack),
              map.tracks.indices.contains(selectedTrack),
              let chunk = map.tracks[selectedTrack].midiChunk,
              document.rawChunks.indices.contains(chunk) else {
            return nil
        }
        return chunk
    }

    private func firstEngineTrack(for chunk: Int, in document: SongDocument) -> Int? {
        let map = document.engineTracks
        for track in 0..<map.usedTrackCount where map.tracks.indices.contains(track) && map.tracks[track].midiChunk == chunk {
            return track
        }
        return nil
    }

    func rebuildFromDocument(preservingCurrentRow: Bool) {
        guard let session, !session.isClosed else {
            model.setSource(nil)
            publishRows()
            return
        }
        let document = session.document
        let chunks = document.rawChunks
        chunkLabels = chunks.indices.map { chunk in
            if let engineTrack = firstEngineTrack(for: chunk, in: document) {
                return "Chunk \(chunk) — Track \(engineTrack + 1)"
            }
            return "Chunk \(chunk) (tempo/meta)"
        }
        guard chunks.indices.contains(chunkIndex) else {
            model.setSource(nil)
            publishRows()
            return
        }
        model.setSource(chunks[chunkIndex],
                        tempos: chunkIndex == 0 ? session.document.state.tempo : [],
                        filterMask: filterMask,
                        preservingCurrentRow: preservingCurrentRow)
        chunk = chunkIndex
        selectedRows = selectedRows.filter { model.rows.indices.contains($0) }
        model.voiceNames = voiceNames()
        publishRows()
    }

    func publishRows() {
        rows.reset(to: model.rows.map {
            EventListRowHandle($0, tint: model.rowTint(row: $0.index) ?? "")
        })
        rowCount = model.rowCount
        currentRow = model.currentRow
        playRow = model.playRow
        let shown = max(0, model.rowCount - (model.rowCount > 0 ? 1 : 0))
        let total = model.chunk.events.count + (chunkIndex == 0 ? model.tempos.count : 0)
        countText = shown == total ? "\(total) event(s)" : "\(shown) of \(total) events"
        tableRevision &+= 1
    }

    private func publishPlayheadTransition(from oldPlayRow: Int) {
        let newPlayRow = model.playRow
        if oldPlayRow != newPlayRow {
            refreshRowHandle(at: oldPlayRow)
            refreshRowHandle(at: newPlayRow)
            if playRow != newPlayRow { playRow = newPlayRow }
        }
    }

    private func refreshRowHandle(at row: Int) {
        guard model.rows.indices.contains(row) else { return }
        rows[row] = EventListRowHandle(model.rows[row],
                                       tint: model.rowTint(row: row) ?? "")
    }

    private func requestScroll(to row: Int) {
        lastScrollToRow = row
        scrollToRowRequested &+= 1
        onScrollToRow?(row)
        scrollToRow(row: row)
    }

    private func voiceNames() -> [String] {
        (session?.bankSlots ?? []).map {
            let name = VoiceLanePolicy.shortName($0)
            return name == "Voice" ? "" : name
        }
    }
}
