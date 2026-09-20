#include "checkcatalog.h"

#include "fixturecatalog.hpp"
#include "fwd.hpp"

#include <initializer_list>
#include <utility>

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

int retained(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    QString mode = argumentAt(arguments, 0);
    if (mode.startsWith(QStringLiteral("--")))
        mode.remove(0, 2);
    return runRetainedBoundaryCheck(mode, argumentAt(arguments, 1), argumentAt(arguments, 2),
                                    argumentAt(arguments, 3), qtArguments);
}

#ifdef __APPLE__
int swiftCore(QApplication &, const QStringList &arguments, const QStringList &qtArguments)
{
    return runSwiftCoreCheck(argumentAt(arguments, 1), qtArguments);
}
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
        const QStringList gym = project + strings({"sound/songs/midi/mus_gym.mid"}) + editor;
        const auto native = [](const char *name, const char *command, const char *song,
                               const QStringList &files) {
            return CheckDefinition{
                .name = name,
                .argv = {QStringLiteral("--") + QString::fromUtf8(command),
                         QStringLiteral("{scratch}"), QString::fromUtf8(song)},
                .handler = retained,
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
#ifdef __APPLE__
        result.push_back({.name = "swiftcore",
                          .argv = strings({"--swiftcore", "{scratch}"}),
                          .handler = swiftCore,
                          .scratchKind = ScratchKind::ExistingDirectory,
                          .fixtureRootKind = FixtureRootKind::DecompProject,
                          .fixtureFiles = fixtures::decompMidiFiles() +
                                          strings({"test_midis/smf/valid/opaque_sysex.mid",
                                                   "test_midis/smf/valid/vlq_running_status.mid",
                                                   "test_midis/smf/valid/note_lifecycle.mid",
                                                   "test_midis/smf/malformed/duplicate_eot.mid",
                                                   "test_midis/smf/stress/automation_burst.mid"})});
#endif
        const auto appendNative = [&](const char *name, const char *command, const char *song,
                                      const QStringList &files) {
            auto definition = native(name, command, song, files);
            if (QString::fromUtf8(command) == QStringLiteral("roundtrip"))
                definition.argv.append(QStringLiteral("{mid2agb}"));
            result.push_back(std::move(definition));
        };
        appendNative("roundtrip", "roundtrip", "mus_route101", route101);
        appendNative("savecheck", "savecheck", "mus_route101", route101);
        appendNative("vgbankcheck", "vgbankcheck", "mus_gym", gym);
        appendNative("vgsavecheck", "vgsavecheck", "mus_route101", route101 + editor);
        appendNative("loopcheck", "loopcheck", "mus_route101", route101);
        appendNative("primecheck", "primecheck", "mus_route101", route101);
        appendNative("transportcheck", "transportcheck", "mus_route101", route101);
        appendNative("trackactivitycheck", "trackactivitycheck", "mus_route101", route101);
        appendNative("exportcheck-loop", "exportcheck", "mus_route101", route101);
        appendNative("exportcheck-tail", "exportcheck", "mus_route102", route102);
        return result;
    }();
    return definitions;
}

} // namespace checks::detail
