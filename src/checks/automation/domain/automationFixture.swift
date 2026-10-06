import Foundation
import PorydawCore
import PorydawNativeHost

@testable import PorydawApp
@testable import PorydawAppPresentation
@testable import PorydawDocument

// Shared automation fixture (moved verbatim from AutomationPageChecks.swift;
// lives in the edit lane so the xcmd-domain suites can use it).
// MARK: - Fixture

// Row ids shared by the edit-lane xcmd/point-range suites and the pages lane.
public let drawerAutomationProjectionID = "swiftcore/AutomationPage::laneProjection"
public let drawerAutomationPointRangeID =
    "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements"

func drawerAutomationAutomationMidi(
    division: UInt16 = 24, volume: [(Tick, UInt8)] = [],
    pan: [(Tick, UInt8)] = [], modulation: [(Tick, UInt8)] = [],
    lfo: [(Tick, UInt8)] = [], echo: [(Tick, UInt8)] = [],
    tempo: [(Tick, UInt32)] = [(0, 500_000)],
    endTick: Tick = 192, tailTick: Tick? = nil
) -> MidiFile {
    var conductor: [MidiEvent] = tempo.map { tick, microseconds in
        .meta(
            tick: tick, type: 0x51,
            data: [
                UInt8((microseconds >> 16) & 0xFF),
                UInt8((microseconds >> 8) & 0xFF),
                UInt8(microseconds & 0xFF),
            ])
    }
    conductor.append(.meta(tick: 0, type: 0x58, data: [4, 2, 24, 8]))
    var events: [MidiEvent] = [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
    ]
    events += volume.map { .channel(tick: $0.0, status: 0xB0, data0: 0x07, data1: $0.1) }
    events += pan.map { .channel(tick: $0.0, status: 0xB0, data0: 0x0A, data1: $0.1) }
    events += modulation.map { .channel(tick: $0.0, status: 0xB0, data0: 0x01, data1: $0.1) }
    events += lfo.map {
        .channel(
            tick: $0.0, status: 0xB0,
            data0: TimeDefaults.ccLFOSpeed, data1: $0.1)
    }
    // A note ending at the requested tail keeps the document's musical length
    // at least that long, which every lane stroke's restored seam is measured
    // against.
    let resolvedEnd = tailTick ?? endTick
    if let tailTick {
        events.append(.channel(tick: tailTick - 24, status: 0x90, data0: 67, data1: 100))
        events.append(.channel(tick: tailTick, status: 0x80, data0: 67))
    }
    events.sort { $0.tick < $1.tick }
    conductor.sort { $0.tick < $1.tick }
    return MidiFile(
        division: division,
        chunks: [
            MidiChunk(events: conductor, endTick: resolvedEnd),
            MidiChunk(events: events, endTick: resolvedEnd),
        ])
}

@MainActor
public struct drawerAutomationAutomationFixture {
    public let session: DocumentSession
    public let viewport: DocumentViewport
    public let page: AutomationPage
    public let document: SongDocument

    public init(
        suite: DocumentSession, service: ProjectService, division: UInt16 = 24,
        volume: [(Tick, UInt8)] = [], pan: [(Tick, UInt8)] = [],
        modulation: [(Tick, UInt8)] = [], lfo: [(Tick, UInt8)] = [],
        echo: [(Tick, UInt8)] = [],
        tempo: [(Tick, UInt32)] = [(0, 500_000)], baseFontPx: Double = 13,
        plotted: Bool = true, config: SongConfig? = nil, tailTick: Tick? = 576
    ) {
        let session = makeSyntheticSession(
            suite: suite, service: service,
            file: drawerAutomationAutomationMidi(
                division: division, volume: volume, pan: pan,
                modulation: modulation, lfo: lfo, echo: echo, tempo: tempo,
                tailTick: tailTick),
            config: config)
        let document = session.document
        if !echo.isEmpty {
            // XCMD lanes are selector/payload traffic, not raw controller
            // events: they are written through the document's own lane API.
            document.writeLane(
                track: 0, lane: .controller(Xcmd.echoVolumeLane), from: 0,
                through: TimeDefaults.noTick,
                points: echo.map { LaneWrite(tick: $0.0, value: Int($0.1)) })
        }
        session.selectedTrack = 0
        let viewport = DocumentViewport(session: session)
        self.session = session
        self.viewport = viewport
        self.document = document
        page = AutomationPage(baseFontPx: baseFontPx)
        page.attach(viewport: viewport, palette: GridPalette())
        if plotted {
            page.configureBody(
                width: 480, height: 120, gutter: 0, devicePixelRatio: 1,
                baseFontPx: baseFontPx, dragDistance: 10)
        }
        session.onChange = { [weak page] change in
            let content: SessionChangeDomains = [.document, .bank]
            if !change.domains.intersection(content).isEmpty {
                page?.refreshFromDocument()
            } else if change.domains.contains(.selection),
                page?.menuOpen == true || page?.promptOpen == true
            {
                page?.refreshFromDocument()
            } else if change.domains.contains(.cursor) {
                page?.refreshEditCursor()
            }
        }
        viewport.onCameraChangeDetailed = { [weak page] _, _ in page?.refreshCamera() }
    }

    public var snapshot: DocumentSnapshot { DocumentSnapshot(document) }
    public var songEndTick: Tick { session.timeline.lengthTicks }
    public var volumeLane: AutomationParameter {
        .controlChange(track: 0, controller: TimeDefaults.ccVolume)
    }
    public var panLane: AutomationParameter { .controlChange(track: 0, controller: TimeDefaults.ccPan) }
    public var modulationLane: AutomationParameter {
        .controlChange(track: 0, controller: TimeDefaults.ccModulation)
    }
    public var bendLane: AutomationParameter { .pitchBend(track: 0) }
    public var echoLane: AutomationParameter { .controlChange(track: 0, controller: Xcmd.echoVolumeLane) }
    public var lfoLane: AutomationParameter {
        .controlChange(track: 0, controller: TimeDefaults.ccLFOSpeed)
    }

