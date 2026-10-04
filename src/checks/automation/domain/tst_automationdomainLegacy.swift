import Foundation
@testable import PorydawApp
import PorydawCore

// Exact legacy tempo/CC row fixtures for the resolver and commit boundary.
@MainActor
private final class DrawerDomainCheckFixture {
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.channel(status: 0xC0, data0: 0)], endTick: 9216)
            ]))
    let parameter: AutomationParameter
    let camera: EditorCamera.Snapshot

    init(_ parameter: AutomationParameter, camera: EditorCamera.Snapshot) {
        self.parameter = parameter
        self.camera = camera
    }

    struct Snapshot: Equatable {
        let bytes: [UInt8]
        let revision: UInt64
        let identity: DocumentIdentity
    }

    var snapshot: Snapshot {
        Snapshot(
            bytes: try! document.captureSave().bytes, revision: document.revision,
            identity: document.history.currentIdentity)
    }

    var lane: AutomationLaneSnapshot {
        AutomationLaneSnapshot(parameter: parameter, in: document, songEndTick: 9216)
    }

    var facts: AutomationFrozenFacts {
        AutomationFrozenFacts(
            parameter: parameter, snapshot: lane, camera: camera,
            selection: nil, modifiers: .init(), songEndTick: 9216)
    }

    var points: [String] { lane.displaySeries.map { "\($0.tick):\($0.value)" } }

    func set(_ points: [(Tick, Int)]) {
        if parameter.isTempo {
            document.editTempo(
                TempoEdit(
                    remove: document.state.tempo,
                    add: points.map {
                        TempoPoint(
                            tick: $0.0,
                            microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: $0.1))
                    }))
        } else {
            document.writeLane(
                track: 0, lane: parameter.lane!, from: 0,
                through: TimeDefaults.noTick,
                points: points.map { LaneWrite(tick: $0.0, value: $0.1) })
        }
    }

    func insert(_ tick: Tick, _ value: UInt8) {
        document.insertRawEvent(
            chunk: 0,
            event: .channel(
                tick: tick, status: 0xB0,
                data0: 11, data1: value))
    }

    func raw(_ tick: Tick) -> [Int] {
        document.lanePoints(track: 0, lane: .controller(11))
            .filter { $0.tick == tick }.map(\.value)
    }

    func move(_ requests: [(Tick, Tick, Int)]) -> Bool {
        let moves = requests.map {
            AutomationNodeMove(parameter: parameter, sourceTick: $0.0, tick: $0.1, value: $0.2)
        }
        guard let plan = AutomationNodeResolver.moves([.init(facts, moves)]) else { return false }
        return AutomationCommit.apply(plan, in: document)
    }

    func delete(_ ticks: [Tick]) -> Bool {
        guard
            let plan = AutomationNodeResolver.deletions(
                revision: document.revision,
                [.init(parameter: parameter, snapshot: lane, ticks: ticks)])
        else { return false }
        return AutomationCommit.apply(plan, in: document)
    }

    func replace(_ begin: Tick, _ end: Tick, _ points: [(Tick, Int)]) {
        // Like NodeLane::replaceSpan, this is an explicit accepted replacement,
        // below gesture no-op planning. The document compares the stored bytes.
        _ = AutomationCommit.apply(
            AutomationLaneEdit(
                parameter: parameter, revision: document.revision, tickBegin: begin,
                tickEnd: end, points: points.map { AutomationLanePoint(tick: $0.0, value: $0.1) },
                unchanged: false), in: document)
    }

    func oneEdit(_ before: Snapshot) -> Bool {
        document.revision == before.revision + 1 && document.history.currentIdentity != before.identity
    }

    func replay(_ before: Snapshot, _ beforePoints: [String], _ afterPoints: [String]) -> Bool {
        let afterIdentity = document.history.currentIdentity
        guard document.history.undoDocument() else { return false }
        let undone = snapshot.bytes == before.bytes && snapshot.identity == before.identity && points == beforePoints
        guard document.history.redoDocument() else { return false }
        let redone = snapshot.identity == afterIdentity && points == afterPoints
        guard document.history.undoDocument() else { return false }
        return undone && redone && snapshot.bytes == before.bytes && snapshot.identity == before.identity
            && points == beforePoints
    }
}

