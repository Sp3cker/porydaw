#include "checks/themelayout/tst_themelayout.h"

#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"

#include <QApplication>
#include <QLineEdit>
#include <QPushButton>
#include <QRadioButton>
#include <QSettings>
#include <QSlider>
#include <QTemporaryDir>
#include <QWizard>
#include <QtTest>

namespace {

struct DialogControls {
    QRadioButton *custom = nullptr;
    QRadioButton *darkNeutralHigh = nullptr;
    QRadioButton *immaterial = nullptr;
    QLineEdit *primary = nullptr;
    QLineEdit *accent = nullptr;
    QSlider *gridLineContrast = nullptr;
    QPushButton *apply = nullptr;
    QPushButton *close = nullptr;
};

DialogControls dialogControls(themes::ThemeDialog &dialog)
{
    return {dialog.findChild<QRadioButton *>(QStringLiteral("customModeButton")),
            dialog.findChild<QRadioButton *>(QStringLiteral("darkNeutralHighModeButton")),
            dialog.findChild<QRadioButton *>(QStringLiteral("immaterialModeButton")),
            dialog.findChild<QLineEdit *>(QStringLiteral("primaryHexEdit")),
            dialog.findChild<QLineEdit *>(QStringLiteral("accentHexEdit")),
            dialog.findChild<QSlider *>(QStringLiteral("gridLineContrastSlider")),
            dialog.findChild<QPushButton *>(QStringLiteral("themeApplyButton")),
            dialog.findChild<QPushButton *>(QStringLiteral("themeCloseButton"))};
}

bool controlsPresent(const DialogControls &controls)
{
    return controls.custom && controls.darkNeutralHigh && controls.immaterial && controls.primary &&
           controls.accent && controls.gridLineContrast && controls.apply && controls.close;
}

themes::ThemeSelection customSelection()
{
    return {themes::ThemeMode::Custom,
            themes::ColorPair{QColor(QStringLiteral("#000000")), QColor(QStringLiteral("#FFFFFF"))},
            80};
}

} // namespace

void ThemeLayoutTest::startupChromePins()
{
    QVERIFY(
        m_application->styleSheet().contains(QStringLiteral("QHeaderView::section{border:0;}")));
    QWizard wizard;
    wizard.ensurePolished();
    QCOMPARE(wizard.wizardStyle(), QWizard::ClassicStyle);

    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    themes::ThemeController controller(*m_application, settings);
    controller.restore();
    QVERIFY(
        m_application->styleSheet().contains(QStringLiteral("QHeaderView::section{border:0;}")));
}

void ThemeLayoutTest::settingsRepair()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    settings.setValue(QStringLiteral("theme/mode"), QStringLiteral("custom"));
    settings.setValue(QStringLiteral("theme/primary"), QStringLiteral("#000000"));
    settings.setValue(QStringLiteral("theme/grid-line-contrast"), QStringLiteral("invalid"));

    themes::ThemeController controller(*m_application, settings);
    controller.restore();

    QCOMPARE(controller.committedSelection().mode, themes::ThemeMode::Vanilla);
    QCOMPARE(settings.value(QStringLiteral("theme/mode")).toString(), QStringLiteral("vanilla"));
    QVERIFY(!settings.contains(QStringLiteral("theme/primary")));
    QVERIFY(!settings.contains(QStringLiteral("theme/accent")));
    QCOMPARE(settings.value(QStringLiteral("theme/grid-line-contrast")).toInt(),
             themes::defaultGridLineContrast);
}

void ThemeLayoutTest::themePersistence_data()
{
    QTest::addColumn<int>("mode");
    QTest::addColumn<QString>("storedName");
    QTest::newRow("custom") << static_cast<int>(themes::ThemeMode::Custom)
                            << QStringLiteral("custom");
    QTest::newRow("dark-neutral-high") << static_cast<int>(themes::ThemeMode::DarkNeutralHigh)
                                       << QStringLiteral("dark-neutral-high");
    QTest::newRow("immaterial") << static_cast<int>(themes::ThemeMode::Immaterial)
                                << QStringLiteral("immaterial");
}

void ThemeLayoutTest::themePersistence()
{
    QFETCH(int, mode);
    QFETCH(QString, storedName);
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const QString settingsPath = directory.filePath(QStringLiteral("settings.ini"));
    QSettings writeSettings(settingsPath, QSettings::IniFormat);
    themes::ThemeController writeController(*m_application, writeSettings);
    writeController.restore();
    const auto themeMode = static_cast<themes::ThemeMode>(mode);
    const themes::ThemeSelection selection = themeMode == themes::ThemeMode::Custom
                                                 ? customSelection()
                                                 : themes::ThemeSelection{themeMode};
    QVERIFY(writeController.commit(selection));
    writeSettings.sync();

    QSettings readSettings(settingsPath, QSettings::IniFormat);
    themes::ThemeController readController(*m_application, readSettings);
    readController.restore();
    const themes::ThemeSelection &restored = readController.committedSelection();
    QCOMPARE(restored.mode, themeMode);
    QCOMPARE(readSettings.value(QStringLiteral("theme/mode")).toString(), storedName);
    if (themeMode == themes::ThemeMode::Custom) {
        QVERIFY(restored.customColors.has_value());
        QCOMPARE(restored.customColors->primary, QColor(QStringLiteral("#000000")));
        QCOMPARE(restored.customColors->accent, QColor(QStringLiteral("#FFFFFF")));
        QCOMPARE(restored.gridLineContrast, 80);
    }
}

void ThemeLayoutTest::dialogCommitAndRevert()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    themes::ThemeController controller(*m_application, settings);
    controller.restore();
    themes::ThemeDialog dialog(controller);
    const DialogControls controls = dialogControls(dialog);
    QVERIFY(controlsPresent(controls));
    dialog.show();
    QTRY_VERIFY(dialog.isVisible());

    controls.custom->click();
    controls.primary->setText(QStringLiteral("#000000"));
    controls.accent->setText(QStringLiteral("#FFFFFF"));
    QTRY_VERIFY(controls.apply->isEnabled());
    controls.gridLineContrast->setValue(80);
    controls.apply->click();

    const themes::ThemeSelection &committed = controller.committedSelection();
    QCOMPARE(committed.mode, themes::ThemeMode::Custom);
    QVERIFY(committed.customColors.has_value());
    QCOMPARE(committed.customColors->primary, QColor(QStringLiteral("#000000")));
    QCOMPARE(committed.customColors->accent, QColor(QStringLiteral("#FFFFFF")));
    QCOMPARE(committed.gridLineContrast, 80);

    controls.darkNeutralHigh->click();
    QCOMPARE(themes::color(themes::Role::toolbar_background),
             themes::darkNeutralHigh().color(themes::Role::toolbar_background));
    controls.immaterial->click();
    QCOMPARE(themes::color(themes::Role::toolbar_background),
             themes::immaterial().color(themes::Role::toolbar_background));
    controls.gridLineContrast->setValue(10);
    controls.close->click();

    QCOMPARE(themes::color(themes::Role::link_text), QColor(QStringLiteral("#FFFFFF")));
    QCOMPARE(themes::color(themes::Role::song_view_grid),
             themes::withGridLineContrast(themes::derive(QColor(QStringLiteral("#000000")),
                                                         QColor(QStringLiteral("#FFFFFF"))),
                                          80)
                 .color(themes::Role::song_view_grid));
}
