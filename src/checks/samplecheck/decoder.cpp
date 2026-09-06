#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QDir>
#include <QtTest>
#include <algorithm>
#include <cmath>
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

void SampleProcessingTest::decodeWidths_data()
{
    QTest::addColumn<int>("width");
    QTest::newRow("prepared-u8") << 8;
    QTest::newRow("signed-16") << 16;
    QTest::newRow("signed-24") << 24;
    QTest::newRow("float-32") << 32;
}

void SampleProcessingTest::decodeWidths()
{
    QFETCH(int, width);
    QString error;
    ImportedSample sample;

    if (width == 8) {
        QVERIFY2(
            importAudioBytes(preparedSampleWav(), QStringLiteral("fix/tone8.wav"), &sample, &error),
            "u8 wav imports");
        QCOMPARE(sample.frameCount(), qint64(64));
        for (int i = 0; i < 64; ++i)
            QCOMPARE(sample.buffer[size_t(i)], float((i * 2 - 128) / 128.0));
        QVERIFY2(sample.gbaReady && sample.sourceBits == 8 && sample.sourceChannels == 1,
                 "u8 prepared shape detected");
        QVERIFY2(sample.baseKey == 58 && std::abs(sample.fracSemitone - 0.25) < 1e-12,
                 "u8 smpl unity/fraction (standard semantics)");
        QVERIFY2(sample.hasLoop && sample.loopStart == 8 && sample.loopEndIncl == 63 &&
                     sample.playLength == 64,
                 "u8 loop end takes the agbl override");
        QVERIFY2(sample.exactPitch == 15000000 && std::abs(sample.sampleRate - 13240.0948) < 0.01,
                 "u8 sample rate inverted from agbp");
        QCOMPARE(sample.suggestedName, QStringLiteral("tone8"));
        return;
    }

    if (width == 16) {
        FixtureSpec spec;
        spec.bits = 16;
        spec.rate = 44100;
        spec.withSmpl = false;
        const qint16 values[] = {0, 16384, -32768, 32767};
        for (const qint16 value : values)
            putU16(&spec.samples, quint16(value));

        QVERIFY2(importAudioBytes(fixtureWav(spec), QStringLiteral("f/s16.wav"), &sample, &error),
                 "s16 wav imports");
        QCOMPARE(sample.frameCount(), qint64(4));
        QCOMPARE(sample.buffer[0], 0.0f);
        QCOMPARE(sample.buffer[1], 0.5f);
        QCOMPARE(sample.buffer[2], -1.0f);
        QCOMPARE(sample.buffer[3], float(32767.0 / 32768.0));
        QVERIFY2(!sample.gbaReady && sample.sampleRate == 44100.0 && !sample.hasLoop &&
                     sample.baseKey == 60,
                 "s16 hi-res defaults");
        return;
    }

    if (width == 24) {
        FixtureSpec spec;
        spec.bits = 24;
        spec.withSmpl = false;
        const qint32 values[] = {0, 8388607, -8388608, -1};
        for (const qint32 value : values) {
            const quint32 bits = quint32(value);
            spec.samples += char(bits & 0xFFu);
            spec.samples += char((bits >> 8) & 0xFFu);
            spec.samples += char((bits >> 16) & 0xFFu);
        }

        QVERIFY2(importAudioBytes(fixtureWav(spec), QStringLiteral("f/s24.wav"), &sample, &error),
                 "s24 wav imports");
        QCOMPARE(sample.frameCount(), qint64(4));
        QCOMPARE(sample.buffer[0], 0.0f);
        QCOMPARE(sample.buffer[1], float(8388607.0 / 8388608.0));
        QCOMPARE(sample.buffer[2], -1.0f);
        QCOMPARE(sample.buffer[3], float(-1.0 / 8388608.0));
        return;
    }

    if (width == 32) {
        FixtureSpec spec;
        spec.formatTag = 3;
        spec.bits = 32;
        spec.withSmpl = false;
        const float values[] = {0.5f, -0.25f, 1.5f, -2.0f};
        for (const float value : values) {
            quint32 bits;
            std::memcpy(&bits, &value, sizeof(bits));
            putU32(&spec.samples, bits);
        }

        QVERIFY2(importAudioBytes(fixtureWav(spec), QStringLiteral("f/f32.wav"), &sample, &error),
                 "f32 wav imports");
        QVERIFY(sample.sourceFloat);
        QCOMPARE(sample.frameCount(), qint64(4));
        QCOMPARE(sample.buffer[0], 0.5f);
        QCOMPARE(sample.buffer[1], -0.25f);
        QCOMPARE(sample.buffer[2], 1.0f);
        QCOMPARE(sample.buffer[3], -1.0f);
        QVERIFY2(!sample.warnings.isEmpty(), "clamped floats warn");
        return;
    }

    QFAIL("unsupported PCM test width");
}