@MainActor
func drawerAutomationLegacyResolverRows(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    for parameter in [AutomationParameter.tempo, .controlChange(track: 0, controller: 11)] {
        let row = parameter.isTempo ? "tempo" : "cc"
        func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
            report.expect(
                condition(), cppID: "automation-domain/AutomationDomainTest::legacyResolverRows",
                message: "tst_automationdomain.cpp:\(line) row=\(row)")
        }

        let deletion = DrawerDomainCheckFixture(parameter, camera: camera)
        deletion.set([(0, 120), (96, 100), (288, 110)])
        let beforeDelete = deletion.snapshot
        expect(!deletion.delete([]), 303)
        expect(deletion.snapshot == beforeDelete, 304)
        expect(!deletion.delete([99999]), 305)
        expect(deletion.snapshot == beforeDelete, 306)
        expect(deletion.delete([96]), 307)
        expect(deletion.oneEdit(beforeDelete), 308)
        expect(deletion.points == ["0:120", "288:110"], 309)
        if !parameter.isTempo { expect(deletion.raw(96).isEmpty, 311) }
        expect(
            deletion.replay(
                beforeDelete, ["0:120", "96:100", "288:110"],
                ["0:120", "288:110"]), 312)

        if !parameter.isTempo {
            deletion.set([(0, 64)])
            deletion.insert(96, 10)
            deletion.insert(96, 20)
            let groupedBefore = deletion.snapshot
            let groupedPoints = deletion.points
            expect(deletion.delete([96]), 320)
            expect(deletion.oneEdit(groupedBefore), 321)
            expect(deletion.points == ["0:64"], 322)
            expect(deletion.raw(96).isEmpty, 323)
            expect(deletion.replay(groupedBefore, groupedPoints, ["0:64"]), 324)
        }

        let moving = DrawerDomainCheckFixture(parameter, camera: camera)
        if parameter.isTempo {
            moving.document.editTempo(
                TempoEdit(add: [
                    TempoPoint(tick: 96, microsecondsPerQuarterNote: 499999),
                    TempoPoint(
                        tick: 288, microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: 110)),
                ]))
        } else {
            moving.set([(288, 40)])
            moving.insert(96, 10)
            moving.insert(96, 20)
        }
        let movingBefore = moving.snapshot
        let movingPoints = moving.points
        let movedValue = parameter.isTempo ? 120 : 20
        expect(!moving.move([]), parameter.isTempo ? 346 : 372)
        expect(moving.snapshot == movingBefore, parameter.isTempo ? 347 : 373)
        expect(!moving.move([(99999, 192, movedValue)]), parameter.isTempo ? 348 : 374)
        expect(moving.snapshot == movingBefore, parameter.isTempo ? 349 : 375)
        expect(moving.move([(96, 192, movedValue)]), parameter.isTempo ? 351 : 376)
        expect(moving.oneEdit(movingBefore), parameter.isTempo ? 352 : 377)
        let movedPoints = parameter.isTempo ? ["192:120", "288:110"] : ["192:20", "288:40"]
        expect(moving.points == movedPoints, parameter.isTempo ? 353 : 378)
        if parameter.isTempo {
            expect(moving.document.state.tempo.first?.microsecondsPerQuarterNote == 499999, 354)
        } else {
            expect(moving.raw(192) == [10, 20], 379)
        }
        expect(moving.replay(movingBefore, movingPoints, movedPoints), parameter.isTempo ? 355 : 380)

        if parameter.isTempo {
            let rewriteBefore = moving.snapshot
            let rewritePoints = moving.points
            expect(moving.move([(96, 192, 140)]), 359)
            expect(moving.oneEdit(rewriteBefore), 360)
            expect(
                moving.document.state.tempo.first?.microsecondsPerQuarterNote
                    == TimeDefaults.microsecondsPerQuarterNote(forBPM: 140), 361)
            expect(moving.replay(rewriteBefore, rewritePoints, ["192:140", "288:110"]), 362)
        }

        if !parameter.isTempo {
            moving.insert(192, 70)
            moving.insert(192, 80)
        }
        let collisionBefore = moving.snapshot
        let collisionPoints = moving.points
        let destination: Tick = parameter.isTempo ? 288 : 192
        expect(moving.move([(96, destination, movedValue)]), parameter.isTempo ? 402 : 417)
        expect(moving.oneEdit(collisionBefore), parameter.isTempo ? 403 : 418)
        let collisionAfter = parameter.isTempo ? ["288:120"] : ["192:20", "288:40"]
        expect(moving.points == collisionAfter, parameter.isTempo ? 404 : 419)
        if parameter.isTempo {
            expect(moving.document.state.tempo.first?.microsecondsPerQuarterNote == 499999, 405)
        } else {
            expect(moving.raw(192) == [10, 20], 420)
        }
        expect(moving.replay(collisionBefore, collisionPoints, collisionAfter), parameter.isTempo ? 406 : 421)
    }
}

