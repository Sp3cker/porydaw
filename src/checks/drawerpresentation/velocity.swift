import Foundation
import PorydawApp
import PorydawAppPresentation
import PorydawCore
import PorydawDocument

@MainActor
func drawerVelocityValueAxisLadder(_ report: CheckReport) {
    var geometry = VelocityAxisGeometry()
    geometry.height = 120
    geometry.verticalInset = 5
    geometry.labelHeight = 14
    geometry.continuousDensityD1 = 78
    geometry.continuousDensityD2 = 108
    geometry.continuousDensityD3 = 156
    geometry.continuousDensityD4 = 312
    let continuous = VelocityAxisModel(
        map: VelocityMap(voiceKind: .unresolved),
        geometry: geometry, activeValues: [100, 64])
    report.expectEqual(
        expected: VelocityAxisModel.Mode.continuous.rawValue, actual: continuous.mode.rawValue,
        cppID: drawerVelocityAxisID,
        what: "an unresolved voice uses the continuous 1-127 ruler")
    report.expect(
        continuous.labels.count == 5 && continuous.ticks.count == 9, cppID: drawerVelocityAxisID,
        message: "the mid density band publishes 9 ticks and 5 labels")
    report.expect(
        continuous.labels.map(\.velocity) == [127, 96, 64, 32, 1], cppID: drawerVelocityAxisID,
        message: "the density band's labels descend from 127 to 1")
    report.expect(
        continuous.ticks.map(\.velocity) == [127, 112, 96, 80, 64, 48, 32, 16, 1],
        cppID: drawerVelocityAxisID, message: "the density band's ticks step by sixteen")
    report.expectEqual(
        expected: 2, actual: continuous.markers.count, cppID: drawerVelocityAxisID,
        what: "one marker per distinct displayed value")
    report.expectEqual(
        expected: 64, actual: continuous.markers[0].velocity, cppID: drawerVelocityAxisID,
        what: "the lowest displayed value names the first marker")
    report.expectEqual(
        expected: 100, actual: continuous.markers[1].velocity, cppID: drawerVelocityAxisID,
        what: "the highest displayed value names the second marker")
    report.expect(
        continuous.markers[0].y > continuous.markers[1].y, cppID: drawerVelocityAxisID,
        message: "a lower velocity draws lower on the ruler")
    report.expect(
        abs(continuous.markers[0].y - continuous.velocityToY(64)) <= 1,
        cppID: drawerVelocityAxisID,
        message: "the lower marker aligns with its independently supplied velocity 64")
    let single = VelocityAxisModel(
        map: VelocityMap(voiceKind: .unresolved), geometry: geometry,
        activeValues: [76, 76])
    report.expectEqual(
        expected: 1, actual: single.markers.count, cppID: drawerVelocityAxisID,
        what: "equal displayed values collapse to one marker")
    report.expectEqual(
        expected: 127, actual: continuous.yToVelocity(continuous.top), cppID: drawerVelocityAxisID,
        what: "the ruler's top is velocity 127")
    report.expectEqual(
        expected: 1, actual: continuous.yToVelocity(continuous.bottom), cppID: drawerVelocityAxisID,
        what: "the ruler's bottom is velocity 1")
    report.expectEqual(
        expected: 127, actual: continuous.yToVelocity(-500), cppID: drawerVelocityAxisID,
        what: "a pointer above the ruler clamps to the maximum velocity")

    var short = geometry
    short.height = 40
    let dense = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: short)
    report.expect(
        dense.ticks.count == 5 && dense.labels.count == 3, cppID: drawerVelocityAxisID,
        message: "a 40px body uses the first density band")
    report.expect(
        dense.labels.map(\.velocity) == [127, 64, 1], cppID: drawerVelocityAxisID,
        message: "the first band labels 127/64/1 only")
    report.expect(
        dense.hasLabel(64) && !dense.hasLabel(96), cppID: drawerVelocityAxisID,
        message: "the first band omits the mid values")
    var tall = geometry
    tall.height = 400
    let finest = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: tall)
    report.expect(
        finest.ticks.count == 32 && finest.labels.count == 17, cppID: drawerVelocityAxisID,
        message: "a 400px body reaches the finest band's tick and label caps")

    let labelY = continuous.labels[2].y
    report.expectEqual(
        expected: 64, actual: continuous.rulerVelocityAt(y: labelY, labelHeight: 14), cppID: drawerVelocityAxisID,
        what: "a ruler press inside a label row takes its value")
    let betweenRows = (continuous.labels[0].y + continuous.labels[1].y) / 2
    report.expectEqual(
        expected: -1, actual: continuous.rulerVelocityAt(y: betweenRows, labelHeight: 2),
        cppID: drawerVelocityAxisID, what: "a ruler press between rows reports no value")
    report.expect(
        continuous.inRuler(x: 0, rulerWidth: 56), cppID: drawerVelocityAxisID,
        message: "the ruler owns x = 0")
    report.expect(
        !continuous.inRuler(x: 56, rulerWidth: 56), cppID: drawerVelocityAxisID,
        message: "the ruler ends at the gutter width")
    report.expectEqual(
        expected: "Velocity", actual: continuous.accessibleDescription, cppID: drawerVelocityAxisID,
        what: "the continuous ruler's description is the plain domain")
}

