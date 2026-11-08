import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawPlayback

@testable import PorydawApp
@testable import PorydawDocument
@testable import PorydawPluginHost

private enum MidiEffectsPresenterCheckError: Error { case fixture, deadline }

@MainActor
private func midiEffectsPresenterWait(_ predicate: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while try await predicate() == false {
        guard ContinuousClock.now < deadline else { throw MidiEffectsPresenterCheckError.deadline }
        await Task.yield()
    }
}

@MainActor
private final class MidiEffectsPresenterFixture {
    let audio: NativeAudio
    let session: DocumentSession
    let workspace: DocumentWorkspace
    var presenter: MidiEffectsPresenter { workspace.midiEffects }
    let catalog: PluginCatalog
    private let playhead = SharedPlayheadPresenter()
    private let guides = PlayheadGuidesPresenter()
    private let events = EventListPresenter()
    var controller: TrackEffectsController { workspace.effects }

    init(suite: DocumentSession, service: ProjectService, catalog: PluginCatalog, audio: NativeAudio) {
        self.audio = audio
        self.catalog = catalog
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
            file: file, config: suite.document.state.config, source: suite.document.source,
            trackBudget: suite.document.trackBudget)
        session = DocumentSession(
            document: document, service: service, lease: suite.bankLease, slots: suite.bankSlots,
            dirty: false, loadName: suite.bankLoadName, sampleRate: audio.sampleRate)
        let palette = GridPalette()
        let typography = Typography(baseFontPx: 13)
        workspace = DocumentWorkspace(
            viewport: DocumentViewport(session: session), audio: audio, pluginCatalog: catalog,
            preferences: PreferencesStore(),
            playhead: playhead, playheadGuides: guides, eventList: events, palette: palette,
            typography: typography,
            callbacks: .init(
                changeTrackVoiceRequested: { (_: Int) in }, revealTrackVoiceRequested: { (_: Int) in },
                gridCommandAvailabilityChanged: {}, sessionStateChanged: {}, publicationFailed: { (_: String) in },
                timeSignaturePromptInvalidated: { (_: DocumentSession, _: UInt64) in }))
        workspace.trackHeaders.configureViewport(width: 228, height: 240, fontPx: 13, dpr: 1)
        workspace.trackHeaders.configureTextMetrics(titleLineSpacing: 18, boldLineSpacing: 18, subtitleLineSpacing: 14)
        workspace.activate()
    }

    func settle() async throws {
        try await midiEffectsPresenterWait {
            self.presenter.catalogDidChange()
            return !self.presenter.isScanning && !self.presenter.isLoading
        }
    }

    func ready() async throws {
        let timeline = audio.requestedTimelineIdentity
        try await midiEffectsPresenterWait {
            self.audio.songLoaded && self.audio.status.appliedTimelineIdentity == timeline
                && self.audio.status.appliedTransport == .stopped
        }
    }

    func row(_ name: String, modulePath: String? = nil) throws -> Int {
        let entries = catalog.entries.filter { (entry: PluginCatalogEntry) -> Bool in
            entry.isMidiProducer || entry.blockedReason != nil
        }
        guard
            let index = entries.firstIndex(where: { (entry: PluginCatalogEntry) -> Bool in
                entry.name == name && (modulePath == nil || entry.modulePath == modulePath)
            })
        else { throw MidiEffectsPresenterCheckError.fixture }
        return index
    }

    func select(_ name: String, modulePath: String? = nil) async throws -> EffectID {
        presenter.selectPlugin(index: try row(name, modulePath: modulePath))
        try await settle()
        guard let effect = session.document.effect(onTrack: 0), controller.instance(for: effect.id) != nil else {
            throw MidiEffectsPresenterCheckError.fixture
        }
        return effect.id
    }

    func finish() async throws {
        presenter.close()
        presenter.cancelScan()
        var scanFailure: (any Error)?
        do { try await settle() } catch { scanFailure = error }
        await controller.shutdown()
        workspace.teardown()
        await workspace.awaitAudioRelease()
        if let scanFailure { throw scanFailure }
    }
}

