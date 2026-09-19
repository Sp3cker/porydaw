import Foundation
import NativeGridTypography
import SwiftGridDocumentFeed
import SwiftGridKeyFeed
import SwiftGridSessionFeed

// The Swift track-header presenter (spec.md §5): the second consumer of the
// writable seams. The C++ TrackHeaderSwift shell owns the QObject surface
// TrackHeaderBand.qml binds; this type owns the presenter state the shell
// mirrors — rows, layout rects, pointer visuals, reorder and rename state,
// and the revision-guarded menu snapshot (the PendingHeaderMenu pattern).
//
// Document intents (track add/duplicate/delete/reorder/rename) submit through
// sgc_ — one intent, one undo entry. Mute/solo submit SGC_TRACK_MUTE/SOLO and
// the checked state renders from sgs_ pushes, never local state. Host-only
// actions (selection, voice reveal/picker, context menu, focus, cursor,
// mouse hints) cross back through the action callback; the shell routes them
// to the same SongView primitives the C++ presenter uses.

// Change bits reported through the notify callback; the shell maps them to
// its NOTIFY signals. Rows means "re-pull the row list" — the shell diffs
// per-role, so Swift never tracks which roles changed.
private enum SgthChange: UInt32 {
    case rows = 1
    case geometry = 2
    case rename = 4
    case scroll = 8
    case reorder = 16
}

// Host actions the presenter cannot express as sgc_ intents. Values are
// order-frozen with the shell's dispatch switch.
private enum SgthAction: Int32 {
    case selectTrack = 0
    case trackHeaderClicked = 1
    case revealTrackVoice = 2
    case queueEditTrackVoice = 3
    case showContextMenu = 4
    case focusContent = 5
    case setCursorClosedHand = 6
    case clearCursor = 7
    case releasePointerGrab = 8
    case setMouseHint = 9
    case focusHeaderBand = 10
}

// Hit targets mirror TrackHeaderModel::HitTarget declaration order.
private enum HitTarget: Int32 {
    case none = 0
    case body
    case voice
    case mute
    case solo
    case addTrack
}

// Pointer kinds mirror the SGB_POINTER_* order the roll band uses.
private enum PointerKind: Int32 {
    case press = 0
    case move = 1
    case release = 2
    case doubleClick = 3
}

// Header menu action ids mirror TrackHeaderModel::HeaderMenuAction.
private enum HeaderMenuAction: Int32 {
    case changeVoice = 1
    case showVoiceInVoicegroup = 2
    case renameTrack = 3
    case duplicateTrack = 4
    case deleteTrack = 5
}

private struct HeaderGeometry {
    var rowHeight = 0
    var activityWidth = 0
    var buttonExtent = 0
    var buttonColumnWidth = 0
    var textLeft = 0
    var renameEditorLeft = 0
    var renameEditorTop = 0
    var renameEditorRight = 0
    var renameEditorHeight = 0
    var reorderIndicatorHeight = 0
    var separatorWidth = 0
    var scrollbarWidth = 0
    var scrollbarMinimumThumbHeight = 0
    var spaceOne = 0
    var spaceHalf = 0
    var startDragDistance = 0
}

public struct HeaderRect: Equatable, Sendable {
    public var x = 0.0
    public var y = 0.0
    public var w = 0.0
    public var h = 0.0

    public init(x: Double = 0.0, y: Double = 0.0, w: Double = 0.0, h: Double = 0.0) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    // QRectF::contains parity: edges are inclusive.
    func contains(px: Double, py: Double) -> Bool {
        px >= x && px <= x + w && py >= y && py <= y + h
    }
}

private struct HeaderRow {
    var isAddTrack = false
    var track = -1
    var program = -1
    var rawName = ""
    var placeholder = ""
    var subtitle = ""
    var title = ""
    var titleRect = HeaderRect()
    var subtitleRect = HeaderRect()
    var baseColor: UInt32 = 0
    var overlayColor: UInt32 = 0
    var titleColor: UInt32 = 0
    var subtitleColor: UInt32 = 0
    var activityDimColor: UInt32 = 0
    var activityActiveColor: UInt32 = 0
    var titleBold = false
    var muted = false
    var soloed = false
}

private struct PointerState {
    var hoverRow = -1
    var hoverTarget = HitTarget.none
    var pressedRow = -1
    var pressedTrack = -1
    var pressedTarget = HitTarget.none
    var pressX = 0.0
    var pressY = 0.0
    var dragArmed = false
    var dragging = false
}