@MainActor
func drawerVelocityPsgIntrinsicRows(_ report: CheckReport) {
    var geometry = VelocityAxisGeometry()
    geometry.height = 120
    geometry.verticalInset = 5
    geometry.labelHeight = 14
    geometry.continuousDensityD1 = 78
    geometry.continuousDensityD2 = 108
    geometry.continuousDensityD3 = 156
    geometry.continuousDensityD4 = 312
    let square = VelocityAxisModel(
        map: VelocityMap(voiceKind: .square1), geometry: geometry,
        activeValues: [76])
    report.expectEqual(
        expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: square.mode.rawValue, cppID: drawerVelocityPsgID,
        what: "a PSG voice uses the intrinsic level ruler")
    report.expectEqual(
        expected: 16, actual: square.graduations.count, cppID: drawerVelocityPsgID,
        what: "Square 1 publishes sixteen volume levels")
    let wave = VelocityAxisModel(map: VelocityMap(voiceKind: .wave), geometry: geometry)
    report.expectEqual(
        expected: 5, actual: wave.graduations.count, cppID: drawerVelocityPsgID,
        what: "Programmable Wave publishes five volume levels")
    let noise = VelocityAxisModel(map: VelocityMap(voiceKind: .noise), geometry: geometry)
    report.expectEqual(
        expected: 16, actual: noise.graduations.count, cppID: drawerVelocityPsgID,
        what: "Noise publishes sixteen volume levels")
    report.expectEqual(
        expected: "Vol 10", actual: square.graduations[9].text, cppID: drawerVelocityPsgID,
        what: "a graduation names its own level")
    report.expectEqual(
        expected: 76, actual: square.graduations[9].velocity, cppID: drawerVelocityPsgID,
        what: "level 9's representative velocity is 76")
    report.expect(
        square.graduations[9].active, cppID: drawerVelocityPsgID,
        message: "the displayed value marks its own graduation active")
    report.expectEqual(
        expected: 1, actual: square.graduations.filter(\.active).count,
        cppID: drawerVelocityPsgID,
        what: "hovering one PSG value lights exactly one graduation")
    report.expect(
        square.graduations[9].audible, cppID: drawerVelocityPsgID,
        message: "an audible level is not the silent level")
    report.expect(
        !square.graduations[0].audible, cppID: drawerVelocityPsgID,
        message: "level 0 is the silent level")
    report.expect(
        square.levelToY(0) > square.levelToY(15), cppID: drawerVelocityPsgID,
        message: "lower levels draw lower")
    report.expectEqual(
        expected: 9, actual: square.yToLevel(square.levelToY(9)), cppID: drawerVelocityPsgID,
        what: "a level center maps back to its own level")
    let boundary = square.levelBoundaryToY(8)
    report.expect(
        boundary < square.levelToY(8) && boundary > square.levelToY(9), cppID: drawerVelocityPsgID,
        message: "a level boundary sits between the two row centers")
    report.expectEqual(
        expected: 76, actual: square.rulerVelocityAt(y: square.levelToY(9), labelHeight: 14),
        cppID: drawerVelocityPsgID, what: "an intrinsic ruler press takes the level's value")
    report.expect(
        square.accessibleDescription.contains("Square 1"), cppID: drawerVelocityPsgID,
        message: "the accessible description names the voice")
}

