import Foundation
import PorydawCore
import PorydawProject

@testable import PorydawApp

struct BenchFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
struct BenchScenario {
    let applies: @MainActor (BenchFixture) -> Bool
    let name: String
    let prepare: @MainActor (BenchFixture) async throws -> Void
    let run: @MainActor (BenchFixture) async throws -> Void
    let validate: @MainActor (BenchFixture) throws -> Void
    let operations: @MainActor (BenchFixture) -> Int

    init(
        name: String,
        applies: @escaping @MainActor (BenchFixture) -> Bool = { _ in true },
        prepare: @escaping @MainActor (BenchFixture) async throws -> Void = { _ in },
        run: @escaping @MainActor (BenchFixture) async throws -> Void,
        validate: @escaping @MainActor (BenchFixture) throws -> Void,
        operations: @escaping @MainActor (BenchFixture) -> Int = { _ in 1 }
    ) {
        self.name = name
        self.prepare = prepare
        self.applies = applies
        self.run = run
        self.validate = validate
        self.operations = operations
    }
}

@MainActor
final class BenchFixture {
    let document: SongDocument
    let session: DocumentSession
    let page: AutomationPage
    let service: ProjectService
    let nodes: Int
    let samples: Int
    let parameter: AutomationParameter
    let workload: BenchWorkload
    let lowValue: Int
    let highValue: Int
    let sourceTick: Tick = 24
    let targetTick: Tick = 48
    let emptyTick: Tick = 36
    let originalPoints: [AutomationLanePoint]
    let initialRevision: UInt64
    let initialUndoCount: Int
    let initialUndoIndex: Int
    var runResult = false
    private var coordinateProjection: AutomationProjection?

    init(
        environment: BenchEnvironment, parameter: AutomationParameter, nodes: Int, samples: Int,
        workload: BenchWorkload = BenchWorkload()
    ) {
        self.service = environment.service
        self.nodes = nodes
        self.samples = samples
        self.parameter = parameter
        self.workload = workload
        let lowValue = parameter == .pitchBend(track: 0) ? -20 : 40
        let highValue = parameter == .pitchBend(track: 0) ? 20 : 80
        self.lowValue = lowValue
        self.highValue = highValue
        let end = Tick((nodes + 8) * 24)
        let writes = (0..<nodes).map {
            LaneWrite(tick: Tick(($0 + 1) * 24), value: $0.isMultiple(of: 2) ? lowValue : highValue)
        }
        var conductor: [MidiEvent] = [
            .meta(tick: 0, type: 0x51, data: [7, 161, 32]),
            .meta(tick: 0, type: 0x58, data: [4, 2, 24, 8]),
        ]
        if parameter.isTempo {
            conductor += writes.map { point in
                let microseconds = TimeDefaults.microsecondsPerQuarterNote(forBPM: point.value)
                return .meta(
                    tick: point.tick, type: 0x51,
                    data: [
                        UInt8((microseconds >> 16) & 255), UInt8((microseconds >> 8) & 255),
                        UInt8(microseconds & 255),
                    ])
            }
        }
        let seed = SongDocument(
            file: MidiFile(
                division: 24,
                chunks: workload.midiChunks(conductor: conductor, end: end)),
            config: environment.basis.document.state.config)
        if let lane = parameter.lane {
            seed.writeLane(track: 0, lane: lane, from: 0, through: end, points: writes)
        }
        var adopted = seed.state.file
        adopted.chunks[0] = MidiChunk(events: conductor, endTick: end)
        document = SongDocument(
            file: adopted, config: seed.state.config,
            source: environment.basis.document.source)
        session = DocumentSession(
            document: document, service: service,
            lease: environment.basis.bankLease, slots: environment.basis.bankSlots,
            dirty: false, loadName: environment.basis.bankLoadName)
        session.selectedTrack = 0
        page = AutomationPage(baseFontPx: 13)
        page.attach(session: session, palette: GridPalette())
        page.configureBody(
            width: 480, height: 120, gutter: 0, devicePixelRatio: 1,
            baseFontPx: 13, dragDistance: 10)
        session.camera.updateViewport(width: page.plotWidth, rollHeight: 120)
        if workload.visibleNodes > 0 {
            session.camera.setTimeZoom(page.plotWidth / Double(workload.visibleNodes))
            session.camera.setHScroll(0)
        }
        page.refreshCamera()
        session.onChange = { [weak page] change in
            if !change.domains.intersection([.document, .bank]).isEmpty {
                page?.refreshFromDocument()
            } else if change.domains.contains(.selection), page?.menuOpen == true || page?.promptOpen == true {
                page?.refreshFromDocument()
            } else if change.domains.contains(.cursor) {
                page?.refreshEditCursor()
            }
        }
        session.onCameraChange = { [weak page] _ in page?.refreshCamera() }
        _ = page.activateParameter(index: AutomationCatalog.index(of: parameter, track: 0) ?? 0)
        originalPoints = AutomationLaneSnapshot(
            parameter: parameter, in: document,
            songEndTick: session.timeline.lengthTicks
        ).sources.map {
            AutomationLanePoint(tick: $0.tick, value: $0.value)
        }
        initialRevision = document.revision
        initialUndoCount = document.history.undoCount
        initialUndoIndex = document.history.undoIndex
        coordinateProjection = page.makeProjection(facts: facts(), camera: session.camera)
    }
    func validateDensity() throws {
        try check(
            document.engineTracks.usedTrackCount == workload.trackCount,
            "Expected \(workload.trackCount) engine tracks")
        for track in 0..<workload.trackCount {
            try check(
                document.notes(in: track).count == workload.notesPerTrack,
                "Track \(track) must contain \(workload.notesPerTrack) paired notes")
        }
    }

