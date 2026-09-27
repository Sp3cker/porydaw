import Foundation

enum ShellQmlRegistry {
    struct Entry {
        let name: String
        let inputFileName: String
        let fixtureFiles: [String]
        /// run_checks.ts windowing: "offscreen", or "window-system" for real
        /// focus/activation delivery (run serially, never beside other windows).
        var windowing = "offscreen"
        /// Qt Quick Test selectors run when the caller passes none, so one
        /// input file can back several entries, each within the harness timeout.
        var testFunctions: [String] = []
    }

    /// The rendered text-contrast audit: one entry per shell state and theme.
    private static let textContrastEntries: [Entry] = ["empty", "song"].flatMap { state in
        ["vanilla", "dark-neutral-high", "immaterial"].map { mode in
            Entry(name: "shell-text-contrast-\(state)-\(mode)",
                  inputFileName: "tst_TextContrast.qml",
                  fixtureFiles: songs("mus_route101"),
                  testFunctions: ["TextContrast::test_\(state)ShellText:\(mode)"])
        }
    }

    /// Project tables, samples and the original `_fixture_rich` voicegroups.
    private static let projectFixture = [
        "sound/song_table.inc",
        "sound/songs/midi/midi.cfg",
        "sound/direct_sound_data.inc",
        "sound/direct_sound_samples/fixture_bass.bin",
        "sound/direct_sound_samples/fixture_drum.bin",
        "sound/direct_sound_samples/fixture_loop.bin",
        "sound/direct_sound_samples/fixture_pluck.bin",
        "sound/programmable_wave_data.inc",
        "sound/programmable_wave_samples/fixture_pulse.pcm",
        "sound/programmable_wave_samples/fixture_saw.pcm",
        "sound/keysplit_tables.inc",
        "sound/voicegroups/fixture_rich.inc",
        "sound/voicegroups/fixture_keys.inc",
        "sound/voicegroups/fixture_bass.inc",
        "sound/voicegroups/fixture_drums_a.inc",
        "sound/voicegroups/fixture_drums_b.inc",
    ]

    private static func songs(_ labels: String...) -> [String] {
        projectFixture + labels.map { "sound/songs/midi/\($0).mid" }
    }

