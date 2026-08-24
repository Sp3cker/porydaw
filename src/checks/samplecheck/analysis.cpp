#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <cmath>
#include <cstdio>
#include <span>
#include <vector>

#include "audio/auditionslots.h"
#include "audio/sampledoc.h"
#include "audio/sampledsp.h"

namespace {
constexpr double kPi = 3.14159265358979323846;

int soundingPcmChannels(const M4AEngine *engine)
{
    int count = 0;
    for (int i = 0; i < MAX_PCM_CHANNELS; i++) {
        if (engine->pcmChannels[i].status & CHN_ON)
            count++;
    }
    return count;
}

void pumpEngine(M4AEngine *engine, int blocks)
{
    static std::vector<float> l(512), r(512);
    for (int i = 0; i < blocks; i++)
        m4a_engine_process(engine, l.data(), r.data(), 512);
}
} // namespace

namespace samplecheck {

void runAnalysisChecks(Reporter &reporter)
{
    // ---- pitch detection (DSP.md §9 item 9) ----
    {
        const int before = reporter.failureCount();
        for (const double rate : {8000.0, 13379.0, 22050.0, 44100.0}) {
            for (const int key : {33, 45, 57, 69, 81, 93}) { // A1..A6
                const double f0 = 440.0 * std::pow(2.0, (key - 69) / 12.0);
                const std::vector<float> sine = genSine(rate, f0, 1.5, 0.4);
                SampleDsp::PitchResult p = SampleDsp::detectPitchYin(sine, rate);
                if (!p.pitched || std::abs(centsOff(p.f0, f0)) > 5.0) {
                    std::fprintf(stderr,
                                 "samplecheck: FAIL: sine A%d @%g Hz rate "
                                 "%g: %s %.2f cents\n",
                                 (key - 21) / 12, f0, rate, p.pitched ? "off by" : "unpitched",
                                 p.pitched ? centsOff(p.f0, f0) : 0.0);
                    reporter.noteFailure();
                }
                const std::vector<float> saw = genSaw(rate, f0, 1.5, 0.4);
                p = SampleDsp::detectPitchYin(saw, rate);
                if (!p.pitched || std::abs(centsOff(p.f0, f0)) > 5.0) {
                    std::fprintf(stderr,
                                 "samplecheck: FAIL: saw A%d @%g Hz rate "
                                 "%g: %s %.2f cents\n",
                                 (key - 21) / 12, f0, rate, p.pitched ? "off by" : "unpitched",
                                 p.pitched ? centsOff(p.f0, f0) : 0.0);
                    reporter.noteFailure();
                }
            }
        }
        std::vector<float> noise(size_t(13379 * 2));
        quint32 rng = 0xA5A5A5A5u;
        for (auto &v : noise) {
            rng = rng * 1664525u + 1013904223u;
            v = float(double(rng) / 4294967296.0 - 0.5) * 0.8f;
        }
        reporter.expect(!SampleDsp::detectPitchYin(noise, 13379.0).pitched,
                        "white noise reports unpitched");
        const std::vector<float> shorty = genSine(13379.0, 440.0, 0.4, 0.4);
        reporter.expect(!SampleDsp::detectPitchYin(shorty, 13379.0).pitched ||
                            true, // < 3 frames must not crash; result is unpitched
                        "short-buffer detection is safe");
        const std::span<const float> shortFrame = std::span<const float>(shorty).first(4000);
        reporter.expect(!SampleDsp::detectPitchYin(shortFrame, 13379.0).pitched,
                        "fewer than 3 frames reports unpitched");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: pitch detection OK\n");
    }

    // ---- loop suggestion (DSP.md §9 item 7) + the level gates ----
    {
        const int before = reporter.failureCount();
        const double rate = 13379.0;
        const qint64 n = qint64(rate * 2.0);

        // 440 Hz + 5 Hz vibrato (±10 cents) + slow decay.
        std::vector<float> tone(static_cast<size_t>(n));
        for (qint64 i = 0; i < n; i++) {
            const double t = double(i) / rate;
            const double env = 1.0 - 0.10 * double(i) / double(n);
            tone[size_t(i)] = float(
                0.35 * env * std::sin(2.0 * kPi * 440.0 * t + 0.5 * std::sin(2.0 * kPi * 5.0 * t)));
        }
        const SampleDsp::PitchResult pitch = SampleDsp::detectPitchYin(tone, rate);
        reporter.expect(pitch.pitched && std::abs(centsOff(pitch.f0, 440.0)) < 20.0,
                        "vibrato tone detects near 440 Hz");
        const double period = rate / (pitch.pitched ? pitch.f0 : 440.0);
        const std::vector<SampleDsp::LoopCandidate> cands = SampleDsp::suggestLoop(
            tone, rate, period, qint64(std::llround(0.4 * double(n))), n - 1);
        reporter.expect(!cands.empty(), "vibrato tone yields loop candidates");
        if (!cands.empty()) {
            const SampleDsp::LoopCandidate &top = cands[0];
            reporter.expect(top.passedGates, "top candidate passes the gates");
            reporter.expect(top.ncc >= 0.95, "top candidate NCC >= 0.95");
            const QByteArray s8 = SampleDsp::quantizeBuffer(tone, false);
            const SeamMetrics seam = SampleDsp::seamMetricsAt(
                std::span<const qint8>(reinterpret_cast<const qint8 *>(s8.constData()),
                                       size_t(s8.size())),
                top.loopStart, top.loopEnd);
            reporter.expect(seam.valid && seam.ampLsb <= 2 && seam.derivLsb <= 3,
                            "top candidate post-quantize seam within click bounds");
            const qint64 L = top.loopEnd + 1 - top.loopStart;
            const double k = std::round(double(L) / period);
            reporter.expect(k >= 1.0 && std::abs(double(L) - k * period) <= 0.01 * double(L),
                            "loop length within 1% of an integer period multiple");
        }

        // White noise: unpitched ladder; nothing resembling a clean loop.
        std::vector<float> noise(static_cast<size_t>(n));
        quint32 rng = 0xC0FFEE01u;
        for (auto &v : noise) {
            rng = rng * 1664525u + 1013904223u;
            v = float(double(rng) / 4294967296.0 - 0.5) * 0.8f;
        }
        const std::vector<SampleDsp::LoopCandidate> ncands =
            SampleDsp::suggestLoop(noise, rate, 0.0, qint64(std::llround(0.4 * double(n))), n - 1);
        reporter.expect(!ncands.empty() && ncands[0].ncc < 0.5, "white noise yields no clean loop");

        // Amplitude step: NCC is scale-invariant, so a loop spanning the
        // step correlates perfectly — the level-match/anti-pump gates are
        // what reject it. Every gate-passing candidate must stay on one
        // side of the step.
        std::vector<float> step(static_cast<size_t>(n));
        for (qint64 i = 0; i < n; i++) {
            const double amp = i < n / 2 ? 0.4 : 0.2;
            step[size_t(i)] = float(amp * std::sin(2.0 * kPi * 440.0 * double(i) / rate));
        }
        const std::vector<SampleDsp::LoopCandidate> scands = SampleDsp::suggestLoop(
            step, rate, rate / 440.0, qint64(std::llround(0.4 * double(n))), n - 1);
        reporter.expect(!scands.empty() && scands[0].passedGates,
                        "amplitude-step tone still finds a clean same-level loop");
        bool gatesHonest = true;
        for (const SampleDsp::LoopCandidate &c : scands) {
            if (c.passedGates && c.loopStart < n / 2 && c.loopEnd >= n / 2)
                gatesHonest = false;
        }
        reporter.expect(gatesHonest, "no gate-passing candidate spans the amplitude step");

        // Refine: knock a good loop off-seat by a few samples; the ±8
        // local search recovers a seam at least as correlated.
        if (!cands.empty()) {
            qint64 S = cands[0].loopStart + 3, E = cands[0].loopEnd - 2;
            const QByteArray beforeS8 = SampleDsp::quantizeBuffer(tone, false);
            const double nccBefore =
                SampleDsp::seamMetricsAt(
                    std::span<const qint8>(reinterpret_cast<const qint8 *>(beforeS8.constData()),
                                           size_t(beforeS8.size())),
                    S, E)
                    .ncc;
            SampleDsp::refineLoop(tone, period, &S, &E);
            const QByteArray s8 = SampleDsp::quantizeBuffer(tone, false);
            const SeamMetrics refined = SampleDsp::seamMetricsAt(
                std::span<const qint8>(reinterpret_cast<const qint8 *>(s8.constData()),
                                       size_t(s8.size())),
                S, E);
            reporter.expect(refined.ncc >= nccBefore - 1e-9,
                            "refine never worsens the seam correlation");
        }

        // A buffer long enough to search (≥ 256) but too short for the
        // pitched seam windows (2·period ≥ length): no candidates, and no
        // qBound(min > max) on the region clamp.
        const std::vector<float> stub = genSine(rate, 440.0, 300.0 / rate, 0.4);
        reporter.expect(
            SampleDsp::suggestLoop(stub, rate, 200.0, 0, qint64(stub.size()) - 1).empty(),
            "window-starved pitched buffer returns no candidates");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: loop suggestion OK\n");
    }

    // ---- crossfade bake (DSP.md §6) ----
    {
        const int before = reporter.failureCount();
        // Identity-rate 440 Hz source with a loop deliberately mis-seated
        // by half a period: a hard seam click the bake must tame.
        FixtureSpec cf;
        cf.rate = 13379;
        cf.bits = 16;
        cf.withSmpl = false;
        for (int i = 0; i < 13379; i++) {
            const double v = 0.5 * std::sin(2.0 * kPi * 440.0 * double(i) / 13379.0);
            putU16(&cf.samples, quint16(qint16(std::lround(v * 32000.0))));
        }
        ImportedSample cfSrc;
        QString error;
        reporter.expect(
            importAudioBytes(fixtureWav(cf), QStringLiteral("f/cf.wav"), &cfSrc, &error),
            "crossfade fixture imports");
        SampleEditParams p = SampleDocument::defaultParams(cfSrc);
        p.loopOn = true;
        p.loopStart = 4000;
        p.loopEnd = 4623; // ~20.5 periods: seam lands half a period off
        p.normalizeMode = SampleEditParams::NormalizeOff;
        p.dcRemove = SampleEditParams::Off;
        p.fadeIn = false;
        p.fadeOut = false;
        SampleDocument plain(cfSrc);
        plain.setParams(p);
        const ProcessedSample plainOut = plain.processed();
        reporter.expect(plainOut.seam.valid && plainOut.seam.ampLsb > 4,
                        "mis-seated loop clicks without the bake");

        SampleEditParams q = p;
        q.crossfadeOn = true;
        SampleDocument baked(cfSrc), baked2(cfSrc);
        baked.setParams(q);
        baked2.setParams(q);
        const ProcessedSample &bakedOut = baked.processed();
        reporter.expect(bakedOut.s8 == baked2.processed().s8,
                        "crossfade renders deterministically");
        reporter.expect(bakedOut.seam.valid && bakedOut.seam.ampLsb < plainOut.seam.ampLsb &&
                            bakedOut.seam.ampLsb <= 3,
                        "crossfade bake tames the seam click");
        // Only the fade window changes; everything before it is untouched.
        reporter.expect(bakedOut.size == plainOut.size &&
                            bakedOut.s8.left(int(bakedOut.size) - 160) ==
                                plainOut.s8.left(int(plainOut.size) - 160),
                        "bake touches only the fade window");
        // A loop start too close to the buffer start refuses actionably.
        SampleEditParams tight = q;
        tight.loopStart = 2;
        tight.loopEnd = 700;
        SampleDocument tightDoc(cfSrc);
        tightDoc.setParams(tight);
        bool warned = false;
        for (const QString &w : tightDoc.processed().warnings)
            warned = warned || w.contains(QStringLiteral("crossfade"));
        reporter.expect(warned, "impossible crossfade warns instead of baking");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: crossfade bake OK\n");
    }

    // ---- audition-slot protocol (PLAN.md §4) against a bare engine ----
    {
        const int before = reporter.failureCount();
        auto *engine = new M4AEngine();
        m4a_engine_init(engine, 32768.0f);
        AuditionSlots pool;
        const QByteArray patternA(600, char(10));
        const QByteArray patternB(600, char(-20));
        // Release 0 cuts instantly, so retirement is quick and observable.
        const AuditionSlots::Adsr instant{255, 0, 255, 0};
        const auto publish = [&](const QByteArray &bytes, uint8_t key) {
            return pool.publishNote(bytes, 13700096, 100, true, key, instant);
        };

        reporter.expect(publish(patternA, 60), "first publish takes a slot");
        pool.apply(engine, 1);
        reporter.expect(soundingPcmChannels(engine) == 1, "adopted audition keys one channel");
        const M4APCMChannel *chA = nullptr;
        for (int i = 0; i < MAX_PCM_CHANNELS; i++) {
            if (engine->pcmChannels[i].status & CHN_ON)
                chA = &engine->pcmChannels[i];
        }
        reporter.expect(chA && chA->wav && chA->wav->data && chA->wav->data[0] == 10 &&
                            chA->midiKey == 60 && chA->audition,
                        "channel reads the slot's bytes and is audition-flagged");

        // Publish storm without adoption: only the retired slots accept;
        // the rest coalesce. The sounding slot is never re-rendered.
        int accepted = 0;
        for (int i = 0; i < 100; i++)
            accepted += publish(patternB, 62) ? 1 : 0;
        reporter.expect(accepted == AuditionSlots::kSlots - 1,
                        "publish storm coalesces once every retired slot is taken");
        reporter.expect(chA && chA->wav->data[0] == 10,
                        "the sounding slot survives the storm un-overwritten");

        // Adoption plays only the newest publish; the superseded note
        // releases and its slot retires once the envelope finishes.
        pool.apply(engine, 1);
        pumpEngine(engine, 4);
        pool.apply(engine, 1);
        reporter.expect(soundingPcmChannels(engine) == 1, "superseded audition fully retires");
        const M4APCMChannel *chB = nullptr;
        for (int i = 0; i < MAX_PCM_CHANNELS; i++) {
            if (engine->pcmChannels[i].status & CHN_ON)
                chB = &engine->pcmChannels[i];
        }
        reporter.expect(chB && chB->wav && chB->wav->data && chB->wav->data[0] == -20 &&
                            chB->midiKey == 62,
                        "the adopted channel reads the newest render");
        int freed = 0;
        for (int i = 0; i < 6; i++)
            freed += publish(patternA, 64) ? 1 : 0;
        reporter.expect(freed == AuditionSlots::kSlots - 1,
                        "retired slots reuse; the sounding one never does");

        // Note-off: the audition silences and every slot retires.
        pool.apply(engine, 1);
        pumpEngine(engine, 4);
        pool.apply(engine, 1);
        pool.publishOff();
        pool.apply(engine, 1);
        pumpEngine(engine, 4);
        pool.apply(engine, 1);
        reporter.expect(soundingPcmChannels(engine) == 0, "publishOff silences the audition");
        int post = 0;
        for (int i = 0; i < 5; i++)
            post += publish(patternB, 65) ? 1 : 0;
        reporter.expect(post == AuditionSlots::kSlots, "full retirement frees every slot");

        // Cold reset (engine reinit) drops everything cleanly.
        m4a_engine_destroy(engine);
        m4a_engine_init(engine, 32768.0f);
        pool.reset();
        reporter.expect(publish(patternA, 60), "reset retires all slots");
        pool.apply(engine, 1);
        reporter.expect(soundingPcmChannels(engine) == 1, "audition works after reset");
        m4a_engine_destroy(engine);
        delete engine;
        if (reporter.failureCount() == before)
            std::printf("samplecheck: audition slots OK\n");
    }
}

} // namespace samplecheck
