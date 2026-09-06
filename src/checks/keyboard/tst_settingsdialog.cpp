#include "checks/keyboard/tst_settingsdialog.h"

#include <QComboBox>
#include <QDialogButtonBox>
#include <QLayout>
#include <QPushButton>
#include <QSettings>
#include <QTabWidget>
#include <QTreeWidget>
#include <QtTest>
#include <optional>

#include "ui/settingsdialog.h"

namespace {

EngineSettings configuredEngineSettings()
{
    EngineSettings settings;
    settings.pcmMixer = M4A_PCM_MIXER_SAPPY;
    settings.maxPcmChannels = 8;
    return settings;
}

SongTarget configuredSongTarget()
{
    SongCfg cfg;
    cfg.masterVolume = 110;
    return {cfg, QStringLiteral("mus_test")};
}

QStringList voicegroupArguments()
{
    return {QStringLiteral("_abandoned_ship"), QStringLiteral("_route101")};
}

} // namespace

void SettingsDialogCheckTest::initTestCase()
{
    QVERIFY2(m_settingsDirectory.isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory.path());
}

void SettingsDialogCheckTest::init()
{
    auto &registry = keymap::Registry::instance();
    m_keymapSnapshot = registry.snapshotOverrides();
    registry.resetAll();

    QSettings settings;
    m_hadPcmMixer = settings.contains(QStringLiteral("engine/pcmMixer"));
    m_pcmMixer = settings.value(QStringLiteral("engine/pcmMixer"));
}

void SettingsDialogCheckTest::cleanup()
{
    keymap::Registry::instance().restoreOverrides(m_keymapSnapshot);

    QSettings settings;
    if (m_hadPcmMixer)
        settings.setValue(QStringLiteral("engine/pcmMixer"), m_pcmMixer);
    else
        settings.remove(QStringLiteral("engine/pcmMixer"));
    settings.sync();
}

void SettingsDialogCheckTest::configuredSettingsRoundTrip()
{
    const EngineSettings engineSettings = configuredEngineSettings();
    const SongTarget songTarget = configuredSongTarget();
    SettingsDialog dialog(engineSettings, songTarget, voicegroupArguments(),
                          SettingsDialog::Tab::Engine);

    auto *const tabs = dialog.findChild<QTabWidget *>();
    QVERIFY(tabs);
    QCOMPARE(tabs->count(), 3);
    QCOMPARE(dialog.currentTab(), SettingsDialog::Tab::Engine);
    QVERIFY(tabs->tabText(1).contains(songTarget.label));

    auto *const mixer = dialog.findChild<QComboBox *>(QStringLiteral("pcmMixerCombo"));
    QVERIFY(mixer);
    QVERIFY(mixer->findData(int(M4A_PCM_MIXER_IPATIX)) >= 0);
    QVERIFY(mixer->findData(int(M4A_PCM_MIXER_SAPPY)) >= 0);
    QCOMPARE(mixer->currentData().toInt(), int(M4A_PCM_MIXER_SAPPY));
    QCOMPARE(mixer->count(), 2);
    mixer->setCurrentIndex(mixer->findData(int(M4A_PCM_MIXER_IPATIX)));
    QCOMPARE(dialog.engineSettings().pcmMixer, M4A_PCM_MIXER_IPATIX);

    dialog.setCurrentTab(SettingsDialog::Tab::Song);
    QCOMPARE(dialog.currentTab(), SettingsDialog::Tab::Song);
    const std::optional<SongCfg> editedSong = dialog.songCfg();
    QVERIFY(editedSong.has_value());
    QCOMPARE(editedSong->masterVolume, songTarget.cfg.masterVolume);
    QCOMPARE(editedSong->reverb, songTarget.cfg.reverb);

    dialog.setCurrentTab(SettingsDialog::Tab::Keyboard);
    QCOMPARE(dialog.currentTab(), SettingsDialog::Tab::Keyboard);
    QVERIFY(dialog.findChild<QTreeWidget *>());
}

void SettingsDialogCheckTest::keyboardApplySurvivesCancel()
{
    auto &registry = keymap::Registry::instance();
    const QString nudgeLeft = QStringLiteral("roll.nudge_left");
    registry.setBinding(nudgeLeft, QKeySequence(QStringLiteral("Ctrl+Alt+Left")));

    SettingsDialog dialog(configuredEngineSettings(), configuredSongTarget(), voicegroupArguments(),
                          SettingsDialog::Tab::Keyboard);
    QSignalSpy applied(&dialog, &SettingsDialog::applyRequested);
    QVERIFY(applied.isValid());
    dialog.show();
    QTRY_VERIFY(dialog.isVisible());

    const QKeySequence appliedBinding(QStringLiteral("Alt+Left"));
    registry.setBinding(nudgeLeft, appliedBinding);
    QPushButton *button = nullptr;
    const QList<QPushButton *> buttons = dialog.findChildren<QPushButton *>();
    for (QPushButton *const candidate : buttons) {
        if (candidate->text() == QStringLiteral("Apply")) {
            button = candidate;
            break;
        }
    }
    QVERIFY(button);
    button->click();
    QCOMPARE(applied.count(), 1);
    QVERIFY(dialog.isVisible());

    auto *const dialogButtons = dialog.findChild<QDialogButtonBox *>();
    QVERIFY(dialogButtons);
    QLayout *const layout = dialog.layout();
    QVERIFY(layout);
    const int applyGap = dialogButtons->geometry().left() - button->geometry().right() - 1;
    QVERIFY(applyGap >= 0);
    QVERIFY(applyGap <= layout->spacing());

    registry.setBinding(nudgeLeft, QKeySequence(QStringLiteral("Shift+Left")));
    QPushButton *const cancel = dialogButtons->button(QDialogButtonBox::Cancel);
    QVERIFY(cancel);
    cancel->click();
    QCOMPARE(registry.bindings(nudgeLeft), QList<QKeySequence>{appliedBinding});
}

void SettingsDialogCheckTest::unavailableSongTabFallsBackToEngine()
{
    SettingsDialog dialog(configuredEngineSettings(), std::nullopt, voicegroupArguments(),
                          SettingsDialog::Tab::Song);

    auto *const tabs = dialog.findChild<QTabWidget *>();
    QVERIFY(tabs);
    QCOMPARE(tabs->count(), 3);
    QVERIFY(!tabs->isTabEnabled(1));
    QCOMPARE(dialog.currentTab(), SettingsDialog::Tab::Engine);
    QVERIFY(!dialog.songCfg().has_value());
}

void SettingsDialogCheckTest::engineMixerPersistsAndRejectsInvalidValue()
{
    EngineSettings persisted = configuredEngineSettings();
    persisted.pcmMixer = M4A_PCM_MIXER_SAPPY;
    persisted.save();
    QCOMPARE(EngineSettings::load().pcmMixer, M4A_PCM_MIXER_SAPPY);

    QSettings settings;
    settings.setValue(QStringLiteral("engine/pcmMixer"), QStringLiteral("invalid"));
    settings.sync();
    QCOMPARE(EngineSettings::load().pcmMixer, M4A_PCM_MIXER_IPATIX);
    persisted.save();
}

int runSettingsDialogCheck(const QStringList &qtArguments)
{
    SettingsDialogCheckTest test;
    QStringList arguments{QStringLiteral("settings-dialog")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