@MainActor
func drawerAutomationLegacyMetadataRows(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    func expect(_ condition: @autoclosure () -> Bool, _ line: Int, row: String) {
        report.expect(
            condition(), cppID: "automation-domain/AutomationDomainTest::legacyMetadataRows",
            message: "tst_automationdomain.cpp:\(line) row=\(row)")
    }
    for parameter in [AutomationParameter.tempo, .controlChange(track: 0, controller: 11)] {
        let row = parameter.isTempo ? "tempo" : "cc"
        let fixture = DrawerDomainCheckFixture(parameter, camera: camera)
        expect(fixture.document.engineTracks.usedTrackCount == 1, 49, row: row)
        expect(fixture.document.engineTracks.tracks[0].midiChunk == 0, 50, row: row)
        expect(fixture.points.isEmpty, 223, row: row)
        if parameter.isTempo {
            fixture.set([(288, 110), (0, 120), (96, 150)])
            expect(fixture.points == ["0:120", "96:150", "288:110"], 226, row: row)
            fixture.document.editTempo(
                TempoEdit(
                    remove: fixture.document.state.tempo,
                    add: [
                        TempoPoint(
                            tick: 0, microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(forBPM: 150)),
                        TempoPoint(tick: 96, microsecondsPerQuarterNote: 398406),
                    ]))
            let metadata = fixture.lane.metadata
            let fractional = Int(TimeDefaults.tempoBPM(forMicrosecondsPerQuarterNote: 398406).rounded())
            expect(AutomationCatalog.title(parameter) == "Tempo (BPM)", 253, row: row)
            expect(metadata.minimum == 20, 254, row: row)
            expect(metadata.maximum == 255, 255, row: row)
            expect(metadata.valueText(150) == "150", 258, row: row)
            expect(metadata.valueText(fractional) == String(fractional), 259, row: row)
            expect(fixture.points == ["0:150", "96:\(fractional)"], 260, row: row)
        } else {
            fixture.insert(288, 40)
            fixture.insert(0, 64)
            fixture.insert(96, 10)
            fixture.insert(96, 20)
            expect(fixture.points == ["0:64", "96:20", "288:40"], 234, row: row)
            expect(fixture.raw(96) == [10, 20], 235, row: row)
            let bend = AutomationParameterMetadata(parameter: .pitchBend(track: 0))
            let modType = AutomationParameterMetadata(
                parameter: .controlChange(track: 0, controller: TimeDefaults.ccModulationType))
            let tune = AutomationParameterMetadata(
                parameter: .controlChange(track: 0, controller: TimeDefaults.ccFineTune))
            expect(bend.minimum == -8192, 263, row: row)
            expect(bend.maximum == 8191, 264, row: row)
            expect(modType.minimum == 0, 266, row: row)
            expect(modType.maximum == 2, 267, row: row)
            let prompt = tune.prompt(storedValue: 64)
            expect(prompt.minimum == -64, 272, row: row)
            expect(prompt.maximum == 63, 273, row: row)
            expect(prompt.initialValue == 0, 274, row: row)
            expect(tune.neutral == 64, 275, row: row)
            fixture.document.writeLane(
                track: 0, lane: .controller(TimeDefaults.ccFineTune),
                from: 0, through: 96,
                points: [
                    LaneWrite(tick: 0, value: prompt.minimum + prompt.storedOffset),
                    LaneWrite(tick: 48, value: prompt.initialValue + prompt.storedOffset),
                    LaneWrite(tick: 96, value: prompt.maximum + prompt.storedOffset),
                ])
            let tuneSnapshot = AutomationLaneSnapshot(
                parameter: tune.parameter, in: fixture.document, songEndTick: 9216)
            expect(
                tuneSnapshot.displaySeries.map { "\($0.tick):\($0.value)" } == ["0:0", "48:64", "96:127"], 280, row: row
            )
            expect(bend.neutral == 0, 281, row: row)
            expect(bend.prompt(storedValue: 0).storedOffset == 0, 282, row: row)
            expect(modType.neutral == nil, 283, row: row)
        }
    }
}

