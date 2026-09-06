#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QTemporaryDir>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
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

enum class ParityProfile {
    A,
    B,
    C,
    D,
    E,
    F,
};

struct ImportedHiRes {
    ImportedSample sample;
    QString error;
    bool ok = false;
};

ImportedHiRes importHiRes()
{
    ImportedHiRes result;
    result.ok =
        importAudioBytes(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"),
                         &result.sample, &result.error);
    return result;
}

SampleEditParams parityParams(ParityProfile profile, double sourceRate, SampleEditParams params)
{
    switch (profile) {
    case ParityProfile::A:
        params.targetRate = 13379.0;
        break;
    case ParityProfile::B:
        params.loopOn = false;
        params.cropStart = 500;
        params.cropEnd = 8500;
        params.baseKey = 58;
        params.fineTuneCents = 25.0;
        params.targetRate = 13379.0;
        break;
    case ParityProfile::C:
        params.targetRate = 6689.5;
        params.normalizeMode = SampleEditParams::NormalizeOff;
        params.dcRemove = SampleEditParams::Off;
        params.fadeIn = false;
        params.fadeOut = false;
        break;
    case ParityProfile::D:
        params.targetRate = sourceRate;
        params.normalizeMode = SampleEditParams::NormalizeLooped;
        break;
    case ParityProfile::E:
        params.targetRate = 13379.0;
        params.ditherOn = true;
        params.normalizeMode = SampleEditParams::NormalizeOff;
        break;
    case ParityProfile::F:
        params.loopOn = false;
        params.targetRate = 26758.0;
        params.normalizeMode = SampleEditParams::NormalizeOff;
        params.dcRemove = SampleEditParams::Off;
        params.fadeIn = false;
        params.fadeOut = false;
        break;
    }
    return params;
}
} // namespace

