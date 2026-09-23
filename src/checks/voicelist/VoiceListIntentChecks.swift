import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

// Interaction and edit-intent checks; shared fixture lives in VoiceListChecks.swift.

/// Press-and-hold audition emits (voice, 60, 112) on press and
/// (voice, 60, 0) on release; a second press releases the first voice.
@MainActor
internal func voiceListAuditionIntents(_ report: CheckReport) {
    let cppID = "swiftcore/VoiceListController::auditionIntents"
    let list = boundVoiceList()
    var auditions: [(voice: Int, key: Int32, velocity: Int32)] = []
    list.onAuditionVoice = { voice, key, velocity in
        auditions.append((voice, key, velocity))
    }

    list.pressVoice(slot: 2)
    report.expectEqual(2, list.soundingVoice, cppID: cppID,
                       what: "a press marks the voice sounding")
    report.expect(auditions.count == 1 && auditions[0].voice == 2 &&
                      auditions[0].key == 60 && auditions[0].velocity == 112,
                  cppID: cppID,
                  message: "a press auditions the slot at middle C, velocity 112")

    list.pressVoice(slot: 5)
    report.expect(auditions.count == 3 && auditions[1].voice == 2 &&
                      auditions[1].velocity == 0 && auditions[2].voice == 5 &&
                      auditions[2].velocity == 112,
                  cppID: cppID,
                  message: "a second press releases the first voice before sounding")

    list.releaseVoice()
    report.expect(auditions.count == 4 && auditions[3].voice == 5 &&
                      auditions[3].velocity == 0,
                  cppID: cppID,
                  message: "release emits velocity 0 for the sounding voice")
    report.expectEqual(-1, list.soundingVoice, cppID: cppID,
                       what: "release clears the sounding voice")
    list.releaseVoice()
    report.expectEqual(4, auditions.count, cppID: cppID,
                       what: "releasing with nothing sounding emits nothing")

    // Picker browse auditions classify by destination voice and symbol.
    var sampleAuditions: [(symbol: String, kind: VoiceListAuditionKind,
                           adsr: VoiceListAdsr)] = []
    list.onSampleAuditionRequested = { symbol, kind, adsr in
        sampleAuditions.append((symbol, kind, adsr))
    }
    list.keysplitTables = ["fixture_keys": "keysplit_fixture"]
    list.selectSlot(slot: 0) // DirectSound destination: full 0-255 envelope
    list.requestSampleAudition(symbol: "DirectSoundWaveData_other")
    report.expect(sampleAuditions.count == 1 && sampleAuditions[0].kind == .sample &&
                      sampleAuditions[0].adsr == VoiceListAdsr(attack: 255, decay: 180,
                                                             sustain: 200, release: 72),
                  cppID: "vgsavecheck/VoicegroupSaveTest::samplePickerAuditionsAndCommits",
                  message: "a sample browse audition carries the destination's envelope")

    list.selectSlot(slot: 6) // wave destination: masked CGB envelope
    list.requestSampleAudition(symbol: "ProgrammableWaveData_other")
    report.expect(sampleAuditions.count == 2 && sampleAuditions[1].kind == .wave &&
                      sampleAuditions[1].adsr == VoiceListAdsr(attack: 2, decay: 3,
                                                             sustain: 12, release: 4),
                  cppID: "vgsavecheck/VoicegroupSaveTest::samplePickerWaveModeAuditionsAndCommits",
                  message: "a wave browse audition carries the masked CGB envelope")

    list.selectSlot(slot: 3) // keysplit destination: no envelope of its own
    list.requestSampleAudition(symbol: "fixture_keys")
    report.expect(sampleAuditions.count == 3 && sampleAuditions[2].kind == .keysplit &&
                      sampleAuditions[2].adsr == VoiceListAdsr(),
                  cppID: "vgsavecheck/VoicegroupSaveTest::samplePickerKeysplitAuditions",
                  message: "a keysplit browse audition leaves the envelope default")

    var stops = 0
    list.onSampleAuditionStopRequested = { stops += 1 }
    list.stopSampleAudition()
    report.expectEqual(1, stops, cppID: cppID,
                       what: "the picker stop intent reaches the owner")
}