@MainActor
private func midiEffectsSelectionAndSettings(
    _ fixture: MidiEffectsPresenterFixture, check: CheckReport.Scoped
) async throws {
    let presenter = fixture.presenter
    let document = fixture.session.document
    presenter.open(track: -1)
    check.expect(!presenter.isOpen, message: "an invalid track never opens the setup panel")
    let headers = fixture.workspace.trackHeaders
    let plainTitle = headers.snapshots[0].titleRect
    let plainSubtitle = headers.snapshots[0].subtitleRect
    let rowHeight = headers.rowHeight
    let timeline = fixture.audio.requestedTimelineIdentity
    headers.showHeaderMenu(track: 0, x: 20, y: 10)
    check.expect(
        headers.menuItems.count == 7 && headers.menuItems[6].text == "MIDI Effects...",
        message: "the production header menu exposes MIDI Effects after Arpeggiator")
    headers.activateHeaderMenuAction(actionId: 7)
    check.expect(!headers.menuOpen && presenter.isOpen, message: "menu action 7 closes its menu before opening setup")
    try await fixture.settle()
    check.expect(presenter.isOpen && !presenter.trackLabel.isEmpty, message: "opening resolves the source track label")
    let names = (0..<presenter.plugins.count).map { (index: Int) -> String in presenter.plugins[index].name }
    check.expect(
        names.contains("TestGen") && names.contains("TestGenAudio") && names.contains("TestGenRealtimeOnly")
            && !names.contains("TestAudioOnly"),
        message: "only MIDI producers and blocked modules appear in the setup list")
    let before = document.history.undoCount
    presenter.selectPlugin(index: -1)
    presenter.selectPlugin(index: presenter.plugins.count)
    check.expect(document.history.undoCount == before, message: "invalid list indices never change the song")
    let first = try await fixture.select("TestGen")
    guard let initial = document.effect(onTrack: 0) else { throw MidiEffectsPresenterCheckError.fixture }
    let selectedRow = try fixture.row("TestGen")
    check.expect(
        document.history.undoCount == before + 1 && presenter.hasEffect
            && presenter.selectedPlugin == selectedRow,
        message: "select adds one effect in one undo step and publishes the selected class")
    check.expect(
        initial.config.plugin.input == .none && initial.config.plugin.pacing == .offline
            && initial.config.plugin.prerollBars == 0 && !presenter.canReload && presenter.canOpenEditor,
        message: "a loaded selection starts with default setup settings and offers its editor, not Reload")
    let header = headers.rows[0]
    check.expect(
        header.effectName == "TestGen" && !header.liveArmed && !header.effectStopped
            && !header.subtitle.isEmpty && headers.rowHeight == rowHeight
            && header.effectRect.y >= header.subtitleRect.y + header.subtitleRect.height
            && header.effectRect.y + header.effectRect.height <= Double(rowHeight - headers.separatorWidth),
        message:
            "selection publishes the badge on a third font-derived line without losing the voice or changing row height"
    )
    check.expect(
        headers.hitTarget(row: 0, x: header.subtitleRect.x + 1, y: header.subtitleRect.y + 1) == .voice
            && headers.hitTarget(row: 0, x: header.effectRect.x + 1, y: header.effectRect.y + 1) == .body,
        message: "voice hit testing uses the rendered subtitle rectangle, leaving the effect line a body target")
    presenter.setInputMode(value: 1)
    presenter.setPacing(value: 1)
    presenter.setPrerollBars(value: 2)
    check.expect(
        document.history.undoCount == before + 2 && presenter.inputMode == 1 && presenter.pacing == 1
            && presenter.prerollBars == 2,
        message: "all settings in one open panel session coalesce into one history group")
    check.expect(
        fixture.audio.requestedTimelineIdentity == timeline,
        message: "effect-only selection and grouped setup edits never republish the MIDI playback timeline")
    presenter.setInputMode(value: 2)
    presenter.setPacing(value: -1)
    presenter.setPrerollBars(value: 3)
    check.expect(
        presenter.inputMode == 1 && presenter.pacing == 1 && presenter.prerollBars == 2,
        message: "out-of-contract setup values leave the selected configuration unchanged")
    _ = try await fixture.session.undo()
    check.expect(
        document.effect(onTrack: 0)?.config == initial.config && presenter.inputMode == 0 && presenter.pacing == 0
            && presenter.prerollBars == 0,
        message: "one Undo reverts every setup setting, not the effect selection")
    _ = try await fixture.session.redo()
    presenter.close()
    presenter.open(track: 0)
    try await fixture.settle()
    let reopened = document.history.undoCount
    presenter.setPrerollBars(value: 1)
    check.expect(document.history.undoCount == reopened + 1, message: "reopening starts a distinct settings undo group")
    _ = try await fixture.session.undo()
    check.expect(presenter.prerollBars == 2, message: "Undo of the new session preserves the prior session settings")
    let previous = document.effect(onTrack: 0)
    let replacement = try await fixture.select("TestGenRealtimeOnly")
    check.expect(
        replacement != first && document.effects.count == 1 && document.effect(onTrack: 0)?.pluginState == nil
            && presenter.inputMode == 0 && presenter.pacing == 0 && presenter.prerollBars == 0,
        message: "replacement changes identity and resets settings without adding a second track effect")
    _ = try await fixture.session.undo()
    check.expect(
        document.effect(onTrack: 0) == previous && !presenter.isOpen,
        message: "one Undo restores the replaced effect and disappearance closes the panel")
    presenter.open(track: 0)
    try await fixture.settle()
    presenter.removeEffect()
    check.expect(!presenter.isOpen && document.effects.isEmpty, message: "Remove deletes the effect and closes setup")
    check.expect(
        header.effectName.isEmpty && !header.liveArmed && !header.effectStopped
            && headers.snapshots[0].titleRect == plainTitle && headers.snapshots[0].subtitleRect == plainSubtitle,
        message: "removal clears badge state and restores the unchanged two-line geometry")
    _ = try await fixture.session.undo()
    check.expect(document.effect(onTrack: 0) == previous, message: "Undo restores the removed effect's full settings")
    presenter.open(track: 0)
    try await fixture.settle()
    guard let restored = document.effect(onTrack: 0) else { throw MidiEffectsPresenterCheckError.fixture }
    try document.removeEffect(restored.id)
    check.expect(!presenter.isOpen, message: "external effect removal closes the panel through documentChanged")
}

