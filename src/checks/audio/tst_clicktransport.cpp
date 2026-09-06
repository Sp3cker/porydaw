#include "checks/audio/tst_clicktransport.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include <algorithm>
#include <array>
#include <memory>
#include <span>

#include "checks/support/audioengineaccess.h"
#include "project/voicegroupsource.h"

namespace checks {
namespace {

constexpr uint32_t kRenderChunk = 512; // per-call process granularity (legacy rig; < m_bufCapacity)
constexpr uint64_t kRenderChunk64 = kRenderChunk;

enum HardCutScenario { PauseCut = 0, StopCut, PlayOverAuditionCut };

QString evidenceText(const SteadySilence &steady)
{
    QString text;
    for (std::size_t i = 0; i < steady.evidence.size(); ++i) {
        const std::size_t interval = i == 0 ? 0 : steady.evidence[i] - steady.evidence[i - 1];
        text += QStringLiteral(" %1(+%2)").arg(steady.evidence[i]).arg(interval);
    }
    return text;
}

} // namespace

void ClickTest::initTestCase()
{
    // Required deterministic null backend: click asserts sample-exact steps,
    // so a missing or wrong device must FAIL, never SKIP. The suite parks the
    // device right after init and renders synchronously — no physical audio
    // anywhere, no callback thread, no wall-clock polling.
    m_priorBackendEnv = qEnvironmentVariable("PORYDAW_AUDIO_BACKEND");
    qputenv("PORYDAW_AUDIO_BACKEND", "null");
}

void ClickTest::cleanupTestCase()
{
    if (m_priorBackendEnv.isEmpty())
        qunsetenv("PORYDAW_AUDIO_BACKEND");
    else
        qputenv("PORYDAW_AUDIO_BACKEND", m_priorBackendEnv.toUtf8().constData());
}

bool ClickTest::startRig(Rig &rig)
{
    if (!rig.engine.init(&rig.error)) {
        QTest::qFail(
            qUtf8Printable(QStringLiteral("forced null audio init failed: %1").arg(rig.error)),
            __FILE__, __LINE__);
        return false;
    }
    // Park the real device and drive AudioEngine synchronously so every
    // transport decision is observed at an exact sample index (same two-step
    // seam as the transport suite's suppressor checks).
    if (!AudioEngineTestAccess::parkDevice(rig.engine)) {
        QTest::qFail("could not stop the audio device for deterministic rendering", __FILE__,
                     __LINE__);
        return false;
    }
    return loadSustainSong(rig);
}

bool ClickTest::loadSustainSong(Rig &rig)
{
    const SmfFile smf = buildSustainSong();
    rig.timeline = MidiTimeline::build(smf, rig.engine.sampleRate());
    if (!rig.timeline) {
        QTest::qFail("synthesized song failed to build", __FILE__, __LINE__);
        return false;
    }
    rig.engine.loadSong(rig.timeline, borrowVoicegroupLease(&rig.voicegroup.vg), SongSettings{});
    rig.engine.setLoopEnabled(false);
    return true;
}

void ClickTest::render(AudioEngine &engine, uint64_t frames, Capture &capture)
{
    std::array<float, 2 * kRenderChunk> interleaved;
    while (frames > 0) {
        const auto chunk = uint32_t(std::min<uint64_t>(frames, kRenderChunk64));
        AudioEngineTestAccess::renderParked(
            engine, std::span<float>(interleaved.data(), std::size_t(chunk) * 2));
        const std::size_t start = capture.frames();
        capture.left.resize(start + chunk);
        capture.right.resize(start + chunk);
        for (std::size_t i = 0; i < chunk; ++i) {
            capture.left[start + i] = interleaved[2 * i];
            capture.right[start + i] = interleaved[2 * i + 1];
        }
        frames -= chunk;
    }
}

bool ClickTest::spinUntilApplied(AudioEngine &engine, Transport target, Capture &capture,
                                 std::size_t *onset)
{
    const auto bound = uint64_t(engine.sampleRate());
    for (uint64_t i = 0; i < bound; ++i) {
        if (engine.m_appliedTransport == static_cast<int>(target)) {
            if (onset)
                *onset = capture.frames();
            return true;
        }
        render(engine, 1, capture);
    }
    if (onset)
        *onset = capture.frames();
    return engine.m_appliedTransport == static_cast<int>(target);
}

bool ClickTest::sounding(const AudioEngine &engine, uint8_t midiKey) const
{
    for (int i = 0; i < TOTAL_PCM_CHANNELS; i++) {
        const M4APCMChannel &ch = engine.m_engine->pcmChannels[i];
        if ((ch.status & CHN_ON) && ch.midiKey == midiKey)
            return true;
    }
    return false;
}

bool ClickTest::sustaining(const AudioEngine &engine, uint8_t midiKey) const
{
    for (int i = 0; i < TOTAL_PCM_CHANNELS; i++) {
        const M4APCMChannel &ch = engine.m_engine->pcmChannels[i];
        if ((ch.status & CHN_ON) && !(ch.status & CHN_STOP) && ch.midiKey == midiKey)
            return true;
    }
    return false;
}

void ClickTest::verifyTransition(const char *what, const Capture &capture, std::size_t at,
                                 TransitionExpectation expectation) const
{
    const TransitionProbe probe = measureTransition(capture.left, capture.right, at);
    QVERIFY2(probe.amp >= kMeasurableSignalFloor,
             qUtf8Printable(QStringLiteral("%1: sustain amplitude %2 too low to measure")
                                .arg(QLatin1String(what))
                                .arg(probe.amp, 0, 'f', 4)));

    const bool clickDetected = probe.step > probe.allowed;
    if (expectation == TransitionExpectation::DetectableClick) {
        QVERIFY2(
            clickDetected,
            qUtf8Printable(QStringLiteral("%1 hard-cut control produced no detectable click "
                                          "(step %2, sustain %3, natural step %4, threshold %5)")
                               .arg(QLatin1String(what))
                               .arg(probe.step, 0, 'f', 4)
                               .arg(probe.amp, 0, 'f', 4)
                               .arg(probe.naturalStep, 0, 'f', 5)
                               .arg(probe.allowed, 0, 'f', 6)));
        return;
    }
    QVERIFY2(!clickDetected,
             qUtf8Printable(QStringLiteral("%1: output stepped %2 in one sample at the transition "
                                           "(sustain %3, natural step %4, allowed %5)")
                                .arg(QLatin1String(what))
                                .arg(probe.step, 0, 'f', 4)
                                .arg(probe.amp, 0, 'f', 4)
                                .arg(probe.naturalStep, 0, 'f', 5)
                                .arg(probe.allowed, 0, 'f', 6)));
}

void ClickTest::pauseFadesSilently_data()
{
    QTest::addColumn<bool>("squareVoice");
    QTest::newRow("dc-pause") << false;
    QTest::newRow("square-pause") << true;
}

void ClickTest::pauseFadesSilently()
{
    QFETCH(bool, squareVoice);
    const char *what = squareVoice ? "square pause" : "DC pause";
    Rig rig(squareVoice);
    if (!startRig(rig))
        return;

    Capture capture;
    const auto rate = uint64_t(rig.engine.sampleRate());
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    const uint32_t settle = rig.engine.m_cutFadeSettleSamples;

    rig.engine.play();
    render(rig.engine, rate, capture); // 1 s of loud sustain
    const std::size_t at = capture.frames();
    rig.engine.pause();
    const std::size_t steadyStart = at + 3 * std::size_t(ramp) + std::size_t(settle);
    const std::size_t steadySamples = 3 * std::size_t(rate);
    render(rig.engine, uint64_t(steadyStart - at) + steadySamples, capture);

    verifyTransition(what, capture, at, TransitionExpectation::Smooth);

    // Pause must fall silent: after the cut (well inside the tail window)
    // nothing but silence remains (audible-silence contract: < 0.01).
    const double tail =
        std::max(maxAbsIn(capture.left, at + 2 * std::size_t(ramp), capture.left.size()),
                 maxAbsIn(capture.right, at + 2 * std::size_t(ramp), capture.right.size()));
    QVERIFY2(tail <= 0.01,
             qUtf8Printable(QStringLiteral("%1: pause did not fall silent (tail level %2)")
                                .arg(QLatin1String(what))
                                .arg(tail, 0, 'f', 4)));

    // Settled Paused tail is digitally silent: <= 1 LSB of amplitude and step.
    const std::size_t steadyEnd = std::min(steadyStart + steadySamples, capture.left.size());
    const SteadySilence steady =
        scanSteadySilence(capture.left, capture.right, steadyStart, steadyEnd);
    QVERIFY2(steady.maxAbs <= kOutputLsb && steady.maxStep <= kOutputLsb,
             qUtf8Printable(QStringLiteral("%1: steady Paused tail was not silent (max abs %2 at "
                                           "sample %3, max step %4 at sample %5; evidence:%6)")
                                .arg(QLatin1String(what))
                                .arg(steady.maxAbs)
                                .arg(steady.absAt)
                                .arg(steady.maxStep)
                                .arg(steady.stepAt)
                                .arg(evidenceText(steady))));
}

void ClickTest::stopFadesSilently()
{
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    rig.engine.play();
    render(rig.engine, uint64_t(rig.engine.sampleRate()), capture); // 1 s of loud sustain
    const std::size_t at = capture.frames();
    rig.engine.stop();
    render(rig.engine, 3 * std::size_t(ramp) + 2048, capture);

    verifyTransition("DC stop", capture, at, TransitionExpectation::Smooth);

    // Stop must fall silent like pause (the Stopped cut also resets the
    // player and the suppressor state).
    const double tail =
        std::max(maxAbsIn(capture.left, at + 2 * std::size_t(ramp), capture.left.size()),
                 maxAbsIn(capture.right, at + 2 * std::size_t(ramp), capture.right.size()));
    QVERIFY2(
        tail <= 0.01,
        qUtf8Printable(
            QStringLiteral("DC stop did not fall silent (tail level %1)").arg(tail, 0, 'f', 4)));
}

void ClickTest::playOverAuditionFadesSilently()
{
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    // A live audition rings from outside the timeline (piano-key click note
    // preview). The transport cut uses the public all-sound-off API for the
    // complete engine, so the sequenced note starts only after zero.
    rig.engine.previewNote(0, 62, 100);
    render(rig.engine, uint64_t(0.5 * rig.engine.sampleRate()), capture);
    QVERIFY2(sounding(rig.engine, 62), "the audition must ring before playback starts");
    const std::size_t at = capture.frames();
    rig.engine.play();
    render(rig.engine, 3 * std::size_t(ramp) + 4096, capture);

    verifyTransition("DC play-over-audition", capture, at, TransitionExpectation::Smooth);
    // The ringing audition must be cut (not left sounding under playback).
    QVERIFY2(!sounding(rig.engine, 62), "play did not halt the ringing audition");
}

void ClickTest::songStartReachesFullGain()
{
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    std::size_t onset = 0;
    rig.engine.play();
    // The deferred Playing start parks the transport through the settle hold:
    // the player neither advances nor renders while the gain is zero, and the
    // hold-end completion flips to Playing at unity output gain.
    QVERIFY2(spinUntilApplied(rig.engine, Transport::Playing, capture, &onset),
             "Playing was not applied within one second");
    QVERIFY2(rig.engine.m_cutFadeGain >= 0.999f, "song start applied below full output gain");
    QCOMPARE(rig.engine.m_player.position(), uint64_t(0));

    render(rig.engine, std::size_t(rig.engine.m_cutFadeSettleSamples) + 2 * kRenderChunk64,
           capture);
    const double level = std::max(maxAbsIn(capture.left, onset, capture.left.size()),
                                  maxAbsIn(capture.right, onset, capture.right.size()));
    QVERIFY2(level >= kMeasurableSignalFloor,
             qUtf8Printable(QStringLiteral("Playing transition cut the first sequenced note "
                                           "(level %1)")
                                .arg(level, 0, 'f', 4)));
    QVERIFY2(sustaining(rig.engine, 60), "first sequenced note did not sustain after Playing");
    QCOMPARE(rig.engine.m_appliedTransport, static_cast<int>(Transport::Playing));
    QVERIFY2(!rig.engine.m_cutFadeActive && rig.engine.m_cutFadeGain >= 0.99f,
             "Playing transition left stale transport/fade state");
}

void ClickTest::rapidRetargetKeepsNewestTransport()
{
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    const uint32_t settle = rig.engine.m_cutFadeSettleSamples;
    rig.engine.play();
    render(rig.engine, ramp / 2, capture); // interrupt the cut mid-fall
    rig.engine.pause();
    rig.engine.play();
    QVERIFY2(rig.engine.m_cutFadeActive, "rapid retarget did not keep a cut in flight");
    QCOMPARE(rig.engine.m_cutFadeTargetTransport, static_cast<int>(Transport::Playing));

    render(rig.engine, 3 * std::size_t(ramp) + std::size_t(settle) + 2 * kRenderChunk64, capture);
    QCOMPARE(rig.engine.m_appliedTransport, static_cast<int>(Transport::Playing));
    QVERIFY2(!rig.engine.m_cutFadeActive && rig.engine.m_cutFadeGain >= 0.99f,
             "rapid retarget left stale transport/fade state");
    QVERIFY2(sustaining(rig.engine, 60), "rapid retarget lost the sequenced note");
}

void ClickTest::timedPreviewCutDefersCommands()
{
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    // One active preview and one queued preview share the song note's
    // track/key. Neither may leave a timed note-off behind the Playing cut.
    rig.engine.previewNoteTimed(0, 60, 100, 4 * kRenderChunk);
    render(rig.engine, kRenderChunk64, capture);
    rig.engine.previewNoteTimed(0, 60, 100, 2 * kRenderChunk + 1);
    rig.engine.play();
    render(rig.engine, kRenderChunk64, capture); // the cut drains active + queued
    QCOMPARE(rig.engine.m_timedActiveCount, 0);
    QCOMPARE(rig.engine.m_timedRead.load(), rig.engine.m_timedWrite.load());

    // A command published while the deferred cut is in flight remains
    // deterministic: it waits for the cut to complete, then starts normally.
    rig.engine.previewNoteTimed(0, 61, 100, 8 * kRenderChunk);
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    const uint32_t settle = rig.engine.m_cutFadeSettleSamples;
    render(rig.engine, 3 * std::size_t(ramp) + std::size_t(settle) + 2 * kRenderChunk64, capture);
    QVERIFY2(sustaining(rig.engine, 60), "timed preview note-off stopped the Playing song note");
    QVERIFY2(sustaining(rig.engine, 61), "later timed preview was not deferred cleanly");
}

void ClickTest::reloadAfterInterruptedFadeStartsLoud()
{
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    rig.engine.play();
    render(rig.engine, uint64_t(rig.engine.sampleRate()), capture); // 1 s of loud sustain
    rig.engine.pause();
    render(rig.engine, ramp / 2, capture); // interrupt the fade at a partial gain

    rig.engine.unloadSong();
    QVERIFY2(!rig.engine.m_cutFadeActive, "unload must clear an interrupted fade");
    QCOMPARE(rig.engine.m_cutFadeGain, 1.0f);
    rig.engine.loadSong(rig.timeline, borrowVoicegroupLease(&rig.voicegroup.vg), SongSettings{});
    rig.engine.setLoopEnabled(false);

    std::size_t onset = 0;
    rig.engine.play();
    QVERIFY2(spinUntilApplied(rig.engine, Transport::Playing, capture, &onset),
             "Playing was not applied within one second after reload");
    QVERIFY2(rig.engine.m_cutFadeGain >= 0.9f, "load after interrupted fade reused stale cut gain");
    QCOMPARE(rig.engine.m_player.position(), uint64_t(0));

    render(rig.engine, std::size_t(rig.engine.m_cutFadeSettleSamples) + 2 * kRenderChunk64,
           capture);
    const double level = std::max(maxAbsIn(capture.left, onset, capture.left.size()),
                                  maxAbsIn(capture.right, onset, capture.right.size()));
    QVERIFY2(level >= kMeasurableSignalFloor,
             qUtf8Printable(QStringLiteral("loaded song started below the measurable floor (level "
                                           "%1)")
                                .arg(level, 0, 'f', 4)));
    QVERIFY2(sustaining(rig.engine, 60), "loaded song did not sustain after interrupted fade");
}

void ClickTest::hardCutControlsClick_data()
{
    QTest::addColumn<int>("scenario");
    QTest::newRow("hard-cut-pause-dc") << int(PauseCut);
    QTest::newRow("hard-cut-stop-dc") << int(StopCut);
    QTest::newRow("hard-cut-play-over-audition-dc") << int(PlayOverAuditionCut);
}

void ClickTest::hardCutControlsClick()
{
    QFETCH(int, scenario);
    Rig rig(false);
    if (!startRig(rig))
        return;

    Capture capture;
    const uint32_t ramp = rig.engine.m_outputGainRampSamples;
    if (scenario == PlayOverAuditionCut) {
        rig.engine.previewNote(0, 62, 100);
        render(rig.engine, uint64_t(0.5 * rig.engine.sampleRate()), capture);
    } else {
        rig.engine.play();
        render(rig.engine, uint64_t(rig.engine.sampleRate()), capture); // 1 s of loud sustain
    }
    const std::size_t at = capture.frames();

    // Calibrate the transition detector against the deliberately abrupt
    // pre-fade interface: both engines are cut at once at full gain, exactly
    // as every transport worked before the cut-fade existed. Each DC
    // transition must independently register a click.
    m4a_engine_all_sound_off(rig.engine.m_engine.get());
    m4a_engine_all_sound_off(rig.engine.m_previewEngine.get());

    const char *what = "hard-cut pause control";
    switch (scenario) {
    case PauseCut:
        rig.engine.pause();
        break;
    case StopCut:
        what = "hard-cut stop control";
        rig.engine.stop();
        break;
    case PlayOverAuditionCut:
        what = "hard-cut play-over-audition control";
        rig.engine.play();
        break;
    }
    render(rig.engine, 3 * std::size_t(ramp) + (scenario == PlayOverAuditionCut ? 4096u : 2048u),
           capture);
    verifyTransition(what, capture, at, TransitionExpectation::DetectableClick);
}

} // namespace checks

int runClickCheck(const QStringList &qtArguments)
{
    checks::ClickTest test;
    QStringList arguments{QStringLiteral("clickcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
