#include "cursor_probe.h"

#include <QtCore/qcoreapplication.h>
#include <QtGui/qcursor.h>
#include <QtGui/qfont.h>
#include <QtGui/qfontdatabase.h>
#include <QtGui/qguiapplication.h>
#include <QtGui/qicon.h>
#include <QtGui/qimage.h>
#include <QtGui/qpixmap.h>
#include <QtQml/qqml.h>
#include <QtQml/qqmlfile.h>

namespace {

QImage artImage(const QUrl &url, int extent, qreal dpr)
{
    return QIcon(QQmlFile::urlToLocalFileOrQrc(url))
        .pixmap(QSize(extent, extent), dpr)
        .toImage();
}

void registerCursorProbe()
{
    qmlRegisterType<CursorProbe>("PorydawRollTest", 1, 0, "CursorProbe");
}

// The QTest child never runs checkstartup, so its application font stays Qt's
// "Sans Serif": absent from CoreText, every child pays a ~130ms alias scan on
// its first text. Register the staged faces and point the default font at the
// bundled body before any QML resolves a family. Size is untouched: only the
// family swaps, so default-text metrics keep the platform size.
void installRollCheckFonts()
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

Q_COREAPP_STARTUP_FUNCTION(registerCursorProbe)
Q_COREAPP_STARTUP_FUNCTION(installRollCheckFonts)

bool CursorProbe::artDiffers(const QUrl &leftUrl, const QUrl &rightUrl,
                             int extent, qreal devicePixelRatio) const
{
    if (extent <= 0)
        return false;
    const QImage left = artImage(leftUrl, extent, devicePixelRatio);
    const QImage right = artImage(rightUrl, extent, devicePixelRatio);
    return !left.isNull() && !right.isNull() && left != right;
}

bool CursorProbe::matchesArt(QQuickItem *item, const QUrl &artUrl, int extent,
                             qreal devicePixelRatio) const
{
    if (!item || extent <= 0 || item->cursor().shape() != Qt::BitmapCursor)
        return false;
    const QImage expected = artImage(artUrl, extent, devicePixelRatio);
    return !expected.isNull() && item->cursor().pixmap().toImage() == expected;
}
