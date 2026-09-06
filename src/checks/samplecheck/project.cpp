#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QTemporaryDir>
#include <QtTest>

#include <memory>

#include "project/samplereg.h"
#include "project/voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace samplecheck {
namespace {
constexpr auto kWav2AgbRules = "SOUND_BIN_DIR := $(OBJ_DIR)/sound\n"
                               "\n"
                               "$(SOUND_BIN_DIR)/%.bin: sound/%.wav \n"
                               "\t$(WAV2AGB) -b $< $@\n";
constexpr auto kIncSeed = "\t.align 2\n"
                          "DirectSoundWaveData_existing::\n"
                          "\t.incbin \"sound/direct_sound_samples/existing.bin\"\n";
constexpr auto kRegisteredSampleName = "samplecheck_tone";
} // namespace

bool createWav2AgbProject(const QString &root)
{
    return writeFile(root + QStringLiteral("/Makefile"), "include audio_rules.mk\n") &&
           writeFile(root + QStringLiteral("/audio_rules.mk"), kWav2AgbRules) &&
           writeFile(root + QStringLiteral("/sound/direct_sound_data.inc"), kIncSeed) &&
           writeFile(root + QStringLiteral("/sound/direct_sound_samples/existing.wav"),
                     "placeholder") &&
           writeFile(root + QStringLiteral("/sound/direct_sound_samples/orphan.wav"),
                     "placeholder");
}

QByteArray preparedSampleWav()
{
    auto spec = FixtureSpec{};
    for (int i = 0; i < 64; ++i)
        spec.samples += char(i * 2);
    spec.unityKey = 58;
    spec.pitchFraction = 0x40000000;
    spec.numLoops = 1;
    spec.loopStart = 8;
    spec.loopEndIncl = 47;
    spec.agbp = 15000000;
    spec.agbl = 64;
    return fixtureWav(spec);
}

QByteArray hiResSampleWav()
{
    auto spec = FixtureSpec{};
    spec.bits = 16;
    spec.rate = 44100;
    spec.numLoops = 1;
    spec.loopStart = 2000;
    spec.loopEndIncl = 9999;
    for (int i = 0; i < 12000; ++i) {
        const double value = 0.5 * std::sin(2.0 * 3.14159265358979323846 * 220.5 * i / 44100.0);
        putU16(&spec.samples, quint16(qint16(std::lround(value * 32000.0))));
    }
    return fixtureWav(spec);
}

void SampleProcessingTest::projectProbe()
{
    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "project-probe scratch directory is available");

    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "synthetic wav2agb project is created");
    const SampleFormatProbe probe = SampleRegistrar::probeSampleFormat(root);
    QVERIFY2(probe.ok() && probe.pipeline == SampleFormatProbe::Wav2Agb,
             "wav2agb project probes OK");

    const QString aifRoot = scratch.filePath(QStringLiteral("aifproj"));
    QVERIFY(writeFile(aifRoot + QStringLiteral("/audio_rules.mk"),
                      "$(SOUND_BIN_DIR)/%.bin: $(SAMPLE_SUBDIR)/%.aif\n\t$(AIF2PCM) $< $@\n"));
    QVERIFY(writeFile(aifRoot + QStringLiteral("/sound/direct_sound_data.inc"), kIncSeed));
    const SampleFormatProbe aif = SampleRegistrar::probeSampleFormat(aifRoot);
    QCOMPARE(aif.pipeline, SampleFormatProbe::LegacyAif);
    QVERIFY2(!aif.refusal.isEmpty(), "legacy AIFF project layout is refused");

    const QString noRuleRoot = scratch.filePath(QStringLiteral("noruleproj"));
    QVERIFY(writeFile(noRuleRoot + QStringLiteral("/sound/direct_sound_data.inc"), kIncSeed));
    QVERIFY2(!SampleRegistrar::probeSampleFormat(noRuleRoot).refusal.isEmpty(),
             "unsupported project layout is refused");

    const QString noIncRoot = scratch.filePath(QStringLiteral("noincproj"));
    QVERIFY(writeFile(noIncRoot + QStringLiteral("/audio_rules.mk"), kWav2AgbRules));
    QVERIFY2(!SampleRegistrar::probeSampleFormat(noIncRoot).refusal.isEmpty(),
             "unsupported project layout is refused");
}