// The guarded open-time menu target (PendingHeaderMenu): document identity
// plus revision plus the raw engine track. Any document mutation between
// open and activation bumps the sgd_ revision and the action drops.
private struct PendingHeaderMenu {
    var documentId: UInt64 = 0
    var documentRevision: UInt64 = 0
    var track = -1
}

@MainActor
private final class HeaderFontMetrics {
    let session: OpaquePointer
    let extents: SGFontExtents

    init(family: String, pixelSize: Int32, weight: Int32, letterSpacing: Double) {
        session = family.withCString {
            sgf_create($0, pixelSize, weight, letterSpacing)!
        }
        extents = sgf_extents(session)
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double {
        text.withCString { sgf_advance(session, $0) }
    }
}


@MainActor
public final class TrackHeadersPresenter {
    private let notify: (UInt32, UnsafeMutableRawPointer?) -> Void
    private let action: (Int32, Int32, Double, Double, UnsafeMutableRawPointer?) -> Void
    private let context: UnsafeMutableRawPointer?

    private let documents: DocumentFeed
    private let sessions: SessionFeed
    private let commands: SgcCommandPipe
    private let keyTargetId: UInt64
    private var connected = false

    private var geometry = HeaderGeometry()
    private var viewportWidth = 0.0
    private var viewportHeight = 0.0
    private var rows: [HeaderRow] = []
    private var pointer = PointerState()
    private var scrollY = 0.0
    private var reorderIndicatorVisible = false
    private var reorderIndicatorY = 0.0
    private var renamingTrack = -1
    private var renameDraft = ""
    private var renamePlaceholder = ""
    private var renameRevision: UInt64 = 0
    private var finishingRename = false
    private var pendingMenu: PendingHeaderMenu?

    private var normalTitle: HeaderFontMetrics?
    private var boldTitle: HeaderFontMetrics?
    private var subtitleFont: HeaderFontMetrics?
    // The primary track the current layout was computed against; a session
    // push that changes it re-elides titles with the other metrics.
    private var laidOutPrimary = -1

    public init(
        documentId: UInt64, sessionId: UInt64, keyTargetId: UInt64,
        notify: @escaping (UInt32, UnsafeMutableRawPointer?) -> Void,
        action: @escaping (Int32, Int32, Double, Double, UnsafeMutableRawPointer?) -> Void,
        context: UnsafeMutableRawPointer?
    ) {
        self.notify = notify
        self.action = action
        self.context = context
        self.keyTargetId = keyTargetId
        documents = DocumentFeed(documentId: documentId)
        sessions = SessionFeed(sessionId: sessionId)
        commands = SgcCommandPipe(documentId: documentId)
    }

    @discardableResult
    public func connect() -> Bool {
        guard !connected else { return false }
        guard documents.connect(), sessions.connect() else {
            documents.disconnect()
            sessions.disconnect()
            return false
        }
        sessions.onSession = { [weak self] _ in self?.applySession() }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            sgk_set_delivery(
                keyTargetId,
                { facts, context in
                    guard let facts, let context else { return 0 }
                    return MainActor.assumeIsolated {
                        let presenter: TrackHeadersPresenter = Unmanaged.fromOpaque(context)
                            .takeUnretainedValue()
                        return presenter.answerKey(facts.pointee) ? 1 : 0
                    }
                }, context)
        else {
            sessions.disconnect()
            documents.disconnect()
            return false
        }
        connected = true
        return true
    }

    public func disconnect() {
        guard connected else { return }
        connected = false
        sgk_clear_delivery(keyTargetId)
        sessions.disconnect()
        documents.disconnect()
    }

    isolated deinit {
        disconnect()
    }

    private func emit(_ change: SgthChange) {
        notify(change.rawValue, context)
    }

    private func emit(_ changes: [SgthChange]) {
        let mask = changes.reduce(UInt32(0)) { $0 | $1.rawValue }
        notify(mask, context)
    }

    private func request(
        _ id: SgthAction, track: Int32 = 0, a: Double = 0, b: Double = 0
    ) {
        action(id.rawValue, track, a, b, context)
    }

    // MARK: - Shell pushes

    public func setGeometry(_ values: [Int32]) {
        precondition(values.count == 16)
        geometry = HeaderGeometry(
            rowHeight: Int(values[0]), activityWidth: Int(values[1]),
            buttonExtent: Int(values[2]), buttonColumnWidth: Int(values[3]),
            textLeft: Int(values[4]), renameEditorLeft: Int(values[5]),
            renameEditorTop: Int(values[6]), renameEditorRight: Int(values[7]),
            renameEditorHeight: Int(values[8]), reorderIndicatorHeight: Int(values[9]),
            separatorWidth: Int(values[10]), scrollbarWidth: Int(values[11]),
            scrollbarMinimumThumbHeight: Int(values[12]), spaceOne: Int(values[13]),
            spaceHalf: Int(values[14]), startDragDistance: Int(values[15]))
        relayoutRows()
        emit(.geometry)
        clampScroll()
    }

