import Foundation
import PorydawCore
import PorydawDocument
import QtBridge
import PorydawAppCommands
import PorydawAppPresentation

@MainActor
@QtBridgeable
public final class RulerMenuRow {
    public var actionId: Int = 0
    public var text: String = ""
    public var shortcutText: String = ""
    public var enabled: Bool = true
    public var separator: Bool = false

    public init() {}

    init(_ id: Int, _ available: Bool = true) {
        actionId = id
        enabled = available
    }

    static func divider() -> RulerMenuRow {
        let row = RulerMenuRow()
        row.actionId = -1
        row.separator = true
        row.enabled = false
        return row
    }
}

/// The positional ruler menu and its selection-scoped variant share the
/// document's automation selection, clipboard and history command executor.
@MainActor
@QtBridgeable
public final class RulerMenuPresenter {
    private enum Action: Int {
        case insertTime = 1, setLoopStart, setLoopEnd, removeLoop, loopFromSelection
        case duplicate, removeContents, clearSelection, editTimeSignature
        case removeTimeSignature, copy, cut, paste, deleteSelection
    }
    private static let keybindingIds: [Action: String] = [
        .copy: "roll.copy", .cut: "roll.cut", .paste: "roll.paste",
        .deleteSelection: "roll.delete", .insertTime: "edit.insert_time",
        .duplicate: "roll.duplicate_time", .removeContents: "edit.delete_time",
        .clearSelection: "edit.clear_time_selection",
        .loopFromSelection: "edit.loop_from_selection",
        .setLoopStart: "edit.set_loop_start", .setLoopEnd: "edit.set_loop_end",
        .removeLoop: "edit.remove_loop",
        .editTimeSignature: "edit.edit_time_signature",
        .removeTimeSignature: "edit.remove_time_signature",
    ]
    private let keybindings = KeybindingRegistry()
    private static let controlModifier = 0x0400_0000
    @QtTracked public var isOpen = false
    public var rows: QListModel<RulerMenuRow> = QListModel()
    @QtTracked public var menuKind = 0  // 1: ruler background; 2: selected time range
    @QtTracked public var insertTimePromptOpen = false
    @QtTracked public var promptStyle = PromptStyle()
    public var insertTimePromptTitle: String = "Insert Time"
    public var insertTimePromptInitialBars: Int = 1
    public var insertTimePromptInitialBeats: Int = 0
    public var insertTimePromptInitialBeatFractions: Int = 0
    public var insertTimePromptMinimumBars: Int = 0
    public var insertTimePromptMaximumBars: Int = 9999
    public var insertTimePromptMinimumBeats: Int = 0
    @QtTracked public var insertTimePromptMaximumBeats = 3
    public var insertTimePromptMinimumBeatFractions: Int = 0
    public var insertTimePromptMaximumBeatFractions: Int = 3
    /// The pointer is over, or dragging, a ruler loop marker: QML shows the resize cursor.
    @QtTracked public var loopMarkerHovered = false

    private let viewport: DocumentViewport
    private var session: DocumentSession { viewport.session }
    private let grid: PianoGrid
    private let automation: AutomationPage
    private var capturedRevision: UInt64 = 0
    private var capturedSelection: AutomationTimeSelection?
    private var capturedTick: Tick = 0
    private var capturedCursor: Tick = 0
    private var rulerPress: (raw: Double, chip: Tick?)?
    private var sweepAnchor: Tick?
    private var sweepPressX = 0.0
    private var sweepPressY = 0.0
    private var sweepWasRange = false
    private var sweepMultiTrack = false
    /// A press on a loop marker: a click places the edit cursor, a drag moves the marker as one undo step.
    private struct LoopMarkerDrag {
        let end: Bool
        let origin: Tick
        let pressTick: Tick
        let pressX: Double
        let pressY: Double
        let group = HistoryGroup()
        var moved = false
    }
    private var loopDrag: LoopMarkerDrag?
    private var pendingInsert: (tick: Tick, revision: UInt64, beatTicks: UInt32, beatsPerBar: UInt32)?
    /// Fork commitEditCursor egress, installed by the owning session.
    @QtIgnored public var onCommitCursor: ((Tick) -> Void)?
    private var rowSnapshot: [RulerMenuRow] = []
    private var clipboardObserver: UUID?
    private var selectionObserver: UUID?