void SampleProcessingTest::decodeStereoPolicy()
{
    FixtureSpec antiPhase;
    antiPhase.bits = 16;
    antiPhase.channels = 2;
    antiPhase.withSmpl = false;
    std::vector<qint16> left(200);
    for (int i = 0; i < 200; ++i) {
        left[size_t(i)] = qint16(std::lround(16000.0 * std::sin(2.0 * kPi * i / 50.0)));
        putU16(&antiPhase.samples, quint16(left[size_t(i)]));
        putU16(&antiPhase.samples, quint16(qint16(-left[size_t(i)])));
    }

    QString error;
    ImportedSample downmixed;
    QVERIFY2(
        importAudioBytes(fixtureWav(antiPhase), QStringLiteral("f/st.wav"), &downmixed, &error),
        "anti-phase stereo imports");
    QCOMPARE(downmixed.frameCount(), qint64(200));
    for (int i = 0; i < 200; ++i)
        QVERIFY(std::abs(downmixed.buffer[size_t(i)]) < 1e-6f);
    QVERIFY2(downmixed.phaseCancelStereo && downmixed.sourceChannels == 2,
             "anti-phase stereo cancels and is flagged");

    ImportedSample leftOnly;
    QVERIFY2(importAudioBytes(fixtureWav(antiPhase), QStringLiteral("f/st.wav"), &leftOnly, &error,
                              true),
             "left-only re-import works");
    QCOMPARE(leftOnly.frameCount(), qint64(200));
    for (int i = 0; i < 200; ++i)
        QCOMPARE(leftOnly.buffer[size_t(i)], float(left[size_t(i)] / 32768.0));
    QVERIFY2(!leftOnly.phaseCancelStereo, "left-only takes channel 0 verbatim");

    FixtureSpec inPhase = antiPhase;
    inPhase.samples.clear();
    for (int i = 0; i < 200; ++i) {
        putU16(&inPhase.samples, quint16(left[size_t(i)]));
        putU16(&inPhase.samples, quint16(qint16(left[size_t(i)] / 2)));
    }
    ImportedSample mean;
    QVERIFY2(importAudioBytes(fixtureWav(inPhase), QStringLiteral("f/stm.wav"), &mean, &error),
             "in-phase stereo imports");
    QVERIFY(!mean.phaseCancelStereo);
    QCOMPARE(mean.buffer[12], float((double(left[12]) + double(left[12] / 2)) / 2.0 / 32768.0));
}

