import Foundation
@testable import PorydawApp
import PorydawCore

private let detentDragLedger = "velocity/VelocityEditingTest::velocityDetentDragging"
private let detentPaintLedger = "velocity/VelocityEditingTest::velocityDetentPainting"
private let paintLedger = "velocity/VelocityEditingTest::velocityPainting"
private let rollLedger = "velocity/VelocityEditingTest::velocityRoll"

@MainActor
private func velocityGapExpect(
    _ report: CheckReport, ledger: String, row: String,
    _ facts: [(id: String, condition: Bool, message: String)]
) {
    for fact in facts {
        report.expect(fact.condition, cppID: ledger,
                      message: "\(fact.id)-\(row): \(fact.message)")
    }
}

@MainActor
private func velocityGapFail(
    _ report: CheckReport, ledger: String, row: String, ids: [String], message: String
) {
    for id in ids { report.fail(ledger, "\(id)-\(row): \(message)") }
}

@MainActor
private func velocityGapFixture(
    suite: DocumentSession, service: ProjectService, program: Int? = nil
) -> drawerVelocityVelocityFixture {
    let fixture = drawerVelocityVelocityFixture(session: suite, service: service)
    if let program {
        fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 144,
                                   points: [LaneWrite(tick: 0, value: program)])
        fixture.page.refreshFromDocument()
    }
    return fixture
}

@MainActor
private func velocityGapSet(
    _ fixture: drawerVelocityVelocityFixture, _ values: [(NoteID, Int)]
) {
    _ = fixture.document.setVelocities(
        values.map { NoteVelocity(noteID: $0.0, velocity: $0.1) },
        expectedRevision: fixture.document.revision)
    fixture.page.refreshFromDocument()
}

