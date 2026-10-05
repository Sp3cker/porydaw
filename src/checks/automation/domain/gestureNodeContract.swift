import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
func drawerAutomationExactNodeContract(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = drawerAutomationContractParityID
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(0, 64), (96, 10), (96, 20), (192, 70), (192, 80), (288, 40)],
        tempo: [(96, 499_999), (288, 545_455)])
    let document = fixture.document
    let tempoMetadata = AutomationParameterMetadata(parameter: .tempo)
    let ccMetadata = AutomationParameterMetadata(parameter: fixture.panLane)
    let bendMetadata = AutomationParameterMetadata(parameter: fixture.bendLane)
    report.expect(
        tempoMetadata.minimum == TimeDefaults.minimumTempoBPM
            && tempoMetadata.maximum == TimeDefaults.maximumTempoBPM, cppID: id,
        message: "Tempo bounds expose the exact supported BPM interval")
    report.expectEqual(
        expected: "120", actual: tempoMetadata.valueText(120), cppID: id,
        what: "Tempo formats a whole BPM without losing digits")
    report.expectEqual(
        expected: ["96:120", "288:110"], actual: fixture.tempoValues, cppID: id,
        what: "fractional Tempo projects its displayed node value")
    report.expect(
        ccMetadata.valueText(64) == "c_v+0" && ccMetadata.valueText(0) == "c_v-64",
        cppID: id, message: "CC text formats both neutral and zero")
    report.expect(
        bendMetadata.minimum == TimeDefaults.minimumBendValue
            && bendMetadata.maximum == TimeDefaults.maximumBendValue
            && bendMetadata.valueText(0) == "0"
            && bendMetadata.valueText(100) == "+100", cppID: id,
        message: "bend bounds and zero and hundred text retain their domain")
    let covered = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .lanes,
        lanes: [fixture.panLane])
    let uncovered = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .lanes,
        lanes: [.tempo], tempo: true)
    report.expect(
        covered.isActive && covered.range == uncovered.range
            && covered.covers(fixture.panLane, usedTracks: [0]), cppID: id,
        message: "covered lane reports the complete 50 to 150 interval")
    report.expect(
        uncovered.isActive && !uncovered.covers(fixture.panLane, usedTracks: [0]),
        cppID: id, message: "uncovered lane keeps the interval without coverage")
    let allTracks = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .tracks([0, 1]))
    let oneTrack = AutomationTimeSelection(
        range: TimeRange(startTick: 50, endTick: 150), scope: .tracks([0]))
    report.expect(
        allTracks.covers(.tempo, usedTracks: [0, 1])
            && allTracks.coversTempo(usedTracks: [0, 1]), cppID: id,
        message: "all-used-track ruler range covers its Tempo lane")
    report.expect(
        !oneTrack.covers(.tempo, usedTracks: [0, 1])
            && oneTrack.covers(fixture.panLane, usedTracks: [0]), cppID: id,
        message: "partial-track ruler range excludes Tempo but covers its own Pan")
    fixture.page.selectRange(from: 50, to: 150, lanes: [fixture.panLane])
    fixture.page.clearTimeSelection()
    report.expect(
        fixture.page.selection?.isActive != true
            && fixture.page.selection?.covers(fixture.panLane, usedTracks: [0]) != true,
        cppID: id, message: "cleared range is inactive and cannot cover its former lane")
    let emptyTempo = drawerAutomationAutomationFixture(suite: suite, service: service, tempo: [])
    report.expect(
        emptyTempo.laneSnapshot(.tempo).displaySeries.isEmpty, cppID: id,
        message: "empty Tempo lane displays no written nodes")
    report.expect(
        fixture.laneSnapshot(fixture.modulationLane).displaySeries.isEmpty
            && fixture.laneSnapshot(fixture.modulationLane).leadInValue == 0, cppID: id,
        message: "empty modulation lane has no displayed nodes but retains its lead-in")

    let before = fixture.snapshot
    let bytes = try! document.captureSave().bytes
    let index = document.history.undoIndex
    let emptyMoves = AutomationNodeResolver.moves([.init(fixture.facts(.tempo), [])])
    report.expect(
        emptyMoves?.isEmpty == true
            && !(emptyMoves.map { AutomationCommit.apply($0, in: document) } ?? false)
            && fixture.snapshot == before && document.history.undoIndex == index
            && (try! document.captureSave().bytes) == bytes, cppID: id,
        message: "empty Tempo move leaves bytes revision and undo index intact")
    let unknownTempo = AutomationNodeResolver.moves([
        .init(
            fixture.facts(.tempo),
            [
                AutomationNodeMove(parameter: .tempo, sourceTick: 99999, tick: 192, value: 120)
            ])
    ])
    report.expect(
        unknownTempo == nil && fixture.snapshot == before
            && document.history.undoIndex == index
            && (try! document.captureSave().bytes) == bytes, cppID: id,
        message: "unknown Tempo move leaves bytes revision and undo index intact")
    let emptyDelete = AutomationNodeResolver.deletions(revision: document.revision, [])
    report.expect(
        emptyDelete?.isEmpty == true
            && !(emptyDelete.map { AutomationCommit.apply($0, in: document) } ?? false)
            && fixture.snapshot == before && document.history.undoIndex == index
            && (try! document.captureSave().bytes) == bytes, cppID: id,
        message: "empty Delete leaves bytes revision and undo index intact")
    report.expect(
        AutomationNodeResolver.deletions(
            revision: document.revision,
            [
                .init(
                    parameter: .tempo, snapshot: fixture.laneSnapshot(.tempo), ticks: [99999])
            ]) == nil
            && fixture.snapshot == before && document.history.undoIndex == index
            && (try! document.captureSave().bytes) == bytes, cppID: id,
        message: "unknown Tempo Delete leaves bytes revision and undo index intact")

    let ccBefore = fixture.snapshot
    let ccBytes = try! document.captureSave().bytes
    let ccIndex = document.history.undoIndex
    let emptyCc = AutomationNodeResolver.moves([.init(fixture.facts(fixture.panLane), [])])
    report.expect(
        emptyCc?.isEmpty == true
            && !(emptyCc.map { AutomationCommit.apply($0, in: document) } ?? false)
            && fixture.snapshot == ccBefore && document.history.undoIndex == ccIndex
            && (try! document.captureSave().bytes) == ccBytes, cppID: id,
        message: "empty CC move preserves the complete document snapshot")
    report.expect(
        AutomationNodeResolver.moves([
            .init(
                fixture.facts(fixture.panLane),
                [
                    AutomationNodeMove(parameter: fixture.panLane, sourceTick: 99999, tick: 192, value: 20)
                ])
        ]) == nil && fixture.snapshot == ccBefore && document.history.undoIndex == ccIndex
            && (try! document.captureSave().bytes) == ccBytes, cppID: id,
        message: "unknown CC move preserves bytes and history")
    report.expect(
        AutomationNodeResolver.deletions(
            revision: document.revision,
            [
                .init(
                    parameter: fixture.panLane, snapshot: fixture.laneSnapshot(fixture.panLane),
                    ticks: [99999])
            ]) == nil && fixture.snapshot == ccBefore
            && document.history.undoIndex == ccIndex
            && (try! document.captureSave().bytes) == ccBytes, cppID: id,
        message: "unknown CC Delete preserves bytes and history")

    guard
        let ccMove = AutomationNodeResolver.moves([
            .init(
                fixture.facts(fixture.panLane),
                [
                    AutomationNodeMove(parameter: fixture.panLane, sourceTick: 96, tick: 192, value: 20)
                ])
        ])
    else { report.fail(id, "same-tick collision needs a resolved CC move"); return }
    report.expect(
        AutomationCommit.apply(ccMove, in: document)
            && document.revision == ccBefore.revision + 1
            && document.history.undoIndex == ccIndex + 1, cppID: id,
        message: "same-tick collision commits exactly one CC edit")
    report.expect(
        fixture.values(fixture.panLane) == ["0:64", "192:10", "192:20", "288:40"],
        cppID: id, message: "collision evicts the destination group without reordering surviving CC events")
    report.expect(
        fixture.playbackValues(fixture.panLane, at: 96).isEmpty
            && fixture.playbackValues(fixture.panLane, at: 192) == [10, 20], cppID: id,
        message: "collision vacates source and writes both raw Pan occupants in order")
    let committedBytes = try! document.captureSave().bytes
    report.expect(
        fixture.undo() && document.history.undoIndex == ccIndex
            && (try! document.captureSave().bytes) == ccBytes
            && fixture.values(fixture.panLane) == ["0:64", "96:10", "96:20", "192:70", "192:80", "288:40"],
        cppID: id, message: "CC collision undo restores index bytes and every original point")
    let ccRedo = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(
        ccRedo && document.history.undoIndex == ccIndex + 1
            && (try! document.captureSave().bytes) == committedBytes
            && fixture.values(fixture.panLane) == ["0:64", "192:10", "192:20", "288:40"],
        cppID: id, message: "CC collision redo restores committed index bytes and points")

    let tempoBefore = fixture.snapshot
    let tempoBytes = try! document.captureSave().bytes
    let tempoIndex = document.history.undoIndex
    guard
        let tempoMove = AutomationNodeResolver.moves([
            .init(
                fixture.facts(.tempo),
                [
                    AutomationNodeMove(parameter: .tempo, sourceTick: 96, tick: 288, value: 120)
                ])
        ])
    else { report.fail(id, "fractional Tempo collision needs a resolved move"); return }
    report.expect(
        AutomationCommit.apply(tempoMove, in: document)
            && document.revision == tempoBefore.revision + 1
            && document.history.undoIndex == tempoIndex + 1, cppID: id,
        message: "fractional Tempo collision commits exactly one edit")
    report.expect(
        document.state.tempo.count == 1
            && document.state.tempo[0].tick == 288
            && document.state.tempo[0].microsecondsPerQuarterNote == 499_999, cppID: id,
        message: "fractional Tempo collision evicts occupant but preserves 499999 microseconds")
    let tempoCommitted = try! document.captureSave().bytes
    report.expect(
        fixture.undo() && document.history.undoIndex == tempoIndex
            && (try! document.captureSave().bytes) == tempoBytes
            && fixture.tempoValues == ["96:120", "288:110"], cppID: id,
        message: "Tempo collision undo restores index bytes and both source points")
    let tempoRedo = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(
        tempoRedo && document.history.undoIndex == tempoIndex + 1
            && (try! document.captureSave().bytes) == tempoCommitted
            && fixture.tempoValues == ["288:120"], cppID: id,
        message: "Tempo collision redo restores index bytes and sole destination")
    let fractional = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        tempo: [(0, 500_000), (96, 398_406)])
    report.expect(
        fractional.document.state.tempo.first(where: { $0.tick == 96 })?
            .microsecondsPerQuarterNote == 398_406, cppID: id,
        message: "398406-us Tempo node retains exact fractional raw timing")
    let tempoNodes = fractional.laneSnapshot(.tempo).displaySeries
    report.expect(
        tempoNodes.map { "\($0.tick):\($0.value)" } == ["0:120", "96:151"]
            && tempoNodes.allSatisfy { !$0.projected }, cppID: id,
        message: "398406-us Tempo lane displays both actual nodes including rounded 151 BPM")
    let displayedFraction = tempoNodes.first(where: { $0.tick == 96 && !$0.projected })?.value
    report.expect(
        displayedFraction.map(tempoMetadata.valueText) == "151", cppID: id,
        message: "fractional Tempo lane value formats its full 151 BPM text")
    let changedDocument = fractional.document
    let changedBefore = fractional.snapshot
    let changedBytes = try! changedDocument.captureSave().bytes
    let changedIndex = changedDocument.history.undoIndex
    guard
        let changedMove = AutomationNodeResolver.moves([
            .init(
                fractional.facts(.tempo),
                [
                    AutomationNodeMove(parameter: .tempo, sourceTick: 96, tick: 192, value: 140)
                ])
        ])
    else { report.fail(id, "changed fractional Tempo needs a resolved move"); return }
    report.expect(
        AutomationCommit.apply(changedMove, in: changedDocument)
            && changedDocument.revision == changedBefore.revision + 1
            && changedDocument.history.undoIndex == changedIndex + 1, cppID: id,
        message: "changing fractional Tempo tick and value commits exactly one edit")
    report.expect(
        changedDocument.state.tempo.first(where: { $0.tick == 96 }) == nil
            && changedDocument.state.tempo.first(where: { $0.tick == 192 })?
                .microsecondsPerQuarterNote == TimeDefaults.microsecondsPerQuarterNote(forBPM: 140)
            && fractional.tempoValues == ["0:120", "192:140"], cppID: id,
        message: "changing fractional Tempo to 140 vacates source and recomputes destination")
    let changedCommitted = try! changedDocument.captureSave().bytes
    report.expect(
        fractional.undo() && changedDocument.history.undoIndex == changedIndex
            && (try! changedDocument.captureSave().bytes) == changedBytes
            && fractional.tempoValues == ["0:120", "96:151"], cppID: id,
        message: "changed Tempo move undo restores original index bytes and fractional point")
    let changedRedo = (try? runBlocking { try await fractional.session.redo() }) ?? false
    report.expect(
        changedRedo && changedDocument.history.undoIndex == changedIndex + 1
            && (try! changedDocument.captureSave().bytes) == changedCommitted
            && fractional.tempoValues == ["0:120", "192:140"], cppID: id,
        message: "changed Tempo move redo restores committed index bytes and destination")

    let deleting = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(0, 64), (96, 10), (96, 20), (288, 40)],
        tempo: [(0, 500_000), (96, 499_999), (288, 545_455)])
    let deleteDocument = deleting.document
    let deleteBefore = deleting.snapshot
    let deleteBytes = try! deleteDocument.captureSave().bytes
    let deleteIndex = deleteDocument.history.undoIndex
    guard
        let deletion = AutomationNodeResolver.deletions(
            revision: deleteDocument.revision,
            [
                .init(parameter: .tempo, snapshot: deleting.laneSnapshot(.tempo), ticks: [96]),
                .init(
                    parameter: deleting.panLane, snapshot: deleting.laneSnapshot(deleting.panLane),
                    ticks: [96]),
            ])
    else { report.fail(id, "mixed node Delete needs a resolved plan"); return }
    report.expect(
        AutomationCommit.apply(deletion, in: deleteDocument)
            && deleteDocument.revision == deleteBefore.revision + 1
            && deleteDocument.history.undoIndex == deleteIndex + 1, cppID: id,
        message: "mixed node Delete commits one revision and one applied undo entry")
    report.expect(
        deleting.values(deleting.panLane) == ["0:64", "288:40"]
            && deleting.playbackValues(deleting.panLane, at: 96).isEmpty, cppID: id,
        message: "CC node Delete removes its entire same-tick raw group without touching siblings")
    report.expect(
        deleting.tempoValues == ["0:120", "288:110"], cppID: id,
        message: "mixed node Delete removes only the named Tempo occurrence")
    let deletedBytes = try! deleteDocument.captureSave().bytes
    report.expect(
        deleting.undo() && deleteDocument.history.undoIndex == deleteIndex
            && (try! deleteDocument.captureSave().bytes) == deleteBytes
            && deleting.values(deleting.panLane) == ["0:64", "96:10", "96:20", "288:40"]
            && deleting.tempoValues == ["0:120", "96:120", "288:110"], cppID: id,
        message: "mixed node Delete undo restores prior index bytes Tempo and CC points")
    let deleteRedo = (try? runBlocking { try await deleting.session.redo() }) ?? false
    report.expect(
        deleteRedo && deleteDocument.history.undoIndex == deleteIndex + 1
            && (try! deleteDocument.captureSave().bytes) == deletedBytes
            && deleting.values(deleting.panLane) == ["0:64", "288:40"]
            && deleting.tempoValues == ["0:120", "288:110"], cppID: id,
        message: "mixed node Delete redo restores committed index bytes and points")
}
