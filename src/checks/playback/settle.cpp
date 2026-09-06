#include <QTest>
#include <algorithm>
#include <cmath>
#include <memory>
#include <span>
#include <vector>

#include "audio/audioengine.h"
#include "audio/resonance_suppressor.h"
#include "checks/playback/transportfixture.h"
#include "checks/playback/tst_transport.h"
#include "checks/support/audioengineaccess.h"
#include "project/voicegroupsource.h"

namespace checks {

bool TransportTest::parkSuppressed(AudioEngine &engine)
{
    if (!AudioEngineTestAccess::parkDevice(engine)) {
        QTest::qFail("could not stop the audio device for deterministic suppressor checks",
                     __FILE__, __LINE__);
        return false;
    }
    engine.setResonanceSuppression(true);
    return true;
}

std::vector<float> TransportTest::renderParked(AudioEngine &engine, uint32_t frames)
{
    auto output = std::vector<float>(static_cast<std::size_t>(frames) * 2);
    AudioEngineTestAccess::renderParked(engine, std::span<float>(output));
    return output;
}

float TransportTest::peak(const std::vector<float> &audio)
{
    auto value = 0.0f;
    for (const auto sample : audio)
        value = std::max(value, std::abs(sample));
    return value;
}

double TransportTest::deepestResonanceGain(AudioEngine &engine) const
{
    auto gain = 0.0;
    for (auto bin = 1; bin < ResonanceSuppressor::kN / 2; ++bin)
        gain = std::min(gain, engine.m_resonance.binGainDb(bin));
    return gain;
}

// Renders one frame at a time until the audio thread applied the requested
// transport, bounded by one second of rendering.
bool TransportTest::renderUntilApplied(AudioEngine &engine, int transport)
{
    uint32_t frames = 0;
    while (engine.m_appliedTransport != transport && frames < uint32_t(engine.sampleRate())) {
        renderParked(engine, 1);
        ++frames;
    }
    return engine.m_appliedTransport == transport;
}

// Parks the device (no live callback races the manual process() renders)
// and enables suppression, then plays the note song for three seconds: the
// song must sound and the suppressor must adapt (deepest bin gain below
// -0.1 dB). The regression slots below inherit this precondition.
bool TransportTest::engageSuppressorWithNoteSong(AudioEngine &engine)
{
    if (!parkSuppressed(engine))
        return false;
    auto timeline = loadedSong(buildNoteSong(), "note song built wrong");
    if (!timeline) {
        QTest::qFail("note song built wrong", __FILE__, __LINE__);
        return false;
    }
    engine.loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine.play();
    if (!renderUntilApplied(engine, static_cast<int>(Transport::Playing))) {
        QTest::qFail("initial play was not applied", __FILE__, __LINE__);
        return false;
    }
    const auto playingAudio = renderParked(engine, uint32_t(3.0 * engine.sampleRate()));
    if (peak(playingAudio) < 0.01f || deepestResonanceGain(engine) >= -0.1) {
        QTest::qFail("active suppressor control signal did not play or engage", __FILE__, __LINE__);
        return false;
    }
    return true;
}

// Song start: play applies at full output gain and the player stays at
// position zero until the gain reaches unity — the first note is neither
// consumed nor attenuated by the start transition.
void TransportTest::songStartEntersAtUnityGain()
{
    QVERIFY2(parkSuppressed(engine()), "could not park the device for deterministic checks");
    auto timeline = loadedSong(buildNoteSong(), "note song built wrong");
    QVERIFY2(timeline, "note song built wrong");
    engine().loadSong(timeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});

    engine().play();
    if (!renderUntilApplied(engine(), static_cast<int>(Transport::Playing))) {
        QTest::qFail("initial play was not applied", __FILE__, __LINE__);
        return;
    }
    QVERIFY2(engine().m_cutFadeGain >= 0.999f, "initial play began below full output gain");
    QVERIFY2(engine().m_player.position() == 0,
             "initial play advanced before reaching full output gain");

    const auto playingAudio = renderParked(engine(), uint32_t(3.0 * engine().sampleRate()));
    QVERIFY2(peak(playingAudio) >= 0.01f && deepestResonanceGain(engine()) < -0.1,
             "active suppressor control signal did not play or engage");
}

// Pause preserves the suppressor's adaptation state; it must not re-prime
// from 0 dB when playback resumes.
void TransportTest::pausePreservesSuppressorAdaptation()
{
    if (!engageSuppressorWithNoteSong(engine()))
        return;
    engine().pause();
    renderParked(engine(), engine().m_outputGainRampSamples + 512);
    QVERIFY2(engine().m_appliedTransport == static_cast<int>(Transport::Paused),
             "pause was not applied during active suppressor check");
    QVERIFY2(deepestResonanceGain(engine()) < -0.1, "pause reset active suppressor gain state");

    auto pauseDrainFrames = uint32_t{0};
    while (engine().m_cutFadeActive && pauseDrainFrames < uint32_t(engine().sampleRate())) {
        renderParked(engine(), 512);
        pauseDrainFrames += 512;
    }
    engine().play();
    QVERIFY2(renderUntilApplied(engine(), static_cast<int>(Transport::Playing)),
             "resume was not applied during active suppressor check");
    QVERIFY2(deepestResonanceGain(engine()) < -0.1,
             "resume re-primed active suppressor gain state");
}

