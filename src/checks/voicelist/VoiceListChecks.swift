import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

// MARK: - Voice List Model Checks
//
// Runnable Swift predicates for the VoicegroupBrowser list contract,
// mirrored from the retired native oracle (src/checks/voicegroupsave,
// src/ui/voicegroupbrowser.cpp). cppIDs reuse the native test names where a
// direct predicate correspondence exists; swiftcore/VoiceListController::*
// IDs mark predicates the native suite never asserted (characterized here
// from the oracle source).

/// A bank view exercising every row-rendering branch: each editable macro
/// family, a blank slot, a read-only voice, a broken line, and a synth
/// symbol.
private func voiceListFixtureSlots() -> [BankSlotView] {
    var slots = (0..<128).map { _ in BankSlotView() }
    slots[0] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.directSound, symbol: "DirectSoundWaveData_fixture_loop",
        attack: 255, decay: 180, sustain: 200, release: 72))
    slots[1] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.square1, sweep: 0x22, duty: 2,
        attack: 2, decay: 3, sustain: 12, release: 4))
    slots[2] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.square1Alt, duty: 1,
        attack: 15, decay: 8, sustain: 31, release: 15))
    slots[3] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.keysplit, symbol: "fixture_keys",
        keysplitTable: "keysplit_fixture"))
    slots[4] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.keysplitAll, symbol: "fixture_drums_a"))
    slots[5] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.noise, period: 1,
        attack: 2, decay: 2, sustain: 10, release: 3))
    slots[6] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.programmableWave, symbol: "ProgrammableWaveData_pulse",
        attack: 2, decay: 3, sustain: 12, release: 4))
    slots[7] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.directSoundAlt, symbol: "DirectSoundWaveData_drum",
        attack: 255, decay: 96, sustain: 160, release: 48))
    slots[8] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.directSound, symbol: "DirectSoundSynth_GoldenSun_Saw",
        attack: 255, decay: 0, sustain: 255, release: 165))
    slots[9] = BankSlotView(kind: BankSlotKind.editable, voice: BankVoice(
        macro: BankVoiceMacro.directSoundNoResample, symbol: "DirectSoundWaveData_bass",
        attack: 224, decay: 128, sustain: 192, release: 80))
    slots[10] = BankSlotView(kind: BankSlotKind.readOnlyVoice,
                             tone: BankTone(name: "missing_cry_sample", type: 0x20,
                                            isSynth: false,
                                            adsr: BankToneAdsr(attack: 255, decay: 0,
                                                               sustain: 255, release: 0)))
    slots[11] = BankSlotView(kind: BankSlotKind.broken,
                             tone: BankTone(name: "fixture_keys", type: 0x40,
                                            isSynth: false, adsr: nil))
    // slots[12..] stay BankSlotKind.none (blank templates).
    return slots
}

@MainActor
internal func boundVoiceList() -> VoiceListController {
    let list = VoiceListController()
    list.synthSymbols = ["DirectSoundSynth_GoldenSun_Saw"]
    list.bindBank(slots: voiceListFixtureSlots(), dirty: false, loadName: "test_vg")
    return list
}

@MainActor
internal func runVoiceListChecks(_ report: CheckReport) {
    voiceListStableRows(report)
    voiceListRowRendering(report)
    voiceListLoadingOverlay(report)
    voiceListSelector(report)
    voiceListSelectionAndReveal(report)
    voiceListUsedMarks(report)
    voiceListAuditionIntents(report)
    voiceListNarrowRefresh(report)
    voiceListDraftsAndEditIntents(report)
}
/// voiceChanged is the narrow refresh: the owner hands over the changed
/// slot's new view and only that row re-derives — undo/redo and
/// owner-applied edits never rebuild the list.
@MainActor
private func voiceListNarrowRefresh(_ report: CheckReport) {
    let cppID = "swiftcore/VoiceListController::voiceChangedRefresh"
    let list = boundVoiceList()

    let voice = BankVoice(macro: BankVoiceMacro.directSound, key: 60,
                          symbol: "DirectSoundWaveData_replaced",
                          attack: 10, decay: 20, sustain: 30, release: 40)
    list.voiceChanged(0, slotView: BankSlotView(kind: BankSlotKind.editable, voice: voice))
    report.expectEqual(expected: "000  replaced", actual: list.rows[0].title, cppID: cppID,
                       what: "voiceChanged re-derives the changed row from the new view")
    report.expectEqual(expected: "10 20 30 40", actual: list.rows[0].adsr, cppID: cppID,
                       what: "voiceChanged refreshes the row's ADSR text")
    report.expectEqual(expected: "001  Square 1", actual: list.rows[1].title, cppID: cppID,
                       what: "voiceChanged leaves every other row untouched")

    // The draft seam sees the same swapped view (an owner-applied edit
    // reflects back through the same slot data the row reads).
    report.expectEqual(expected: voice, actual: list.voiceDraft(0)?.voice, cppID: cppID,
                       what: "the swapped slot view feeds the edit draft")
}