@MainActor
private func midiEffectsCloseAndDiagnostics(
    _ fixture: MidiEffectsPresenterFixture, check: CheckReport.Scoped
) async throws {
    let presenter = fixture.presenter
    presenter.open(track: 0)
    try await fixture.settle()
    let id = try await fixture.select("TestGen")
    guard let instance = fixture.controller.instance(for: id) else { throw MidiEffectsPresenterCheckError.fixture }
    var report = NormalizationReport()
    report.notes = 3
    report.nonNoteEvents = 1
    report.snappedOnsets = 2
    fixture.controller.outputs[id] = EffectOutput(
        range: TimeRange(startTick: 0, endTick: 96), notes: [], origin: .render, report: report, degraded: false)
    check.expect(
        presenter.diagnostics == "notes: 3, nonNoteEvents: 1, snappedOnsets: 2",
        message: "diagnostics are one line containing exactly the non-zero normalization counters")
    fixture.controller.outputs[id] = EffectOutput(
        range: TimeRange(startTick: 0, endTick: 96), notes: [], origin: .grab,
        report: NormalizationReport(), degraded: false)
    check.expect(presenter.diagnostics.isEmpty, message: "zero diagnostics clear the readout")
    presenter.configure(fontPx: 18)
    presenter.configure(fontPx: .nan)
    check.expect(presenter.baseFontPx == 18, message: "configuration follows typography and rejects a non-finite size")
    try await fixture.controller.setLive(id, true)
    check.expect(
        fixture.workspace.trackHeaders.rows[0].liveArmed, message: "controller arming publishes the header Live state")
    let state = fixture.session.document.state
    presenter.close()
    check.expect(
        !presenter.isOpen && fixture.controller.isLive(id) && fixture.controller.instance(for: id) === instance
            && fixture.session.document.state == state && !instance.isEditorOpen,
        message: "closing setup neither disarms Live, unloads the helper nor edits the document")
    try await fixture.controller.setLive(id, false)
    check.expect(
        !fixture.workspace.trackHeaders.rows[0].liveArmed, message: "controller disarming clears the header Live state")
}

