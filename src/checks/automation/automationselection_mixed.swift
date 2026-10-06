import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
func drawerAutomationMixedSelectionFixture(
    suite: DocumentSession,
    service: ProjectService
) -> drawerAutomationAutomationFixture {
    drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(24, 32)],
        pan: [(0, 80), (96, 10), (96, 20), (144, 70), (144, 80), (384, 110)],
        lfo: [(0, 32), (96, 96), (384, 64)],
        tempo: [(0, 750_000), (96, 499_999), (384, 937_500)])
}

@MainActor
func drawerAutomationArmHorizontalTempoDrag(_ fixture: drawerAutomationAutomationFixture) -> Double {
    let page = fixture.page
    let sourceX = fixture.x(96)
    let sourceY = fixture.y(.tempo, 120)
    let activationX = sourceX + page.geometry.nodeDragActivationDistance + 2
    let endX = activationX + fixture.x(144) - sourceX
    _ = page.pointerPress(
        x: sourceX, y: sourceY, surface: 1,
        button: DrawerQtButton.left, modifiers: AutomationQtModifier.shift)
    _ = page.pointerMove(
        x: activationX, y: sourceY, buttons: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    _ = page.pointerMove(
        x: endX, y: sourceY, buttons: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    return endX
}

@MainActor
func drawerAutomationMixedSelectionDragPlayback(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::multiLaneSelectionDragPreservesTempoAndCcOrder"
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    let page = fixture.page
    page.selectRange(from: 96, to: 144, lanes: [fixture.panLane, fixture.lfoLane, .tempo])
    fixture.activate(fixture.panLane)
    fixture.activate(.tempo)
    let before = fixture.snapshot
    let history = fixture.document.history.undoCount
    let beforeBytes = try? fixture.document.state.file.encoded()
    let beforeIndex = fixture.document.history.undoIndex
    let panBefore = fixture.values(fixture.panLane)
    let lfoBefore = fixture.values(fixture.lfoLane)
    let tempoBefore = fixture.tempoValues
    let volumeBefore = fixture.values(fixture.volumeLane)
    let volumeRaw = fixture.document.rawChunks[1].events.filter {
        if case let .channel(status, controller, _) = $0.payload {
            return status >> 4 == 0xB && controller == TimeDefaults.ccVolume
        }
        return false
    }
    let volume = fixture.playbackValues(fixture.volumeLane, at: 24)
    var editedCount = 0
    let priorChange = fixture.session.onChange
    fixture.session.onChange = { change in
        if change.domains.contains(.document) && change.domains.contains(.dirty) {
            editedCount += 1
        }
        priorChange?(change)
    }
    let endX = drawerAutomationArmHorizontalTempoDrag(fixture)
    report.expect(
        fixture.snapshot == before
            && fixture.playbackValues(fixture.panLane, at: 96) == [10, 20]
            && fixture.playbackTempo(at: 96)?.microseconds == 499_999
            && editedCount == 0, cppID: id,
        message: "mixed selected Tempo drag keeps document and playback frozen while held")
    report.expect(
        (try? fixture.document.state.file.encoded()) == beforeBytes
            && fixture.document.history.undoIndex == beforeIndex
            && fixture.values(fixture.panLane) == panBefore
            && fixture.values(fixture.lfoLane) == lfoBefore
            && fixture.tempoValues == tempoBefore, cppID: id,
        message: "mixed drag preview leaves MIDI bytes index and all selected points unchanged")
    _ = page.pointerRelease(
        x: endX, y: fixture.y(.tempo, 120),
        button: DrawerQtButton.left, modifiers: AutomationQtModifier.shift)
    report.expect(
        editedCount == 1 && fixture.document.revision == before.revision + 1
            && fixture.document.history.undoCount == history + 1
            && fixture.document.isDirty, cppID: id,
        message: "mixed selected drag publishes one dirty edit and one history entry")
    report.expect(
        fixture.document.history.undoIndex == beforeIndex + 1, cppID: id,
        message: "mixed drag increments the applied undo index exactly once")
    report.expect(
        page.selection?.range == TimeRange(startTick: 144, endTick: 192)
            && page.selection?.scope == .lanes && page.selection?.tempo == true
            && page.selection?.lanes == Set([fixture.panLane, fixture.lfoLane]), cppID: id,
        message: "mixed selected drag translates its Tempo Pan LFO interval to 144 through 192")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96).isEmpty
            && fixture.playbackValues(fixture.panLane, at: 144) == [10, 20]
            && fixture.playbackValues(fixture.volumeLane, at: 24) == volume, cppID: id,
        message: "mixed selected drag publishes ordered Pan collisions and preserves Volume playback")
    report.expect(
        fixture.playbackValues(fixture.lfoLane, at: 96).isEmpty
            && fixture.playbackValues(fixture.lfoLane, at: 144) == [96], cppID: id,
        message: "mixed selected drag publishes the selected LFO into playback")
    report.expect(
        fixture.playbackTempo(at: 144)?.microseconds == 499_999
            && abs((fixture.playbackTempo(at: 144)?.bpm ?? 0) - 60000000.0 / 499999.0) < 0.001,
        cppID: id, message: "mixed selected drag publishes exact 499999-us Tempo at tick 144")
    report.expect(
        fixture.values(fixture.panLane) == ["0:80", "144:10", "144:20", "384:110"]
            && fixture.values(fixture.lfoLane) == ["0:32", "144:96", "384:64"],
        cppID: id, message: "mixed move preserves exact surviving raw Pan and LFO point order")
    let volumeAfter = fixture.document.rawChunks[1].events.filter {
        if case let .channel(status, controller, _) = $0.payload {
            return status >> 4 == 0xB && controller == TimeDefaults.ccVolume
        }
        return false
    }
    report.expect(
        fixture.values(fixture.volumeLane) == volumeBefore && volumeAfter == volumeRaw,
        cppID: id, message: "mixed Tempo Pan LFO move leaves unrelated Volume events byte-identical")
    report.expect(
        !page.interactionActive, cppID: id,
        message: "mixed selection drag finishes idle on pointer release")
    let committedBytes = try? fixture.document.state.file.encoded()
    let undid = fixture.undo()
    report.expect(
        undid && fixture.playbackValues(fixture.panLane, at: 96) == [10, 20]
            && fixture.playbackValues(fixture.panLane, at: 144) == [70, 80], cppID: id,
        message: "one undo restores both original Pan playback groups")
    report.expect(
        fixture.playbackValues(fixture.lfoLane, at: 96) == [96]
            && fixture.playbackTempo(at: 96)?.microseconds == 499_999, cppID: id,
        message: "one undo restores LFO and raw Tempo playback at tick 96")
    report.expect(
        undid && fixture.document.history.undoIndex == beforeIndex
            && (try? fixture.document.state.file.encoded()) == beforeBytes
            && fixture.values(fixture.panLane) == panBefore
            && fixture.values(fixture.lfoLane) == lfoBefore
            && fixture.tempoValues == tempoBefore, cppID: id,
        message: "mixed move undo restores prior index MIDI bytes and all selected points")
    let redid = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(
        redid && fixture.playbackValues(fixture.panLane, at: 144) == [10, 20]
            && fixture.playbackValues(fixture.panLane, at: 96).isEmpty, cppID: id,
        message: "one redo restores ordered moved Pan playback")
    report.expect(
        fixture.playbackValues(fixture.lfoLane, at: 144) == [96]
            && fixture.playbackTempo(at: 144)?.microseconds == 499_999, cppID: id,
        message: "one redo restores selected LFO and exact moved Tempo playback")
    report.expect(
        redid && fixture.document.history.undoIndex == beforeIndex + 1
            && (try? fixture.document.state.file.encoded()) == committedBytes
            && fixture.values(fixture.panLane) == ["0:80", "144:10", "144:20", "384:110"], cppID: id,
        message: "mixed move redo restores committed index MIDI bytes and Pan points")
}

