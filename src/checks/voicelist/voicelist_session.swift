import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawDocument
import PorydawPlayback

// MARK: - Voice List Session Checks
//
// The VoiceListController bound to a real DocumentSession: the published
// bank view drives the 128 rows, applyVoiceEdit routes through
// DocumentSession.applyBankEdit (canonical undo/history), refresh(from:)
// re-derives rows/selector/used marks after bank and document changes, and
// undo restores prior observable state. Mirrors the retired native oracle's
// owner-driven flow (WorkspaceUi::rebuildVoicegroupPresentation).

@MainActor
internal func runVoiceListSessionChecks(_ report: CheckReport) {
    let bindingID = "vgsavecheck/VoicegroupSaveTest::revealsTrackProgramsAndUsedMarks"
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(bindingID, "missing --swiftcore fixture root")
        return
    }
    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-voicelist-test")
    let alternate = URL(fileURLWithPath: projectDir)
        .appendingPathComponent("sound/voicegroups/other.inc")
    let groupIndex = URL(fileURLWithPath: projectDir)
        .appendingPathComponent("sound/voice_groups.inc")
    do {
        try """
        .align 2
        voice_group other
            voice_square_2 60, 0, 1, 3, 2, 11, 4
        """.write(to: alternate, atomically: true, encoding: .utf8)
        let index = try String(contentsOf: groupIndex, encoding: .utf8)
        try (index + "\n.include \"sound/voicegroups/other.inc\"\n")
            .write(to: groupIndex, atomically: true, encoding: .utf8)
    } catch {
        report.fail(bindingID, "alternate voicegroup fixture failed: \(error)")
        return
    }
    let service = ProjectService()
    do {
        try runBlocking {
            try await service.open(root: projectDir)
        }
    } catch {
        report.fail(bindingID, "project open failed: \(error)")
        return
    }
    var session: DocumentSession!
    let catalogArgs: [String]
    do {
        catalogArgs = try runBlocking { try await service.voicegroupArgs() }
    } catch {
        report.fail(bindingID, "voicegroup catalog failed: \(error)")
        return
    }
    report.expect(
        catalogArgs.contains("_other") && catalogArgs.count >= 2,
        cppID: "vgsavecheck/VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit",
        message: "the staged selector catalog offers both original and alternate groups")
    do {
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
    } catch {
        report.fail(bindingID, "session open failed: \(error)")
        return
    }

    let list = VoiceListController()
    let bankViewID = "voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates"
    let originalRow = list.rows[0]
    list.refresh(from: session)

    // The staged test_vg binds: three editable CGB voices, then blanks.
    report.expectEqual(
        expected: 128, actual: list.rows.count, cppID: bindingID,
        what: "a bound session publishes the full 128 rows")
    report.expectEqual(
        expected: true, actual: list.isBound, cppID: bindingID,
        what: "the session's bank view binds the list")
    report.expectEqual(
        expected: "000  Square 1", actual: list.rows[0].title, cppID: bindingID,
        what: "slot 0 renders the fixture's square_1 voice")
    report.expectEqual(
        expected: "2 3 12 4", actual: list.rows[0].adsr, cppID: bindingID,
        what: "slot 0 shows the fixture's CGB envelope")
    report.expectEqual(
        expected: "Square 2", actual: list.rows[1].typeName, cppID: bindingID,
        what: "slot 1 renders the fixture's square_2 voice")
    report.expectEqual(
        expected: "Noise", actual: list.rows[2].typeName, cppID: bindingID,
        what: "slot 2 renders the fixture's noise voice")
    report.expectEqual(
        expected: "003  [Blank]", actual: list.rows[3].title, cppID: bindingID,
        what: "slot 3 renders the blank template row")
    report.expectEqual(
        expected: "test_vg", actual: list.selectorText, cppID: bindingID,
        what: "the selector reflects the song's -G arg as a display name")
    report.expectEqual(
        expected: true, actual: list.selectorEnabled, cppID: bindingID,
        what: "a bound selector is enabled")
    report.expectEqual(
        expected: false, actual: list.bankDirty, cppID: bindingID,
        what: "a freshly opened bank is clean")
    let assigned = Set(
        session.timeline.tracks.filter { $0.used && $0.firstProgram >= 0 }
            .map(\.firstProgram))
    report.expect(
        (0..<128).allSatisfy { list.slotIsMarkedUsed(slot: $0) == assigned.contains($0) },
        cppID: bindingID,
        message: "used marks match the assigned programs and clear on undo")
    if let track = session.timeline.tracks.indices.first(where: {
        session.timeline.tracks[$0].used && session.timeline.tracks[$0].firstProgram >= 0
    }) {
        let program = session.timeline.tracks[track].firstProgram
        list.selectSlot(slot: 12)
        let beforeReveal = list.revealRequest
        list.revealTrackVoice(track: track, session: session)
        report.expect(
            list.currentSlot == program && list.revealSlotId == program
                && list.revealRequest == beforeReveal + 1,
            cppID: bindingID,
            message: "revealing a track voice selects its program")
    }
    list.revealSlot(slot: 2)
    report.expect(
        list.currentSlot == 2 && list.revealSlotId == 2,
        cppID: bindingID, message: "revealing a voice selects its row")

    // Used marks derive from the document: the fixture song references no
    // programs, then a voice lane point marks its program, and undo clears
    // it — the native addLanePoint/undo flow.
    report.expectEqual(
        expected: false, actual: list.slotIsMarkedUsed(slot: 9), cppID: bindingID,
        what: "an unreferenced program starts unmarked")
    session.document.writeLane(
        track: 0, lane: .voice, from: 480, through: 480,
        points: [LaneWrite(tick: 480, value: 9)])
    list.refreshUsedVoices(from: session)
    report.expectEqual(
        expected: true, actual: list.slotIsMarkedUsed(slot: 9), cppID: bindingID,
        what: "a voice lane point marks its program used")
    report.expect(
        list.slotIsMarkedUsed(slot: 9)
            && (0..<128).allSatisfy {
                list.slotIsMarkedUsed(slot: $0) == (assigned.contains($0) || $0 == 9)
            }, cppID: bindingID,
        message: "used marks include voice-lane programs beside track programs")
    if session.timeline.tracks[0].firstProgram < 0 {
        let prior = list.revealRequest
        list.revealTrackVoice(track: 0, session: session)
        report.expect(
            list.currentSlot == 9 && list.revealSlotId == 9
                && list.revealRequest == prior + 1,
            cppID: bindingID,
            message: "a track without an initial program reveals its first voice-lane point")
    }
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(bindingID, "voice-lane undo threw: \(error)")
        return
    }
    list.refreshUsedVoices(from: session)
    report.expectEqual(
        expected: false, actual: list.slotIsMarkedUsed(slot: 9), cppID: bindingID,
        what: "voice-lane undo clears the used mark")
    report.expect(
        (0..<128).allSatisfy {
            list.slotIsMarkedUsed(slot: $0) == assigned.contains($0)
        }, cppID: bindingID,
        message: "voice-lane undo restores precisely the assigned-program used set")
    let revealBeforeInvalid = list.revealRequest
    list.revealTrackVoice(track: -1, session: session)
    list.revealTrackVoice(track: 16, session: session)
    report.expect(
        list.revealRequest == revealBeforeInvalid, cppID: bindingID,
        message: "unmapped track reveal leaves the dock selection untouched")

    let songFileBeforeBankEdit = session.document.state.file
    let songDirtyBeforeBankEdit = session.document.isDirty
    let historyIndexBeforeBankEdit = session.document.history.undoIndex
    // applyVoiceEdit routes through DocumentSession.applyBankEdit: the
    // canonical service apply plus undoable history action.
    let editID = "vgsavecheck/VoicegroupSaveTest::releaseEditorUsesBankUndoPipeline"
    guard let original = session.bankSlots[0].voice else {
        report.fail(editID, "fixture slot 0 has no editable voice")
        return
    }
    var edited = original
    edited.release = original.release < 255 ? original.release + 1 : original.release - 1
    do {
        _ = try runBlocking {
            try await list.applyVoiceEdit(slot: 0, voice: edited)
        }
    } catch {
        report.fail(editID, "applyVoiceEdit threw: \(error)")
        return
    }
    report.expectEqual(
        expected: true, actual: session.bankDirty, cppID: editID,
        what: "a committed voice edit dirties the bank")
    report.expectEqual(
        expected: edited, actual: session.bankSlots[0].voice, cppID: editID,
        what: "a committed voice edit lands in the published bank")
    report.expect(
        session.document.state.file == songFileBeforeBankEdit,
        cppID: editID,
        message: "a bank edit leaves song content unchanged")
    report.expect(
        session.document.isDirty == songDirtyBeforeBankEdit && session.bankDirty,
        cppID: editID,
        message: "a bank edit preserves song dirtiness while dirtying the bank")
    report.expect(
        session.document.history.undoIndex == historyIndexBeforeBankEdit + 1,
        cppID: editID,
        message: "the bank edit appends one history entry without mutating song content")
    // Rows are explicit-refresh: the model holds the pre-edit row until the
    // owner's change seam calls refresh (DocumentSession.onChange stays
    // single-subscriber, owned by DocumentWorkspace).
    report.expectEqual(
        expected: "2 3 12 4", actual: list.rows[0].adsr, cppID: editID,
        what: "rows hold the pre-edit state until refresh")
    list.refresh(from: session)
    report.expect(
        list.rows[0] === originalRow && list.bankDirty
            && list.panelTitle == "Voicegroup*",
        cppID: bankViewID,
        message: "bank edit republishes the dirty view on the same voice row handle")
    report.expectEqual(
        expected: "2 3 12 \(edited.release & 7)", actual: list.rows[0].adsr, cppID: editID,
        what: "refresh re-derives the edited row")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(editID, "voice edit undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(
        list.rows[0] === originalRow && !list.bankDirty
            && list.panelTitle == "Voicegroup",
        cppID: bankViewID,
        message: "bank undo republishes the clean view on the same voice row handle")
    report.expectEqual(
        expected: original, actual: session.bankSlots[0].voice, cppID: editID,
        what: "voice edit undo restores the published voice")
    report.expectEqual(
        expected: "2 3 12 4", actual: list.rows[0].adsr, cppID: editID,
        what: "voice edit undo restores the row")

    let blankID = "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably"
    report.expect(
        list.voiceDraft(3)?.materializesBlank == true, cppID: blankID, message: "fixture slot 3 is a blank draft")
    guard let draft = list.voiceDraft(3), draft.materializesBlank else {
        return
    }
    do {
        _ = try runBlocking {
            try await list.applyVoiceEdit(slot: 3, voice: draft.voice)
        }
    } catch {
        report.fail(blankID, "blank materialization threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expectEqual(
        expected: draft.voice, actual: session.bankSlots[3].voice, cppID: blankID,
        what: "a blank slot materializes the template voice")
    report.expectEqual(
        expected: "003  Sample", actual: list.rows[3].title, cppID: blankID,
        what: "the materialized row renders its type-named title")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(blankID, "blank materialization undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(
        session.bankSlots[3].voice == nil, cppID: blankID,
        message: "materialization undo returns the slot to blank")
    report.expectEqual(
        expected: "003  [Blank]", actual: list.rows[3].title, cppID: blankID,
        what: "the reverted row renders the blank template again")
    do {
        _ = try runBlocking { try await session.redo() }
    } catch {
        report.fail(blankID, "blank materialization redo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(
        session.bankSlots[3].voice == draft.voice
            && list.rows[3].title == "003  Sample" && !session.document.isDirty,
        cppID: blankID,
        message: "the blank template materializes again on redo without dirtying the song")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(blankID, "blank redo cleanup threw: \(error)")
        return
    }
    list.refresh(from: session)
    let pickerID = "vgsavecheck/VoicegroupSaveTest::samplePickerKeysplitAuditions"
    var auditions: [(String, VoiceListAuditionKind, VoiceListAdsr)] = []
    var stops = 0
    list.onSampleAuditionRequested = { symbol, kind, adsr in
        auditions.append((symbol, kind, adsr))
    }
    list.onSampleAuditionStopRequested = { stops += 1 }
    list.selectSlot(slot: 0)
    let committedSymbol = session.bankSlots[0].voice?.symbol
    list.requestSampleAudition(symbol: "DirectSoundWaveData_fixture_bass")
    report.expect(
        committedSymbol != nil && session.bankSlots[0].voice?.symbol == committedSymbol,
        cppID: pickerID,
        message: "first-row audition leaves the selected bank slot symbol unchanged")
    var sample = draft.voice
    sample.attack = 240
    sample.decay = 180
    sample.sustain = 100
    sample.release = 165
    var previewSlots = session.bankSlots
    previewSlots[3] = BankSlotView(kind: BankSlotKind.editable, voice: sample)
    list.bindBank(slots: previewSlots, dirty: false, loadName: session.bankLoadName)
    list.selectSlot(slot: 3)
    list.requestSampleAudition(symbol: "DirectSoundWaveData_fixture_loop")
    report.expect(
        auditions.last?.0 == "DirectSoundWaveData_fixture_loop"
            && auditions.last?.1 == .sample
            && auditions.last?.2
                == VoiceListAdsr(
                    attack: 240, decay: 180,
                    sustain: 100, release: 165),
        cppID: pickerID,
        message: "sample audition carries the selected DirectSound voice envelope")
    list.keysplitTables["fixture_bass"] = "fixture_bass_table"
    list.requestSampleAudition(symbol: "fixture_bass")
    report.expect(
        auditions.last?.1 == .keysplit && auditions.last?.2 == VoiceListAdsr(),
        cppID: pickerID,
        message: "keysplit and wave auditions carry their kind and the voice envelope")
    var wave = sample
    wave.macro = BankVoiceMacro.programmableWave
    wave.attack = 15
    wave.decay = 10
    wave.sustain = 31
    wave.release = 9
    previewSlots[3] = BankSlotView(kind: BankSlotKind.editable, voice: wave)
    list.bindBank(slots: previewSlots, dirty: false, loadName: session.bankLoadName)
    list.requestSampleAudition(symbol: "ProgrammableWaveData_fixture_pulse")
    report.expect(
        auditions.last?.1 == .wave
            && auditions.last?.2
                == VoiceListAdsr(
                    attack: 7, decay: 2,
                    sustain: 15, release: 1),
        cppID: pickerID,
        message: "wave audition masks the selected CGB envelope to its hardware range")
    list.stopSampleAudition()
    report.expect(
        stops == 1, cppID: pickerID,
        message: "closing the picker stops the current sample audition")
    let glyphs: [VoiceListGlyph] = [
        .sample, .sampleReverse, .square1, .square2,
        .wave, .noise, .keysplit, .drumkit,
    ]
    report.expect(
        Set(
            glyphs.map {
                VoiceListSemantics.iconKey(glyph: $0, altChip: false)
            }
        ).count == 8, cppID: bindingID,
        message: "distinct families carry distinct glyphs")
    list.refresh(from: session)

    let selectorID = "vgsavecheck/VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit"
    let originalBankLease = session.bankLease
    list.setVoicegroupChoices(catalogArgs)
    var selectionError: Error?
    list.onVoicegroupChangeRequested = { arg in
        do {
            try runBlocking { try await session.selectVoicegroup(arg) }
        } catch {
            selectionError = error
        }
        list.refresh(from: session)
    }
    list.selectorText = "other"
    list.commitVoicegroupSelection()
    report.expect(
        selectionError == nil
            && session.document.state.config.voicegroupArgument == "_other",
        cppID: selectorID,
        message: "p: the selector commit resolves display text to the alternate arg")
    report.expect(
        list.rows[0] === originalRow
            && list.rows[0].title == "000  Square 2",
        cppID: bankViewID,
        message: "voicegroup rebind publishes the alternate voice on the original row handle")
    report.expectEqual(
        expected: true, actual: session.document.isDirty, cppID: selectorID,
        what: "the selected -G marks the song config dirty")
    report.expectEqual(
        expected: "other", actual: list.selectorText, cppID: selectorID,
        what: "selected -G name reflects the undoable config")
    report.expectEqual(
        expected: "other", actual: session.bankLoadName, cppID: selectorID,
        what: "the selected -G loads the alternate bank")
    report.expect(
        !session.bankLease.sharesBank(with: originalBankLease)
            && session.bankSlots[0].voice?.macro == BankVoiceMacro.square2,
        cppID: selectorID,
        message: "the alternate bank owns a fresh lease and different voice")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(selectorID, "-G undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(
        list.rows[0] === originalRow
            && list.rows[0].title == "000  Square 1",
        cppID: bankViewID,
        message: "voicegroup undo rebind restores the original voice on the original row handle")
    report.expectEqual(
        expected: "test_vg", actual: list.selectorText, cppID: selectorID,
        what: "-G undo restores the original selector")
    report.expectEqual(
        expected: "test_vg", actual: session.bankLoadName, cppID: selectorID,
        what: "-G undo restores the original loaded bank")
    report.expectEqual(
        expected: false, actual: session.document.isDirty, cppID: selectorID,
        what: "-G undo clears the song config dirty state")
    report.expectEqual(
        expected: original, actual: session.bankSlots[0].voice, cppID: selectorID,
        what: "-G undo restores the original slot's instrument")
    let beforeFailedSelection = session.document.history.undoIndex
    list.selectorText = "porydaw_missing_voicegroup"
    list.commitVoicegroupSelection()
    report.expect(
        selectionError.map { String(describing: $0).contains("_porydaw_missing_voicegroup") } == true,
        cppID: selectorID,
        message: "missing voicegroup selector publishes the load failure with its argument")
    report.expect(
        session.document.state.config.voicegroupArgument == "_porydaw_missing_voicegroup"
            && list.selectorText == "porydaw_missing_voicegroup"
            && session.document.isDirty
            && session.document.history.undoIndex == beforeFailedSelection + 1,
        cppID: selectorID,
        message: "failed voicegroup selector records the edited song cfg as one dirty undo step")
    report.expect(
        session.bankLease.sharesBank(with: originalBankLease)
            && session.bankSlots[0].voice == original,
        cppID: selectorID,
        message: "failed voicegroup selector retains the previous bank lease and voice")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(selectorID, "missing -G undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(
        session.document.state.config.voicegroupArgument == "_test_vg"
            && list.selectorText == "test_vg"
            && session.bankLease.sharesBank(with: originalBankLease)
            && !session.document.isDirty,
        cppID: selectorID,
        message: "undo of failed voicegroup selector restores the clean home binding")
    let originID = "swiftcore/VoiceEditorController::queuedOriginSurvivesTabRebind"
    let second: DocumentSession
    do {
        second = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test2")
        }
    } catch {
        report.fail(originID, "second session open failed: \(error)")
        return
    }
    guard let firstVoice = session.bankSlots[0].voice,
        let secondVoice = second.bankSlots[0].voice
    else {
        report.fail(originID, "both sessions need editable slot zero")
        return
    }
    let originalHistory = session.document.history.currentIdentity
    let secondUndoIndex = second.document.history.undoIndex
    list.refresh(from: session)
    list.selectSlot(slot: 0)
    let editor = list.editor
    let staleRelease = firstVoice.release == 7 ? 6 : firstVoice.release + 1
    editor.change(field: "release", value: Int(staleRelease))
    editor.changeType(macro: Int(BankVoiceMacro.square2), symbol: "")
    list.refresh(from: second)
    let committedRelease = secondVoice.release == 7 ? 6 : secondVoice.release + 1
    var expectedVoice = secondVoice
    expectedVoice.release = committedRelease
    editor.change(field: "release", value: Int(committedRelease))
    do {
        try runBlocking {
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if second.bankSlots[0].voice?.release == committedRelease
                    && second.document.history.undoIndex == secondUndoIndex + 1
                    && !second.document.history.bankTransitionInFlight
                {
                    return
                }
                await Task.yield()
            }
            throw RunBlockingError.timeout
        }
    } catch {
        report.fail(originID, "same-origin queued edit did not complete: \(error)")
        return
    }
    report.expectEqual(
        expected: originalHistory, actual: session.document.history.currentIdentity, cppID: originID,
        what: "discarded queued edits leave the original document history unchanged")
    report.expect(
        session.bankSlots[0].voice == expectedVoice && second.bankSlots[0].voice == expectedVoice,
        cppID: originID,
        message: "the valid peer edit publishes its full voice to both live bank views")
    report.expectEqual(
        expected: secondVoice.macro, actual: second.bankSlots[0].voice?.macro, cppID: originID,
        what: "queued type edit cannot retarget the other tab's slot")
    report.expectEqual(
        expected: committedRelease, actual: second.bankSlots[0].voice?.release, cppID: originID,
        what: "same-origin edit commits after discarded earlier requests")
    do {
        let undone = try runBlocking { try await second.undo() }
        report.expect(
            undone, cppID: originID,
            message: "same-origin queued edit is undoable after history publication")
    } catch {
        report.fail(originID, "same-origin edit undo threw: \(error)")
        return
    }
    report.expectEqual(
        expected: secondVoice, actual: second.bankSlots[0].voice, cppID: originID,
        what: "undo restores the second tab's original voice")
    runVoiceListNewVoicegroupChecks(report, fixtureRoot: fixtureRoot)
}

