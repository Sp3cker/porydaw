#include "checkcatalog.h"

#include "fixturecatalog.hpp"
#include "fwd.hpp"

#include <initializer_list>

namespace checks::detail {
namespace {

QStringList strings(std::initializer_list<const char *> values)
{
    QStringList result;
    result.reserve(qsizetype(values.size()));
    for (const char *value : values)
        result.append(QString::fromUtf8(value));
    return result;
}

const QString &argumentAt(const QStringList &arguments, qsizetype index)
{
    static const QString empty;
    return index < arguments.size() ? arguments.at(index) : empty;
}

template <auto Run>
int qtOnly(QApplication &, const QStringList &, const QStringList &qtArguments)
{
    return Run(qtArguments);
}

#ifdef __APPLE__
int swiftCore(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    auto selected = QStringList{
        QStringLiteral("--pdc-mid2agb=") + argumentAt(arguments, 2),
    };
    // argv[3] optionally names one QTest slot; without it the whole suite runs.
    if (arguments.size() > 3)
        selected.append(arguments.at(3));
    selected.append(qtArguments);
    return runSwiftCoreCheck(argumentAt(arguments, 1), selected);
}

int swiftBank(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    return runSwiftCoreCheck(argumentAt(arguments, 1), QStringList{"bankLeases"} + qtArguments);
}

int swiftExport(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    return runSwiftCoreCheck(argumentAt(arguments, 1), QStringList{"exportChecks"} + qtArguments);
}
#else
constexpr Handler swiftCore = nullptr;
constexpr Handler swiftBank = nullptr;
constexpr Handler swiftExport = nullptr;
#endif

} // namespace

const std::vector<CheckDefinition> &catalog()
{
    static const auto definitions = [] {
        const QStringList project = fixtures::decompProjectFiles();
        const QStringList rich = fixtures::richVoicegroupFiles();
        const QStringList editor = fixtures::voicegroupEditorFiles();
        const QStringList route101 =
            project + strings({"sound/songs/midi/mus_route101.mid"}) + rich;
        const QStringList route102 =
            project + strings({"sound/songs/midi/mus_route102.mid"}) + rich;
        const QStringList bank =
            project + strings({"sound/songs/midi/mus_gym.mid", "sound/songs/midi/mus_oldale.mid"}) +
            rich;

        std::vector<CheckDefinition> result;
        result.push_back({.name = "production-startup",
                          .argv = strings({"--version"}),
                          .binary = BinaryKind::Application,
                          .startup = StartupKind::HandlerOwned,
                          .framework = Framework::Process});
        // The scale, activity, transport, telemetry, click, resonance and MIDI
        // engine lanes now run under swiftcore; their retired native originals
        // are recorded in their proof ledgers.
        // Forced-null backend initialization and backend-name reporting.
        result.push_back(
            {.name = "audiocheck-backend",
             .argv = strings({"--audiocheck-backend"}),
             .handler = qtOnly<runAudioBackendCheck>,
             .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}}});
        result.push_back(
            {.name = "swiftcore",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 project + fixtures::decompMidiFiles() +
                 strings({"test_midis/external_import.mid", "test_midis/duplicate_setters.mid",
                          "test_midis/smf/valid/opaque_sysex.mid",
                          "test_midis/smf/valid/vlq_running_status.mid",
                          "test_midis/smf/valid/note_lifecycle.mid",
                          "test_midis/smf/malformed/duplicate_eot.mid",
                          "test_midis/smf/stress/automation_burst.mid"}) +
                 rich + editor +
                 strings({"include/constants/songs.h", "sound/music_player_table.inc"}),
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectidentitycheck",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectIdentity"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project,
             .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-songmodel",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "songModel"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project,
                          .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-midicfg",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "midiCfg"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project,
                          .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-songsmk",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "songsMk"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project,
                          .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-catalog",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "songCatalog"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project,
                          .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-synthcatalog",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "synthCatalog"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + rich,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-values",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupValues"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project,
             .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-savecore",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "saveCore"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project + editor,
                          .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-editing",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupEditing"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-incopen",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupEditing"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-open",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreOpen"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 project + editor +
                 strings({"include/constants/songs.h", "sound/music_player_table.inc"}) +
                 fixtures::decompMidiFiles(),
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-edits",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupEditing"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-save",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "saveCore"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project + editor,
                          .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-checks",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreChecks"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-checks-catalog-absent",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "catalogAbsent"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-context",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupContext"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-fileio",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupContext"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-banklogic",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "voicegroupBankLogic"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project + editor,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-actor",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreActor"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = project,
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-reads",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreReads"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 project + editor +
                 strings({"include/constants/songs.h", "sound/music_player_table.inc"}) +
                 fixtures::decompMidiFiles(),
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-loadbank",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreLoadBank"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 project + editor +
                 strings({"include/constants/songs.h", "sound/music_player_table.inc"}) +
                 fixtures::decompMidiFiles(),
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-edit",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreEdit"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 project + editor +
                 strings({"include/constants/songs.h", "sound/music_player_table.inc"}) +
                 fixtures::decompMidiFiles(),
             .platforms = Platform::MacOS});
        result.push_back(
            {.name = "projectstore-savebank",
             .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "projectStoreSave"}),
             .handler = swiftCore,
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles =
                 project + editor +
                 strings({"include/constants/songs.h", "sound/music_player_table.inc"}) +
                 fixtures::decompMidiFiles(),
             .platforms = Platform::MacOS});
        result.push_back({.name = "bankleases",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "bankLeases"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project + editor +
                                          strings({"include/constants/songs.h",
                                                   "sound/music_player_table.inc"}) +
                                          fixtures::decompMidiFiles(),
                          .platforms = Platform::MacOS});
        result.push_back({.name = "projectstore-parity",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}", "bankLeases"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project + editor +
                                          strings({"include/constants/songs.h",
                                                   "sound/music_player_table.inc"}) +
                                          fixtures::decompMidiFiles(),
                          .platforms = Platform::MacOS});
        const auto native = [](const char *name, const char *command, const char *song,
                               const QStringList &files, Handler handler) {
            return CheckDefinition{
                .name = name,
                .argv = {QStringLiteral("--") + QString::fromUtf8(command),
                         QStringLiteral("{scratch}"), QString::fromUtf8(song)},
                .handler = handler,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = files,
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
                .platforms = Platform::MacOS,
            };
        };
        result.push_back(native("vgbankcheck", "vgbankcheck", "mus_gym", bank, swiftBank));
        result.push_back(
            native("exportcheck-loop", "exportcheck", "mus_route101", route101, swiftExport));
        result.push_back(
            native("exportcheck-tail", "exportcheck", "mus_route102", route102, swiftExport));
        return result;
    }();
    return definitions;
}

} // namespace checks::detail
