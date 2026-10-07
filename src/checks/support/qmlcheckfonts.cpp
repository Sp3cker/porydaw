// Every QML check binary (roll, editor, shell) spawns one child process per
// suite through QTestAppCpp, which never runs checkstartup: the application
// font stays Qt's "Sans Serif", absent from CoreText, so each child pays a
// ~130-250ms alias scan on its first text. Register the staged faces and
// point the default font at the bundled body from a QCoreApplication startup
// function, before any QML resolves a family. Size is untouched: only the
// family swaps, so default-text metrics keep the platform size.
#include <QtCore/qcoreapplication.h>
#include <QtGui/qfont.h>
#include <QtGui/qfontdatabase.h>
#include <QtGui/qguiapplication.h>

namespace {

void installQmlCheckFonts()
{
    if (QCoreApplication::instance() == nullptr)
        return;
#if defined(Q_OS_MACOS)
    if (QGuiApplication::platformName() == QStringLiteral("offscreen")) {
        auto offscreenFont = QFont{};
        offscreenFont.setFamily(QStringLiteral(".AppleSystemUIFont"));
        QGuiApplication::setFont(offscreenFont);
        return;
    }
    const auto fontDirectory =
        QCoreApplication::applicationDirPath() + QStringLiteral("/../Resources");
#else
    const auto fontDirectory = QCoreApplication::applicationDirPath();
#endif
    for (const auto *file : {"/AtkinsonHyperlegibleNext-Regular.ttf",
                             "/AtkinsonHyperlegibleNext-SemiBold.ttf",
                             "/AtkinsonHyperlegibleMono-Regular.ttf",
                             "/PorydawIcons.otf"}) {
        QFontDatabase::addApplicationFont(fontDirectory + QLatin1StringView(file));
    }
    auto font = QGuiApplication::font();
    font.setFamily(QStringLiteral("Atkinson Hyperlegible Next"));
    font.setStyleName({});
    font.setWeight(QFont::Normal);
    font.setStyle(QFont::StyleNormal);
    font.setHintingPreference(QFont::PreferNoHinting);
    font.setStyleStrategy(QFont::StyleStrategy(font.styleStrategy() | QFont::PreferAntialias));
    font.setFeature(QFont::Tag{"tnum"}, 1);
    QGuiApplication::setFont(font);
}

} // namespace

Q_COREAPP_STARTUP_FUNCTION(installQmlCheckFonts)