/// Drafts mirror voiceDraft: editable slots edit in place, blank slots
/// materialize a template, read-only/broken slots have none. Edit intents
/// carry the structural flag (materialization or macro/symbol change).
@MainActor
internal func voiceListDraftsAndEditIntents(_ report: CheckReport) {
    let cppID = "vgsavecheck/VoicegroupSaveTest::blankTemplateMaterializesUndoably"
    let list = boundVoiceList()
    list.sampleChoices = ["DirectSoundWaveData_first"]
    list.adsrDefaults = VoiceListAdsrDefaults(
        byFamily: [BankVoiceMacro.directSound: VoiceListAdsr(attack: 250, decay: 1,
                                                           sustain: 240, release: 90)])

    let editable = list.voiceDraft(0)
    report.expect(editable != nil && !editable!.materializesBlank &&
                      editable!.voice.symbol == "DirectSoundWaveData_fixture_loop",
                  cppID: cppID,
                  message: "an editable slot drafts its published voice in place")

    let blank = list.voiceDraft(12)
    report.expect(blank != nil && blank!.materializesBlank,
                  cppID: cppID,
                  message: "a blank slot drafts a materializing template")
    report.expectEqual("DirectSoundWaveData_first", blank?.voice.symbol ?? "", cppID: cppID,
                       what: "the blank template adopts the first sample symbol")
    report.expectEqual(Int32(250), blank?.voice.attack ?? -1, cppID: cppID,
                       what: "the blank template adopts the project-typical envelope")
    report.expectEqual(Int32(90), blank?.voice.release ?? -1, cppID: cppID,
                       what: "the blank template adopts the typical release")

    report.expect(list.voiceDraft(10) == nil, cppID: cppID,
                  message: "a read-only slot has no draft")
    report.expect(list.voiceDraft(11) == nil, cppID: cppID,
                  message: "a broken slot has no draft")
    report.expect(list.voiceDraft(200) == nil, cppID: cppID,
                  message: "an uncovered slot has no draft")

    var edits: [(slot: Int, voice: BankVoice, structural: Bool)] = []
    list.onVoiceEditRequested = { slot, voice, structural in
        edits.append((slot, voice, structural))
    }

    // Scalar poke: same macro and symbol — not structural.
    var scalar = list.voiceDraft(0)!.voice
    scalar.release = 100
    list.requestVoiceEdit(slot: 0, voice: scalar)
    report.expect(edits.count == 1 && edits[0].slot == 0 && !edits[0].structural,
                  cppID: "vgsavecheck/VoicegroupSaveTest::releaseEditorUsesBankUndoPipeline",
                  message: "a scalar edit emits a non-structural request")

    // Symbol change: structural.
    var symbol = list.voiceDraft(0)!.voice
    symbol.symbol = "DirectSoundWaveData_other"
    list.requestVoiceEdit(slot: 0, voice: symbol)
    report.expect(edits.count == 2 && edits[1].structural,
                  cppID: cppID,
                  message: "a symbol change emits a structural request")

    // Blank materialization: always structural.
    list.requestVoiceEdit(slot: 12, voice: list.voiceDraft(12)!.voice)
    report.expect(edits.count == 3 && edits[2].slot == 12 && edits[2].structural,
                  cppID: cppID,
                  message: "a blank materialization emits a structural request")

    // Unchanged and draft-less requests emit nothing.
    list.requestVoiceEdit(slot: 0, voice: list.voiceDraft(0)!.voice)
    list.requestVoiceEdit(slot: 10, voice: BankVoice())
    report.expectEqual(3, edits.count, cppID: cppID,
                       what: "unchanged and draft-less edits emit no request")

    // The edit path requires an explicit session binding: a bank-bound
    // list without bindSession/refresh refuses applyVoiceEdit instead of
    // silently editing nothing.
    var unboundEditError: String = ""
    do {
        _ = try runBlocking {
            try await list.applyVoiceEdit(slot: 0, voice: scalar)
        }
    } catch {
        unboundEditError = "\(error)"
    }
    report.expect(!unboundEditError.isEmpty, cppID: cppID,
                  message: "applyVoiceEdit without a bound session fails explicitly")

    // Intent emission only; the owner flows (dialog, file writes, undoable
    // assignment) stay NATIVE with the shell.
    var newVoicegroups = 0
    var newSamples: [Int] = []
    var editSamples: [Int] = []
    list.onNewVoicegroupRequested = { newVoicegroups += 1 }
    list.onNewSampleRequested = { newSamples.append($0) }
    list.onEditSampleRequested = { editSamples.append($0) }
    list.requestNewVoicegroup()
    list.requestNewSample(slot: 0)
    list.requestEditSample(slot: 0)
    report.expectEqual(1, newVoicegroups,
                       cppID: "vgsavecheck/VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably",
                       what: "the New Voicegroup intent reaches the owner")
    report.expectEqual([0], newSamples, cppID: cppID,
                       what: "the New Sample intent carries the slot")
    report.expectEqual([0], editSamples, cppID: cppID,
                       what: "the Edit Sample intent carries the slot")
}