// Stop is a discontinuity: once the zero-gain cut is applied, no delayed
// pre-stop samples may escape during the hold or fade-up.
void TransportTest::stopLeaksNoDelayedSuppressorAudio()
{
    if (!engageSuppressorWithNoteSong(engine()))
        return;
    renderParked(engine(), uint32_t(0.5 * engine().sampleRate()));
    engine().stop();
    if (!renderUntilApplied(engine(), static_cast<int>(Transport::Stopped))) {
        QTest::qFail("stop was not applied during active suppressor check", __FILE__, __LINE__);
        return;
    }
    const uint32_t settle = engine().m_cutFadeSettleSamples;
    const uint32_t ramp = engine().m_outputGainRampSamples;
    const auto stoppedAudio = renderParked(engine(), settle + ramp + ResonanceSuppressor::kLatency);
    const float stoppedPeak = peak(stoppedAudio);
    const auto firstLeak = std::find_if(stoppedAudio.cbegin(), stoppedAudio.cend(),
                                        [](float sample) { return std::abs(sample) > 1.0e-7f; });
    const bool leaked = firstLeak != stoppedAudio.cend();
    const std::size_t firstFrame =
        leaked ? std::size_t(std::distance(stoppedAudio.cbegin(), firstLeak)) / 2 : 0;
    const float firstSample = leaked ? *firstLeak : 0.0f;
    const auto lastLeak = std::find_if(stoppedAudio.crbegin(), stoppedAudio.crend(),
                                       [](float sample) { return std::abs(sample) > 1.0e-7f; });
    const std::size_t lastFrame =
        leaked ? (stoppedAudio.size() - 1 -
                  std::size_t(std::distance(stoppedAudio.crbegin(), lastLeak))) /
                     2
               : 0;
    const char *phase = !leaked                                   ? "none"
                        : firstFrame < settle                     ? "hold"
                        : firstFrame < std::size_t(settle) + ramp ? "fade-up"
                                                                  : "post-ramp";
    QVERIFY2(stoppedPeak <= 1.0e-7f,
             qUtf8Printable(QStringLiteral("stopped transport leaked delayed suppressor audio: "
                                           "peak %1; first sample %2 at frame %3 (%4), last frame "
                                           "%5; settle=%6 ramp=%7; end cut active=%8 rising=%9 "
                                           "remaining=%10 hold=%11 gain=%12")
                                .arg(stoppedPeak)
                                .arg(firstSample)
                                .arg(firstFrame)
                                .arg(QLatin1String(phase))
                                .arg(lastFrame)
                                .arg(settle)
                                .arg(ramp)
                                .arg(engine().m_cutFadeActive)
                                .arg(engine().m_cutFadeRising)
                                .arg(engine().m_cutFadeRemaining)
                                .arg(engine().m_cutFadeHold)
                                .arg(engine().m_cutFadeGain)));
}

// Restarting with suppression still enabled must produce the song again
// after the transport transition.
void TransportTest::restartProducesAudioWithSuppression()
{
    if (!engageSuppressorWithNoteSong(engine()))
        return;
    engine().stop();
    if (!renderUntilApplied(engine(), static_cast<int>(Transport::Stopped))) {
        QTest::qFail("stop was not applied before the restart check", __FILE__, __LINE__);
        return;
    }
    engine().play();
    if (!renderUntilApplied(engine(), static_cast<int>(Transport::Playing))) {
        QTest::qFail("restart was not applied during active suppressor check", __FILE__, __LINE__);
        return;
    }
    const auto restartedAudio = renderParked(engine(), 2 * ResonanceSuppressor::kN);
    QVERIFY2(peak(restartedAudio) >= 0.01f,
             "restart did not produce audio with suppression active");
}

// Starting again from position zero after a prior playback must not reuse
// the normal resume fade and soften the first note: a song-start play
// enters at unity gain with the player still at zero.
void TransportTest::secondSongStartDoesNotReuseResumeFade()
{
    if (!engageSuppressorWithNoteSong(engine()))
        return;
    engine().pause();
    auto secondPauseFrames = uint32_t{0};
    while ((engine().m_appliedTransport != static_cast<int>(Transport::Paused) ||
            engine().m_cutFadeActive) &&
           secondPauseFrames < uint32_t(engine().sampleRate())) {
        renderParked(engine(), 512);
        secondPauseFrames += 512;
    }
    engine().seek(0);
    renderParked(engine(), 1);
    engine().play();
    if (!renderUntilApplied(engine(), static_cast<int>(Transport::Playing))) {
        QTest::qFail("second song-start play was not applied", __FILE__, __LINE__);
        return;
    }
    QVERIFY2(engine().m_cutFadeGain >= 0.999f,
             "second song-start play began below full output gain");
    QVERIFY2(engine().m_player.position() == 0,
             "second song-start play advanced before reaching full output gain");
}