@MainActor
func drawerAutomationLegacyDefaultPromotion(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    let fixture = DrawerDomainCheckFixture(.controlChange(track: 0, controller: 11), camera: camera)
    let document = fixture.document
    func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
        report.expect(
            condition(), cppID: "automation-domain/AutomationDomainTest::defaultNodePromotion",
            message: "tst_automationdomain.cpp:\(line)")
    }
    func lane(_ parameter: AutomationParameter) -> AutomationLaneSnapshot {
        AutomationLaneSnapshot(parameter: parameter, in: document, songEndTick: 9216)
    }
    func points(_ parameter: AutomationParameter) -> [String] {
        lane(parameter).displaySeries.map { "\($0.tick):\($0.value)" }
    }
    let volume = AutomationParameter.controlChange(track: 0, controller: 7)
    let pan = AutomationParameter.controlChange(track: 0, controller: 10)
    let modulation = AutomationParameter.controlChange(track: 0, controller: 1)
    let bend = AutomationParameter.pitchBend(track: 0)
    expect(points(volume) == ["0:127"], 486)
    expect(points(pan) == ["0:64"], 487)
    expect(points(modulation).isEmpty, 488)
    expect(lane(modulation).leadInValue == 0, 490)
    expect(points(bend).isEmpty, 491)
    expect(lane(bend).leadInValue == 0, 493)
    expect(lane(.controlChange(track: 0, controller: TimeDefaults.ccFineTune)).leadInValue == 64, 499)
    expect(lane(.controlChange(track: 0, controller: TimeDefaults.ccModulationType)).leadInValue == 0, 502)
    expect(lane(.controlChange(track: 0, controller: TimeDefaults.ccLFODelay)).leadInValue == 0, 505)
    document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccModulationType), from: 0,
        through: TimeDefaults.noTick, points: [LaneWrite(tick: 0, value: 7)])
    expect(
        document.lanePoints(track: 0, lane: .controller(TimeDefaults.ccModulationType))
            .filter { $0.tick == 0 }.map(\.value) == [2], 510)

    for (parameter, value, base, defaultPoints) in [
        (volume, 100, 514, ["0:127"]), (pan, 32, 527, ["0:64"]),
    ] {
        let before = fixture.snapshot
        let facts = AutomationFrozenFacts(
            parameter: parameter, snapshot: lane(parameter),
            camera: camera, selection: nil, modifiers: .init(),
            songEndTick: 9216)
        let resolved = AutomationNodeResolver.moves([
            .init(
                facts,
                [
                    AutomationNodeMove(parameter: parameter, sourceTick: 0, tick: 96, value: value)
                ])
        ])
        expect(resolved != nil, base)
        guard let resolved else { return }
        expect(!resolved.isEmpty, base + 3)
        _ = AutomationCommit.apply(resolved, in: document)
        expect(fixture.oneEdit(before), base + 5)
        expect(
            document.lanePoints(track: 0, lane: parameter.lane!)
                .filter { $0.tick == 96 }.map(\.value) == [value], base + 6)
        _ = document.history.undoDocument()
        expect(fixture.snapshot.bytes == before.bytes, base + 8)
        expect(points(parameter) == defaultPoints, base + 9)
    }
}

@MainActor
func drawerAutomationLegacySpanRows(_ report: CheckReport, camera: EditorCamera.Snapshot) {
    for parameter in [AutomationParameter.tempo, .controlChange(track: 0, controller: 11)] {
        let row = parameter.isTempo ? "tempo" : "cc"
        func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
            report.expect(
                condition(), cppID: "automation-domain/AutomationDomainTest::replaceSpans",
                message: "tst_automationdomain.cpp:\(line) row=\(row)")
        }
        let fixture = DrawerDomainCheckFixture(parameter, camera: camera)
        let emptyBefore = fixture.snapshot
        fixture.replace(0, 10000, [])
        expect(fixture.snapshot == emptyBefore, 440)
        fixture.replace(0, 10000, [(96, 90)])
        expect(fixture.oneEdit(emptyBefore), 442)
        expect(fixture.points == ["96:90"], 443)
        expect(fixture.replay(emptyBefore, [], ["96:90"]), 444)

        let original = ["0:120", "96:100", "288:110"]
        fixture.set([(0, 120), (96, 100), (288, 110)])
        let before = fixture.snapshot
        fixture.replace(96, 96, [(96, 100)])
        expect(fixture.snapshot == before, 450)
        fixture.replace(96, 200, [(96, 80), (128, 70)])
        expect(fixture.oneEdit(before), 452)
        let replacement = ["0:120", "96:80", "128:70", "288:110"]
        expect(fixture.points == replacement, 454)
        expect(fixture.replay(before, original, replacement), 455)

        let clearBefore = fixture.snapshot
        fixture.replace(0, 10000, [])
        expect(fixture.oneEdit(clearBefore), 459)
        expect(fixture.points.isEmpty, 460)
        expect(fixture.replay(clearBefore, original, []), 461)

        if parameter.isTempo {
            fixture.document.editTempo(
                TempoEdit(
                    remove: fixture.document.state.tempo,
                    add: [
                        TempoPoint(tick: 96, microsecondsPerQuarterNote: 398406)
                    ]))
            let displayed = Int(TimeDefaults.tempoBPM(forMicrosecondsPerQuarterNote: 398406).rounded())
            let fractionalBefore = fixture.snapshot
            let beforePoints = fixture.points
            fixture.replace(96, 96, [(96, displayed)])
            expect(fixture.oneEdit(fractionalBefore), 469)
            expect(
                fixture.document.state.tempo.first?.microsecondsPerQuarterNote
                    == TimeDefaults.microsecondsPerQuarterNote(forBPM: displayed), 470)
            expect(fixture.replay(fractionalBefore, beforePoints, ["96:\(displayed)"]), 471)
        }
    }
}
