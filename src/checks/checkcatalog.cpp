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
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runRoundTrip(args[1], args[2], qtArgs);
                 },
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
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runEventViewsChromeCheck(qtArgs); }},
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
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runSaveCheck(args[1], args[2], optional(args, 3), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "onboardcheck",
             .argv = strings({"--onboardcheck", "{scratch}", "{mid2agb}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runOnboardCheck(args[1], args.value(2), qtArgs);
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
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runVgCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgbankcheck",
             .argv = strings({"--vgbankcheck", "{scratch}", "mus_gym"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runVgBankCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 decompProjectFiles +
                 strings({"sound/songs/midi/mus_gym.mid", "sound/songs/midi/mus_oldale.mid"}) +
                 voicegroupEditorFiles},
            {.name = "vgloadcheck",
             .argv = strings({"--vgloadcheck", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runVgLoadCheck(args[1], args.value(2), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + voicegroupEditorFiles},
            {.name = "vgloadbench",
             .argv = strings({"--vgloadbench", "{scratch}", "mus_gym"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runVgLoadCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgsavecheck",
             .argv = strings({"--vgsavecheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runVoicegroupSaveCheck(args[1], args[2], optional(args, 3), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 route101Files + voicegroupEditorFiles + strings({"data/sound_data.s"})},
            {.name = "exportcheck-loop",
             .argv = strings({"--exportcheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runExportCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101RichFiles},
            {.name = "exportcheck-tail",
             .argv = strings({"--exportcheck", "{scratch}", "mus_route102"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runExportCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_route102.mid"}) +
                             richVoicegroupFiles},
            {
                .name = "project-identity",
                .argv = strings({"--project-identity"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runProjectIdentityCheck(qtArgs);
                    },
            },
            {
                .name = "project-io-flow",
                .argv = strings({"--project-io-flow", "{scratch}"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runProjectIoFlowCheck(args[1], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "project-io-mutations",
                .argv = strings({"--project-io-mutations", "{scratch}"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runProjectIoMutationsCheck(args[1], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "projectworkspacecheck",
                .argv = strings({"--projectworkspacecheck", "{scratch}"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runProjectWorkspaceCheck(args[1], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "sessioncheck",
                .argv = strings({"--sessioncheck", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runSessionCheck(args[1], args[2], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {
                .name = "tabcheck",
                .argv = strings({"--tabcheck", "{scratch}", "mus_route101", "mus_route102"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runTabCheck(args[1], args[2], args[3], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/songs/midi/mus_route102.mid"}),
            },
            {.name = "eventviews-edits",
             .argv = strings({"--eventviews-edits"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runEventViewsEditsCheck(qtArgs); }},
            {.name = "rollcheck",
             .argv = strings({"--rollcheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runRollCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "trackheaderquickcheck",
             .argv = strings({"--trackheaderquickcheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runTrackHeaderQuickCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "trackactivitymetercheck",
             .argv = strings({"--trackactivitymetercheck"}),
             .handler =
                 [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                     return runTrackActivityMeterCheck(qtArgs);
                 }},
            {.name = "trackactivitymetercheck-fractional-dpr",
             .argv = strings({"--trackactivitymetercheck"}),
             .handler =
                 [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                     return runTrackActivityMeterCheck(qtArgs);
                 },
             .environment = {{QStringLiteral("QT_SCALE_FACTOR"), QStringLiteral("1.5")}}},
            {.name = "rollwindowingcheck",
             .argv = strings({"--rollwindowingcheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runRollWindowingCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "timelinepancheck",
             .argv = strings({"--timelinepancheck", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runTimelinePanCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "timelinepan-native",
             .argv = strings({"--timelinepan-native", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runTimelinePanNativeCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {
                .name = "rollcheck-static",
                .argv = strings({"--rollcheck-static", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return checks::rollcheck::staticcheck::runPianoRollStaticCheck(
                            args[1], args[2], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {.name = "mkcheck",
             .argv = strings({"--mkcheck", "{scratch}", "mus_aqua_magma_hideout"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runMkCheck(args[1], args[2], qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::SongsMkProject,
             .fixtureFiles = strings({"sound/song_table.inc", "songs.mk"})},
            {.name = "loopcheck",
             .argv = strings({"--loopcheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runLoopCheck(qtArgs); }},
            {.name = "ignorecheck",
             .argv = strings({"--ignorecheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runIgnoreCheck(qtArgs); },
             .scratchKind = ScratchKind::Unused},
            {.name = "primecheck",
             .argv = strings({"--primecheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runPrimeCheck(qtArgs); }},
            {.name = "xcmdcheck",
             .argv = strings({"--xcmdcheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runXcmdCheck(qtArgs); }},
            {.name = "smfcheck",
             .argv = strings({"--smfcheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runSmfCheck(qtArgs); }},
            {.name = "transportcheck",
             .argv = strings({"--transportcheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runTransportCheck(qtArgs); }},
            {.name = "voicegroupviewcachecheck",
             .argv = strings({"--voicegroupviewcachecheck"}),
             .handler =
                 [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                     return runVoicegroupViewCacheCheck(qtArgs);
                 }},
            {
                .name = "audiocheck",
                .argv = strings({"--audiocheck"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runAudioCheck(qtArgs); },
            },
            {
                .name = "audiocheck-backend",
                .argv = strings({"--audiocheck-backend"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runAudioBackendCheck(qtArgs); },
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            },
            {
                .name = "clickcheck",
                .argv = strings({"--clickcheck"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runClickCheck(qtArgs); },
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            },
            {.name = "resonancecheck",
             .argv = strings({"--resonancecheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runResonanceCheck(qtArgs); }},
            {.name = "resonancecheck-timing",
             .argv = strings({"--resonancecheck-timing"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runResonanceTimingCheck(qtArgs); }},
            {.name = "trackactivitycheck",
             .argv = strings({"--trackactivitycheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runTrackActivityCheck(qtArgs); }},
            {.name = "keymapcheck",
             .argv = strings({"--keymapcheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runKeymapCheck(qtArgs); }},
            {.name = "selectioncheck",
             .argv = strings({"--selectioncheck"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runSelectionCheck(qtArgs); }},
            {
                .name = "laneselectioncheck",
                .argv = strings({"--laneselectioncheck"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runLaneSelectionCheck(qtArgs); },
            },
            {
                .name = "clipmimecheck",
                .argv = strings({"--clipmimecheck"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runClipMimeCheck(qtArgs); },
            },
            {
                .name = "clipcheck",
                .argv = strings({"--clipcheck"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runClipCheck(qtArgs); },
            },
            {
                .name = "polycheck",
                .argv = strings({"--polycheck"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runPolyCheck(optional(args, 1), qtArgs);
                    },
            },
            {
                .name = "settings-dialog",
                .argv = strings({"--settings-dialog"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runSettingsDialogCheck(qtArgs); },
            },
            {.name = "samplecheck",
             .argv = strings({"--samplecheck", "{sample-corpus?}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runSampleCheck(args.value(1), qtArgs);
                 },
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
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runHostSeamsCheck(qtArgs); },
            },
            {
                .name = "velocity-model",
                .argv = strings({"--check-velocity-model"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runVelocityModelCheck(qtArgs); },
            },
            {
                .name = "editor-drawer",
                .argv = strings({"--check-editor-drawer"}),
                .handler = [](QApplication &, const QStringList &,
                              const QStringList &qtArgs) { return runEditorDrawerCheck(qtArgs); },
            },
            {
                .name = "automation-raster",
                .argv = strings({"--check-automation-raster", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runAutomationRasterCheck(args[1], args[2], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "velocity-page",
                .argv = strings({"--check-velocity-page", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runVelocityPageCheck(args[1], args[2], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "scrollbar",
                .argv = strings({"--scrollbar", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runScrollbarCheck(args[1], args[2], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "velocity-editing",
                .argv = strings({"--velocity-editing"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runVelocityEditingCheck(qtArgs);
                    },
            },
            {
                .name = "automation-editing",
                .argv = strings({"--automation-editing"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runAutomationEditingCheck(qtArgs);
                    },
            },
            {
                .name = "automation-domain",
                .argv = strings({"--automation-domain"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runAutomationDomainCheck(qtArgs);
                    },
            },
            {
                .name = "automation-presentation",
                .argv = strings({"--automation-presentation"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runAutomationPresentationCheck(qtArgs);
                    },
            },
            {
                .name = "automation-hover",
                .argv = strings({"--automation-hover"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runAutomationHoverCheck(qtArgs);
                    },
            },
            {
                .name = "host-adapter",
                .argv = strings({"--check-host-adapter", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runHostAdapterCheck(args[1], args[2], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "mainwindow-routing-input",
                .argv = strings({"--check-mainwindow-routing-input", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return checks::mainwindowrouting::runMainWindowRoutingInputCheck(
                            args[1], args[2], args[3], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "mainwindow-routing-state",
                .argv = strings({"--check-mainwindow-routing-state", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return checks::mainwindowrouting::runMainWindowRoutingStateCheck(
                            args[1], args[2], args[3], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "mainwindow-routing-lifecycle",
                .argv = strings({"--check-mainwindow-routing-lifecycle", "{scratch}",
                                 "mus_route101", "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return checks::mainwindowrouting::runMainWindowRoutingLifecycleCheck(
                            args[1], args[2], args[3], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "mainwindow-routing-native",
                .argv = strings({"--check-mainwindow-routing-native", "{scratch}", "mus_route101",
                                 "mus_petalburg"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return checks::mainwindowrouting::runMainWindowRoutingNativeCheck(
                            args[1], args[2], args[3], qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "rendering-playhead",
                .argv = strings({"--check-rendering-playhead", "{scratch}", "mus_route101"}),
                .handler =
                    [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                        return runRenderingPlayheadCheck(args[1], args[2], optional(args, 3),
                                                         qtArgs);
                    },
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
                        return runHostIntegrationCheck(args[1], args[2], args[3], optional(args, 4),
                                                       qtArgs);
                    },
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "eventviews-remap",
                .argv = strings({"--eventviews-remap"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runEventViewsRemapCheck(qtArgs);
                    },
            },
            {
                .name = "eventviews-playhead",
                .argv = strings({"--eventviews-playhead"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runEventViewsPlayheadCheck(qtArgs);
                    },
            },
            {
                .name = "view-buckets-grid",
                .argv = strings({"--view-buckets-grid"}),
                .handler =
                    [](QApplication &, const QStringList &, const QStringList &qtArgs) {
                        return runViewBucketsGridCheck(qtArgs);
                    },
            },
            {.name = "pitch-bend-editing",
             .argv = strings({"--pitch-bend-editing"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runPitchBendEditingCheck(qtArgs); }},
            {.name = "pitch-bend-raster",
             .argv = strings({"--pitch-bend-raster"}),
             .handler = [](QApplication &, const QStringList &,
                           const QStringList &qtArgs) { return runPitchBendRasterCheck(qtArgs); },
             .windowing = Windowing::WindowSystem},
            {.name = "themecheck",
             .argv = strings({"--themecheck"}),
             .handler =
                 [](QApplication &application, const QStringList &, const QStringList &qtArgs) {
                     return runThemeLayoutThemeCheck(application, qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "fontcheck",
             .argv = strings({"--fontcheck"}),
             .handler =
                 [](QApplication &application, const QStringList &, const QStringList &qtArgs) {
                     return runThemeLayoutFontCheck(application, qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "darkbasecheck",
             .argv = strings({"--darkbasecheck"}),
             .handler =
                 [](QApplication &application, const QStringList &, const QStringList &qtArgs) {
                     return runThemeLayoutDarkBaseCheck(application, qtArgs);
                 },
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
