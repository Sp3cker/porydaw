#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QDir>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <span>
#include <vector>

#include "audio/sampledoc.h"
#include "audio/sampledsp.h"
#include "audio/sampleimport.h"
#include "checks/samplecheck_fixtures.h"

namespace {
constexpr double kPi = 3.14159265358979323846;
}

namespace samplecheck {

void runDecodeChecks(Reporter &reporter, const RegisteredSampleProject &project)
{
    const QByteArray &fixture = project.wavFixture;
    // ---- hi-res decoding (phase 2): every container → canonical floats ----
    {
        const int before = reporter.failureCount();
        QString error;

        // u8 prepared file: exact (x − 128)/128 floats, agbp-derived true
        // rate, agbl-corrected loop end, prepared-shape flag.
        ImportedSample u8s;
        reporter.expect(importAudioBytes(fixture, QStringLiteral("fix/tone8.wav"), &u8s, &error),
                        "u8 wav imports");
        bool u8ok = u8s.frameCount() == 64;
        for (int i = 0; u8ok && i < 64; i++)
            u8ok = u8s.buffer[size_t(i)] == float((i * 2 - 128) / 128.0);
        reporter.expect(u8ok, "u8 floats are exactly (x-128)/128");
        reporter.expect(u8s.gbaReady && u8s.sourceBits == 8 && u8s.sourceChannels == 1,
                        "u8 prepared shape detected");
        reporter.expect(u8s.baseKey == 58 && std::abs(u8s.fracSemitone - 0.25) < 1e-12,
                        "u8 smpl unity/fraction (standard semantics)");
        reporter.expect(u8s.hasLoop && u8s.loopStart == 8 && u8s.loopEndIncl == 63 &&
                            u8s.playLength == 64,
                        "u8 loop end takes the agbl override");
        reporter.expect(u8s.exactPitch == 15000000 && std::abs(u8s.sampleRate - 13240.0948) < 0.01,
                        "u8 sample rate inverted from agbp");
        reporter.expect(u8s.suggestedName == QStringLiteral("tone8"),
                        "suggested name from the basename");

        // s16: x/32768 exactly.
        FixtureSpec s16;
        s16.bits = 16;
        s16.rate = 44100;
        s16.withSmpl = false;
        const qint16 s16vals[] = {0, 16384, -32768, 32767};
        for (const qint16 v : s16vals)
            putU16(&s16.samples, quint16(v));
        ImportedSample s16s;
        reporter.expect(
            importAudioBytes(fixtureWav(s16), QStringLiteral("f/s16.wav"), &s16s, &error),
            "s16 wav imports");
        reporter.expect(s16s.frameCount() == 4 && s16s.buffer[0] == 0.0f &&
                            s16s.buffer[1] == 0.5f && s16s.buffer[2] == -1.0f &&
                            s16s.buffer[3] == float(32767.0 / 32768.0),
                        "s16 floats are exactly x/32768");
        reporter.expect(!s16s.gbaReady && s16s.sampleRate == 44100.0 && !s16s.hasLoop &&
                            s16s.baseKey == 60,
                        "s16 hi-res defaults");

        // s24: x/8388608 exactly.
        FixtureSpec s24;
        s24.bits = 24;
        s24.withSmpl = false;
        const qint32 s24vals[] = {0, 8388607, -8388608, -1};
        for (const qint32 v : s24vals) {
            s24.samples += char(v & 0xFF);
            s24.samples += char((v >> 8) & 0xFF);
            s24.samples += char((v >> 16) & 0xFF);
        }
        ImportedSample s24s;
        reporter.expect(
            importAudioBytes(fixtureWav(s24), QStringLiteral("f/s24.wav"), &s24s, &error),
            "s24 wav imports");
        reporter.expect(s24s.frameCount() == 4 && s24s.buffer[0] == 0.0f &&
                            s24s.buffer[1] == float(8388607.0 / 8388608.0) &&
                            s24s.buffer[2] == -1.0f && s24s.buffer[3] == float(-1.0 / 8388608.0),
                        "s24 floats are exactly x/8388608");

        // float32 passes through; out-of-range clamps with a warning.
        FixtureSpec f32;
        f32.formatTag = 3;
        f32.bits = 32;
        f32.withSmpl = false;
        const float f32vals[] = {0.5f, -0.25f, 1.5f, -2.0f};
        for (const float v : f32vals) {
            quint32 bits;
            std::memcpy(&bits, &v, 4);
            putU32(&f32.samples, bits);
        }
        ImportedSample f32s;
        reporter.expect(
            importAudioBytes(fixtureWav(f32), QStringLiteral("f/f32.wav"), &f32s, &error),
            "f32 wav imports");
        reporter.expect(f32s.sourceFloat && f32s.frameCount() == 4 && f32s.buffer[0] == 0.5f &&
                            f32s.buffer[1] == -0.25f && f32s.buffer[2] == 1.0f &&
                            f32s.buffer[3] == -1.0f,
                        "f32 passthrough with ±1 clamp");
        reporter.expect(!f32s.warnings.isEmpty(), "clamped floats warn");

        // Stereo: mean downmix; anti-phase flags phase cancellation and the
        // left-only re-import takes channel 0 verbatim.
        FixtureSpec st;
        st.bits = 16;
        st.channels = 2;
        st.withSmpl = false;
        std::vector<qint16> left(200);
        for (int i = 0; i < 200; i++) {
            left[size_t(i)] = qint16(std::lround(16000.0 * std::sin(2.0 * kPi * i / 50.0)));
            putU16(&st.samples, quint16(left[size_t(i)]));
            putU16(&st.samples, quint16(qint16(-left[size_t(i)])));
        }
        ImportedSample sts;
        reporter.expect(importAudioBytes(fixtureWav(st), QStringLiteral("f/st.wav"), &sts, &error),
                        "anti-phase stereo imports");
        bool cancelled = sts.frameCount() == 200;
        for (int i = 0; cancelled && i < 200; i++)
            cancelled = std::abs(sts.buffer[size_t(i)]) < 1e-6f;
        reporter.expect(cancelled && sts.phaseCancelStereo && sts.sourceChannels == 2,
                        "anti-phase stereo cancels and is flagged");
        ImportedSample stl;
        reporter.expect(
            importAudioBytes(fixtureWav(st), QStringLiteral("f/st.wav"), &stl, &error, true),
            "left-only re-import works");
        bool leftOk = stl.frameCount() == 200;
        for (int i = 0; leftOk && i < 200; i++)
            leftOk = stl.buffer[size_t(i)] == float(left[size_t(i)] / 32768.0);
        reporter.expect(leftOk && !stl.phaseCancelStereo, "left-only takes channel 0 verbatim");
        FixtureSpec stIn = st;
        stIn.samples.clear();
        for (int i = 0; i < 200; i++) {
            putU16(&stIn.samples, quint16(left[size_t(i)]));
            putU16(&stIn.samples, quint16(qint16(left[size_t(i)] / 2)));
        }
        ImportedSample stm;
        reporter.expect(
            importAudioBytes(fixtureWav(stIn), QStringLiteral("f/stm.wav"), &stm, &error) &&
                !stm.phaseCancelStereo &&
                stm.buffer[12] == float((double(left[12]) + double(left[12] / 2)) / 2.0 / 32768.0),
            "in-phase stereo mean-downmixes without the flag");

        // AIFF: big-endian 16-bit, extended-80 rate, MARK/INST loop, INST
        // detune folded into unity/fraction.
        AiffSpec aif;
        aif.numFrames = 500;
        aif.rate = 22050.0;
        aif.baseNote = 57;
        aif.detune = -25;
        aif.loop = true;
        aif.loopStartPos = 100;
        aif.loopEndPos = 400;
        std::vector<qint16> aifVals(500);
        for (int i = 0; i < 500; i++) {
            aifVals[size_t(i)] = qint16((i * 37) % 30001 - 15000);
            putBe16(&aif.ssnd, quint16(aifVals[size_t(i)]));
        }
        ImportedSample aifs;
        reporter.expect(
            importAudioBytes(fixtureAiff(aif), QStringLiteral("f/a.aif"), &aifs, &error),
            "aiff imports");
        bool aifOk = aifs.frameCount() == 500;
        for (int i = 0; aifOk && i < 500; i++)
            aifOk = aifs.buffer[size_t(i)] == float(aifVals[size_t(i)] / 32768.0);
        reporter.expect(aifOk, "aiff floats are exactly x/32768 (big-endian)");
        reporter.expect(aifs.sampleRate == 22050.0 && aifs.sourceKind == ImportedSample::Aif,
                        "aiff extended-80 rate");
        reporter.expect(aifs.hasLoop && aifs.loopStart == 100 && aifs.loopEndIncl == 399,
                        "aiff MARK/INST loop (exclusive end converted)");
        reporter.expect(aifs.baseKey == 56 && std::abs(aifs.fracSemitone - 0.75) < 1e-12,
                        "aiff INST detune renormalized into unity/fraction");

        // A data chunk claiming ~2 GB in a 108-byte file must never drive a
        // header-sized allocation: dr_wav clamps the chunk to the actual
        // buffer (its onTell validation), and decodeWav's own guard backs
        // that up, so the import succeeds with exactly the real frames.
        FixtureSpec lying;
        lying.bits = 16;
        lying.withSmpl = false;
        for (int i = 0; i < 32; i++)
            putU16(&lying.samples, quint16(i));
        QByteArray lyingWav = fixtureWav(lying);
        const qsizetype dataSizeAt = 12 + 8 + 16 + 4; // data chunk size field
        lyingWav[dataSizeAt] = char(0xF0);
        lyingWav[dataSizeAt + 1] = char(0xFF);
        lyingWav[dataSizeAt + 2] = char(0xFF);
        lyingWav[dataSizeAt + 3] = char(0x7F);
        ImportedSample lied;
        reporter.expect(importAudioBytes(lyingWav, QStringLiteral("f/lying.wav"), &lied, &error) &&
                            lied.frameCount() == 32 && lied.buffer[1] == float(1.0 / 32768.0),
                        "lying data-chunk size clamps to the real bytes");

        // Refusals.
        ImportedSample junk;
        reporter.expect(!importAudioBytes(QByteArray("MThd not audio at all"),
                                          QStringLiteral("f/x.mid"), &junk, &error),
                        "garbage refused");
        reporter.expectError(error,
                             QStringLiteral("not a supported audio file (WAV, AIFF, "
                                            "MP3, FLAC, and Ogg Vorbis sources are "
                                            "supported)."),
                             "unsupported-format text");
        QByteArray aifc = fixtureAiff(aif);
        aifc.replace(8, 4, "AIFC");
        reporter.expect(!importAudioBytes(aifc, QStringLiteral("f/x.aifc"), &junk, &error),
                        "AIFC refused");
        reporter.expectError(error,
                             QStringLiteral("AIFF-C is not supported — export "
                                            "uncompressed AIFF or WAV."),
                             "aifc text");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: hi-res decode OK\n");
    }
}

void runCompressedChecks(Reporter &reporter)
{
    // ---- compressed formats (phase 4): dr_mp3 / dr_flac / stb_vorbis ----
    // Fixtures are embedded (samplecheck_fixtures.h, regenerate with
    // docs/sample-editor/tools/make_fixtures.py): a 440 Hz amp-0.5 sine per
    // codec. FLAC is lossless, so its decode is asserted bit-exact against
    // a golden FNV-1a hash; the lossy codecs get exact structure (length /
    // rate / channels — deterministic for the vendored decoders) plus
    // tone-amplitude tolerance. Regenerating the fixtures with a different
    // encoder invalidates the goldens — the failure output prints actuals.
    {
        const int before = reporter.failureCount();
        QString error;
        auto expectCount = [&](qint64 got, qint64 want, const char *what) {
            if (got != want) {
                std::fprintf(stderr, "samplecheck: FAIL: %s (want %lld, got %lld)\n", what,
                             (long long)want, (long long)got);
                reporter.noteFailure();
            }
        };
        auto hashFloats = [](const std::vector<float> &v) {
            quint64 h = 1469598103934665603ull;
            for (const float f : v) {
                quint32 bits;
                std::memcpy(&bits, &f, 4);
                for (int i = 0; i < 4; i++) {
                    h ^= (bits >> (8 * i)) & 0xFF;
                    h *= 1099511628211ull;
                }
            }
            return h;
        };

        // MP3 (mono): dr_mp3 honors the LAME gapless (delay/padding) info,
        // so the decode comes back at exactly the source's 5512 frames.
        const QByteArray mp3Bytes(reinterpret_cast<const char *>(kFixtureMp3),
                                  qsizetype(kFixtureMp3Len));
        ImportedSample mp3;
        reporter.expect(importAudioBytes(mp3Bytes, QStringLiteral("f/tone.mp3"), &mp3, &error),
                        "mp3 fixture decodes");
        reporter.expect(mp3.sourceKind == ImportedSample::Mp3 && mp3.sourceChannels == 1 &&
                            mp3.sourceBits == 0 && !mp3.hasPitchMetadata && !mp3.hasLoop &&
                            !mp3.gbaReady && mp3.sampleRate == 22050.0 &&
                            mp3.playLength == mp3.frameCount(),
                        "mp3 structure and metadata defaults");
        expectCount(mp3.frameCount(), 5512, "mp3 decoded length");
        if (mp3.frameCount() > 3000) {
            const double amp =
                toneAmp(mp3.buffer, 22050.0, 440.0, 1024, size_t(mp3.frameCount()) - 1024);
            reporter.expect(std::abs(amp - 0.5) < 0.05, "mp3 tone amplitude near 0.5");
        }

        // FLAC (24-bit mono): lossless — the decode equals the source sine
        // to within one 24-bit quantization step, and bit-exactly matches
        // the golden hash.
        const QByteArray flacBytes(reinterpret_cast<const char *>(kFixtureFlac),
                                   qsizetype(kFixtureFlacLen));
        ImportedSample flac;
        reporter.expect(importAudioBytes(flacBytes, QStringLiteral("f/tone.flac"), &flac, &error),
                        "flac fixture decodes");
        reporter.expect(flac.sourceKind == ImportedSample::Flac && flac.sourceChannels == 1 &&
                            flac.sourceBits == 24 && !flac.hasPitchMetadata && !flac.hasLoop &&
                            flac.sampleRate == 22050.0,
                        "flac structure and metadata defaults");
        expectCount(flac.frameCount(), 5512, "flac decoded length");
        if (flac.frameCount() == 5512) {
            const std::vector<float> ref = genSine(22050.0, 440.0, 0.25, 0.5);
            double maxDiff = 0.0;
            for (size_t i = 0; i < ref.size(); i++)
                maxDiff = std::max(maxDiff, std::abs(double(flac.buffer[i]) - double(ref[i])));
            reporter.expect(maxDiff < 3e-7, "flac decode matches the source sine");
            const quint64 h = hashFloats(flac.buffer);
            if (h != 0x6c3d054141a6aae7ull) {
                std::fprintf(stderr,
                             "samplecheck: FAIL: flac decode hash "
                             "(got 0x%llx)\n",
                             (unsigned long long)h);
                reporter.noteFailure();
            }
        }

        // Ogg Vorbis (stereo, R = 0.8·L, in-phase): mean downmix lands at
        // amp 0.45 with no phase-cancel flag; left-only re-import recovers
        // the full 0.5.
        const QByteArray oggBytes(reinterpret_cast<const char *>(kFixtureOgg),
                                  qsizetype(kFixtureOggLen));
        ImportedSample ogg;
        reporter.expect(importAudioBytes(oggBytes, QStringLiteral("f/tone.ogg"), &ogg, &error),
                        "ogg fixture decodes");
        reporter.expect(ogg.sourceKind == ImportedSample::Ogg && ogg.sourceChannels == 2 &&
                            ogg.sourceBits == 0 && !ogg.hasPitchMetadata && !ogg.hasLoop &&
                            !ogg.phaseCancelStereo && ogg.sampleRate == 22050.0,
                        "ogg structure and metadata defaults");
        expectCount(ogg.frameCount(), 5512, "ogg decoded length");
        if (ogg.frameCount() > 3000) {
            const double amp =
                toneAmp(ogg.buffer, 22050.0, 440.0, 512, size_t(ogg.frameCount()) - 512);
            reporter.expect(std::abs(amp - 0.45) < 0.05,
                            "ogg stereo mean-downmix amplitude near 0.45");
            ImportedSample left;
            reporter.expect(
                importAudioBytes(oggBytes, QStringLiteral("f/tone.ogg"), &left, &error, true) &&
                    !left.warnings.isEmpty(),
                "ogg left-only re-import decodes with the warning");
            const double lamp =
                toneAmp(left.buffer, 22050.0, 440.0, 512, size_t(left.frameCount()) - 512);
            reporter.expect(std::abs(lamp - 0.5) < 0.05, "ogg left-only amplitude near 0.5");
        }

        // Downstream is untouched: a compressed source runs the ordinary
        // pipeline to final s8 bytes.
        if (flac.frameCount() > 0) {
            SampleDocument doc(flac);
            doc.setParams(SampleDocument::defaultParams(flac));
            const ProcessedSample &out = doc.processed();
            reporter.expect(!out.s8.isEmpty() && out.size == quint32(out.s8.size()) && out.freq > 0,
                            "flac source renders through the pipeline");
        }

        // Refusals: Ogg that is not Vorbis (Opus), and corrupt streams
        // behind valid magics.
        const QByteArray opusBytes(reinterpret_cast<const char *>(kFixtureOpus),
                                   qsizetype(kFixtureOpusLen));
        ImportedSample junk;
        reporter.expect(!importAudioBytes(opusBytes, QStringLiteral("f/tone.opus"), &junk, &error),
                        "ogg opus refused");
        reporter.expectError(error,
                             QStringLiteral("cannot decode the Ogg file — only Ogg "
                                            "Vorbis is supported (Opus and other "
                                            "codecs are not)."),
                             "opus refusal text");
        QByteArray badMp3 = QByteArray("ID3\x04", 4);
        badMp3 += QByteArray(6, '\0');
        badMp3 += QByteArray(64, '\0');
        reporter.expect(!importAudioBytes(badMp3, QStringLiteral("f/bad.mp3"), &junk, &error),
                        "sync-less mp3 refused");
        reporter.expectError(error, QStringLiteral("the MP3 file is corrupt or truncated."),
                             "mp3 corrupt text");
        reporter.expect(!importAudioBytes(QByteArray("fLaC") + QByteArray(64, 'x'),
                                          QStringLiteral("f/bad.flac"), &junk, &error),
                        "corrupt flac refused");
        reporter.expectError(error, QStringLiteral("the FLAC file is corrupt or truncated."),
                             "flac corrupt text");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: compressed formats OK\n");
    }
}
void runCorpusChecks(Reporter &reporter, const QString &corpusRoot)
{
    // ---- corpus-conditional: the sc88pro reference set (item 5/6 halves) ----
    if (!corpusRoot.isEmpty()) {
        const int before = reporter.failureCount();
        const QString samplesDir = corpusRoot + QStringLiteral("/sound/direct_sound_samples");
        const QStringList names =
            QDir(samplesDir).entryList({QStringLiteral("sc88pro_*.wav")}, QDir::Files, QDir::Name);
        reporter.expect(!names.isEmpty(), "corpus has sc88pro samples");
        int compared = 0;
        std::vector<double> peaks, loopRmsList;
        for (const QString &name : names) {
            const QString wavPath = samplesDir + QLatin1Char('/') + name;
            const QString binPath = wavPath.left(wavPath.size() - 4) + QStringLiteral(".bin");
            const QByteArray bin = readFileBytes(binPath);
            ImportedSample src;
            QString error;
            if (!importAudioFile(wavPath, &src, &error)) {
                std::fprintf(stderr, "samplecheck: FAIL: corpus import %s: %s\n",
                             qUtf8Printable(name), qUtf8Printable(error));
                reporter.noteFailure();
                continue;
            }
            SampleDocument doc(src);
            const ProcessedSample &p = doc.processed();

            double peak = 0.0;
            for (const char b : p.s8)
                peak = std::max(peak, std::abs(double(qint8(b))));
            peaks.push_back(peak);
            if (p.looped) {
                double sum = 0.0;
                for (quint32 i = p.loopStart; i < p.size; i++)
                    sum += double(qint8(p.s8[int(i)])) * double(qint8(p.s8[int(i)]));
                loopRmsList.push_back(std::sqrt(sum / double(p.size - p.loopStart)));
            }
            if (bin.size() < 16)
                continue; // no built artifact for this file — skip parity
            const quint32 flags = getU32(bin, 0);
            const bool ok = p.freq == getU32(bin, 4) && p.loopStart == getU32(bin, 8) &&
                            p.size == getU32(bin, 12) && p.looped == bool(flags & 0x40000000u) &&
                            bin.size() >= 16 + int(p.size) &&
                            std::memcmp(bin.constData() + 16, p.s8.constData(), p.size) == 0;
            if (!ok) {
                std::fprintf(stderr, "samplecheck: FAIL: corpus .bin parity: %s\n",
                             qUtf8Printable(name));
                reporter.noteFailure();
            } else {
                compared++;
            }
        }
        std::printf("samplecheck: corpus: %d/%d files .bin-compared\n", compared,
                    int(names.size()));
        reporter.expect(compared > 0, "at least one corpus .bin compared");
        // Stats drift detection: medians stay inside the recorded IQRs
        // (DSP.md §5.1).
        const double peakMedian = median(peaks);
        const double rmsMedian = median(loopRmsList);
        reporter.expect(peakMedian >= 117.0 && peakMedian <= 127.0,
                        "corpus peak median inside the recorded IQR");
        reporter.expect(rmsMedian >= 37.9 && rmsMedian <= 50.7,
                        "corpus loop-RMS median inside the recorded IQR");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: corpus round-trip OK\n");
    } else {
        std::printf("samplecheck: corpus sections SKIPPED (no corpus root given)\n");
    }
}

} // namespace samplecheck