/// The 128 stable rows exist for the model's lifetime: binding, loading,
/// and edits rewrite them in place; the list is never rebuilt or resized.
@MainActor
private func voiceListStableRows(_ report: CheckReport) {
    let cppID = "swiftcore/VoiceListController::stableRows"
    let list = VoiceListController()
    report.expectEqual(expected: 128, actual: list.rows.count, cppID: cppID,
                       what: "a fresh list publishes the full 128 rows")
    report.expectEqual(expected: "000", actual: list.rows[0].title, cppID: cppID,
                       what: "an unbound row renders its bare slot number")
    report.expectEqual(expected: "127", actual: list.rows[127].title, cppID: cppID,
                       what: "the last unbound row renders its bare slot number")
    report.expectEqual(expected: -1, actual: list.currentSlot, cppID: cppID,
                       what: "no slot is selected before any selection call")

    // The QListModel holds the same 128 row objects for the model's
    // lifetime; binding, loading, and edits rewrite their fields in place.
    let row0 = list.rows[0]
    let row127 = list.rows[127]
    list.bindBank(slots: voiceListFixtureSlots(), dirty: false, loadName: "test_vg")
    report.expectEqual(expected: 128, actual: list.rows.count, cppID: cppID,
                       what: "binding a bank rewrites rows in place without resizing")
    report.expect(list.rows[0] === row0 && list.rows[127] === row127,
                  cppID: cppID,
                  message: "binding keeps the same row object handles")
    list.setLoading(true)
    report.expectEqual(expected: 128, actual: list.rows.count, cppID: cppID,
                       what: "loading keeps the same 128 stable rows")
    report.expect(list.rows[0] === row0, cppID: cppID,
                  message: "loading rewrites the same row handle in place")
    list.setLoading(false)
    report.expectEqual(expected: 128, actual: list.rows.count, cppID: cppID,
                       what: "leaving loading keeps the same 128 stable rows")
    list.bindBank(slots: nil)
    report.expectEqual(expected: 128, actual: list.rows.count, cppID: cppID,
                       what: "detaching keeps the same 128 stable rows")
    report.expectEqual(expected: "000", actual: list.rows[0].title, cppID: cppID,
                       what: "a detached row renders its bare slot number")
    report.expect(list.rows[0] === row0, cppID: cppID,
                  message: "detaching keeps the same row object handle")
}

