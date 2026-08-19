#include "ui/applicationstartup.h"
#include "ui/theme/themecheck.h"

#include <QApplication>
#include <QFontInfo>
#include <QPalette>
#include <QSettings>
#include <QStringList>
#include <QTemporaryDir>

int runFontCheck(int expectedBaseFontPx);

int runThemeHarness(QApplication &application, const QString &command)
{
    QTemporaryDir settingsDirectory;
    if (!settingsDirectory.isValid())
        return 1;
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDirectory.path());
    QApplication::setApplicationName(QStringLiteral("porydaw"));
    QApplication::setApplicationVersion(QStringLiteral("0.1.0"));
    QApplication::setOrganizationName(QStringLiteral("huderlem"));
    const auto expectedBaseFontPx = QFontInfo(application.font()).pixelSize();
    const bool darkBaseline = command == QStringLiteral("--darkbasecheck");
    if (darkBaseline) {
        // Model a dark-platform boot exactly: Fusion (as porydaw's main forces
        // everywhere), then a hostile platform palette, then normal startup —
        // initializeApplication captures the poisoned baseline underneath the
        // theme, as a dark macOS system palette would sit on real hardware.
        application.setStyle(QStringLiteral("fusion"));
        QPalette poisoned = application.palette();
        for (int group = 0; group < QPalette::NColorGroups; ++group) {
            for (int role = 0; role < QPalette::NColorRoles; ++role) {
                poisoned.setColor(static_cast<QPalette::ColorGroup>(group),
                                  static_cast<QPalette::ColorRole>(role), kDarkBaselinePoison);
            }
        }
        application.setPalette(poisoned);
    }
    if (!ui::initializeApplication(application))
        return 1;
    if (darkBaseline)
        return runDarkBaselineCheck();
    if (command == QStringLiteral("--fontcheck"))
        return runFontCheck(expectedBaseFontPx);
    if (command == QStringLiteral("--themecheck"))
        return runThemeCheck();
    return 2;
}
