#include "support/checkstartup.h"

#include <QApplication>
#include <QDebug>
#include <QFont>
#include <QFontDatabase>
#include <QFontInfo>
#include <QGuiApplication>
#include <QStandardPaths>

namespace checks {

void installOffscreenSystemFont(QApplication &application)
{
#if defined(Q_OS_MACOS)
    // QOffscreen's generic family is absent from CoreText's family list. Do
    // not resolve application.font(): resolving its "Sans Serif" family is
    // exactly the expensive alias lookup this avoids.
    if (QGuiApplication::platformName() == QStringLiteral("offscreen")) {
        auto font = QFont{};
        font.setFamily(QStringLiteral(".AppleSystemUIFont"));
        application.setFont(font);
    }
#elif defined(Q_OS_WIN)
    // The offscreen backend does not discover Windows system fonts. Register
    // the UI face before the platform's font pixel size is captured.
    if (QGuiApplication::platformName() == QStringLiteral("offscreen")) {
        const auto path =
            QStandardPaths::locate(QStandardPaths::FontsLocation, QStringLiteral("segoeui.ttf"));
        const auto id = QFontDatabase::addApplicationFont(path);
        const auto families = QFontDatabase::applicationFontFamilies(id);
        if (!families.isEmpty()) {
            auto font = application.font();
            font.setFamily(families.first());
            application.setFont(font);
        }
    }
#else
    Q_UNUSED(application);
#endif
}

bool initializeCheckApplication(QApplication &application)
{
    QApplication::setApplicationName(QStringLiteral("porydaw"));
    QApplication::setApplicationVersion(QStringLiteral(PORYDAW_VERSION));
    QApplication::setOrganizationName(QStringLiteral("sp3cker"));

    // The platform size captured before the bundled face replaces it, scaled
    // by the shell's body policy: max(1, round(base * 1.125)).
    const auto baseFontPx = QFontInfo(application.font()).pixelSize();
    if (baseFontPx <= 0) {
        qWarning() << "Cannot resolve the application font pixel size:" << application.font();
        return false;
    }
    for (const auto *file : {":/fonts/AtkinsonHyperlegibleNext-Regular.ttf",
                             ":/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf",
                             ":/fonts/AtkinsonHyperlegibleMono-Regular.ttf"}) {
        if (QFontDatabase::addApplicationFont(QString::fromLatin1(file)) < 0) {
            qWarning() << "Cannot load bundled font:" << file;
            return false;
        }
    }
    const auto bodyPx = qMax(1, qRound(baseFontPx * 1.125));
    auto font = application.font();
    font.setFamily(QStringLiteral("Atkinson Hyperlegible Next"));
    font.setStyleName({});
    font.setWeight(QFont::Normal);
    font.setStyle(QFont::StyleNormal);
    font.setHintingPreference(QFont::PreferNoHinting);
    font.setStyleStrategy(QFont::StyleStrategy(font.styleStrategy() | QFont::PreferAntialias));
    font.setFeature(QFont::Tag{"tnum"}, 1);
    font.setPixelSize(bodyPx);
    application.setFont(font);
    const auto resolved = QFontInfo(application.font());
    if (resolved.family() != QStringLiteral("Atkinson Hyperlegible Next") ||
        resolved.pixelSize() != bodyPx) {
        qWarning() << "Cannot resolve bundled body font:" << resolved.family()
                   << resolved.pixelSize();
        return false;
    }
    return true;
}

} // namespace checks
