import Foundation
import PorydawCore
import QtBridge

/// Clamp before QtTracked publishes a write; its generated didSet cannot be customized.
@propertyWrapper
public struct HeaderScrollPosition {
    public var maximum: Double = 0
    private var value: Double = 0

    public init(wrappedValue: Double) {
        self.wrappedValue = wrappedValue
    }

    public var wrappedValue: Double {
        get { value }
        set { value = newValue.isFinite ? min(maximum, max(0, newValue)) : 0 }
    }
}

/// Document-bound header band. Qt owns input delivery and font measurement;
/// Swift owns presentation, hit testing and mutations of the current session.
@MainActor
@QtBridgeable
public final class TrackHeadersPresenter {
    public var rows: QListModel<TrackHeaderRowHandle> = QListModel()
    public var menuItems: QListModel<TrackHeaderMenuItem> = QListModel()
    @QtTracked public var trackHeaderWidth: Double = 0
    @QtTracked public var rowHeight: Int = 0
    @QtTracked public var activityWidth: Int = 0
    @QtTracked public var separatorWidth: Int = 0
    @QtTracked public var scrollbarWidth: Int = 0
    @QtTracked public var scrollbarMinimumThumbHeight: Int = 0
    @QtTracked public var reorderIndicatorHeight: Int = 0
    @QtTracked public var contentHeight: Int = 0
    @QtTracked public var viewportHeight: Double = 0
    @QtTracked public var maximumScrollY: Double = 0 {
        willSet { _scrollY.maximum = newValue }
    }
    @QtTracked @HeaderScrollPosition public var scrollY: Double = 0
    @QtTracked public var muteButtonRect: [String: QVariantSettable] = HeaderRect().map
    @QtTracked public var soloButtonRect: [String: QVariantSettable] = HeaderRect().map
    @QtTracked public var voiceLineRect: [String: QVariantSettable] = HeaderRect().map
    @QtTracked public var renameEditorRect: [String: QVariantSettable] = HeaderRect().map
    @QtTracked public var renamingTrack: Int = -1
    @QtTracked public var renameDraft: String = ""
    @QtTracked public var renamePlaceholder: String = ""
    @QtTracked public var reorderIndicatorVisible = false
    @QtTracked public var reorderIndicatorY: Double = 0
    @QtTracked public var menuOpen = false
    @QtTracked public var rowRebuildCount: Int = 0
    @QtTracked public var lastCancelReason: Int = -1
    @QtTracked public var cursorKind: Int = 0
    @QtTracked public var controlFont: [String: QVariantSettable] = [:]
    @QtTracked public var appearance: [String: QVariantSettable] = [:]
    @QtTracked public var normalTitleFont: [String: QVariantSettable] = [:]
    @QtTracked public var boldTitleFont: [String: QVariantSettable] = [:]
    @QtTracked public var subtitleFont: [String: QVariantSettable] = [:]
    /// Supplied by the same Qt host style hints as every other pointer surface.
    public var dragDistance: Double = 0

    @QtIgnored public var onAddTrackRequested: (() -> Void)?
    @QtIgnored public var onChangeTrackVoiceRequested: ((Int) -> Void)?
    @QtIgnored public var onRevealTrackVoiceRequested: ((Int) -> Void)?
    @QtIgnored public var onTrackSelected: ((Int) -> Void)?
    @QtIgnored public var onContextMenuRequested: ((Double, Double) -> Void)?
    @QtIgnored public var onRestoreRollFocus: (() -> Void)?
    @QtIgnored var session: DocumentSession?
    @QtIgnored var palette = GridPalette()
    @QtIgnored var geometry = TrackHeadersGeometry()
    @QtIgnored var pointer = HeaderPointerState()
    @QtIgnored var snapshots: [TrackHeaderSnapshot] = []
    @QtIgnored var resolvedPrograms: [Int] = []
    /// Voice context bounds paired with `resolvedPrograms`; intra-span ticks do
    /// not need to rescan the document lane.
    @QtIgnored var resolvedProgramStarts: [Tick] = []
    @QtIgnored var resolvedProgramEnds: [Tick] = []
    @QtIgnored var baseFontPx: Double
    @QtIgnored var viewportWidth: Double = 0
    @QtIgnored var devicePixelRatio: Double = 1
    @QtIgnored var textMetrics: HeaderTextMetrics?
    @QtIgnored var pendingMenu: PendingHeaderMenu?
    @QtIgnored var pendingVoice: PendingHeaderMenu?
    @QtIgnored var renameTarget: PendingHeaderMenu?
    @QtIgnored var appliedRevision: UInt64?
    @QtIgnored var structuralRevision: UInt64?
    @QtIgnored var playing = false
    @QtIgnored var playheadTick: Tick = 0
    @QtIgnored public var activityAnimating: Bool { activity.isAnimating }
    @QtIgnored var activity = TrackActivity()
    @QtIgnored var activityPlaying = false

