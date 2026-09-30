#include <QCoreApplication>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QTimer>

extern "C" void automation_bench_start();

extern "C" void automation_bench_finish(int code)
{
    QCoreApplication::exit(code);
}

extern "C" void automation_bench_drain()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    for (const auto *file : {":/fonts/AtkinsonHyperlegibleNext-Regular.ttf",
                             ":/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf",
                             ":/fonts/AtkinsonHyperlegibleMono-Regular.ttf"}) {
        if (QFontDatabase::addApplicationFont(QString::fromLatin1(file)) < 0)
            qFatal("Cannot load bundled benchmark font: %s", file);
    }
    QFont font(QStringLiteral("Atkinson Hyperlegible Next"));
    font.setPixelSize(13);
    font.setHintingPreference(QFont::PreferNoHinting);
    font.setStyleStrategy(QFont::PreferAntialias);
    font.setFeature(QFont::Tag{"tnum"}, 1);
    app.setFont(font);
    QTimer::singleShot(0, &app, [] { automation_bench_start(); });
    return app.exec();
}