    public init(viewport: DocumentViewport, grid: PianoGrid, automation: AutomationPage) {
        self.viewport = viewport
        self.grid = grid
        self.automation = automation
        selectionObserver = session.addSelectionTransitionObserver { [weak self] _ in
            if self?.isOpen == true { self?.close() }
        }
        clipboardObserver = automation.clipboard.addChangeObserver { [weak self] in
            if self?.isOpen == true { self?.close() }
        }
    }

    isolated deinit {
        if let clipboardObserver { automation.clipboard.removeChangeObserver(clipboardObserver) }
        if let selectionObserver { session.removeSelectionTransitionObserver(selectionObserver) }
    }

    public func captureRulerPress(contentX: Double, pointerY: Double) {
        guard contentX.isFinite, pointerY.isFinite else { return }
        let raw = viewport.camera.tickAtContentX(contentX)
        guard raw.isFinite else { return }
        if isOpen { close() }
        let chip = signatureTick(at: contentX, pointerY: pointerY)
        rulerPress = (raw, chip)
    }

    public func openRulerAtRelease() {
        guard let press = rulerPress else { return }
        rulerPress = nil
        let insideTick = press.chip.map { Double($0) } ?? press.raw
        let inside = session.timeSelection?.contains(TimeDefaults.tick(from: max(0, insideTick))) == true
        let tick = press.chip ?? snapped(press.raw)
        if !inside {
            session.clearTimeSelection()
            commitCursor(tick)
        }
        capturedTick = tick
        capturedSelection = session.timeSelection
        capturedCursor = session.editCursor
        capturedRevision = session.document.revision
        let loop = session.timeline
        let hasLoop = loop.loopStartTick != TimeDefaults.noTick || loop.loopEndTick != TimeDefaults.noTick
        var items: [RulerMenuRow] = []
        if inside {
            items = [
                RulerMenuRow(Action.loopFromSelection.rawValue),
                RulerMenuRow(
                    Action.insertTime.rawValue,
                    automation.selectionCommandAvailable(command: .insertTime)),
                RulerMenuRow(
                    Action.duplicate.rawValue,
                    automation.selectionCommandAvailable(command: .duplicate)),
                RulerMenuRow(
                    Action.removeContents.rawValue,
                    automation.selectionCommandAvailable(command: .deleteTime)),
                RulerMenuRow(Action.clearSelection.rawValue),
                .divider(), RulerMenuRow(Action.removeLoop.rawValue, hasLoop),
            ]
        } else {
            items = [
                RulerMenuRow(Action.insertTime.rawValue, tick < TimeDefaults.maxTick),
                RulerMenuRow(Action.paste.rawValue, canPaste),
                .divider(), RulerMenuRow(Action.setLoopStart.rawValue),
                RulerMenuRow(Action.setLoopEnd.rawValue),
                RulerMenuRow(Action.removeLoop.rawValue, hasLoop),
                .divider(), RulerMenuRow(Action.editTimeSignature.rawValue),
            ]
            let explicit = press.chip == tick
            items.append(RulerMenuRow(Action.removeTimeSignature.rawValue, explicit))
        }
        if automation.hasMenu { automation.dismissMenu() }
        if grid.gridMenuKind != 0 { grid.dismissGridMenu() }
        publish(items)
        menuKind = 1
    }

    /// Called when a press on the roll lands inside the shared range; a roll
    /// sweep itself remains owned by the roll interaction lane.
    public func openTimeSelection(contentX: Double) {
        guard contentX.isFinite else { return }
        let raw = viewport.camera.tickAtContentX(contentX)
        guard raw.isFinite,
            let selection = session.timeSelection, selection.isActive,
            selection.contains(TimeDefaults.tick(from: max(0, raw)))
        else { return }
        publishTimeSelection(selection: selection, tick: snapped(raw))
    }

    public func openTimeSelection(tick: Tick) {
        guard let selection = session.timeSelection, selection.isActive,
            selection.contains(tick)
        else { return }
        publishTimeSelection(selection: selection, tick: tick)
    }

