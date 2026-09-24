import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
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
    report.expect(catalogArgs.contains("_other") && catalogArgs.count >= 2,
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
    list.refresh(from: session)

    // The staged test_vg binds: three editable CGB voices, then blanks.
    report.expectEqual(128, list.rows.count, cppID: bindingID,
                       what: "a bound session publishes the full 128 rows")
    report.expectEqual(true, list.isBound, cppID: bindingID,
                       what: "the session's bank view binds the list")
    report.expectEqual("000  Square 1", list.rows[0].title, cppID: bindingID,
                       what: "slot 0 renders the fixture's square_1 voice")
    report.expectEqual("2 3 12 4", list.rows[0].adsr, cppID: bindingID,
                       what: "slot 0 shows the fixture's CGB envelope")
    report.expectEqual("Square 2", list.rows[1].typeName, cppID: bindingID,
                       what: "slot 1 renders the fixture's square_2 voice")
    report.expectEqual("Noise", list.rows[2].typeName, cppID: bindingID,
                       what: "slot 2 renders the fixture's noise voice")
    report.expectEqual("003  [Blank]", list.rows[3].title, cppID: bindingID,
                       what: "slot 3 renders the blank template row")
    report.expectEqual("test_vg", list.selectorText, cppID: bindingID,
                       what: "the selector reflects the song's -G arg as a display name")
    report.expectEqual(true, list.selectorEnabled, cppID: bindingID,
                       what: "a bound selector is enabled")
    report.expectEqual(false, list.bankDirty, cppID: bindingID,
                       what: "a freshly opened bank is clean")

    // Used marks derive from the document: the fixture song references no
    // programs, then a voice lane point marks its program, and undo clears
    // it — the native addLanePoint/undo flow.
    report.expectEqual(false, list.slotIsMarkedUsed(slot: 9), cppID: bindingID,
                       what: "an unreferenced program starts unmarked")
    session.document.writeLane(track: 0, lane: .voice, from: 480, through: 480,
                               points: [LaneWrite(tick: 480, value: 9)])
    list.refreshUsedVoices(from: session)
    report.expectEqual(true, list.slotIsMarkedUsed(slot: 9), cppID: bindingID,
                       what: "a voice lane point marks its program used")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(bindingID, "voice-lane undo threw: \(error)")
        return
    }
    list.refreshUsedVoices(from: session)
    report.expectEqual(false, list.slotIsMarkedUsed(slot: 9), cppID: bindingID,
                       what: "voice-lane undo clears the used mark")

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
    report.expectEqual(true, session.bankDirty, cppID: editID,
                       what: "a committed voice edit dirties the bank")
    report.expectEqual(edited, session.bankSlots[0].voice, cppID: editID,
                       what: "a committed voice edit lands in the published bank")
    // Rows are explicit-refresh: the model holds the pre-edit row until the
    // owner's change seam calls refresh (DocumentSession.onChange stays
    // single-subscriber, owned by DocumentWorkspace).
    report.expectEqual("2 3 12 4", list.rows[0].adsr, cppID: editID,
                       what: "rows hold the pre-edit state until refresh")
    list.refresh(from: session)
    report.expectEqual("2 3 12 \(edited.release & 7)", list.rows[0].adsr, cppID: editID,
                       what: "refresh re-derives the edited row")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(editID, "voice edit undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expectEqual(original, session.bankSlots[0].voice, cppID: editID,
                       what: "voice edit undo restores the published voice")
    report.expectEqual("2 3 12 4", list.rows[0].adsr, cppID: editID,
                       what: "voice edit undo restores the row")

    // Blank materialization through the same canonical path.
    let blankID = "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably"
    guard let draft = list.voiceDraft(3), draft.materializesBlank else {
        report.fail(blankID, "fixture slot 3 is not a blank draft")
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
    report.expectEqual(draft.voice, session.bankSlots[3].voice, cppID: blankID,
                       what: "a blank slot materializes the template voice")
    report.expectEqual("003  Sample", list.rows[3].title, cppID: blankID,
                       what: "the materialized row renders its type-named title")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(blankID, "blank materialization undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expect(session.bankSlots[3].voice == nil, cppID: blankID,
                  message: "materialization undo returns the slot to blank")
    report.expectEqual("003  [Blank]", list.rows[3].title, cppID: blankID,
                       what: "the reverted row renders the blank template again")

    // A -G selection changes both document history and the real loaded bank.
    let selectorID = "vgsavecheck/VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit"
    let originalToken = session.bankLease.bankToken
    do {
        try runBlocking { try await session.selectVoicegroup("_other") }
    } catch {
        report.fail(selectorID, "-G bank rebind threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expectEqual(true, session.document.isDirty, cppID: selectorID,
                       what: "the selected -G marks the song config dirty")
    report.expectEqual("other", list.selectorText, cppID: selectorID,
                       what: "selected -G name reflects the undoable config")
    report.expectEqual("other", session.bankLoadName, cppID: selectorID,
                       what: "the selected -G loads the alternate bank")
    report.expect(session.bankLease.bankToken != originalToken &&
                      session.bankSlots[0].voice?.macro == BankVoiceMacro.square2,
                  cppID: selectorID,
                  message: "the alternate bank owns a fresh lease and different voice")
    do {
        _ = try runBlocking { try await session.undo() }
    } catch {
        report.fail(selectorID, "-G undo threw: \(error)")
        return
    }
    list.refresh(from: session)
    report.expectEqual("test_vg", list.selectorText, cppID: selectorID,
                       what: "-G undo restores the original selector")
    report.expectEqual("test_vg", session.bankLoadName, cppID: selectorID,
                       what: "-G undo restores the original loaded bank")
    report.expectEqual(false, session.document.isDirty, cppID: selectorID,
                       what: "-G undo clears the song config dirty state")
    report.expectEqual(original, session.bankSlots[0].voice, cppID: selectorID,
                       what: "-G undo restores the original slot's instrument")
}