@MainActor
private func midiEffectsUnavailable(
    _ fixture: MidiEffectsPresenterFixture, check: CheckReport.Scoped
) async throws {
    let id = try fixture.session.document.addEffect(
        TrackEffectConfig(
            track: 0,
            plugin: PluginEffectConfig(
                modulePath: "/missing/porydaw-presenter-fixture.vst3", classUID: Array(repeating: 0, count: 16),
                name: "Missing fixture", input: .none, pacing: .offline, prerollBars: 0)))
    fixture.presenter.open(track: 0)
    try await fixture.settle()
    check.expect(
        fixture.presenter.status == "Plugin unavailable: Plugin is unknown or skipped."
            && fixture.presenter.hasEffect && fixture.presenter.selectedPlugin == -1
            && !fixture.presenter.canOpenEditor && !fixture.presenter.canReload
            && fixture.controller.instance(for: id) == nil,
        message: "an unknown identity publishes the exact unavailable reason without loading or offering Reload")
}

private func midiEffectsFaultState(_ fault: Int32) -> PluginStateBlob {
    var bytes: [UInt8] = []
    for field in [Int32(0), Int32(128), Int32(0), fault] {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: UInt32(bitPattern: field) >> shift))
        }
    }
    return PluginStateBlob(component: bytes, controller: bytes)
}

@MainActor
private func midiEffectsCrashAndReload(
    _ fixture: MidiEffectsPresenterFixture, fault: Int32, check: CheckReport.Scoped
) async throws {
    fixture.presenter.open(track: 0)
    try await fixture.settle()
    let id = try await fixture.select("TestGen")
    guard let instance = fixture.controller.instance(for: id) else { throw MidiEffectsPresenterCheckError.fixture }
    let state = fixture.session.document.state
    let armed = fault == 1
    if armed { try await fixture.controller.setLive(id, true) }
    // A stopped attached callback can fault between the two restore RPCs.
    // Rendering is needed only if injection has not already committed a failure.
    let injection = Task { @MainActor in try await instance.restore(midiEffectsFaultState(fault)) }
    let rendering = Task { @MainActor in
        try await injection.value
        if let failure = instance.failure { throw failure }
        try await fixture.controller.render(id, range: TimeRange(startTick: 0, endTick: 24))
    }
    let outcome = await rendering.result
    _ = await injection.result
    switch outcome {
    case .success:
        check.fail("the processing-fault fixture returned successful output")
    case .failure(let error):
        let committed: PluginHostError
        if let transport = error as? HelperProcessError {
            switch transport {
            case .eof, .terminated:
                guard fault == 1 else { throw error }
                committed = .native(transport.description)
            case .stoppedResponding, .timeout:
                guard fault == 2 else { throw error }
                committed = .stoppedResponding(transport.description)
            case .scannerMissing, .channelCreation, .channelUnlink, .invalidPayload, .notReady, .launch, .native:
                throw error
            }
        } else if let hostError = error as? PluginHostError {
            switch hostError {
            case .native:
                guard fault == 1 else { throw error }
            case .stoppedResponding:
                guard fault == 2 else { throw error }
            }
            committed = hostError
        } else {
            throw error
        }
        guard instance.failure == committed else { throw error }
        let reason = fault == 1 ? "stopped working" : "stopped responding"
        check.expect(
            fixture.controller.status(id) == .crashed(reason),
            message: "joined injection/render failure matches the exact committed helper cause and crash classification"
        )
    }
    let expected = fault == 1 ? "TestGen stopped working." : "TestGen stopped responding."
    try await midiEffectsPresenterWait {
        // Status must arrive through the workspace's production controller fan-out.
        return fixture.presenter.status == expected && fixture.presenter.canReload
    }
    check.expect(
        !fixture.presenter.canOpenEditor && fixture.session.document.state == state,
        message: "crash status disables the editor and preserves the last recorded song state")
    let header = fixture.workspace.trackHeaders.rows[0]
    check.expect(
        header.effectName == "TestGen" && header.effectStopped && !header.liveArmed,
        message: "crash notification publishes Stopped instead of Live without a document mutation")
    fixture.presenter.reloadPlugin()
    check.expect(fixture.presenter.isLoading, message: "manual Reload immediately publishes the pending operation")
    try await fixture.settle()
    check.expect(
        fixture.controller.instance(for: id) != nil && fixture.controller.instance(for: id) !== instance
            && !fixture.presenter.canReload && fixture.presenter.status.isEmpty
            && fixture.presenter.canOpenEditor && fixture.controller.isLive(id) == armed
            && !header.effectStopped && header.liveArmed == armed,
        message: "manual Reload clears Stopped and restores the appropriate header Live caption")
}

