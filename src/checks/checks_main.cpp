#include <cstdio>

#include <QApplication>

#include "checkregistry.hpp"
#ifdef Q_OS_MACOS
#include "checks/support/nativeapplication.h"
#endif
#include "ui/applicationstartup.h"

int main(int argc, char *argv[])
{
    if (!qEnvironmentVariableIsSet("PORYDAW_AUDIO_BACKEND"))
        qputenv("PORYDAW_AUDIO_BACKEND", "null");
    auto application = QApplication{argc, argv};
    ui::installOffscreenSystemFont(application);

    const auto arguments = application.arguments();
    if (checks::writeManifest(arguments))
        return 0;
#ifdef Q_OS_MACOS
    if (QApplication::platformName() == QLatin1String("cocoa") &&
        !checks::prepareNativeApplication()) {
        std::fprintf(stderr,
                     "porydaw_checks: Cocoa refused a foreground-capable activation policy\n");
        return 2;
    }
#endif
    const auto result = checks::runRequested(application, arguments);
    if (result)
        return *result;
    std::fprintf(stderr, "porydaw_checks: no check command supplied\n");
    return 2;
}