void SampleProcessingTest::decodeAiff()
{
    AiffSpec spec;
    spec.numFrames = 500;
    spec.rate = 22050.0;
    spec.baseNote = 57;
    spec.detune = -25;
    spec.loop = true;
    spec.loopStartPos = 100;
    spec.loopEndPos = 400;
    std::vector<qint16> values(500);
    for (int i = 0; i < 500; ++i) {
        values[size_t(i)] = qint16((i * 37) % 30001 - 15000);
        putBe16(&spec.ssnd, quint16(values[size_t(i)]));
    }

    QString error;
    ImportedSample sample;
    QVERIFY2(importAudioBytes(fixtureAiff(spec), QStringLiteral("f/a.aif"), &sample, &error),
             "aiff imports");
    QCOMPARE(sample.frameCount(), qint64(500));
    for (int i = 0; i < 500; ++i)
        QCOMPARE(sample.buffer[size_t(i)], float(values[size_t(i)] / 32768.0));
    QVERIFY2(sample.sampleRate == 22050.0 && sample.sourceKind == ImportedSample::Aif,
             "aiff extended-80 rate");
    QVERIFY2(sample.hasLoop && sample.loopStart == 100 && sample.loopEndIncl == 399,
             "aiff MARK/INST loop (exclusive end converted)");
    QVERIFY2(sample.baseKey == 56 && std::abs(sample.fracSemitone - 0.75) < 1e-12,
             "aiff INST detune renormalized into unity/fraction");
}

void SampleProcessingTest::decodeRefusalBoundaries_data()
{
    QTest::addColumn<QByteArray>("bytes");
    QTest::addColumn<QString>("path");
    QTest::addColumn<bool>("accepted");
    QTest::addColumn<qint64>("frames");
    QTest::addColumn<float>("secondSample");

    FixtureSpec lying;
    lying.bits = 16;
    lying.withSmpl = false;
    for (int i = 0; i < 32; ++i)
        putU16(&lying.samples, quint16(i));
    QByteArray lyingWav = fixtureWav(lying);
    const qsizetype dataSizeAt = 12 + 8 + 16 + 4;
    lyingWav[dataSizeAt] = char(0xF0);
    lyingWav[dataSizeAt + 1] = char(0xFF);
    lyingWav[dataSizeAt + 2] = char(0xFF);
    lyingWav[dataSizeAt + 3] = char(0x7F);
    QTest::newRow("lying-data-size")
        << lyingWav << QStringLiteral("f/lying.wav") << true << qint64(32) << float(1.0 / 32768.0);

    QTest::newRow("garbage") << QByteArray("MThd not audio at all") << QStringLiteral("f/x.mid")
                             << false << qint64(0) << 0.0f;

    AiffSpec aiff;
    QByteArray aifc = fixtureAiff(aiff);
    aifc.replace(8, 4, "AIFC");
    QTest::newRow("aifc") << aifc << QStringLiteral("f/x.aifc") << false << qint64(0) << 0.0f;
}

void SampleProcessingTest::decodeRefusalBoundaries()
{
    QFETCH(QByteArray, bytes);
    QFETCH(QString, path);
    QFETCH(bool, accepted);
    QFETCH(qint64, frames);
    QFETCH(float, secondSample);

    QString error;
    ImportedSample sample;
    const bool imported = importAudioBytes(bytes, path, &sample, &error);
    QCOMPARE(imported, accepted);
    if (!accepted) {
        QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
        return;
    }

    QCOMPARE(sample.frameCount(), frames);
    QCOMPARE(sample.buffer[1], secondSample);
}

void SampleProcessingTest::compressedContainers_data()
{
    QTest::addColumn<int>("codec");
    QTest::newRow("mp3") << 0;
    QTest::newRow("flac") << 1;
    QTest::newRow("ogg-vorbis") << 2;
}