    public func setFont(slot: Int32, family: String, pixelSize: Int32, weight: Int32,
                        letterSpacing: Double) {
        let metrics = HeaderFontMetrics(
            family: family, pixelSize: pixelSize, weight: weight,
            letterSpacing: letterSpacing)
        switch slot {
        case 0: normalTitle = metrics
        case 1: boldTitle = metrics
        default: subtitleFont = metrics
        }
        guard normalTitle != nil, boldTitle != nil, subtitleFont != nil else { return }
        relayoutRows()
        emit(.geometry)
    }

    public func setViewport(width: Double, height: Double) {
        viewportWidth = width
        viewportHeight = height
        relayoutRows()
        emit(.geometry)
        clampScroll()
    }

    public func beginRows() {
        rows.removeAll(keepingCapacity: true)
    }

    public func pushTrack(
        track: Int32, program: Int32, name: String, placeholder: String, subtitle: String,
        baseColor: UInt32, overlayColor: UInt32, titleColor: UInt32, subtitleColor: UInt32,
        activityDim: UInt32, activityActive: UInt32
    ) {
        var row = HeaderRow()
        row.track = Int(track)
        row.program = Int(program)
        row.rawName = name
        row.placeholder = placeholder
        row.subtitle = subtitle
        row.baseColor = baseColor
        row.overlayColor = overlayColor
        row.titleColor = titleColor
        row.subtitleColor = subtitleColor
        row.activityDimColor = activityDim
        row.activityActiveColor = activityActive
        rows.append(row)
    }

    public func pushAddTrack(title: String) {
        var row = HeaderRow()
        row.isAddTrack = true
        row.title = title
        rows.append(row)
    }

    public func endRows() {
        applySession()
        relayoutRows()
        emit([.rows, .geometry])
        clampScroll()
    }

    // MARK: - Layout (mirrors TrackHeaderModel's resolved geometry)

    private var textBounds: HeaderRect {
        let textWidth = max(
            0.0,
            viewportWidth - Double(geometry.buttonColumnWidth + geometry.textLeft
                + geometry.spaceOne))
        return HeaderRect(
            x: Double(geometry.textLeft), y: 0, w: textWidth,
            h: Double(max(0, geometry.rowHeight - geometry.separatorWidth)))
    }

    private var twoLineHeights: (primary: Double, gap: Double, secondary: Double)? {
        guard let normalTitle, let boldTitle, let subtitleFont else { return nil }
        return (
            max(normalTitle.extents.height, boldTitle.extents.height),
            Double(geometry.spaceHalf), subtitleFont.extents.height)
    }

    private func twoLineBoxes() -> (primary: HeaderRect, secondary: HeaderRect)? {
        guard let heights = twoLineHeights else { return nil }
        let bounds = textBounds
        let total = heights.primary + heights.gap + heights.secondary
        let top = bounds.y + (bounds.h - total) / 2.0
        return (
            HeaderRect(x: bounds.x, y: top, w: bounds.w, h: heights.primary),
            HeaderRect(
                x: bounds.x, y: top + heights.primary + heights.gap, w: bounds.w,
                h: heights.secondary))
    }

    private func elide(_ text: String, metrics: HeaderFontMetrics, width: Double) -> String {
        guard width > 0, metrics.advance(text) > width else { return text }
        let ellipsis = "…"
        let ellipsisAdvance = metrics.advance(ellipsis)
        var result = ""
        for scalar in text.unicodeScalars {
            let candidate = result + String(scalar)
            if metrics.advance(candidate) + ellipsisAdvance > width { break }
            result = candidate
        }
        return result + ellipsis
    }

