#include "checks/keyboard/tst_settingsdialog.h"

#include <QComboBox>
#include <QSettings>
#include <QTabWidget>
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
    QSettings settings;
    m_hadPcmMixer = settings.contains(QStringLiteral("engine/pcmMixer"));
    m_pcmMixer = settings.value(QStringLiteral("engine/pcmMixer"));
}

void SettingsDialogCheckTest::cleanup()
{
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
    QCOMPARE(dialog.currentTab(), SettingsDialog::Tab::Engine);

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
}

void SettingsDialogCheckTest::unavailableSongTabFallsBackToEngine()
{
    SettingsDialog dialog(configuredEngineSettings(), std::nullopt, voicegroupArguments(),
                          SettingsDialog::Tab::Song);

    auto *const tabs = dialog.findChild<QTabWidget *>();
    QVERIFY(tabs);
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
