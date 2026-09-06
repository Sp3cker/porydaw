#pragma once

// Track meter intensity state machine (migrated from
// src/checks/trackactivitycheck.cpp). Pure model tests — no audio device, no
// UI: attack/release/retrigger/pause-fill/resume chains each run on their own
// scratch TrackActivity so no temporal case inherits another's state.

#include <QObject>

namespace checks {

class TrackActivityTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackActivityTest)

  public:
    TrackActivityTest() = default;

  private slots:
    void freshActivityIsDark();
    void attackRetainsStereoTargets_data();
    void attackRetainsStereoTargets();
    void releaseIsGradualAndMonotonic();
    void imperceptibleTailSnapsToZero();
    void retriggerRetainsInertia();
    void resetClearsEveryLight();
    void pausedFillSettlesEveryTrack();
    void resumeUsesFastWindowThenOrdinaryRelease();
    void rapidPauseRearmsFastDescent();
    void clampedElapsedNeedsTicksWithoutMovement();
};

} // namespace checks
