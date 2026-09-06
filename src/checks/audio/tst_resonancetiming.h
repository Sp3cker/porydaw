#pragma once

// Resonance suppressor timing and gain-state cases (migrated from
// src/checks/resonancecheck.cpp, slow half): release recovery across a gap,
// the indefinitely stable plateau, the 150 ms attack time constant, and the
// per-hop step caps at both supported rates. These are the long renders and
// the documented gain-state probes (see resonancefixture.h for the
// measurement policy); kept as their own suite so they can be selected —
// and diagnosed — independently of the fast law cases.

#include <QObject>

namespace checks {

class ResonanceTimingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ResonanceTimingTest)

  public:
    ResonanceTimingTest() = default;

  private slots:
    void releaseRecoversAcrossGap();
    void plateauHoldsSixtySeconds();
    void attackReachesSixtyThreePercent();
    void hopStepCapAt48kHz();
    void rateParameterizedLawHoldsAt44kHz();
};

} // namespace checks
