#include "checkcatalog.h"

#include "fixturecatalog.hpp"
#include "fwd.hpp"
#include "mainwindow.h"

#include <initializer_list>

namespace checks::detail {
namespace {

QStringList strings(std::initializer_list<const char *> values)
{
    auto result = QStringList{};
    result.reserve(qsizetype(values.size()));
    for (const auto *value : values)
        result.push_back(QString::fromUtf8(value));
    return result;
}

QString optional(const QStringList &arguments, qsizetype index)
{
    return index < arguments.size() ? arguments[index] : QString{};
}

} // namespace

const std::vector<CheckDefinition> &catalog()
{
    static const auto definitions = [] {
        const auto decompProjectFiles = fixtures::decompProjectFiles();
        const auto decompMidiFiles = fixtures::decompMidiFiles();
        const auto richVoicegroupFiles = fixtures::richVoicegroupFiles();
        const auto voicegroupEditorFiles = fixtures::voicegroupEditorFiles();
        const auto route101Files =
            decompProjectFiles + strings({"sound/songs/midi/mus_route101.mid"});
        const auto route101RichFiles = route101Files + richVoicegroupFiles;
        const auto twoSongRichFiles =
            decompProjectFiles +
            strings({"sound/songs/midi/mus_route101.mid", "sound/songs/midi/mus_petalburg.mid"}) +
            richVoicegroupFiles + strings({"sound/voicegroups/fixture_alt.inc"});
        return std::vector<CheckDefinition>{
            {.name = "production-startup",
             .argv = strings({"--version"}),
             .binary = BinaryKind::Application,
             .startup = StartupKind::HandlerOwned},
            {.name = "roundtrip",
             .argv = strings({"--roundtrip", "{scratch}", "{mid2agb}"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runRoundTrip(args[1], args[2]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "editcheck",
             .argv = strings({"--editcheck", "{scratch}"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runEditCheck(args[1]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "scalecheck",
             .argv = strings({"--scalecheck", "{scratch}"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runScaleCheck(args[1]); },
             .scratchKind = ScratchKind::ExistingDirectory},
            {.name = "viewcheck",
             .argv = strings({"--viewcheck", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runViewCheck(args[1], optional(args, 2), optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "selftest",
             .argv = strings({"--selftest", "{scratch}", "mus_littleroot_test"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     auto window = MainWindow{};
                     window.show();
                     return window.runSelfTest(args[1], args[2]) ? 0 : 1;
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles +
                             strings({"sound/songs/midi/mus_littleroot_test.mid"}) +
                             richVoicegroupFiles},
            {.name = "savecheck",
             .argv = strings({"--savecheck", "{scratch}", "mus_route101", "{mid2agb}"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runSaveCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "onboardcheck",
             .argv = strings({"--onboardcheck", "{scratch}", "{mid2agb}"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runOnboardCheck(args[1], optional(args, 2));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({
                                                      "sound/music_player_table.inc",
                                                      "include/constants/songs.h",
                                                      "ld_script.ld",
                                                      "charmap.txt",
                                                      "src/debug.c",
                                                      "sound/voice_groups.inc",
                                                      "sound/voicegroups/dummy.inc",
                                                      "test_midis/external_import.mid",
                                                      "test_midis/duplicate_setters.mid",
                                                  })},
            {.name = "vgcheck",
             .argv = strings({"--vgcheck", "{scratch}", "mus_gym"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runVgCheck(args[1], args[2]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgsavecheck",
             .argv = strings({"--vgsavecheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runVgSaveCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 route101Files + voicegroupEditorFiles + strings({"data/sound_data.s"})},
            {.name = "exportcheck-loop",
             .argv = strings({"--exportcheck", "{scratch}", "mus_route101"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runExportCheck(args[1], args[2]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101RichFiles},
            {.name = "exportcheck-tail",
             .argv = strings({"--exportcheck", "{scratch}", "mus_route102"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runExportCheck(args[1], args[2]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_route102.mid"}) +
                             richVoicegroupFiles},
            {
                .name = "projectiocheck",
                .argv = strings({"--projectiocheck", "{scratch}"}),
                .handler = [](QApplication &,
                              const QStringList &args) { return runProjectIoCheck(args[1]); },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = decompProjectFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "sessioncheck",
                .argv = strings({"--sessioncheck", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runSessionCheck(args[1], args[2]);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {
                .name = "tabcheck",
                .argv = strings({"--tabcheck", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runTabCheck(args[1], args[2], args[3]);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {.name = "eventviewcheck",
             .argv = strings({"--eventviewcheck", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runEventViewCheck(args[1], optional(args, 2), optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "rollcheck",
             .argv = strings({"--rollcheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runRollCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "rollwindowingcheck",
             .argv = strings({"--rollwindowingcheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runRollWindowingCheck(args[1], args[2]);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "mkcheck",
             .argv = strings({"--mkcheck", "{scratch}", "mus_aqua_magma_hideout"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runMkCheck(args[1], args[2]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::SongsMkProject,
             .fixtureFiles = strings({"sound/song_table.inc", "songs.mk"})},
            {.name = "loopcheck",
             .argv = strings({"--loopcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runLoopCheck(); }},
            {.name = "ignorecheck",
             .argv = strings({"--ignorecheck", "{scratch}"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runIgnoreCheck(args[1]); },
             .scratchKind = ScratchKind::MustNotExistPath},
            {.name = "primecheck",
             .argv = strings({"--primecheck"}),
             .handler = [](QApplication &, const QStringList &) { return runPrimeCheck(); }},
            {.name = "xcmdcheck",
             .argv = strings({"--xcmdcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runXcmdCheck(); }},
            {.name = "smfcheck",
             .argv = strings({"--smfcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runSmfCheck(); }},
            {.name = "transportcheck",
             .argv = strings({"--transportcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runTransportCheck(); }},
            {
                .name = "audiocheck",
                .argv = strings({"--audiocheck"}),
                .handler = [](QApplication &, const QStringList &) { return runAudioCheck(); },
            },
            {
                .name = "clickcheck",
                .argv = strings({"--clickcheck"}),
                .handler = [](QApplication &, const QStringList &) { return runClickCheck(); },
            },
            {.name = "resonancecheck",
             .argv = strings({"--resonancecheck"}),
             .handler = [](QApplication &, const QStringList &) { return runResonanceCheck(); }},
            {.name = "trackactivitycheck",
             .argv = strings({"--trackactivitycheck"}),
             .handler = [](QApplication &,
                           const QStringList &) { return runTrackActivityCheck(); }},
            {.name = "trackactivitymetercheck",
             .argv = strings({"--trackactivitymetercheck"}),
             .handler = [](QApplication &,
                           const QStringList &) { return runTrackActivityMeterCheck(); }},
            {.name = "trackactivitymetercheck-fractional-dpr",
             .argv = strings({"--trackactivitymetercheck"}),
             .handler = [](QApplication &,
                           const QStringList &) { return runTrackActivityMeterCheck(); },
             .environment = {{QStringLiteral("QT_SCALE_FACTOR"), QStringLiteral("1.5")}}},
            {.name = "keymapcheck",
             .argv = strings({"--keymapcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runKeymapCheck(); }},
            {
                .name = "selectioncheck",
                .argv = strings({"--selectioncheck"}),
                .handler = [](QApplication &, const QStringList &) { return runSelectionCheck(); },
            },
            {
                .name = "laneselectioncheck",
                .argv = strings({"--laneselectioncheck"}),
                .handler = [](QApplication &,
                              const QStringList &) { return runLaneSelectionCheck(); },
            },
            {
                .name = "clipmimecheck",
                .argv = strings({"--clipmimecheck"}),
                .handler = [](QApplication &, const QStringList &) { return runClipMimeCheck(); },
            },
            {
                .name = "clipcheck",
                .argv = strings({"--clipcheck"}),
                .handler = [](QApplication &, const QStringList &) { return runClipCheck(); },
            },
            {
                .name = "polycheck",
                .argv = strings({"--polycheck"}),
                .handler = [](QApplication &,
                              const QStringList &args) { return runPolyCheck(optional(args, 1)); },
            },
            {.name = "samplecheck",
             .argv = strings({"--samplecheck", "{scratch}", "{sample-corpus?}"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runSampleCheck(args[1], optional(args, 2), optional(args, 3));
                 },
             .scratchKind = ScratchKind::MustNotExistPath,
             .optionalArgumentEnvironment = {{QStringLiteral("{sample-corpus?}"),
                                              QStringLiteral("PORYDAW_SAMPLE_CORPUS")}}},
            {.name = "noteidcheck",
             .argv = strings({"--check-note-identity", "{scratch}"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runNoteIdentityCheck(args[1]); },
             .scratchKind = ScratchKind::ExistingDirectory},
            {
                .name = "host-seams",
                .argv = strings({"--check-host-seams"}),
                .handler = [](QApplication &, const QStringList &) { return runHostSeamsCheck(); },
            },
            {
                .name = "velocity-model",
                .argv = strings({"--check-velocity-model"}),
                .handler = [](QApplication &,
                              const QStringList &) { return runVelocityModelCheck(); },
            },
            {
                .name = "editor-drawer",
                .argv = strings({"--check-editor-drawer"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runEditorDrawerCheck(optional(args, 1));
                    },
            },
            {
                .name = "automation-gestures",
                .argv = strings({"--check-automation-gestures", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runAutomationGestureCheck(args[1], args[2], optional(args, 3));
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "automation-popup-menus",
                .argv = strings({"--check-automation-popup-menus", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runAutomationPopupMenuCheck(args[1], args[2], optional(args, 3));
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "automation",
                .argv = strings({"--check-automation", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runAutomationCheck(args[1], args[2]);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "velocity-page",
                .argv = strings({"--check-velocity-page", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runVelocityPageCheck(args[1], args[2], optional(args, 3));
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "sidecar",
                .argv = strings({"--check-sidecar", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runViewSidecarCheck(args[1], args[2]);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
            },
            {
                .name = "host-adapter",
                .argv = strings({"--check-host-adapter", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runHostAdapterCheck(args[1], args[2]);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "mainwindow-routing",
                .argv = strings(
                    {"--check-mainwindow-routing", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runMainWindowRoutingCheck(args[1], args[2], args[3]);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "rendering-playhead",
                .argv = strings({"--check-rendering-playhead", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runRenderingPlayheadCheck(args[1], args[2], optional(args, 3));
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "host-integration",
                .argv = strings(
                    {"--check-host-integration", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args) {
                        return runHostIntegrationCheck(args[1], args[2], args[3],
                                                       optional(args, 4));
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {.name = "themecheck",
             .argv = strings({"--themecheck"}),
             .handler =
                 [](QApplication &application, const QStringList &args) {
                     return runThemeHarness(application, args[0]);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "fontcheck",
             .argv = strings({"--fontcheck"}),
             .handler =
                 [](QApplication &application, const QStringList &args) {
                     return runThemeHarness(application, args[0]);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "darkbasecheck",
             .argv = strings({"--darkbasecheck"}),
             .handler =
                 [](QApplication &application, const QStringList &args) {
                     return runThemeHarness(application, args[0]);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-12",
             .argv = strings({"--editor-layout-check", "12"}),
             .handler =
                 [](QApplication &application, const QStringList &args) {
                     return runEditorLayoutCheck(application, args[1].toInt());
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-16",
             .argv = strings({"--editor-layout-check", "16"}),
             .handler =
                 [](QApplication &application, const QStringList &args) {
                     return runEditorLayoutCheck(application, args[1].toInt());
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-18",
             .argv = strings({"--editor-layout-check", "18"}),
             .handler =
                 [](QApplication &application, const QStringList &args) {
                     return runEditorLayoutCheck(application, args[1].toInt());
                 },
             .startup = StartupKind::HandlerOwned},
        };
    }();
    return definitions;
}
} // namespace checks::detail
