import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerOriginalNumericPromptTransaction(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "selectionkey/SelectionLocalInputTierTest::numericPromptOwnsKeys"
    let labelID = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let lifetimeID = "selectionkey/SelectionWindowTierTest::tabsDocumentsAndPrimaryTrackLifetime"
    // localinputtier_text.cpp: track0 CC10 at48=32 and96=64; insert at144.
    // These predicates exercise the production Swift transaction. Original
    // keyboard delivery and focus assertions remain deferred, not simulated.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(48, 32), (96, 64)],
                                                     tailTick: 6000)
    fixture.activate(fixture.panLane)
    var insertedNotes: [NoteID] = []
    do {
        let notes = try fixture.document.addNotes([
            NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100)
        ])
        report.expectEqual(1, notes.count, cppID: id, what: "the original selected fixture note exists")
        insertedNotes = notes
        fixture.session.setSelectedNotes(notes)
    } catch {
        report.fail(id, "original fixture note creation failed: \(error)")
        return
    }
    let before = fixture.snapshot
    let state = fixture.document.state
    let selection = fixture.session.selectedNotes
    let page = fixture.page
    report.expect(page.openPrompt(tick: 144, value: 64), cppID: id,
                  message: "the original empty-tick numeric prompt opens")
    page.updatePromptDraft(draft: "12")
    report.expectEqual("12", page.promptDraft, cppID: id,
                       what: "the production prompt retains the supplied numeric draft")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "draft editing does not mutate the song")
    report.expectEqual(selection, fixture.session.selectedNotes, cppID: id,
                       what: "draft editing preserves note selection")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: id, message: "cancellation closes the prompt")
    report.expectEqual(before, fixture.snapshot, cppID: id,
                       what: "cancellation leaves the original document unchanged")
    report.expect(fixture.document.state == state, cppID: id,
                  message: "draft and cancellation preserve the full song contents")

    // Model facts the original read through the QML canvas: the CC10 lane is
    // one row of the page's published row stack, and the inserted fixture
    // note resolves by ID. The QML surfaces themselves stay deferred.
    report.expect(page.rows.contains { $0.parameter == fixture.panLane }, cppID: id,
                  message: "the original CC10 lane is present in the page's row stack")
    report.expect(insertedNotes.first.flatMap { fixture.document.note($0) } != nil, cppID: id,
                  message: "the original fixture note resolves by its inserted ID")

    // windowtier_keyboard.cpp parameterLabelActivationAndSharedCommands opens
    // the volume lane's insertion prompt at tick 5808 value 48 through the
    // same production entry point.
    fixture.activate(fixture.volumeLane)
    report.expect(page.rows.contains { $0.parameter == fixture.volumeLane }, cppID: labelID,
                  message: "the original volume lane is present in the page's row stack")
    report.expect(page.openPrompt(tick: 5808, value: 48), cppID: labelID,
                  message: "the original volume-lane insertion prompt opens")
    report.expectEqual("48", page.promptDraft, cppID: labelID,
                       what: "the volume prompt opens with the plotted value as its draft")
    page.cancelPrompt()

    // windowtier_lifetime.cpp tabsDocumentsAndPrimaryTrackLifetime opens the
    // pan lane's insertion prompt at tick 5760 value 64; a document switch
    // routes through cancelSectionInteraction, and a late acceptance writes
    // nothing.
    fixture.activate(fixture.panLane)
    report.expect(page.openPrompt(tick: 5760, value: 64), cppID: lifetimeID,
                  message: "the original pan-lane insertion prompt opens")
    page.cancelSectionInteraction()
    report.expect(!page.promptOpen, cppID: lifetimeID,
                  message: "the document-switch cancellation closes the prompt")
    report.expect(!page.acceptPrompt(displayedValue: 96), cppID: lifetimeID,
                  message: "accepting a closed prompt commits nothing")
    report.expectEqual(before, fixture.snapshot, cppID: lifetimeID,
                       what: "the closed prompt's late acceptance leaves the document unchanged")
    let peer = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                 pan: [(48, 32), (96, 64)],
                                                 tailTick: 6000)
    peer.activate(peer.panLane)
    let pairB: [NoteID]
    do {
        pairB = try peer.document.addNotes([
            NewNote(track: 0, tick: 960, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 0, tick: 1056, pitch: 64, duration: 48, velocity: 96),
        ])
    } catch {
        report.fail(lifetimeID, "second-document note pair creation failed: \(error)")
        return
    }
    report.expectEqual(2, pairB.count, cppID: lifetimeID,
                       what: "the second document holds the reserved tick-960 note pair")
    report.expect(pairB.allSatisfy { peer.document.note($0) != nil }, cppID: lifetimeID,
                  message: "the second-document pair resolves by its inserted IDs")
    let pairA: [NoteID]
    do {
        pairA = try fixture.document.addNotes([
            NewNote(track: 0, tick: 3840, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 0, tick: 3936, pitch: 64, duration: 48, velocity: 96),
        ])
    } catch {
        report.fail(lifetimeID, "first-document note pair creation failed: \(error)")
        return
    }
    report.expectEqual(2, pairA.count, cppID: lifetimeID,
                       what: "the first document holds the reserved tick-3840 note pair")
    _ = peer.page.activateParameter(index: AutomationCatalog.index(of: .tempo, track: 0) ?? 0)
    report.expectEqual(AutomationParameter.tempo, peer.page.activeParameter, cppID: lifetimeID,
                       what: "the second document keeps tempo active")
    report.expectEqual(fixture.panLane, page.activeParameter, cppID: lifetimeID,
                       what: "the first document keeps pan active while the second shows tempo")
    let firstSteady = fixture.snapshot
    peer.document.nudgeNotes(pairB, byTicks: 24, byKeys: 0)
    report.expect(peer.document.note(pairB[0])?.tick == Tick(984), cppID: lifetimeID,
                  message: "the second document's pair advances under the Right-arrow nudge")
    report.expectEqual(firstSteady, fixture.snapshot, cppID: lifetimeID,
                       what: "the second-document nudge leaves the first document unchanged")
    let peerSteady = peer.snapshot
    fixture.document.nudgeNotes(pairA, byTicks: 0, byKeys: 1)
    report.expect(fixture.document.note(pairA[0])?.pitch == 61, cppID: lifetimeID,
                  message: "the reselected first document transposes one semitone under Up")
    report.expectEqual(peerSteady, peer.snapshot, cppID: lifetimeID,
                       what: "the first-document transpose leaves the second document unchanged")
    var layout = EditorDrawerLayout()
    _ = layout.attachPage(page)
    _ = layout.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false)
    report.expect(!layout.isVisible(.automation), cppID: lifetimeID,
                  message: "the production layout hides the automation section")
    let hiddenTick = fixture.document.note(pairA[0])?.tick ?? Tick(0)
    fixture.session.setSelectedNotes(pairA)
    fixture.document.nudgeNotes(pairA, byTicks: 24, byKeys: 0)
    report.expect(fixture.document.note(pairA[0])?.tick == hiddenTick + Tick(24), cppID: lifetimeID,
                  message: "note arrows route while the automation section stays hidden")
    let second = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                   pan: [(48, 32), (96, 64)],
                                                   tailTick: 6000)
    report.expectEqual(fixture.volumeLane, second.page.activeParameter, cppID: lifetimeID,
                       what: "a fresh page presents the volume lane")
    let addedTrack = second.document.addTrack(voice: 0)
    report.expect(addedTrack == 1, cppID: lifetimeID,
                  message: "the document offers the second engine track")
    report.expect(second.document.engineTracks.usedTrackCount > 1, cppID: lifetimeID,
                  message: "the rich document carries two engine tracks")
    let pairT1: [NoteID]
    do {
        pairT1 = try second.document.addNotes([
            NewNote(track: 1, tick: 960, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 1, tick: 1056, pitch: 64, duration: 48, velocity: 96),
        ])
    } catch {
        report.fail(lifetimeID, "track-1 note pair creation failed: \(error)")
        return
    }
    report.expectEqual(2, pairT1.count, cppID: lifetimeID,
                       what: "the reserved track-1 tick-960 note pair inserts")
    let trackZeroStaging = try? second.document.addNotes([
        NewNote(track: 0, tick: 2000, pitch: 60, duration: 48, velocity: 100),
        NewNote(track: 0, tick: 2096, pitch: 64, duration: 48, velocity: 96),
    ])
    guard let trackZeroPair = trackZeroStaging, trackZeroPair.count == 2 else {
        report.fail(lifetimeID, "track-0 staging pair creation failed")
        return
    }
    second.activate(second.panLane)
    second.session.setSelectedNotes(trackZeroPair)
    let grid = PianoGrid(session: second.session)
    grid.setTrack(index: 1)
    report.expect(second.session.selectedTrack == 1, cppID: lifetimeID,
                  message: "the primary track follows the change")
    report.expect(second.session.selectedNotes.isEmpty, cppID: lifetimeID,
                  message: "the primary-track change clears the note selection")
    let trackOnePan = AutomationParameter.controlChange(track: 1, controller: TimeDefaults.ccPan)
    report.expectEqual(trackOnePan, second.page.activeParameter, cppID: lifetimeID,
                       what: "the primary-track change retargets the active parameter")
    report.expect(second.page.rows.contains { $0.parameter == trackOnePan }, cppID: lifetimeID,
                  message: "the track-1 pan lane is present in the row stack")
    let panLane = Lane.controller(TimeDefaults.ccPan)
    report.expect(!second.document.lanePoints(track: 1, lane: panLane).contains { $0.tick == 5760 },
                  cppID: lifetimeID,
                  message: "the track-1 pan lane holds no point at the insertion tick")
    let peerBeforeInsert = peer.snapshot
    let trackZeroValues = second.values(second.panLane)
    report.expect(second.page.openPrompt(tick: 5760, value: 64), cppID: lifetimeID,
                  message: "the track-1 pan-lane insertion prompt opens")
    report.expect(second.page.acceptPrompt(displayedValue: 32), cppID: lifetimeID,
                  message: "the track-1 prompt accepts the displayed value")
    report.expect(second.document.lanePoints(track: 1, lane: panLane).contains { $0.tick == 5760 && $0.value == 96 },
                  cppID: lifetimeID,
                  message: "the accepted value lands on the track-1 lane through the pan offset")
    report.expectEqual(trackZeroValues, second.values(second.panLane), cppID: lifetimeID,
                       what: "the track-1 insertion leaves the track-0 lane untouched")
    report.expectEqual(peerBeforeInsert, peer.snapshot, cppID: lifetimeID,
                       what: "the track-1 insertion leaves the second document unchanged")
    second.session.setSelectedNotes(pairT1)
    second.document.nudgeNotes(pairT1, byTicks: 0, byKeys: 1)
    report.expect(second.document.note(pairT1[0])?.pitch == 61, cppID: lifetimeID,
                  message: "the new primary track's selection transposes one semitone under Up")

    second.session.setSelectedNotes(pairT1)
    let priorChange = second.session.onChange
    var publications: [SessionChangeDomains] = []
    second.session.onChange = { change in
        publications.append(change.domains)
        priorChange?(change)
    }
    second.session.selectPrimaryTrack(1)
    report.expectEqual(Set(pairT1), second.session.selectedNotes, cppID: lifetimeID,
                       what: "selecting the existing primary track preserves selected notes")
    report.expectEqual([SessionChangeDomains](), publications, cppID: lifetimeID,
                       what: "selecting the existing primary track publishes no change")

    second.session.setSelectedNotes(pairT1)
    publications.removeAll()
    second.session.selectPrimaryTrack(0)
    report.expect(second.session.selectedNotes.isEmpty, cppID: lifetimeID,
                  message: "changing the primary track clears selected notes")
    report.expectEqual(0, second.session.selectedTrack, cppID: lifetimeID,
                       what: "changing the primary track selects track zero")
    report.expectEqual([SessionChangeDomains.selection], publications, cppID: lifetimeID,
                       what: "changing the primary track publishes one selection change")

    second.session.setSelectedNotes(pairT1)
    publications.removeAll()
    let primaryBeforeOutOfRange = second.session.selectedTrack
    second.session.selectPrimaryTrack(-1)
    second.session.selectPrimaryTrack(second.document.engineTracks.usedTrackCount)
    report.expect(second.session.selectedNotes == Set(pairT1) && second.session.selectedTrack == primaryBeforeOutOfRange && publications.isEmpty, cppID: lifetimeID,
                  message: "out-of-range primary-track selects keep the track, notes, and publications")
    second.session.onChange = priorChange
    let tempoID = "drawerpresentation/DrawerPresentationTest::valuePromptTempoLimitsAcceptAndClamp"
    let ccID = "drawerpresentation/DrawerPresentationTest::valuePromptCcCenterOffsetInsertionCommit"
    let escapeID = "drawerpresentation/DrawerPresentationTest::valuePromptEscapeCancelsAndReturnsFocus"
    let focusID = "drawerpresentation/DrawerPresentationTest::valuePromptFocusLossDocumentChangeAndPageHideCancel"
    let lateID = "drawerpresentation/DrawerPresentationTest::valuePromptCancelAndLateAcceptWriteNothing"
    let tempoFixture = drawerAutomationAutomationFixture(suite: suite, service: service)
    tempoFixture.activate(.tempo)
    let tempoBaseRevision = tempoFixture.document.revision
    report.expect(tempoFixture.page.openPrompt(tick: 24, value: 140), cppID: tempoID,
                  message: "tempo insertion prompt opens at tick 24")
    report.expect(tempoFixture.page.acceptPrompt(displayedValue: 90), cppID: tempoID,
                  message: "tempo prompt commits 90 BPM")
    report.expectEqual(tempoBaseRevision + 1, tempoFixture.document.revision, cppID: tempoID,
                       what: "A017 one tempo acceptance advances the revision once")
    report.expect(tempoFixture.tempoValues.contains("24:90"), cppID: tempoID,
                  message: "A019 committed tempo reads 90 BPM at tick 24")
    report.expect(tempoFixture.page.openPrompt(tick: 32, value: 120), cppID: tempoID,
                  message: "tempo ceiling prompt opens at tick 32")
    report.expect(tempoFixture.page.acceptPrompt(displayedValue: TimeDefaults.maximumTempoBPM + 1000),
                  cppID: tempoID, message: "over-maximum tempo acceptance commits")
    report.expect(tempoFixture.tempoValues.contains("32:\(TimeDefaults.maximumTempoBPM)"), cppID: tempoID,
                  message: "A024 ceiling acceptance clamps to the maximum BPM")
    report.expect(tempoFixture.page.openPrompt(tick: 40, value: 120), cppID: tempoID,
                  message: "tempo floor prompt opens at tick 40")
    report.expect(tempoFixture.page.acceptPrompt(displayedValue: TimeDefaults.minimumTempoBPM - 1000),
                  cppID: tempoID, message: "under-minimum tempo acceptance commits")
    report.expect(tempoFixture.tempoValues.contains("40:\(TimeDefaults.minimumTempoBPM)"), cppID: tempoID,
                  message: "A028 floor acceptance clamps to the minimum BPM")
    report.expectEqual(tempoBaseRevision + 3, tempoFixture.document.revision, cppID: tempoID,
                       what: "A029 three tempo acceptances advance the revision three times")
    let tempoDepthFixture = drawerAutomationAutomationFixture(suite: suite, service: service)
    tempoDepthFixture.activate(.tempo)
    let tempoDepthBase = try? coreEditHistoryCountAtTip(tempoDepthFixture.document, report: report, cppID: tempoID)
    report.expect(tempoDepthFixture.page.openPrompt(tick: 24, value: 140), cppID: tempoID,
                  message: "depth tempo prompt opens at tick 24")
    report.expect(tempoDepthFixture.page.acceptPrompt(displayedValue: 90), cppID: tempoID,
                  message: "depth tempo prompt commits 90 BPM")
    if let base = tempoDepthBase,
       let afterFirst = try? coreEditHistoryCountAtTip(tempoDepthFixture.document, report: report, cppID: tempoID) {
        report.expectEqual(base + 1, afterFirst, cppID: tempoID,
                           what: "A018 one tempo acceptance records one history entry")
    } else {
        report.fail(tempoID, "tempo history depth unreadable after one acceptance")
    }
    report.expect(tempoDepthFixture.page.openPrompt(tick: 32, value: 120), cppID: tempoID,
                  message: "depth tempo ceiling prompt opens at tick 32")
    report.expect(tempoDepthFixture.page.acceptPrompt(displayedValue: TimeDefaults.maximumTempoBPM + 1000),
                  cppID: tempoID, message: "depth over-maximum tempo acceptance commits")
    report.expect(tempoDepthFixture.page.openPrompt(tick: 40, value: 120), cppID: tempoID,
                  message: "depth tempo floor prompt opens at tick 40")
    report.expect(tempoDepthFixture.page.acceptPrompt(displayedValue: TimeDefaults.minimumTempoBPM - 1000),
                  cppID: tempoID, message: "depth under-minimum tempo acceptance commits")
    if let base = tempoDepthBase,
       let afterAll = try? coreEditHistoryCountAtTip(tempoDepthFixture.document, report: report, cppID: tempoID) {
        report.expectEqual(base + 3, afterAll, cppID: tempoID,
                           what: "A030 three tempo acceptances record three history entries")
    } else {
        report.fail(tempoID, "tempo history depth unreadable after three acceptances")
    }
    let ccFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    ccFixture.activate(ccFixture.panLane)
    report.expect(ccFixture.page.rows.contains { $0.parameter == ccFixture.panLane }, cppID: ccID,
                  message: "A035 CC10 lane present in the insertion fixture row stack")
    let ccBaseRevision = ccFixture.document.revision
    report.expect(ccFixture.page.openPrompt(tick: 96, value: 64), cppID: ccID,
                  message: "CC insertion prompt opens at empty tick 96")
    report.expect(ccFixture.page.acceptPrompt(displayedValue: 0), cppID: ccID,
                  message: "displayed 0 commits through the center offset")
    report.expectEqual(ccBaseRevision + 1, ccFixture.document.revision, cppID: ccID,
                       what: "A042 one CC insertion advances the revision once")
    report.expectEqual(2, ccFixture.lanePoints(ccFixture.panLane).count, cppID: ccID,
                       what: "A044 insertion leaves two lane points")
    report.expectEqual(64, ccFixture.lanePoints(ccFixture.panLane).first { $0.tick == 96 }?.value ?? -1,
                       cppID: ccID, what: "A045 inserted point stores 64")
    report.expect(ccFixture.page.openPrompt(tick: 96, value: 64), cppID: ccID,
                  message: "node prompt opens on the inserted point")
    report.expect(ccFixture.page.acceptPrompt(displayedValue: -64), cppID: ccID,
                  message: "displayed -64 commits through the stored offset")
    report.expect(ccFixture.lanePoints(ccFixture.panLane).contains { $0.tick == 96 }, cppID: ccID,
                  message: "A049 lowered node found at tick 96")
    report.expectEqual(0, ccFixture.lanePoints(ccFixture.panLane).first { $0.tick == 96 }?.value ?? -1,
                       cppID: ccID, what: "A050 displayed -64 stores 0")
    report.expect(ccFixture.page.openPrompt(tick: 96, value: 0), cppID: ccID,
                  message: "node prompt reopens on the lowered point")
    report.expect(ccFixture.page.acceptPrompt(displayedValue: 63), cppID: ccID,
                  message: "displayed 63 commits through the stored offset")
    report.expect(ccFixture.lanePoints(ccFixture.panLane).contains { $0.tick == 96 }, cppID: ccID,
                  message: "A054 raised node found at tick 96")
    report.expectEqual(127, ccFixture.lanePoints(ccFixture.panLane).first { $0.tick == 96 }?.value ?? -1,
                       cppID: ccID, what: "A055 displayed 63 stores 127")
    report.expectEqual(ccBaseRevision + 3, ccFixture.document.revision, cppID: ccID,
                       what: "A056 three CC acceptances advance the revision three times")
    let ccDepthFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    ccDepthFixture.activate(ccDepthFixture.panLane)
    let ccDepthBase = try? coreEditHistoryCountAtTip(ccDepthFixture.document, report: report, cppID: ccID)
    report.expect(ccDepthFixture.page.openPrompt(tick: 96, value: 64), cppID: ccID,
                  message: "depth CC insertion prompt opens at tick 96")
    report.expect(ccDepthFixture.page.acceptPrompt(displayedValue: 0), cppID: ccID,
                  message: "depth displayed 0 commits through the center offset")
    if let base = ccDepthBase,
       let afterFirst = try? coreEditHistoryCountAtTip(ccDepthFixture.document, report: report, cppID: ccID) {
        report.expectEqual(base + 1, afterFirst, cppID: ccID,
                           what: "A043 one CC insertion records one history entry")
    } else {
        report.fail(ccID, "CC history depth unreadable after one insertion")
    }
    report.expect(ccDepthFixture.page.openPrompt(tick: 96, value: 64), cppID: ccID,
                  message: "depth node prompt opens on the inserted point")
    report.expect(ccDepthFixture.page.acceptPrompt(displayedValue: -64), cppID: ccID,
                  message: "depth displayed -64 commits")
    report.expect(ccDepthFixture.page.openPrompt(tick: 96, value: 0), cppID: ccID,
                  message: "depth node prompt reopens on the lowered point")
    report.expect(ccDepthFixture.page.acceptPrompt(displayedValue: 63), cppID: ccID,
                  message: "depth displayed 63 commits")
    if let base = ccDepthBase,
       let afterAll = try? coreEditHistoryCountAtTip(ccDepthFixture.document, report: report, cppID: ccID) {
        report.expectEqual(base + 3, afterAll, cppID: ccID,
                           what: "A057 three CC acceptances record three history entries")
    } else {
        report.fail(ccID, "CC history depth unreadable after three acceptances")
    }
    let escapeFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    escapeFixture.activate(escapeFixture.panLane)
    report.expect(escapeFixture.page.rows.contains { $0.parameter == escapeFixture.panLane }, cppID: escapeID,
                  message: "A063 CC10 lane present in the escape fixture row stack")
    let focusFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    focusFixture.activate(focusFixture.panLane)
    report.expect(focusFixture.page.rows.contains { $0.parameter == focusFixture.panLane }, cppID: focusID,
                  message: "A073 CC10 lane present in the focus fixture row stack")
    let focusDepthBase = try? coreEditHistoryCountAtTip(focusFixture.document, report: report, cppID: focusID)
    let focusBaseRevision = focusFixture.document.revision
    report.expect(focusFixture.page.openPrompt(tick: 24, value: 64), cppID: focusID,
                  message: "node prompt opens before the document change")
    focusFixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 48, through: 48,
                                    points: [LaneWrite(tick: 48, value: 32)])
    report.expect(!focusFixture.page.promptOpen, cppID: focusID,
                  message: "document change cancels the pending prompt")
    report.expect(focusFixture.lanePoints(focusFixture.panLane).contains { $0.tick == 24 }, cppID: focusID,
                  message: "A080 original node found after the cancel")
    report.expectEqual(64, focusFixture.lanePoints(focusFixture.panLane).first { $0.tick == 24 }?.value ?? -1,
                       cppID: focusID, what: "A081 cancelled prompt keeps the original value 64")
    report.expect(focusFixture.lanePoints(focusFixture.panLane).contains { $0.tick == 48 }, cppID: focusID,
                  message: "A082 added point found at tick 48")
    report.expectEqual(32, focusFixture.lanePoints(focusFixture.panLane).first { $0.tick == 48 }?.value ?? -1,
                       cppID: focusID, what: "A083 added point stores 32")
    report.expectEqual(["24:64", "48:32"], focusFixture.values(focusFixture.panLane), cppID: focusID,
                       what: "A084 lane holds the original plus the added point")
    report.expectEqual(focusBaseRevision + 1, focusFixture.document.revision, cppID: focusID,
                       what: "A085 document change alone advances the revision once")
    if let base = focusDepthBase,
       let afterChange = try? coreEditHistoryCountAtTip(focusFixture.document, report: report, cppID: focusID) {
        report.expectEqual(base + 1, afterChange, cppID: focusID,
                           what: "A086 document change records one history entry")
    } else {
        report.fail(focusID, "focus history depth unreadable after the document change")
    }
    let lateFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    lateFixture.activate(lateFixture.panLane)
    report.expect(lateFixture.page.rows.contains { $0.parameter == lateFixture.panLane }, cppID: lateID,
                  message: "A096 CC10 lane present in the cancel fixture row stack")

}