    public init(baseFontPx: Double = 13) {
        self.baseFontPx = max(1, baseFontPx)
        controlFont = TrackHeadersGeometry.titleFont(baseFontPx: self.baseFontPx).map
        normalTitleFont = controlFont
        boldTitleFont = TrackHeadersGeometry.titleFont(baseFontPx: self.baseFontPx, bold: true).map
        subtitleFont = TrackHeadersGeometry.subtitleFont(baseFontPx: self.baseFontPx).map
        appearance = TrackHeadersGeometry.appearance(palette: palette)
    }

    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        if self.session !== session { detach() }
        self.session = session
        self.palette = palette
        appearance = TrackHeadersGeometry.appearance(palette: palette)
        refreshFromDocument()
    }

    @QtIgnored
    public func detach() {
        cancelTransientState()
        session = nil
        appliedRevision = nil
        structuralRevision = nil
        pendingVoice = nil
        resolvedPrograms.removeAll(keepingCapacity: false)
        resolvedProgramStarts.removeAll(keepingCapacity: false)
        resolvedProgramEnds.removeAll(keepingCapacity: false)
        playing = false
        activity.reset()
        activityPlaying = false
        if !snapshots.isEmpty {
            snapshots.removeAll()
            rows.reset(to: [])
            rowRebuildCount += 1
        }
        updateScrollGeometry()
        onAddTrackRequested = nil
        onChangeTrackVoiceRequested = nil
        onRevealTrackVoiceRequested = nil
        onTrackSelected = nil
        onContextMenuRequested = nil
        onRestoreRollFocus = nil
    }

    /// Called by the composition's one document publication, before refresh.
    @QtIgnored
    public func documentDidChange(_ change: SessionChange) {
        if change.trackRemap != nil { structuralRevision = change.revision }
        refreshFromDocument()
    }

    @QtIgnored
    public func refreshFromDocument() {
        guard let session, !session.isClosed else { return }
        let document = session.document
        let trackCount = document.engineTracks.usedTrackCount
        let hasAdd = trackCount > 0 && document.canAddTrack
        let expectedCount = trackCount + (hasAdd ? 1 : 0)
        let structural = snapshots.count != expectedCount
            || (structuralRevision == document.revision && appliedRevision != document.revision)
        if structural {
            cancelTransientState()
            activity.resetPaused()
        }
        if let target = pendingMenu, !target.matches(document) { dismissHeaderMenu() }
        if let target = pendingVoice, !target.matches(document) { pendingVoice = nil }
        var next: [TrackHeaderSnapshot] = []
        next.reserveCapacity(expectedCount)
        var nextPrograms: [Int] = []
        var nextStarts: [Tick] = []
        var nextEnds: [Tick] = []
        nextPrograms.reserveCapacity(trackCount)
        nextStarts.reserveCapacity(trackCount)
        nextEnds.reserveCapacity(trackCount)
        let contextTick = playing ? playheadTick : session.editCursor
        for track in 0..<trackCount {
            let span = resolvedProgramSpan(track: track, session: session, tick: contextTick)
            nextPrograms.append(span.program)
            nextStarts.append(span.start)
            nextEnds.append(span.end)
            next.append(makeSnapshot(track: track, session: session, program: span.program))
        }
        if hasAdd { next.append(TrackHeaderSnapshot(isAddTrack: true, title: "+ Add track")) }
        if structural {
            snapshots = next
            rows.reset(to: next.map(TrackHeaderRowHandle.init))
            rowRebuildCount += 1
        } else {
            for index in next.indices {
                // Native glyph centering belongs to the rendered text/font pair.
                if next[index].title == snapshots[index].title,
                   next[index].titleBold == snapshots[index].titleBold {
                    next[index].selectedTitleOffset = snapshots[index].selectedTitleOffset
                }
                publishRow(next[index], at: index)
            }
        }
        resolvedPrograms = nextPrograms
        resolvedProgramStarts = nextStarts
        resolvedProgramEnds = nextEnds
        appliedRevision = document.revision
        updateScrollGeometry()
        publishPointerVisuals()
    }

    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard tick.isFinite else { return }
        let bounded = min(Double(TimeDefaults.maxTick), max(0, tick))
        let nextTick = Tick(bounded.rounded(.down))
        let playingChanged = self.playing != playing
        guard playingChanged || (playing && playheadTick != nextTick) else { return }
        self.playing = playing
        playheadTick = nextTick
        guard let session, !session.isClosed else { return }

        let trackCount = session.document.engineTracks.usedTrackCount
        guard resolvedPrograms.count == trackCount,
              resolvedProgramStarts.count == trackCount,
              resolvedProgramEnds.count == trackCount,
              snapshots.count >= trackCount else {
            refreshFromDocument()
            return
        }
        let contextTick = playing ? nextTick : session.editCursor
        for track in 0..<trackCount {
            if playing && !playingChanged,
               contextTick >= resolvedProgramStarts[track],
               contextTick < resolvedProgramEnds[track] {
                continue
            }
            let span = resolvedProgramSpan(track: track, session: session, tick: contextTick)
            resolvedProgramStarts[track] = span.start
            resolvedProgramEnds[track] = span.end
            guard resolvedPrograms[track] != span.program else { continue }
            resolvedPrograms[track] = span.program
            var row = makeSnapshot(track: track, session: session, program: span.program)
            if row.title == snapshots[track].title,
               row.titleBold == snapshots[track].titleBold {
                row.selectedTitleOffset = snapshots[track].selectedTitleOffset
            }
            publishRow(row, at: track)
        }

    }

    public func configureViewport(width: Double, height: Double, fontPx: Double, dpr: Double) {
        configureGeometry(width: width, height: height, base: fontPx, dpr: dpr)
    }

    /// QML's FontMetrics supplies native Qt measurements, not layout policy.
    public func configureTextMetrics(titleLineSpacing: Double, boldLineSpacing: Double,
                                     subtitleLineSpacing: Double) {
        guard titleLineSpacing.isFinite, boldLineSpacing.isFinite,
              subtitleLineSpacing.isFinite, titleLineSpacing > 0,
              boldLineSpacing > 0, subtitleLineSpacing > 0 else { return }
        let next = HeaderTextMetrics(title: Int(titleLineSpacing.rounded()),
                                    bold: Int(boldLineSpacing.rounded()),
                                    subtitle: Int(subtitleLineSpacing.rounded()))
        guard next != textMetrics else { return }
        textMetrics = next
        publishGeometry()
        refreshFromDocument()
    }

    public func setSelectedTitleOffset(track: Int, x: Double, y: Double) {
        guard x.isFinite, y.isFinite, snapshots.indices.contains(track),
              snapshots[track].track == track else { return }
        var row = snapshots[track]
        row.selectedTitleOffset = row.titleBold ? HeaderPoint(x: x, y: y) : HeaderPoint()
        publishRow(row, at: track)
    }

    public func activateMute(track: Int) {
        guard let session, validTrack(track) else { return }
        if !session.mutedTracks.insert(track).inserted { session.mutedTracks.remove(track) }
    }

    public func activateSolo(track: Int) {
        guard let session, validTrack(track) else { return }
        if !session.soloedTracks.insert(track).inserted { session.soloedTracks.remove(track) }
    }

    public func activateAddTrack() {
        guard let session, !session.isClosed, session.document.engineTracks.usedTrackCount > 0,
              session.document.canAddTrack else { return }
        pendingVoice = PendingHeaderMenu(document: session.document, track: -1)
        onAddTrackRequested?()
    }

    public func beginRename(track: Int) {
        guard let session, validTrack(track), renamingTrack != track else { return }
        finishRename(commit: false, restoreRollFocus: false)
        renameTarget = PendingHeaderMenu(document: session.document, track: track)
        renameDraft = session.document.trackName(track)
        renamePlaceholder = "Track \(track + 1)"
        renamingTrack = track
    }

    public func finishRename(commit: Bool, restoreRollFocus: Bool) {
        guard renamingTrack >= 0 else { return }
        let target = renameTarget
        let draft = renameDraft
        renamingTrack = -1
        renameDraft = ""
        renamePlaceholder = ""
        renameTarget = nil
        if commit, let session, let target, target.matches(session.document) {
            session.document.renameTrack(target.track, to: draft)
            refreshFromDocument()
        }
        if restoreRollFocus { onRestoreRollFocus?(); rollFocusRequested() }
    }

    public func beginPointer(x: Double, y: Double, button: Int, modifiers: Int) -> Bool {
        pointerPress(x: x, y: y, button: button, modifiers: modifiers)
    }
    public func updatePointer(x: Double, y: Double, modifiers: Int) -> Bool {
        pointerMove(x: x, y: y, modifiers: modifiers)
    }
    public func endPointer(x: Double, y: Double, button: Int, modifiers: Int) -> Bool {
        pointerRelease(x: x, y: y, button: button, modifiers: modifiers)
    }
    public func doublePointer(x: Double, y: Double, button: Int, modifiers: Int) -> Bool {
        pointerDoubleClick(x: x, y: y, button: button, modifiers: modifiers)
    }
    public func updateHover(x: Double, y: Double) { hover(x: x, y: y) }
    public func clearHover() {
        if pointer.dragging { pointer.hoverRow = -1; pointer.hoverTarget = .none }
        else { pointer = HeaderPointerState() }
        publishPointerVisuals()
    }
    public func handleWheel(angleDeltaX: Double, angleDeltaY: Double,
                            pixelDeltaX: Double, pixelDeltaY: Double,
                            modifiers: Int, phase: Int) -> Bool {
        scrollWheel(angleDeltaX: angleDeltaX, angleDeltaY: angleDeltaY,
                    pixelDeltaX: pixelDeltaX, pixelDeltaY: pixelDeltaY)
    }
    public func inputCancelled(reason: Int) {
        guard GridCancelReason(rawValue: reason) != nil else { return }
        lastCancelReason = reason
        finishReorder(commit: false)
        pointer = HeaderPointerState()
        publishPointerVisuals()
        if reason == GridCancelReason.hidden.rawValue {
            finishRename(commit: false, restoreRollFocus: false)
            dismissHeaderMenu()
            pendingVoice = nil
        }
    }

    public func activateHeaderMenuAction(actionId: Int) {
        guard let target = pendingMenu, (1...5).contains(actionId) else { return }
        if actionId == 4, session?.document.canAddTrack != true { return }
        dismissHeaderMenu()
        guard let session, target.matches(session.document), validTrack(target.track) else { return }
        switch actionId {
        case 1: requestTrackVoice(track: target.track)
        case 2: onRevealTrackVoiceRequested?(target.track)
        case 3: beginRename(track: target.track)
        case 4:
            if let added = session.document.duplicateTrack(target.track) { selectTrack(added) }
            refreshFromDocument()
        case 5:
            session.document.deleteTrack(target.track)
            refreshFromDocument()
        default: break
        }
    }

    public func dismissHeaderMenu() { pendingMenu = nil; menuOpen = false }

    /// Completion of the existing host's picker callback, guarded across edits
    /// and document replacement. A negative program is the picker's cancellation.
    public func completeVoiceRequest(program: Int) {
        guard let target = pendingVoice else { return }
        pendingVoice = nil
        guard (0...127).contains(program), let session,
              target.matches(session.document) else { return }
        if target.track < 0 {
            if let track = session.document.addTrack(voice: program) { selectTrack(track) }
        } else if validTrack(target.track) {
            let points = session.document.lanePoints(track: target.track, lane: .voice)
            let tick = points.first?.tick ?? 0
            session.document.writeLane(track: target.track, lane: .voice,
                                       from: tick, through: tick,
                                       points: [LaneWrite(tick: tick, value: program)])
        }
        refreshFromDocument()
    }

    @QtSignal public func contextMenuRequested(x: Double, y: Double)
    @QtSignal public func rollFocusRequested()

    @QtIgnored
    func validTrack(_ track: Int) -> Bool {
        guard let session, !session.isClosed else { return false }
        return (0..<session.document.engineTracks.usedTrackCount).contains(track)
    }

    @QtIgnored
    func selectTrack(_ track: Int) {
        guard let session, validTrack(track) else { return }
        session.selectPrimaryTrack(track)
        onTrackSelected?(track)
        refreshFromDocument()
    }

    @QtIgnored
    func requestTrackVoice(track: Int) {
        guard let session, validTrack(track) else { return }
        pendingVoice = PendingHeaderMenu(document: session.document, track: track)
        onChangeTrackVoiceRequested?(track)
    }

    @QtIgnored
    func showHeaderMenu(track: Int, x: Double, y: Double) {
        guard let session, validTrack(track) else { return }
        dismissHeaderMenu()
        let labels = ["Change voice...", "Show voice in voicegroup", "Rename track...",
                      "Duplicate track", "Delete track"]
        menuItems.reset(to: labels.enumerated().map { index, text in
            TrackHeaderMenuItem(actionId: index + 1, text: text,
                                enabled: index != 3 || session.document.canAddTrack)
        })
        pendingMenu = PendingHeaderMenu(document: session.document, track: track)
        menuOpen = true
        contextMenuRequested(x: x, y: y)
        onContextMenuRequested?(x, y)
    }

    @QtIgnored
    func cancelTransientState() {
        inputCancelled(reason: GridCancelReason.hidden.rawValue)
        finishRename(commit: false, restoreRollFocus: false)
        dismissHeaderMenu()
    }

    @QtIgnored
    func publishRow(_ row: TrackHeaderSnapshot, at index: Int) {
        guard row != snapshots[index] else { return }
        snapshots[index] = row
        rows[index] = TrackHeaderRowHandle(row)
    }
}