    func activate(_ parameter: AutomationParameter) {
        _ = page.activateParameter(index: AutomationCatalog.index(of: parameter, track: 0) ?? 0)
        coordinateProjection = page.makeProjection(facts: facts(), camera: session.camera)
    }

    func x(_ tick: Tick) -> Double { session.camera.contentX(tick: Double(tick)) }

    func y(_ value: Int) -> Double {
        guard let coordinateProjection else { preconditionFailure("Missing coordinate projection") }
        return coordinateProjection.y(value, metadata: AutomationParameterMetadata(parameter: page.activeParameter))
    }

    func points() -> [AutomationLanePoint] {
        AutomationLaneSnapshot(
            parameter: parameter, in: document,
            songEndTick: session.timeline.lengthTicks
        ).sources.map {
            AutomationLanePoint(tick: $0.tick, value: $0.value)
        }
    }

    func facts() -> AutomationFrozenFacts {
        AutomationFrozenFacts(
            parameter: parameter,
            snapshot: AutomationLaneSnapshot(
                parameter: parameter, in: document,
                songEndTick: session.timeline.lengthTicks),
            camera: session.camera.snapshot, selection: page.selection,
            modifiers: .init(), songEndTick: session.timeline.lengthTicks)
    }

    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw BenchFailure(description: message) }
    }

    func drag(from: Tick, value: Int, to: Tick, targetValue: Int, modifiers: Int = 0) {
        let pressX = x(from)
        let pressY = y(value)
        let armY = pressY - 30
        _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: 1, modifiers: modifiers)
        _ = page.pointerMove(x: pressX, y: armY, buttons: 1, modifiers: modifiers)
        for sample in 1...samples {
            let fraction = Double(sample) / Double(samples)
            _ = page.pointerMove(
                x: pressX + (x(to) - pressX) * fraction,
                y: armY + (y(targetValue) - pressY) * fraction,
                buttons: 1, modifiers: modifiers)
        }
        runResult = page.pointerRelease(
            x: x(to), y: armY + y(targetValue) - pressY,
            button: 1, modifiers: modifiers)
    }

    func click(tick: Tick, value: Int, modifiers: Int = 0) {
        _ = page.pointerPress(x: x(tick), y: y(value), surface: 1, button: 1, modifiers: modifiers)
        runResult = page.pointerRelease(x: x(tick), y: y(value), button: 1, modifiers: modifiers)
    }
}

@MainActor
final class BenchEnvironment {
    let service: ProjectService
    let basis: DocumentSession
    let root: URL

    private init(service: ProjectService, basis: DocumentSession, root: URL) {
        self.service = service
        self.basis = basis
        self.root = root
    }

    static func open() async throws -> BenchEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "automation-bench-\(UUID().uuidString)")
        let files = [
            "sound/song_table.inc":
                ".equiv MUSIC_PLAYER_BGM, 0\n.align 2\ngSongTable::\n    song mus_bench, MUSIC_PLAYER_BGM, 0\n",
            "sound/songs/midi/midi.cfg": "mus_bench.mid: -R50 -G_bench_vg -V100\n",
            "sound/voicegroups/bench_vg.inc":
                ".align 2\nvoice_group bench_vg\n    voice_square_1 60, 0, 2, 2, 2, 3, 12, 4\n",
            "sound/voice_groups.inc": ".include \"sound/voicegroups/bench_vg.inc\"\n",
            "include/constants/songs.h": "#define MUS_BENCH 1\n",
        ]
        do {
            for (path, content) in files {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
            let midi = MidiFile(
                division: 24,
                chunks: [
                    MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [7, 161, 32])], endTick: 192),
                    MidiChunk(
                        events: [
                            .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
                            .channel(tick: 192, status: 0x80, data0: 60),
                        ], endTick: 192),
                ])
            try Data(midi.encoded()).write(to: root.appendingPathComponent("sound/songs/midi/mus_bench.mid"))
            let service = ProjectService()
            try await service.open(root: root.path)
            let basis = try await DocumentSession.open(service: service, label: "mus_bench")
            return BenchEnvironment(service: service, basis: basis, root: root)
        } catch {
            try FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func close() async throws {
        await service.close()
        try FileManager.default.removeItem(at: root)
    }
}