@MainActor
private func midiEffectsCatalogAndFolders(
    _ fixture: MidiEffectsPresenterFixture, modules: URL, launches: @MainActor () -> [String],
    check: CheckReport.Scoped
) async throws {
    let presenter = fixture.presenter
    let preferences = PreferencesStore()
    presenter.open(track: 0)
    try await fixture.settle()
    let initialLaunches = launches().count
    check.expect(initialLaunches > 0, message: "the fixture has exercised the real scanner")
    presenter.close()
    presenter.open(track: 0)
    try await fixture.settle()
    check.expect(launches().count == initialLaunches, message: "opening uses the unforced catalog cache")
    let blocked = (0..<presenter.plugins.count).first { (index: Int) -> Bool in presenter.plugins[index].blocked }
    guard let blocked else { throw MidiEffectsPresenterCheckError.fixture }
    let blockedName = presenter.plugins[blocked].name
    let before = fixture.session.document.state
    presenter.selectPlugin(index: blocked)
    check.expect(fixture.session.document.state == before, message: "a blocked row can never become a track effect")
    check.expect(!presenter.plugins[blocked].detail.isEmpty, message: "blocked rows expose their scanner diagnosis")
    presenter.retryBlocked(index: blocked)
    try await fixture.settle()
    check.expect(
        launches().count == initialLaunches + 1
            && (0..<presenter.plugins.count).contains { (index: Int) -> Bool in
                presenter.plugins[index].name == blockedName && presenter.plugins[index].blocked
            },
        message: "Retry re-probes only the blocked module and republishes its real failure")
    let beforeRescan = launches().count
    presenter.rescan()
    check.expect(presenter.isScanning, message: "Rescan immediately publishes scanning state")
    try await fixture.settle()
    check.expect(launches().count > beforeRescan, message: "forced Rescan probes cached modules again")
    presenter.rescan()
    presenter.cancelScan()
    try await fixture.settle()
    check.expect(!presenter.isScanning, message: "cancelling a pending scan settles without leaving a busy panel")
    let extra = modules.deletingLastPathComponent().appendingPathComponent("Extra Ω", isDirectory: true)
    try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
    presenter.addFolder(path: extra.absoluteString)
    presenter.addFolder(path: extra.appendingPathComponent(".").path)
    presenter.addFolder(path: "   ")
    try await fixture.settle()
    check.expect(
        presenter.folders == [modules.path, extra.path]
            && preferences.strings("vst3PluginFolders") == presenter.folders,
        message: "folder URLs normalize and deduplicate into the synchronized vst3PluginFolders preference")
    check.expect(
        PreferencesStore().strings("vst3PluginFolders") == presenter.folders,
        message: "a fresh preferences reader sees the synchronized custom roots")
    presenter.removeFolder(index: -1)
    presenter.removeFolder(index: 1)
    try await fixture.settle()
    check.expect(
        presenter.folders == [modules.path] && preferences.strings("vst3PluginFolders") == [modules.path],
        message: "folder removal persists only the remaining root")
    let secondModule = modules.appendingPathComponent("other/porydawtestgen.vst3").path
    let id = try await fixture.select("TestGen", modulePath: secondModule)
    let secondRow = try fixture.row("TestGen", modulePath: secondModule)
    check.expect(
        fixture.session.document.effect(onTrack: 0)?.config.plugin.modulePath == secondModule
            && presenter.selectedPlugin == secondRow,
        message: "identically named classes in separate modules keep module-path plus class-UID identity")
    presenter.rescan()
    try await fixture.settle()
    let rescannedRow = try fixture.row("TestGen", modulePath: secondModule)
    check.expect(
        fixture.session.document.effect(onTrack: 0)?.id == id
            && presenter.selectedPlugin == rescannedRow,
        message: "catalog rebuilding preserves the selected identity rather than selecting the first matching name")
}

