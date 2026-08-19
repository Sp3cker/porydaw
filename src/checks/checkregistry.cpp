#include "checkregistry.hpp"

#include "fixturecatalog.hpp"
#include "fwd.hpp"
#include "mainwindow.h"
#include "ui/applicationstartup.h"

#include <algorithm>
#include <cstdio>
#include <initializer_list>
#include <vector>

#include <QApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QSettings>
#include <QTemporaryDir>

namespace checks {
namespace {

using Handler = int (*)(QApplication &, const QStringList &);

enum class StartupKind { Porydaw, HandlerOwned };
enum class ScratchKind { Unused, ExistingDirectory, MustNotExistPath };
enum class FixtureRootKind { None, DecompProject, SongsMkProject };
enum class BinaryKind { Checks, Application };
enum class CheckSuite { Regression, Specialized, Negative };

struct CheckDefinition {
    const char *name;
    QStringList argv;
    Handler handler = nullptr;
    ScratchKind scratchKind = ScratchKind::Unused;
    FixtureRootKind fixtureRootKind = FixtureRootKind::None;
    QStringList fixtureFiles;
    QMap<QString, QString> environment;
    QMap<QString, QString> optionalArgumentEnvironment;
    QMap<QString, QString> environmentArguments;
    bool exclusive = false;
    BinaryKind binary = BinaryKind::Checks;
    StartupKind startup = StartupKind::Porydaw;
    CheckSuite suite = CheckSuite::Regression;
};

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

const std::vector<CheckDefinition> &registry()
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
                             richVoicegroupFiles,
             .exclusive = true},
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
             .fixtureFiles = route101Files + voicegroupEditorFiles + strings({"data/sound_data.s"}),
             .exclusive = true},
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
            {.name = "sessioncheck",
             .argv = strings({"--sessioncheck", "{scratch}", "mus_route101"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runSessionCheck(args[1], args[2]); },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101RichFiles,
             .exclusive = true},
            {.name = "tabcheck",
             .argv = strings({"--tabcheck", "{scratch}", "mus_route101", "mus_petalburg"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runTabCheck(args[1], args[2], args[3]);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = twoSongRichFiles,
             .exclusive = true},
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
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runSmfCheck(args.contains(QStringLiteral("--stress")));
                 },
             .environmentArguments = {{QStringLiteral("PORYDAW_SMF_STRESS"),
                                       QStringLiteral("--stress")}}},
            {.name = "transportcheck",
             .argv = strings({"--transportcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runTransportCheck(); },
             .exclusive = true},
            {.name = "audiocheck",
             .argv = strings({"--audiocheck"}),
             .handler = [](QApplication &, const QStringList &) { return runAudioCheck(); },
             .exclusive = true},
            {.name = "clickcheck",
             .argv = strings({"--clickcheck"}),
             .handler = [](QApplication &, const QStringList &) { return runClickCheck(false); },
             .exclusive = true},
            {.name = "clickcheck-hardcut",
             .argv = strings({"--clickcheck-hardcut"}),
             .handler = [](QApplication &, const QStringList &) { return runClickCheck(true); },
             .exclusive = true,
             .suite = CheckSuite::Negative},
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
            {.name = "polycheck",
             .argv = strings({"--polycheck"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runPolyCheck(optional(args, 1)); },
             .exclusive = true},
            {.name = "samplecheck",
             .argv = strings({"--samplecheck", "{scratch}", "{sample-corpus?}"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runSampleCheck(args[1], optional(args, 2), optional(args, 3));
                 },
             .scratchKind = ScratchKind::MustNotExistPath,
             .optionalArgumentEnvironment = {{QStringLiteral("{sample-corpus?}"),
                                              QStringLiteral("PORYDAW_SAMPLE_CORPUS")}},
             .exclusive = true},
            {.name = "noteidcheck",
             .argv = strings({"--check-note-identity", "{scratch}"}),
             .handler = [](QApplication &,
                           const QStringList &args) { return runNoteIdentityCheck(args[1]); },
             .scratchKind = ScratchKind::ExistingDirectory},
            {.name = "host-seams",
             .argv = strings({"--check-host-seams"}),
             .handler = [](QApplication &, const QStringList &) { return runHostSeamsCheck(); },
             .suite = CheckSuite::Specialized},
            {.name = "velocity-model",
             .argv = strings({"--check-velocity-model"}),
             .handler = [](QApplication &, const QStringList &) { return runVelocityModelCheck(); },
             .suite = CheckSuite::Specialized},
            {.name = "editor-drawer",
             .argv = strings({"--check-editor-drawer"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runEditorDrawerCheck(optional(args, 1));
                 },
             .suite = CheckSuite::Specialized},
            {.name = "automation-gestures",
             .argv = strings({"--check-automation-gestures", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runAutomationGestureCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .suite = CheckSuite::Specialized},
            {.name = "automation-popup-menus",
             .argv = strings({"--check-automation-popup-menus", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runAutomationPopupMenuCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .suite = CheckSuite::Specialized},
            {.name = "automation",
             .argv = strings({"--check-automation", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runAutomationCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .suite = CheckSuite::Specialized},
            {.name = "velocity-page",
             .argv = strings({"--check-velocity-page", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runVelocityPageCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .suite = CheckSuite::Specialized},
            {.name = "sidecar",
             .argv = strings({"--check-sidecar", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runViewSidecarCheck(args[1], args[2]);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .suite = CheckSuite::Specialized},
            {.name = "host-adapter",
             .argv = strings({"--check-host-adapter", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runHostAdapterCheck(args[1], args[2]);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .suite = CheckSuite::Specialized},
            {.name = "mainwindow-routing",
             .argv = strings(
                 {"--check-mainwindow-routing", "{scratch}", "mus_route101", "mus_petalburg"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runMainWindowRoutingCheck(args[1], args[2], args[3]);
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = twoSongRichFiles,
             .exclusive = true,
             .suite = CheckSuite::Specialized},
            {.name = "rendering-playhead",
             .argv = strings({"--check-rendering-playhead", "{scratch}", "mus_route101"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runRenderingPlayheadCheck(args[1], args[2], optional(args, 3));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = route101Files,
             .suite = CheckSuite::Specialized},
            {.name = "host-integration",
             .argv = strings(
                 {"--check-host-integration", "{scratch}", "mus_route101", "mus_petalburg"}),
             .handler =
                 [](QApplication &, const QStringList &args) {
                     return runHostIntegrationCheck(args[1], args[2], args[3], optional(args, 4));
                 },
             .scratchKind = ScratchKind::ExistingDirectory,
             .fixtureRootKind = FixtureRootKind::DecompProject,
             .fixtureFiles = twoSongRichFiles,
             .exclusive = true,
             .suite = CheckSuite::Specialized},
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
             .environment =
                 {
#ifdef Q_OS_WIN
                     {QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("windows")},
#else
                     {QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen")},
#endif
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

QJsonObject jsonObject(const QMap<QString, QString> &values)
{
    auto result = QJsonObject{};
    for (auto it = values.cbegin(); it != values.cend(); ++it)
        result.insert(it.key(), it.value());
    return result;
}

QString jsonName(ScratchKind kind)
{
    switch (kind) {
    case ScratchKind::Unused:
        return QStringLiteral("unused");
    case ScratchKind::ExistingDirectory:
        return QStringLiteral("existing-directory");
    case ScratchKind::MustNotExistPath:
        return QStringLiteral("must-not-exist-path");
    }
    Q_UNREACHABLE();
}

QString jsonName(FixtureRootKind kind)
{
    switch (kind) {
    case FixtureRootKind::None:
        return QStringLiteral("none");
    case FixtureRootKind::DecompProject:
        return QStringLiteral("decomp-project");
    case FixtureRootKind::SongsMkProject:
        return QStringLiteral("songs-mk-project");
    }
    Q_UNREACHABLE();
}

QString jsonName(BinaryKind kind)
{
    switch (kind) {
    case BinaryKind::Checks:
        return QStringLiteral("checks");
    case BinaryKind::Application:
        return QStringLiteral("application");
    }
    Q_UNREACHABLE();
}

QString jsonName(CheckSuite suite)
{
    switch (suite) {
    case CheckSuite::Regression:
        return QStringLiteral("regression");
    case CheckSuite::Specialized:
        return QStringLiteral("specialized");
    case CheckSuite::Negative:
        return QStringLiteral("negative");
    }
    Q_UNREACHABLE();
}

QJsonObject manifestEntry(const CheckDefinition &definition)
{
    auto entry = QJsonObject{
        {QStringLiteral("name"), QString::fromUtf8(definition.name)},
        {QStringLiteral("argv"), QJsonArray::fromStringList(definition.argv)},
        {QStringLiteral("scratchKind"), jsonName(definition.scratchKind)},
        {QStringLiteral("fixtureRootKind"), jsonName(definition.fixtureRootKind)},
        {QStringLiteral("fixtureFiles"), QJsonArray::fromStringList(definition.fixtureFiles)},
        {QStringLiteral("binary"), jsonName(definition.binary)},
        {QStringLiteral("suite"), jsonName(definition.suite)},
    };
    if (!definition.environment.isEmpty())
        entry.insert(QStringLiteral("environment"), jsonObject(definition.environment));
    if (!definition.optionalArgumentEnvironment.isEmpty())
        entry.insert(QStringLiteral("optionalArgumentEnvironment"),
                     jsonObject(definition.optionalArgumentEnvironment));
    if (!definition.environmentArguments.isEmpty())
        entry.insert(QStringLiteral("environmentArguments"),
                     jsonObject(definition.environmentArguments));
    if (definition.exclusive)
        entry.insert(QStringLiteral("exclusive"), true);
    return entry;
}

} // namespace

bool writeManifest(const QStringList &arguments)
{
    if (!arguments.contains(QStringLiteral("--manifest")))
        return false;
    auto checks = QJsonArray{};
    for (const auto &definition : registry())
        checks.push_back(manifestEntry(definition));
    const auto document = QJsonDocument{QJsonObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("checks"), checks},
    }};
    const auto json = document.toJson(QJsonDocument::Compact);
    std::fwrite(json.constData(), 1, size_t(json.size()), stdout);
    std::fputc('\n', stdout);
    return true;
}

std::optional<int> runRequested(QApplication &application, const QStringList &arguments)
{
    for (const auto &definition : registry()) {
        if (!definition.handler)
            continue;
        const auto commandIndex = arguments.indexOf(definition.argv[0]);
        if (commandIndex < 0)
            continue;
        const auto checkArguments = arguments.mid(commandIndex);
        const auto requiredArguments = std::count_if(
            definition.argv.cbegin(), definition.argv.cend(), [&](const auto &argument) {
                return !definition.optionalArgumentEnvironment.contains(argument);
            });
        if (checkArguments.size() < requiredArguments) {
            std::fprintf(stderr, "porydaw_checks: %s requires %lld argument(s)\n", definition.name,
                         static_cast<long long>(requiredArguments - 1));
            return 2;
        }
        if (definition.startup == StartupKind::HandlerOwned)
            return definition.handler(application, checkArguments);
        auto settingsDirectory = QTemporaryDir{};
        if (!settingsDirectory.isValid())
            return 1;
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDirectory.path());
        if (!ui::initializePorydawApplication(application))
            return 1;
        return definition.handler(application, checkArguments);
    }
    return std::nullopt;
}

} // namespace checks
