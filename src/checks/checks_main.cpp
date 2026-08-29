#include <cstdio>

#include <QApplication>

#include "checkregistry.hpp"
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
    const auto result = checks::runRequested(application, arguments);
    if (result)
        return *result;
    std::fprintf(stderr, "porydaw_checks: no check command supplied\n");
    return 2;
}