    private func publishTimeSelection(selection: AutomationTimeSelection, tick: Tick) {
        capturedTick = tick
        capturedRevision = session.document.revision
        capturedCursor = session.editCursor
        capturedSelection = selection
        if automation.hasMenu { automation.dismissMenu() }
        if grid.gridMenuKind != 0 { grid.dismissGridMenu() }
        publish([
            RulerMenuRow(
                Action.copy.rawValue,
                automation.selectionCommandAvailable(command: .copy)),
            RulerMenuRow(
                Action.cut.rawValue,
                automation.selectionCommandAvailable(command: .cut)),
            RulerMenuRow(
                Action.deleteSelection.rawValue,
                automation.selectionCommandAvailable(command: .delete)),
            RulerMenuRow(
                Action.insertTime.rawValue,
                automation.selectionCommandAvailable(command: .insertTime)),
            RulerMenuRow(
                Action.duplicate.rawValue,
                automation.selectionCommandAvailable(command: .duplicate)),
            RulerMenuRow(
                Action.removeContents.rawValue,
                automation.selectionCommandAvailable(command: .deleteTime)),
            RulerMenuRow(Action.paste.rawValue, canPaste),
            .divider(),
            RulerMenuRow(Action.clearSelection.rawValue),
        ])
        menuKind = 2
    }

    private var canPaste: Bool {
        automation.selectionCommandAvailable(command: .paste)
    }

    @QtIgnored
    public func sessionDidChange(_ change: SessionChange) {
        if isOpen && (change.revision != capturedRevision || change.domains.contains(.selection)) {
            close()
        }
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        menuKind = 0
        rowSnapshot = []
        rows.replaceSubrange(0..<rows.count, with: [])
    }

    public func targetTick() -> Double { Double(capturedTick) }

    public func menuRow(index: Int) -> Optional<RulerMenuRow> {
        guard index >= 0, index < rows.count else { return nil }
        return rows[index]
    }

    /// Returns true only when the guarded edit-time-signature row should open
    /// the existing form, after the menu is already dismissed.
    public func activate(actionId: Int) -> Bool {
        guard isOpen, let action = Action(rawValue: actionId),
            rowSnapshot.contains(where: { $0.actionId == actionId && $0.enabled && !$0.separator })
        else { return false }
        let valid =
            session.document.revision == capturedRevision
            && session.editCursor == capturedCursor
            && session.timeSelection == capturedSelection
        close()
        guard valid else { return false }
        if action == .paste && !canPaste { return false }
        if action == .insertTime && capturedSelection == nil {
            openInsertTimePrompt()
            return false
        }
        switch action {
        case .setLoopStart: session.document.setLoop(end: false, tick: Int64(capturedTick))
        case .setLoopEnd: session.document.setLoop(end: true, tick: Int64(capturedTick))
        case .removeLoop:
            session.document.setLoop(end: false, tick: nil)
            session.document.setLoop(end: true, tick: nil)
        case .editTimeSignature: return true
        case .removeTimeSignature: session.document.deleteTimeSignature(at: capturedTick)
        case .loopFromSelection, .duplicate, .removeContents, .clearSelection,
            .copy, .cut, .paste, .insertTime, .deleteSelection:
            let command: EditCommand
            switch action {
            case .loopFromSelection: command = .loopFromSelection
            case .duplicate: command = .duplicate
            case .removeContents: command = .deleteTime
            case .clearSelection: command = .clearTimeSelection
            case .copy: command = .copy
            case .cut: command = .cut
            case .deleteSelection: command = .delete
            case .paste: command = .paste
            case .insertTime: command = .insertTime
            default: preconditionFailure("Unexpected ruler command")
            }
            _ = automation.consumeSelectionCommand(command: command)
        }
        return false
    }

    public func openInsertTimePromptAtCursor() -> Bool {
        guard !session.isClosed, session.editCursor < TimeDefaults.maxTick,
            session.timeSelection?.isActive != true
        else { return false }
        capturedTick = session.editCursor
        openInsertTimePrompt()
        return true
    }

    private func openInsertTimePrompt() {
        let segment = session.projectionCache.timeAxis.segmentAt(capturedTick)
        pendingInsert = (
            capturedTick, session.document.revision,
            segment.beatTicks, segment.beatsPerBar
        )
        insertTimePromptMaximumBeats = Int(segment.beatsPerBar - 1)
        let typography = Typography(baseFontPx: Int(grid.baseFontPx.rounded()))
        promptStyle.update(
            metrics: PromptAppearance.Layout(base: grid.baseFontPx),
            palette: grid.palette, font: typography.body.qmlFont, surface: .chrome)
        insertTimePromptOpen = true
    }

    public func cancelInsertTimePrompt() {
        pendingInsert = nil
        insertTimePromptOpen = false
    }