@MainActor
private func midiEffectsWorkspaceLifecycle(
    _ fixture: MidiEffectsPresenterFixture, check: CheckReport.Scoped
) async throws {
    let presenter = fixture.presenter
    presenter.open(track: 0)
    try await fixture.settle()
    fixture.session.publishChange([.bank])
    check.expect(!presenter.isOpen, message: "the production bank publication closes setup")
    presenter.open(track: 0)
    try await fixture.settle()
    fixture.workspace.cancel(reason: GridCancelReason.windowDeactivated.rawValue)
    check.expect(!presenter.isOpen, message: "window deactivation input cancellation closes setup")
    presenter.open(track: 0)
    try await fixture.settle()
    let id = try await fixture.select("TestGen")
    try await fixture.controller.setLive(id, true)
    fixture.workspace.deactivate()
    check.expect(
        !presenter.isOpen && !fixture.controller.isLive(id) && !fixture.workspace.trackHeaders.rows[0].liveArmed,
        message: "workspace deactivation closes setup and publishes the controller's disarmed header")
    await fixture.workspace.awaitAudioRelease()
    fixture.workspace.activate()
    try await fixture.ready()
    presenter.open(track: 0)
    try await fixture.settle()
    fixture.workspace.suspendCallbacks()
    check.expect(!presenter.isOpen, message: "callback suspension closes setup before scene release")
    presenter.open(track: 0)
    fixture.workspace.teardown()
    check.expect(!presenter.isOpen, message: "workspace teardown closes setup even after suspension")
}

@MainActor
private func midiEffectsSharedFolders(
    _ fixture: MidiEffectsPresenterFixture, service: ProjectService, modules: URL, check: CheckReport.Scoped
) async throws {
    fixture.workspace.deactivate()
    await fixture.workspace.awaitAudioRelease()
    let peer = MidiEffectsPresenterFixture(
        suite: fixture.session, service: service, catalog: fixture.catalog, audio: fixture.audio)
    do {
        try await peer.ready()
        let extra = modules.deletingLastPathComponent().appendingPathComponent("Shared roots")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let source = modules.appendingPathComponent("porydawtestgen.vst3")
        let copied = extra.appendingPathComponent("porydawtestgen.vst3")
        try FileManager.default.copyItem(at: source, to: copied)
        fixture.presenter.addFolder(path: extra.path)
        try await fixture.settle()
        peer.presenter.open(track: 0)
        try await peer.settle()
        check.expect(
            peer.presenter.folders.contains(extra.path)
                && fixture.catalog.entries.contains { (entry: PluginCatalogEntry) -> Bool in
                    entry.modulePath == copied.path
                },
            message: "an already-created workspace opens with the other workspace's canonical custom folders")
        let another = modules.deletingLastPathComponent().appendingPathComponent("Second shared root")
        peer.presenter.addFolder(path: another.path)
        try await peer.settle()
        fixture.presenter.rescan()
        try await fixture.settle()
        check.expect(
            fixture.presenter.folders.contains(extra.path) && fixture.presenter.folders.contains(another.path)
                && fixture.catalog.entries.contains { (entry: PluginCatalogEntry) -> Bool in
                    entry.modulePath == copied.path
                },
            message: "cross-workspace mutations merge canonical roots and a later Rescan never drops a peer's plugins")
        fixture.presenter.removeFolder(index: fixture.presenter.folders.firstIndex(of: extra.path) ?? -1)
        try await fixture.settle()
        peer.presenter.rescan()
        try await peer.settle()
        check.expect(
            !peer.presenter.folders.contains(extra.path)
                && !fixture.catalog.entries.contains { (entry: PluginCatalogEntry) -> Bool in
                    entry.modulePath == copied.path
                },
            message: "cross-workspace removal also reaches the next scan of an existing presenter")
    } catch {
        try await peer.finish()
        throw error
    }
    try await peer.finish()
    fixture.workspace.activate()
    try await fixture.ready()
}

