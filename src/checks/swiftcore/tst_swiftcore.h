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
    void noteEdits();
    void documentHistory();
    void eventEdits();
    void xcmdEdits();
    void midiImport();
};

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