@MainActor
func drawerAutomationTempoOnlyHorizontalPlayback(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::bandSelectionIsolatesTempoAndControlChangeRows"
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    fixture.activate(.tempo)
    fixture.page.selectRange(from: 72, to: 144, lanes: [.tempo])
    let before = fixture.snapshot
    let tempoIndex = fixture.document.history.undoIndex
    let pan = fixture.playbackValues(fixture.panLane, at: 96)
    var editedCount = 0
    let priorChange = fixture.session.onChange
    fixture.session.onChange = { change in
        if change.domains.contains(.document) && change.domains.contains(.dirty) {
            editedCount += 1
        }
        priorChange?(change)
    }
    let endX = drawerAutomationArmHorizontalTempoDrag(fixture)
    report.expect(
        fixture.snapshot == before && fixture.playbackTempo(at: 96)?.microseconds == 499_999
            && editedCount == 0, cppID: id,
        message: "Tempo-only horizontal drag freezes document and playback while held")
    _ = fixture.page.pointerRelease(
        x: endX, y: fixture.y(.tempo, 120),
        button: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expect(
        fixture.playbackTempo(at: 144)?.microseconds == 499_999
            && abs((fixture.playbackTempo(at: 144)?.bpm ?? 0) - 60000000.0 / 499999.0) < 0.001
            && fixture.playbackValues(fixture.panLane, at: 96) == pan, cppID: id,
        message: "Tempo-only horizontal drag publishes exact moved Tempo without touching Pan")
    report.expect(
        fixture.document.revision == before.revision + 1
            && fixture.document.history.undoIndex == tempoIndex + 1
            && fixture.values(fixture.panLane) == ["0:80", "96:10", "96:20", "144:70", "144:80", "384:110"]
            && fixture.values(fixture.lfoLane) == ["0:32", "96:96", "384:64"],
        cppID: id, message: "Tempo-scoped drag makes exactly one edit and leaves both raw CC rows untouched")
    let panLfo = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    panLfo.activate(panLfo.panLane)
    panLfo.page.selectRange(from: 96, to: 144, lanes: [panLfo.panLane, panLfo.lfoLane])
    let panX = panLfo.x(96)
    let panY = panLfo.y(panLfo.panLane, 20)
    let armX = panX + panLfo.page.geometry.nodeDragActivationDistance + 2
    let finishX = armX + panLfo.x(144) - panX
    let panLfoIndex = panLfo.document.history.undoIndex
    let panLfoBytes = try? panLfo.document.state.file.encoded()
    let panLfoBefore = panLfo.snapshot
    let panBefore = panLfo.values(panLfo.panLane)
    let lfoBefore = panLfo.values(panLfo.lfoLane)
    let tempoRow = panLfo.laneSnapshot(.tempo).displaySeries.map { "\($0.tick):\($0.value)" }
    let volumeRawBefore = panLfo.document.rawChunks[1].events.filter {
        if case let .channel(status, controller, _) = $0.payload {
            return status >> 4 == 0xB && controller == TimeDefaults.ccVolume
        }
        return false
    }
    _ = panLfo.page.pointerPress(
        x: panX, y: panY, surface: 1,
        button: DrawerQtButton.left, modifiers: AutomationQtModifier.shift)
    _ = panLfo.page.pointerMove(
        x: armX, y: panY, buttons: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    _ = panLfo.page.pointerMove(
        x: finishX, y: panY, buttons: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expect(
        (try? panLfo.document.state.file.encoded()) == panLfoBytes
            && panLfo.document.history.undoIndex == panLfoIndex, cppID: id,
        message: "Pan LFO selected preview does not write raw events")
    _ = panLfo.page.pointerRelease(
        x: finishX, y: panY, button: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expect(
        panLfo.document.revision == panLfoBefore.revision + 1
            && panLfo.document.history.undoIndex == panLfoIndex + 1
            && panLfo.page.selection?.range == TimeRange(startTick: 144, endTick: 192)
            && !panLfo.page.interactionActive, cppID: id,
        message: "Pan LFO range commits one revision and applied undo entry then finishes idle")
    report.expect(
        panLfo.playbackTempo(at: 96)?.microseconds == 499_999
            && panLfo.playbackTempo(at: 144) == nil, cppID: id,
        message: "Pan LFO-only range preserves fractional Tempo at source")
    report.expect(
        panLfo.playbackValues(panLfo.panLane, at: 96).isEmpty
            && panLfo.playbackValues(panLfo.panLane, at: 144) == [10, 20],
        cppID: id, message: "Pan LFO range evicts collision and keeps ordered raw Pan group")
    report.expect(
        panLfo.values(panLfo.lfoLane) == ["0:32", "144:96", "384:64"]
            && panLfo.values(panLfo.volumeLane) == ["24:32"], cppID: id,
        message: "Pan LFO range shifts LFO but never changes unrelated Volume")
    let volumeRawAfter = panLfo.document.rawChunks[1].events.filter {
        if case let .channel(status, controller, _) = $0.payload {
            return status >> 4 == 0xB && controller == TimeDefaults.ccVolume
        }
        return false
    }
    report.expect(
        panLfo.laneSnapshot(.tempo).displaySeries.map {
            "\($0.tick):\($0.value)"
        } == tempoRow
            && panLfo.tempoValues == ["0:80", "96:120", "384:64"]
            && volumeRawAfter == volumeRawBefore, cppID: id,
        message: "Pan LFO-only edit preserves complete Tempo row and raw Volume events")
    let panLfoCommitted = try? panLfo.document.state.file.encoded()
    report.expect(
        panLfo.undo() && panLfo.document.history.undoIndex == panLfoIndex
            && (try? panLfo.document.state.file.encoded()) == panLfoBytes
            && panLfo.values(panLfo.panLane) == panBefore
            && panLfo.values(panLfo.lfoLane) == lfoBefore
            && panLfo.laneSnapshot(.tempo).displaySeries.map {
                "\($0.tick):\($0.value)"
            } == tempoRow, cppID: id,
        message: "Pan LFO undo restores original bytes index points and Tempo row")
    let panLfoRedid = (try? runBlocking { try await panLfo.session.redo() }) ?? false
    report.expect(
        panLfoRedid && panLfo.document.history.undoIndex == panLfoIndex + 1
            && (try? panLfo.document.state.file.encoded()) == panLfoCommitted
            && panLfo.values(panLfo.panLane) == ["0:80", "144:10", "144:20", "384:110"]
            && panLfo.values(panLfo.lfoLane) == ["0:32", "144:96", "384:64"]
            && panLfo.laneSnapshot(.tempo).displaySeries.map {
                "\($0.tick):\($0.value)"
            } == tempoRow, cppID: id,
        message: "Pan LFO redo restores committed bytes index points and Tempo row")
}

@MainActor
func drawerAutomationMixedSelectionDeletePlayback(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::multiLaneSelectionDeleteAndEmptyDeleteNoop"
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    let page = fixture.page
    page.selectRange(from: 96, to: 144, lanes: [fixture.panLane, fixture.lfoLane, .tempo])
    fixture.activate(.tempo)
    let before = fixture.snapshot
    let history = fixture.document.history.undoCount
    let beforeBytes = try? fixture.document.state.file.encoded()
    let beforeIndex = fixture.document.history.undoIndex
    var editedCount = 0
    let priorChange = fixture.session.onChange
    fixture.session.onChange = { change in
        if change.domains.contains(.document) && change.domains.contains(.dirty) {
            editedCount += 1
        }
        priorChange?(change)
    }
    report.expect(
        page.activeParameter == .tempo
            && Set(page.selectedParameters) == Set([fixture.panLane, fixture.lfoLane, .tempo])
            && !page.selectedParameters.contains(fixture.volumeLane), cppID: id,
        message: "displayed Tempo Delete covers the selected Pan and LFO lanes")
    _ = page.consumeSelectionCommand(command: .delete)
    report.expect(
        editedCount == 1 && fixture.document.revision == before.revision + 1
            && fixture.document.history.undoCount == history + 1
            && fixture.document.isDirty, cppID: id,
        message: "selected Delete publishes exactly one dirty edit")
    report.expect(
        fixture.document.history.undoIndex == beforeIndex + 1, cppID: id,
        message: "mixed Delete advances the applied undo index by one")
    report.expect(
        fixture.values(fixture.panLane) == ["0:80", "144:70", "144:80", "384:110"]
            && fixture.values(fixture.lfoLane) == ["0:32", "384:64"]
            && fixture.values(fixture.volumeLane) == ["24:32"], cppID: id,
        message: "mixed Delete removes only selected raw groups and keeps outsiders ordered")
    report.expect(
        fixture.document.state.tempo.map(\.tick) == [0, 384]
            && !page.interactionActive, cppID: id,
        message: "mixed Delete removes only the interval Tempo and leaves gesture idle")
    let deletedBytes = try? fixture.document.state.file.encoded()
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96).isEmpty
            && fixture.playbackValues(fixture.panLane, at: 144) == [70, 80],
        cppID: id, message: "selected Delete removes covered Pan playback but leaves later occupants")
    report.expect(
        fixture.playbackValues(fixture.lfoLane, at: 96).isEmpty
            && fixture.playbackValues(fixture.lfoLane, at: 384) == [64],
        cppID: id, message: "selected Delete removes covered LFO playback but leaves later events")
    report.expect(
        fixture.playbackTempo(at: 96) == nil
            && fixture.playbackTempo(at: 0)?.microseconds == 750_000, cppID: id,
        message: "selected Delete removes covered Tempo playback without removing initial Tempo")
    report.expect(
        fixture.undo() && fixture.playbackTempo(at: 96)?.microseconds == 499_999,
        cppID: id, message: "Delete undo restores exact raw Tempo in playback")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96) == [10, 20]
            && fixture.playbackValues(fixture.lfoLane, at: 96) == [96],
        cppID: id, message: "Delete undo restores ordered Pan and LFO playback")
    report.expect(
        fixture.document.history.undoIndex == beforeIndex
            && (try? fixture.document.state.file.encoded()) == beforeBytes
            && fixture.values(fixture.panLane) == ["0:80", "96:10", "96:20", "144:70", "144:80", "384:110"], cppID: id,
        message: "mixed Delete undo restores prior index bytes and all Pan points")
    let redid = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(
        redid && fixture.playbackTempo(at: 96) == nil
            && fixture.playbackValues(fixture.panLane, at: 96).isEmpty
            && fixture.playbackValues(fixture.lfoLane, at: 96).isEmpty, cppID: id,
        message: "Delete redo removes all three selected playback streams again")
    report.expect(
        redid && fixture.document.history.undoIndex == beforeIndex + 1
            && (try? fixture.document.state.file.encoded()) == deletedBytes
            && fixture.values(fixture.lfoLane) == ["0:32", "384:64"], cppID: id,
        message: "mixed Delete redo restores committed index bytes and LFO points")
    let editedCountBeforeEmptyDelete = editedCount
    page.selectRange(from: 192, to: 240, lanes: [fixture.panLane, fixture.lfoLane, .tempo])
    let empty = fixture.snapshot
    let emptyIndex = fixture.document.history.undoIndex
    let emptyBytes = try? fixture.document.state.file.encoded()
    report.expect(
        page.consumeSelectionCommand(command: .delete) && fixture.snapshot == empty
            && editedCount == editedCountBeforeEmptyDelete, cppID: id,
        message: "empty selected Delete consumes the key without publishing an edit")
    report.expect(
        fixture.document.history.undoIndex == emptyIndex
            && (try? fixture.document.state.file.encoded()) == emptyBytes, cppID: id,
        message: "empty mixed Delete preserves MIDI bytes and applied undo index")
}