void SampleProcessingTest::compressedContainers()
{
    QFETCH(int, codec);
    QString error;
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

    if (codec == 0) {
        // MP3 (mono): dr_mp3 honors the LAME gapless (delay/padding) info,
        // so the decode comes back at exactly the source's 5512 frames.
        const QByteArray mp3Bytes(reinterpret_cast<const char *>(kFixtureMp3),
                                  qsizetype(kFixtureMp3Len));
        ImportedSample mp3;
        QVERIFY2(importAudioBytes(mp3Bytes, QStringLiteral("f/tone.mp3"), &mp3, &error),
                 "mp3 fixture decodes");
        QVERIFY2(mp3.sourceKind == ImportedSample::Mp3 && mp3.sourceChannels == 1 &&
                     mp3.sourceBits == 0 && !mp3.hasPitchMetadata && !mp3.hasLoop &&
                     !mp3.gbaReady && mp3.sampleRate == 22050.0 &&
                     mp3.playLength == mp3.frameCount(),
                 "mp3 structure and metadata defaults");
        QCOMPARE(mp3.frameCount(), qint64(5512));
        const double amp =
            toneAmp(mp3.buffer, 22050.0, 440.0, 1024, size_t(mp3.frameCount()) - 1024);
        QVERIFY2(std::abs(amp - 0.5) < 0.05, "mp3 tone amplitude near 0.5");
    }

    if (codec == 1) {
        // FLAC (24-bit mono): lossless — the decode equals the source sine
        // to within one 24-bit quantization step, and bit-exactly matches
        // the golden hash.
        const QByteArray flacBytes(reinterpret_cast<const char *>(kFixtureFlac),
                                   qsizetype(kFixtureFlacLen));
        ImportedSample flac;
        QVERIFY2(importAudioBytes(flacBytes, QStringLiteral("f/tone.flac"), &flac, &error),
                 "flac fixture decodes");
        QVERIFY2(flac.sourceKind == ImportedSample::Flac && flac.sourceChannels == 1 &&
                     flac.sourceBits == 24 && !flac.hasPitchMetadata && !flac.hasLoop &&
                     flac.sampleRate == 22050.0,
                 "flac structure and metadata defaults");
        QCOMPARE(flac.frameCount(), qint64(5512));
        {
            const std::vector<float> ref = genSine(22050.0, 440.0, 0.25, 0.5);
            double maxDiff = 0.0;
            for (size_t i = 0; i < ref.size(); i++)
                maxDiff = std::max(maxDiff, std::abs(double(flac.buffer[i]) - double(ref[i])));
            QVERIFY2(maxDiff < 3e-7, "flac decode matches the source sine");
            QCOMPARE(hashFloats(flac.buffer), 0x6c3d054141a6aae7ull);
        }
    }

    if (codec == 2) {
        // Ogg Vorbis (stereo, R = 0.8·L, in-phase): mean downmix lands at
        // amp 0.45 with no phase-cancel flag; left-only re-import recovers
        // the full 0.5.
        const QByteArray oggBytes(reinterpret_cast<const char *>(kFixtureOgg),
                                  qsizetype(kFixtureOggLen));
        ImportedSample ogg;
        QVERIFY2(importAudioBytes(oggBytes, QStringLiteral("f/tone.ogg"), &ogg, &error),
                 "ogg fixture decodes");
        QVERIFY2(ogg.sourceKind == ImportedSample::Ogg && ogg.sourceChannels == 2 &&
                     ogg.sourceBits == 0 && !ogg.hasPitchMetadata && !ogg.hasLoop &&
                     !ogg.phaseCancelStereo && ogg.sampleRate == 22050.0,
                 "ogg structure and metadata defaults");
        QCOMPARE(ogg.frameCount(), qint64(5512));
        const double amp = toneAmp(ogg.buffer, 22050.0, 440.0, 512, size_t(ogg.frameCount()) - 512);
        QVERIFY2(std::abs(amp - 0.45) < 0.05, "ogg stereo mean-downmix amplitude near 0.45");
        ImportedSample left;
        QVERIFY2(importAudioBytes(oggBytes, QStringLiteral("f/tone.ogg"), &left, &error, true) &&
                     !left.warnings.isEmpty(),
                 "ogg left-only re-import decodes with the warning");
        const double lamp =
            toneAmp(left.buffer, 22050.0, 440.0, 512, size_t(left.frameCount()) - 512);
        QVERIFY2(std::abs(lamp - 0.5) < 0.05, "ogg left-only amplitude near 0.5");
    }

    // The FLAC row proves that a compressed source reaches the ordinary
    // pipeline. It is deliberately adjacent to that codec's lossless
    // oracle, so every row owns only one decoder family.
    if (codec == 1) {
        ImportedSample flac;
        const QByteArray flacBytes(reinterpret_cast<const char *>(kFixtureFlac),
                                   qsizetype(kFixtureFlacLen));
        QVERIFY2(importAudioBytes(flacBytes, QStringLiteral("f/tone.flac"), &flac, &error),
                 "flac fixture decodes for pipeline coverage");
        SampleDocument doc(flac);
        doc.setParams(SampleDocument::defaultParams(flac));
        const ProcessedSample &out = doc.processed();
        QVERIFY2(!out.s8.isEmpty() && out.size == quint32(out.s8.size()) && out.freq > 0,
                 "flac source renders through the pipeline");
    }
}