    private func relayoutRows() {
        let primaryTrack = Int(sessions.session?.primaryTrack ?? -1)
        laidOutPrimary = primaryTrack
        guard let boxes = twoLineBoxes(), let normalTitle, let boldTitle, let subtitleFont else {
            // No host fonts yet: mirror the C++ no-host record — raw display
            // strings, empty rects — so data() still serves real titles.
            for index in rows.indices where !rows[index].isAddTrack {
                let row = rows[index]
                let name = row.rawName.isEmpty ? row.placeholder : row.rawName
                rows[index].title = "\(row.track + 1) · \(name)"
                rows[index].titleBold = row.track == primaryTrack
                rows[index].titleRect = HeaderRect()
                rows[index].subtitleRect = HeaderRect()
            }
            return
        }
        let width = textBounds.w
        for index in rows.indices where !rows[index].isAddTrack {
            let row = rows[index]
            let bold = row.track == primaryTrack
            let titleMetrics = bold ? boldTitle : normalTitle
            let name = row.rawName.isEmpty ? row.placeholder : row.rawName
            rows[index].title = elide(
                "\(row.track + 1) · \(name)", metrics: titleMetrics, width: width)
            rows[index].subtitle = elide(row.subtitle, metrics: subtitleFont, width: width)
            rows[index].titleBold = bold
            rows[index].titleRect = boxes.primary
            rows[index].subtitleRect = boxes.secondary
        }
    }

    private var muteButtonRect: HeaderRect {
        let gap = max(0, geometry.rowHeight - geometry.separatorWidth - 2 * geometry.buttonExtent)
        let topGap = gap / 3
        let x = viewportWidth - Double(geometry.spaceOne + geometry.buttonExtent)
        return HeaderRect(
            x: x, y: Double(topGap), w: Double(geometry.buttonExtent),
            h: Double(geometry.buttonExtent))
    }

    private var soloButtonRect: HeaderRect {
        let gap = max(0, geometry.rowHeight - geometry.separatorWidth - 2 * geometry.buttonExtent)
        let topGap = gap / 3
        let middleGap = gap / 3
        let x = viewportWidth - Double(geometry.spaceOne + geometry.buttonExtent)
        return HeaderRect(
            x: x, y: Double(topGap + geometry.buttonExtent + middleGap),
            w: Double(geometry.buttonExtent), h: Double(geometry.buttonExtent))
    }

    private var voiceLineRect: HeaderRect {
        twoLineBoxes()?.secondary ?? HeaderRect()
    }

    private var renameEditorRect: HeaderRect {
        HeaderRect(
            x: Double(geometry.renameEditorLeft), y: Double(geometry.renameEditorTop),
            w: max(0.0, viewportWidth - Double(geometry.renameEditorRight)),
            h: Double(geometry.renameEditorHeight))
    }

    // Band-level geometry queries.
    public func bandRect(_ field: Int32) -> HeaderRect {
        switch field {
        case 0: return muteButtonRect
        case 1: return soloButtonRect
        case 2: return voiceLineRect
        default: return renameEditorRect
        }
    }

    // MARK: - Row queries

    public var rowCount: Int32 { Int32(rows.count) }
    public var contentHeight: Int32 { Int32(rows.count) * Int32(geometry.rowHeight) }
    public var maximumScrollY: Double {
        max(0.0, Double(contentHeight) - viewportHeight)
    }
    public var currentScrollY: Double { scrollY }
    public var currentViewportHeight: Double { max(0.0, viewportHeight) }
    public var currentRenamingTrack: Int32 { Int32(renamingTrack) }
    public var currentRenameDraft: String { renameDraft }
    public var currentRenamePlaceholder: String { renamePlaceholder }
    public var currentReorderVisible: Bool { reorderIndicatorVisible }
    public var currentReorderY: Double { reorderIndicatorY }

    public func rowFlags(_ row: Int32) -> UInt16 {
        guard row >= 0, Int(row) < rows.count else { return 0 }
        let record = rows[Int(row)]
        var flags: UInt16 = record.isAddTrack ? 1 : 0
        if record.titleBold { flags |= 1 << 1 }

        if record.muted { flags |= 1 << 2 }
        if record.soloed { flags |= 1 << 3 }
        if !record.isAddTrack && pointer.hoverRow == Int(row) && pointer.hoverTarget == .mute {
            flags |= 1 << 4
            if pointer.pressedRow == Int(row) && pointer.pressedTarget == .mute {
                flags |= 1 << 5
            }
        }
        if !record.isAddTrack && pointer.hoverRow == Int(row) && pointer.hoverTarget == .solo {
            flags |= 1 << 6
            if pointer.pressedRow == Int(row) && pointer.pressedTarget == .solo {
                flags |= 1 << 7
            }
        }
        if record.isAddTrack && pointer.hoverRow == Int(row)
            && pointer.hoverTarget == .addTrack
        {
            flags |= 1 << 8
            if pointer.pressedRow == Int(row) && pointer.pressedTarget == .addTrack {
                flags |= 1 << 9
            }
        }
        return flags
    }

    public func rowTrack(_ row: Int32) -> Int32 {
        guard row >= 0, Int(row) < rows.count else { return -1 }
        let record = rows[Int(row)]
        return record.isAddTrack ? -1 : Int32(record.track)
    }