    static let entries = [
        Entry(name: "shellwindow", inputFileName: "tst_ShellWindow.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-cross-tab", inputFileName: "tst_ShellWindowCrossTab.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-drawer", inputFileName: "tst_ShellWindowDrawer.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-shortcuts", inputFileName: "tst_ShellWindowShortcuts.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-editor-keys", inputFileName: "tst_ShellWindowEditorKeys.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-prompts", inputFileName: "tst_ShellWindowPrompts.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-focus", inputFileName: "tst_ShellWindowFocus.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-time-editing", inputFileName: "tst_ShellWindowTimeEditing.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-velocity", inputFileName: "tst_ShellWindowVelocity.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-parameter-keys", inputFileName: "tst_ShellWindowParameterKeys.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-label-commands", inputFileName: "tst_ShellWindowLabelCommands.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shellwindow-hints", inputFileName: "tst_ShellWindowHints.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input-draw", inputFileName: "tst_ShellGridInputDraw.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input-editing", inputFileName: "tst_ShellGridInputEditing.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input-cancel", inputFileName: "tst_ShellGridInputCancel.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input-keyboard", inputFileName: "tst_ShellGridInputKeyboard.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input-automation", inputFileName: "tst_ShellGridInputAutomation.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-pitch-bend-cancellation", inputFileName: "tst_ShellPitchBendCancellation.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-pitch-bend-controls", inputFileName: "tst_ShellPitchBendControls.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-pitch-bend-pointer", inputFileName: "tst_ShellPitchBendPointer.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-pitch-bend-keys", inputFileName: "tst_ShellPitchBendKeys.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-pitch-bend-retarget", inputFileName: "tst_ShellPitchBendRetarget.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu-input-zones", inputFileName: "tst_ShellGridMenuInputZones.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu-note-actions", inputFileName: "tst_ShellGridMenuNoteActions.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu-ruler-lifecycle", inputFileName: "tst_ShellGridMenuRulerLifecycle.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu-ruler-markers", inputFileName: "tst_ShellGridMenuRulerMarkers.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu-ruler-clipboard", inputFileName: "tst_ShellGridMenuRulerClipboard.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu-automation", inputFileName: "tst_ShellGridMenuAutomation.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-clipboard-range", inputFileName: "tst_ShellClipboardRange.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-clipboard-round-trip", inputFileName: "tst_ShellClipboardRoundTrip.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-grid-input", inputFileName: "tst_ShellGridInput.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-pitch-bend", inputFileName: "tst_ShellPitchBend.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-grid-menu", inputFileName: "tst_ShellGridMenu.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-clipboard", inputFileName: "tst_ShellClipboard.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-theme", inputFileName: "tst_Theme.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-typography", inputFileName: "tst_Typography.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-open-failure", inputFileName: "tst_ShellOpenFailure.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-chrome-visuals", inputFileName: "tst_ShellChromeVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-transport", inputFileName: "tst_ShellTransport.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-transport-volume", inputFileName: "tst_ShellTransportVolume.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-transport-session", inputFileName: "tst_ShellTransportSession.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test")),
        Entry(name: "shell-menus-commands", inputFileName: "tst_ShellMenusCommands.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-menus-loop", inputFileName: "tst_ShellMenusLoop.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-note-visuals-detail", inputFileName: "tst_ShellNoteVisualsDetail.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-note-visuals-ruler", inputFileName: "tst_ShellNoteVisualsRuler.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-tabs-mouse-hints", inputFileName: "tst_ShellTabsMouseHints.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-tabs-open-select", inputFileName: "tst_ShellTabsOpenSelect.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-tabs-close", inputFileName: "tst_ShellTabsClose.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-tabs-drawer", inputFileName: "tst_ShellTabsDrawer.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-tabs-bank-lifetime", inputFileName: "tst_ShellTabsBankLifetime.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-tabs-reload", inputFileName: "tst_ShellTabsReload.qml", fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-event-list-menus", inputFileName: "tst_ShellEventListMenus.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-event-list-presentation", inputFileName: "tst_ShellEventListPresentation.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-event-list-keyboard-selection", inputFileName: "tst_ShellEventListKeyboardSelection.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-drawer-parity-automation", inputFileName: "tst_ShellDrawerParityAutomation.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-drawer-parity-voice-velocity", inputFileName: "tst_ShellDrawerParityVoiceVelocity.qml", fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-voicegroup-editing", inputFileName: "tst_ShellVoicegroupEditing.qml", fixtureFiles: songs("mus_route101", "mus_route102") + ["asm/macros/synth_test.inc", "data/sound_data.s", "sound/voicegroups/fixture_alt.inc"]),
        Entry(name: "shell-voicegroup-picker", inputFileName: "tst_ShellVoicegroupPicker.qml", fixtureFiles: songs("mus_route101", "mus_route102") + ["asm/macros/synth_test.inc", "data/sound_data.s", "sound/voicegroups/fixture_alt.inc"]),
        Entry(name: "shell-voicegroup-save", inputFileName: "tst_ShellVoicegroupSave.qml", fixtureFiles: songs("mus_route101", "mus_route102") + ["asm/macros/synth_test.inc", "data/sound_data.s", "sound/voicegroups/fixture_alt.inc"]),
        Entry(name: "shell-menus", inputFileName: "tst_ShellMenus.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-note-visuals", inputFileName: "tst_ShellNoteVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-reticle-visuals", inputFileName: "tst_ShellReticleVisuals.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-tabs", inputFileName: "tst_ShellTabs.qml",
              fixtureFiles: songs("mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym")),
        Entry(name: "shell-songs", inputFileName: "tst_ShellSongs.qml",
              fixtureFiles: songs("mus_route101", "mus_petalburg", "mus_gym", "mus_surf",
                                  "mus_victory_wild", "se_fanfare_1trk", "se_pc_login",
                                  "se_use_item") + ["sound/voicegroups/fixture_alt.inc",
                                                     "include/constants/songs.h"]),
        Entry(name: "shell-event-list", inputFileName: "tst_ShellEventList.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-drawer-parity", inputFileName: "tst_ShellDrawerParity.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-polyphony", inputFileName: "tst_ShellPolyphony.qml",
              fixtureFiles: songs("mus_route101")),
        Entry(name: "shell-voicegroup", inputFileName: "tst_ShellVoicegroup.qml",
              fixtureFiles: songs("mus_route101", "mus_route102") + [
                  "asm/macros/synth_test.inc", "data/sound_data.s",
                  "sound/voicegroups/fixture_alt.inc"
              ]),
        Entry(name: "shell-settings", inputFileName: "tst_ShellSettings.qml",
              fixtureFiles: songs("mus_route101")),
    ] + textContrastEntries
}