void SampleProcessingTest::projectSanitizeValidate()
{
    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "project-sanitize scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "synthetic wav2agb project is created");

    QCOMPARE(SampleRegistrar::sanitizeSampleName(QStringLiteral("My Sample #2")),
             QStringLiteral("my_sample_2"));
    QCOMPARE(SampleRegistrar::sanitizeSampleName(QStringLiteral("Bell (C5)")),
             QStringLiteral("bell_c5"));

    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    auto error = QString{};
    QVERIFY(
        SampleRegistrar::validateSampleName(root, QStringLiteral("fresh_tone"), symbols, &error));
    QVERIFY(!SampleRegistrar::validateSampleName(root, {}, symbols, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
    QVERIFY(
        !SampleRegistrar::validateSampleName(root, QStringLiteral("Bad Name"), symbols, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
    QVERIFY(
        !SampleRegistrar::validateSampleName(root, QStringLiteral("existing"), symbols, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
    QVERIFY(!SampleRegistrar::validateSampleName(root, QStringLiteral("orphan"), symbols, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
}

void SampleProcessingTest::projectInspect()
{
    const QByteArray fixture = preparedSampleWav();
    auto error = QString{};
    auto info = SampleWavInfo{};
    QVERIFY(SampleRegistrar::inspectSampleWav(fixture, &info, &error));
    QVERIFY(info.formatTag == 1 && info.channels == 1 && info.bitsPerSample == 8 &&
            info.sampleRate == 13379 && info.numSamples == 64);
    QVERIFY(info.hasSmpl && info.midiKey == 58 && info.pitchFraction == 0x40000000 &&
            info.loopEnabled && info.loopStart == 8 && info.loopEndIncl == 47);
    QVERIFY(info.agbPitch == 15000000 && info.agbLoopEnd == 64);
    QVERIFY(info.waveFreq == 15000000 && info.waveLoopStart == 8 && info.waveSize == 64 &&
            info.waveLooped);

    QVERIFY(!SampleRegistrar::inspectSampleWav(QByteArray("not a wav"), nullptr, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");

    auto stereo = FixtureSpec{};
    stereo.samples = fixture.mid(44, 64);
    stereo.channels = 2;
    stereo.unityKey = 58;
    stereo.pitchFraction = 0x40000000;
    stereo.numLoops = 1;
    stereo.loopStart = 8;
    stereo.loopEndIncl = 47;
    stereo.agbp = 15000000;
    stereo.agbl = 64;
    QVERIFY(!SampleRegistrar::inspectSampleWav(fixtureWav(stereo), nullptr, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");

    auto twoLoops = FixtureSpec{};
    twoLoops.samples = fixture.mid(44, 64);
    twoLoops.numLoops = 2;
    twoLoops.loopStart = 8;
    twoLoops.loopEndIncl = 47;
    QVERIFY(!SampleRegistrar::inspectSampleWav(fixtureWav(twoLoops), nullptr, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");

    auto backward = twoLoops;
    backward.numLoops = 1;
    backward.loopType = 1;
    QVERIFY(!SampleRegistrar::inspectSampleWav(fixtureWav(backward), nullptr, &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");

    auto bare = FixtureSpec{};
    bare.samples = fixture.mid(44, 64);
    bare.numLoops = 1;
    bare.loopStart = 8;
    bare.loopEndIncl = 47;
    auto bareInfo = SampleWavInfo{};
    QVERIFY(SampleRegistrar::inspectSampleWav(fixtureWav(bare), &bareInfo, &error));
    QVERIFY(bareInfo.waveSize == 48 && bareInfo.waveFreq != 0 && bareInfo.agbPitch == 0);
}

void SampleProcessingTest::projectRegister()
{
    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "project-register scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "synthetic wav2agb project is created");

    const QByteArray fixture = preparedSampleWav();
    auto error = QString{};
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    QVERIFY(SampleRegistrar::registerSample(root, QLatin1String(kRegisteredSampleName), fixture,
                                            &error));
    QCOMPARE(
        readFileBytes(root + QStringLiteral("/sound/direct_sound_samples/samplecheck_tone.wav")),
        fixture);
    const QByteArray expectedInc =
        QByteArray(kIncSeed) + "\n\t.align 2\n"
                               "DirectSoundWaveData_samplecheck_tone::\n"
                               "\t.incbin \"sound/direct_sound_samples/samplecheck_tone.bin\"\n";
    QCOMPARE(readFileBytes(incPath), expectedInc);
    const QStringList registeredSymbols = VoicegroupSource::directSoundSymbols(root);
    QVERIFY(registeredSymbols.contains(QStringLiteral("DirectSoundWaveData_samplecheck_tone")) &&
            registeredSymbols.contains(QStringLiteral("DirectSoundWaveData_existing")));

    QVERIFY(writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_samplecheck.inc"),
                      "voicegroup_samplecheck::\n\tvoice_directsound 60, 0, "
                      "DirectSoundWaveData_samplecheck_tone, 255, 165, 90, 178\n"));
    const QByteArray rootUtf8 = root.toLocal8Bit();
    auto voicegroup = std::unique_ptr<LoadedVoiceGroup, decltype(&voicegroup_free)>{
        voicegroup_load(rootUtf8.constData(), "voicegroup_samplecheck", nullptr), voicegroup_free};
    QVERIFY2(voicegroup, "registered sample resolves through the production voicegroup loader");
    const ToneData &tone = voicegroup->voices[0];
    QVERIFY(tone.type == 0 && tone.key == 60 && tone.attack == 255 && tone.decay == 165 &&
            tone.sustain == 90 && tone.release == 178);
    QVERIFY(tone.wav && tone.wav->freq == 15000000 && tone.wav->loopStart == 8 &&
            tone.wav->size == 64 && tone.wav->status == 0x4000 && tone.wav->data);
    for (int i = 0; i < 64; ++i)
        QCOMPARE(tone.wav->data[i], qint8(i * 2 - 128));
    QCOMPARE(QByteArray(voicegroup->voiceNames[0]), QByteArray("samplecheck_tone"));
}

void SampleProcessingTest::projectDuplicate()
{
    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "project-duplicate scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "synthetic wav2agb project is created");

    const QByteArray fixture = preparedSampleWav();
    auto error = QString{};
    QVERIFY(SampleRegistrar::registerSample(root, QLatin1String(kRegisteredSampleName), fixture,
                                            &error));
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    const QByteArray incBeforeDuplicate = readFileBytes(incPath);
    QVERIFY(!SampleRegistrar::registerSample(root, QLatin1String(kRegisteredSampleName), fixture,
                                             &error));
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
    QCOMPARE(readFileBytes(incPath), incBeforeDuplicate);
}

void SampleProcessingTest::projectCrlf()
{
    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "project-crlf scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("crlfproj"));
    const QByteArray fixture = preparedSampleWav();
    const QByteArray crlfSeed = "\t.align 2\r\nDirectSoundWaveData_existing::\r\n"
                                "\t.incbin \"sound/direct_sound_samples/existing.bin\"\r\n";
    QVERIFY(writeFile(root + QStringLiteral("/audio_rules.mk"), kWav2AgbRules));
    QVERIFY(writeFile(root + QStringLiteral("/sound/direct_sound_data.inc"), crlfSeed));
    auto error = QString{};
    QVERIFY(SampleRegistrar::registerSample(root, QStringLiteral("crlf_tone"), fixture, &error));
    const QByteArray grown = readFileBytes(root + QStringLiteral("/sound/direct_sound_data.inc"));
    QCOMPARE(grown,
             crlfSeed + QByteArray("\r\n\t.align 2\r\nDirectSoundWaveData_crlf_tone::\r\n"
                                   "\t.incbin \"sound/direct_sound_samples/crlf_tone.bin\"\r\n"));
    for (qsizetype i = 0; i < grown.size(); ++i)
        QVERIFY(grown[i] != '\n' || (i > 0 && grown[i - 1] == '\r'));
}

} // namespace samplecheck
