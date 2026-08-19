#include <cstdio>

#include <QApplication>

#include "mainwindow.h"
#include "ui/applicationstartup.h"

int main(int argc, char *argv[])
{
    auto application = QApplication{argc, argv};
    if (!ui::initializePorydawApplication(application))
        return 1;
    if (application.arguments().contains(QStringLiteral("--version"))) {
        std::printf("porydaw %s (Qt %s)\n", PORYDAW_VERSION, qVersion());
        return 0;
    }
    auto window = MainWindow{};
    ui::showCoveredWhileRestoring(window, [&window] { window.restoreSession(); });
    return application.exec();
}