/// Row rendering mirrors updateRow: "NNN  name" titles with the
/// DirectSoundWave/Data_ prefix shedding, the Type column's display name
/// and glyph (alt chip, synth, keysplit, drumkit), and the ADSR column's
/// family-masked values.
@MainActor
private func voiceListRowRendering(_ report: CheckReport) {
    let cppID = "vgsavecheck/VoicegroupSaveTest::typeColumnMapsEveryFamily"
    let list = boundVoiceList()

    report.expectEqual(expected: "000  fixture_loop", actual: list.rows[0].title, cppID: cppID,
                       what: "sample rows shed the DirectSoundWaveData_ prefix")
    report.expectEqual(expected: "Sample", actual: list.rows[0].typeName, cppID: cppID,
                       what: "a DirectSound row reads Sample")
    report.expectEqual(expected: VoiceListGlyph.sample, actual: list.rows[0].glyph, cppID: cppID,
                       what: "a DirectSound row carries the sample glyph")
    report.expectEqual(expected: "255 180 200 72", actual: list.rows[0].adsr, cppID: cppID,
                       what: "a DirectSound row shows raw 0-255 ADSR values")

    report.expectEqual(expected: "001  Square 1", actual: list.rows[1].title, cppID: cppID,
                       what: "a symbol-less voice falls back to its type name")
    report.expectEqual(expected: "2 3 12 4", actual: list.rows[1].adsr, cppID: cppID,
                       what: "a CGB row shows masked ADSR values")

    report.expectEqual(expected: "Square 1 (Alt)", actual: list.rows[2].typeName, cppID: cppID,
                       what: "an alt CGB row gains the (Alt) marker")
    report.expectEqual(expected: VoiceListGlyph.square1, actual: list.rows[2].glyph, cppID: cppID,
                       what: "an alt CGB row reuses the family glyph")
    report.expectEqual(expected: true, actual: list.rows[2].altChip, cppID: cppID,
                       what: "an alt CGB row marks the grey chip")
    report.expectEqual(expected: "7 0 15 7", actual: list.rows[2].adsr, cppID: cppID,
                       what: "CGB ADSR values mask to A/D/R 0-7, S 0-15")

    report.expectEqual(expected: "003  fixture_keys", actual: list.rows[3].title, cppID: cppID,
                       what: "a keysplit row shows its sub-voicegroup symbol")
    report.expectEqual(expected: "Keysplit", actual: list.rows[3].typeName, cppID: cppID,
                       what: "a keysplit row keeps the Keysplit type name")
    report.expectEqual(expected: VoiceListGlyph.keysplit, actual: list.rows[3].glyph, cppID: cppID,
                       what: "a keysplit row carries the keysplit glyph")
    report.expectEqual(expected: "", actual: list.rows[3].adsr, cppID: cppID,
                       what: "a keysplit row carries no ADSR text")

    report.expectEqual(expected: "Drumkit", actual: list.rows[4].typeName, cppID: cppID,
                       what: "a keysplit_all row reads Drumkit")
    report.expectEqual(expected: VoiceListGlyph.drumkit, actual: list.rows[4].glyph, cppID: cppID,
                       what: "a keysplit_all row carries the drumkit glyph")
    report.expectEqual(expected: "", actual: list.rows[4].adsr, cppID: cppID,
                       what: "a drumkit row carries no ADSR text")

    report.expectEqual(expected: "Noise", actual: list.rows[5].typeName, cppID: cppID,
                       what: "a noise row reads Noise")
    report.expectEqual(expected: "Wave", actual: list.rows[6].typeName, cppID: cppID,
                       what: "a programmable-wave row reads Wave")
    report.expectEqual(expected: "Sample (reverse)", actual: list.rows[7].typeName, cppID: cppID,
                       what: "a reverse DirectSound row reads Sample (reverse)")
    report.expectEqual(expected: VoiceListGlyph.sampleReverse, actual: list.rows[7].glyph, cppID: cppID,
                       what: "a reverse DirectSound row carries the rotated sample glyph")

    report.expectEqual(expected: "Synth (Golden Sun)", actual: list.rows[8].typeName, cppID: cppID,
                       what: "a synth-symbol row reads Synth (Golden Sun)")
    report.expectEqual(expected: VoiceListGlyph.sample, actual: list.rows[8].glyph, cppID: cppID,
                       what: "a synth row reads as a sample glyph")
    report.expectEqual(expected: "Sample (fixed pitch)", actual: list.rows[9].typeName, cppID: cppID,
                       what: "a no-resample row reads Sample (fixed pitch)")

    report.expectEqual(expected: "010  missing_cry_sample", actual: list.rows[10].title, cppID: cppID,
                       what: "a read-only cry row keeps its loaded tone name")
    report.expectEqual(expected: "Sample", actual: list.rows[10].typeName, cppID: cppID,
                       what: "a cry tone renders the native sample type fallback")
    report.expectEqual(expected: "255 0 255 0", actual: list.rows[10].adsr, cppID: cppID,
                       what: "a read-only tone retains its loaded ADSR")
    report.expectEqual(expected: "011  fixture_keys", actual: list.rows[11].title, cppID: cppID,
                       what: "an unparsed row keeps its loaded tone name")
    report.expectEqual(expected: "Keysplit", actual: list.rows[11].typeName, cppID: cppID,
                       what: "an unparsed keysplit uses its loaded type")
    report.expectEqual(expected: "", actual: list.rows[11].adsr, cppID: cppID,
                       what: "a keysplit loaded tone has no envelope")

    report.expectEqual(expected: "012  [Blank]", actual: list.rows[12].title, cppID: cppID,
                       what: "a blank slot renders the materializable template row")
    report.expectEqual(expected: "", actual: list.rows[12].typeName, cppID: cppID,
                       what: "a blank row publishes no type")
    report.expectEqual(expected: "", actual: list.rows[12].adsr, cppID: cppID,
                       what: "a blank row publishes no ADSR text")

    var minted = voiceListFixtureSlots()
    minted[13] = BankSlotView(
        kind: BankSlotKind.editable,
        voice: BankVoice(macro: BankVoiceMacro.directSound,
                         symbol: "DirectSoundSynth_RuntimeMinted"),
        isSynth: true)
    list.bindBank(slots: minted, loadName: "test_vg")
    report.expectEqual(expected: "Synth (Golden Sun)", actual: list.rows[13].typeName, cppID: cppID,
                       what: "a loader-confirmed minted synth works before catalog persistence")
}