// Resume at a nonzero cursor: the transition must keep the sequencer parked
// through the zero-gain settle hold — no player advance, no note rendered
// below full output gain — and enter Playing at unity cut-fade gain, so the
// first resumed interval is neither consumed nor attenuated. Playing stays
// applied through the pause fade-down, so the resume cursor is captured
// only after the pause settles.
void TransportTest::resumeParksSequencerThroughSettle()
{
    if (!engageSuppressorWithNoteSong(engine()))
        return;
    renderParked(engine(), uint32_t(0.25 * engine().sampleRate()));
    engine().pause();
    auto resumePauseFrames = uint32_t{0};
    while ((engine().m_appliedTransport != static_cast<int>(Transport::Paused) ||
            engine().m_cutFadeActive) &&
           resumePauseFrames < uint32_t(engine().sampleRate())) {
        renderParked(engine(), 1);
        ++resumePauseFrames;
    }
    QVERIFY2(engine().m_appliedTransport == static_cast<int>(Transport::Paused) &&
                 !engine().m_cutFadeActive,
             "pause did not settle before the resume regression");
    QVERIFY2(engine().m_player.position() != 0, "resume regression needs a nonzero cursor");

    const auto resumeCursorPosition = engine().m_player.position();
    engine().play();
    auto resumeSettleFrames = uint32_t{0};
    auto advancedDuringSettle = false;
    while (engine().m_appliedTransport != static_cast<int>(Transport::Playing) &&
           resumeSettleFrames < uint32_t(engine().sampleRate())) {
        renderParked(engine(), 1);
        ++resumeSettleFrames;
        advancedDuringSettle |= engine().m_player.position() != resumeCursorPosition;
    }
    QVERIFY2(engine().m_appliedTransport == static_cast<int>(Transport::Playing),
             "resume was not applied for the resume regression");
    QVERIFY2(!advancedDuringSettle, "resume advanced the player during the zero-gain settle");
    QVERIFY2(engine().m_cutFadeGain >= 0.999f, "resume entered Playing below unity cut-fade gain");
    QVERIFY2(engine().m_player.position() == resumeCursorPosition,
             "resume consumed timeline audio before full output gain");
    renderParked(engine(), 1);
    QVERIFY2(engine().m_player.position() > resumeCursorPosition,
             "timeline did not advance after the resumed start");
}

// Rapid retarget: play requested while a pause cut is still fading down.
// The pending cut retargets onto already-applied Playing and must complete
// through the normal return ramp — no state may wait for an
// applied-transport change that already matches the target.
void TransportTest::pendingCutRetargetsOntoPlaying()
{
    if (!engageSuppressorWithNoteSong(engine()))
        return;
    engine().pause();
    renderParked(engine(), 1);
    QVERIFY2(engine().m_cutFadeActive && !engine().m_cutFadeRising,
             "pause cut did not start in its fade-down for the retarget check");

    engine().play();
    auto retargetFrames = uint32_t{0};
    while (engine().m_cutFadeActive && retargetFrames < uint32_t(engine().sampleRate())) {
        renderParked(engine(), 1);
        ++retargetFrames;
    }
    QVERIFY2(!engine().m_cutFadeActive, "retargeted cut never completed");
    QVERIFY2(engine().m_appliedTransport == static_cast<int>(Transport::Playing),
             "retargeted cut lost the playing state");
    QVERIFY2(engine().m_cutFadeGain >= 0.999f, "retargeted cut ended below unity output gain");
}

// A cold song replacement is another playback boundary. Starting a silent
// song must not reveal delayed samples from the outgoing song.
void TransportTest::coldReplacementLeaksNoPriorSongAudio()
{
    QVERIFY2(parkSuppressed(engine()), "could not park the device for deterministic checks");
    auto noteTimeline = loadedSong(buildNoteSong(), "note song built wrong");
    QVERIFY2(noteTimeline, "note song built wrong");
    engine().loadSong(noteTimeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine().play();
    if (!renderUntilApplied(engine(), static_cast<int>(Transport::Playing))) {
        QTest::qFail("play was not applied before the cold replacement", __FILE__, __LINE__);
        return;
    }
    // Prime the suppressor's delay line with outgoing-song audio.
    renderParked(engine(), uint32_t(0.5 * engine().sampleRate()));

    auto silentTimeline = loadedSong(buildSilentSong(), "silent song built wrong");
    QVERIFY2(silentTimeline, "silent song built wrong");
    engine().loadSong(silentTimeline, borrowVoicegroupLease(&m_bank->vg), SongSettings{});
    engine().play();
    const auto silentStart = renderParked(engine(), engine().m_cutFadeSettleSamples +
                                                        2 * engine().m_outputGainRampSamples +
                                                        2 * ResonanceSuppressor::kN);
    QVERIFY2(peak(silentStart) <= 1.0e-7f,
             "new playback leaked delayed suppressor audio from the prior song");
    engine().unloadSong();
}

} // namespace checks