namespace samplecheck {

void SampleProcessingTest::resamplePassband_data()
{
    QTest::addColumn<double>("frequency");
    QTest::newRow("100-hz") << 100.0;
    QTest::newRow("500-hz") << 500.0;
    QTest::newRow("1-khz") << 1000.0;
    QTest::newRow("2-khz") << 2000.0;
    QTest::newRow("4-khz") << 4000.0;
    QTest::newRow("5-khz") << 5000.0;
    QTest::newRow("5.5-khz") << 5500.0;
    QTest::newRow("6-khz") << 6000.0;
}

void SampleProcessingTest::resamplePassband()
{
    QFETCH(double, frequency);
    constexpr double sourceRate = 44100.0;
    constexpr double targetRate = 13379.0;
    constexpr double ratio = targetRate / sourceRate;
    const std::vector<float> input = genSineFast(sourceRate, frequency, 0.3, 0.5);
    const qint64 outputLength = qint64(std::llround(double(input.size()) * ratio));
    const std::vector<float> output = SampleDsp::resampleSinc(input, ratio, outputLength);
    const double amplitude = toneAmp(output, targetRate, frequency, size_t(outputLength / 5),
                                     size_t(outputLength * 4 / 5));
    const double decibels = 20.0 * std::log10(amplitude / 0.5);
    QVERIFY2(
        std::abs(decibels) <= 0.1,
        qPrintable(QStringLiteral("passband %1 Hz offset %2 dB").arg(frequency).arg(decibels)));
}

void SampleProcessingTest::resampleAliasRejection_data()
{
    QTest::addColumn<double>("frequency");
    QTest::newRow("8-khz") << 8000.0;
    QTest::newRow("10-khz") << 10000.0;
    QTest::newRow("14-khz") << 14000.0;
}

void SampleProcessingTest::resampleAliasRejection()
{
    QFETCH(double, frequency);
    constexpr double sourceRate = 44100.0;
    constexpr double targetRate = 13379.0;
    constexpr double ratio = targetRate / sourceRate;
    const std::vector<float> input = genSine(sourceRate, frequency, 0.3, 0.5);
    const qint64 outputLength = qint64(std::llround(double(input.size()) * ratio));
    const std::vector<float> output = SampleDsp::resampleSinc(input, ratio, outputLength);
    const double outputRms = rmsOf(output, size_t(outputLength / 5), size_t(outputLength * 4 / 5));
    const double inputRms = 0.5 / std::sqrt(2.0);
    QVERIFY2(outputRms <= inputRms * 1e-4,
             qPrintable(QStringLiteral("alias %1 Hz leaked").arg(frequency)));
}

void SampleProcessingTest::resampleDcGain()
{
    constexpr double sourceRate = 44100.0;
    constexpr double targetRate = 13379.0;
    constexpr double ratio = targetRate / sourceRate;
    const std::vector<float> input(size_t(sourceRate * 0.2), 0.25f);
    const qint64 outputLength = qint64(std::llround(double(input.size()) * ratio));
    const std::vector<float> output = SampleDsp::resampleSinc(input, ratio, outputLength);
    for (qint64 i = 100; i < outputLength - 100; ++i)
        QVERIFY(std::abs(double(output[size_t(i)]) - 0.25) <= 1e-4);
}

void SampleProcessingTest::resampleImpulseSymmetry()
{
    std::vector<float> input(4000, 0.0f);
    input[2000] = 1.0f;
    const std::vector<float> output = SampleDsp::resampleSinc(input, 0.5, 2000);
    QVERIFY(output[1000] > 0.1);
    for (int distance = 1; distance <= 500; ++distance)
        QVERIFY(std::abs(double(output[size_t(1000 + distance)]) -
                         double(output[size_t(1000 - distance)])) <= 2e-6);
}

void SampleProcessingTest::resampleFrequencyAccuracy()
{
    constexpr double sourceRate = 44100.0;
    constexpr double targetRate = 13379.0;
    constexpr double ratio = targetRate / sourceRate;
    const std::vector<float> input = genSine(sourceRate, 1000.0, 1.2, 0.5);
    const qint64 outputLength = qint64(std::llround(double(input.size()) * ratio));
    const std::vector<float> output = SampleDsp::resampleSinc(input, ratio, outputLength);
    double bestFrequency = 0.0;
    double bestAmplitude = -1.0;
    for (double frequency = 998.0; frequency <= 1002.0; frequency += 0.05) {
        const double amplitude = toneAmp(output, targetRate, frequency, 0, size_t(outputLength));
        if (amplitude > bestAmplitude) {
            bestAmplitude = amplitude;
            bestFrequency = frequency;
        }
    }
    QVERIFY(std::abs(bestFrequency - 1000.0) <= 0.5);
}

void SampleProcessingTest::resampleIdentity()
{
    std::vector<float> input(5000);
    quint32 random = 12345;
    for (float &value : input) {
        random = random * 1664525u + 1013904223u;
        value = float(double(random) / 4294967296.0 - 0.5);
    }
    const std::vector<float> output = SampleDsp::resampleSinc(input, 1.0, qint64(input.size()));
    QCOMPARE(output.size(), input.size());
    QVERIFY(std::memcmp(input.data(), output.data(), input.size() * sizeof(float)) == 0);
}

void SampleProcessingTest::quantizationVectors_data()
{
    QTest::addColumn<double>("input");
    QTest::addColumn<int>("expected");
    QTest::newRow("positive-ceiling") << 1.0 << 127;
    QTest::newRow("negative-floor") << -1.0 << -128;
    QTest::newRow("positive-half-ceiling") << 127.5 / 128.0 << 127;
    QTest::newRow("negative-half-floor") << -127.5 / 128.0 << -128;
    QTest::newRow("positive-exact") << 127.0 / 128.0 << 127;
    QTest::newRow("negative-exact") << -127.0 / 128.0 << -127;
    QTest::newRow("positive-half") << 0.5 << 64;
    QTest::newRow("negative-half") << -0.5 << -64;
    QTest::newRow("positive-near-zero") << 1e-9 << 0;
    QTest::newRow("negative-near-zero") << -1e-9 << -1;
    QTest::newRow("zero") << 0.0 << 0;
}

void SampleProcessingTest::quantizationVectors()
{
    QFETCH(double, input);
    QFETCH(int, expected);
    QCOMPARE(int(SampleDsp::quantizeToAgb8(input)), expected);
}

void SampleProcessingTest::quantizationU8Roundtrip()
{
    for (int value = 0; value < 256; ++value)
        QCOMPARE(int(SampleDsp::quantizeToAgb8((value - 128) / 128.0)), value - 128);
}

void SampleProcessingTest::quantizationDither()
{
    std::vector<float> noise(2000);
    quint32 random = 999;
    for (float &value : noise) {
        random = random * 1664525u + 1013904223u;
        value = float(double(random) / 4294967296.0 - 0.5);
    }
    const QByteArray dithered = SampleDsp::quantizeBuffer(noise, true);
    QCOMPARE(SampleDsp::quantizeBuffer(noise, true), dithered);
    QVERIFY(SampleDsp::quantizeBuffer(noise, false) != dithered);
}

void SampleProcessingTest::markerMapping()
{
    const float zeroCrossings[] = {0.5f,  0.5f,  0.5f, 0.5f, -0.5f, -0.5f,
                                   -0.5f, -0.5f, 0.5f, 0.5f, 0.5f,  0.5f};
    QCOMPARE(SampleDsp::nearestZeroCrossing(std::span<const float>(zeroCrossings), 5), qint64(4));
    QCOMPARE(SampleDsp::nearestZeroCrossing(std::span<const float>(zeroCrossings), 7), qint64(8));
    QCOMPARE(SampleDsp::nearestZeroCrossing(std::span<const float>(zeroCrossings), 0), qint64(4));
    QCOMPARE(SampleDsp::mapMarker(2000, 500, 0.5), qint64(750));
    QCOMPARE(SampleDsp::mapMarker(2001, 0, 13379.0 / 44100.0), qint64(607));
}

void SampleProcessingTest::normalization_data()
{
    QTest::addColumn<int>("profile");
    QTest::newRow("looped-rms") << 0;
    QTest::newRow("looped-peak-cap") << 1;
    QTest::newRow("one-shot-peak") << 2;
    QTest::newRow("near-silent-refusal") << 3;
}

void SampleProcessingTest::normalization()
{
    QFETCH(int, profile);
    QString warning;

    if (profile == 0) {
        std::vector<float> tone = genSine(13379.0, 440.0, 0.5, 0.11);
        const double gain = SampleDsp::normalizeGain(tone, true, 0, &warning);
        for (float &value : tone)
            value = float(double(value) * gain);
        const double rms = rmsOf(tone, 0, tone.size());
        QVERIFY(std::abs(20.0 * std::log10(rms / SampleDsp::kTargetLoopRms)) < 0.1);
        QVERIFY(warning.isEmpty());
        return;
    }

    if (profile == 1) {
        std::vector<float> crest = genSine(13379.0, 440.0, 0.5, 0.05);
        crest[100] = 0.9f;
        const double gain = SampleDsp::normalizeGain(crest, true, 0, &warning);
        double peak = 0.0;
        for (const float value : crest)
            peak = (std::max)(peak, std::abs(double(value) * gain));
        QVERIFY(peak <= SampleDsp::kPeakCeiling + 1e-9);
        QVERIFY(std::abs(peak - SampleDsp::kPeakCeiling) < 1e-6);
        return;
    }

    if (profile == 2) {
        const std::vector<float> hit = genSine(13379.0, 200.0, 0.1, 0.4);
        const double gain = SampleDsp::normalizeGain(hit, false, 0, &warning);
        double peak = 0.0;
        for (const float value : hit)
            peak = (std::max)(peak, std::abs(double(value) * gain));
        QVERIFY(std::abs(peak - SampleDsp::kPeakCeiling) < 1e-6);
        return;
    }

    if (profile == 3) {
        const std::vector<float> quiet(1000, 0.01f);
        QCOMPARE(SampleDsp::normalizeGain(quiet, false, 0, &warning), 1.0);
        QVERIFY(!warning.isEmpty());
        return;
    }

    QFAIL("unsupported normalization profile");
}

void SampleProcessingTest::dspDeterminism()
{
    const ImportedHiRes imported = importHiRes();
    QVERIFY2(imported.ok, qPrintable(imported.error));
    const ImportedSample &source = imported.sample;

    QCOMPARE(SampleDocument::defaultParams(source).targetRate, 13379.0);
    ImportedSample lowRate = source;
    lowRate.sampleRate = 8000.0;
    lowRate.gbaReady = false;
    QCOMPARE(SampleDocument::defaultParams(lowRate).targetRate, 8000.0);

    SampleEditParams params = SampleDocument::defaultParams(source);
    params.cropStart = 100;
    params.cropEnd = 11500;
    params.targetRate = 13379.0;
    params.baseKey = 59;
    params.fineTuneCents = 10.0;
    params.ditherOn = true;
    SampleDocument first(source);
    SampleDocument second(source);
    first.setParams(params);
    second.setParams(params);
    const ProcessedSample &firstRender = first.processed();
    const ProcessedSample &secondRender = second.processed();
    QVERIFY(firstRender.s8 == secondRender.s8 && firstRender.freq == secondRender.freq &&
            firstRender.size == secondRender.size &&
            firstRender.loopStart == secondRender.loopStart &&
            firstRender.pitchFraction == secondRender.pitchFraction);

    SampleEditParams changed = params;
    changed.baseKey = 60;
    first.setParams(changed);
    first.processed();
    first.setParams(params);
    QCOMPARE(first.processed().s8, secondRender.s8);

    SampleDocument midLoop(source);
    midLoop.setParams(SampleDocument::defaultParams(source));
    QVERIFY(midLoop.processed().seam.valid);
    QVERIFY(midLoop.processed().seam.nccValid);
    SampleEditParams fromZero = SampleDocument::defaultParams(source);
    fromZero.loopStart = 0;
    SampleDocument zeroLoop(source);
    zeroLoop.setParams(fromZero);
    QVERIFY(zeroLoop.processed().seam.valid);
    QVERIFY(!zeroLoop.processed().seam.nccValid);
}

void SampleProcessingTest::parityCases_data()
{
    QTest::addColumn<int>("profile");
    QTest::addColumn<QString>("name");
    QTest::newRow("pm_a") << int(ParityProfile::A) << QStringLiteral("pm_a");
    QTest::newRow("pm_b") << int(ParityProfile::B) << QStringLiteral("pm_b");
    QTest::newRow("pm_c") << int(ParityProfile::C) << QStringLiteral("pm_c");
    QTest::newRow("pm_d") << int(ParityProfile::D) << QStringLiteral("pm_d");
    QTest::newRow("pm_e") << int(ParityProfile::E) << QStringLiteral("pm_e");
    QTest::newRow("pm_f") << int(ParityProfile::F) << QStringLiteral("pm_f");
}

void SampleProcessingTest::parityCases()
{
    QFETCH(int, profile);
    QFETCH(QString, name);
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "parity scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "parity synthetic wav2agb project is created");

    const ImportedHiRes imported = importHiRes();
    QVERIFY2(imported.ok, qPrintable(imported.error));
    const SampleEditParams params =
        parityParams(static_cast<ParityProfile>(profile), imported.sample.sampleRate,
                     SampleDocument::defaultParams(imported.sample));
    SampleDocument document(imported.sample);
    document.setParams(params);
    const ProcessedSample &render = document.processed();
    const QByteArray bytes = writeSampleWav(render);
    QString error;
    QVERIFY2(SampleRegistrar::registerSample(root, name, bytes, &error), qPrintable(error));

    SampleWavInfo info;
    QVERIFY2(SampleRegistrar::inspectSampleWav(bytes, &info, &error), qPrintable(error));
    QVERIFY(info.agbPitch == render.freq && info.agbLoopEnd == render.size &&
            info.numSamples == render.size && info.sampleRate == render.declaredRate &&
            info.midiKey == quint32(render.unityNote) &&
            info.pitchFraction == render.pitchFraction);
    QVERIFY(info.loopEnabled == render.looped &&
            (!render.looped ||
             (info.loopStart == render.loopStart && info.loopEndIncl == render.size - 1)));
    QVERIFY(info.waveFreq == render.freq && info.waveSize == render.size &&
            info.waveLoopStart == render.loopStart);
    const double fraction = double(info.pitchFraction) / 4294967296.0;
    const double exactKey = double(params.baseKey) + params.fineTuneCents / 100.0;
    QVERIFY(fraction >= 0.0 && fraction < 1.0 &&
            std::abs((double(info.midiKey) + fraction) - exactKey) < 1e-6);

    const QString voiceGroupText =
        QStringLiteral("voicegroup_parity::\n"
                       "\tvoice_directsound 60, 0, DirectSoundWaveData_%1, 255, 0, 255, 0\n")
            .arg(name);
    QVERIFY2(writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_parity.inc"),
                       voiceGroupText.toUtf8()),
             "parity voicegroup source is written");
    const QByteArray rootUtf8 = root.toLocal8Bit();
    const std::unique_ptr<LoadedVoiceGroup, decltype(&voicegroup_free)> voiceGroup{
        voicegroup_load(rootUtf8.constData(), "voicegroup_parity", nullptr), voicegroup_free};
    QVERIFY2(voiceGroup, "parity voicegroup resolves");
    const WaveData *wave = voiceGroup->voices[0].wav;
    QVERIFY2(wave && wave->data, "parity voice resolves sample bytes");
    QCOMPARE(wave->freq, render.freq);
    QCOMPARE(wave->loopStart, render.loopStart);
    QCOMPARE(wave->size, render.size);
    QCOMPARE(wave->status, render.looped ? 0x4000 : 0);
    QCOMPARE(QByteArrayView(reinterpret_cast<const char *>(wave->data), render.size),
             QByteArrayView(render.s8));
}