/// The loading overlay fills the stable rows with "NNN  Loading..." and
/// disables the selector in place; audition and voiceChanged are inert;
/// binding nil or clearing loading restores the bound rows.
@MainActor
private func voiceListLoadingOverlay(_ report: CheckReport) {
    let cppID = "swiftcore/VoiceListController::loadingOverlay"
    let list = boundVoiceList()
    list.setCurrentVoicegroupArg("_test_vg")
    var auditions: [(voice: Int, key: Int32, velocity: Int32)] = []
    list.onAuditionVoice = { voice, key, velocity in
        auditions.append((voice, key, velocity))
    }

    list.setLoading(true)
    report.expectEqual(expected: true, actual: list.isLoading, cppID: cppID,
                       what: "setLoading(true) enters the loading overlay")
    report.expectEqual(expected: "000  Loading...", actual: list.rows[0].title, cppID: cppID,
                       what: "loading fills row 0 with the placeholder")
    report.expectEqual(expected: "127  Loading...", actual: list.rows[127].title, cppID: cppID,
                       what: "loading fills row 127 with the placeholder")
    report.expectEqual(expected: "", actual: list.rows[0].typeName, cppID: cppID,
                       what: "loading clears the type cell")
    report.expectEqual(expected: "", actual: list.rows[0].adsr, cppID: cppID,
                       what: "loading clears the ADSR cell")
    report.expectEqual(expected: false, actual: list.selectorEnabled, cppID: cppID,
                       what: "loading disables the selector")
    report.expectEqual(expected: "Loading...", actual: list.selectorText, cppID: cppID,
                       what: "loading shows its placeholder as the selector text")

    list.pressVoice(slot: 0)
    report.expectEqual(expected: 0, actual: auditions.count, cppID: cppID,
                       what: "loading suppresses press-and-hold audition")
    report.expectEqual(expected: -1, actual: list.soundingVoice, cppID: cppID,
                       what: "loading never marks a voice sounding")

    list.voiceChanged(0)
    report.expectEqual(expected: "000  Loading...", actual: list.rows[0].title, cppID: cppID,
                       what: "voiceChanged is ignored while loading")

    list.setLoading(false)
    report.expectEqual(expected: false, actual: list.isLoading, cppID: cppID,
                       what: "setLoading(false) exits the overlay")
    report.expectEqual(expected: "000  fixture_loop", actual: list.rows[0].title, cppID: cppID,
                       what: "leaving loading re-derives the bound rows")
    report.expectEqual(expected: true, actual: list.selectorEnabled, cppID: cppID,
                       what: "leaving loading re-enables the bound selector")
    report.expectEqual(expected: "test_vg", actual: list.selectorText, cppID: cppID,
                       what: "leaving loading restores the standing arg's display text")

    // A nil bind also exits loading (native setSource(nullptr)) and
    // restores the selector text the same way.
    list.setLoading(true)
    list.bindBank(slots: nil)
    report.expectEqual(expected: false, actual: list.isLoading, cppID: cppID,
                       what: "detaching exits the loading overlay")
    report.expectEqual(expected: false, actual: list.selectorEnabled, cppID: cppID,
                       what: "a detached selector stays disabled")
    report.expectEqual(expected: "No song loaded", actual: list.selectorPlaceholder, cppID: cppID,
                       what: "a detached selector shows the no-song placeholder")
    report.expectEqual(expected: "test_vg", actual: list.selectorText, cppID: cppID,
                       what: "detaching restores the standing arg's display text")
}

