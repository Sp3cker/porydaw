import Foundation
import PorydawAppCommands
import PorydawCore

@testable import PorydawApp

// Range delete (window command, range menu), time-range paste overwrite, and lane-menu paste/clear.
// Paste round-trips the clip through ClipboardCodec in memory; the native system clipboard is never touched.

@MainActor
func drawingRangeScenarios(_ applies: @escaping @MainActor (BenchFixture) -> Bool) -> [BenchScenario] {
    /// Selects the tested and companion lanes over `[targetTick, nodes * 24)`:
    /// every node but the first and last.
    func prepareDelete(_ f: BenchFixture, _ box: DrawingBox) throws -> TimeRange {
        box.reset()
        try drawingSeedCompanion(f, box)
        guard let companion = box.s.companion else { throw BenchFailure(description: "no companion lane") }
        let range = TimeRange(startTick: f.targetTick, endTick: Tick(f.nodes * 24))
        f.page.selectRange(from: range.startTick, to: range.endTick, lanes: [f.parameter, companion])
        try f.check(f.page.resolvedSelectionScope() != nil, "the multi-lane selection resolved no scope")
        drawingCapture(f, box)
        box.s.expected = box.s.before.filter { !range.contains($0.tick) }
        box.s.companionExpected = box.s.companionBefore.filter { !range.contains($0.tick) }
        try f.check(
            box.s.expected.count < box.s.before.count
                && box.s.companionExpected.count < box.s.companionBefore.count,
            "the selected range covers no points on one of its lanes")
        return range
    }
    func validateDelete(_ f: BenchFixture, _ box: DrawingBox, _ what: String) throws {
        try f.check(f.runResult, "\(what): the range delete reported no action")
        try drawingExpectOneEdit(f, box, what)
        try drawingExpectLane(f, box.s.expected, what)
        try drawingExpectCompanion(f, box, box.s.companionExpected, what)
    }

    let command = DrawingBox()
    let menu = DrawingBox()
    let paste = DrawingBox()
    return [
        BenchScenario(
            name: "range.delete.command.multiLane", applies: applies,
            prepare: { f in _ = try prepareDelete(f, command) },
            run: { f in f.runResult = f.page.consumeSelectionCommand(command: .delete) },
            validate: { f in try validateDelete(f, command, "range.delete.command.multiLane") }),
        BenchScenario(
            name: "range.delete.menu.multiLane", applies: applies,
            prepare: { f in
                let range = try prepareDelete(f, menu)
                let menuY = try drawingLevels(f).alternateY
                f.page.openRangeMenu(x: f.x(range.startTick + range.span / 2), y: menuY)
                try f.check(
                    f.page.menuOpen
                        && f.page.menuRowActions.contains(AutomationMenuAction.rangeDelete.rawValue),
                    "the range menu did not open with its Delete row")
                // Opening a menu writes nothing; the baseline stays valid.
                try drawingExpectUntouched(f, menu, "range menu open")
            },
            run: { f in f.runResult = f.page.consumeMenuAction(actionId: AutomationMenuAction.rangeDelete.rawValue) },
            validate: { f in
                try validateDelete(f, menu, "range.delete.menu.multiLane")
                try f.check(!f.page.menuOpen, "range.delete.menu.multiLane: the menu stayed open")
            }),
        BenchScenario(
            name: "range.paste.overwrite", applies: applies,
            prepare: { f in
                paste.reset()
                // Copy the first half of the nodes and paste them one node later,
                // so every pasted point lands on an occupied tick of the other value.
                let range = TimeRange(
                    startTick: f.sourceTick,
                    endTick: f.sourceTick + Tick((f.nodes / 2) * 24))
                f.page.selectRange(from: range.startTick, to: range.endTick, lanes: [f.parameter])
                guard let scope = f.page.resolvedSelectionScope(),
                    let clip = ClipboardSemantics.extractTimeRange(
                        range, scope: scope, from: f.document,
                        unterminatedDuration: f.page.selectionSnapDuration()),
                    let data = ClipboardCodec.encode(clip, ticksPerBeat: UInt32(f.document.ticksPerBeat))
                else {
                    throw BenchFailure(description: "the selected range produced no clip")
                }
                paste.s.clipData = data
                paste.s.pasteCursor = f.targetTick
                paste.s.pasteTrack = f.page.activeTrack() ?? 0
                paste.s.pasteSpan = clip.span
                drawingCapture(f, paste)
                let offset = f.targetTick - range.startTick
                let written = paste.s.before.filter { range.contains($0.tick) }
                    .map { AutomationLanePoint(tick: $0.tick + offset, value: $0.value) }
                let overwritten = Set(written.map(\.tick))
                try f.check(
                    !written.isEmpty
                        && overwritten.allSatisfy { tick in paste.s.before.contains { $0.tick == tick } },
                    "the paste would not overwrite occupied ticks")
                paste.s.expected = paste.s.before.filter { !overwritten.contains($0.tick) } + written
            },
            run: { f in
                guard let data = paste.s.clipData, let decoded = ClipboardCodec.decode(data) else {
                    f.runResult = false
                    return
                }
                let clip = ClipboardCodec.rescale(
                    decoded.clip, sourceTicksPerBeat: decoded.ticksPerBeat,
                    destinationTicksPerBeat: UInt32(f.document.ticksPerBeat))
                let cursor = paste.s.pasteCursor
                f.runResult = f.session.withStateChanges { () -> Bool in
                    guard
                        let result = ClipboardSemantics.paste(
                            clip, at: cursor, selectedTrack: paste.s.pasteTrack,
                            into: f.document)
                    else { return false }
                    f.session.editCursor = result.nextCursor
                    f.page.clearTimeSelection()
                    f.page.refreshFromDocument()
                    return true
                }
            },
            validate: { f in
                let what = "range.paste.overwrite"
                try f.check(f.runResult, "\(what): the paste wrote nothing")
                try drawingExpectOneEdit(f, paste, what)
                try drawingExpectLane(f, paste.s.expected, what)
                let occurrences = drawingSources(f, f.parameter).map(\.tick)
                try f.check(
                    Set(occurrences).count == occurrences.count,
                    "\(what): an overwritten tick kept two occurrences")
                try f.check(
                    f.session.editCursor == paste.s.pasteCursor + paste.s.pasteSpan,
                    "\(what): the edit cursor is \(f.session.editCursor), expected the paste end")
                try f.check(f.page.selection == nil, "\(what): the paste kept the time selection")
            }),
    ]
}