@MainActor
func drawerAutomationMixedDragRebuildCancellation(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::multiLaneSelectionDragAbortsOnDocumentRebuild"
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    let page = fixture.page
    fixture.activate(.tempo)
    page.selectRange(from: 96, to: 144, lanes: [fixture.panLane, fixture.lfoLane, .tempo])
    let selection = page.selection
    let before = fixture.snapshot
    let initialBytes = try? fixture.document.state.file.encoded()
    let initialIndex = fixture.document.history.undoIndex
    let endX = drawerAutomationArmHorizontalTempoDrag(fixture)
    report.expect(
        fixture.snapshot == before
            && fixture.document.history.undoIndex == initialIndex
            && (try? fixture.document.state.file.encoded()) == initialBytes, cppID: id,
        message: "rebuild-bound mixed preview writes neither bytes nor history")
    fixture.document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccVolume),
        from: 24, through: 24, points: [LaneWrite(tick: 24, value: 33)])
    let rebuilt = fixture.snapshot
    let rebuildBytes = try? fixture.document.state.file.encoded()
    let rebuildIndex = fixture.document.history.undoIndex
    _ = page.pointerRelease(
        x: endX, y: fixture.y(.tempo, 120),
        button: DrawerQtButton.left, modifiers: AutomationQtModifier.shift)
    report.expect(
        page.selection == selection && fixture.snapshot == rebuilt
            && rebuilt.revision == before.revision + 1, cppID: id,
        message: "document rebuild cancels the drag without changing its selected scope")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96) == [10, 20]
            && fixture.playbackValues(fixture.lfoLane, at: 96) == [96]
            && fixture.playbackTempo(at: 96)?.microseconds == 499_999
            && fixture.playbackTempo(at: 144) == nil
            && fixture.playbackValues(fixture.volumeLane, at: 24) == [33], cppID: id,
        message: "release after rebuild retains original Pan LFO and Tempo playback")
    report.expect(
        page.selection?.range == TimeRange(startTick: 96, endTick: 144)
            && !page.interactionActive
            && fixture.document.history.undoIndex == rebuildIndex
            && (try? fixture.document.state.file.encoded()) == rebuildBytes, cppID: id,
        message: "stale release keeps original mixed range and rebuilt bytes while idle")
}
let drawerAutomationCcOnlyIntervalID = "automation/AutomationEditingTest::ccOnlySelectionDragExactInterval"

