import Foundation
import PorydawCore
import QtBridge

/// The QML-facing value for one event-list row. Policy stays in
/// `EventListModel`; this handle only publishes the values a delegate renders.
@MainActor
@QtBridgeable
public final class EventListRowHandle {
    public var row: Int = -1
    public var eventIndex: Int = -1
    public var tick: Int = 0
    public var typeKind: Int = EventListEventType.endOfTrack.rawValue
    public var isEndOfTrack = false
    public var rowTint = ""

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
    public var rows: QListModel<EventListRowHandle> = QListModel()

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
    @QtIgnored public private(set) var lastScrollToRow = -1
    @QtIgnored public private(set) var playheadTick = -1.0
    @QtIgnored public private(set) var playing = false
    @QtIgnored public private(set) var pointerDown = false
    /// Qt's mouse-button bit mask. Zero is the native `NoButton` state.
    @QtIgnored public private(set) var mouseButtons = 0
    @QtIgnored public private(set) var model = EventListModel()
    @QtIgnored public var onScrollToRow: ((Int) -> Void)?

    @QtIgnored private weak var session: DocumentSession?

    public init() {}

    /// Installs one document and rebuilds its configured chunk synchronously.
    @QtIgnored
    public func attach(session: DocumentSession, chunkIndex: Int = 0) {
        if self.session !== session { detach() }
        self.session = session
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
        guard attached, let session, !session.isClosed else { return }

        let documentChanged = change.domains.contains(.document) || change.trackRemap != nil
        if documentChanged, let remap = change.trackRemap {
            remapCurrentChunk(using: remap)
        }

        var chunkChangedBySelection = false
        if change.domains.contains(.selection),
           let selectedChunk = mappedChunk(for: session.selectedTrack, in: session.document),
           selectedChunk != chunkIndex {
            // The native controller gates this sync on page visibility. Swift
            // has no page-visible state, so an attached presenter syncs now.
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
        let oldPlayRow = model.playRow
        model.setCurrentRow(row)
        currentRow = model.currentRow
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

    /// Commits or cancels the editing session. Document mutation is intentionally
    /// outside this playhead presenter; valid commits close the session.
    public func finishEditing(text: String, commit: Bool) -> Bool {
        guard editing else { return false }
        if commit && !model.validatesEdit(row: editingRow, column: editingColumn, text: text) {
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

    @QtSignal public func scrollToRow(row: Int)

    private func clearEditing() {
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

    private func mappedChunk(for selectedTrack: Int?, in document: SongDocument) -> Int? {
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

    private func rebuildFromDocument(preservingCurrentRow: Bool) {
        guard let session, !session.isClosed,
              session.document.rawChunks.indices.contains(chunkIndex) else {
            model.setSource(nil)
            publishRows()
            return
        }
        model.setSource(session.document.rawChunks[chunkIndex],
                        preservingCurrentRow: preservingCurrentRow)
        publishRows()
    }

    private func publishRows() {
        rows.reset(to: model.rows.map {
            EventListRowHandle($0, tint: model.rowTint(row: $0.index) ?? "")
        })
        rowCount = model.rowCount
        currentRow = model.currentRow
        playRow = model.playRow
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
}
