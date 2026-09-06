#pragma once

// Transport transitions into silence (pause, stop, and starting playback over
// a ringing audition) must not step the output waveform. Migrated from
// src/checks/clickcheck.cpp onto the real AudioEngine: the scenarios drive
// the production process() path on a parked null-backend device (no physical
// audio) and assert the sample-to-sample steps around each transition stay
// near the signal's own natural step size. The old harness's shadow
// CutFader/Driver transport state machine is gone — every fade, cut, drain,
// and deferred-start decision exercised here is production's own.

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include <QObject>
#include <QString>

#include "audio/audioengine.h"
#include "checks/audio/clickrig.h"
#include "core/miditimeline.h"

namespace checks {

class ClickTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ClickTest)

  public:
    ClickTest() = default;

  private slots:
    void initTestCase();
    void cleanupTestCase();

    // Smooth-cut scenarios (the audible-no-click contract).
    void pauseFadesSilently_data();
    void pauseFadesSilently();
    void stopFadesSilently();
    void playOverAuditionFadesSilently();
    // Song-start-at-zero exception: the first sequenced note is NOT cut and
    // begins at full output gain after the settle hold.
    void songStartReachesFullGain();
    // Newest transport wins while a fade is in flight; no stuck fade, no
    // lost note.
    void rapidRetargetKeepsNewestTransport();
    // Timed band-sweep previews never leak note-offs into the song note;
    // post-cut commands wait deterministically for the deferred cut.
    void timedPreviewCutDefersCommands();
    // Song reload clears interrupted fade state; the new song starts loud.
    void reloadAfterInterruptedFadeStartsLoud();

    // Negative controls: the deliberately abrupt pre-fade interface (both
    // engines cut at once at full gain) must register a click — proof that
    // the detector is sensitive. DC rows only: square waves' natural edges
    // exceed a hard cut's step, so they are unsuitable controls.
    void hardCutControlsClick_data();
    void hardCutControlsClick();

  private:
    struct Capture {
        std::vector<float> left;
        std::vector<float> right;

        std::size_t frames() const { return left.size(); }
    };

    // Per-case rig: fresh forced-null engine with the device parked, the
    // borrowed click voicegroup, and the sustain song built at the engine's
    // live rate. Every slot constructs its own — no state crosses cases.
    struct Rig {
        explicit Rig(bool square) : voicegroup(square) {}

        ClickVoicegroup voicegroup;
        std::shared_ptr<const MidiTimeline> timeline;
        AudioEngine engine;
        QString error;
    };

    // Returns false (after recording the failure) so a slot can bail out
    // instead of running against a half-initialized rig.
    bool startRig(Rig &rig);
    bool loadSustainSong(Rig &rig);
    void render(AudioEngine &engine, uint64_t frames, Capture &capture);
    // Renders one frame at a time until the engine's applied transport
    // reaches `target` (bounded by one second of frames). Captures every
    // rendered frame; `onset` receives the frame count at the flip.
    bool spinUntilApplied(AudioEngine &engine, Transport target, Capture &capture,
                          std::size_t *onset = nullptr);
    bool sounding(const AudioEngine &engine, uint8_t midiKey) const;
    bool sustaining(const AudioEngine &engine, uint8_t midiKey) const;
    void verifyTransition(const char *what, const Capture &capture, std::size_t at,
                          TransitionExpectation expectation) const;

    QString m_priorBackendEnv;
};

} // namespace checks
