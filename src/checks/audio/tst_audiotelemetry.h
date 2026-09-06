#pragma once

// Deterministic activity telemetry (migrated from src/checks/audiocheck.cpp,
// pure half): byte-order-stable pack/unpack for the renderer/IPC level
// format, per-track meter source math, the output-volume clamp, and the
// fresh-engine telemetry drain. No audio device is touched; the same
// functions are additionally pinned at compile time by the static_asserts in
// audio/trackactivitylevel.h.

#include <QObject>

namespace checks {

class AudioTelemetryTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AudioTelemetryTest)

  public:
    AudioTelemetryTest() = default;

  private slots:
    void packedActivityPreservesByteOrder_data();
    void packedActivityPreservesByteOrder();
    void unpackConsumesOnlyActivityBytes();
    void maxLevelIsComponentWise();
    void pcmPanRetainsEnvelope_data();
    void pcmPanRetainsEnvelope();
    void outputVolumeClamps();
    void freshConsumeIsAllDark();
};

} // namespace checks