    public func rowString(_ row: Int32, field: Int32) -> String? {
        guard row >= 0, Int(row) < rows.count else { return nil }
        let record = rows[Int(row)]
        return field == 0 ? record.title : record.subtitle
    }

    public func rowRect(_ row: Int32, field: Int32) -> HeaderRect {
        guard row >= 0, Int(row) < rows.count else { return HeaderRect() }
        let record = rows[Int(row)]
        switch field {
        case 0: return record.titleRect
        case 1: return record.subtitleRect
        case 2: return muteButtonRect
        case 3: return soloButtonRect
        case 4: return voiceLineRect
        default: return renameEditorRect
        }
    }

    public func rowColor(_ row: Int32, field: Int32) -> UInt32 {
        guard row >= 0, Int(row) < rows.count else { return 0 }
        let record = rows[Int(row)]
        switch field {
        case 0: return record.baseColor
        case 1: return record.overlayColor
        case 2: return record.titleColor
        case 3: return record.subtitleColor
        case 4: return record.activityDimColor
        default: return record.activityActiveColor
        }
    }

    // MARK: - Session feed (sgs_ masks/selection)

    private func applySession() {
        guard let session = sessions.session else { return }
        var changed = false
        for index in rows.indices where !rows[index].isAddTrack {
            let bit = UInt32(1) << UInt32(rows[index].track)
            let muted = (session.muteMask & bit) != 0
            let soloed = (session.soloMask & bit) != 0
            if rows[index].muted != muted || rows[index].soloed != soloed {
                rows[index].muted = muted
                rows[index].soloed = soloed
                changed = true
            }
        }
        // A primary-track change re-elides titles with the other metrics;
        // relayoutRows owns the bold flag from there.
        if Int(session.primaryTrack) != laidOutPrimary {
            relayoutRows()
            changed = true
        }
        if changed { emit(.rows) }
    }

    // MARK: - Scroll

    private func clampScroll() {
        let next = scrollY.isFinite ? min(max(scrollY, 0.0), maximumScrollY) : 0.0
        if next != scrollY {
            scrollY = next
            emit(.scroll)
        }
    }

    public func setScroll(_ value: Double) {
        let next = value.isFinite ? min(max(value, 0.0), maximumScrollY) : 0.0
        if next != scrollY {
            scrollY = next
            emit(.scroll)
        }
    }

    // MARK: - Rename (host text entry, SGC_TRACK_RENAME commit)

    public func beginRename(_ track: Int32) {
        guard track >= 0, track < 16,
            rows.contains(where: { !$0.isAddTrack && $0.track == Int(track) }),
            renamingTrack != Int(track)
        else { return }
        cancelRename()
        renamingTrack = Int(track)
        let row = rows.first { !$0.isAddTrack && $0.track == Int(track) }
        renameDraft = row?.rawName ?? ""
        renamePlaceholder = row?.placeholder ?? ""
        renameRevision = documents.appliedRevision ?? 0
        emit(.rename)
    }

    public func setRenameDraft(_ text: String) {
        guard renameDraft != text else { return }
        renameDraft = text
        emit(.rename)
    }

    public func finishRename(commit: Bool, restoreRollFocus: Bool) {
        guard renamingTrack >= 0, !finishingRename else { return }
        finishingRename = true
        let track = renamingTrack
        let draft = renameDraft
        let revision = renameRevision
        renamingTrack = -1
        renameDraft = ""
        renamePlaceholder = ""
        emit(.rename)
        if restoreRollFocus { request(.focusContent) }
        // Revision guard: a document mutation since beginRename makes the
        // draft's target ambiguous; the commit drops silently.
        if commit, documents.appliedRevision == revision {
            _ = commands.submit(.trackRename(track: Int32(track), name: draft))
        }
        finishingRename = false
    }

    public func cancelRename() {
        guard renamingTrack >= 0, !finishingRename else { return }
        renamingTrack = -1
        renameDraft = ""
        renamePlaceholder = ""
        emit(.rename)
    }

    // MARK: - Activations (sgc_ intents)

    public func activateMute(_ track: Int32) {
        guard rows.contains(where: { !$0.isAddTrack && $0.track == Int(track) }) else { return }
        let on = !((sessions.session?.muteMask ?? 0) & (UInt32(1) << UInt32(max(0, track))) != 0)
        _ = commands.submit(.trackMute(track: track, on: on))
    }