// The CC-only drag on the fork's exact [96,144) lands [144,192) with ordered
// groups and no held edit notification. Held captures are pre-stimulus.
@MainActor
func drawerAutomationCcOnlyExactIntervalDrag(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 96, to: 144, lanes: [fixture.panLane, fixture.lfoLane])
    let held = DrawerAutomationStagedSnapshot(fixture.document)
    var documentEdits = 0
    var dirtyEdits = 0
    let priorChange = fixture.session.onChange
    fixture.session.onChange = { change in
        if change.domains.contains(.document) { documentEdits += 1 }
        if change.domains.contains(.dirty) { dirtyEdits += 1 }
        priorChange?(change)
    }
    let sourceX = fixture.x(96)
    let sourceY = fixture.y(fixture.panLane, 20)
    let activationX = sourceX + fixture.page.geometry.nodeDragActivationDistance + 2
    let endX = activationX + fixture.x(144) - sourceX
    _ = fixture.page.pointerPress(
        x: sourceX, y: sourceY, surface: 1,
        button: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    _ = fixture.page.pointerMove(
        x: activationX, y: sourceY, buttons: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    _ = fixture.page.pointerMove(
        x: endX, y: sourceY, buttons: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expect(
        DrawerAutomationStagedSnapshot(fixture.document) == held
            && documentEdits == 0 && dirtyEdits == 0,
        cppID: drawerAutomationCcOnlyIntervalID,
        message: "held CC-only preview freezes the song and emits no edit notification")
    _ = fixture.page.pointerRelease(
        x: endX, y: sourceY, button: DrawerQtButton.left,
        modifiers: AutomationQtModifier.shift)
    report.expect(
        fixture.page.selection?.range == TimeRange(startTick: 144, endTick: 192)
            && fixture.page.selection?.scope == .lanes
            && fixture.page.selection?.tempo == false
            && fixture.page.selection?.lanes == Set([fixture.panLane, fixture.lfoLane]),
        cppID: drawerAutomationCcOnlyIntervalID,
        message: "CC-only drag translates its exact interval to 144 through 192 in Pan LFO scope")
    report.expectEqual(
        expected: [10, 20], actual: fixture.playbackValues(fixture.panLane, at: 144),
        cppID: drawerAutomationCcOnlyIntervalID,
        what: "CC-only drag publishes ordered Pan collisions at tick 144")
    report.expectEqual(
        expected: [96], actual: fixture.playbackValues(fixture.lfoLane, at: 144),
        cppID: drawerAutomationCcOnlyIntervalID,
        what: "CC-only drag publishes the LFO group at tick 144")
}