// MARK: - New Voicegroup Prompt Checks
//
// The mounted New Voicegroup flow at the controller level: prompt gates,
// collision refusal, accept binds _name undoably with a bank rebind, and one
// undo restores the home binding while the created files remain.

@MainActor
internal func runVoiceListNewVoicegroupChecks(_ report: CheckReport, fixtureRoot: String) {
    let flowID = "vgsavecheck/VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably"
    let projectDir = stageTestProject(in: fixtureRoot, projectName: "swiftcore-voicelist-newvg")
    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: projectDir) }
    } catch {
        report.fail(flowID, "project open failed: \(error)")
        return
    }
    var session: DocumentSession!
    do {
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_session_test")
        }
    } catch {
        report.fail(flowID, "session open failed: \(error)")
        return
    }
    let homeArg = session.document.state.config.voicegroupArgument
    let homeLoad = session.bankLoadName
    let gateID = "swiftcore/VoiceListNewVoicegroup::promptGates"
    let orphan = VoiceListController()
    var orphanFailures: [String] = []
    orphan.onNewVoicegroupFailed = { orphanFailures.append($0) }
    orphan.presentNewVoicegroup()
    report.expect(
        !orphan.newVoicegroupPrompt && orphanFailures.isEmpty, cppID: gateID,
        message: "present refuses silently with no bound session")
    let list = VoiceListController()
    list.projectService = service
    list.refresh(from: session)
    do {
        list.setVoicegroupChoices(try runBlocking { try await service.voicegroupArgs() })
    } catch {
        report.fail(flowID, "voicegroup catalog failed: \(error)")
        return
    }
    list.setLoading(true)
    list.presentNewVoicegroup()
    report.expect(
        !list.newVoicegroupPrompt, cppID: gateID,
        message: "present refuses silently while the bank is loading")
    list.setLoading(false)
    var failures: [String] = []
    list.onNewVoicegroupFailed = { failures.append($0) }
    var statuses: [String] = []
    list.onStatusMessage = { statuses.append($0) }
    list.presentNewVoicegroup()
    report.expect(
        list.newVoicegroupPrompt && list.newVoicegroupName.isEmpty
            && list.newVoicegroupCopyLabel == "test_vg.inc", cppID: flowID,
        message: "A032: requestNewVoicegroup opens the prompt with its name and copy source")
    list.newVoicegroupName = "draft"
    list.presentNewVoicegroup()
    report.expect(
        list.newVoicegroupName == "draft", cppID: gateID,
        message: "present is a no-op while the prompt is already open")
    report.expect(
        !list.isValidVoicegroupName(name: "9bad") && !list.isValidVoicegroupName(name: "")
            && list.isValidVoicegroupName(name: "vgsave_created"), cppID: flowID,
        message: "A033: the prompt gates Create on the fork name rule with its copy source")
    report.expect(
        !list.newVoicegroupNameAvailable(name: "test_vg")
            && list.newVoicegroupNameAvailable(name: "vgsave_created"), cppID: gateID,
        message: "the prompt reports colliding names as unavailable")
    list.newVoicegroupName = "test_vg"
    let hubURL = URL(fileURLWithPath: projectDir).appendingPathComponent("sound/voice_groups.inc")
    let hubBeforeCollision = (try? Data(contentsOf: hubURL)) ?? Data()
    list.acceptNewVoicegroup()
    let hubAfterCollision = (try? Data(contentsOf: hubURL)) ?? Data()
    report.expect(
        failures.last?.contains("test_vg") == true && list.newVoicegroupPrompt
            && session.document.state.config.voicegroupArgument == homeArg
            && hubAfterCollision == hubBeforeCollision, cppID: gateID,
        message: "a colliding name refuses with its message and writes nothing")
    list.cancelNewVoicegroup()
    list.presentNewVoicegroup()
    list.newVoicegroupName = "9bad"
    list.acceptNewVoicegroup()
    report.expect(
        (failures.last?.isEmpty == false) && list.newVoicegroupPrompt
            && session.document.state.config.voicegroupArgument == homeArg, cppID: gateID,
        message: "an invalid name refuses through the failure seam and writes nothing")
    list.cancelNewVoicegroup()
    list.presentNewVoicegroup()
    list.newVoicegroupName = "vgsave_created"
    list.acceptNewVoicegroup()
    do {
        try runBlocking {
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if session.document.state.config.voicegroupArgument == "_vgsave_created"
                    && list.bankLoadName == "vgsave_created"
                {
                    return
                }
                await Task.yield()
            }
            throw RunBlockingError.timeout
        }
    } catch {
        report.fail(flowID, "accept did not bind the created group: \(error)")
        return
    }
    let createdPath = URL(fileURLWithPath: projectDir)
        .appendingPathComponent("sound/voicegroups/vgsave_created.inc").path
    report.expect(
        session.document.state.config.voicegroupArgument == "_vgsave_created"
            && FileManager.default.fileExists(atPath: createdPath)
            && session.bankLease.id.sourceRelativePath.hasSuffix("vgsave_created.inc"), cppID: flowID,
        message: "A034: accept creates the per-file group and binds _vgsave_created")
    report.expect(
        session.document.isDirty, cppID: flowID,
        message: "A035: the created binding marks the document dirty")
    report.expect(
        statuses == ["Created sound/voicegroups/vgsave_created.inc and assigned it to mus_session_test."],
        cppID: gateID,
        message: "success publishes the fork status line naming the file and song")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(flowID, "creation undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(
        session.document.state.config.voicegroupArgument == homeArg, cppID: flowID,
        message: "A036: one undo restores the home -G binding")
    report.expect(
        session.bankLoadName == homeLoad
            && session.bankLease.id.sourceRelativePath.hasSuffix("test_vg.inc"), cppID: flowID,
        message: "A037: undo restores the home bank lease")
    let hub =
        (try? String(
            contentsOf: URL(fileURLWithPath: projectDir)
                .appendingPathComponent("sound/voice_groups.inc"), encoding: .utf8)) ?? ""
    report.expect(
        FileManager.default.fileExists(atPath: createdPath)
            && hub.contains("sound/voicegroups/vgsave_created.inc"), cppID: gateID,
        message: "undo keeps the created file and hub line: creation is a project op")
}
