#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class MidiExportTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MidiExportTest)

  public:
    MidiExportTest(QString projectRoot, QString songLabel);

  private slots:
    void initTestCase();
    void durationCalculationMatchesRenderParity();
    void offlineExportProducesValidRiffPcm();
    void resonanceSuppressionChangesPcmWithoutChangingFrames();
    void cancelledExportRemovesPartialFile();

  private:
    QString m_projectRoot;
    QString m_songLabel;
};

int runExportCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);