    public func acceptInsertTimePrompt(bars: Int, beats: Int, fractions: Int) {
        let barsOK = insertTimePromptMinimumBars <= bars && bars <= insertTimePromptMaximumBars
        let beatsOK = insertTimePromptMinimumBeats <= beats && beats <= insertTimePromptMaximumBeats
        let fracsOK =
            insertTimePromptMinimumBeatFractions <= fractions
            && fractions <= insertTimePromptMaximumBeatFractions
        guard let pendingInsert, barsOK, beatsOK, fracsOK else { return }
        cancelInsertTimePrompt()
        guard session.document.revision == pendingInsert.revision else { return }
        let beat = UInt64(pendingInsert.beatTicks)
        let barTicks = UInt64(bars) * beat * UInt64(pendingInsert.beatsPerBar)
        let beatTicks = UInt64(beats) * beat
        let fracTicks = (UInt64(fractions) * beat + 3) / 4
        let span = barTicks + beatTicks + fracTicks
        guard span > 0, span <= UInt64(TimeDefaults.maxTick - pendingInsert.tick) else { return }
        _ = session.document.insertBlankTime(
            TimeRange(startTick: pendingInsert.tick, endTick: pendingInsert.tick + Tick(span)),
            scope: TimeScope(wholeSong: true))
    }

    public func beginSweep(contentX: Double, pointerY: Double, modifiers: Int = 0) {
        guard contentX.isFinite, pointerY.isFinite else { return }
        if isOpen { close() }
        rulerPress = nil
        loopDrag = nil
        let raw = viewport.camera.tickAtContentX(contentX)
        guard raw.isFinite else { return }
        sweepAnchor = snapped(raw)
        sweepPressX = contentX
        sweepPressY = pointerY
        sweepWasRange = false
        sweepMultiTrack = modifiers & Self.controlModifier != 0
    }

    /// A ruler press: a loop marker under the pointer starts a marker drag, else a range sweep.
    public func beginRulerSweep(contentX: Double, pointerY: Double, modifiers: Int = 0) {
        guard let marker = loopMarker(at: contentX, pointerY: pointerY) else {
            beginSweep(contentX: contentX, pointerY: pointerY, modifiers: modifiers)
            return
        }
        if isOpen { close() }
        rulerPress = nil
        sweepAnchor = nil
        loopDrag = LoopMarkerDrag(
            end: marker.end, origin: marker.tick,
            pressTick: snapped(viewport.camera.tickAtContentX(contentX)),
            pressX: contentX, pressY: pointerY)
        loopMarkerHovered = true
    }

    public func updateRulerHover(contentX: Double, pointerY: Double) {
        guard loopDrag == nil else { return }
        let hovered = loopMarker(at: contentX, pointerY: pointerY) != nil
        if loopMarkerHovered != hovered { loopMarkerHovered = hovered }
    }

    public func clearRulerHover() {
        guard loopDrag == nil, loopMarkerHovered else { return }
        loopMarkerHovered = false
    }

    public func updateSweep(contentX: Double, pointerY: Double = 0) {
        if loopDrag != nil {
            dragLoopMarker(contentX: contentX, pointerY: pointerY)
            return
        }
        guard let sweepAnchor, contentX.isFinite, pointerY.isFinite else { return }
        guard
            sweepWasRange
                || pastDragDistance(contentX, pointerY, fromX: sweepPressX, fromY: sweepPressY)
        else { return }
        sweepWasRange = true
        let raw = viewport.camera.tickAtContentX(contentX)
        guard raw.isFinite else { return }
        let tick = snapped(raw)
        guard tick != sweepAnchor else {
            session.clearTimeSelection()
            return
        }
        let start = min(sweepAnchor, tick)
        let end = max(sweepAnchor, tick)
        session.applyTimeSelection(
            AutomationTimeSelection(
                range: TimeRange(startTick: start, endTick: end),
                scope: .tracks(sweepTrackScope(start: start, end: end))))
    }

    public func endSweep(contentX: Double, pointerY: Double = 0) {
        if loopDrag != nil {
            dragLoopMarker(contentX: contentX, pointerY: pointerY)
            if let drag = loopDrag, !drag.moved { commitCursor(drag.pressTick) }
            loopDrag = nil
            return
        }
        updateSweep(contentX: contentX, pointerY: pointerY)
        if sweepWasRange {
            if session.timeSelection?.isActive != true { session.clearTimeSelection() }
        } else if let sweepAnchor {
            commitCursor(sweepAnchor)
        }
        sweepAnchor = nil
        sweepWasRange = false
        sweepMultiTrack = false
    }

