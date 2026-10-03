#pragma once

#include <vector>

#include <QFlags>
#include <QMap>
#include <QStringList>

class QApplication;

namespace checks::detail {

using Handler = int (*)(QApplication &application, const QStringList &checkArgs,
                        const QStringList &qtArgs);

enum class StartupKind { Porydaw, HandlerOwned };
enum class ScratchKind { Unused, ExistingDirectory, MustNotExistPath };
enum class FixtureRootKind { None, DecompProject, SongsMkProject };
enum class BinaryKind { Checks, Application };
enum class Windowing { Offscreen, WindowSystem };
enum class Framework { QtTest, Process };
enum class Platform { MacOS = 0x1, Windows = 0x2, Linux = 0x4 };
Q_DECLARE_FLAGS(Platforms, Platform)
Q_DECLARE_OPERATORS_FOR_FLAGS(Platforms)
inline constexpr auto allPlatforms =
    Platforms{Platform::MacOS} | Platform::Windows | Platform::Linux;

struct CheckDefinition {
    const char *name;
    QStringList argv;
    Handler handler = nullptr;
    ScratchKind scratchKind = ScratchKind::Unused;
    FixtureRootKind fixtureRootKind = FixtureRootKind::None;
    QStringList fixtureFiles = {};
    QMap<QString, QString> environment = {};
    QMap<QString, QString> optionalArgumentEnvironment = {};
    BinaryKind binary = BinaryKind::Checks;
    StartupKind startup = StartupKind::Porydaw;
    Windowing windowing = Windowing::Offscreen;
    Framework framework = Framework::QtTest;
    bool optIn = false;
    Platforms platforms = allPlatforms;
};

const std::vector<CheckDefinition> &catalog();

} // namespace checks::detail
