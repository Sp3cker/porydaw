import Foundation
import PorydawCore
import QtBridge

@MainActor
@QtBridgeable
public final class RulerMenuRow {
    public var actionId: Int = 0
    public var text: String = ""
    public var enabled: Bool = true
    public var separator: Bool = false

    public init() {}

    init(_ id: Int, _ title: String, _ available: Bool = true) {
        actionId = id
        text = title
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
    private static let controlModifier = 0x0400_0000
    @QtTracked public var isOpen = false
    public var rows: QListModel<RulerMenuRow> = QListModel()
    @QtTracked public var menuKind = 0 // 1: ruler background; 2: selected time range
    @QtTracked public var insertTimePromptOpen = false
    public var insertTimePromptAppearance: [String: QVariantSettable] = [:]
    public var insertTimePromptFont: [String: QVariantSettable] = [:]
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

    private let session: DocumentSession
    private let grid: PianoGrid
    private let automation: AutomationPage
    private var capturedRevision: UInt64 = 0
    private var capturedSelection: AutomationTimeSelection?
    private var capturedTick: Tick = 0
    private var capturedCursor: Tick = 0
    private var sweepAnchor: Tick?
    private var sweepWasRange = false
    private var sweepMultiTrack = false
    private var pendingInsert: (tick: Tick, revision: UInt64, beatTicks: UInt32, beatsPerBar: UInt32)?
    @QtIgnored public var onSeek: ((Tick) -> Void)?
    private var rowSnapshot: [RulerMenuRow] = []

    public init(session: DocumentSession, grid: PianoGrid, automation: AutomationPage) {
        self.session = session
        self.grid = grid
        self.automation = automation
    }

    /// The raw press position determines selection containment before snapping;
    /// a press on an existing range does not move the cursor or clear it.
    public func openRuler(contentX: Double, chipTick: Double = -1) {
        guard contentX.isFinite else { return }
        let raw = session.camera.tickAtContentX(contentX)
        guard raw.isFinite else { return }
        let chip = chipTick.isFinite && chipTick >= 0 && chipTick < Double(TimeDefaults.noTick)
            ? Tick(chipTick) : nil
        let insideTick = chip.map { Double($0) } ?? raw
        let inside = automation.selection?.contains(TimeDefaults.tick(from: max(0, insideTick))) == true
        let tick = chip ?? snapped(raw)
        if !inside {
            automation.clearTimeSelection()
            session.editCursor = tick
            onSeek?(tick)
        }
        capturedTick = tick
        capturedSelection = automation.selection
        capturedCursor = session.editCursor
        capturedRevision = session.document.revision
        let loop = session.timeline
        let hasLoop = loop.loopStartTick != TimeDefaults.noTick || loop.loopEndTick != TimeDefaults.noTick
        var items: [RulerMenuRow] = []
        if inside {
            items = [RulerMenuRow(Action.loopFromSelection.rawValue, "Loop from Selection"),
                     RulerMenuRow(Action.insertTime.rawValue, "Insert Time",
                                  automation.selectionCommandAvailable(command: .insertTime)),
                     RulerMenuRow(Action.duplicate.rawValue, "Duplicate Time",
                                  automation.selectionCommandAvailable(command: .duplicate)),
                     RulerMenuRow(Action.removeContents.rawValue, "Delete Time",
                                  automation.selectionCommandAvailable(command: .deleteTime)),
                     RulerMenuRow(Action.clearSelection.rawValue, "Clear Time Selection"),
                     .divider(), RulerMenuRow(Action.removeLoop.rawValue, "Remove Loop Markers", hasLoop)]
        } else {
            items = [RulerMenuRow(Action.insertTime.rawValue, "Insert Time",
                                  tick < TimeDefaults.maxTick),
                     RulerMenuRow(Action.paste.rawValue, "Paste", canPaste),
                     .divider(), RulerMenuRow(Action.setLoopStart.rawValue, "Set Loop Start"),
                     RulerMenuRow(Action.setLoopEnd.rawValue, "Set Loop End"),
                     RulerMenuRow(Action.removeLoop.rawValue, "Remove Loop Markers", hasLoop),
                     .divider(), RulerMenuRow(Action.editTimeSignature.rawValue, "Edit Time Signature")]
            let explicit = session.document.timeSignatures.contains { $0.tick == tick }
            items.append(RulerMenuRow(Action.removeTimeSignature.rawValue, "Remove Time Signature", explicit))
        }
        publish(items)
        menuKind = 1
    }

    /// Called when a press on the roll lands inside the shared range; a roll
    /// sweep itself remains owned by the roll interaction lane.
    public func openTimeSelection(contentX: Double) {
        guard contentX.isFinite else { return }
        let raw = session.camera.tickAtContentX(contentX)
        guard raw.isFinite,
              let selection = automation.selection, selection.isActive,
              selection.contains(TimeDefaults.tick(from: max(0, raw)))
        else { return }
        capturedTick = snapped(raw)
        capturedRevision = session.document.revision
        capturedCursor = session.editCursor
        capturedSelection = selection
        publish([RulerMenuRow(Action.copy.rawValue, "Copy",
                              automation.selectionCommandAvailable(command: .copy)),
                 RulerMenuRow(Action.cut.rawValue, "Cut",
                              automation.selectionCommandAvailable(command: .cut)),
                 RulerMenuRow(Action.deleteSelection.rawValue, "Delete Selection",
                              automation.selectionCommandAvailable(command: .delete)),
                 RulerMenuRow(Action.insertTime.rawValue, "Insert Time",
                              automation.selectionCommandAvailable(command: .insertTime)),
                 RulerMenuRow(Action.duplicate.rawValue, "Duplicate Time",
                              automation.selectionCommandAvailable(command: .duplicate)),
                 RulerMenuRow(Action.removeContents.rawValue, "Delete Time",
                              automation.selectionCommandAvailable(command: .deleteTime)),
                 RulerMenuRow(Action.paste.rawValue, "Paste", canPaste),
                 .divider(),
                 RulerMenuRow(Action.clearSelection.rawValue, "Clear Time Selection")])
        menuKind = 2
    }

    private var canPaste: Bool {
        guard automation.selectionCommandAvailable(command: .paste),
              let clip = automation.clipboard.read()?.clip else { return false }
        return clip.tracks.contains { !$0.notes.isEmpty }
            || clip.lanes.contains { !$0.points.isEmpty } || !clip.tempo.isEmpty
    }

    public func close() {
        isOpen = false
        menuKind = 0
        rowSnapshot = []
        rows.replaceSubrange(0..<rows.count, with: [])
    }

    public func targetTick() -> Double { Double(capturedTick) }

    /// Returns true only when the guarded edit-time-signature row should open
    /// the existing form, after the menu is already dismissed.
    public func activate(actionId: Int) -> Bool {
        guard isOpen, let action = Action(rawValue: actionId),
              rowSnapshot.contains(where: { $0.actionId == actionId && $0.enabled && !$0.separator })
        else { return false }
        let valid = session.document.revision == capturedRevision
            && session.editCursor == capturedCursor
            && automation.selection == capturedSelection
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

    private func openInsertTimePrompt() {
        let segment = session.projectionCache.timeAxis.segmentAt(capturedTick)
        pendingInsert = (capturedTick, session.document.revision,
                         segment.beatTicks, segment.beatsPerBar)
        insertTimePromptMaximumBeats = Int(segment.beatsPerBar - 1)
        var appearance = PromptAppearance.metrics(base: grid.baseFontPx)
        insertTimePromptFont = PromptAppearance.font(base: grid.baseFontPx)
        let palette = grid.palette
        appearance["background"] = palette.chromeBackground
        appearance["text"] = palette.primaryText
        appearance["buttonText"] = palette.primaryText
        appearance["buttonBackground"] = palette.chromeBackground
        appearance["pressedBackground"] = palette.hoverChipFill
        appearance["focus"] = palette.editCursor
        appearance["selection"] = palette.tabSelectedBackground
        appearance["selectionText"] = palette.selectionText
        appearance["outline"] = palette.separator
        insertTimePromptAppearance = appearance
        insertTimePromptOpen = true
    }

    public func cancelInsertTimePrompt() {
        pendingInsert = nil
        insertTimePromptOpen = false
    }

    public func acceptInsertTimePrompt(bars: Int, beats: Int, fractions: Int) {
        guard let pendingInsert,
              (insertTimePromptMinimumBars...insertTimePromptMaximumBars).contains(bars),
              (insertTimePromptMinimumBeats...insertTimePromptMaximumBeats).contains(beats),
              (insertTimePromptMinimumBeatFractions...insertTimePromptMaximumBeatFractions).contains(fractions)
        else { return }
        cancelInsertTimePrompt()
        guard session.document.revision == pendingInsert.revision else { return }
        let beat = UInt64(pendingInsert.beatTicks)
        let span = UInt64(bars) * beat * UInt64(pendingInsert.beatsPerBar)
            + UInt64(beats) * beat + (UInt64(fractions) * beat + 3) / 4
        guard span > 0, span <= UInt64(TimeDefaults.maxTick - pendingInsert.tick) else { return }
        _ = session.document.insertBlankTime(
            TimeRange(startTick: pendingInsert.tick, endTick: pendingInsert.tick + Tick(span)),
            scope: TimeScope(wholeSong: true))
    }

    public func beginSweep(contentX: Double, modifiers: Int = 0) {
        guard contentX.isFinite else { return }
        close()
        let raw = session.camera.tickAtContentX(contentX)
        guard raw.isFinite else { return }
        sweepAnchor = snapped(raw)
        sweepWasRange = false
        sweepMultiTrack = modifiers & Self.controlModifier != 0
    }

    public func updateSweep(contentX: Double) {
        guard let sweepAnchor, contentX.isFinite else { return }
        let raw = session.camera.tickAtContentX(contentX)
        guard raw.isFinite else { return }
        let tick = snapped(raw)
        guard tick != sweepAnchor else {
            if sweepWasRange { automation.clearTimeSelection() }
            return
        }
        sweepWasRange = true
        let start = min(sweepAnchor, tick)
        let end = max(sweepAnchor, tick)
        automation.applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: start, endTick: end),
            scope: .tracks(sweepTrackScope(start: start, end: end))))
    }

    public func endSweep(contentX: Double) {
        updateSweep(contentX: contentX)
        if sweepWasRange {
            if automation.selection?.isActive != true {
                automation.clearTimeSelection()
            }
        } else if let sweepAnchor {
            session.editCursor = sweepAnchor
            onSeek?(sweepAnchor)
        }
        sweepAnchor = nil
        sweepWasRange = false
        sweepMultiTrack = false
    }

    public func cancelSweep() {
        sweepAnchor = nil
        sweepWasRange = false
        sweepMultiTrack = false
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

    private func snapped(_ raw: Double) -> Tick {
        let position = min(Double(TimeDefaults.maxTick), max(0, raw))
        let lower = grid.snapTickDown(position)
        let upper = min(Int(TimeDefaults.maxTick), lower + max(1, grid.snapTicks))
        let nearest = position - Double(lower) <= Double(upper) - position ? lower : upper
        return Tick(nearest)
    }

    private func publish(_ items: [RulerMenuRow]) {
        close()
        rowSnapshot = items
        rows.replaceSubrange(0..<rows.count, with: items)
        isOpen = true
    }
}
