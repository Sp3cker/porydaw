#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include "project/decompproject.h"

class MidiRoundtripTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MidiRoundtripTest)

  public:
    MidiRoundtripTest(QString projectRoot, QString mid2agbPath);

  private slots:
    void initTestCase();
    void songM2Roundtrip_data();
    void songM2Roundtrip();

  private:
    QString m_projectRoot;
    QString m_mid2agbPath;
    DecompProject m_project;
};

int runRoundTrip(const QString &projectRoot, const QString &mid2agbPath,
                 const QStringList &qtArguments);