@MainActor
func runMidiEffectsPresenterChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let check = report.scoped(cppID: "no-row/miditools/presenter")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "midi-effects-presenter-\(UUID().uuidString)")
    let preferences = PreferencesStore()
    let savedFolders = preferences.strings("vst3PluginFolders")
    defer {
        preferences.setStrings("vst3PluginFolders", savedFolders)
        preferences.synchronize()
        do {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        } catch { check.fail("presenter fixture cleanup: \(error)") }
    }
    do {
        let executable = HelperProcess.executableURL
        let fixtures = executable.deletingLastPathComponent().appendingPathComponent("vstfixtures")
        let modules = root.appendingPathComponent("modules")
        try FileManager.default.createDirectory(
            at: modules.appendingPathComponent("other"), withIntermediateDirectories: true)
        for path in ["porydawtestgen.vst3", "other/porydawtestgen.vst3", "porydawtestcrash.vst3"] {
            let name = URL(fileURLWithPath: path).lastPathComponent
            try FileManager.default.copyItem(
                at: fixtures.appendingPathComponent(name), to: modules.appendingPathComponent(path))
        }
        var launched: [String] = []
        let catalog = PluginCatalog(
            cacheDirectory: root.appendingPathComponent("cache"), scannerURL: executable, standardRoots: [],
            childLaunched: { (path: String, _: Int32) in launched.append(path) })
        preferences.setStrings("vst3PluginFolders", ["  ", modules.appendingPathComponent(".").path, modules.path])
        let audio = try runBlocking { try await NativeAudio.make() }
        defer {
            do { try runBlocking { await audio.shutdown() } } catch {
                check.fail("presenter fixture audio cleanup: \(error)")
            }
        }
        @MainActor
        func run(
            catalog override: PluginCatalog? = nil,
            _ body: @escaping @MainActor (MidiEffectsPresenterFixture) async throws -> Void
        ) throws {
            try runBlocking {
                let fixture = MidiEffectsPresenterFixture(
                    suite: session, service: service, catalog: override ?? catalog, audio: audio)
                do {
                    try await fixture.ready()
                    try await body(fixture)
                } catch {
                    try await fixture.finish()
                    throw error
                }
                try await fixture.finish()
            }
        }
        try run { (fixture: MidiEffectsPresenterFixture) in
            try await midiEffectsSelectionAndSettings(fixture, check: check)
        }
        try run { (fixture: MidiEffectsPresenterFixture) in
            try await midiEffectsCloseAndDiagnostics(fixture, check: check)
        }
        try run { (fixture: MidiEffectsPresenterFixture) in
            try await midiEffectsUnavailable(fixture, check: check)
        }
        for fault: Int32 in [1, 2] {
            try run { (fixture: MidiEffectsPresenterFixture) in
                try await midiEffectsCrashAndReload(fixture, fault: fault, check: check)
            }
        }
        try run { (fixture: MidiEffectsPresenterFixture) in
            try await midiEffectsCatalogAndFolders(fixture, modules: modules, launches: { launched }, check: check)
        }
        try run { (fixture: MidiEffectsPresenterFixture) in
            try await midiEffectsWorkspaceLifecycle(fixture, check: check)
        }
        try run { (fixture: MidiEffectsPresenterFixture) in
            try await midiEffectsSharedFolders(fixture, service: service, modules: modules, check: check)
        }
        preferences.setStrings("vst3PluginFolders", [])
        let emptyCatalog = PluginCatalog(
            cacheDirectory: root.appendingPathComponent("empty-cache"), scannerURL: executable, standardRoots: [])
        try run(catalog: emptyCatalog) { (fixture: MidiEffectsPresenterFixture) in
            fixture.presenter.open(track: 0)
            try await fixture.settle()
            check.expect(
                fixture.presenter.status == "No MIDI-producing VST3 plugins found. Add a folder or Rescan."
                    && fixture.presenter.plugins.count == 0 && !fixture.presenter.hasEffect,
                message: "an empty unforced scan publishes the exact empty-list guidance")
        }
    } catch { check.fail("headless MidiEffectsPresenter fixture: \(error)") }
}
