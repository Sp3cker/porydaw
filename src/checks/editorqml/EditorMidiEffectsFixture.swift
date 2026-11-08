import Foundation
import PorydawAppPresentation
import PorydawCore

@testable import PorydawApp
@testable import PorydawDocument
@testable import PorydawPluginHost

@MainActor
final class EditorMidiEffectsFixture {
    private enum Failure: Error { case fixture, deadline }
    private let audio: NativeAudio
    private let fixture: WorkspacePresenterFixture
    private let session: DocumentSession
    var headers: TrackHeadersPresenter { fixture.workspace.trackHeaders }
    private(set) var voiceRequests = 0

    private init(source: DocumentSession, audio: NativeAudio) {
        self.audio = audio
        let file = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 0x58, data: [4, 2, 24, 8])], endTick: 192),
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC0, data0: 0),
                        .channel(tick: 0, status: 0x90, data0: 40, data1: 100),
                        .channel(tick: 24, status: 0x80, data0: 40),
                    ], endTick: 192),
            ])
        let document = SongDocument(
            file: file, config: source.document.state.config, source: source.document.source,
            trackBudget: source.document.trackBudget)
        session = DocumentSession(
            document: document, service: source.service, lease: source.bankLease,
            slots: source.bankSlots, dirty: false, loadName: source.bankLoadName,
            sampleRate: audio.sampleRate)
        fixture = WorkspacePresenterFixture(
            viewport: DocumentViewport(session: session), audio: audio,
            callbacks: .init(
                changeTrackVoiceRequested: { (_: Int) in }, revealTrackVoiceRequested: { (_: Int) in },
                gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
                publicationFailed: { (_: String) in },
                timeSignaturePromptInvalidated: { (_: DocumentSession, _: UInt64) in }))
        fixture.workspace.activate()
        fixture.workspace.trackHeaders.onChangeTrackVoiceRequested = { [weak self] (_: Int) in
            self?.voiceRequests += 1
        }
    }

    static func make(source: DocumentSession) async throws -> EditorMidiEffectsFixture {
        let fixture = EditorMidiEffectsFixture(source: source, audio: try await NativeAudio.make())
        do {
            let module = HelperProcess.executableURL.deletingLastPathComponent()
                .appendingPathComponent("vstfixtures/porydawtestgen.vst3")
            await fixture.fixture.catalog.scan(folders: [module.path], force: false)
            guard
                let entry = fixture.fixture.catalog.entries.first(where: { (entry: PluginCatalogEntry) -> Bool in
                    entry.name == "TestGen" && entry.modulePath == module.path
                })
            else { throw Failure.fixture }
            let id = try fixture.session.document.addEffect(
                TrackEffectConfig(
                    track: 0,
                    plugin: PluginEffectConfig(
                        modulePath: entry.modulePath, classUID: entry.classUID, name: entry.name,
                        input: .none, pacing: .offline, prerollBars: 0)))
            try await fixture.fixture.workspace.effects.load(id)
            try await fixture.wait {
                fixture.audio.songLoaded
                    && fixture.audio.status.appliedTimelineIdentity == fixture.audio.requestedTimelineIdentity
                    && fixture.audio.status.appliedTransport == .stopped
            }
            return fixture
        } catch {
            try await fixture.finish()
            throw error
        }
    }

    func setLive(_ enabled: Bool) async throws {
        guard let id = session.document.effect(onTrack: 0)?.id else { throw Failure.fixture }
        try await fixture.workspace.effects.setLive(id, enabled)
    }

    func crash() async throws {
        let controller = fixture.workspace.effects
        guard let id = session.document.effect(onTrack: 0)?.id,
            controller.isLive(id), let instance = controller.instance(for: id)
        else { throw Failure.fixture }
        var bytes: [UInt8] = []
        for field in [Int32(0), Int32(128), Int32(0), Int32(1)] {
            for shift in stride(from: 0, to: 32, by: 8) {
                bytes.append(UInt8(truncatingIfNeeded: UInt32(bitPattern: field) >> shift))
            }
        }
        let state = PluginStateBlob(component: bytes, controller: bytes)
        let injection = Task { @MainActor in try await instance.restore(state) }
        let outcome = await injection.result
        try await wait { controller.status(id) == .crashed("stopped working") }
        if case .failure(let error) = outcome {
            let committed: PluginHostError
            if let transport = error as? HelperProcessError {
                switch transport {
                case .eof, .terminated: committed = .native(transport.description)
                default: throw error
                }
            } else if let host = error as? PluginHostError, case .native = host {
                committed = host
            } else {
                throw error
            }
            guard instance.failure == committed else { throw error }
        }
    }

    func reload() async throws {
        guard let id = session.document.effect(onTrack: 0)?.id else { throw Failure.fixture }
        try await fixture.workspace.effects.reload(id)
    }

    func setTheme(_ mode: String) {
        PreferencesStore().setString(key: "theme.mode", value: mode)
        fixture.workspace.refreshAppearance()
    }

    func finish() async throws {
        await fixture.workspace.effects.shutdown()
        fixture.workspace.teardown()
        await fixture.workspace.awaitAudioRelease()
        await audio.shutdown()
        if FileManager.default.fileExists(atPath: fixture.catalogDirectory.path) {
            try FileManager.default.removeItem(at: fixture.catalogDirectory)
        }
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw Failure.deadline }
            await Task.yield()
        }
    }
}