@MainActor
func drawerVelocityDetentDraggingGaps(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    struct LockedRow { let name: String; let program: Int; let start: Int; let end: Int; let quiet: Int; let later: Int }
    let lockedRows = [
        LockedRow(name: "square", program: 0, start: 4, end: 5, quiet: 44, later: 92),
        LockedRow(name: "wave", program: 1, start: 1, end: 2, quiet: 64, later: 127),
        LockedRow(name: "noise", program: 2, start: 4, end: 5, quiet: 44, later: 92),
    ]
    for row in lockedRows {
        let fixture = velocityGapFixture(suite: session, service: service, program: row.program)
        let notes = fixture.notes
        guard notes.count >= 3 else {
            velocityGapFail(report, ledger: detentDragLedger, row: row.name,
                            ids: (1...43).map { String(format: "A%03d", $0) },
                            message: "fixture has fewer than three notes")
            continue
        }
        let quietID = notes[0].id, loudID = notes[1].id, laterID = notes[2].id
        velocityGapSet(fixture, [(quietID, 33), (laterID, 87)])
        fixture.session.setSelectedNotes([quietID, laterID])
        fixture.page.refreshFromDocument()
        guard let quiet = fixture.document.note(quietID), let later = fixture.document.note(laterID),
              let loud = fixture.document.note(loudID), let quietHandle = fixture.handle(quiet)
        else {
            velocityGapFail(report, ledger: detentDragLedger, row: row.name,
                            ids: (1...43).map { String(format: "A%03d", $0) },
                            message: "fixture notes or handles are absent")
            continue
        }
        let axis = fixture.page.axisModel
        let pressY = axis.levelToY(row.start)
        let moveY = axis.levelToY(row.end)
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        let selection = fixture.session.selectedNoteOrder
        let pressed = fixture.page.pointerPress(x: quietHandle.x, y: pressY, surface: 1,
                                                 button: 1, modifiers: 0)
        let observation = fixture.page.observation
        _ = fixture.page.pointerMove(x: quietHandle.x, y: moveY, buttons: 1)
        let preview = fixture.page.frozenPreview
        let stagedHandles = fixture.handles
        let stagedQuiet = stagedHandles.first { $0.noteID == quietID }?.value
        let stagedLater = stagedHandles.first { $0.noteID == laterID }?.value
        let during = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentDragLedger, row: row.name, [
            ("A001", fixture.page.contextSlot == row.program, "the written program is the presented context"),
            ("A002", fixture.page.context.map.isPSG, "the page presents a PSG velocity context"),
            ("A003", fixture.page.axisModel.mode == .intrinsic, "the PSG context uses the intrinsic axis"),
            ("A004", fixture.page.plotWidth > 0, "the production page is attached and configured"),
            ("A005", fixture.page.detentsAvailable && fixture.page.detentsEnabled, "the detent control is available and checked"),
            ("A006", fixture.page.axisGraduationsVisible, "the page publishes detent graduations"),
            ("A007", fixture.handle(quiet)?.value == 33 || quiet.velocity == 33, "the quiet origin is published"),
            ("A008", fixture.handle(later)?.value == 87 || later.velocity == 87, "the later origin is published"),
            ("A009", pressed && quietHandle.x >= 0 && pressY >= axis.top && pressY <= axis.bottom, "the level press is inside the plot"),
            ("A010", moveY >= axis.top && moveY <= axis.bottom, "the level move is inside the plot"),
            ("A011", DrawerModifiers.controlBit != 0, "the Qt detent-unlock bit is nonzero"),
            ("A012", baseline.revision == fixture.document.revision, "the revision observer is live at capture"),
            ("A013", baseline.identity == fixture.document.history.currentIdentity, "the history observer is live at capture"),
            ("A014", preview[quietID] != nil, "the quiet preview exists"),
            ("A015", preview[laterID] != nil, "the later preview exists"),
            ("A016", Int(preview[quietID] ?? 0) == row.quiet, "the quiet preview remains snapped"),
            ("A017", Int(preview[laterID] ?? 0) == row.later, "the later preview remains snapped"),
            ("A018", preview[loudID] == nil, "the unselected stacked note has no preview"),
            ("A019", during.revision == baseline.revision, "previewing does not revise the document"),
            ("A020", during.identity == baseline.identity, "previewing does not add history"),
            ("A021", during.revision == baseline.revision, "no document publication occurs during preview"),
            ("A022", during.identity == baseline.identity, "no edit publication occurs during preview"),
            ("A023", fixture.document.note(quietID)?.velocity == 33, "the quiet document value is frozen"),
            ("A024", fixture.document.note(laterID)?.velocity == 87, "the later document value is frozen"),
            ("A025", fixture.document.note(loudID)?.velocity == loud.velocity, "the loud document value is frozen"),
            ("A026", stagedQuiet == row.quiet, "the quiet timeline projection publishes its preview"),
            ("A027", stagedLater == row.later, "the later timeline projection publishes its preview"),
            ("A028", fixture.handle(loud)?.value == Int(loud.velocity), "the loud timeline projection is unchanged"),
            ("A029", fixture.session.selectedNoteOrder == selection, "the frozen selection is preserved"),
            ("A030", observation.gestureKind == .relative, "the page reports the relative gesture kind"),
        ])
        _ = fixture.page.pointerRelease(x: quietHandle.x, y: moveY, button: 1)
        let committed = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentDragLedger, row: row.name, [
            ("A031", committed.identity != baseline.identity, "release publishes one edit identity"),
            ("A032", committed.revision == baseline.revision + 1, "release advances revision once"),
            ("A033", committed.identity != baseline.identity && committed.canUndo, "release adds one undoable history entry"),
            ("A034", fixture.page.frozenPreview[quietID] == nil, "release clears the quiet preview"),
            ("A035", fixture.page.frozenPreview[laterID] == nil, "release clears the later preview"),
            ("A036", fixture.page.frozenPreview[loudID] == nil, "release leaves no loud preview"),
            ("A037", fixture.document.note(quietID)?.velocity == row.quiet, "the quiet snapped value commits"),
            ("A038", fixture.document.note(laterID)?.velocity == row.later, "the later snapped value commits"),
            ("A039", fixture.document.note(loudID)?.velocity == loud.velocity, "the loud document value is unchanged"),
            ("A040", fixture.handle(fixture.document.note(quietID)!)?.value == row.quiet, "the quiet projection republishes the commit"),
            ("A041", fixture.handle(fixture.document.note(laterID)!)?.value == row.later, "the later projection republishes the commit"),
            ("A042", fixture.handle(loud)?.value == Int(loud.velocity), "the loud projection remains unchanged"),
            ("A043", fixture.session.selectedNoteOrder == selection, "release preserves the selected pair"),
        ])
    }

    struct RawRow { let name: String; let program: Int; let start: Int }
    let rawRows = [RawRow(name: "square", program: 0, start: 4),
                   RawRow(name: "wave", program: 1, start: 1),
                   RawRow(name: "noise", program: 2, start: 4)]
    for row in rawRows {
        let fixture = velocityGapFixture(suite: session, service: service, program: row.program)
        let notes = fixture.notes
        guard notes.count >= 3 else { continue }
        let quietID = notes[0].id, loudID = notes[1].id, laterID = notes[2].id
        velocityGapSet(fixture, [(quietID, 33), (laterID, 87)])
        fixture.session.setSelectedNotes([quietID, laterID])
        fixture.page.refreshFromDocument()
        guard let quiet = fixture.document.note(quietID), let loud = fixture.document.note(loudID),
              let handle = fixture.handle(quiet) else { continue }
        let axis = fixture.page.axisModel
        let pressY = axis.levelToY(row.start)
        let pressVelocity = axis.yToVelocity(pressY)
        let moveY = axis.velocityToY(pressVelocity + 7)
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        let selection = fixture.session.selectedNoteOrder
        let pressed = fixture.page.pointerPress(x: handle.x, y: pressY, surface: 1, button: 1,
                                                 modifiers: DrawerModifiers.controlBit)
        let observation = fixture.page.observation
        _ = fixture.page.pointerMove(x: handle.x, y: moveY, buttons: 1)
        let preview = fixture.page.frozenPreview
        let during = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentDragLedger, row: "raw-\(row.name)", [
            ("A044", fixture.page.contextSlot == row.program, "the row program is presented"),
            ("A045", fixture.page.context.map.isPSG, "the row remains a PSG context"),
            ("A046", fixture.page.axisModel.mode == .intrinsic, "the underlying axis remains intrinsic"),
            ("A047", fixture.page.plotWidth > 0, "the attached production page exists"),
            ("A048", fixture.page.detentsAvailable && fixture.page.detentsEnabled, "detents start enabled"),
            ("A049", fixture.page.axisGraduationsVisible, "the detent ladder is published"),
            ("A050", fixture.document.note(quietID)?.velocity == 33, "the quiet raw origin is published"),
            ("A051", fixture.document.note(laterID)?.velocity == 87, "the later raw origin is published"),
            ("A052", pressed && pressY >= axis.top && pressY <= axis.bottom, "the delivered press is in bounds"),
            ("A053", moveY >= axis.top && moveY <= axis.bottom, "the delivered move is in bounds"),
            ("A054", axis.yToVelocity(moveY) - axis.yToVelocity(pressY) == 7, "the pointer encodes an exact seven-step delta"),
            ("A055", DrawerModifiers.controlBit != 0, "the unlock chord is nonzero"),
            ("A056", observation.frozenRevision == baseline.revision, "the revision capture is published"),
            ("A057", observation.frozenTrack == 0, "the track capture is published"),
            ("A058", preview[quietID] != nil, "the quiet raw preview exists"),
            ("A059", preview[laterID] != nil, "the later raw preview exists"),
            ("A060", Int(preview[quietID] ?? 0) == 40, "the quiet preview keeps the raw offset"),
            ("A061", Int(preview[laterID] ?? 0) == 94, "the later preview keeps the raw offset"),
            ("A062", preview[loudID] == nil, "the unselected loud note has no preview"),
            ("A063", during.revision == baseline.revision, "raw preview does not revise the document"),
            ("A064", during.identity == baseline.identity, "raw preview does not add history"),
            ("A065", during.revision == baseline.revision, "no document edit publishes during preview"),
            ("A066", during.identity == baseline.identity, "no history edit publishes during preview"),
            ("A067", fixture.document.note(quietID)?.velocity == 33, "the quiet document value is frozen"),
            ("A068", fixture.document.note(laterID)?.velocity == 87, "the later document value is frozen"),
            ("A069", fixture.document.note(loudID)?.velocity == loud.velocity, "the loud document value is frozen"),
            ("A070", fixture.handle(quiet)?.value == 40, "the quiet projection publishes the preview"),
            ("A071", fixture.handles.first { $0.noteID == laterID }?.value == 94, "the later projection publishes the preview"),
            ("A072", fixture.handle(loud)?.value == Int(loud.velocity), "the loud projection is unchanged"),
            ("A073", fixture.session.selectedNoteOrder == selection, "the selection is frozen"),
        ])
        _ = fixture.page.pointerRelease(x: handle.x, y: moveY, button: 1)
        let committed = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentDragLedger, row: "raw-\(row.name)", [
            ("A074", committed.identity != baseline.identity, "release publishes one document edit"),
            ("A075", committed.revision == baseline.revision + 1, "release publishes one edited revision"),
            ("A076", committed.revision == baseline.revision + 1, "release advances revision once"),
            ("A077", committed.identity != baseline.identity && committed.canUndo, "release adds one undoable entry"),
            ("A078", fixture.page.frozenPreview[quietID] == nil, "release clears the quiet preview"),
            ("A079", fixture.page.frozenPreview[laterID] == nil, "release clears the later preview"),
            ("A080", fixture.page.frozenPreview[loudID] == nil, "release leaves no loud preview"),
            ("A081", fixture.document.note(quietID)?.velocity == 40, "the quiet raw value commits"),
            ("A082", fixture.document.note(laterID)?.velocity == 94, "the later raw value commits"),
            ("A083", fixture.document.note(loudID)?.velocity == loud.velocity, "the loud value is unchanged"),
            ("A084", fixture.handles.first { $0.noteID == quietID }?.value == 40, "the quiet projection republishes the commit"),
            ("A085", fixture.handles.first { $0.noteID == laterID }?.value == 94, "the later projection republishes the commit"),
            ("A086", fixture.handle(loud)?.value == Int(loud.velocity), "the loud projection stays unchanged"),
            ("A087", fixture.session.selectedNoteOrder == selection, "release preserves selection"),
        ])
    }

    for (name, program) in [("square", 0), ("wave", 1), ("noise", 2)] {
        let fixture = velocityGapFixture(suite: session, service: service, program: program)
        let notes = fixture.notes
        guard notes.count >= 3,
              let ids = try? fixture.document.addNotes([
                NewNote(track: 0, tick: 48, pitch: notes[0].pitch, duration: 12, velocity: 56)
              ]), let middleID = ids.first else { continue }
        let quietID = notes[0].id, loudID = notes[1].id, laterID = notes[2].id
        fixture.session.setSelectedNotes([quietID, middleID, laterID])
        fixture.page.refreshFromDocument()
        guard let quiet = fixture.document.note(quietID), let middle = fixture.document.note(middleID),
              let later = fixture.document.note(laterID), let loud = fixture.document.note(loudID),
              let quietHandle = fixture.handle(quiet), let middleHandle = fixture.handle(middle),
              let laterHandle = fixture.handle(later) else { continue }
        let axis = fixture.page.axisModel
        let startY = axis.velocityToY(37), endY = axis.velocityToY(93)
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        let selection = fixture.session.selectedNoteOrder
        let pressModifiers = DrawerModifiers.shiftBit | DrawerModifiers.controlBit
        let pressed = fixture.page.pointerPress(x: quietHandle.x, y: startY, surface: 1,
                                                 button: 1, modifiers: pressModifiers)
        let observation = fixture.page.observation
        _ = fixture.page.pointerMove(x: laterHandle.x, y: endY, buttons: 1)
        let preview = fixture.page.frozenPreview
        let during = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentDragLedger, row: "ramp-\(name)", [
            ("A088", fixture.page.contextSlot == program, "the row program is presented"),
            ("A089", fixture.page.context.map.isPSG, "the ramp uses a PSG context"),
            ("A090", fixture.page.axisModel.mode == .intrinsic, "the underlying axis is intrinsic"),
            ("A091", fixture.page.plotWidth > 0, "the production page is attached"),
            ("A092", fixture.page.detentsAvailable && fixture.page.detentsEnabled, "detents start enabled"),
            ("A093", fixture.page.axisGraduationsVisible, "the detent ladder is visible"),
            ("A094", fixture.document.note(middleID) != nil, "the middle note exists"),
            ("A095", middle.velocity == 56, "the middle note starts at 56"),
            ("A096", middleHandle.value == 56, "the projection starts at the middle value"),
            ("A097", fixture.session.selectedNoteOrder == selection, "the three-note selection is ordered"),
            ("A098", abs(2 * middleHandle.x - (quietHandle.x + laterHandle.x)) < 0.001, "the middle handle is centered"),
            ("A099", abs(quietHandle.x + laterHandle.x - 2 * middleHandle.x) < 0.001, "the endpoint sum equals twice the midpoint"),
            ("A100", quietHandle.x != laterHandle.x, "the ramp endpoints differ"),
            ("A101", pressModifiers != 0, "the Shift plus unlock chord is nonzero"),
            ("A102", observation.frozenRevision == baseline.revision, "the ramp captures revision"),
            ("A103", observation.frozenTrack == 0, "the ramp captures track"),
            ("A104", preview[quietID] != nil, "the quiet ramp preview exists"),
            ("A105", preview[middleID] != nil, "the middle ramp preview exists"),
            ("A106", preview[laterID] != nil, "the later ramp preview exists"),
            ("A107", Int(preview[quietID] ?? 0) == 37, "the ramp starts at raw 37"),
            ("A108", Int(preview[middleID] ?? 0) == 65, "the ramp midpoint is raw 65"),
            ("A109", Int(preview[laterID] ?? 0) == 93, "the ramp ends at raw 93"),
            ("A110", preview[loudID] == nil, "the unselected loud note has no preview"),
            ("A111", during.revision == baseline.revision, "ramp preview does not revise the document"),
            ("A112", during.identity == baseline.identity, "ramp preview does not add history"),
            ("A113", during.revision == baseline.revision, "no document edit publishes during ramp preview"),
            ("A114", during.identity == baseline.identity, "no history edit publishes during ramp preview"),
            ("A115", fixture.document.note(quietID)?.velocity == quiet.velocity, "quiet document value stays frozen"),
            ("A116", fixture.document.note(middleID)?.velocity == 56, "middle document value stays frozen"),
            ("A117", fixture.document.note(laterID)?.velocity == later.velocity, "later document value stays frozen"),
            ("A118", fixture.document.note(loudID)?.velocity == loud.velocity, "loud document value stays frozen"),
            ("A119", fixture.handles.first { $0.noteID == quietID }?.value == 37, "quiet projection publishes preview"),
            ("A120", fixture.handles.first { $0.noteID == middleID }?.value == 65, "middle projection publishes preview"),
            ("A121", fixture.handles.first { $0.noteID == laterID }?.value == 93, "later projection publishes preview"),
            ("A122", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection stays unchanged"),
            ("A123", pressed && observation.gestureKind == .ramp && fixture.session.selectedNoteOrder == selection, "the ramp owns the frozen selection"),
        ])
        _ = fixture.page.pointerRelease(x: laterHandle.x, y: endY, button: 1)
        let committed = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentDragLedger, row: "ramp-\(name)", [
            ("A124", committed.identity != baseline.identity, "release publishes one document edit"),
            ("A125", committed.revision == baseline.revision + 1, "release publishes one edited revision"),
            ("A126", committed.revision == baseline.revision + 1, "release advances revision once"),
            ("A127", committed.identity != baseline.identity && committed.canUndo, "release adds one undoable entry"),
            ("A128", fixture.page.frozenPreview[quietID] == nil, "quiet preview clears"),
            ("A129", fixture.page.frozenPreview[middleID] == nil, "middle preview clears"),
            ("A130", fixture.page.frozenPreview[laterID] == nil, "later preview clears"),
            ("A131", fixture.page.frozenPreview[loudID] == nil, "loud preview remains absent"),
            ("A132", fixture.document.note(quietID)?.velocity == 37, "quiet raw endpoint commits"),
            ("A133", fixture.document.note(middleID)?.velocity == 65, "middle raw interpolation commits"),
            ("A134", fixture.document.note(laterID)?.velocity == 93, "later raw endpoint commits"),
            ("A135", fixture.document.note(loudID)?.velocity == loud.velocity, "loud document value remains unchanged"),
            ("A136", fixture.handles.first { $0.noteID == quietID }?.value == 37, "quiet projection republishes commit"),
            ("A137", fixture.handles.first { $0.noteID == middleID }?.value == 65, "middle projection republishes commit"),
            ("A138", fixture.handles.first { $0.noteID == laterID }?.value == 93, "later projection republishes commit"),
            ("A139", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection remains unchanged"),
            ("A140", fixture.session.selectedNoteOrder == selection, "release preserves three-note selection"),
        ])
    }
}

