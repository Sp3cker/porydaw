#pragma once

#include <QKeySequence>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QVariant>

#include "ui/keymap.h"

class SettingsDialogCheckTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SettingsDialogCheckTest)

  public:
    SettingsDialogCheckTest() = default;

  private slots:
    void initTestCase();
    void init();
    void cleanup();

    void configuredSettingsRoundTrip();
    void keyboardApplySurvivesCancel();
    void unavailableSongTabFallsBackToEngine();
    void engineMixerPersistsAndRejectsInvalidValue();

  private:
    keymap::Registry::OverrideSnapshot m_keymapSnapshot;
    bool m_hadPcmMixer = false;
    QVariant m_pcmMixer;
    QTemporaryDir m_settingsDirectory;
};

int runSettingsDialogCheck(const QStringList &qtArguments);