@MainActor
@QtBridgeable
public final class TrackHeaderRowHandle {
    public var isAddTrack: Bool = false
    public var track: Int = -1
    public var title: String = ""
    public var subtitle: String = ""
    public var titleRect: [String: QVariantSettable] = [:]
    public var subtitleRect: [String: QVariantSettable] = [:]
    public var selectedTitleOffset: [String: QVariantSettable] = [:]
    public var titleFont: [String: QVariantSettable] = [:]
    public var subtitleFont: [String: QVariantSettable] = [:]
    public var baseColor: String = "#00000000"
    public var overlayColor: String = "#00000000"
    public var titleColor: String = "#00000000"
    public var subtitleColor: String = "#00000000"
    public var titleBold: Bool = false
    public var muteChecked: Bool = false
    public var soloChecked: Bool = false
    public var muteHovered: Bool = false
    public var mutePressed: Bool = false
    public var soloHovered: Bool = false
    public var soloPressed: Bool = false
    public var addHovered: Bool = false
    public var addPressed: Bool = false
    public var activityDimColor: String = "#00000000"
    public var activityActiveColor: String = "#00000000"
    public var activityLeftHeight: Double = 0
    public var activityRightHeight: Double = 0

    init(_ row: TrackHeaderSnapshot) {
        isAddTrack = row.isAddTrack; track = row.track
        title = row.title; subtitle = row.subtitle
        titleRect = row.titleRect.map; subtitleRect = row.subtitleRect.map
        selectedTitleOffset = ["x": row.selectedTitleOffset.x, "y": row.selectedTitleOffset.y]
        titleFont = row.titleFont.map; subtitleFont = row.subtitleFont.map
        baseColor = row.baseColor; overlayColor = row.overlayColor
        titleColor = row.titleColor; subtitleColor = row.subtitleColor
        titleBold = row.titleBold; muteChecked = row.muteChecked; soloChecked = row.soloChecked
        muteHovered = row.muteHovered; mutePressed = row.mutePressed
        soloHovered = row.soloHovered; soloPressed = row.soloPressed
        addHovered = row.addHovered; addPressed = row.addPressed
        activityDimColor = row.activityDimColor; activityActiveColor = row.activityActiveColor
        activityLeftHeight = row.activityLeftHeight; activityRightHeight = row.activityRightHeight
    }
}

@MainActor
@QtBridgeable
public final class TrackHeaderMenuItem {
    public var actionId: Int
    public var text: String
    public var enabled: Bool

    init(actionId: Int, text: String, enabled: Bool) {
        self.actionId = actionId; self.text = text; self.enabled = enabled
    }
}

@MainActor
struct PendingHeaderMenu {
    let document: ObjectIdentifier
    let revision: UInt64
    let track: Int

    init(document: SongDocument, track: Int) {
        self.document = ObjectIdentifier(document)
        revision = document.revision
        self.track = track
    }

    func matches(_ document: SongDocument) -> Bool {
        self.document == ObjectIdentifier(document) && revision == document.revision
    }
}