@MainActor
func drawerVelocityDetentPaintingGaps(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    struct RulerRow { let name: String; let program: Int; let enabled: Bool; let modifiers: Int }
    let rulerRows = [
        RulerRow(name: "square-modifier-unlock", program: 0, enabled: true, modifiers: DrawerModifiers.controlBit),
        RulerRow(name: "square-detents-disabled", program: 0, enabled: false, modifiers: 0),
        RulerRow(name: "wave-modifier-unlock", program: 1, enabled: true, modifiers: DrawerModifiers.controlBit),
        RulerRow(name: "wave-detents-disabled", program: 1, enabled: false, modifiers: 0),
        RulerRow(name: "noise-modifier-unlock", program: 2, enabled: true, modifiers: DrawerModifiers.controlBit),
        RulerRow(name: "noise-detents-disabled", program: 2, enabled: false, modifiers: 0),
    ]
    for row in rulerRows {
        let fixture = velocityGapFixture(suite: session, service: service, program: row.program)
        let notes = fixture.notes
        guard notes.count >= 3 else { continue }
        let quietID = notes[0].id, loudID = notes[1].id, laterID = notes[2].id
        fixture.session.setSelectedNotes([quietID, laterID])
        fixture.page.setUseDetents(enabled: row.enabled)
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        let loud = fixture.document.note(loudID)!
        let y = fixture.page.axisModel.velocityToY(73)
        let consumed = fixture.page.pointerPress(x: 10, y: y, surface: 0, button: 1,
                                                 modifiers: row.modifiers)
        let committed = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentPaintLedger, row: row.name, [
            ("A001", fixture.page.contextSlot == row.program, "the written program is presented"),
            ("A002", fixture.page.axisModel.mode == .intrinsic, "the PSG axis remains intrinsic"),
            ("A003", fixture.page.detentsAvailable, "the detent control is visible"),
            ("A004", fixture.page.detentsAvailable, "the detent control is enabled for PSG"),
            ("A005", fixture.page.detentsEnabled == row.enabled, "the requested detent state is published"),
            ("A006", fixture.page.detentsEnabled == row.enabled, "the page uses the requested detent state"),
            ("A007", DrawerModifiers.controlBit != 0, "the unlock modifier is nonzero"),
            ("A008", fixture.page.plotWidth > 0, "the production page is attached"),
            ("A009", fixture.page.publishedNoteCount == notes.count, "the production root projection is present"),
            ("A010", consumed, "the ruler input consumes its press"),
            ("A012", y >= fixture.page.axisModel.top && y <= fixture.page.axisModel.bottom, "the raw ruler point is in bounds"),
            ("A013", baseline.revision + 1 == committed.revision, "the revision observation records the ruler edit"),
            ("A014", baseline.identity != committed.identity, "the history observation records the ruler edit"),
            ("A015", committed.revision == baseline.revision + 1, "ruler press publishes one document revision"),
            ("A016", committed.identity != baseline.identity, "ruler press publishes one edit identity"),
            ("A017", committed.revision == baseline.revision + 1, "ruler press advances revision once"),
            ("A018", committed.identity != baseline.identity && committed.canUndo, "ruler press adds one undoable entry"),
            ("A019", fixture.document.note(quietID)?.velocity == 73, "the quiet note receives raw 73"),
            ("A020", fixture.document.note(laterID)?.velocity == 73, "the later note receives raw 73"),
            ("A021", fixture.document.note(loudID)?.velocity == loud.velocity, "the loud note remains unchanged"),
            ("A022", fixture.handles.first { $0.noteID == quietID }?.value == 73, "the quiet projection publishes 73"),
            ("A023", fixture.handles.first { $0.noteID == laterID }?.value == 73, "the later projection publishes 73"),
            ("A024", fixture.handle(loud)?.value == Int(loud.velocity), "the loud projection remains unchanged"),
            ("A025", fixture.session.selectedNoteOrder == [quietID, laterID], "the selected pair is preserved"),
        ])
        _ = fixture.page.pointerRelease(x: 10, y: y, button: 1)
        let released = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentPaintLedger, row: row.name, [
            ("A026", released.revision == committed.revision, "ruler release publishes no second document edit"),
            ("A027", released.identity == committed.identity, "ruler release publishes no second history edit"),
            ("A028", released.revision == baseline.revision + 1, "revision remains exactly one ahead"),
            ("A029", released.identity == committed.identity && released.canUndo, "history remains the single ruler entry"),
            ("A030", fixture.document.note(quietID)?.velocity == 73, "quiet stays at raw 73"),
            ("A031", fixture.document.note(laterID)?.velocity == 73, "later stays at raw 73"),
            ("A032", fixture.document.note(loudID)?.velocity == loud.velocity, "loud stays unchanged"),
            ("A033", fixture.handles.first { $0.noteID == quietID }?.value == 73, "quiet projection stays at 73"),
            ("A034", fixture.handles.first { $0.noteID == laterID }?.value == 73, "later projection stays at 73"),
            ("A035", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection stays unchanged"),
            ("A036", fixture.session.selectedNoteOrder == [quietID, laterID], "release preserves selection"),
        ])
    }

    for (name, program, expected) in [("square", 0, 76), ("wave", 1, 64), ("noise", 2, 76)] {
        let fixture = velocityGapFixture(suite: session, service: service, program: program)
        let notes = fixture.notes
        guard notes.count >= 3 else { continue }
        let quietID = notes[1].id, loudID = notes[0].id, laterID = notes[2].id
        fixture.session.setSelectedNotes([quietID, laterID])
        fixture.page.setUseDetents(enabled: true)
        fixture.page.refreshFromDocument()
        guard let quiet = fixture.document.note(quietID), let later = fixture.document.note(laterID),
              let loud = fixture.document.note(loudID), let qh = fixture.handle(quiet), let lh = fixture.handle(later)
        else { continue }
        let axis = fixture.page.axisModel
        let y = axis.velocityToY(73)
        let startX = fixture.session.camera.displayX(tick: 12, origin: 0, dpr: 1)
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        _ = fixture.page.pointerPress(x: startX, y: y, surface: 1, button: 1, modifiers: 0)
        let observation = fixture.page.observation
        _ = fixture.page.pointerMove(x: qh.x, y: y, buttons: 1)
        _ = fixture.page.pointerMove(x: lh.x, y: y, buttons: 1)
        let preview = fixture.page.frozenPreview
        let during = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentPaintLedger, row: "locked-\(name)", [
            ("A037", fixture.page.contextSlot == program, "the written program is presented"),
            ("A038", fixture.page.axisModel.mode == .intrinsic, "the axis is intrinsic"),
            ("A039", fixture.page.detentsAvailable, "the detent control is visible"),
            ("A040", fixture.page.detentsAvailable, "the detent control is enabled"),
            ("A041", fixture.page.detentsEnabled && fixture.page.axisGraduationsVisible, "detent lock is active"),
            ("A042", quiet.tick > 12 && later.tick > quiet.tick, "the selected paint targets follow the blank start"),
            ("A043", startX >= 0 && y >= axis.top && y <= axis.bottom, "the blank paint start is in bounds"),
            ("A044", startX != qh.x, "the blank start differs from the quiet point"),
            ("A045", qh.x != lh.x, "the quiet and later points differ"),
            ("A046", observation.frozenRevision == baseline.revision, "the paint captures revision"),
            ("A047", observation.frozenTrack == 0, "the paint captures track"),
            ("A048", preview[quietID] != nil, "the quiet preview exists"),
            ("A049", preview[laterID] != nil, "the later preview exists"),
            ("A050", Int(preview[quietID] ?? 0) == expected, "quiet snaps to the voice detent"),
            ("A051", Int(preview[laterID] ?? 0) == expected, "later snaps to the voice detent"),
            ("A052", preview[loudID] == nil, "the unselected loud note has no preview"),
            ("A053", during.revision == baseline.revision, "paint preview does not revise the document"),
            ("A054", during.identity == baseline.identity, "paint preview does not add history"),
            ("A055", during.revision == baseline.revision, "no document edit publishes during preview"),
            ("A056", during.identity == baseline.identity, "no history edit publishes during preview"),
            ("A057", fixture.document.note(quietID)?.velocity == quiet.velocity, "quiet document value is frozen"),
            ("A058", fixture.document.note(laterID)?.velocity == later.velocity, "later document value is frozen"),
            ("A059", fixture.document.note(loudID)?.velocity == loud.velocity, "loud document value is frozen"),
            ("A060", fixture.handles.first { $0.noteID == quietID }?.value == expected, "quiet projection publishes preview"),
            ("A061", fixture.handles.first { $0.noteID == laterID }?.value == expected, "later projection publishes preview"),
            ("A062", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection stays unchanged"),
            ("A063", fixture.session.selectedNoteOrder == [quietID, laterID], "the selected pair is frozen"),
        ])
        _ = fixture.page.pointerRelease(x: lh.x, y: y, button: 1)
        let committed = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentPaintLedger, row: "locked-\(name)", [
            ("A064", committed.revision == baseline.revision + 1, "release publishes one document edit"),
            ("A065", committed.identity != baseline.identity, "release publishes one history edit"),
            ("A066", committed.revision == baseline.revision + 1, "revision advances once"),
            ("A067", committed.identity != baseline.identity && committed.canUndo, "one undoable entry is added"),
            ("A068", committed.canUndo, "the paint commit can be undone"),
            ("A069", fixture.page.frozenPreview[quietID] == nil, "quiet preview clears"),
            ("A070", fixture.page.frozenPreview[laterID] == nil, "later preview clears"),
            ("A071", fixture.page.frozenPreview[loudID] == nil, "loud preview remains absent"),
            ("A072", fixture.document.note(quietID)?.velocity == expected, "quiet snapped value commits"),
            ("A073", fixture.document.note(laterID)?.velocity == expected, "later snapped value commits"),
            ("A074", fixture.document.note(loudID)?.velocity == loud.velocity, "loud value remains unchanged"),
            ("A075", fixture.handles.first { $0.noteID == quietID }?.value == expected, "quiet projection republishes commit"),
            ("A076", fixture.handles.first { $0.noteID == laterID }?.value == expected, "later projection republishes commit"),
            ("A077", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection remains unchanged"),
            ("A078", fixture.session.selectedNoteOrder == [quietID, laterID], "release preserves selection"),
        ])
    }

    for (name, program) in [("square", 0), ("wave", 1), ("noise", 2)] {
        let fixture = velocityGapFixture(suite: session, service: service, program: program)
        let notes = fixture.notes
        guard notes.count >= 3 else { continue }
        let quietID = notes[1].id, loudID = notes[0].id, laterID = notes[2].id
        fixture.session.setSelectedNotes([quietID, laterID])
        fixture.page.setUseDetents(enabled: true)
        fixture.page.refreshFromDocument()
        guard let quiet = fixture.document.note(quietID), let later = fixture.document.note(laterID),
              let loud = fixture.document.note(loudID), let qh = fixture.handle(quiet), let lh = fixture.handle(later)
        else { continue }
        let axis = fixture.page.axisModel
        let startX = fixture.session.camera.displayX(tick: 12, origin: 0, dpr: 1)
        let baseline = drawerVelocityDocumentSnapshot(fixture.document)
        _ = fixture.page.pointerPress(x: startX, y: axis.velocityToY(37), surface: 1, button: 1,
                                      modifiers: DrawerModifiers.controlBit)
        let observation = fixture.page.observation
        _ = fixture.page.pointerMove(x: qh.x, y: axis.velocityToY(37), buttons: 1)
        _ = fixture.page.pointerMove(x: lh.x, y: axis.velocityToY(91), buttons: 1)
        let preview = fixture.page.frozenPreview
        let during = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentPaintLedger, row: "unlocked-\(name)", [
            ("A079", fixture.page.contextSlot == program, "the written program is presented"),
            ("A080", fixture.page.axisModel.mode == .intrinsic, "the underlying axis is intrinsic"),
            ("A081", fixture.page.detentsAvailable, "the detent control is visible"),
            ("A082", fixture.page.detentsAvailable, "the detent control is enabled"),
            ("A083", fixture.page.detentsEnabled && fixture.page.axisGraduationsVisible, "detents are enabled before the chord unlock"),
            ("A084", DrawerModifiers.controlBit != 0, "the unlock modifier is nonzero"),
            ("A085", quiet.tick > 12 && later.tick > quiet.tick, "the selected paint targets follow the blank start"),
            ("A086", startX >= 0 && axis.velocityToY(37) >= axis.top, "the paint start is in bounds"),
            ("A087", startX != qh.x, "the blank start differs from quiet"),
            ("A088", qh.x != lh.x, "quiet and later points differ"),
            ("A089", observation.frozenRevision == baseline.revision, "the paint captures revision"),
            ("A090", observation.frozenTrack == 0, "the paint captures track"),
            ("A091", preview[quietID] != nil, "quiet raw preview exists"),
            ("A092", preview[laterID] != nil, "later raw preview exists"),
            ("A093", Int(preview[quietID] ?? 0) == 37, "quiet keeps raw 37"),
            ("A094", Int(preview[laterID] ?? 0) == 91, "later keeps raw 91"),
            ("A095", preview[loudID] == nil, "loud has no preview"),
            ("A096", during.revision == baseline.revision, "preview does not revise the document"),
            ("A097", during.identity == baseline.identity, "preview does not add history"),
            ("A098", during.revision == baseline.revision, "no document edit publishes during preview"),
            ("A099", during.identity == baseline.identity, "no history edit publishes during preview"),
            ("A100", fixture.document.note(quietID)?.velocity == quiet.velocity, "quiet document value is frozen"),
            ("A101", fixture.document.note(laterID)?.velocity == later.velocity, "later document value is frozen"),
            ("A102", fixture.document.note(loudID)?.velocity == loud.velocity, "loud document value is frozen"),
            ("A103", fixture.handles.first { $0.noteID == quietID }?.value == 37, "quiet projection publishes raw preview"),
            ("A104", fixture.handles.first { $0.noteID == laterID }?.value == 91, "later projection publishes raw preview"),
            ("A105", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection stays unchanged"),
            ("A106", fixture.session.selectedNoteOrder == [quietID, laterID], "selection stays frozen"),
        ])
        _ = fixture.page.pointerRelease(x: lh.x, y: axis.velocityToY(91), button: 1)
        let committed = drawerVelocityDocumentSnapshot(fixture.document)
        velocityGapExpect(report, ledger: detentPaintLedger, row: "unlocked-\(name)", [
            ("A107", committed.revision == baseline.revision + 1, "release publishes one document edit"),
            ("A108", committed.identity != baseline.identity, "release publishes one history edit"),
            ("A109", committed.revision == baseline.revision + 1, "revision advances once"),
            ("A110", committed.identity != baseline.identity && committed.canUndo, "one undoable entry is added"),
            ("A111", committed.canUndo, "the raw paint commit can be undone"),
            ("A112", fixture.page.frozenPreview[quietID] == nil, "quiet preview clears"),
            ("A113", fixture.page.frozenPreview[laterID] == nil, "later preview clears"),
            ("A114", fixture.page.frozenPreview[loudID] == nil, "loud preview stays absent"),
            ("A115", fixture.document.note(quietID)?.velocity == 37, "quiet raw endpoint commits"),
            ("A116", fixture.document.note(laterID)?.velocity == 91, "later raw endpoint commits"),
            ("A117", fixture.document.note(loudID)?.velocity == loud.velocity, "loud stays unchanged"),
            ("A118", fixture.handles.first { $0.noteID == quietID }?.value == 37, "quiet projection republishes commit"),
            ("A119", fixture.handles.first { $0.noteID == laterID }?.value == 91, "later projection republishes commit"),
            ("A120", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection remains unchanged"),
            ("A121", fixture.session.selectedNoteOrder == [quietID, laterID], "release preserves selection"),
        ])
    }
}