    public func activateSolo(_ track: Int32) {
        guard rows.contains(where: { !$0.isAddTrack && $0.track == Int(track) }) else { return }
        let on = !((sessions.session?.soloMask ?? 0) & (UInt32(1) << UInt32(max(0, track))) != 0)
        _ = commands.submit(.trackSolo(track: track, on: on))
    }

    public func activateAddTrack() {
        guard rows.contains(where: { $0.isAddTrack }) else { return }
        _ = commands.submit(.trackAdd(voice: 0))
    }

    // MARK: - Hit testing and pointer input

    private func contentY(_ bandY: Double) -> Double { bandY + scrollY }

    private func rowAt(_ bandY: Double) -> Int {
        guard geometry.rowHeight > 0 else { return -1 }
        let row = Int((contentY(bandY) / Double(geometry.rowHeight)).rounded(.down))
        return row >= 0 && row < rows.count ? row : -1
    }

    private func trackRowCount() -> Int {
        var count = 0
        while count < rows.count && !rows[count].isAddTrack { count += 1 }
        return count
    }

    private func rowLocalRect(_ rect: HeaderRect, bandY: Double) -> HeaderRect {
        let row = rowAt(bandY)
        guard row >= 0 else { return HeaderRect() }
        return HeaderRect(
            x: rect.x, y: rect.y + Double(row) * Double(geometry.rowHeight) - scrollY,
            w: rect.w, h: rect.h)
    }

    private func hitTarget(_ row: Int, x: Double, y: Double) -> HitTarget {
        guard row >= 0, row < rows.count else { return .none }
        if rows[row].isAddTrack { return .addTrack }
        if rowLocalRect(muteButtonRect, bandY: y).contains(px: x, py: y) { return .mute }
        if rowLocalRect(soloButtonRect, bandY: y).contains(px: x, py: y) { return .solo }
        if rowLocalRect(voiceLineRect, bandY: y).contains(px: x, py: y) { return .voice }
        return .body
    }

    private func updatePointerVisuals(row: Int, target: HitTarget, pressed: Bool) {
        let before = pointer
        pointer.hoverRow = row
        pointer.hoverTarget = target
        if pressed {
            pointer.pressedRow = row
            pointer.pressedTarget = target
        }
        if before.hoverRow != pointer.hoverRow || before.hoverTarget != pointer.hoverTarget
            || before.pressedRow != pointer.pressedRow
            || before.pressedTarget != pointer.pressedTarget
        {
            emit(.rows)
        }
    }

    private func clearPointerVisuals() {
        // Mirrors the C++ PointerState reset: hover, press, armed, and the
        // dragging flag all clear together (callers finish the reorder first).
        let before = pointer
        pointer = PointerState()
        if before.hoverRow != -1 || before.hoverTarget != .none || before.pressedRow != -1
            || before.pressedTarget != .none
        {
            emit(.rows)
        }
    }

    // Qt::LeftButton = 1, Qt::RightButton = 2; Control = 1<<26, Shift = 1<<25.
    private static let leftButton: Int32 = 1
    private static let rightButton: Int32 = 2
    private static let controlModifier: Int32 = 1 << 26
    private static let shiftModifier: Int32 = 1 << 25

    private func pointerPress(x: Double, y: Double, globalX: Double, globalY: Double,
                              button: Int32, buttons: Int32, modifiers: Int32) -> Bool {
        let row = rowAt(y)
        guard row >= 0 else { return false }
        let target = hitTarget(row, x: x, y: y)
        if button == Self.rightButton && (buttons & Self.leftButton) != 0 { return true }

        clearPointerVisuals()
        if target == .addTrack {
            guard button == Self.leftButton else { return true }
            pointer.pressedTrack = -1
            pointer.pressX = x
            pointer.pressY = y
            updatePointerVisuals(row: row, target: target, pressed: true)
            return true
        }
        if (target == .mute || target == .solo) && button == Self.leftButton {
            pointer.pressedTrack = rows[row].track
            pointer.pressX = x
            pointer.pressY = y
            updatePointerVisuals(row: row, target: target, pressed: true)
            return true
        }

        let track = rows[row].track
        if button == Self.rightButton {
            request(.selectTrack, track: Int32(track))
            request(.showContextMenu, track: Int32(track), a: globalX, b: globalY)
            return true
        }

        request(.trackHeaderClicked, track: Int32(track), a: Double(modifiers))
        let plainLeft = button == Self.leftButton
            && (modifiers & (Self.controlModifier | Self.shiftModifier)) == 0
        if plainLeft {
            pointer.pressedTrack = track
            pointer.pressX = x
            pointer.pressY = y
            pointer.dragArmed = true
            updatePointerVisuals(row: row, target: target, pressed: true)
        }
        return true
    }