void SampleProcessingTest::parityLoopGeometry()
{
    const ImportedHiRes imported = importHiRes();
    QVERIFY2(imported.ok, qPrintable(imported.error));
    SampleDocument document(imported.sample);
    document.setParams(parityParams(ParityProfile::A, imported.sample.sampleRate,
                                    SampleDocument::defaultParams(imported.sample)));
    const ProcessedSample &render = document.processed();
    QVERIFY(render.looped);
    QCOMPARE(render.loopStart, quint32(607));
    QCOMPARE(render.size, quint32(3034));
    QCOMPARE(render.declaredRate, 13379.0);
}

void SampleProcessingTest::parityRiffPadding()
{
    const ImportedHiRes imported = importHiRes();
    QVERIFY2(imported.ok, qPrintable(imported.error));
    SampleDocument document(imported.sample);
    document.setParams(parityParams(ParityProfile::F, imported.sample.sampleRate,
                                    SampleDocument::defaultParams(imported.sample)));
    const ProcessedSample &render = document.processed();
    QCOMPARE(render.size, quint32(7281));

    const QByteArray bytes = writeSampleWav(render);
    const qsizetype dataAt = 12 + 8 + 16;
    QCOMPARE(bytes.mid(12, 4), QByteArray("fmt "));
    QCOMPARE(bytes.mid(dataAt, 4), QByteArray("data"));
    QCOMPARE(getU32(bytes, dataAt + 4), quint32(7281));
    QCOMPARE(bytes[dataAt + 8 + 7281], '\0');
    QCOMPARE(bytes.mid(dataAt + 8 + 7281 + 1, 4), QByteArray("smpl"));
    QCOMPARE(bytes.mid(dataAt + 8 + 7281 + 1 + 8 + 36, 4), QByteArray("agbp"));
    QCOMPARE(bytes.mid(dataAt + 8 + 7281 + 1 + 8 + 36 + 12, 4), QByteArray("agbl"));
}

