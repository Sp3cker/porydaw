#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QVariant>

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
    void unavailableSongTabFallsBackToEngine();
    void engineMixerPersistsAndRejectsInvalidValue();

  private:
    bool m_hadPcmMixer = false;
    QVariant m_pcmMixer;
    QTemporaryDir m_settingsDirectory;
};

int runSettingsDialogCheck(const QStringList &qtArguments);