    private func pointerDoubleClick(x: Double, y: Double) -> Bool {
        let row = rowAt(y)
        guard row >= 0 else { return false }
        let target = hitTarget(row, x: x, y: y)
        clearPointerVisuals()
        if target == .addTrack || target == .mute || target == .solo { return true }

        let track = rows[row].track
        request(.selectTrack, track: Int32(track))
        if target == .voice {
            request(.queueEditTrackVoice, track: Int32(track), a: -1)
        } else {
            beginRename(Int32(track))
        }
        return true
    }

    private func pointerMove(x: Double, y: Double, buttons: Int32) -> Bool {
        let row = rowAt(y)
        let target = row >= 0 ? hitTarget(row, x: x, y: y) : .none
        updatePointerVisuals(row: row, target: target, pressed: false)
        if buttons == 0 {
            // ui::hint_profiles::Id: TrackScope = 14, Empty = 0.
            request(
                .setMouseHint,
                a: Double(target == .body || target == .voice ? 14 : 0))
        }
        if pointer.dragging {
            updateReorder(y: y)
            return true
        }
        if pointer.dragArmed, (buttons & Self.leftButton) != 0,
            abs(x - pointer.pressX) + abs(y - pointer.pressY)
                >= Double(geometry.startDragDistance)
        {
            beginReorder(track: pointer.pressedTrack, y: y)
            return pointer.dragging
        }
        return row >= 0 || pointer.pressedRow >= 0
    }

    private func pointerRelease(x: Double, y: Double, button: Int32) -> Bool {
        if pointer.dragging {
            finishReorder(commit: button == Self.leftButton)
            clearPointerVisuals()
            return true
        }
        guard pointer.pressedRow >= 0 else { return false }
        guard button == Self.leftButton else {
            clearPointerVisuals()
            return true
        }

        let pressedRow = pointer.pressedRow
        let pressedTrack = pointer.pressedTrack
        let pressedTarget = pointer.pressedTarget
        let row = rowAt(y)
        let target = row >= 0 ? hitTarget(row, x: x, y: y) : .none
        clearPointerVisuals()
        guard row == pressedRow, target == pressedTarget else { return true }

        switch pressedTarget {
        case .addTrack:
            activateAddTrack()
        case .mute:
            activateMute(Int32(pressedTrack))
        case .solo:
            activateSolo(Int32(pressedTrack))
        case .body, .voice:
            request(.revealTrackVoice, track: Int32(pressedTrack))
        case .none:
            break
        }
        return true
    }

    public func pointer(
        kind: Int32, x: Double, y: Double, globalX: Double, globalY: Double,
        button: Int32, buttons: Int32, modifiers: Int32
    ) -> Bool {
        switch PointerKind(rawValue: kind) {
        case .press:
            return pointerPress(
                x: x, y: y, globalX: globalX, globalY: globalY, button: button,
                buttons: buttons, modifiers: modifiers)
        case .move:
            return pointerMove(x: x, y: y, buttons: buttons)
        case .release:
            return pointerRelease(x: x, y: y, button: button)
        case .doubleClick:
            return pointerDoubleClick(x: x, y: y)
        case nil:
            return false
        }
    }

    public func pointerLeave() {
        if pointer.dragging {
            updatePointerVisuals(row: -1, target: .none, pressed: false)
        } else {
            clearPointerVisuals()
        }
    }

    public func wheel(pixelDeltaX: Int32, pixelDeltaY: Int32, angleDeltaX: Int32,
                      angleDeltaY: Int32, inverted: Bool) -> Bool {
        var delta = 0.0
        if pixelDeltaX != 0 || pixelDeltaY != 0 {
            guard abs(pixelDeltaX) <= abs(pixelDeltaY), pixelDeltaY != 0 else { return false }
            delta = Double(pixelDeltaY)
        } else {
            guard abs(angleDeltaX) <= abs(angleDeltaY), angleDeltaY != 0 else { return false }
            delta = Double(angleDeltaY) / 120.0 * Double(geometry.rowHeight)
        }
        setScroll(scrollY + (inverted ? delta : -delta))
        return true
    }

    public func cancelInput() {
        finishReorder(commit: false)
        clearPointerVisuals()
    }

    public func cancelTransient() {
        finishReorder(commit: false)
        clearPointerVisuals()
        cancelRename()
        pendingMenu = nil
        request(.releasePointerGrab)
    }

    public var gestureActive: Bool { pointer.dragging }

    // MARK: - Reorder