/// The selector publishes display-name choices, reflects the current arg
/// without emitting, and resolves user commits back to args through the
/// underscore rule — verbatim known args stay addressable.
@MainActor
private func voiceListSelector(_ report: CheckReport) {
    let cppID = "vgsavecheck/VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit"
    let list = boundVoiceList()
    var requested: [String] = []
    list.onVoicegroupChangeRequested = { requested.append($0) }

    list.setVoicegroupChoices(["_test_vg", "_fixture_alt", "128"])
    report.expectEqual(expected: ["test_vg", "fixture_alt", "128"],
                       actual: list.argChoices.asArray.map(\.name),
                       cppID: cppID,
                       what: "choices publish display names with the underscore folded")
    report.expectEqual(expected: ["_test_vg", "_fixture_alt", "128"],
                       actual: list.argChoices.asArray.map(\.arg),
                       cppID: cppID,
                       what: "each choice carries its raw -G arg")
    list.setVoicegroupChoices(["_test_vg", "_fixture_alt", "128"])
    report.expectEqual(expected: ["test_vg", "fixture_alt", "128"],
                       actual: list.argChoices.asArray.map(\.name),
                       cppID: cppID,
                       what: "an unchanged choice list is a no-op")

    list.setCurrentVoicegroupArg("_test_vg")
    report.expectEqual(expected: "test_vg", actual: list.selectorText, cppID: cppID,
                       what: "the current arg displays without its underscore")
    report.expectEqual(expected: 0, actual: requested.count, cppID: cppID,
                       what: "reflecting the current arg never emits a request")

    // A user commit to a different name emits the resolved arg.
    list.selectorText = "fixture_alt"
    list.commitVoicegroupSelection()
    report.expectEqual(expected: ["_fixture_alt"], actual: requested, cppID: cppID,
                       what: "committing a display name emits the underscore arg")

    // The emitted arg now stands; the owner's echo-back is a no-op.
    list.setCurrentVoicegroupArg("_fixture_alt")
    list.selectorText = "fixture_alt"
    list.commitVoicegroupSelection()
    report.expectEqual(expected: ["_fixture_alt"], actual: requested, cppID: cppID,
                       what: "re-committing the standing arg emits nothing")

    // A verbatim known arg stays underscore-less (legacy "128"-style).
    list.selectorText = "128"
    list.commitVoicegroupSelection()
    report.expectEqual(expected: ["_fixture_alt", "128"], actual: requested, cppID: cppID,
                       what: "a verbatim known arg commits without an underscore")

    // A raw pasted arg (leading underscore) passes through untouched.
    list.selectorText = "_test_vg"
    list.commitVoicegroupSelection()
    report.expectEqual(expected: ["_fixture_alt", "128", "_test_vg"], actual: requested, cppID: cppID,
                       what: "a pasted raw arg commits verbatim")

    // Disabled selectors never emit: loading and detach both suppress.
    list.setLoading(true)
    list.selectorText = "other"
    list.commitVoicegroupSelection()
    list.setLoading(false)
    list.bindBank(slots: nil)
    list.selectorText = "other"
    list.commitVoicegroupSelection()
    report.expectEqual(expected: ["_fixture_alt", "128", "_test_vg"], actual: requested, cppID: cppID,
                       what: "loading and detach suppress selector commits")
}

