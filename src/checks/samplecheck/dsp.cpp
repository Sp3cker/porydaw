#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <span>
#include <utility>
#include <vector>

#include "audio/sampledoc.h"
#include "audio/sampledsp.h"
#include "audio/sampleimport.h"
#include "audio/samplewav.h"
#include "project/samplereg.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace {
constexpr double kPi = 3.14159265358979323846;
}

namespace samplecheck {

std::optional<DspFixture> runDspChecks(Reporter &reporter, const RegisteredSampleProject &project)
{
    const QString &root = project.root;
    // ---- resampler (DSP.md §9 items 1-4) ----
    {
        const int before = reporter.failureCount();
        const double srcRate = 44100.0, dstRate = 13379.0;
        const double r = dstRate / srcRate;

        // 1. Passband: 100 Hz–6.0 kHz within ±0.1 dB of unity.
        for (const double f : {100.0, 500.0, 1000.0, 2000.0, 4000.0, 5000.0, 5500.0, 6000.0}) {
            const std::vector<float> in = genSineFast(srcRate, f, 0.3, 0.5);
            const qint64 nOut = qint64(std::llround(double(in.size()) * r));
            const std::vector<float> out = SampleDsp::resampleSinc(in, r, nOut);
            const double amp = toneAmp(out, dstRate, f, size_t(nOut / 5), size_t(nOut * 4 / 5));
            const double db = 20.0 * std::log10(amp / 0.5);
            if (std::abs(db) > 0.1) {
                std::fprintf(stderr,
                             "samplecheck: FAIL: passband %.0f Hz off by "
                             "%.3f dB\n",
                             f, db);
                reporter.noteFailure();
            }
        }

        // 2. Alias rejection: above-Nyquist input ≤ −80 dB re input.
        for (const double f : {8000.0, 10000.0, 14000.0}) {
            const std::vector<float> in = genSine(srcRate, f, 0.3, 0.5);
            const qint64 nOut = qint64(std::llround(double(in.size()) * r));
            const std::vector<float> out = SampleDsp::resampleSinc(in, r, nOut);
            const double rms = rmsOf(out, size_t(nOut / 5), size_t(nOut * 4 / 5));
            const double inRms = 0.5 / std::sqrt(2.0);
            if (rms > inRms * 1e-4) {
                std::fprintf(stderr, "samplecheck: FAIL: alias %.0f Hz leaks %.1f dB\n", f,
                             20.0 * std::log10(rms / inRms));
                reporter.noteFailure();
            }
        }

        // 3a. DC: constant in → same constant (±1e-4) away from the edges.
        {
            std::vector<float> in(size_t(srcRate * 0.2), 0.25f);
            const qint64 nOut = qint64(std::llround(double(in.size()) * r));
            const std::vector<float> out = SampleDsp::resampleSinc(in, r, nOut);
            bool flat = true;
            for (qint64 i = 100; i < nOut - 100; i++)
                flat = flat && std::abs(double(out[size_t(i)]) - 0.25) <= 1e-4;
            reporter.expect(flat, "constant input passes at unity DC gain");
        }

        // 3b. Impulse response symmetric (linear phase) at ratio 1/2.
        {
            std::vector<float> in(4000, 0.0f);
            in[2000] = 1.0f;
            const std::vector<float> out = SampleDsp::resampleSinc(in, 0.5, 2000);
            bool symmetric = true;
            for (int d = 1; d <= 500; d++)
                symmetric = symmetric && std::abs(double(out[size_t(1000 + d)]) -
                                                  double(out[size_t(1000 - d)])) <= 2e-6;
            reporter.expect(symmetric && out[1000] > 0.1,
                            "impulse response is symmetric about the center");
        }

        // 3c. 1 kHz in → spectral peak at 1000 ± 0.5 Hz out.
        {
            const std::vector<float> in = genSine(srcRate, 1000.0, 1.2, 0.5);
            const qint64 nOut = qint64(std::llround(double(in.size()) * r));
            const std::vector<float> out = SampleDsp::resampleSinc(in, r, nOut);
            double bestF = 0.0, bestAmp = -1.0;
            for (double f = 998.0; f <= 1002.0; f += 0.05) {
                const double amp = toneAmp(out, dstRate, f, 0, size_t(nOut));
                if (amp > bestAmp) {
                    bestAmp = amp;
                    bestF = f;
                }
            }
            reporter.expect(std::abs(bestF - 1000.0) <= 0.5,
                            "1 kHz spectral peak lands within ±0.5 Hz");
        }

        // 4. Identity bypass: equal rates → bit-exact passthrough.
        {
            std::vector<float> in(size_t(5000));
            quint32 rng = 12345;
            for (auto &v : in) {
                rng = rng * 1664525u + 1013904223u;
                v = float(double(rng) / 4294967296.0 - 0.5);
            }
            const std::vector<float> out = SampleDsp::resampleSinc(in, 1.0, qint64(in.size()));
            reporter.expect(std::memcmp(in.data(), out.data(), in.size() * sizeof(float)) == 0,
                            "identity ratio is a bit-exact passthrough");
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: resampler OK\n");
    }

    // ---- quantizer (DSP.md §9 item 5, synthetic half) ----
    {
        const int before = reporter.failureCount();
        const struct {
            double in;
            int out;
        } vectors[] = {
            {1.0, 127},
            {-1.0, -128},
            {127.5 / 128.0, 127},
            {-127.5 / 128.0, -128},
            {127.0 / 128.0, 127},
            {-127.0 / 128.0, -127},
            {0.5, 64},
            {-0.5, -64},
            {1e-9, 0},
            {-1e-9, -1}, // floor, not truncate
            {0.0, 0},
        };
        bool vecOk = true;
        for (const auto &v : vectors)
            vecOk = vecOk && SampleDsp::quantizeToAgb8(v.in) == v.out;
        reporter.expect(vecOk, "quantizer matches clamp(floor(x*128), -128, 127)");

        bool u8Round = true;
        for (int v = 0; v < 256; v++)
            u8Round = u8Round && SampleDsp::quantizeToAgb8((v - 128) / 128.0) == v - 128;
        reporter.expect(u8Round, "u8 → float → s8 is the identity for all 256 values");

        std::vector<float> noise(size_t(2000));
        quint32 rng = 999;
        for (auto &v : noise) {
            rng = rng * 1664525u + 1013904223u;
            v = float(double(rng) / 4294967296.0 - 0.5);
        }
        reporter.expect(SampleDsp::quantizeBuffer(noise, true) ==
                            SampleDsp::quantizeBuffer(noise, true),
                        "dither uses a fixed seed — renders are deterministic");
        reporter.expect(SampleDsp::quantizeBuffer(noise, true) !=
                            SampleDsp::quantizeBuffer(noise, false),
                        "dither actually perturbs the output");

        // Zero-crossing snap: sign changes at 4 and 8.
        const float zx[] = {0.5f,  0.5f,  0.5f, 0.5f, -0.5f, -0.5f,
                            -0.5f, -0.5f, 0.5f, 0.5f, 0.5f,  0.5f};
        reporter.expect(SampleDsp::nearestZeroCrossing(std::span<const float>(zx), 5) == 4 &&
                            SampleDsp::nearestZeroCrossing(std::span<const float>(zx), 7) == 8 &&
                            SampleDsp::nearestZeroCrossing(std::span<const float>(zx), 0) == 4,
                        "nearest zero crossing snaps to the closest sign change");
        // Marker mapping: crop offset then ratio, rounded.
        reporter.expect(SampleDsp::mapMarker(2000, 500, 0.5) == 750 &&
                            SampleDsp::mapMarker(2001, 0, 13379.0 / 44100.0) == 607,
                        "marker mapping crops then scales");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: quantizer OK\n");
    }

    // ---- normalization (DSP.md §9 item 6, synthetic half) ----
    {
        const int before = reporter.failureCount();
        QString warning;

        // Looped tone with a comfortable crest: RMS lands on target.
        std::vector<float> tone = genSine(13379.0, 440.0, 0.5, 0.11);
        double gain = SampleDsp::normalizeGain(tone, true, 0, &warning);
        for (auto &v : tone)
            v = float(double(v) * gain);
        const double rms = rmsOf(tone, 0, tone.size());
        reporter.expect(std::abs(20.0 * std::log10(rms / SampleDsp::kTargetLoopRms)) < 0.1,
                        "looped normalize lands within 0.1 dB of the target RMS");
        reporter.expect(warning.isEmpty(), "clean tone normalizes without warnings");

        // High crest: the peak cap engages and is never exceeded.
        std::vector<float> crest = genSine(13379.0, 440.0, 0.5, 0.05);
        crest[100] = 0.9f;
        gain = SampleDsp::normalizeGain(crest, true, 0, &warning);
        double peak = 0.0;
        for (const auto &v : crest)
            peak = std::max(peak, std::abs(double(v) * gain));
        reporter.expect(peak <= SampleDsp::kPeakCeiling + 1e-9 &&
                            std::abs(peak - SampleDsp::kPeakCeiling) < 1e-6,
                        "peak cap engages on high-crest material");

        // One-shot: pure peak normalize.
        std::vector<float> hit = genSine(13379.0, 200.0, 0.1, 0.4);
        gain = SampleDsp::normalizeGain(hit, false, 0, &warning);
        peak = 0.0;
        for (const auto &v : hit)
            peak = std::max(peak, std::abs(double(v) * gain));
        reporter.expect(std::abs(peak - SampleDsp::kPeakCeiling) < 1e-6,
                        "one-shot normalizes to the peak ceiling");

        // Near-silent input refuses auto-normalize.
        std::vector<float> quiet(1000, 0.01f);
        gain = SampleDsp::normalizeGain(quiet, false, 0, &warning);
        reporter.expect(gain == 1.0 &&
                            warning == QStringLiteral("silent sample — auto-normalize skipped."),
                        "silent sample refuses auto-normalize");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: normalization OK\n");
    }

    // ---- the parity fixture: hi-res 16-bit source used from here on ----
    FixtureSpec hiSpec;
    hiSpec.bits = 16;
    hiSpec.rate = 44100;
    hiSpec.numLoops = 1;
    hiSpec.loopStart = 2000;
    hiSpec.loopEndIncl = 9999;
    for (int i = 0; i < 12000; i++) {
        const double v = 0.5 * std::sin(2.0 * kPi * 220.5 * i / 44100.0);
        putU16(&hiSpec.samples, quint16(qint16(std::lround(v * 32000.0))));
    }
    const QByteArray hiResWav = fixtureWav(hiSpec);
    ImportedSample hiRes;
    {
        QString error;
        if (!importAudioBytes(hiResWav, QStringLiteral("fix/hires_tone.wav"), &hiRes, &error)) {
            std::fprintf(stderr, "samplecheck: FAIL: hi-res fixture import: %s\n",
                         qUtf8Printable(error));
            return std::nullopt;
        }
    }

    // ---- pipeline determinism: two fresh documents → identical bytes ----
    {
        const int before = reporter.failureCount();
        // Fresh (non-prepared) sources default to the GBA mix rate; sources
        // at or below it keep their own. Prepared files are covered by the
        // byte-faithful dialog assertions.
        reporter.expect(SampleDocument::defaultParams(hiRes).targetRate == 13379.0,
                        "fresh hi-res source defaults to 13379 Hz");
        {
            ImportedSample low = hiRes;
            low.sampleRate = 8000.0;
            low.gbaReady = false;
            reporter.expect(SampleDocument::defaultParams(low).targetRate == 8000.0,
                            "sources below the GBA rate keep their own");
        }
        SampleEditParams p = SampleDocument::defaultParams(hiRes);
        p.cropStart = 100;
        p.cropEnd = 11500;
        p.targetRate = 13379.0;
        p.baseKey = 59;
        p.fineTuneCents = 10.0;
        p.ditherOn = true;
        SampleDocument docA(hiRes), docB(hiRes);
        docA.setParams(p);
        docB.setParams(p);
        const ProcessedSample &a = docA.processed();
        const ProcessedSample &b = docB.processed();
        reporter.expect(a.s8 == b.s8 && a.freq == b.freq && a.size == b.size &&
                            a.loopStart == b.loopStart && a.pitchFraction == b.pitchFraction,
                        "two renders of the same params are byte-identical");
        // A no-op params round trip re-renders identically too.
        SampleEditParams q = p;
        q.baseKey = 60;
        docA.setParams(q);
        docA.processed();
        docA.setParams(p);
        reporter.expect(docA.processed().s8 == b.s8, "param round-trip re-renders identically");

        // Seam metrics: a mid-buffer loop start forms the NCC window; a
        // loop starting at 0 has no pre-start context, so ncc is flagged
        // invalid (amp/slope stay valid) and readouts must not show 0%.
        SampleEditParams mid = SampleDocument::defaultParams(hiRes);
        SampleDocument docMid(hiRes);
        docMid.setParams(mid);
        reporter.expect(docMid.processed().seam.valid && docMid.processed().seam.nccValid,
                        "mid-buffer loop start gets a valid NCC");
        SampleEditParams zero = mid;
        zero.loopStart = 0;
        SampleDocument docZero(hiRes);
        docZero.setParams(zero);
        reporter.expect(docZero.processed().seam.valid && !docZero.processed().seam.nccValid,
                        "loop-from-0 seam flags NCC as unformable");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: pipeline determinism OK\n");
    }

    // ---- retune vectors (FORMATS.md §3, independently precomputed) ----
    {
        const int before = reporter.failureCount();
        FixtureSpec flat;
        flat.rate = 44100;
        flat.withSmpl = false;
        flat.samples = QByteArray(64, char(0x80));
        ImportedSample flatSrc;
        QString error;
        importAudioBytes(fixtureWav(flat), QStringLiteral("f/flat.wav"), &flatSrc, &error);
        const struct {
            double rate;
            int key;
            double cents;
            quint32 agbp;
        } vectors[] = {
            {13379.0, 60, 0.0, 13700096}, {13379.0, 72, 0.0, 6850048},
            {13379.0, 57, 0.0, 16292252}, {13379.0, 58, 25.0, 15157369},
            {3344.75, 60, 0.0, 3425024},  {44100.0, 69, 50.0, 26086940},
            {6689.5, 60, 0.0, 6850048},
        };
        for (const auto &v : vectors) {
            SampleDocument doc(flatSrc);
            SampleEditParams p = doc.params();
            p.targetRate = v.rate;
            p.baseKey = v.key;
            p.fineTuneCents = v.cents;
            doc.setParams(p);
            if (doc.processed().freq != v.agbp) {
                std::fprintf(stderr,
                             "samplecheck: FAIL: retune (%g Hz, key %d, %g "
                             "cents): agbp %u, want %u\n",
                             v.rate, v.key, v.cents, doc.processed().freq, v.agbp);
                reporter.noteFailure();
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: retune vectors OK\n");
    }

    // ---- parity matrix: in-memory render == loader-decoded project file
    // (the audition == build invariant), plus metadata round-trip ----
    {
        const int before = reporter.failureCount();
        struct Case {
            const char *name;
            SampleEditParams params;
        };
        const SampleEditParams d = SampleDocument::defaultParams(hiRes);
        std::vector<Case> cases;
        {
            SampleEditParams p = d; // downsample, loop, auto-normalize, fades
            p.targetRate = 13379.0;
            cases.push_back({"pm_a", p});
        }
        {
            SampleEditParams p = d; // one-shot crop + retune
            p.loopOn = false;
            p.cropStart = 500;
            p.cropEnd = 8500;
            p.baseKey = 58;
            p.fineTuneCents = 25.0;
            p.targetRate = 13379.0;
            cases.push_back({"pm_b", p});
        }
        {
            SampleEditParams p = d; // fractional rate, bare pipeline
            p.targetRate = 6689.5;
            p.normalizeMode = SampleEditParams::NormalizeOff;
            p.dcRemove = SampleEditParams::Off;
            p.fadeIn = false;
            p.fadeOut = false;
            cases.push_back({"pm_c", p});
        }
        {
            SampleEditParams p = d; // identity rate, explicit looped gain
            p.targetRate = hiRes.sampleRate;
            p.normalizeMode = SampleEditParams::NormalizeLooped;
            cases.push_back({"pm_d", p});
        }
        {
            SampleEditParams p = d; // dithered
            p.targetRate = 13379.0;
            p.ditherOn = true;
            p.normalizeMode = SampleEditParams::NormalizeOff;
            cases.push_back({"pm_e", p});
        }
        {
            SampleEditParams p = d; // one-shot, odd output length (pad byte)
            p.loopOn = false;
            p.targetRate = 26758.0;
            p.normalizeMode = SampleEditParams::NormalizeOff;
            p.dcRemove = SampleEditParams::Off;
            p.fadeIn = false;
            p.fadeOut = false;
            cases.push_back({"pm_f", p});
        }

        std::vector<ProcessedSample> renders;
        QString vgText = QStringLiteral("voicegroup_parity::\n");
        for (const Case &c : cases) {
            SampleDocument doc(hiRes);
            doc.setParams(c.params);
            renders.push_back(doc.processed());
            const QByteArray bytes = writeSampleWav(renders.back());
            QString error;
            if (!SampleRegistrar::registerSample(root, QLatin1String(c.name), bytes, &error)) {
                std::fprintf(stderr, "samplecheck: FAIL: register %s: %s\n", c.name,
                             qUtf8Printable(error));
                reporter.noteFailure();
                continue;
            }
            vgText += QStringLiteral("\tvoice_directsound 60, 0, DirectSoundWaveData_%1, "
                                     "255, 0, 255, 0\n")
                          .arg(QLatin1String(c.name));

            // Metadata round-trip (DSP.md §9 item 10) on the written bytes.
            SampleWavInfo info;
            const bool inspected = SampleRegistrar::inspectSampleWav(bytes, &info, &error);
            const ProcessedSample &p = renders.back();
            reporter.expect(inspected, "export re-inspects");
            if (inspected) {
                reporter.expect(info.agbPitch == p.freq && info.agbLoopEnd == p.size &&
                                    info.numSamples == p.size &&
                                    info.sampleRate == p.declaredRate &&
                                    info.midiKey == quint32(p.unityNote) &&
                                    info.pitchFraction == p.pitchFraction,
                                "smpl/agbp/agbl re-parse to identical values");
                reporter.expect(info.loopEnabled == p.looped &&
                                    (!p.looped || (info.loopStart == p.loopStart &&
                                                   info.loopEndIncl == p.size - 1)),
                                "loop record re-parses (inclusive end n-1)");
                reporter.expect(info.waveFreq == p.freq && info.waveSize == p.size &&
                                    info.waveLoopStart == p.loopStart,
                                "derived WaveData projection matches the render");
                // Unity/fraction reconstruct m_exact with frac ∈ [0, 1).
                const double frac = double(info.pitchFraction) / 4294967296.0;
                const double exact = double(c.params.baseKey) + c.params.fineTuneCents / 100.0;
                reporter.expect(frac >= 0.0 && frac < 1.0 &&
                                    std::abs((double(info.midiKey) + frac) - exact) < 1e-6,
                                "unity/fraction reconstruct the exact key");
            }
        }

        // Loop nudge geometry for pm_a: Lout = round(8000·r0) = 2427,
        // S_out = round(2000·2427/8000) = 607, n = 3034.
        reporter.expect(renders[0].looped && renders[0].loopStart == 607 &&
                            renders[0].size == 3034 && renders[0].declaredRate == 13379,
                        "looped resample nudges the ratio onto an integer loop");
        // pm_f: odd data length exercises the RIFF pad byte.
        reporter.expect(renders[5].size == 7281, "odd-length one-shot render");
        {
            const QByteArray bytes = writeSampleWav(renders[5]);
            // Chunk order fmt/data/smpl/agbp/agbl with a pad byte after data.
            const qsizetype dataAt = 12 + 8 + 16;
            reporter.expect(bytes.mid(12, 4) == "fmt " && bytes.mid(dataAt, 4) == "data" &&
                                getU32(bytes, dataAt + 4) == 7281 &&
                                bytes[dataAt + 8 + 7281] == '\0' &&
                                bytes.mid(dataAt + 8 + 7281 + 1, 4) == "smpl" &&
                                bytes.mid(dataAt + 8 + 7281 + 1 + 8 + 36, 4) == "agbp" &&
                                bytes.mid(dataAt + 8 + 7281 + 1 + 8 + 36 + 12, 4) == "agbl",
                            "writer chunk order and RIFF pad byte");
        }

        writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_parity.inc"),
                  vgText.toUtf8());
        const QByteArray rootUtf8 = root.toLocal8Bit();
        LoadedVoiceGroup *vg = voicegroup_load(rootUtf8.constData(), "voicegroup_parity", nullptr);
        if (!vg) {
            std::fprintf(stderr, "samplecheck: FAIL: parity voicegroup_load failed\n");
            reporter.noteFailure();
        } else {
            for (size_t i = 0; i < cases.size(); i++) {
                const ProcessedSample &p = renders[i];
                const WaveData *wd = vg->voices[i].wav;
                if (!wd || !wd->data) {
                    std::fprintf(stderr, "samplecheck: FAIL: %s did not resolve\n", cases[i].name);
                    reporter.noteFailure();
                    continue;
                }
                const bool headerOk = wd->freq == p.freq && wd->loopStart == p.loopStart &&
                                      wd->size == p.size && wd->status == (p.looped ? 0x4000 : 0);
                const bool bytesOk =
                    headerOk && std::memcmp(wd->data, p.s8.constData(), p.size) == 0;
                if (!headerOk || !bytesOk) {
                    std::fprintf(stderr,
                                 "samplecheck: FAIL: %s loader parity "
                                 "(header %d bytes %d)\n",
                                 cases[i].name, int(headerOk), int(bytesOk));
                    reporter.noteFailure();
                }
            }
            voicegroup_free(vg);
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: parity matrix OK\n");
    }
    return DspFixture{std::move(hiRes), hiResWav};
}

} // namespace samplecheck
