import Foundation
import PorydawApp
import PorydawCore
import PorydawDocument
import PorydawProject

@MainActor
internal func runNewSongWizardChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/NewSongWizard::blankSong"
    let project = SongImportProjectData(
        players: [
            MusicPlayer(name: "MUSIC_PLAYER_BGM", number: 0, trackCount: 16),
            MusicPlayer(name: "MUSIC_PLAYER_SE1", number: 1, trackCount: 3),
        ], voicegroupArgs: ["_existing", "_collision"], canCreateVoicegroup: true)
    var state = NewSongWizardState(project: project, takenLabels: ["taken"])
    report.expectEqual(expected: "New Song", actual: state.windowTitle, cppID: id, what: "blank wizard title")
    report.expect(
        state.label.isEmpty && state.constant.isEmpty && !state.next() && state.page == 0,
        cppID: id, message: "empty name refuses Next")
    report.expect(!state.back(), cppID: id, message: "Back refuses on identity")
    report.expectEqual(
        expected: "Background music (MUSIC_PLAYER_BGM)",
        actual: state.identityPlayerNames[0], cppID: id, what: "identity player role")
    report.expectEqual(
        expected: "existing", actual: state.voicegroupText,
        cppID: id, what: "first existing voicegroup avoids create entry")
    report.expectEqual(
        expected: "(create a new voicegroup for this song)",
        actual: state.voicegroupOptions[0], cppID: id, what: "create entry order")
    _ = state.editLabel("taken")
    report.expectEqual(
        expected: "A song named taken already exists.", actual: state.nameHint,
        cppID: id, what: "taken name hint")
    report.expect(!state.next() && !state.identityComplete, cppID: id, message: "taken name refuses Next")
    report.expectEqual(
        expected: "mus_my_song", actual: state.editLabel("MUS_MY_SONG"),
        cppID: id, what: "whole-edit name folding")
    report.expectEqual(
        expected: "MUS_MY_SONG", actual: state.constant,
        cppID: id, what: "constant derives from name")
    state.editConstant("")
    report.expect(!state.next(), cppID: id, message: "empty constant refuses Next")
    state.editConstant("MY_MANUAL_CONSTANT")
    _ = state.editLabel("mus_another")
    report.expectEqual(
        expected: "MY_MANUAL_CONSTANT", actual: state.constant,
        cppID: id, what: "manual constant survives name change")
    report.expect(
        state.next() && state.page == 1 && !state.next(),
        cppID: id, message: "complete identity advances once to Sound")
    report.expect(
        state.volume == 100 && state.reverb == kDefaultReverb && state.priority == 0
            && state.exactGate && !state.extendedClocks && !state.noCompression,
        cppID: id, message: "Sound defaults")
    state.selectPlayer(1)
    state.selectPlayer(99)
    report.expectEqual(
        expected: 1, actual: state.playerIndex, cppID: id,
        what: "invalid player selection preserves chosen player")
    state.voicegroupText = "(create a new voicegroup for this song)"
    _ = state.editLabel("collision")
    if case .failure(let refusal) = state.finishPlan() {
        report.expectEqual(
            expected: "New Voicegroup", actual: refusal.title,
            cppID: id, what: "collision refusal title")
        report.expectEqual(
            expected: "A voicegroup named voicegroup_collision already exists — pick it from the list instead.",
            actual: refusal.message, cppID: id, what: "collision refusal message")
    } else {
        report.fail(id, "existing voicegroup creation was accepted")
    }
    _ = state.editLabel("mus_another")
    state.volume = 85
    state.reverb = 27
    state.priority = 12
    state.exactGate = false
    state.extendedClocks = true
    state.noCompression = true
    if case .success(let request) = state.finishPlan() {
        report.expect(request.createVoicegroup, cppID: id, message: "create entry selects new voicegroup")
        report.expectEqual(
            expected: "_mus_another", actual: request.config.voicegroupArgument,
            cppID: id, what: "new voicegroup argument")
        report.expectEqual(
            expected: "MY_MANUAL_CONSTANT", actual: request.constant,
            cppID: id, what: "chosen constant")
        report.expectEqual(
            expected: "MUSIC_PLAYER_SE1", actual: request.player,
            cppID: id, what: "selected player")
        report.expect(
            request.config.masterVolume == 85 && request.config.reverb == 27
                && request.config.priority == 12 && !request.config.exactGate
                && request.config.extendedClocks && request.config.noCompression,
            cppID: id, message: "chosen Sound settings enter config")
        report.expectEqual(
            expected: SongFlags.merge(request.config), actual: request.config.rawFlags,
            cppID: id, what: "config flags match selected sound")
        do {
            report.expectEqual(
                expected: try MidiFile.blankSong().encoded(), actual: try request.midi.encoded(),
                cppID: id, what: "blank template MIDI bytes")
        } catch {
            report.fail(id, "blank MIDI encoding failed: \(error)")
        }
    } else {
        report.fail(id, "valid blank song finish was refused")
    }
    state.voicegroupText = "existing"
    if case .success(let request) = state.finishPlan() {
        report.expect(!request.createVoicegroup, cppID: id, message: "existing voicegroup does not create")
        report.expectEqual(
            expected: "_existing", actual: request.config.voicegroupArgument,
            cppID: id, what: "existing voicegroup argument")
    } else {
        report.fail(id, "existing voicegroup finish was refused")
    }
    report.expect(state.back() && state.page == 0, cppID: id, message: "Back returns to identity")
    if case .failure(let refusal) = state.finishPlan() {
        report.expectEqual(
            expected: "New Song", actual: refusal.title,
            cppID: id, what: "premature finish refusal title")
        report.expectEqual(
            expected: "Complete the song identity before finishing.", actual: refusal.message,
            cppID: id, what: "premature finish refusal message")
    } else {
        report.fail(id, "finish accepted on identity page")
    }
    let createOnly = NewSongWizardState(
        project: SongImportProjectData(
            players: project.players, voicegroupArgs: [], canCreateVoicegroup: true), takenLabels: [])
    report.expectEqual(
        expected: "(create a new voicegroup for this song)", actual: createOnly.voicegroupText,
        cppID: id, what: "create-only default")
    let noVoicegroup = NewSongWizardState(
        project: SongImportProjectData(
            players: project.players, voicegroupArgs: [], canCreateVoicegroup: false), takenLabels: [])
    report.expectEqual(
        expected: "", actual: noVoicegroup.voicegroupText,
        cppID: id, what: "no available voicegroup default")
}
