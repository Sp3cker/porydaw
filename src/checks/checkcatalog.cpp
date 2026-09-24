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

int midiExport(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    return runExportCheck(argumentAt(arguments, 1), argumentAt(arguments, 2), qtArguments);
}

int voicegroupBank(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    return runVgBankCheck(argumentAt(arguments, 1), argumentAt(arguments, 2), qtArguments);
}

#ifdef __APPLE__
int swiftCore(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    auto selected = QStringList{
        QStringLiteral("--pdc-mid2agb=") + argumentAt(arguments, 2),
    };
    selected.append(qtArguments);
    return runSwiftCoreCheck(argumentAt(arguments, 1), selected);
}
#endif

} // namespace

const std::vector<CheckDefinition> &catalog()
{
    static const auto definitions = [] {
        const QStringList project = fixtures::decompProjectFiles();
        const QStringList rich = fixtures::richVoicegroupFiles();
        const QStringList route101 =
            project + strings({"sound/songs/midi/mus_route101.mid"}) + rich;
        const QStringList route102 =
            project + strings({"sound/songs/midi/mus_route102.mid"}) + rich;
        const QStringList bank =
            project + strings({"sound/songs/midi/mus_gym.mid", "sound/songs/midi/mus_oldale.mid"}) +
            rich;
        const auto native = [](const char *name, const char *command, const char *song,
                               const QStringList &files, Handler handler = midiExport) {
            return CheckDefinition{
                .name = name,
                .argv = {QStringLiteral("--") + QString::fromUtf8(command),
                         QStringLiteral("{scratch}"), QString::fromUtf8(song)},
                .handler = handler,
                .scratchKind = ScratchKind::ExistingDirectory,
                .fixtureRootKind = FixtureRootKind::DecompProject,
                .fixtureFiles = files,
                .environment = {{QStringLiteral("PORYDAW_AUDIO_BACKEND"), QStringLiteral("null")}},
            };
        };

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
#ifdef __APPLE__
        result.push_back({.name = "swiftcore",
                          .argv = strings({"--swiftcore", "{scratch}", "{mid2agb}"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = project + fixtures::decompMidiFiles() +
                                          strings({"test_midis/smf/valid/opaque_sysex.mid",
                                                   "test_midis/smf/valid/vlq_running_status.mid",
                                                   "test_midis/smf/valid/note_lifecycle.mid",
                                                   "test_midis/smf/malformed/duplicate_eot.mid",
                                                   "test_midis/smf/stress/automation_burst.mid"}) +
                                          rich});
#endif
        const auto appendNative = [&](const char *name, const char *command, const char *song,
                                      const QStringList &files, Handler handler = midiExport) {
            result.push_back(native(name, command, song, files, handler));
        };
        appendNative("vgbankcheck", "vgbankcheck", "mus_gym", bank, voicegroupBank);
        appendNative("exportcheck-loop", "exportcheck", "mus_route101", route101);
        appendNative("exportcheck-tail", "exportcheck", "mus_route102", route102);
        return result;
    }();
    return definitions;
}

} // namespace checks::detail
