#include <cstdio>

#include <QApplication>
#include <QCommandLineOption>
#include <QCommandLineParser>

#include "app/RewriteWindow.h"
#include "ui/applicationstartup.h"

int main(int argc, char *argv[])
{
    auto application = QApplication{argc, argv};
    ui::installOffscreenSystemFont(application);

    if (!ui::initializePorydawApplication(application))
        return 1;

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Porydaw"));
    parser.addHelpOption();
    parser.addVersionOption();
    const QCommandLineOption projectOption(
        QStringLiteral("project"), QStringLiteral("Open project root."), QStringLiteral("path"));
    const QCommandLineOption songOption(QStringLiteral("song"), QStringLiteral("Open song label."),
                                        QStringLiteral("label"));
    parser.addOption(projectOption);
    parser.addOption(songOption);
    parser.process(application);

    auto window = RewriteWindow{};
    if (!window.isReady())
        return 1;
    window.openStartup(parser.value(projectOption), parser.value(songOption));
    ui::showPreparedWindow(window);
    return application.exec();
}
