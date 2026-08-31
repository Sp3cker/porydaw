#include <cstdio>

#include <QApplication>

#include "mainwindow.h"
#include "ui/applicationstartup.h"

int main(int argc, char *argv[])
{
    auto application = QApplication{argc, argv};
    ui::installOffscreenSystemFont(application);

    if (!ui::initializePorydawApplication(application))
        return 1;
    if (application.arguments().contains(QStringLiteral("--version"))) {
        std::printf("porydaw %s (Qt %s)\n", PORYDAW_VERSION, qVersion());
        return 0;
    }
    auto window = MainWindow{};
    ui::showPreparedWindow(window);
    return application.exec();
}