@MainActor
func drawingLaneMenuScenarios(_ applies: @escaping @MainActor (BenchFixture) -> Bool) -> [BenchScenario] {
    func openLaneMenu(_ f: BenchFixture, _ parameter: AutomationParameter) throws {
        try f.check(
            f.page.openParameterMenu(index: f.page.catalogIndex(of: parameter), x: 0, y: 0)
                && f.page.menuOpen,
            "the lane menu did not open for \(parameter)")
    }
    func validateReplace(_ f: BenchFixture, _ box: DrawingBox, _ what: String) throws {
        guard let edit = box.s.edit else { throw BenchFailure(description: "\(what): no expected edit") }
        try f.check(f.runResult, "\(what): the menu row was refused")
        try f.check(!f.page.menuOpen, "\(what): the menu stayed open")
        try drawingExpectOneEdit(f, box, what)
        try drawingExpectLane(f, drawingApplying(edit, to: box.s.before), what)
        try drawingExpectCompanion(f, box, box.s.companionBefore, what)
    }

    let paste = DrawingBox()
    let clear = DrawingBox()
    return [
        BenchScenario(
            name: "lane.paste.replace", applies: applies,
            prepare: { f in
                paste.reset()
                try drawingSeedCompanion(f, paste)
                guard let companion = paste.s.companion else { throw BenchFailure(description: "no companion lane") }
                // The lane menu's clipboard is the page's own absolute-tick copy,
                // separate from the system clipboard.
                try openLaneMenu(f, companion)
                try f.check(
                    f.page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                    "the companion lane's Copy row was refused")
                try openLaneMenu(f, f.parameter)
                try f.check(
                    f.page.menuRowActions.contains(AutomationMenuAction.pasteLane.rawValue),
                    "the tested lane menu offers no Paste (replace) row")
                guard let points = f.page.laneClipPoints(f.parameter) else {
                    throw BenchFailure(description: "the copied lane is not available to the tested lane")
                }
                let edit = AutomationRangeEditor.replaceLane(f.facts(), points: points)
                try f.check(!edit.unchanged, "the pasted lane equals the tested lane")
                paste.s.edit = edit
                drawingCapture(f, paste)
            },
            run: { f in f.runResult = f.page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue) },
            validate: { f in try validateReplace(f, paste, "lane.paste.replace") }),
        BenchScenario(
            name: "lane.clear", applies: applies,
            prepare: { f in
                clear.reset()
                try openLaneMenu(f, f.parameter)
                try f.check(
                    f.page.menuRowActions.contains(AutomationMenuAction.clearLane.rawValue),
                    "the tested lane menu offers no Clear row")
                clear.s.edit = AutomationRangeEditor.replaceLane(f.facts(), points: [])
                drawingCapture(f, clear)
            },
            run: { f in f.runResult = f.page.consumeMenuAction(actionId: AutomationMenuAction.clearLane.rawValue) },
            validate: { f in try validateReplace(f, clear, "lane.clear") }),
    ]
}
