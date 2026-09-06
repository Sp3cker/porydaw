#pragma once

// Resonance suppressor law (migrated from src/checks/resonancecheck.cpp,
// signal-level half): bypass transparency, the plateau/saturation law, guard
// bins, spectral-contrast program interaction, stereo determinism, and the
// mid-stream disable path. Every case owns a fresh suppressor and vectors —
// nothing is shared across slots. The slow gain-state cases (release, 60 s
// hold, attack, step caps) live in the resonance timing suite.

#include <QObject>

namespace checks {

class ResonanceLawTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ResonanceLawTest)

  public:
    ResonanceLawTest() = default;

  private slots:
    void disabledPathIsBitExact();
    void unitMaskReconstructionFloor();
    void belowThresholdTonePasses();
    void shippingDefaultLimitsSaturatedResonance();
    void testCurvePlateauAboveGuard();
    void lowBandTonePassesThrough();
    void saturationPlateausWithoutOvershoot();
    void levelStaircaseHoldsPlateau();
    void dualTonesEngageSeparately();
    void broadbandProgramPasses();
    void embeddedLoudToneEngagesProgramSurvives();
    void embeddedModestToneEngagesGently();
    void stereoChannelsStayBitIdentical();
    void midStreamDisableRestoresBypass();
    void guardBinsNeverMasked();
};

} // namespace checks
