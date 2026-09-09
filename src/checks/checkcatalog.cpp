#include "checkcatalog.h"

#include "fixturecatalog.hpp"
#include "fwd.hpp"

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

const QString &argumentAt(const QStringList &arguments, qsizetype index)
{
    static const QString empty;
    return index < arguments.size() ? arguments.at(index) : empty;
}

template <auto Run>
int qtOnly(QApplication &, const QStringList &, const QStringList &qtArgs)
{
    return Run(qtArgs);
}

template <auto Run>
int qtWithApplication(QApplication &application, const QStringList &, const QStringList &qtArgs)
{
    return Run(application, qtArgs);
}

template <auto Run>
int qtWithOneArgument(QApplication &, const QStringList &args, const QStringList &qtArgs)
{
    return Run(argumentAt(args, 1), qtArgs);
}

template <auto Run>
int qtWithTwoArguments(QApplication &, const QStringList &args, const QStringList &qtArgs)
{
    return Run(argumentAt(args, 1), argumentAt(args, 2), qtArgs);
}

template <auto Run>
int qtWithThreeArguments(QApplication &, const QStringList &args, const QStringList &qtArgs)
{
    return Run(argumentAt(args, 1), argumentAt(args, 2), argumentAt(args, 3), qtArgs);
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
        const auto selfTestFiles = decompProjectFiles +
                                   strings({"sound/songs/midi/mus_littleroot_test.mid"}) +
                                   richVoicegroupFiles;
        return std::vector<CheckDefinition>{
            {.name = "production-startup",
             .argv = strings({"--version"}),
             .binary = BinaryKind::Application,
             .startup = StartupKind::HandlerOwned,
             .framework = Framework::Process},
            {.name = "roundtrip",
             .argv = strings({"--roundtrip", "{scratch}", "{mid2agb}"}),
             .handler = qtWithTwoArguments<runRoundTrip>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "editcheck",
             .argv = strings({"--editcheck", "{scratch}"}),
             .handler = [](QApplication &, const QStringList &args,
                           const QStringList &qtArgs) { return runEditCheck(args.mid(1), qtArgs); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "scalecheck",
             .argv = strings({"--scalecheck", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runScaleCheck(args.mid(1), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory},
            {.name = "eventviews-chrome",
             .argv = strings({"--eventviews-chrome"}),
             .handler = qtOnly<runEventViewsChromeCheck>},
            {.name = "selftest-timeline",
             .argv = strings({"--selftest-timeline", "{scratch}", "mus_littleroot_test"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runSelfTestTimelineCheck(args, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = selfTestFiles,
             .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}}},
            {.name = "selftest-transport",
             .argv = strings({"--selftest-transport", "{scratch}", "mus_littleroot_test"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runSelfTestTransportCheck(args, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = selfTestFiles,
             .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}}},
            {.name = "selftest-workspace",
             .argv = strings({"--selftest-workspace", "{scratch}", "mus_littleroot_test"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runSelfTestWorkspaceCheck(args, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = selfTestFiles,
             .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}}},
            {.name = "savecheck",
             .argv = strings({"--savecheck", "{scratch}", "mus_route101", "{mid2agb}"}),
             .handler = qtWithThreeArguments<runSaveCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "onboardcheck",
             .argv = strings({"--onboardcheck", "{scratch}", "{mid2agb}"}),
             .handler = qtWithTwoArguments<runOnboardCheck>,
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
             .handler = qtWithTwoArguments<runVgCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgbankcheck",
             .argv = strings({"--vgbankcheck", "{scratch}", "mus_gym"}),
             .handler = qtWithTwoArguments<runVgBankCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 decompProjectFiles +
                 strings({"sound/songs/midi/mus_gym.mid", "sound/songs/midi/mus_oldale.mid"}) +
                 voicegroupEditorFiles},
            {.name = "vgloadcheck",
             .argv = strings({"--vgloadcheck", "{scratch}"}),
             .handler = qtWithTwoArguments<runVgLoadCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + voicegroupEditorFiles},
            {.name = "vgloadbench",
             .argv = strings({"--vgloadbench", "{scratch}", "mus_gym"}),
             .handler = qtWithTwoArguments<runVgLoadCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgsavecheck",
             .argv = strings({"--vgsavecheck", "{scratch}", "mus_route101"}),
             .handler = qtWithThreeArguments<runVoicegroupSaveCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 route101Files + voicegroupEditorFiles + strings({"data/sound_data.s"})},
            {.name = "exportcheck-loop",
             .argv = strings({"--exportcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runExportCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101RichFiles},
            {.name = "exportcheck-tail",
             .argv = strings({"--exportcheck", "{scratch}", "mus_route102"}),
             .handler = qtWithTwoArguments<runExportCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_route102.mid"}) +
                             richVoicegroupFiles},
            {
                .name = "project-identity",
                .argv = strings({"--project-identity"}),
                .handler = qtOnly<runProjectIdentityCheck>,
            },
            {
                .name = "project-io-flow",
                .argv = strings({"--project-io-flow", "{scratch}"}),
                .handler = qtWithOneArgument<runProjectIoFlowCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "project-io-mutations",
                .argv = strings({"--project-io-mutations", "{scratch}"}),
                .handler = qtWithOneArgument<runProjectIoMutationsCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "projectworkspacecheck",
                .argv = strings({"--projectworkspacecheck", "{scratch}"}),
                .handler = qtWithOneArgument<runProjectWorkspaceCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "sessioncheck",
                .argv = strings({"--sessioncheck", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSessionCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {
                .name = "tabcheck",
                .argv = strings({"--tabcheck", "{scratch}", "mus_route101", "mus_route102"}),
                .handler = qtWithThreeArguments<runTabCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles =
                    route101RichFiles +
                    strings({"sound/songs/midi/mus_route102.mid",
                             "sound/songs/midi/mus_littleroot_test.mid",
                             "sound/songs/midi/mus_oldale.mid", "sound/songs/midi/mus_gym.mid"}),
            },
            {.name = "eventviews-edits",
             .argv = strings({"--eventviews-edits"}),
             .handler = qtOnly<runEventViewsEditsCheck>},
            {.name = "rollcheck",
             .argv = strings({"--rollcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runRollCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "trackheaderquickcheck",
             .argv = strings({"--trackheaderquickcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTrackHeaderQuickCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "trackheader-model",
             .argv = strings({"--trackheader-model", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTrackHeaderModelCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "trackactivitymetercheck",
             .argv = strings({"--trackactivitymetercheck"}),
             .handler = qtOnly<runTrackActivityMeterCheck>},
            {.name = "trackactivitymetercheck-fractional-dpr",
             .argv = strings({"--trackactivitymetercheck"}),
             .handler = qtOnly<runTrackActivityMeterCheck>,
             .environment = {{QStringLiteral("QT_SCALE_FACTOR"), QStringLiteral("1.5")}}},
            {.name = "rollwindowingcheck",
             .argv = strings({"--rollwindowingcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runRollWindowingCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "timelinepancheck",
             .argv = strings({"--timelinepancheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTimelinePanCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "timelinepan-native",
             .argv = strings({"--timelinepan-native", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTimelinePanNativeCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem,
             .optIn = true},
            {
                .name = "rollcheck-static",
                .argv = strings({"--rollcheck-static", "{scratch}", "mus_route101"}),
                .handler =
                    qtWithTwoArguments<checks::rollcheck::staticcheck::runPianoRollStaticCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {.name = "mkcheck",
             .argv = strings({"--mkcheck", "{scratch}", "mus_aqua_magma_hideout"}),
             .handler = qtWithTwoArguments<runMkCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::SongsMkProject,
             .fixtureFiles = strings({"sound/song_table.inc", "songs.mk"})},
            {.name = "loopcheck",
             .argv = strings({"--loopcheck"}),
             .handler = qtOnly<runLoopCheck>},
            {.name = "ignorecheck",
             .argv = strings({"--ignorecheck"}),
             .handler = qtOnly<runIgnoreCheck>,
             .scratchKind = ScratchKind::Unused},
            {.name = "primecheck",
             .argv = strings({"--primecheck"}),
             .handler = qtOnly<runPrimeCheck>},
            {.name = "xcmdcheck",
             .argv = strings({"--xcmdcheck"}),
             .handler = qtOnly<runXcmdCheck>},
            {.name = "smfcheck", .argv = strings({"--smfcheck"}), .handler = qtOnly<runSmfCheck>},
            {.name = "transportcheck",
             .argv = strings({"--transportcheck"}),
             .handler = qtOnly<runTransportCheck>},
            {.name = "voicegroupviewcachecheck",
             .argv = strings({"--voicegroupviewcachecheck"}),
             .handler = qtOnly<runVoicegroupViewCacheCheck>},
            {
                .name = "audiocheck",
                .argv = strings({"--audiocheck"}),
                .handler = qtOnly<runAudioCheck>,
            },
            {
                .name = "audiocheck-backend",
                .argv = strings({"--audiocheck-backend"}),
                .handler = qtOnly<runAudioBackendCheck>,
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            },
            {
                .name = "clickcheck",
                .argv = strings({"--clickcheck"}),
                .handler = qtOnly<runClickCheck>,
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            },
            {.name = "resonancecheck",
             .argv = strings({"--resonancecheck"}),
             .handler = qtOnly<runResonanceCheck>},
            {.name = "resonancecheck-timing",
             .argv = strings({"--resonancecheck-timing"}),
             .handler = qtOnly<runResonanceTimingCheck>},
            {.name = "trackactivitycheck",
             .argv = strings({"--trackactivitycheck"}),
             .handler = qtOnly<runTrackActivityCheck>},
            {.name = "keymapcheck",
             .argv = strings({"--keymapcheck"}),
             .handler = qtOnly<runKeymapCheck>},
            {.name = "selectioncheck",
             .argv = strings({"--selectioncheck"}),
             .handler = qtOnly<runSelectionCheck>},
            {
                .name = "laneselectioncheck",
                .argv = strings({"--laneselectioncheck"}),
                .handler = qtOnly<runLaneSelectionCheck>,
            },
            {
                .name = "clipmimecheck",
                .argv = strings({"--clipmimecheck"}),
                .handler = qtOnly<runClipMimeCheck>,
            },
            {
                .name = "clipcheck",
                .argv = strings({"--clipcheck"}),
                .handler = qtOnly<runClipCheck>,
            },
            {
                .name = "polycheck",
                .argv = strings({"--polycheck"}),
                .handler = qtWithOneArgument<runPolyCheck>,
            },
            {
                .name = "settings-dialog",
                .argv = strings({"--settings-dialog"}),
                .handler = qtOnly<runSettingsDialogCheck>,
            },
            {.name = "samplecheck",
             .argv = strings({"--samplecheck", "{sample-corpus?}"}),
             .handler = qtWithOneArgument<runSampleCheck>,
             .scratchKind = ScratchKind::Unused,
             .optionalArgumentEnvironment = {{QStringLiteral("{sample-corpus?}"),
                                              QStringLiteral("PORYDAW_SAMPLE_CORPUS")}}},
            {.name = "noteidcheck",
             .argv = strings({"--check-note-identity", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runNoteIdentityCheck(args.mid(1), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory},
            {
                .name = "host-seams",
                .argv = strings({"--check-host-seams"}),
                .handler = qtOnly<runHostSeamsCheck>,
            },
            {
                .name = "page-popup-seams",
                .argv = strings({"--page-popup-seams"}),
                .handler = qtOnly<runPagePopupSeamsCheck>,
            },
            {
                .name = "ruler-grid-menu",
                .argv = strings({"--check-ruler-grid-menu"}),
                .handler = qtOnly<runRulerGridMenuCheck>,
            },
            {
                .name = "velocity-model",
                .argv = strings({"--check-velocity-model"}),
                .handler = qtOnly<runVelocityModelCheck>,
            },
            {
                .name = "editor-drawer",
                .argv = strings({"--check-editor-drawer"}),
                .handler = qtOnly<runEditorDrawerCheck>,
            },
            {
                .name = "automation-raster",
                .argv = strings({"--check-automation-raster", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runAutomationRasterCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "velocity-page",
                .argv = strings({"--check-velocity-page", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runVelocityPageCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "scrollbar",
                .argv = strings({"--scrollbar", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runScrollbarCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "velocity-editing",
                .argv = strings({"--velocity-editing"}),
                .handler = qtOnly<runVelocityEditingCheck>,
            },
            {
                .name = "automation-editing",
                .argv = strings({"--automation-editing"}),
                .handler = qtOnly<runAutomationEditingCheck>,
            },
            {
                .name = "automation-domain",
                .argv = strings({"--automation-domain"}),
                .handler = qtOnly<runAutomationDomainCheck>,
            },
            {
                .name = "automation-presentation",
                .argv = strings({"--automation-presentation"}),
                .handler = qtOnly<runAutomationPresentationCheck>,
            },
            {
                .name = "automation-hover",
                .argv = strings({"--automation-hover"}),
                .handler = qtOnly<runAutomationHoverCheck>,
            },
            {
                .name = "host-adapter",
                .argv = strings({"--check-host-adapter", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runHostAdapterCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "mainwindow-routing-input",
                .argv = strings({"--check-mainwindow-routing-input", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler =
                    qtWithThreeArguments<checks::mainwindowrouting::runMainWindowRoutingInputCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "mainwindow-routing-state",
                .argv = strings({"--check-mainwindow-routing-state", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler =
                    qtWithThreeArguments<checks::mainwindowrouting::runMainWindowRoutingStateCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "mainwindow-routing-lifecycle",
                .argv = strings({"--check-mainwindow-routing-lifecycle", "{scratch}",
                                 "mus_route101", "mus_petalburg"}),
                .handler = qtWithThreeArguments<
                    checks::mainwindowrouting::runMainWindowRoutingLifecycleCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "mainwindow-routing-native",
                .argv = strings({"--check-mainwindow-routing-native", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler = qtWithThreeArguments<
                    checks::mainwindowrouting::runMainWindowRoutingNativeCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "selectionkey-core",
                .argv = strings({"--selectionkey-core", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSelectionKeyCoreCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {
                .name = "selectionkey-gesture",
                .argv = strings({"--selectionkey-gesture", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSelectionKeyGestureCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "selectionkey-window",
                .argv = strings(
                    {"--selectionkey-window", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler = qtWithThreeArguments<runSelectionKeyWindowCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "selectionkey-local-input",
                .argv = strings({"--selectionkey-local-input", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSelectionKeyLocalInputCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "selectionkey-page-ownership",
                .argv = strings({"--selectionkey-page-ownership", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler = qtWithThreeArguments<runSelectionPageOwnershipTests>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {.name = "playhead-guides",
             .argv = strings({"--playhead-guides", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runPlayheadGuidesCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {
                .name = "rendering-playhead",
                .argv = strings({"--check-rendering-playhead", "{scratch}", "mus_route101"}),
                .handler = qtWithThreeArguments<runRenderingPlayheadCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "host-integration",
                .argv = strings(
                    {"--check-host-integration", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runHostIntegrationCheck(args[1], args[2], args[3],
                                                       argumentAt(args, 4), qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "eventviews-remap",
                .argv = strings({"--eventviews-remap"}),
                .handler = qtOnly<runEventViewsRemapCheck>,
            },
            {
                .name = "eventviews-playhead",
                .argv = strings({"--eventviews-playhead"}),
                .handler = qtOnly<runEventViewsPlayheadCheck>,
            },
            {
                .name = "view-buckets-grid",
                .argv = strings({"--view-buckets-grid"}),
                .handler = qtOnly<runViewBucketsGridCheck>,
            },
            {.name = "pitch-bend-editing",
             .argv = strings({"--pitch-bend-editing"}),
             .handler = qtOnly<runPitchBendEditingCheck>},
            {.name = "pitch-bend-raster",
             .argv = strings({"--pitch-bend-raster"}),
             .handler = qtOnly<runPitchBendRasterCheck>,
             .windowing = Windowing::WindowSystem},
            {.name = "themecheck",
             .argv = strings({"--themecheck"}),
             .handler = qtWithApplication<runThemeLayoutThemeCheck>,
             .startup = StartupKind::HandlerOwned},
            {.name = "fontcheck",
             .argv = strings({"--fontcheck"}),
             .handler = qtWithApplication<runThemeLayoutFontCheck>,
             .startup = StartupKind::HandlerOwned},
            {.name = "darkbasecheck",
             .argv = strings({"--darkbasecheck"}),
             .handler = qtWithApplication<runThemeLayoutDarkBaseCheck>,
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-12",
             .argv = strings({"--editor-layout-check", "12"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     return runThemeLayoutScaleCheck(application, args[1].toInt(), qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-16",
             .argv = strings({"--editor-layout-check", "16"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     return runThemeLayoutScaleCheck(application, args[1].toInt(), qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-18",
             .argv = strings({"--editor-layout-check", "18"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     return runThemeLayoutScaleCheck(application, args[1].toInt(), qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
        };
    }();
    return definitions;
}
} // namespace checks::detail
