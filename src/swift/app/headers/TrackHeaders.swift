import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
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
    public var trackHeaderWidth: Double = 0
    public var rowHeight: Int = 0
    public var activityWidth: Int = 0
    public var separatorWidth: Int = 0
    public var scrollbarWidth: Int = 0
    public var scrollbarMinimumThumbHeight: Int = 0
    public var reorderIndicatorHeight: Int = 0
    public var contentHeight: Int = 0
    public var viewportHeight: Double = 0
    public var maximumScrollY: Double = 0 {
        willSet { _scrollY.maximum = newValue }
    }
    @HeaderScrollPosition public var scrollY: Double = 0
    @QtTracked public var muteButtonRect = SceneRect(
        x: 0, y: 0, width: 0, height: 0, fillColor: .clear)
    @QtTracked public var soloButtonRect = SceneRect(
        x: 0, y: 0, width: 0, height: 0, fillColor: .clear)
    @QtTracked public var voiceLineRect = SceneRect(
        x: 0, y: 0, width: 0, height: 0, fillColor: .clear)
    @QtTracked public var renameEditorRect = SceneRect(
        x: 0, y: 0, width: 0, height: 0, fillColor: .clear)
    public var renamingTrack: Int = -1
    public var renameDraft: String = ""
    public var renamePlaceholder: String = ""
    @QtTracked public var reorderIndicatorVisible = false
    public var reorderIndicatorY: Double = 0
    @QtTracked public var menuOpen = false
    public var rowRebuildCount: Int = 0
    public var lastCancelReason: Int = -1
    public var cursorKind: Int = 0
    public var controlFont: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var normalTitleFont: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var boldTitleFont: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var subtitleFont: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var buttonBackground: QmlColor = .clear
    public var buttonText: QmlColor = .clear
    public var buttonHoverBackground: QmlColor = .clear
    public var buttonHoverText: QmlColor = .clear
    public var buttonPressedBackground: QmlColor = .clear
    public var buttonPressedText: QmlColor = .clear
    public var buttonOutline: QmlColor = .clear
    public var focusOutline: QmlColor = .clear
    public var muteCheckedBackground: QmlColor = .clear
    public var muteCheckedText: QmlColor = .clear
    public var soloCheckedBackground: QmlColor = .clear
    public var soloCheckedText: QmlColor = .clear
    public var inputBackground: QmlColor = .clear
    public var inputText: QmlColor = .clear
    public var inputOutline: QmlColor = .clear
    public var scrollbarHandle: QmlColor = .clear
    public var scrollbarHandleHover: QmlColor = .clear
    public var reorderIndicator: QmlColor = .clear
    public var selectionBackground: QmlColor = .clear
    public var selectionText: QmlColor = .clear
    /// Supplied by the same Qt host style hints as every other pointer surface.
    public var dragDistance: Double = 0

    @QtIgnored public var onAddTrackRequested: (() -> Void)?
    @QtIgnored public var onChangeTrackVoiceRequested: ((Int) -> Void)?
    @QtIgnored public var onRevealTrackVoiceRequested: ((Int) -> Void)?
    @QtIgnored public var onTrackSelected: ((Int) -> Void)?
    @QtIgnored public var onContextMenuRequested: ((Double, Double) -> Void)?
    @QtIgnored var session: DocumentSession?
    @QtIgnored var palette = GridPalette()
    @QtIgnored var geometry = TrackHeadersGeometry()
    @QtIgnored var pointer = HeaderPointerState()
    @QtIgnored var snapshots: [TrackHeaderSnapshot] = []
    private var spareRows: [TrackHeaderRowHandle] = []
    @QtIgnored var resolvedPrograms: [Int] = []
    /// Voice context bounds paired with `resolvedPrograms`; intra-span ticks do
    /// not need to rescan the document lane.
    @QtIgnored var resolvedProgramStarts: [Tick] = []
    @QtIgnored var resolvedProgramEnds: [Tick] = []
    @QtIgnored var fontRoles: Typography
    @QtIgnored var baseFontPx: Double { Double(fontRoles.baseFontPx) }
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

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        fontRoles = typography
        publishAppearance()
    }

    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        if self.session !== session { detach() }
        self.session = session
        self.palette = palette
        refreshAppearance()
    }

    /// Rebuilds cached control roles and row colors from the attached palette.
    /// The existing row refresh preserves interaction and measured text state.
    @QtIgnored
    public func refreshAppearance() {
        publishAppearance()
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
    }

    /// Called by the composition's one document publication, before refresh.
    @QtIgnored
    public func documentDidChange(_ change: SessionChange) {
        if change.trackRemap != nil { structuralRevision = change.revision }
        refreshFromDocument()
    }

    /// PROTOTYPE probe — counts document refreshes for the revision-stamp demo; delete after.
    public private(set) var documentRefreshCount = 0

    @QtIgnored
    public func refreshFromDocument() {
        documentRefreshCount += 1
        guard let session, !session.isClosed else { return }
        let document = session.document
        let trackCount = document.engineTracks.usedTrackCount
        let hasAdd = trackCount > 0 && document.canAddTrack
        let expectedCount = trackCount + (hasAdd ? 1 : 0)
        let structural =
            snapshots.count != expectedCount
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
        if hasAdd {
            next.append(
                TrackHeaderSnapshot(
                    isAddTrack: true, title: "+ Add track",
                    titleFont: normalTitleFont,
                    subtitleFont: subtitleFont))
        }
        if structural {
            snapshots = next
            if rows.count > next.count {
                for index in next.count..<rows.count { spareRows.append(rows[index]) }
            }
            syncRetained(
                rows, next,
                make: { row in
                    if let handle = self.spareRows.popLast() {
                        handle.update(row)
                        return handle
                    }
                    return TrackHeaderRowHandle(row)
                },
                update: { handle, row in
                    handle.update(row)
                    // Publish structural roles synchronously even when the handle is unchanged.
                    return true
                })
            rowRebuildCount += 1
        } else {
            for index in next.indices {
                // Native glyph centering belongs to the rendered text/font pair.
                if next[index].title == snapshots[index].title,
                    next[index].titleBold == snapshots[index].titleBold
                {
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
            snapshots.count >= trackCount
        else {
            refreshFromDocument()
            return
        }
        let contextTick = playing ? nextTick : session.editCursor
        for track in 0..<trackCount {
            if playing && !playingChanged,
                contextTick >= resolvedProgramStarts[track],
                contextTick < resolvedProgramEnds[track]
            {
                continue
            }
            let span = resolvedProgramSpan(track: track, session: session, tick: contextTick)
            resolvedProgramStarts[track] = span.start
            resolvedProgramEnds[track] = span.end
            guard resolvedPrograms[track] != span.program else { continue }
            resolvedPrograms[track] = span.program
            var row = makeSnapshot(track: track, session: session, program: span.program)
            if row.title == snapshots[track].title,
                row.titleBold == snapshots[track].titleBold
            {
                row.selectedTitleOffset = snapshots[track].selectedTitleOffset
            }
            publishRow(row, at: track)
        }

    }

    public func configureViewport(width: Double, height: Double, fontPx: Double, dpr: Double) {
        configureGeometry(width: width, height: height, base: fontPx, dpr: dpr)
    }

    public func rowAt(index: Int) -> Optional<TrackHeaderRowHandle> {
        guard index >= 0, index < rows.count else { return nil }
        return rows[index]
    }

    public func menuItem(index: Int) -> Optional<TrackHeaderMenuItem> {
        guard index >= 0, index < menuItems.count else { return nil }
        return menuItems[index]
    }

    /// QML's FontMetrics supplies native Qt measurements, not layout policy.
    public func configureTextMetrics(
        titleLineSpacing: Double, boldLineSpacing: Double,
        subtitleLineSpacing: Double
    ) {
        guard titleLineSpacing.isFinite, boldLineSpacing.isFinite,
            subtitleLineSpacing.isFinite, titleLineSpacing > 0,
            boldLineSpacing > 0, subtitleLineSpacing > 0
        else { return }
        let next = HeaderTextMetrics(
            title: Int(titleLineSpacing.rounded()),
            bold: Int(boldLineSpacing.rounded()),
            subtitle: Int(subtitleLineSpacing.rounded()))
        guard next != textMetrics else { return }
        textMetrics = next
        publishGeometry()
        refreshFromDocument()
    }

    public func setSelectedTitleOffset(track: Int, x: Double, y: Double) {
        guard x.isFinite, y.isFinite, snapshots.indices.contains(track),
            snapshots[track].track == track
        else { return }
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
            session.document.canAddTrack
        else { return }
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
        if restoreRollFocus { restoreRollFocusRequested() }
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
        if pointer.dragging {
            pointer.hoverRow = -1; pointer.hoverTarget = .none
        } else {
            pointer = HeaderPointerState()
        }
        publishPointerVisuals()
    }
    public func handleWheel(
        angleDeltaX: Double, angleDeltaY: Double,
        pixelDeltaX: Double, pixelDeltaY: Double,
        modifiers: Int, phase: Int
    ) -> Bool {
        scrollWheel(
            angleDeltaX: angleDeltaX, angleDeltaY: angleDeltaY,
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

    public func completeVoiceRequest(program: Int) {
        guard let target = pendingVoice else { return }
        pendingVoice = nil
        guard (0...127).contains(program), let session,
            target.matches(session.document)
        else { return }
        if target.track < 0 {
            if session.document.canAddTrack,
                let track = session.document.addTrack(voice: program)
            {
                selectTrack(track)
            }
        } else if validTrack(target.track) {
            let points = session.document.lanePoints(track: target.track, lane: .voice)
            if let firstTick = points.first?.tick,
                let firstChange = points.last(where: { $0.tick == firstTick })
            {
                if program != firstChange.value {
                    session.document.moveLanePoints(
                        track: target.track, lane: .voice,
                        moves: [LanePointMove(point: firstChange, tick: firstTick, value: program)])
                }
            } else {
                session.document.writeLane(
                    track: target.track, lane: .voice,
                    from: 0, through: 0,
                    points: [LaneWrite(tick: 0, value: program)])
            }
        }
        refreshFromDocument()
    }

    @QtSignal public func contextMenuRequested(x: Double, y: Double)
    // Mounted EditorSurface observes this to run the fork's focusContent
    // synchronously after a rename ends with the editor's restore flag.
    @QtSignal public func restoreRollFocusRequested()

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
    func firstVoiceProgram(track: Int) -> Int {
        guard let session, validTrack(track) else { return 0 }
        let points = session.document.lanePoints(track: track, lane: .voice)
        guard let firstTick = points.first?.tick else { return 0 }
        return points.last { $0.tick == firstTick }?.value ?? 0
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
        let labels = [
            "Change voice...", "Show voice in voicegroup", "Rename track...",
            "Duplicate track", "Delete track",
        ]
        menuItems.reset(
            to: labels.enumerated().map { index, text in
                TrackHeaderMenuItem(
                    actionId: index + 1, text: text,
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
        rows[index].update(row)
        rows[index] = rows[index]
    }
}

@MainActor
@QtBridgeable
public final class TrackHeaderRowHandle {
    public var isAddTrack: Bool = false
    public var track: Int = -1
    public var title: String = ""
    public var subtitle: String = ""
    @QtTracked public var titleRect = SceneRect(
        x: 0, y: 0, width: 0, height: 0, fillColor: .clear)
    @QtTracked public var subtitleRect = SceneRect(
        x: 0, y: 0, width: 0, height: 0, fillColor: .clear)
    public var selectedTitleOffsetX: Double = 0
    public var selectedTitleOffsetY: Double = 0
    public var titleFont: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var subtitleFont: QmlFont = QmlFont(family: gridBodyFamily, pixelSize: 13)
    public var baseColor: QmlColor = .clear
    public var overlayColor: QmlColor = .clear
    public var titleColor: QmlColor = .clear
    public var subtitleColor: QmlColor = .clear
    public var titleBold: Bool = false
    public var muteChecked: Bool = false
    public var soloChecked: Bool = false
    public var muteHovered: Bool = false
    public var mutePressed: Bool = false
    public var soloHovered: Bool = false
    public var soloPressed: Bool = false
    public var addHovered: Bool = false
    public var addPressed: Bool = false
    public var activityDimColor: QmlColor = .clear
    public var activityActiveColor: QmlColor = .clear
    public var activityLeftHeight: Double = 0
    public var activityRightHeight: Double = 0

    init(_ row: TrackHeaderSnapshot) {
        update(row)
    }

    @QtIgnored
    func update(_ row: TrackHeaderSnapshot) {
        publish(\.isAddTrack, row.isAddTrack)
        publish(\.track, row.track)
        publish(\.title, row.title)
        publish(\.subtitle, row.subtitle)
        _ = titleRect.update(row.titleRect.sceneValue)
        _ = subtitleRect.update(row.subtitleRect.sceneValue)
        publish(\.selectedTitleOffsetX, row.selectedTitleOffset.x)
        publish(\.selectedTitleOffsetY, row.selectedTitleOffset.y)
        publish(\.titleFont, row.titleFont)
        publish(\.subtitleFont, row.subtitleFont)
        publish(\.baseColor, row.baseColor)
        publish(\.overlayColor, row.overlayColor)
        publish(\.titleColor, row.titleColor)
        publish(\.subtitleColor, row.subtitleColor)
        publish(\.titleBold, row.titleBold)
        publish(\.muteChecked, row.muteChecked)
        publish(\.soloChecked, row.soloChecked)
        publish(\.muteHovered, row.muteHovered)
        publish(\.mutePressed, row.mutePressed)
        publish(\.soloHovered, row.soloHovered)
        publish(\.soloPressed, row.soloPressed)
        publish(\.addHovered, row.addHovered)
        publish(\.addPressed, row.addPressed)
        publish(\.activityDimColor, row.activityDimColor)
        publish(\.activityActiveColor, row.activityActiveColor)
        publish(\.activityLeftHeight, row.activityLeftHeight)
        publish(\.activityRightHeight, row.activityRightHeight)
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