@MainActor
func drawerVelocityKeysplitPerNoteMapping(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService
) {
    var macros = Array(repeating: Int32(-1), count: 128)
    macros[60] = BankVoiceMacro.square1
    macros[67] = BankVoiceMacro.programmableWave
    macros[72] = BankVoiceMacro.square1
    let split = BankSlotView(
        kind: BankSlotKind.editable,
        voice: BankVoice(macro: BankVoiceMacro.keysplitAll),
        subvoiceMacros: macros)
    let slots = [split, BankSlotView(), split]
    let keyless = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots)
    report.expect(
        keyless.map == VelocityMap(voiceKind: .keyless) && !keyless.editable,
        cppID: drawerVelocityKeysplitID, message: "a split without a note key remains keyless")
    let invalid = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: 61)
    report.expect(
        invalid.map == VelocityMap(voiceKind: .invalid) && !invalid.editable,
        cppID: drawerVelocityKeysplitID, message: "invalid child facts never borrow another key")
    for (key, kind) in [(60, VoiceKind.square1), (67, .wave), (72, .square1)] {
        let context = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: key)
        report.expect(
            context.editable && context.map == VelocityMap(voiceKind: kind),
            cppID: drawerVelocityKeysplitID, message: "key \(key) resolves its own child map")
    }
    report.expect(
        split.subvoiceMacro(forKey: -1) == nil
            && split.subvoiceMacro(forKey: 128) == nil,
        cppID: drawerVelocityKeysplitID, message: "out-of-domain keys do not resolve")
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(drawerVelocityKeysplitID, "the staged project fixture is unavailable")
        return
    }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("drawer-velocity-keysplit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let fixtureService = ProjectService()
    defer {
        do {
            try runBlocking { await fixtureService.close() }
        } catch {
            report.fail(drawerVelocityKeysplitID, "could not close the keysplit fixture: \(error)")
        }
    }
    let loaded: (split: LoadedSong, unsupported: LoadedSong)
    do {
        try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: scratch)
        let voicegroups = scratch.appendingPathComponent("sound/voicegroups", isDirectory: true)
        let square = "\tvoice_square_1 60, 0, 2, 2, 2, 3, 12, 4"
        let wave = "\tvoice_programmable_wave 60, 0, ProgrammableWaveData_fixture_pulse, 2, 3, 12, 4"
        let children = (60...72).map { $0 == 67 ? wave : square }.joined(separator: "\n")
        try """
        \t.align 2
        velocity_children::
        voice_group velocity_children, 60
        \(children)

        """.write(
            to: voicegroups.appendingPathComponent("velocity_children.inc"),
            atomically: true, encoding: .utf8)
        try """
        \t.align 2
        velocity_split::
        voice_group velocity_split
        \tvoice_keysplit_all velocity_children
        \(square)
        \tvoice_keysplit_all velocity_children

        """.write(
            to: voicegroups.appendingPathComponent("velocity_split.inc"),
            atomically: true, encoding: .utf8)
        try """
        \t.align 2
        velocity_unsupported::
        voice_group velocity_unsupported, 36
        \(square)

        """.write(
            to: voicegroups.appendingPathComponent("velocity_unsupported.inc"),
            atomically: true, encoding: .utf8)
        let cfgPath = scratch.appendingPathComponent("sound/songs/midi/midi.cfg")
        var cfg = try String(contentsOf: cfgPath, encoding: .utf8)
        let splitRoute = "mus_gym.mid: -E -R50 -G_fixture_rich -V100"
        let unsupportedRoute = "mus_oldale.mid: -E -R50 -G_fixture_rich -V100"
        guard cfg.contains(splitRoute), cfg.contains(unsupportedRoute) else {
            report.fail(drawerVelocityKeysplitID, "fixture MIDI bank routes are missing")
            return
        }
        cfg = cfg.replacingOccurrences(
            of: splitRoute,
            with: "mus_gym.mid: -E -R50 -G_velocity_split -V100")
        cfg = cfg.replacingOccurrences(
            of: unsupportedRoute,
            with: "mus_oldale.mid: -E -R50 -G_velocity_unsupported -V100")
        try cfg.write(to: cfgPath, atomically: true, encoding: .utf8)
        try runBlocking { try await fixtureService.open(root: scratch.path) }
        loaded = (
            split: try runBlocking { try await fixtureService.openSong(label: "mus_gym") },
            unsupported: try runBlocking { try await fixtureService.openSong(label: "mus_oldale") }
        )
    } catch {
        report.fail(drawerVelocityKeysplitID, "could not load the staged keysplit fixture: \(error)")
        return
    }
    let document = SongDocument(
        file: drawerVelocityVelocityPageFixture(),
        config: loaded.split.config,
        source: loaded.split.source,
        trackBudget: loaded.split.trackBudget)
    let splitSession = DocumentSession(
        document: document, service: fixtureService,
        lease: loaded.split.bank, slots: loaded.split.bankSlots,
        dirty: loaded.split.bank.dirty, loadName: loaded.split.bank.loadName,
        sampleRate: 48_000)
    splitSession.selectedTrack = 0
    let page = VelocityPage(baseFontPx: 13)
    let splitViewport = DocumentViewport(session: splitSession)
    page.attach(viewport: splitViewport, palette: GridPalette())
    page.configureBody(
        width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let notes = document.notes(in: 0)
    splitSession.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    report.expect(
        page.detentsAvailable && !page.contextUnsupported
            && page.axisMode == VelocityAxisModel.Mode.intrinsic.rawValue,
        cppID: drawerVelocityKeysplitID, message: "compatible per-key PSG notes retain detents")
    splitSession.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expect(
        !page.detentsAvailable && !page.contextUnsupported
            && page.axisMode == VelocityAxisModel.Mode.continuous.rawValue,
        cppID: drawerVelocityKeysplitID, message: "mixed PSG maps remain editable and continuous")
    for note in notes.prefix(2) {
        let kind: VoiceKind = note.pitch == 60 ? .square1 : .wave
        let map = VelocityMap(voiceKind: kind)
        let noteAxis = VelocityAxisModel(map: map, geometry: page.axisModel.geometry)
        let handle = page.publishedHandlesSnapshot.first { $0.noteIdText == "\(note.id.rawValue)" }
        report.expect(
            handle?.y == noteAxis.levelToY(map.level(of: Int(note.velocity))!),
            cppID: drawerVelocityKeysplitID,
            message: "mixed selection places each handle using its own level boundaries")
    }
    if let wave = page.publishedHandlesSnapshot.first(where: { $0.noteIdText == "\(notes[1].id.rawValue)" }) {
        _ = page.pointerMove(x: wave.x, y: wave.y, buttons: 0)
        report.expect(
            page.axisModel.map == VelocityMap(voiceKind: .wave),
            cppID: drawerVelocityKeysplitID, message: "hover resolves the hovered note key")
        report.expectEqual(
            expected: 1, actual: page.axisModel.graduations.filter(\.active).count,
            cppID: drawerVelocityPsgID,
            what: "hovering the live PSG note lights exactly one ruler graduation")
        page.pointerLeave()
    }
    let before = DocumentSnapshot(document)
    report.expect(
        page.openSelectedVelocityPrompt(), cppID: drawerVelocityKeysplitID,
        message: "mixed per-key selection opens its prompt")
    page.updatePromptDraft(draft: "127")
    report.expect(
        DocumentSnapshot(document) == before, cppID: drawerVelocityKeysplitID,
        message: "per-key prompt drafts never mutate history")
    report.expect(
        page.acceptPrompt(), cppID: drawerVelocityKeysplitID,
        message: "per-key prompt accepts one captured transaction")
    let accepted = DocumentSnapshot(document)
    report.expect(
        document.note(notes[0].id)?.velocity == 127
            && document.note(notes[1].id)?.velocity == 127
            && document.note(notes[2].id)?.velocity == notes[2].velocity
            && accepted.revision == before.revision + 1,
        cppID: drawerVelocityKeysplitID, message: "acceptance changes only captured notes once")
    report.expect(
        !page.acceptPrompt() && DocumentSnapshot(document) == accepted,
        cppID: drawerVelocityKeysplitID, message: "repeated acceptance cannot duplicate a transaction")
    _ = try? runBlocking { try await splitSession.undo() }
    report.expect(
        document.note(notes[0].id)?.velocity == notes[0].velocity
            && document.note(notes[1].id)?.velocity == notes[1].velocity,
        cppID: drawerVelocityKeysplitID, message: "one undo restores both captured values")
    page.detach()
    withExtendedLifetime(splitViewport) {}

    let invalidDocument = SongDocument(
        file: drawerVelocityVelocityPageFixture(),
        config: loaded.unsupported.config,
        source: loaded.unsupported.source,
        trackBudget: loaded.unsupported.trackBudget)
    let invalidSession = DocumentSession(
        document: invalidDocument, service: fixtureService,
        lease: loaded.unsupported.bank, slots: loaded.unsupported.bankSlots,
        dirty: loaded.unsupported.bank.dirty,
        loadName: loaded.unsupported.bank.loadName,
        sampleRate: 48_000)
    invalidSession.selectedTrack = 0
    let invalidViewport = DocumentViewport(session: invalidSession)
    page.attach(viewport: invalidViewport, palette: GridPalette())
    report.expect(
        page.contextUnsupported, cppID: drawerVelocityKeysplitID,
        message: "the invalid bank context advertises that velocity editing is unavailable")
    let invalidBefore = DocumentSnapshot(invalidDocument)
    _ = page.pointerPress(
        x: 399, y: 0, surface: VelocityInputSurface.plot.rawValue,
        button: 1, modifiers: 0)
    report.expect(
        !page.interactionActive, cppID: drawerVelocityKeysplitID,
        message: "an unsupported paint press never suspends follow or owns Escape")
    _ = page.pointerMove(x: 0, y: 60, buttons: 1)
    _ = page.pointerRelease(x: 0, y: 60, button: 1)
    report.expect(
        DocumentSnapshot(invalidDocument) == invalidBefore,
        cppID: drawerVelocityKeysplitID,
        message: "dragging an unsupported velocity context cannot change notes or history")
    page.detach()
    withExtendedLifetime(invalidViewport) {}
}
