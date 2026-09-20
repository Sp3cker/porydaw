#pragma once

#include <QObject>

namespace checks {

class MidiEngineBoundsTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MidiEngineBoundsTest)

  public:
    MidiEngineBoundsTest() = default;

  private slots:
    void programChangesRejectOutOfRangeValues();
    void noteOnsRejectOutOfRangeKeys();
};

} // namespace checks