void SampleProcessingTest::compressedRefusals()
{
    QString error;
    const QByteArray opusBytes(reinterpret_cast<const char *>(kFixtureOpus),
                               qsizetype(kFixtureOpusLen));
    ImportedSample junk;
    QVERIFY2(!importAudioBytes(opusBytes, QStringLiteral("f/tone.opus"), &junk, &error),
             "ogg opus refuses");
    QVERIFY2(!error.isEmpty(), "refused codec reports an error");
    QByteArray badMp3 = QByteArray("ID3\x04", 4);
    badMp3 += QByteArray(6, '\0');
    badMp3 += QByteArray(64, '\0');
    QVERIFY2(!importAudioBytes(badMp3, QStringLiteral("f/bad.mp3"), &junk, &error),
             "sync-less mp3 refuses");
    QVERIFY2(!error.isEmpty(), "refused stream reports an error");
    QVERIFY2(!importAudioBytes(QByteArray("fLaC") + QByteArray(64, 'x'),
                               QStringLiteral("f/bad.flac"), &junk, &error),
             "corrupt flac refuses");
    QVERIFY2(!error.isEmpty(), "refused stream reports an error");
}
void SampleProcessingTest::optionalCorpus()
{
    if (m_corpusRoot.isEmpty())
        QSKIP("sample corpus not supplied; pass it as the samplecheck catalog argument.");

    const QString samplesDir = m_corpusRoot + QStringLiteral("/sound/direct_sound_samples");
    const QStringList names =
        QDir(samplesDir).entryList({QStringLiteral("sc88pro_*.wav")}, QDir::Files, QDir::Name);
    QVERIFY2(!names.isEmpty(), "corpus has sc88pro samples");
    int compared = 0;
    std::vector<double> peaks;
    std::vector<double> loopRmsList;
    for (const QString &name : names) {
        const QString wavPath = samplesDir + QLatin1Char('/') + name;
        const QString binPath = wavPath.left(wavPath.size() - 4) + QStringLiteral(".bin");
        const QByteArray bin = readFileBytes(binPath);
        ImportedSample src;
        QString error;
        QVERIFY2(importAudioFile(wavPath, &src, &error),
                 qPrintable(name + QStringLiteral(": ") + error));
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
        QVERIFY2(bin.size() >= 16,
                 qPrintable(name + QStringLiteral(": required built .bin artifact is absent")));
        const quint32 flags = getU32(bin, 0);
        QCOMPARE(p.freq, getU32(bin, 4));
        QCOMPARE(p.loopStart, getU32(bin, 8));
        QCOMPARE(p.size, getU32(bin, 12));
        QCOMPARE(p.looped, bool(flags & 0x40000000u));
        QVERIFY(bin.size() >= 16 + int(p.size));
        QCOMPARE(QByteArrayView(bin).sliced(16, p.size), QByteArrayView(p.s8));
        ++compared;
    }
    QVERIFY2(compared > 0, "at least one corpus .bin compared");
    QVERIFY2(!peaks.empty() && !loopRmsList.empty(),
             "corpus provides peak and loop-RMS observations");
    const double peakMedian = median(peaks);
    const double rmsMedian = median(loopRmsList);
    QVERIFY2(peakMedian >= 117.0 && peakMedian <= 127.0,
             "corpus peak median inside the recorded IQR");
    QVERIFY2(rmsMedian >= 37.9 && rmsMedian <= 50.7,
             "corpus loop-RMS median inside the recorded IQR");
}

} // namespace samplecheck
