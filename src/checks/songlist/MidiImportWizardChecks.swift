import Foundation
import PorydawApp
import PorydawCore
import PorydawProject

@MainActor
internal func runMidiImportWizardChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "onboardcheck/OnboardingTest::importWizard"
    for (previous, proposed, expected) in [
        ("", "MUS_Loud_3", "mus_loud_3"),
        ("", "mus 3!", ""),
        ("mu", "mu$", "mu"),
        ("mu", "9mu", "mu"),
        ("abc", "", ""),
    ] {
        report.expectEqual(
            expected: expected,
            actual: SongListPresenter.acceptSongLabelEdit(previous: previous, proposed: proposed),
            cppID: id, what: "whole edit \(String(reflecting: proposed)) from \(String(reflecting: previous))")
    }

    guard let path = CheckEnvironment.fixturePath("test_midis/external_import.mid") else {
        report.fail(id, "external_import.mid fixture is missing")
        return
    }
    do {
        let source = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
        let project = SongImportProjectData(
            players: [
                MusicPlayer(name: "MUSIC_PLAYER_BGM", number: 0, trackCount: 16),
                MusicPlayer(name: "MUSIC_PLAYER_SE1", number: 1, trackCount: 3),
                MusicPlayer(name: "MUSIC_PLAYER_SE_1TRK", number: 2, trackCount: 1),
            ], voicegroupArgs: ["_fixture_alt", "_fixture_rich"], canCreateVoicegroup: true)
        var state = MidiImportWizardState(
            source: source, sourceFileName: "external_import.mid",
            project: project, takenLabels: ["mus_route101"])
        report.expectEqual(
            expected: "Import MIDI — external_import.mid", actual: state.windowTitle,
            cppID: id, what: "opening title")
        report.expectEqual(
            expected: "mus_external_import", actual: state.label,
            cppID: id, what: "suggested name")
        report.expectEqual(
            expected: "MUS_EXTERNAL_IMPORT", actual: state.constant,
            cppID: id, what: "derived constant")
        report.expect(
            state.offersRescale && state.rescale, cppID: id,
            message: "non-24 division offers and defaults rescale on")
        report.expectEqual(
            expected: "Background music", actual: state.analysisPlayerNames[0],
            cppID: id, what: "analysis combo first role")
        report.expectEqual(
            expected: "Background music (MUSIC_PLAYER_BGM)",
            actual: state.identityPlayerNames[0], cppID: id,
            what: "identity combo first role and symbol")
        report.expectEqual(
            expected: "fixture_alt", actual: state.voicegroupText,
            cppID: id, what: "first existing voicegroup default")
        report.expectEqual(
            expected: "(create a new voicegroup for this song)",
            actual: state.voicegroupOptions[0], cppID: id, what: "create choice first")
        report.expect(
            state.controllerRows.allSatisfy { $0.controller.hasPrefix("CC ") || $0.controller == "XCMD" },
            cppID: id, message: "controller rows use CC or XCMD column labels")
        state.selectPlayer(2)
        report.expectEqual(
            expected: 2, actual: state.playerIndex, cppID: id,
            what: "identity and analysis player selection")
        report.expect(
            state.summary.summary.contains("mute"), cppID: id,
            message: "single-track role mutes the imported overflow")
        state.selectPlayer(99)
        report.expectEqual(
            expected: 2, actual: state.playerIndex, cppID: id,
            what: "out-of-bounds player does not change selection")
        report.expect(!state.back(), cppID: id, message: "cannot back before analysis")
        report.expect(state.next(), cppID: id, message: "analysis advances to identity")
        _ = state.editLabel("mus_route101")
        report.expectEqual(
            expected: "A song named mus_route101 already exists.",
            actual: state.nameHint, cppID: id, what: "registered name hint")
        report.expect(
            !state.next() && state.page == 1, cppID: id,
            message: "taken name blocks sound page")
        _ = state.editLabel("mus_external_import")
        state.editConstant("MY_IMPORT")
        _ = state.editLabel("mus_another")
        report.expectEqual(
            expected: "MY_IMPORT", actual: state.constant,
            cppID: id, what: "manual constant survives name edit")
        _ = state.editLabel("mus_external_import")
        report.expect(
            state.next() && !state.next() && state.page == 2,
            cppID: id, message: "sound page is upper bound")
        report.expect(
            state.volume == 100 && state.reverb == 50 && state.priority == 0 && state.exactGate && !state.extendedClocks
                && !state.noCompression,
            cppID: id, message: "fork sound defaults")
        state.voicegroupText = "(create a new voicegroup for this song)"
        _ = state.editLabel("fixture_alt")
        if case .failure(let refusal) = state.finishPlan() {
            report.expectEqual(
                expected: "New Voicegroup", actual: refusal.title,
                cppID: id, what: "collision warning title")
            report.expectEqual(
                expected: "A voicegroup named voicegroup_fixture_alt already exists — pick it from the list instead.",
                actual: refusal.message, cppID: id, what: "collision warning text")
        } else {
            report.fail(id, "existing voicegroup creation was accepted")
        }
        _ = state.editLabel("mus_external_import")
        if case .success(let plan) = state.finishPlan() {
            report.expectEqual(
                expected: "_mus_external_import", actual: plan.config.voicegroupArgument,
                cppID: id, what: "new voicegroup argument")
            report.expect(plan.createVoicegroup, cppID: id, message: "new voicegroup planned")
        } else {
            report.fail(id, "new voicegroup plan was refused")
        }
        state.voicegroupText = "fixture_alt"
        if case .success(let plan) = state.finishPlan() {
            report.expectEqual(
                expected: ["-E", "-R50", "-G_fixture_alt", "-V100"],
                actual: plan.config.rawFlags, cppID: id, what: "explicit sound cfg flags")
            report.expect(!plan.createVoicegroup, cppID: id, message: "existing voicegroup plan")
        } else {
            report.fail(id, "existing voicegroup plan was refused")
        }
        report.expect(
            state.back() && state.page == 1 && state.back() && state.page == 0 && !state.back(),
            cppID: id, message: "back steps within page bounds")
        var division24 = source
        division24.division = 24
        let noRescale = MidiImportWizardState(
            source: division24, sourceFileName: "external_import.mid",
            project: project, takenLabels: [])
        report.expect(
            !noRescale.offersRescale && !noRescale.rescale,
            cppID: id, message: "division-24 file does not offer rescale")
    } catch {
        report.fail(id, "wizard fixture read or decode failed: \(error)")
    }
}
