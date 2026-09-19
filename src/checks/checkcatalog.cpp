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
             // production application launches with --version and exits successfully
             .argv = strings({"--version"}),
             .binary = BinaryKind::Application,
             .startup = StartupKind::HandlerOwned,
             .framework = Framework::Process},
            {.name = "roundtrip",
             // imports each decomp song and byte-compares exported assembly against a fresh mid2agb
             // compile; synthetic XCMD traffic compiles to XCMD xIECV/xIECL and unknown-selector
             // payloads emit no XCMD op
             .argv = strings({"--roundtrip", "{scratch}", "{mid2agb}"}),
             .handler = qtWithTwoArguments<runRoundTrip>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "editcheck",
             // song document editing: notes, time ranges, metadata, raw data, tracks, and document
             // lifecycle
             .argv = strings({"--editcheck", "{scratch}"}),
             .handler = [](QApplication &, const QStringList &args,
                           const QStringList &qtArgs) { return runEditCheck(args.mid(1), qtArgs); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles},
            {.name = "scalecheck",
             // scale tables: roots and defaults, membership and neighbor queries, diatonic
             // destination mapping
             .argv = strings({"--scalecheck", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runScaleCheck(args.mid(1), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory},
            {.name = "eventviews-chrome",
             // event list chrome: filter menus and matrix, row menus, column resize, wheel clamp,
             // view-state round trip
             .argv = strings({"--eventviews-chrome"}),
             .handler = qtOnly<runEventViewsChromeCheck>},
            {.name = "selftest-timeline",
             // harness self-test timeline: view codec round trip, CC usage, mute and rescale
             // rejects, wizard flow
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
             // harness self-test transport: tick lag clamps, lane blob poisoning and defaults, live
             // VSS persistence through close
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
             // harness self-test workspace: view codec across add-note/new/undo, live timeline
             // swap, preview keeps transport
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
             // project save/reload via loop.cfg: recipe dedup and fallbacks, song history merge and
             // boundaries
             .argv = strings({"--savecheck", "{scratch}", "mus_route101", "{mid2agb}"}),
             .handler = qtWithThreeArguments<runSaveCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "onboardcheck",
             // onboarding import: track split/weld/move/remove ops, synthetic publication, SMF save
             // canonicalization
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
             // voicegroup editor blank-slot and sparse insert over the editor save/reload path with
             // DSR scan
             .argv = strings({"--vgcheck", "{scratch}", "mus_gym"}),
             .handler = qtWithTwoArguments<runVgCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgbankcheck",
             // voicegroup bank leases: reuse across songs, scalar edit replaces bank, conflicts
             // hard-fail, failed save dirty
             .argv = strings({"--vgbankcheck", "{scratch}", "mus_gym"}),
             .handler = qtWithTwoArguments<runVgBankCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 decompProjectFiles +
                 strings({"sound/songs/midi/mus_gym.mid", "sound/songs/midi/mus_oldale.mid"}) +
                 voicegroupEditorFiles},
            {.name = "vgloadcheck",
             // voicegroup load: warm reuse skips reads, batch adapters preserve bank, failed
             // transport and rebind paths
             .argv = strings({"--vgloadcheck", "{scratch}"}),
             .handler = qtWithTwoArguments<runVgLoadCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + voicegroupEditorFiles},
            {.name = "vgloadbench",
             // vgloadcheck runner in benchmark mode: load/warm timing output with warm lease
             // identity assertions
             .argv = strings({"--vgloadbench", "{scratch}", "mus_gym"}),
             .handler = qtWithTwoArguments<runVgLoadCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_gym.mid"}) +
                             voicegroupEditorFiles},
            {.name = "vgsavecheck",
             // voicegroup editor save pipeline: undo/redo save byte round trip, unsaved-edit carry,
             // picker audition and commit, type-column icon/tooltip per voice family
             .argv = strings({"--vgsavecheck", "{scratch}", "mus_route101"}),
             .handler = qtWithThreeArguments<runVoicegroupSaveCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 route101Files + voicegroupEditorFiles + strings({"data/sound_data.s"})},
            {.name = "exportcheck-loop",
             // MIDI export over mus_route101: duration/render parity, RIFF chunk validity,
             // canceled-export cleanup
             .argv = strings({"--exportcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runExportCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101RichFiles},
            {.name = "exportcheck-tail",
             // same export harness over mus_route102: duration/render parity, RIFF chunk validity,
             // canceled-export cleanup
             .argv = strings({"--exportcheck", "{scratch}", "mus_route102"}),
             .handler = qtWithTwoArguments<runExportCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + strings({"sound/songs/midi/mus_route102.mid"}) +
                             richVoicegroupFiles},
            {
                .name = "project-identity",
                // project naming: song name accept/reject/hash, voicegroup id path normalization
                // and rejection
                .argv = strings({"--project-identity"}),
                .handler = qtOnly<runProjectIdentityCheck>,
            },
            {
                .name = "project-io-flow",
                // project open/close flow: async snapshot detach, FIFO command order, failed-open
                // worker retention
                .argv = strings({"--project-io-flow", "{scratch}"}),
                .handler = qtWithOneArgument<runProjectIoFlowCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "project-io-mutations",
                // staged project save: per-stage failure handling, legacy JSON preservation,
                // voicegroup conflict/apply
                .argv = strings({"--project-io-mutations", "{scratch}"}),
                .handler = qtWithOneArgument<runProjectIoMutationsCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "projectworkspacecheck",
                // workspace open/reload: readiness ordering, missing-song reconcile failure,
                // auto-catalog timing
                .argv = strings({"--projectworkspacecheck", "{scratch}"}),
                .handler = qtWithOneArgument<runProjectWorkspaceCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles + strings({"sound/music_player_table.inc"}),
            },
            {
                .name = "sessioncheck",
                // workspace session restore: labels and settings survive close/reopen, missing-song
                // recipe ignore
                .argv = strings({"--sessioncheck", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSessionCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {
                .name = "tabcheck",
                // workspace tabs: open/close ordering, per-tab undo, camera retention, dirty-close
                // gate, persistence
                .argv = strings({"--tabcheck", "{scratch}", "mus_route101", "mus_route102"}),
                .handler = qtWithThreeArguments<runTabCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles + strings({"sound/songs/midi/mus_route102.mid"}),
            },
            {.name = "eventviews-edits",
             // event list edits: queued and high-bit ticks, channel/data conversions, atomic tempo,
             // same-tick reorder, deletes
             .argv = strings({"--eventviews-edits"}),
             .handler = qtOnly<runEventViewsEditsCheck>},
            {.name = "rollcheck",
             // piano roll editing: pencil and resize gestures, keyboard edits, selection sweeps,
             // velocity/time prompts, menus
             .argv = strings({"--rollcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runRollCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "trackheaderquickcheck",
             // offscreen track header Quick surface: publish/render, voice routing, mute/solo
             // cancels, header menus, scroll clamp
             .argv = strings({"--trackheaderquickcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTrackHeaderQuickCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "trackheader-model",
             // track header model: reorder insertion slots with undo restore, reconciliation
             // unchanged and structural paths
             .argv = strings({"--trackheader-model", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTrackHeaderModelCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "trackactivitymetercheck",
             // track activity meter raster: role-scoped pixel updates, pause/intensity, stereo
             // raster with rebuilt identity
             .argv = strings({"--trackactivitymetercheck"}),
             .handler = qtOnly<runTrackActivityMeterCheck>},
            {.name = "trackactivitymetercheck-fractional-dpr",
             // activity meter raster repeated under QT_SCALE_FACTOR=1.5 fractional display scaling
             .argv = strings({"--trackactivitymetercheck"}),
             .handler = qtOnly<runTrackActivityMeterCheck>,
             .environment = {{QStringLiteral("QT_SCALE_FACTOR"), QStringLiteral("1.5")}}},
            {.name = "rollwindowingcheck",
             // quick roll windowing: header selection and voice picker, basis geometry chunks
             // shrink/clear/reactivate, pre-frame background, grid contrast preview/apply
             .argv = strings({"--rollwindowingcheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runRollWindowingCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem},
            {.name = "timelinepancheck",
             // timeline pan: dash-phase clip preservation, wheel pan, gutter labels and geometry
             // counts survive reuse
             .argv = strings({"--timelinepancheck", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTimelinePanCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {.name = "timelinepan-native",
             // native window-system pan across selection extents exercising the full-refresh
             // performance path
             .argv = strings({"--timelinepan-native", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runTimelinePanNativeCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .windowing = Windowing::WindowSystem,
             .optIn = true},
            {
                .name = "rollcheck-static",
                // static piano roll: fallback camera/grid/ruler geometry, tick ceiling, readiness
                // gating, invalid bounds
                .argv = strings({"--rollcheck-static", "{scratch}", "mus_route101"}),
                .handler =
                    qtWithTwoArguments<checks::rollcheck::staticcheck::runPianoRollStaticCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {.name = "mkcheck",
             // songs.mk parse/write: volume-only rewrite, variable spelling preservation,
             // byte-exact append/remove round trip
             .argv = strings({"--mkcheck", "{scratch}", "mus_aqua_magma_hideout"}),
             .handler = qtWithTwoArguments<runMkCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::SongsMkProject,
             .fixtureFiles = strings({"sound/song_table.inc", "songs.mk"})},
            {.name = "loopcheck",
             // loop wrap keyed-on parity with hardware program supply
             .argv = strings({"--loopcheck"}),
             .handler = qtOnly<runLoopCheck>},
            {.name = "ignorecheck",
             // .gitignore authoring: newline and spelling repairs, subdirectory and non-repository
             // no-ops
             .argv = strings({"--ignorecheck"}),
             .handler = qtOnly<runIgnoreCheck>,
             .scratchKind = ScratchKind::Unused},
            {.name = "primecheck",
             // playback priming: chase and voiceless track programs, primed vs unprimed audition
             // audibility, mid-song chase
             .argv = strings({"--primecheck"}),
             .handler = qtOnly<runPrimeCheck>},
            {.name = "xcmdcheck",
             // xcmd projection: epoch selectors, canonical lane rewrites, byte-exact raw
             // reconciliation, export canonicalization
             .argv = strings({"--xcmdcheck"}),
             .handler = qtOnly<runXcmdCheck>},
            {.name = "smfcheck",
             // SMF read/write: save parity, format0 to format1 conversion, SYSEX/meta round trip,
             // duplicate EOT, tick rejects; import-report verdicts for XCMD epochs and ordinary CCs
             .argv = strings({"--smfcheck"}),
             .handler = qtOnly<runSmfCheck>},
            {.name = "transportcheck",
             // transport: blocking-seek handoff ownership, sounding-note tail cuts on pause/unload,
             // unity-gain entry
             .argv = strings({"--transportcheck"}),
             .handler = qtOnly<runTransportCheck>},
            {.name = "voicegroupviewcachecheck",
             // voicegroup view cache history: stale transitions, merge rules for same-tick edits,
             // coordinator gating
             .argv = strings({"--voicegroupviewcachecheck"}),
             .handler = qtOnly<runVoicegroupViewCacheCheck>},
            {
                .name = "audiocheck",
                // audio telemetry: packed activity byte-order preservation and unpack consuming
                // only activity bytes
                .argv = strings({"--audiocheck"}),
                .handler = qtOnly<runAudioCheck>,
            },
            {
                .name = "audiocheck-backend",
                // forced null audio backend: init and name reporting, interrupted fades, hard-cut
                // click calibration
                .argv = strings({"--audiocheck-backend"}),
                .handler = qtOnly<runAudioBackendCheck>,
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            },
            {
                .name = "clickcheck",
                // click track fades: pause/stop/retarget ramp silence, deferred timed preview
                // replay after interruption
                .argv = strings({"--clickcheck"}),
                .handler = qtOnly<runClickCheck>,
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            },
            {.name = "resonancecheck",
             // resonance filter DSP: bypass parity, threshold gating, saturation plateau, stereo
             // bit-identity, release tails
             .argv = strings({"--resonancecheck"}),
             .handler = qtOnly<runResonanceCheck>},
            {.name = "resonancecheck-timing",
             // resonance timing: release recovery across gaps, sixty-second plateau hold, attack
             // and hop constants
             .argv = strings({"--resonancecheck-timing"}),
             .handler = qtOnly<runResonanceTimingCheck>},
            {.name = "trackactivitycheck",
             // track activity DSP: fresh dark activity, gate carry across loop wrap, tied-note
             // stacking, boundary playback
             .argv = strings({"--trackactivitycheck"}),
             .handler = qtOnly<runTrackActivityCheck>},
            {.name = "keymapcheck",
             // keymap registry: seeded user settings ignored, default chord matching, modifier
             // chords
             .argv = strings({"--keymapcheck"}),
             .handler = qtOnly<runKeymapCheck>},
            {.name = "selectioncheck",
             // editor selection model: note/time-selection sanitization, track/lane scope queries,
             // remap preserves selection
             .argv = strings({"--selectioncheck"}),
             .handler = qtOnly<runSelectionCheck>},
            {
                .name = "laneselectioncheck",
                // lane selection: endpoint payloads, lane/track scope separation, hidden-lane
                // exclusion, zoom/scroll hit tests
                .argv = strings({"--laneselectioncheck"}),
                .handler = qtOnly<runLaneSelectionCheck>,
            },
            {
                .name = "clipmimecheck",
                // clipboard mime: codec round trips, foreign text rejection, malformed and
                // custom-mime decode failure reporting
                .argv = strings({"--clipmimecheck"}),
                .handler = qtOnly<runClipMimeCheck>,
            },
            {
                .name = "clipcheck",
                // clipboard clips: cross-TPQN paste scaling, time-range merge with undo, empty lane
                // no-op, tiled paste undo
                .argv = strings({"--clipcheck"}),
                .handler = qtOnly<runClipCheck>,
            },
            {
                .name = "polycheck",
                // polyphony gate panel: overflow counters/ring, sentinel tick, invert audibility,
                // log cap, dock toggles
                .argv = strings({"--polycheck"}),
                .handler = qtWithOneArgument<runPolyCheck>,
            },
            {
                .name = "settings-dialog",
                // settings dialog: round trip with mixer combo, disabled song tab fallback,
                // persistence, invalid value fallback
                .argv = strings({"--settings-dialog"}),
                .handler = qtOnly<runSettingsDialogCheck>,
            },
            {.name = "samplecheck",
             // sample processing: decode refusals, resample passband/alias identity,
             // quantize/dither, pitch matrix, loop crossfade
             .argv = strings({"--samplecheck", "{sample-corpus?}"}),
             .handler = qtWithOneArgument<runSampleCheck>,
             .scratchKind = ScratchKind::Unused,
             .optionalArgumentEnvironment = {{QStringLiteral("{sample-corpus?}"),
                                              QStringLiteral("PORYDAW_SAMPLE_CORPUS")}}},
            {.name = "noteidcheck",
             // note identity: parsed and adopted SMF id assignment, external-edit id remap,
             // timestamped id transport
             .argv = strings({"--check-note-identity", "{scratch}"}),
             .handler =
                 [](QApplication &, const QStringList &args, const QStringList &qtArgs) {
                     return runNoteIdentityCheck(args.mid(1), qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory},
            {
                .name = "host-seams",
                // host seams: plot viewport fill, editor endpoint updates, cosmetic-only state,
                // embedded window ownership/detach
                .argv = strings({"--check-host-seams"}),
                .handler = qtOnly<runHostSeamsCheck>,
            },
            {
                .name = "ruler-grid-menu",
                // ruler/grid quick menus: pick dispatch, outside-click/Escape dismissal,
                // owned-popup cancel scoping
                .argv = strings({"--check-ruler-grid-menu"}),
                .handler = qtOnly<runRulerGridMenuCheck>,
            },
            {
                .name = "velocity-model",
                // velocity model gestures: begin/update/preview/commit lifecycle and atomicity,
                // clamped deltas, level moves
                .argv = strings({"--check-velocity-model"}),
                .handler = qtOnly<runVelocityModelCheck>,
            },
            {
                .name = "editor-drawer",
                // editor drawer: surface and chrome, toggle/resize transactions, value prompts,
                // voice surface and paint lifecycle
                .argv = strings({"--check-editor-drawer"}),
                .handler = qtOnly<runEditorDrawerCheck>,
            },
            {
                .name = "automation-raster",
                // automation raster: curve/node/selected-ring rendering, half-open selection, hover
                // ghost, drag preview to release
                .argv = strings({"--check-automation-raster", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runAutomationRasterCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "velocity-page",
                // velocity page over a seeded route: continuous and PSG axis contexts, graduation
                // density, gesture transactions
                .argv = strings({"--check-velocity-page", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runVelocityPageCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "scrollbar",
                // scrollbar: signed-range drag rebase, paging/wheel/keyboard navigation, canonical
                // band layouts, zoom rebase
                .argv = strings({"--scrollbar", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runScrollbarCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "velocity-editing",
                // velocity editing gestures: single-commit drag/paint/ramp, escape and ungrab
                // cancels, stem hit precedence
                .argv = strings({"--velocity-editing"}),
                .handler = qtOnly<runVelocityEditingCheck>,
            },
            {
                .name = "automation-editing",
                // automation editing: pencil quantization, node drag commit/escape, multi-lane
                // selection, cross-lane paste clamps
                .argv = strings({"--automation-editing"}),
                .handler = qtOnly<runAutomationEditingCheck>,
            },
            {
                .name = "automation-domain",
                // automation domain: effective point resolution, deletion/move/collision, span
                // replacement, xcmd canonical edits
                .argv = strings({"--automation-domain"}),
                .handler = qtOnly<runAutomationDomainCheck>,
            },
            {
                .name = "automation-presentation",
                // automation presentation: gutter labels and active-row event counts, plot
                // switching, tempo ghost painting, scope indicators, pencil cursors,
                // lane scale labels (min/max/neutral), scale ticks, ghost label dodge
                .argv = strings({"--automation-presentation"}),
                .handler = qtOnly<runAutomationPresentationCheck>,
            },
            {
                .name = "automation-hover",
                // automation hover: grab retention across focus loss, revival and cancellation,
                // ghost text/ring, gesture commit
                .argv = strings({"--automation-hover"}),
                .handler = qtOnly<runAutomationHoverCheck>,
            },
            {
                .name = "host-adapter",
                // host adapter: canonical geometry projected to Quick bands, hidden-band clearing,
                // automation pan routing
                .argv = strings({"--check-host-adapter", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runHostAdapterCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "mainwindow-routing-input",
                // fresh main-window tabs withhold readiness and audition ticks until fully routed
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
                // main-window routing state: drawer seed projection after opening sessions
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
                // main-window routing across project close/reopen: global state correctness
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
                // native platform menu and window shortcut routing under the window-system tier
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
                // keyboard routing core: arrow movement across bands, mergeable undo, key-up
                // audition, clipboard parity
                .argv = strings({"--selectionkey-core", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSelectionKeyCoreCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {
                .name = "selectionkey-gesture",
                // keyboard routing gestures: visible-node overlap targeting, stem drag selection
                // guard, drag Escape reselect
                .argv = strings({"--selectionkey-gesture", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSelectionKeyGestureCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "selectionkey-window",
                // offscreen window-tier key routing: Copy/Solo fire once from band focus, chrome
                // grip keys stay local, resize safety; real Qt shortcut dispatch
                .argv = strings(
                    {"--selectionkey-window", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler = qtWithThreeArguments<runSelectionKeyWindowCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
            },
            {
                .name = "selectionkey-local-input",
                // offscreen local input ownership: rename, search, numeric, velocity, and
                // pitch-bend editors consume their keys
                .argv = strings({"--selectionkey-local-input", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSelectionKeyLocalInputCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
            },
            {.name = "playhead-guides",
             // playhead guides: device-pixel rect, guide resize/scroll/ownership, follow-scroll
             // behavior
             .argv = strings({"--playhead-guides", "{scratch}", "mus_route101"}),
             .handler = qtWithTwoArguments<runPlayheadGuidesCheck>,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files},
            {
                .name = "rendering-playhead",
                // playhead rendering: Quick polarity and edges, automation hover
                // decoration, position-only updates without rebuilds, plot geometry and lifecycle
                .argv = strings({"--check-rendering-playhead", "{scratch}", "mus_route101"}),
                .handler = qtWithThreeArguments<runRenderingPlayheadCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                // Custom QSGVertexColorMaterial geometry requires the default scenegraph backend.
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "swiftrollbench",
                // Roll frame-cost bench, flag-off lane: scripted scroll/zoom cadence
                // for the active C++ roll (Swift lane runs as swiftrollbench-swift).
                .argv = strings({"--swiftrollbench", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSwiftRollBenchCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
                .windowing = Windowing::WindowSystem,
            },
#ifdef __APPLE__
            {
                .name = "swiftdocfeed",
                // Real document snapshots, observer lifetime, and the shared Swift revision guard.
                .argv = strings({"--swiftdocfeed", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSwiftDocFeedCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "swiftcommands",
                // sgc_ intent pipe: per-intent validation matrix, undo granularity
                // (move = 1 entry, delete batch = 1 entry), session routing leaves
                // the undo stack untouched, add -> sgd_ revision-push round-trip,
                // and the Swift submission API.
                .argv = strings({"--swiftcommands", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSwiftCommandsCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
            },
            {
                .name = "swiftrollgated",
                // Gated read-only Swift roll overlay in production: initial render,
                // track follow, edit/undo/redo, interleaved documents, input absorption,
                // viewing input, transferred-window teardown, flag-off absence.
                .argv = strings({"--swiftrollgated", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler = qtWithThreeArguments<runSwiftRollGatedCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "swiftbandkeys",
                // sgk_ key seam and SwiftRollBand adapter: command-id arrival,
                // eligibility gating with/without selection, gesture-active
                // blocking, autoRepeat consumption, fallback when unhandled,
                // cancel-reason delivery mid-gesture, pointer/wheel/leave
                // forwarding as plain values.
                .argv = strings({"--swiftbandkeys", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler = qtWithThreeArguments<runSwiftBandKeysCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "swiftqtml",
                // QtBridge observable model updates through a harness-local
                // Swift presenter and real QML delegates.
                .argv = strings({"--swiftqtml", "{scratch}", "mus_route101", "mus_petalburg"}),
                .handler = qtWithThreeArguments<runSwiftQtMlCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = twoSongRichFiles,
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "swiftrollbench-swift",
                // Roll frame-cost bench, Swift lane: PORYDAW_SWIFT_ROLL mounts the
                // overlay; compare cadence against the flag-off swiftrollbench row.
                .argv = strings({"--swiftrollbench", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runSwiftRollBenchCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101RichFiles,
                .environment = {{QStringLiteral("PORYDAW_SWIFT_ROLL"), QStringLiteral("1")}},
                .windowing = Windowing::WindowSystem,
            },
            {
                .name = "rendering-playhead-native",
                // Cocoa playhead layer lifecycle: native ownership, clipping, and surface teardown
                .argv = strings({"--check-rendering-playhead-native", "{scratch}", "mus_route101"}),
                .handler = qtWithTwoArguments<runRenderingPlayheadNativeCheck>,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = route101Files,
                .windowing = Windowing::WindowSystem,
            },
#endif
            {
                .name = "host-integration",
                // host integration: two-tab ready sessions, velocity edit commit/undo, automation
                // pan, project switch/close
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
                // event views under remap: notify order, anchor follow on move, deleted chunk
                // unselect, tempo projection rows
                .argv = strings({"--eventviews-remap"}),
                .handler = qtOnly<runEventViewsRemapCheck>,
            },
            {
                .name = "eventviews-playhead",
                // event list playhead: last-of-run tint, focus commit cursor, focused sibling
                // precedence, follow scroll
                .argv = strings({"--eventviews-playhead"}),
                .handler = qtOnly<runEventViewsPlayheadCheck>,
            },
            {
                .name = "view-buckets-grid",
                // view bucket grid: bucket sums, quirk projection, snap ladder, grid-line snapping,
                // paint smoke
                .argv = strings({"--view-buckets-grid"}),
                .handler = qtOnly<runViewBucketsGridCheck>,
            },
            {.name = "pitch-bend-editing",
             // pitch-bend popup curves: shift-drag/freehand strokes, vertex editing, undo chaining,
             // audition, anchoring
             .argv = strings({"--pitch-bend-editing"}),
             .handler = qtOnly<runPitchBendEditingCheck>},
            {.name = "pitch-bend-raster",
             // pitch-bend popup raster: opaque surface over the window background, drawn curves
             // paint diagonals
             .argv = strings({"--pitch-bend-raster"}),
             .handler = qtOnly<runPitchBendRasterCheck>,
             .windowing = Windowing::WindowSystem},
            {.name = "themecheck",
             // theme: color contrast and completeness, grid/lane/waveform legibility, chrome pins,
             // dialog commit/revert
             .argv = strings({"--themecheck"}),
             .handler = qtWithApplication<runThemeLayoutThemeCheck>,
             .startup = StartupKind::HandlerOwned},
            {.name = "fontcheck",
             // typography: base pixel from application font, face contracts, fitted typography,
             // theme re-apply restores font
             .argv = strings({"--fontcheck"}),
             .handler = qtWithApplication<runThemeLayoutFontCheck>,
             .startup = StartupKind::HandlerOwned},
            {.name = "darkbasecheck",
             // dark baseline masks a poisoned platform palette into the vanilla theme baseline
             .argv = strings({"--darkbasecheck"}),
             .handler = qtWithApplication<runThemeLayoutDarkBaseCheck>,
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-12",
             // editor layout scaling at a 12px base font: process-scoped init, scale across
             // operations, panel scaling
             .argv = strings({"--editor-layout-check", "12"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     return runThemeLayoutScaleCheck(application, args[1].toInt(), qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-16",
             // editor layout scaling at a 16px base font: process-scoped init, scale across
             // operations, panel scaling
             .argv = strings({"--editor-layout-check", "16"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     return runThemeLayoutScaleCheck(application, args[1].toInt(), qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "editor-layout-18",
             // editor layout scaling at an 18px base font: process-scoped init, scale across
             // operations, panel scaling
             .argv = strings({"--editor-layout-check", "18"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     return runThemeLayoutScaleCheck(application, args[1].toInt(), qtArgs);
                 },
             .startup = StartupKind::HandlerOwned},
            {.name = "visual-chrome",
             // frozen chrome appearance: exact named bounds and rendered colors against
             // reviewed baselines at a 12px base font; the staged decomp project root
             // reaches the runner via PORYDAW_VISUAL_PROJECT_ROOT
             .argv = strings({"--visual-chrome", "{scratch}"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     qputenv("PORYDAW_VISUAL_PROJECT_ROOT", args.value(1).toUtf8());
                     return runVisualChromeCheck(application, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles + voicegroupEditorFiles,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("12")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-chrome-16",
             // same frozen chrome appearance at a 16px base font
             .argv = strings({"--visual-chrome", "{scratch}"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     qputenv("PORYDAW_VISUAL_PROJECT_ROOT", args.value(1).toUtf8());
                     return runVisualChromeCheck(application, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles + voicegroupEditorFiles,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("16")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-browsers",
             // frozen browser appearance at a 12px base font; the staged decomp
             // project root reaches the runner via PORYDAW_VISUAL_PROJECT_ROOT
             .argv = strings({"--visual-browsers", "{scratch}"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     qputenv("PORYDAW_VISUAL_PROJECT_ROOT", args.value(1).toUtf8());
                     return runVisualBrowsersCheck(application, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles + voicegroupEditorFiles,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("12")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-browsers-16",
             // same frozen browser appearance at a 16px base font
             .argv = strings({"--visual-browsers", "{scratch}"}),
             .handler =
                 [](QApplication &application, const QStringList &args, const QStringList &qtArgs) {
                     qputenv("PORYDAW_VISUAL_PROJECT_ROOT", args.value(1).toUtf8());
                     return runVisualBrowsersCheck(application, qtArgs);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = decompProjectFiles + decompMidiFiles + voicegroupEditorFiles,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("16")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-dialogs",
             // frozen dialog appearance at a 12px base font
             .argv = strings({"--visual-dialogs"}),
             .handler = qtWithApplication<runVisualDialogsCheck>,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("12")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-dialogs-16",
             // same frozen dialog appearance at a 16px base font
             .argv = strings({"--visual-dialogs"}),
             .handler = qtWithApplication<runVisualDialogsCheck>,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("16")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-quick",
             // frozen Qt Quick surfaces: native QQuickWindow framebuffer against reviewed
             // baselines at a 12px base font
             .argv = strings({"--visual-quick"}),
             .handler = qtWithApplication<runVisualQuickCheck>,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("12")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
            {.name = "visual-quick-16",
             // same frozen Qt Quick surfaces at a 16px base font
             .argv = strings({"--visual-quick"}),
             .handler = qtWithApplication<runVisualQuickCheck>,
             .environment = {{QStringLiteral("PORYDAW_VISUAL_FONT_PX"), QStringLiteral("16")}},
             .startup = StartupKind::HandlerOwned,
             .windowing = Windowing::WindowSystem},
        };
    }();
    return definitions;
}
} // namespace checks::detail