    public func lanePoints(_ parameter: AutomationParameter) -> [LanePoint] {
        guard let track = parameter.track, let lane = parameter.lane else { return [] }
        return document.lanePoints(track: track, lane: lane)
    }

    public func values(_ parameter: AutomationParameter) -> [String] {
        lanePoints(parameter).map { "\($0.tick):\($0.value)" }
    }

    public func laneValues(_ values: [AutomationLanePoint]) -> [String] {
        values.map { "\($0.tick):\($0.value)" }
    }

    public var tempoValues: [String] {
        document.state.tempo.map { point in
            let bpm = Int(
                TimeDefaults.tempoBPM(
                    forMicrosecondsPerQuarterNote: point.microsecondsPerQuarterNote
                ).rounded())
            return "\(point.tick):\(bpm)"
        }
    }
    public func playbackValues(_ parameter: AutomationParameter, at tick: Tick) -> [UInt8] {
        guard case .controlChange(let track, let controller) = parameter else { return [] }
        return session.timeline.events.compactMap { event in
            event.type == 0xB && event.track == UInt8(track)
                && event.data0 == controller && event.tick == tick ? event.data1 : nil
        }
    }

    public func playbackTempo(at tick: Tick) -> (microseconds: UInt32, bpm: Double)? {
        guard let point = session.timeline.tempoMap.first(where: { $0.tick == tick }) else {
            return nil
        }
        return (point.microsecondsPerQuarterNote, point.beatsPerMinute)
    }

    public func laneSnapshot(_ parameter: AutomationParameter) -> AutomationLaneSnapshot {
        AutomationLaneSnapshot(parameter: parameter, in: document, songEndTick: songEndTick)
    }

    /// The frozen facts of one parameter at the current revision, exactly as a
    /// press freezes them.
    public func facts(
        _ parameter: AutomationParameter,
        modifiers: AutomationModifiers = .init()
    ) -> AutomationFrozenFacts {
        AutomationFrozenFacts(
            parameter: parameter, snapshot: laneSnapshot(parameter),
            camera: viewport.camera.snapshot, selection: page.selection,
            modifiers: modifiers, songEndTick: songEndTick)
    }

    public func makeProjection(
        _ parameter: AutomationParameter,
        selection: AutomationTimeSelection? = nil,
        width: Double = 480, height: Double = 120
    ) -> AutomationLaneProjection {
        let facts = facts(parameter)
        let projection = AutomationProjection(
            camera: viewport.camera,
            bounds: AutomationPlotBounds(width: width, height: height, devicePixelRatio: 1),
            geometry: page.geometry,
            snapPolicy: AutomationProjectionCache().snapPolicy(viewport: viewport, font: page.baseFontPx, dpr: 1),
            songEndTick: songEndTick)
        return projection.project(
            facts.snapshot, selection: selection,
            usedTracks: Set(0..<document.engineTracks.usedTrackCount))
    }

    public func projection(_ parameter: AutomationParameter) -> AutomationLaneProjection {
        makeProjection(parameter)
    }

    /// Plot-local x of one tick through the shared camera.
    public func x(_ tick: Tick) -> Double { viewport.camera.contentX(tick: Double(tick)) }

    /// Plot-local y of one value through the page's own geometry.
    public func y(_ parameter: AutomationParameter, _ value: Int) -> Double {
        let projection = AutomationProjection(
            camera: viewport.camera,
            bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
            geometry: page.geometry,
            snapPolicy: AutomationProjectionCache().snapPolicy(viewport: viewport, font: page.baseFontPx, dpr: 1),
            songEndTick: songEndTick)
        return projection.y(value, metadata: AutomationParameterMetadata(parameter: parameter))
    }

    public func activate(_ parameter: AutomationParameter) {
        _ = page.activateParameter(index: AutomationCatalog.index(of: parameter, track: 0) ?? 0)
    }

    public func undo() -> Bool { (try? runBlocking { try await session.undo() }) ?? false }

    /// One node drag through the page's public pointer route, in plot
    /// coordinates, carrying the raw Qt modifier bits a QML event supplies. The
    /// pointer arms the drag with a travel past the activation distance and then
    /// settles, so the drag's own delta lands the mapped value on `target` while
    /// the tick keeps the press's column; `true` means the press itself was
    /// taken. A release's return value is the commit's outcome, so a caller
    /// asserts the lane it produced.
    @discardableResult
    public func drag(
        _ parameter: AutomationParameter, from: (tick: Tick, value: Int),
        to target: Int, armPixels: Double = 30, modifiers: Int
    ) -> Bool {
        let surface = AutomationInputSurface.plot.rawValue
        let button = DrawerQtButton.left
        let pressX = x(from.tick)
        let pressY = y(parameter, from.value)
        let targetY = y(parameter, target)
        let pressed = page.pointerPress(
            x: pressX, y: pressY, surface: surface, button: button,
            modifiers: modifiers)
        let armY = pressY - armPixels
        _ = page.pointerMove(x: pressX, y: armY, buttons: button, modifiers: modifiers)
        _ = page.pointerMove(
            x: pressX, y: armY + (targetY - pressY), buttons: button,
            modifiers: modifiers)
        _ = page.pointerRelease(
            x: pressX, y: armY + (targetY - pressY), button: button,
            modifiers: modifiers)
        return pressed
    }
}