    private func beginReorder(track: Int, y: Double) {
        guard !pointer.dragging, track >= 0, trackRowCount() >= 2 else { return }
        pointer.dragging = true
        pointer.dragArmed = false
        request(.setCursorClosedHand)
        updateReorder(y: y)
    }

    private func updateReorder(y: Double) {
        guard pointer.dragging else { return }
        let trackRows = trackRowCount()
        var slot = 0
        let content = contentY(y)
        while slot < trackRows
            && content > Double(slot) * Double(geometry.rowHeight)
                + Double(geometry.rowHeight) / 2.0
        {
            slot += 1
        }
        let indicatorY = Double(slot) * Double(geometry.rowHeight) - scrollY
        if reorderIndicatorVisible && reorderIndicatorY == indicatorY { return }
        reorderIndicatorVisible = true
        reorderIndicatorY = indicatorY
        emit(.reorder)
    }

    private func reorderTarget(fromTrack: Int, dropSlot: Int) -> Int? {
        let trackRows = trackRowCount()
        guard dropSlot >= 0, dropSlot <= trackRows else { return nil }
        var fromIndex = -1
        for row in 0..<trackRows where rows[row].track == fromTrack {
            fromIndex = row
            break
        }
        guard fromIndex >= 0, dropSlot != fromIndex, dropSlot != fromIndex + 1 else { return nil }
        let targetIndex = dropSlot > fromIndex ? dropSlot - 1 : dropSlot
        return rows[targetIndex].track
    }

    private func finishReorder(commit: Bool) {
        guard pointer.dragging else { return }
        let fromTrack = pointer.pressedTrack
        let dropSlot = reorderIndicatorVisible
            ? Int(((reorderIndicatorY + scrollY) / Double(geometry.rowHeight)).rounded())
            : -1
        pointer.dragging = false
        pointer.dragArmed = false
        if reorderIndicatorVisible || reorderIndicatorY != 0.0 {
            reorderIndicatorVisible = false
            reorderIndicatorY = 0.0
            emit(.reorder)
        }
        request(.clearCursor)
        guard commit, let target = reorderTarget(fromTrack: fromTrack, dropSlot: dropSlot)
        else { return }
        finishRename(commit: true, restoreRollFocus: false)
        _ = commands.submit(
            .trackReorder(track: Int32(fromTrack), newIndex: Int32(target)))
    }

    // MARK: - Context menu (revision-guarded snapshot)

    public func menuOpened(documentId: UInt64, revision: UInt64, track: Int32) {
        pendingMenu = PendingHeaderMenu(
            documentId: documentId, documentRevision: revision, track: Int(track))
    }

    public func menuClosed() {
        pendingMenu = nil
    }

    // Returns true when the shell should refocus the header band (the session
    // is no longer open and no foreign popup claimed it). Host actions run
    // through the action callback; document ops submit intents.
    public func menuAction(_ actionId: Int32, sessionStillOpen: Bool) -> Bool {
        guard let target = pendingMenu else { return false }
        pendingMenu = nil
        guard let document = documents.document,
            document.documentId == target.documentId,
            document.revision == target.documentRevision
        else { return false }

        if !sessionStillOpen { request(.focusHeaderBand) }
        switch HeaderMenuAction(rawValue: actionId) {
        case .changeVoice:
            request(.queueEditTrackVoice, track: Int32(target.track),
                    a: Double(target.documentRevision))
        case .showVoiceInVoicegroup:
            request(.revealTrackVoice, track: Int32(target.track))
        case .renameTrack:
            beginRename(Int32(target.track))
        case .duplicateTrack:
            _ = commands.submit(.trackDuplicate(track: Int32(target.track)))
        case .deleteTrack:
            _ = commands.submit(.trackDelete(track: Int32(target.track)))
        case nil:
            break
        }
        return true
    }

    // MARK: - Keys (sgk_ delivery)

    private func answerKey(_ facts: SgkKeyFacts) -> Bool {
        guard let command = EditCommand(rawValue: Int(facts.command)),
            let origin = EditKeyOrigin(rawValue: Int(facts.origin))
        else { return false }
        let snapshot = sessions.session
        let surface = EditSurfaceState(
            pointerGestureActive: pointer.dragging,
            timeSelectionActive: snapshot?.timeSelection.active ?? false,
            noteSelectionEmpty: snapshot?.selectedNoteIds.isEmpty ?? true,
            origin: origin,
            autoRepeat: facts.autoRepeat != 0,
            commandAvailable: facts.commandAvailable != 0)
        // Only consume verdicts swallow the key; execute and decline defer so
        // execution stays in the single host tier (INV-2).
        return EditKeyArbiter.decide(command: command, surface: surface) == .consume
    }
}

