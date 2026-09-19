#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class SwiftCoreTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SwiftCoreTest)

  public:
    explicit SwiftCoreTest(QString fixtureRoot);

  private slots:
    void midiCodec();
    void musicalSemantics();
    void playback();

  private:
    QString m_fixtureRoot;
};

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