    public func cancelSweep() {
        if let drag = loopDrag, drag.moved {
            session.document.setLoop(end: drag.end, tick: Int64(drag.origin), group: drag.group)
        }
        sweepAnchor = nil
        rulerPress = nil
        sweepWasRange = false
        sweepMultiTrack = false
        loopDrag = nil
        clearRulerHover()
    }

    private func commitCursor(_ tick: Tick) {
        session.editCursor = tick
        onCommitCursor?(tick)
    }

    private func pastDragDistance(_ x: Double, _ y: Double, fromX: Double, fromY: Double) -> Bool {
        abs(x - fromX) + abs(y - fromY) >= grid.dragDistance
    }

    /// Past the drag distance, moves the marker to the snapped pointer, one snap step short of the other marker.
    private func dragLoopMarker(contentX: Double, pointerY: Double) {
        guard var drag = loopDrag, contentX.isFinite, pointerY.isFinite,
            drag.moved || pastDragDistance(contentX, pointerY, fromX: drag.pressX, fromY: drag.pressY)
        else { return }
        drag.moved = true
        loopDrag = drag
        let timeline = session.timeline
        let other = drag.end ? timeline.loopStartTick : timeline.loopEndTick
        var target = snapped(viewport.camera.tickAtContentX(contentX))
        if other != TimeDefaults.noTick {
            let camera = viewport.camera
            target =
                drag.end
                ? max(target, viewport.grid.snapTickUp(Double(other) + 1, camera: camera))
                : min(target, viewport.grid.snapTickDown(max(0, Double(other) - 1), camera: camera))
        }
        session.document.setLoop(end: drag.end, tick: Int64(target), group: drag.group)
    }

    /// The loop marker whose line or bracket glyph lies under a marker-row pointer.
    private func loopMarker(at contentX: Double, pointerY: Double) -> (end: Bool, tick: Tick)? {
        guard contentX.isFinite, pointerY >= 0, pointerY < grid.rulerMarkerRowHeight
        else { return nil }
        let tolerance = max(4, grid.baseFontPx * 0.5)
        let glyphReach = grid.baseFontPx * 1.1
        func distance(_ tick: Tick) -> Double? {
            guard tick != TimeDefaults.noTick else { return nil }
            let x = viewport.camera.contentX(tick: Double(tick))
            guard contentX >= x - tolerance, contentX <= x + glyphReach else { return nil }
            return abs(contentX - x)
        }
        let timeline = session.timeline
        let start = distance(timeline.loopStartTick)
        if let end = distance(timeline.loopEndTick), start.map({ end < $0 }) ?? true {
            return (true, timeline.loopEndTick)
        }
        return start == nil ? nil : (false, timeline.loopStartTick)
    }

    private func sweepTrackScope(start: Tick, end: Tick) -> Set<Int> {
        let primary = session.selectedTrack ?? grid.trackIndex
        var mask: Set<Int> = [primary]
        guard sweepMultiTrack else { return mask }
        for track in 0..<session.document.engineTracks.usedTrackCount where track != primary {
            for note in session.document.notes(in: track)
            where note.tick < end && start < note.tick + note.duration {
                mask.insert(track)
                break
            }
        }
        return mask
    }

    func signatureTick(at contentX: Double, pointerY: Double) -> Tick? {
        guard contentX.isFinite, pointerY >= 0, pointerY < grid.rulerMarkerRowHeight
        else { return nil }
        let tolerance = max(4, grid.baseFontPx * 0.5)
        for signature in session.document.timeSignatures.reversed() {
            let x = viewport.camera.contentX(tick: Double(signature.tick))
            let labelWidth =
                Double("\(signature.numerator)/\(1 << min(signature.denominatorPower, 6))".count)
                * grid.baseFontPx * 0.6
            if abs(x - contentX) <= tolerance
                || (contentX >= x && contentX <= x + tolerance + labelWidth)
            {
                return signature.tick
            }
        }
        return nil
    }

    private func snapped(_ raw: Double) -> Tick {
        let position = min(Double(TimeDefaults.maxTick), max(0, raw))
        return viewport.grid.snapTick(position, camera: viewport.camera)
    }

    private func publish(_ items: [RulerMenuRow]) {
        close()
        for row in items {
            guard let action = Action(rawValue: row.actionId),
                let id = Self.keybindingIds[action]
            else { continue }
            row.text = keybindings.label(id)
            row.shortcutText = keybindings.sequences(id).first?.nativeText ?? ""
        }
        rowSnapshot = items
        rows.replaceSubrange(0..<rows.count, with: items)
        isOpen = true
    }
}