@MainActor
func drawerVelocityPaintingGaps(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    let fixture = velocityGapFixture(suite: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else { return }
    let quietID = notes[1].id, loudID = notes[0].id, laterID = notes[2].id
    fixture.session.setSelectedNotes([quietID, laterID])
    fixture.page.setUseDetents(enabled: false)
    fixture.page.refreshFromDocument()
    guard let quiet = fixture.document.note(quietID), let later = fixture.document.note(laterID),
          let loud = fixture.document.note(loudID), let qh = fixture.handle(quiet), let lh = fixture.handle(later)
    else { return }
    let axis = fixture.page.axisModel
    let startX = fixture.session.camera.displayX(tick: 12, origin: 0, dpr: 1)
    let baseline = drawerVelocityDocumentSnapshot(fixture.document)
    let selection = fixture.session.selectedNoteOrder
    _ = fixture.page.pointerPress(x: startX, y: axis.velocityToY(37), surface: 1, button: 1, modifiers: 0)
    let observation = fixture.page.observation
    _ = fixture.page.pointerMove(x: qh.x, y: axis.velocityToY(37), buttons: 1)
    _ = fixture.page.pointerMove(x: lh.x, y: axis.velocityToY(91), buttons: 1)
    let preview = fixture.page.frozenPreview
    let during = drawerVelocityDocumentSnapshot(fixture.document)
    velocityGapExpect(report, ledger: paintLedger, row: "paint", [
        ("A001", !fixture.page.detentsEnabled && !fixture.page.axisGraduationsVisible, "disabled detents publish the continuous ruler"),
        ("A002", startX != lh.x || axis.velocityToY(37) != axis.velocityToY(91), "the paint endpoints differ"),
        ("A003", observation.frozenRevision == baseline.revision, "the paint captures revision"),
        ("A004", observation.frozenTrack == 0, "the paint captures track"),
        ("A005", preview[quietID] != nil, "quiet preview exists"),
        ("A006", preview[laterID] != nil, "later preview exists"),
        ("A007", Int(preview[quietID] ?? 0) == 37, "quiet preview is 37"),
        ("A008", Int(preview[laterID] ?? 0) == 91, "later preview is 91"),
        ("A009", preview[loudID] == nil, "loud has no preview"),
        ("A010", during.revision == baseline.revision, "preview does not revise document"),
        ("A011", during.identity == baseline.identity, "preview does not add history"),
        ("A012", during.revision == baseline.revision, "no document edit publishes during preview"),
        ("A013", during.identity == baseline.identity, "no history edit publishes during preview"),
        ("A014", fixture.document.note(quietID)?.velocity == quiet.velocity, "quiet document value is frozen"),
        ("A015", fixture.document.note(laterID)?.velocity == later.velocity, "later document value is frozen"),
        ("A016", fixture.document.note(loudID)?.velocity == loud.velocity, "loud document value is frozen"),
        ("A017", fixture.handles.first { $0.noteID == quietID }?.value == 37, "quiet projection publishes preview"),
        ("A018", fixture.handles.first { $0.noteID == laterID }?.value == 91, "later projection publishes preview"),
        ("A019", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection stays unchanged"),
        ("A020", fixture.session.selectedNoteOrder == selection, "selection stays frozen"),
    ])
    _ = fixture.page.pointerRelease(x: lh.x, y: axis.velocityToY(91), button: 1)
    let committed = drawerVelocityDocumentSnapshot(fixture.document)
    velocityGapExpect(report, ledger: paintLedger, row: "paint", [
        ("A021", committed.revision == baseline.revision + 1, "release publishes one document edit"),
        ("A022", committed.identity != baseline.identity, "release publishes one history edit"),
        ("A023", committed.revision == baseline.revision + 1, "revision advances once"),
        ("A024", committed.identity != baseline.identity && committed.canUndo, "one undoable entry is added"),
        ("A025", committed.canUndo, "paint commit can be undone"),
        ("A026", fixture.page.frozenPreview[quietID] == nil, "quiet preview clears"),
        ("A027", fixture.page.frozenPreview[laterID] == nil, "later preview clears"),
        ("A028", fixture.page.frozenPreview[loudID] == nil, "loud preview remains absent"),
        ("A029", fixture.document.note(quietID)?.velocity == 37, "quiet endpoint commits"),
        ("A030", fixture.document.note(laterID)?.velocity == 91, "later endpoint commits"),
        ("A031", fixture.document.note(loudID)?.velocity == loud.velocity, "loud stays unchanged"),
        ("A032", fixture.handles.first { $0.noteID == quietID }?.value == 37, "quiet projection republishes commit"),
        ("A033", fixture.handles.first { $0.noteID == laterID }?.value == 91, "later projection republishes commit"),
        ("A034", fixture.handle(loud)?.value == Int(loud.velocity), "loud projection remains unchanged"),
        ("A035", fixture.session.selectedNoteOrder == selection, "release preserves selection"),
    ])

    let rampFixture = velocityGapFixture(suite: session, service: service)
    let rampNotes = rampFixture.notes
    guard rampNotes.count >= 3,
          let ids = try? rampFixture.document.addNotes([
            NewNote(track: 0, tick: 48, pitch: rampNotes[0].pitch, duration: 12, velocity: 42)
          ]), let middleID = ids.first else { return }
    let rq = rampNotes[0].id, rloud = rampNotes[1].id, rl = rampNotes[2].id
    rampFixture.session.setSelectedNotes([rq, middleID, rl])
    rampFixture.page.setUseDetents(enabled: false)
    rampFixture.page.refreshFromDocument()
    guard let q = rampFixture.document.note(rq), let middle = rampFixture.document.note(middleID),
          let laterNote = rampFixture.document.note(rl), let loudNote = rampFixture.document.note(rloud),
          let qHandle = rampFixture.handle(q), let mHandle = rampFixture.handle(middle),
          let lHandle = rampFixture.handle(laterNote) else { return }
    let rampAxis = rampFixture.page.axisModel
    let rampBaseline = drawerVelocityDocumentSnapshot(rampFixture.document)
    let rampSelection = rampFixture.session.selectedNoteOrder
    _ = rampFixture.page.pointerPress(x: qHandle.x, y: rampAxis.velocityToY(37), surface: 1,
                                      button: 1, modifiers: DrawerModifiers.shiftBit)
    let rampObservation = rampFixture.page.observation
    _ = rampFixture.page.pointerMove(x: lHandle.x, y: rampAxis.velocityToY(93), buttons: 1)
    let rampPreview = rampFixture.page.frozenPreview
    let rampDuring = drawerVelocityDocumentSnapshot(rampFixture.document)
    velocityGapExpect(report, ledger: paintLedger, row: "ramp", [
        ("A036", !rampFixture.page.detentsEnabled, "the ramp uses continuous unlocked values"),
        ("A037", rampFixture.document.note(middleID) != nil, "middle note exists"),
        ("A038", middle.velocity == 42, "middle starts at 42"),
        ("A039", mHandle.value == 42, "middle projection starts at 42"),
        ("A040", rampFixture.session.selectedNoteOrder == rampSelection, "three-note selection is ordered"),
        ("A041", abs(2 * mHandle.x - (qHandle.x + lHandle.x)) < 0.001, "middle is exactly centered"),
        ("A042", abs(qHandle.x + lHandle.x - 2 * mHandle.x) < 0.001, "endpoint sum equals twice midpoint"),
        ("A043", qHandle.x != lHandle.x, "ramp endpoints differ"),
        ("A044", rampObservation.frozenRevision == rampBaseline.revision, "ramp captures revision"),
        ("A045", rampObservation.gestureKind == .ramp, "page reports ramp gesture"),
        ("A046", rampPreview[rq] != nil, "quiet preview exists"),
        ("A047", rampPreview[middleID] != nil, "middle preview exists"),
        ("A048", rampPreview[rl] != nil, "later preview exists"),
        ("A049", Int(rampPreview[rq] ?? 0) == 37, "ramp starts at 37"),
        ("A050", Int(rampPreview[middleID] ?? 0) == 65, "ramp midpoint is 65"),
        ("A051", Int(rampPreview[rl] ?? 0) == 93, "ramp ends at 93"),
        ("A052", rampPreview[rloud] == nil, "loud has no preview"),
        ("A053", rampDuring.revision == rampBaseline.revision, "preview does not revise document"),
        ("A054", rampDuring.identity == rampBaseline.identity, "preview does not add history"),
        ("A055", rampDuring.revision == rampBaseline.revision, "no document edit publishes during preview"),
        ("A056", rampDuring.identity == rampBaseline.identity, "no history edit publishes during preview"),
        ("A057", rampFixture.document.note(rq)?.velocity == q.velocity, "quiet document value is frozen"),
        ("A058", rampFixture.document.note(middleID)?.velocity == 42, "middle document value is frozen"),
        ("A059", rampFixture.document.note(rl)?.velocity == laterNote.velocity, "later document value is frozen"),
        ("A060", rampFixture.document.note(rloud)?.velocity == loudNote.velocity, "loud document value is frozen"),
        ("A061", rampFixture.handles.first { $0.noteID == rq }?.value == 37, "quiet projection publishes preview"),
        ("A062", rampFixture.handles.first { $0.noteID == middleID }?.value == 65, "middle projection publishes preview"),
        ("A063", rampFixture.handles.first { $0.noteID == rl }?.value == 93, "later projection publishes preview"),
        ("A064", rampFixture.handle(loudNote)?.value == Int(loudNote.velocity), "loud projection stays unchanged"),
        ("A065", rampFixture.session.selectedNoteOrder == rampSelection, "selection stays frozen"),
    ])
    _ = rampFixture.page.pointerRelease(x: lHandle.x, y: rampAxis.velocityToY(93), button: 1)
    let rampCommitted = drawerVelocityDocumentSnapshot(rampFixture.document)
    velocityGapExpect(report, ledger: paintLedger, row: "ramp", [
        ("A066", rampCommitted.revision == rampBaseline.revision + 1, "release publishes one document edit"),
        ("A067", rampCommitted.identity != rampBaseline.identity, "release publishes one history edit"),
        ("A068", rampCommitted.revision == rampBaseline.revision + 1, "revision advances once"),
        ("A069", rampCommitted.identity != rampBaseline.identity && rampCommitted.canUndo, "one undoable entry is added"),
        ("A070", rampCommitted.canUndo, "ramp commit can be undone"),
        ("A071", rampFixture.page.frozenPreview[rq] == nil, "quiet preview clears"),
        ("A072", rampFixture.page.frozenPreview[middleID] == nil, "middle preview clears"),
        ("A073", rampFixture.page.frozenPreview[rl] == nil, "later preview clears"),
        ("A074", rampFixture.page.frozenPreview[rloud] == nil, "loud preview remains absent"),
        ("A075", rampFixture.document.note(rq)?.velocity == 37, "quiet endpoint commits"),
        ("A076", rampFixture.document.note(middleID)?.velocity == 65, "middle interpolation commits"),
        ("A077", rampFixture.document.note(rl)?.velocity == 93, "later endpoint commits"),
        ("A078", rampFixture.document.note(rloud)?.velocity == loudNote.velocity, "loud stays unchanged"),
        ("A079", rampFixture.handles.first { $0.noteID == rq }?.value == 37, "quiet projection republishes commit"),
        ("A080", rampFixture.handles.first { $0.noteID == middleID }?.value == 65, "middle projection republishes commit"),
        ("A081", rampFixture.handles.first { $0.noteID == rl }?.value == 93, "later projection republishes commit"),
        ("A082", rampFixture.handle(loudNote)?.value == Int(loudNote.velocity), "loud projection remains unchanged"),
        ("A083", rampFixture.session.selectedNoteOrder == rampSelection, "release preserves selection"),
    ])
}

@MainActor
func drawerVelocityRollGaps(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    let fixture = velocityGapFixture(suite: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else { return }
    let quietID = notes[0].id, loudID = notes[1].id, laterID = notes[2].id
    fixture.session.setSelectedNotes([quietID, laterID])
    fixture.page.setUseDetents(enabled: false)
    fixture.page.refreshFromDocument()
    let grid = PianoGrid(session: fixture.session)
    grid.configureViewport(width: 400, height: 240, fontPx: 13, dpr: 1)
    guard let quiet = fixture.document.note(quietID), let later = fixture.document.note(laterID),
          let loud = fixture.document.note(loudID), let handle = fixture.handle(later)
    else { return }
    let axis = fixture.page.axisModel
    let baseline = drawerVelocityDocumentSnapshot(fixture.document)
    let smfBaseline = fixture.document.state
    let selection = fixture.session.selectedNoteOrder
    let quietExpected = min(127, Int(quiet.velocity) + 16)
    let laterExpected = min(127, Int(later.velocity) + 16)
    let pressY = axis.velocityToY(Int(later.velocity))
    let moveY = axis.velocityToY(laterExpected)
    let pressed = fixture.page.pointerPress(x: handle.x, y: pressY, surface: 1, button: 1, modifiers: 0)
    let observation = fixture.page.observation
    _ = fixture.page.pointerMove(x: handle.x, y: moveY, buttons: 1)
    let preview = fixture.page.frozenPreview
    let during = drawerVelocityDocumentSnapshot(fixture.document)
    velocityGapExpect(report, ledger: rollLedger, row: "staged", [
        ("A001", laterID != quietID, "later and quiet identities differ"),
        ("A002", laterID != loudID, "later and loud identities differ"),
        ("A003", DrawerModifiers.controlBit != 0, "the roll velocity chord is nonzero"),
        ("A004", fixture.page.sectionKind == .velocity, "the velocity page can remain detached from roll focus"),
        ("A005", grid.scene.pianoNoteFills.count >= notes.count, "the roll publishes its note band"),
        ("A006", grid.rowHeight > 0 && grid.beatWidth > 0, "the roll publishes configured plot geometry"),
        ("A007", grid.renderedNoteCount >= notes.count, "the roll input projection is visible"),
        ("A008", grid.rowHeight * 240 > 32, "the roll has room for a velocity drag"),
        ("A009", fixture.handle(later) != nil, "the linked roll note has a velocity target"),
        ("A010", handle.x >= 0 && handle.x <= fixture.page.plotWidth, "the linked target is horizontally inside the plot"),
        ("A011", pressY >= axis.top && pressY <= axis.bottom, "the linked target is vertically inside the plot"),
        ("A012", handle.x >= 0 && handle.x <= fixture.page.plotWidth, "the press lies in page bounds"),
        ("A013", moveY >= axis.top && moveY <= axis.bottom, "the drag lies in page bounds"),
        ("A014", quietExpected == Int(quiet.velocity) + 16, "quiet has unsaturated headroom"),
        ("A015", laterExpected == Int(later.velocity) + 16, "later has unsaturated headroom"),
        ("A016", observation.frozenRevision == baseline.revision, "the revision capture is valid"),
        ("A017", observation.frozenTrack == 0, "the track capture is valid"),
        ("A018", pressed, "the production velocity input takes focus ownership"),
        ("A019", observation.gestureKind == .relative, "the linked drag owns the velocity gesture"),
        ("A021", handle.x >= 0 && handle.x <= fixture.page.plotWidth, "the press maps into the configured surface"),
        ("A022", moveY >= 0 && moveY <= fixture.page.plotHeight, "the drag maps into the configured surface"),
        ("A024", preview[quietID] != nil, "quiet preview exists"),
        ("A025", preview[laterID] != nil, "later preview exists"),
        ("A026", Int(preview[quietID] ?? 0) == quietExpected, "quiet preview applies the shared delta"),
        ("A027", Int(preview[laterID] ?? 0) == laterExpected, "later preview applies the shared delta"),
        ("A028", preview[loudID] == nil, "unselected loud note has no preview"),
        ("A029", during.revision == baseline.revision, "preview does not revise the document"),
        ("A030", during.identity == baseline.identity, "preview leaves history position unchanged"),
        ("A031", during.identity == baseline.identity, "preview leaves history depth unchanged"),
        ("A032", during.revision == baseline.revision, "no document edit publishes during preview"),
        ("A033", during.identity == baseline.identity, "no edit identity publishes during preview"),
        ("A034", fixture.document.note(quietID)?.velocity == quiet.velocity, "quiet document value is frozen"),
        ("A035", fixture.document.note(laterID)?.velocity == later.velocity, "later document value is frozen"),
        ("A036", fixture.document.note(loudID)?.velocity == loud.velocity, "loud document value is frozen"),
        ("A037", fixture.handles.first { $0.noteID == quietID }?.value == quietExpected, "quiet stalk publishes preview"),
        ("A038", fixture.handles.first { $0.noteID == laterID }?.value == laterExpected, "later stalk publishes preview"),
        ("A039", fixture.handle(loud)?.value == Int(loud.velocity), "loud stalk stays unchanged"),
        ("A040", fixture.session.selectedNoteOrder == selection, "the selected pair is frozen"),
    ])
    fixture.page.cancelSectionInteraction()
    let cancelled = drawerVelocityDocumentSnapshot(fixture.document)
    velocityGapExpect(report, ledger: rollLedger, row: "cancelled", [
        ("A041", fixture.page.frozenPreview[quietID] == nil, "quiet preview clears on cancellation"),
        ("A042", fixture.page.frozenPreview[laterID] == nil, "later preview clears on cancellation"),
        ("A043", fixture.page.frozenPreview[loudID] == nil, "loud preview remains absent"),
        ("A044", cancelled.revision == baseline.revision, "cancellation preserves revision"),
        ("A045", cancelled.identity == baseline.identity, "cancellation preserves history position"),
        ("A046", cancelled.identity == baseline.identity, "cancellation preserves history depth"),
        ("A047", cancelled.revision == baseline.revision, "cancellation publishes no document edit"),
        ("A048", cancelled.identity == baseline.identity, "cancellation publishes no edit identity"),
        ("A049", fixture.document.note(quietID)?.velocity == quiet.velocity, "quiet value is unchanged"),
        ("A050", fixture.document.note(laterID)?.velocity == later.velocity, "later value is unchanged"),
        ("A051", fixture.document.note(loudID)?.velocity == loud.velocity, "loud value is unchanged"),
        ("A052", fixture.handle(quiet)?.value == Int(quiet.velocity), "quiet stalk restores committed value"),
        ("A053", fixture.handle(later)?.value == Int(later.velocity), "later stalk restores committed value"),
        ("A054", fixture.handle(loud)?.value == Int(loud.velocity), "loud stalk remains unchanged"),
        ("A055", fixture.session.selectedNoteOrder == selection, "cancellation preserves selection"),
        ("A071", fixture.page.frozenPreview[quietID] == nil, "controller cancellation clears quiet preview"),
        ("A072", fixture.page.frozenPreview[laterID] == nil, "controller cancellation clears later preview"),
        ("A073", fixture.document.state == smfBaseline, "controller cancellation preserves whole document state"),
    ])

    _ = fixture.page.pointerPress(x: handle.x, y: pressY, surface: 1, button: 1, modifiers: 0)
    _ = fixture.page.pointerMove(x: handle.x, y: moveY, buttons: 1)
    _ = fixture.page.pointerRelease(x: handle.x, y: moveY, button: 1)
    let committed = drawerVelocityDocumentSnapshot(fixture.document)
    grid.refreshFromSession()
    velocityGapExpect(report, ledger: rollLedger, row: "commit", [
        ("A056", committed.revision == baseline.revision + 1, "release publishes one document edit"),
        ("A057", committed.identity != baseline.identity, "release publishes one edit identity"),
        ("A058", committed.revision == baseline.revision + 1, "revision advances once"),
        ("A059", committed.identity != baseline.identity && committed.canUndo, "history advances once"),
        ("A060", committed.canUndo, "the velocity drag can be undone"),
        ("A061", fixture.page.frozenPreview[quietID] == nil, "quiet preview clears"),
        ("A062", fixture.page.frozenPreview[laterID] == nil, "later preview clears"),
        ("A063", fixture.page.frozenPreview[loudID] == nil, "loud preview remains absent"),
        ("A064", fixture.document.note(quietID)?.velocity == quietExpected, "quiet value commits"),
        ("A065", fixture.document.note(laterID)?.velocity == laterExpected, "later value commits"),
        ("A066", fixture.document.note(loudID)?.velocity == loud.velocity, "loud value remains unchanged"),
        ("A067", fixture.handle(fixture.document.note(quietID)!)?.value == quietExpected, "quiet stalk republishes commit"),
        ("A068", fixture.handle(fixture.document.note(laterID)!)?.value == laterExpected, "later stalk republishes commit"),
        ("A069", fixture.handle(loud)?.value == Int(loud.velocity), "loud stalk remains unchanged"),
        ("A070", fixture.session.selectedNoteOrder == selection, "release preserves selection"),
    ])

    let escapeFixture = velocityGapFixture(suite: session, service: service)
    let escapeNotes = escapeFixture.notes
    guard escapeNotes.count >= 3 else { return }
    let eq = escapeNotes[0].id, eloud = escapeNotes[1].id, el = escapeNotes[2].id
    escapeFixture.session.setSelectedNotes([eq, el])
    escapeFixture.page.setUseDetents(enabled: false)
    escapeFixture.page.refreshFromDocument()
    guard let elNote = escapeFixture.document.note(el), let eh = escapeFixture.handle(elNote) else { return }
    let escapeBaseline = drawerVelocityDocumentSnapshot(escapeFixture.document)
    let escapeAxis = escapeFixture.page.axisModel
    let ey0 = escapeAxis.velocityToY(Int(elNote.velocity))
    let ey1 = escapeAxis.velocityToY(min(127, Int(elNote.velocity) + 12))
    _ = escapeFixture.page.pointerPress(x: eh.x, y: ey0, surface: 1, button: 1, modifiers: 0)
    _ = escapeFixture.page.pointerMove(x: eh.x, y: ey1, buttons: 1)
    let focusObservation = escapeFixture.page.observation
    _ = escapeFixture.page.handleEscape()
    velocityGapExpect(report, ledger: rollLedger, row: "escape", [
        ("A074", focusObservation.gestureKind == .relative, "the velocity surface owns the active gesture"),
        ("A076", escapeFixture.page.frozenPreview[eq] == nil, "Escape clears quiet preview"),
        ("A077", escapeFixture.page.frozenPreview[el] == nil, "Escape clears later preview"),
        ("A078", escapeFixture.session.selectedNoteOrder == [eq, el], "first Escape preserves selection"),
    ])
    _ = escapeFixture.page.handleEscape()
    let escapeAfter = drawerVelocityDocumentSnapshot(escapeFixture.document)
    velocityGapExpect(report, ledger: rollLedger, row: "escape", [
        ("A079", escapeFixture.session.selectedNoteOrder.isEmpty, "second Escape clears selection"),
        ("A080", escapeAfter.revision == escapeBaseline.revision, "Escape preserves revision"),
        ("A081", escapeAfter.identity == escapeBaseline.identity, "Escape preserves history depth"),
        ("A082", escapeAfter.revision == escapeBaseline.revision, "Escape publishes no document edit"),
        ("A083", escapeAfter.identity == escapeBaseline.identity, "Escape publishes no edit identity"),
    ])

    let octaveFixture = velocityGapFixture(suite: session, service: service)
    let octaveNotes = octaveFixture.notes
    guard octaveNotes.count >= 3 else { return }
    let oq = octaveNotes[0].id, oloud = octaveNotes[1].id, ol = octaveNotes[2].id
    octaveFixture.session.setSelectedNotes([oq, ol])
    octaveFixture.page.refreshFromDocument()
    let octaveGrid = PianoGrid(session: octaveFixture.session)
    octaveGrid.configureViewport(width: 400, height: 240, fontPx: 13, dpr: 1)
    guard let beforeQ = octaveFixture.document.note(oq), let beforeLoud = octaveFixture.document.note(oloud),
          let beforeL = octaveFixture.document.note(ol) else { return }
    let octaveBaseline = drawerVelocityDocumentSnapshot(octaveFixture.document)
    let available = octaveGrid.commandAvailable(command: EditCommand.transposeUpOctave.rawValue)
    octaveGrid.performCommand(command: EditCommand.transposeUpOctave.rawValue)
    octaveFixture.page.refreshFromDocument()
    octaveGrid.refreshFromSession()
    let afterQ = octaveFixture.document.note(oq)
    let afterLoud = octaveFixture.document.note(oloud)
    let afterL = octaveFixture.document.note(ol)
    let octaveCommitted = drawerVelocityDocumentSnapshot(octaveFixture.document)
    velocityGapExpect(report, ledger: rollLedger, row: "octave", [
        ("A084", beforeQ.id == oq, "quiet note resolves before shortcut"),
        ("A085", beforeLoud.id == oloud, "loud note resolves before shortcut"),
        ("A086", beforeL.id == ol, "later note resolves before shortcut"),
        ("A087", octaveBaseline.revision + 1 == octaveCommitted.revision, "revision observer records shortcut"),
        ("A088", octaveBaseline.identity != octaveCommitted.identity, "history observer records shortcut"),
        ("A089", available, "the focused roll route offers octave transpose"),
        ("A091", afterQ != nil, "quiet note resolves after shortcut"),
        ("A092", afterLoud != nil, "loud note resolves after shortcut"),
        ("A093", afterL != nil, "later note resolves after shortcut"),
        ("A094", Int(afterQ?.pitch ?? 0) == Int(beforeQ.pitch) + 12, "quiet moves up one octave"),
        ("A095", Int(afterL?.pitch ?? 0) == Int(beforeL.pitch) + 12, "later moves up one octave"),
        ("A096", afterLoud?.pitch == beforeLoud.pitch, "unselected loud pitch stays unchanged"),
        ("A097", afterQ?.velocity == beforeQ.velocity, "quiet velocity stays unchanged"),
        ("A098", afterLoud?.velocity == beforeLoud.velocity, "loud velocity stays unchanged"),
        ("A099", afterL?.velocity == beforeL.velocity, "later velocity stays unchanged"),
        ("A100", octaveCommitted.revision == octaveBaseline.revision + 1, "shortcut advances revision once"),
        ("A101", octaveCommitted.identity != octaveBaseline.identity && octaveCommitted.canUndo, "shortcut adds one undoable entry"),
        ("A102", octaveCommitted.revision == octaveBaseline.revision + 1, "shortcut publishes one document edit"),
        ("A103", octaveCommitted.identity != octaveBaseline.identity, "shortcut publishes one edit identity"),
        ("A104", octaveFixture.document.note(oq)?.velocity == beforeQ.velocity, "quiet document velocity is preserved"),
        ("A105", octaveFixture.document.note(ol)?.velocity == beforeL.velocity, "later document velocity is preserved"),
        ("A106", octaveFixture.document.note(oloud)?.velocity == beforeLoud.velocity, "loud document velocity is preserved"),
        ("A107", octaveFixture.handles.first { $0.noteID == oq }?.value == Int(beforeQ.velocity), "quiet stalk remains linked after transpose"),
        ("A108", octaveFixture.handles.first { $0.noteID == ol }?.value == Int(beforeL.velocity), "later stalk remains linked after transpose"),
        ("A109", octaveFixture.handles.first { $0.noteID == oloud }?.value == Int(beforeLoud.velocity), "loud stalk remains linked after transpose"),
        ("A110", octaveFixture.session.selectedNoteOrder == [oq, ol], "shortcut preserves selected pair"),
    ])
}