/// selectSlot bounds-checks; revealSlot selects and asks the shell to
/// scroll — the jump-from-context seam the track header and event list use.
@MainActor
private func voiceListSelectionAndReveal(_ report: CheckReport) {
    let cppID = "vgsavecheck/VoicegroupSaveTest::revealsTrackProgramsAndUsedMarks"
    let list = boundVoiceList()

    list.selectSlot(slot: 5)
    report.expectEqual(expected: 5, actual: list.currentSlot, cppID: cppID,
                       what: "selectSlot selects the row")
    list.selectSlot(slot: -1)
    report.expectEqual(expected: 5, actual: list.currentSlot, cppID: cppID,
                       what: "a negative slot is ignored")
    list.selectSlot(slot: 128)
    report.expectEqual(expected: 5, actual: list.currentSlot, cppID: cppID,
                       what: "an out-of-range slot is ignored")

    // revealSlot publishes the scroll intent through the reveal counter
    // (the same pattern SongListPresenter's revealRequest uses); the shell
    // scrolls the row into view on change.
    report.expectEqual(expected: 0, actual: list.revealRequest, cppID: cppID,
                       what: "no reveal is requested before revealSlot")
    list.revealSlot(slot: 9)
    report.expectEqual(expected: 9, actual: list.currentSlot, cppID: cppID,
                       what: "revealSlot selects the revealed row")
    report.expectEqual(expected: 1, actual: list.revealRequest, cppID: cppID,
                       what: "revealSlot bumps the reveal request counter")
    report.expectEqual(expected: 9, actual: list.revealSlotId, cppID: cppID,
                       what: "the reveal request names the row")
    list.revealSlot(slot: 200)
    report.expectEqual(expected: 9, actual: list.currentSlot, cppID: cppID,
                       what: "an out-of-range reveal changes nothing")
    report.expectEqual(expected: 1, actual: list.revealRequest, cppID: cppID,
                       what: "an out-of-range reveal emits no scroll intent")
}

/// Used marks highlight the programs the song references; they rewrite in
/// place, survive row re-derivation, and clear on a bank rebind.
@MainActor
private func voiceListUsedMarks(_ report: CheckReport) {
    let cppID = "vgsavecheck/VoicegroupSaveTest::revealsTrackProgramsAndUsedMarks"
    let list = boundVoiceList()

    list.setUsedVoices([0, 3, 4])
    report.expectEqual(expected: true, actual: list.slotIsMarkedUsed(slot: 0), cppID: cppID,
                       what: "a used program's row is marked")
    report.expectEqual(expected: true, actual: list.slotIsMarkedUsed(slot: 3), cppID: cppID,
                       what: "a used keysplit program's row is marked")
    report.expectEqual(expected: false, actual: list.slotIsMarkedUsed(slot: 1), cppID: cppID,
                       what: "an unused program's row is unmarked")
    report.expectEqual(expected: false, actual: list.slotIsMarkedUsed(slot: 127), cppID: cppID,
                       what: "an out-of-set slot is unmarked")

    list.setUsedVoices([4])
    report.expectEqual(expected: false, actual: list.slotIsMarkedUsed(slot: 0), cppID: cppID,
                       what: "replacing the set clears dropped marks")
    report.expectEqual(expected: true, actual: list.slotIsMarkedUsed(slot: 4), cppID: cppID,
                       what: "replacing the set keeps surviving marks")

    // A live rebind keeps the marks (native setSource clears kUsedRole only
    // on a null view); a nil bind drops them.
    list.bindBank(slots: voiceListFixtureSlots(), dirty: false, loadName: "test_vg")
    report.expectEqual(expected: true, actual: list.slotIsMarkedUsed(slot: 4), cppID: cppID,
                       what: "a live bank rebind keeps the used marks")
    list.bindBank(slots: nil)
    report.expectEqual(expected: false, actual: list.slotIsMarkedUsed(slot: 4), cppID: cppID,
                       what: "a nil bind clears the used marks")
}

