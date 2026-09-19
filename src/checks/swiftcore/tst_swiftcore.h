#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class SwiftCoreTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SwiftCoreTest)

  public:
    SwiftCoreTest() = default;

  private slots:
    void midiCodec();
    void musicalSemantics();
    void playback();
};

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