void SampleProcessingTest::retuneVectors_data()
{
    QTest::addColumn<double>("rate");
    QTest::addColumn<int>("key");
    QTest::addColumn<double>("cents");
    QTest::addColumn<quint32>("agbp");
    QTest::newRow("c4-source-rate") << 13379.0 << 60 << 0.0 << quint32(13700096);
    QTest::newRow("c5-source-rate") << 13379.0 << 72 << 0.0 << quint32(6850048);
    QTest::newRow("a3-source-rate") << 13379.0 << 57 << 0.0 << quint32(16292252);
    QTest::newRow("a-sharp-plus-quarter") << 13379.0 << 58 << 25.0 << quint32(15157369);
    QTest::newRow("quarter-rate") << 3344.75 << 60 << 0.0 << quint32(3425024);
    QTest::newRow("a4-plus-half") << 44100.0 << 69 << 50.0 << quint32(26086940);
    QTest::newRow("half-rate") << 6689.5 << 60 << 0.0 << quint32(6850048);
}

void SampleProcessingTest::retuneVectors()
{
    QFETCH(double, rate);
    QFETCH(int, key);
    QFETCH(double, cents);
    QFETCH(quint32, agbp);

    FixtureSpec flat;
    flat.rate = 44100;
    flat.withSmpl = false;
    flat.samples = QByteArray(64, char(0x80));
    ImportedSample source;
    QString error;
    QVERIFY2(importAudioBytes(fixtureWav(flat), QStringLiteral("f/flat.wav"), &source, &error),
             qPrintable(error));

    SampleDocument doc(source);
    SampleEditParams params = doc.params();
    params.targetRate = rate;
    params.baseKey = key;
    params.fineTuneCents = cents;
    doc.setParams(params);
    QCOMPARE(doc.processed().freq, agbp);
}

} // namespace samplecheck
