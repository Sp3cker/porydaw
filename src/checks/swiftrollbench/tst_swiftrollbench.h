#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class SwiftRollBenchTest final : public QObject
{
    Q_OBJECT

  public:
    SwiftRollBenchTest(QString projectRoot, QString song);

  private slots:
    void initTestCase();

    void testScrollZoomFrameCadence();

  private:
    QString m_projectRoot;
    QString m_song;
};
