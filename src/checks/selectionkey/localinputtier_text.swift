import PorydawApp
import PorydawAppCommands
import PorydawCore

@MainActor
func drawerOriginalNumericPromptTransaction(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let id = "selectionkey/SelectionLocalInputTierTest::numericPromptOwnsKeys"
    let labelID = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let lifetimeID = "selectionkey/SelectionWindowTierTest::tabsDocumentsAndPrimaryTrackLifetime"
    // localinputtier_text.cpp: track0 CC10 at48=32 and96=64; insert at144.
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(48, 32), (96, 64)],
                                                     tailTick: 6000)
    fixture.activate(fixture.panLane)
    var insertedNotes: [NoteID] = []
    do {
        let notes = try fixture.document.addNotes([
            NewNote(track: 0, tick: 24, pitch: 60, duration: 24, velocity: 100)
        ])
        report.expectEqual(expected: 1, actual: notes.count, cppID: id, what: "the original selected fixture note exists")
        insertedNotes = notes
        fixture.session.setSelectedNotes(notes)
    } catch {
        report.fail(id, "original fixture note creation failed: \(error)")
        return
    }
    let before = fixture.snapshot
    let beforeHistory = fixture.document.history.undoIndex
    let beforeBytes = try? fixture.document.state.file.encoded()
    report.expect(beforeBytes != nil, cppID: lifetimeID,
                  message: "the first song serializes before lifetime routing")
    let state = fixture.document.state
    let selection = fixture.session.selectedNotes
    let page = fixture.page
    report.expect(page.openPrompt(tick: 144, value: 64), cppID: id,
                  message: "the original empty-tick numeric prompt opens")
    page.updatePromptDraft(draft: "12")
    report.expectEqual(expected: "12", actual: page.promptDraft, cppID: id,
                       what: "the production prompt retains the supplied numeric draft")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "draft editing does not mutate the song")
    report.expectEqual(expected: selection, actual: fixture.session.selectedNotes, cppID: id,
                       what: "draft editing preserves note selection")
    report.expectEqual(expected: beforeBytes,
                       actual: try? fixture.document.state.file.encoded(), cppID: id,
                       what: "numeric draft leaves every serialized song byte unchanged")
    report.expect(fixture.document.history.undoIndex == beforeHistory, cppID: id,
                  message: "numeric draft creates no song history entry")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: id, message: "cancellation closes the prompt")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: id,
                       what: "cancellation leaves the original document unchanged")
    report.expect(fixture.document.state == state, cppID: id,
                  message: "draft and cancellation preserve the full song contents")
    report.expectEqual(expected: beforeBytes,
                       actual: try? fixture.document.state.file.encoded(), cppID: id,
                       what: "numeric cancellation preserves every serialized song byte")
    report.expect(fixture.document.history.undoIndex == beforeHistory, cppID: id,
                  message: "numeric cancellation creates no song history entry")
    report.expectEqual(expected: selection, actual: fixture.session.selectedNotes, cppID: id,
                       what: "numeric cancellation preserves selected NoteIDs")

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
    report.expectEqual(expected: "48", actual: page.promptDraft, cppID: labelID,
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
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: lifetimeID,
                       what: "the closed prompt's late acceptance leaves the document unchanged")
    report.expectEqual(expected: beforeBytes,
                       actual: try? fixture.document.state.file.encoded(),
                       cppID: lifetimeID,
                       what: "the cancelled document-switch prompt preserves first-song bytes")
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
    report.expectEqual(expected: 2, actual: pairB.count, cppID: lifetimeID,
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
    report.expectEqual(expected: 2, actual: pairA.count, cppID: lifetimeID,
                       what: "the first document holds the reserved tick-3840 note pair")
    _ = peer.page.activateParameter(index: AutomationCatalog.index(of: .tempo, track: 0) ?? 0)
    report.expectEqual(expected: AutomationParameter.tempo, actual: peer.page.activeParameter, cppID: lifetimeID,
                       what: "the second document keeps tempo active")
    report.expectEqual(expected: fixture.panLane, actual: page.activeParameter, cppID: lifetimeID,
                       what: "the first document keeps pan active while the second shows tempo")
    let firstSteady = fixture.snapshot
    let firstSteadyBytes = try? fixture.document.state.file.encoded()
    let peerSteadyBytes = try? peer.document.state.file.encoded()
    report.expect(firstSteadyBytes != nil && peerSteadyBytes != nil,
                  cppID: lifetimeID,
                  message: "both live documents serialize before cross-tab key routing")
    peer.document.nudgeNotes(pairB, byTicks: 24, byKeys: 0)
    report.expect(peer.document.note(pairB[0])?.tick == Tick(984), cppID: lifetimeID,
                  message: "the second document's pair advances under the Right-arrow nudge")
    report.expectEqual(expected: firstSteady, actual: fixture.snapshot, cppID: lifetimeID,
                       what: "the second-document nudge leaves the first document unchanged")
    report.expectEqual(expected: firstSteadyBytes,
                       actual: try? fixture.document.state.file.encoded(),
                       cppID: lifetimeID,
                       what: "a second-document edit preserves the first song's exact bytes")
    let peerAfterNudgeBytes = try? peer.document.state.file.encoded()
    report.expect(peerAfterNudgeBytes != nil && peerSteadyBytes != peerAfterNudgeBytes,
                  cppID: lifetimeID,
                  message: "the second-document edit changes its own serialized bytes")
    let peerSteady = peer.snapshot
    fixture.document.nudgeNotes(pairA, byTicks: 0, byKeys: 1)
    report.expect(fixture.document.note(pairA[0])?.pitch == 61, cppID: lifetimeID,
                  message: "the reselected first document transposes one semitone under Up")
    report.expectEqual(expected: peerSteady, actual: peer.snapshot, cppID: lifetimeID,
                       what: "the first-document transpose leaves the second document unchanged")
    report.expectEqual(expected: peerAfterNudgeBytes,
                       actual: try? peer.document.state.file.encoded(),
                       cppID: lifetimeID,
                       what: "the first-document transpose preserves second-song bytes")
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
    report.expectEqual(expected: fixture.volumeLane, actual: second.page.activeParameter, cppID: lifetimeID,
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
    report.expectEqual(expected: 2, actual: pairT1.count, cppID: lifetimeID,
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
    report.expectEqual(expected: trackOnePan, actual: second.page.activeParameter, cppID: lifetimeID,
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
    report.expectEqual(expected: trackZeroValues, actual: second.values(second.panLane), cppID: lifetimeID,
                       what: "the track-1 insertion leaves the track-0 lane untouched")
    report.expectEqual(expected: peerBeforeInsert, actual: peer.snapshot, cppID: lifetimeID,
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
    report.expectEqual(expected: Set(pairT1), actual: second.session.selectedNotes, cppID: lifetimeID,
                       what: "selecting the existing primary track preserves selected notes")
    report.expectEqual(expected: [SessionChangeDomains](), actual: publications, cppID: lifetimeID,
                       what: "selecting the existing primary track publishes no change")

    second.session.setSelectedNotes(pairT1)
    publications.removeAll()
    second.session.selectPrimaryTrack(0)
    report.expect(second.session.selectedNotes.isEmpty, cppID: lifetimeID,
                  message: "changing the primary track clears selected notes")
    report.expectEqual(expected: 0, actual: second.session.selectedTrack, cppID: lifetimeID,
                       what: "changing the primary track selects track zero")
    report.expectEqual(expected: [SessionChangeDomains.selection], actual: publications, cppID: lifetimeID,
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
    report.expectEqual(expected: tempoBaseRevision + 1, actual: tempoFixture.document.revision, cppID: tempoID,
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
    report.expectEqual(expected: tempoBaseRevision + 3, actual: tempoFixture.document.revision, cppID: tempoID,
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
        report.expectEqual(expected: base + 1, actual: afterFirst, cppID: tempoID,
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
        report.expectEqual(expected: base + 3, actual: afterAll, cppID: tempoID,
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
    report.expectEqual(expected: ccBaseRevision + 1, actual: ccFixture.document.revision, cppID: ccID,
                       what: "A042 one CC insertion advances the revision once")
    report.expectEqual(expected: 2, actual: ccFixture.lanePoints(ccFixture.panLane).count, cppID: ccID,
                       what: "A044 insertion leaves two lane points")
    report.expectEqual(expected: 64, actual: ccFixture.lanePoints(ccFixture.panLane).first { $0.tick == 96 }?.value ?? -1,
                       cppID: ccID, what: "A045 inserted point stores 64")
    report.expect(ccFixture.page.openPrompt(tick: 96, value: 64), cppID: ccID,
                  message: "node prompt opens on the inserted point")
    report.expect(ccFixture.page.acceptPrompt(displayedValue: -64), cppID: ccID,
                  message: "displayed -64 commits through the stored offset")
    report.expect(ccFixture.lanePoints(ccFixture.panLane).contains { $0.tick == 96 }, cppID: ccID,
                  message: "A049 lowered node found at tick 96")
    report.expectEqual(expected: 0, actual: ccFixture.lanePoints(ccFixture.panLane).first { $0.tick == 96 }?.value ?? -1,
                       cppID: ccID, what: "A050 displayed -64 stores 0")
    report.expect(ccFixture.page.openPrompt(tick: 96, value: 0), cppID: ccID,
                  message: "node prompt reopens on the lowered point")
    report.expect(ccFixture.page.acceptPrompt(displayedValue: 63), cppID: ccID,
                  message: "displayed 63 commits through the stored offset")
    report.expect(ccFixture.lanePoints(ccFixture.panLane).contains { $0.tick == 96 }, cppID: ccID,
                  message: "A054 raised node found at tick 96")
    report.expectEqual(expected: 127, actual: ccFixture.lanePoints(ccFixture.panLane).first { $0.tick == 96 }?.value ?? -1,
                       cppID: ccID, what: "A055 displayed 63 stores 127")
    report.expectEqual(expected: ccBaseRevision + 3, actual: ccFixture.document.revision, cppID: ccID,
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
        report.expectEqual(expected: base + 1, actual: afterFirst, cppID: ccID,
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
        report.expectEqual(expected: base + 3, actual: afterAll, cppID: ccID,
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
    report.expectEqual(expected: 64, actual: focusFixture.lanePoints(focusFixture.panLane).first { $0.tick == 24 }?.value ?? -1,
                       cppID: focusID, what: "A081 cancelled prompt keeps the original value 64")
    report.expect(focusFixture.lanePoints(focusFixture.panLane).contains { $0.tick == 48 }, cppID: focusID,
                  message: "A082 added point found at tick 48")
    report.expectEqual(expected: 32, actual: focusFixture.lanePoints(focusFixture.panLane).first { $0.tick == 48 }?.value ?? -1,
                       cppID: focusID, what: "A083 added point stores 32")
    report.expectEqual(expected: ["24:64", "48:32"], actual: focusFixture.values(focusFixture.panLane), cppID: focusID,
                       what: "A084 lane holds the original plus the added point")
    report.expectEqual(expected: focusBaseRevision + 1, actual: focusFixture.document.revision, cppID: focusID,
                       what: "A085 document change alone advances the revision once")
    if let base = focusDepthBase,
       let afterChange = try? coreEditHistoryCountAtTip(focusFixture.document, report: report, cppID: focusID) {
        report.expectEqual(expected: base + 1, actual: afterChange, cppID: focusID,
                           what: "A086 document change records one history entry")
    } else {
        report.fail(focusID, "focus history depth unreadable after the document change")
    }
    let lateFixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    lateFixture.activate(lateFixture.panLane)
    report.expect(lateFixture.page.rows.contains { $0.parameter == lateFixture.panLane }, cppID: lateID,
                  message: "A096 CC10 lane present in the cancel fixture row stack")

    windowTierKeyboardOutcomes(report, suite: suite, service: service)
    coreEditingKeyboardOutcomes(report, suite: suite, service: service)
}

@MainActor
private func windowTierKeyboardOutcomes(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    let id = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, volume: [(5760, 48)], pan: [(5760, 32)],
        modulation: [(5760, 96)], tailTick: 9000)
    let document = fixture.document
    let session = fixture.session
    let page = fixture.page
    let selectedLanes: Set<AutomationParameter> = [fixture.panLane, fixture.modulationLane]
    guard let pair = try? document.addNotes([
        NewNote(track: 0, tick: 2400, pitch: 60, duration: 48, velocity: 100),
        NewNote(track: 0, tick: 2496, pitch: 64, duration: 48, velocity: 96),
    ]), pair.count == 2,
        let first = document.note(pair[0]), let second = document.note(pair[1])
    else {
        report.fail(id, "the reserved tick-2400 pair could not be staged")
        return
    }
    let grid = PianoGrid(session: session)
    let ruler = RulerMenuPresenter(session: session, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    let selection = AutomationTimeSelection(
        range: TimeRange(startTick: 5760, endTick: 5784), scope: .lanes,
        lanes: selectedLanes, tempo: false)
    session.setSelectedNotes(pair)
    page.applyTimeSelection(selection)
    let undoBefore = try? coreEditHistoryCountAtTip(document, report: report, cppID: id)
    fixture.activate(fixture.modulationLane)
    report.expectEqual(expected: Tick(5760), actual: session.timeSelection?.range.startTick,
                       cppID: id, what: "A030 label activation keeps the selection start")
    report.expectEqual(expected: Tick(5784), actual: session.timeSelection?.range.endTick,
                       cppID: id, what: "A030 label activation keeps the selection end")
    report.expect(session.timeSelection?.scope == .lanes, cppID: id,
                  message: "A030 label activation keeps the lanes scope")
    report.expectEqual(expected: selectedLanes, actual: session.timeSelection?.lanes,
                       cppID: id, what: "A030 label activation keeps both selected CC lanes")
    report.expect(session.timeSelection?.tempo == false, cppID: id,
                  message: "A030 label activation keeps Tempo out of the scope")
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "A030 label activation keeps the note selection empty")
    fixture.activate(fixture.volumeLane)
    report.expectEqual(expected: Tick(5760), actual: session.timeSelection?.range.startTick,
                       cppID: id, what: "A038 Return activation keeps the selection start")
    report.expectEqual(expected: Tick(5784), actual: session.timeSelection?.range.endTick,
                       cppID: id, what: "A038 Return activation keeps the selection end")
    report.expect(session.timeSelection?.scope == .lanes, cppID: id,
                  message: "A038 Return activation keeps the lanes scope")
    report.expectEqual(expected: selectedLanes, actual: session.timeSelection?.lanes,
                       cppID: id, what: "A038 Return activation keeps both selected CC lanes")
    report.expect(session.timeSelection?.tempo == false, cppID: id,
                  message: "A038 Return activation keeps Tempo out of the scope")
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "A038 Return activation keeps the note selection empty")
    report.expectEqual(expected: undoBefore,
                       actual: try? coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A035 label activation keeps the exact undo index")
    let beforeUp = document.state
    router.perform(.transposeUp)
    report.expectEqual(expected: beforeUp, actual: document.state, cppID: id,
                       what: "A041 Up with a lane range leaves song contents unchanged")
    report.expectEqual(expected: Tick(5760), actual: session.timeSelection?.range.startTick,
                       cppID: id, what: "A041 Up keeps the selection start")
    report.expectEqual(expected: Tick(5784), actual: session.timeSelection?.range.endTick,
                       cppID: id, what: "A041 Up keeps the selection end")
    report.expect(session.timeSelection?.scope == .lanes, cppID: id,
                  message: "A041 Up keeps the lanes scope")
    report.expectEqual(expected: selectedLanes, actual: session.timeSelection?.lanes,
                       cppID: id, what: "A041 Up keeps both selected CC lanes")
    report.expect(session.timeSelection?.tempo == false, cppID: id,
                  message: "A041 Up keeps Tempo out of the scope")
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "A041 Up keeps the note selection empty")
    let beforePrompt = document.state
    report.expect(page.openPrompt(tick: 5808, value: 48), cppID: id,
                  message: "the active Volume parameter opens its value prompt")
    report.expectEqual(expected: beforePrompt, actual: document.state, cppID: id,
                       what: "A052 prompt draft leaves song contents unchanged")
    report.expectEqual(expected: Tick(5760), actual: session.timeSelection?.range.startTick,
                       cppID: id, what: "A053 prompt draft keeps the selection start")
    report.expectEqual(expected: Tick(5784), actual: session.timeSelection?.range.endTick,
                       cppID: id, what: "A053 prompt draft keeps the selection end")
    report.expect(session.timeSelection?.scope == .lanes, cppID: id,
                  message: "A053 prompt draft keeps the lanes scope")
    report.expectEqual(expected: selectedLanes, actual: session.timeSelection?.lanes,
                       cppID: id, what: "A053 prompt draft keeps both selected CC lanes")
    report.expect(session.timeSelection?.tempo == false, cppID: id,
                  message: "A053 prompt draft keeps Tempo excluded")
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "A053 prompt draft keeps the note selection empty")
    page.cancelPrompt()
    report.expectEqual(expected: undoBefore,
                       actual: try? coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A035 prompt Escape keeps the exact undo index")
    report.expectEqual(expected: Tick(5760), actual: session.timeSelection?.range.startTick,
                       cppID: id, what: "A056 prompt Escape keeps the selection start")
    report.expectEqual(expected: Tick(5784), actual: session.timeSelection?.range.endTick,
                       cppID: id, what: "A056 prompt Escape keeps the selection end")
    report.expect(session.timeSelection?.scope == .lanes, cppID: id,
                  message: "A056 prompt Escape keeps the lanes scope")
    report.expectEqual(expected: selectedLanes, actual: session.timeSelection?.lanes,
                       cppID: id, what: "A056 prompt Escape keeps both selected CC lanes")
    report.expect(session.timeSelection?.tempo == false, cppID: id,
                  message: "A056 prompt Escape keeps Tempo excluded")
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "A056 prompt Escape keeps the note selection empty")
    let tapIndex = document.history.undoIndex
    let tapCount = document.history.undoCount
    page.tapTempoTap(atMilliseconds: 1_000)
    page.tapTempoTap(atMilliseconds: 1_500)
    report.expect(page.tapTempoTapCount == 2 && page.tapTempoDraftBpm > 0,
                  cppID: id, message: "two tempo taps publish a draft without committing it")
    report.expect(document.history.undoIndex == tapIndex, cppID: id,
                  message: "two direct tempo taps preserve the exact undo index")
    report.expect(document.history.undoCount == tapCount, cppID: id,
                  message: "two direct tempo taps preserve the exact undo count")
    page.resetTapTempo()
    router.perform(.copy)
    let clip = GridClipboard().read()?.clip
    report.expectEqual(expected: [ClipLanePoint(relTick: 0, value: 32)],
                       actual: clip?.lanes.first(where: { $0.cc == TimeDefaults.ccPan })?.points,
                       cppID: id, what: "A061 window Copy captures the Pan value at the selected tick")
    report.expectEqual(expected: [ClipLanePoint(relTick: 0, value: 96)],
                       actual: clip?.lanes.first(where: { $0.cc == TimeDefaults.ccModulation })?.points,
                       cppID: id, what: "A061 window Copy captures the Modulation value at the selected tick")
    report.expectEqual(expected: beforePrompt, actual: document.state, cppID: id,
                       what: "A061 window Copy leaves the song unchanged")
    report.expectEqual(expected: Tick(5760), actual: session.timeSelection?.range.startTick,
                       cppID: id, what: "A061 window Copy keeps the selection start")
    report.expectEqual(expected: Tick(5784), actual: session.timeSelection?.range.endTick,
                       cppID: id, what: "A061 window Copy keeps the selection end")
    report.expect(session.timeSelection?.scope == .lanes, cppID: id,
                  message: "A061 window Copy keeps the lanes scope")
    report.expectEqual(expected: selectedLanes, actual: session.timeSelection?.lanes,
                       cppID: id, what: "A061 window Copy keeps both selected CC lanes")
    report.expect(session.timeSelection?.tempo == false, cppID: id,
                  message: "A061 window Copy keeps Tempo excluded")
    report.expect(session.selectedNotes.isEmpty, cppID: id,
                  message: "A061 window Copy keeps the note selection empty")
    router.perform(.delete)
    report.expect(fixture.lanePoints(fixture.panLane).allSatisfy { $0.tick != 5760 },
                  cppID: id, message: "A062 Delete removes the selected Pan point")
    report.expect(fixture.lanePoints(fixture.modulationLane).allSatisfy { $0.tick != 5760 },
                  cppID: id, message: "A063 Delete removes the selected Modulation point")
    report.expectEqual(expected: ["5760:48"], actual: fixture.values(fixture.volumeLane),
                       cppID: id, what: "A064 Delete retains the unselected Volume point")
    report.expectEqual(expected: first, actual: document.note(pair[0]), cppID: id,
                       what: "A065 Delete retains the first reserved note by identity")
    report.expectEqual(expected: second, actual: document.note(pair[1]), cppID: id,
                       what: "A065 Delete retains the second reserved note by identity")
    router.perform(.selectAll)
    report.expect(session.selectedNotes.contains(pair[0]), cppID: id,
                  message: "A067 Select All includes the first reserved note by ID")
    report.expect(session.selectedNotes.contains(pair[1]), cppID: id,
                  message: "A068 Select All includes the second reserved note by ID")
    session.setSelectedNotes([])
    session.editCursor = 7680
    router.perform(.paste)
    let pastedPan = fixture.lanePoints(fixture.panLane).first { $0.tick == 7680 }
    let pastedModulation = fixture.lanePoints(fixture.modulationLane).first { $0.tick == 7680 }
    report.expect(pastedPan != nil, cppID: id,
                  message: "A070 Paste lands a Pan point at the committed cursor")
    report.expectEqual(expected: 32, actual: pastedPan?.value, cppID: id,
                       what: "A071 Paste lands Pan value 32 at the committed cursor")
    report.expect(pastedModulation != nil, cppID: id,
                  message: "A072 Paste lands a Modulation point at the committed cursor")
    report.expectEqual(expected: 96, actual: pastedModulation?.value, cppID: id,
                       what: "A073 Paste lands Modulation value 96 at the committed cursor")
    report.expect(fixture.lanePoints(fixture.volumeLane).allSatisfy { $0.tick != 7680 },
                  cppID: id, message: "A074 Paste keeps the unselected Volume lane empty at the cursor")
    report.expectEqual(expected: first, actual: document.note(pair[0]), cppID: id,
                       what: "A075 Paste retains the first reserved note unchanged")
    report.expectEqual(expected: second, actual: document.note(pair[1]), cppID: id,
                       what: "A075 Paste retains the second reserved note unchanged")
    report.expectEqual(expected: fixture.volumeLane, actual: page.activeParameter, cppID: id,
                       what: "A076 Paste keeps Volume as the active parameter")
    session.setSelectedNotes(pair)
    let step = Tick(grid.snapTicks)
    router.perform(.nudgeRight)
    router.perform(.transposeUp)
    report.expect(document.note(pair[0])?.tick == first.tick + step, cppID: id,
                  message: "A078 routed Right advances the first reserved note one snap by ID")
    report.expect(document.note(pair[1])?.tick == second.tick + step, cppID: id,
                  message: "A078 routed Right advances the second reserved note one snap by ID")
    report.expect(document.note(pair[0])?.pitch == first.pitch + 1, cppID: id,
                  message: "A078 routed Up raises the first reserved note one semitone by ID")
    report.expect(document.note(pair[1])?.pitch == second.pitch + 1, cppID: id,
                  message: "A078 routed Up raises the second reserved note one semitone by ID")
    report.expectEqual(expected: Set(pair), actual: session.selectedNotes, cppID: id,
                       what: "A078 routed arrows preserve the pair selection")
}

@MainActor
private func coreEditingKeyboardOutcomes(_ report: CheckReport, suite: DocumentSession,
                                         service: ProjectService) {
    let rangeID = "selectionkey/SelectionKeyCoreTest::automationRangeAndReboundDelete"
    let moveID = "selectionkey/SelectionKeyCoreTest::laneScopedHorizontalArrowNudgesPointsAndInterval"
    let pasteID = "selectionkey/SelectionKeyCoreTest::keyboardClipboardParity"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(48, 80), (72, 64), (96, 40), (144, 80)])
    let document = fixture.document
    let session = fixture.session
    let page = fixture.page
    let grid = PianoGrid(session: session)
    let ruler = RulerMenuPresenter(session: session, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    let existing = document.notes(in: 0).map(\.id)
    guard !existing.isEmpty else {
        report.fail(rangeID, "the lane-range fixture has no competing note selection")
        return
    }
    session.setSelectedNotes(existing)
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 48, endTick: 144), scope: .lanes,
        lanes: [fixture.panLane]))
    report.expectEqual(expected: Tick(48), actual: session.timeSelection?.range.startTick,
                       cppID: rangeID, what: "A013 the committed lane range starts at tick 48")
    report.expectEqual(expected: Tick(144), actual: session.timeSelection?.range.endTick,
                       cppID: rangeID, what: "A013 the committed lane range ends at tick 144")
    report.expect(session.timeSelection?.scope == .lanes, cppID: rangeID,
                  message: "A013 the committed selection has lanes scope")
    report.expectEqual(expected: Set([fixture.panLane]), actual: session.timeSelection?.lanes,
                       cppID: rangeID, what: "A013 the committed scope contains only Pan")
    report.expect(session.selectedNotes.isEmpty, cppID: rangeID,
                  message: "A013 committing the lane range replaces selected notes")
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 96, endTick: 144), scope: .lanes,
        lanes: [fixture.panLane]))
    let destination = Tick(96 + grid.snapTicks)
    router.perform(.nudgeRight)
    report.expect(fixture.lanePoints(fixture.panLane).contains { $0.tick == destination && $0.value == 40 },
                  cppID: moveID, message: "A033 Right moves the covered Pan point to the snapped destination")
    report.expect(fixture.lanePoints(fixture.panLane).allSatisfy { $0.tick != 96 },
                  cppID: moveID, message: "A033 Right removes the point from its original tick")
    report.expectEqual(expected: destination, actual: session.timeSelection?.range.startTick,
                       cppID: moveID, what: "A033 Right translates the interval start by the same delta")
    report.expectEqual(expected: Tick(144) + destination - Tick(96),
                       actual: session.timeSelection?.range.endTick, cppID: moveID,
                       what: "A033 Right translates the interval end by the same delta")

    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    page.clearTimeSelection()
    guard let source = document.notes(in: 0).first(where: { $0.tick == 0 }) else {
        report.fail(pasteID, "the roll-copy source note at tick zero is unavailable")
        return
    }
    session.setSelectedNotes([source.id])
    router.perform(.copy)
    session.setSelectedNotes([])
    session.editCursor = 7680
    router.perform(.paste)
    report.expect(document.notes(in: 0).contains { $0.tick == 7680 && $0.pitch == 60 },
                  cppID: pasteID,
                  message: "A041 keyboard Paste lands the roll-copied pitch-60 note at the committed cursor")
}
