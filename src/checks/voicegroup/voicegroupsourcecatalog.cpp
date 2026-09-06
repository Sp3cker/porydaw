#include "checks/voicegroup/tst_voicegroupsource.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include "checks/support/songfixture.h"
#include "checks/voicegroup/voicegrouptestfixture.h"

namespace {

bool allLfAreCrLf(const QByteArray &contents)
{
    for (qsizetype index = 0; index < contents.size(); ++index) {
        if (contents[index] == '\n' && (index == 0 || contents[index - 1] != '\r'))
            return false;
    }
    return true;
}

QByteArray sampleBinary(char sample)
{
    QByteArray binary(16, '\0');
    binary[12] = 4;
    binary += QByteArray(4, sample);
    return binary;
}

} // namespace

void VoicegroupSourceTest::typicalAdsrSyntheticScan()
{
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    QVERIFY(QDir().mkpath(temporary.filePath(QStringLiteral("sound/voicegroups"))));
    QString error;
    const QByteArray source =
        QByteArrayLiteral("voicegroup_adsrcheck::\n"
                          "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0\n"
                          "\tvoice_square_1 60, 0, 0, 2, 1, 2, 10, 3\n"
                          "\tvoice_square_1 60, 0, 0, 2, 1, 2, 10, 3\n"
                          "\tvoice_square_1 60, 0, 0, 2, 2, 0, 12, 1\n"
                          "\tvoice_square_2 60, 0, 2, 9, 2, 20, 11\n"
                          "\tvoice_directsound 60, 0, AdsrCheckA, 255, 0, 255, 165\n"
                          "\tvoice_directsound_no_resample 60, 0, AdsrCheckA, 255, 0, 255, 165\n"
                          "\tvoice_directsound 60, 0, AdsrCheckA, 200, 100, 128, 216\n"
                          "\tvoice_directsound 60, 0, AdsrCheckB, 0, 0, 255, 165\n"
                          "\tvoice_noise 60, 0, 0, 1, 0, 13, 2\n");
    QVERIFY2(
        voicegroup_test::writeFile(
            temporary.filePath(QStringLiteral("sound/voicegroups/adsrcheck.inc")), source, error),
        qPrintable(error));

    const VgAdsrDefaults defaults = VoicegroupSource::typicalAdsr(temporary.path());
    const auto verify = [&defaults](VgMacro macro, const VgAdsr &expected) {
        const int family = vgAdsrFamily(macro);
        QVERIFY(defaults.byFamily.contains(family));
        QCOMPARE(defaults.byFamily.value(family), expected);
    };
    verify(VgMacro::Square1, {1, 2, 10, 3});
    verify(VgMacro::Square2Alt, {1, 2, 4, 3});
    verify(VgMacro::DirectSoundNoResample, {255, 0, 255, 165});
    verify(VgMacro::Noise, {1, 0, 13, 2});
    QVERIFY(defaults.bySymbol.contains(QStringLiteral("AdsrCheckA")));
    QCOMPARE(defaults.bySymbol.value(QStringLiteral("AdsrCheckA")), (VgAdsr{255, 0, 255, 165}));
    QVERIFY(!defaults.bySymbol.contains(QStringLiteral("AdsrCheckB")));
    QCOMPARE(vgDefaultAdsr(defaults, VgMacro::DirectSound, QStringLiteral("AdsrCheckA")),
             (VgAdsr{255, 0, 255, 165}));
    QCOMPARE(vgDefaultAdsr(defaults, VgMacro::Square1Alt, {}), (VgAdsr{1, 2, 10, 3}));
    QCOMPARE(vgDefaultAdsr(defaults, VgMacro::ProgWave, QStringLiteral("missing")),
             (VgAdsr{0, 0, 15, 3}));
    QCOMPARE(vgDefaultAdsr(VgAdsrDefaults{}, VgMacro::DirectSound, {}), (VgAdsr{255, 0, 255, 165}));
}

void VoicegroupSourceTest::typicalAdsrFixtureSuggestionsAreAudible()
{
    QVERIFY(m_session);
    const VgAdsrDefaults defaults = VoicegroupSource::typicalAdsr(m_session->root());
    QVERIFY2(!defaults.byFamily.isEmpty(),
             "fixture project must contain audible ADSR family defaults");
    for (auto it = defaults.byFamily.cbegin(); it != defaults.byFamily.cend(); ++it) {
        const bool cgb = it.key() != vgAdsrFamily(VgMacro::DirectSound);
        const VgAdsr &adsr = it.value();
        const int maximum = cgb ? 7 : 255;
        QVERIFY(adsr.release > 0 && adsr.release <= maximum);
        QVERIFY(adsr.attack >= 0 && adsr.attack <= maximum);
        QVERIFY(adsr.decay >= 0 && adsr.decay <= maximum);
        QVERIFY(adsr.sustain >= 0 && adsr.sustain <= (cgb ? 15 : 255));
        QVERIFY(cgb || adsr.attack > 0);
    }
    QVERIFY2(!defaults.bySymbol.isEmpty(),
             "fixture project must contain audible per-symbol ADSR defaults");
    for (auto it = defaults.bySymbol.cbegin(); it != defaults.bySymbol.cend(); ++it) {
        const VgAdsr &adsr = it.value();
        QVERIFY(adsr.release > 0 && adsr.release <= 255);
        QVERIFY(adsr.attack >= 0 && adsr.attack <= 255);
        QVERIFY(adsr.decay >= 0 && adsr.decay <= 255);
        QVERIFY(adsr.sustain >= 0 && adsr.sustain <= 255);
    }
}

void VoicegroupSourceTest::synthCatalogWriteAndGates()
{
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    QString root = temporary.path();
    QVERIFY(QDir().mkpath(root + QStringLiteral("/sound")));
    QVERIFY(QDir().mkpath(root + QStringLiteral("/asm/macros")));
    QVERIFY(QDir().mkpath(root + QStringLiteral("/data")));
    QString error;
    QVERIFY2(
        voicegroup_test::writeFile(
            root + QStringLiteral("/asm/macros/music_voice.inc"),
            QByteArrayLiteral("\t.macro set_synth_pulse a=0, b=0, c=0, d=0\n\t.endm\n"
                              "\t.macro set_synth_saw\n\t.endm\n"
                              "\t.macro set_synth_triangle\n\t.endm\n"
                              "\t.macro set_synth_custom a:req, b:req, c:req, d:req\n\t.endm\n"),
            error),
        qPrintable(error));
    QVERIFY2(voicegroup_test::writeFile(
                 root + QStringLiteral("/sound/direct_sound_data.inc"),
                 QByteArrayLiteral("DirectSoundWaveData_synthcheck_sample::\n"
                                   "\t.incbin \"sound/direct_sound_samples/sample.bin\"\n\n"
                                   "SynthCheckInline:: @ Golden Sun pulse\n"
                                   "\tset_synth_custom 0x10, 0xF0, 0xE0, 0x80\n"),
                 error),
             qPrintable(error));
    QString synthPath = root + QStringLiteral("/sound/direct_sound_synth_data.inc");
    QVERIFY2(voicegroup_test::writeFile(synthPath,
                                        QByteArrayLiteral("\t.align 2\r\nSynthCheckSaw::\r\n"
                                                          "    set_synth_25\r\n"),
                                        error),
             qPrintable(error));
    QString soundData = root + QStringLiteral("/data/sound_data.s");
    QVERIFY2(voicegroup_test::writeFile(
                 soundData,
                 QByteArrayLiteral("\t.include \"sound/direct_sound_data.inc\"\n"
                                   "\t.include \"sound/music_player_table.inc\"\n"),
                 error),
             qPrintable(error));
    const auto fixture = voicegroup_test::copyProject(root, error);
    QVERIFY2(fixture, qPrintable(error));
    root = fixture->root();
    synthPath = root + QStringLiteral("/sound/direct_sound_synth_data.inc");
    soundData = root + QStringLiteral("/data/sound_data.s");

    const VgSynthCatalog catalog = VoicegroupSource::synthInstruments(root);
    QCOMPARE(catalog.defs.size(), 2);
    QCOMPARE(*catalog.find(QStringLiteral("SynthCheckInline")),
             (VgSynthDesc{0, 0x10, 0xF0, 0xE0, 0x80}));
    QVERIFY(catalog.find(QStringLiteral("SynthCheckSaw")));
    QCOMPARE(catalog.find(QStringLiteral("SynthCheckSaw"))->waveform, 1);
    QCOMPARE(catalog.macroWords.size(), 4);
    QVERIFY(catalog.creatable());
    const QStringList samples = VoicegroupSource::directSoundSymbols(root);
    QVERIFY(samples.contains(QStringLiteral("DirectSoundWaveData_synthcheck_sample")));
    QVERIFY(!samples.contains(QStringLiteral("SynthCheckInline")));
    QCOMPARE(vgSynthSymbolName({0, 0x40, 2, 3, 4}),
             QStringLiteral("DirectSoundSynth_GoldenSun_40020304"));
    QCOMPARE(vgSynthSymbolName({1, 0, 0, 0, 0}), QStringLiteral("DirectSoundSynth_GoldenSun_Saw"));
    QCOMPARE(vgSynthSymbolName({2, 0, 0, 0, 0}),
             QStringLiteral("DirectSoundSynth_GoldenSun_Triangle"));
    QCOMPARE(catalog.symbolFor({0, 0x10, 0xF0, 0xE0, 0x80}), QStringLiteral("SynthCheckInline"));
    QCOMPARE(catalog.symbolFor({1, 0, 0, 0, 0}), QStringLiteral("SynthCheckSaw"));

    const VgSynthDesc pulse{0, 0x40, 2, 3, 4};
    const QList<QPair<QString, VgSynthDesc>> newDefs = {
        {vgSynthSymbolName(pulse), pulse},
        {vgSynthSymbolName({2, 0, 0, 0, 0}), {2, 0, 0, 0, 0}},
    };
    QVERIFY2(VoicegroupSource::writeSynthDefinitions(root, newDefs, &error), qPrintable(error));
    const QByteArray grown = voicegroup_test::readFile(synthPath);
    const QByteArray wired = voicegroup_test::readFile(soundData);
    QCOMPARE(wired, QByteArrayLiteral("\t.include \"sound/direct_sound_data.inc\"\n"
                                      "\t.include \"sound/direct_sound_synth_data.inc\"\n"
                                      "\t.include \"sound/music_player_table.inc\"\n"));
    QVERIFY(allLfAreCrLf(grown));
    const VgSynthCatalog saved = VoicegroupSource::synthInstruments(root);
    QCOMPARE(*saved.find(vgSynthSymbolName(pulse)), pulse);
    QVERIFY(saved.find(QStringLiteral("DirectSoundSynth_GoldenSun_Triangle")));
    QVERIFY2(VoicegroupSource::writeSynthDefinitions(root, newDefs, &error), qPrintable(error));
    QCOMPARE(voicegroup_test::readFile(synthPath), grown);
    QCOMPARE(voicegroup_test::readFile(soundData), wired);
    QCOMPARE(wired.count("direct_sound_synth_data.inc"), 1);
    error.clear();
    QVERIFY(!VoicegroupSource::writeSynthDefinitions(
        root, {{QStringLiteral("SynthCheckSaw"), {0, 9, 9, 9, 9}}}, &error));
    QVERIFY(!error.isEmpty());
    QCOMPARE(voicegroup_test::readFile(synthPath), grown);

    QTemporaryDir bare;
    QVERIFY(bare.isValid());
    QVERIFY(QDir().mkpath(bare.filePath(QStringLiteral("sound"))));
    QVERIFY2(voicegroup_test::writeFile(
                 bare.filePath(QStringLiteral("sound/direct_sound_synth_data.inc")),
                 QByteArrayLiteral("SynthCheckSaw::\n\tset_synth_saw\n"), error),
             qPrintable(error));
    const auto bareFixture = voicegroup_test::copyProject(bare.path(), error);
    QVERIFY2(bareFixture, qPrintable(error));
    const QString bareRoot = bareFixture->root();
    const VgSynthCatalog bareCatalog = VoicegroupSource::synthInstruments(bareRoot);
    QVERIFY(!bareCatalog.creatable());
    QCOMPARE(bareCatalog.symbolFor({1, 0, 0, 0, 0}), QStringLiteral("SynthCheckSaw"));
    error.clear();
    QVERIFY(!VoicegroupSource::writeSynthDefinitions(
        bareRoot, {{QStringLiteral("DirectSoundSynth_GoldenSun_09090909"), {0, 9, 9, 9, 9}}},
        &error));
    QVERIFY(!error.isEmpty());

    QTemporaryDir unwired;
    QVERIFY(unwired.isValid());
    QVERIFY(QDir().mkpath(unwired.filePath(QStringLiteral("sound"))));
    QVERIFY(QDir().mkpath(unwired.filePath(QStringLiteral("asm/macros"))));
    QVERIFY2(voicegroup_test::writeFile(
                 unwired.filePath(QStringLiteral("asm/macros/music_voice.inc")),
                 QByteArrayLiteral("\t.macro set_synth_pulse a=0, b=0, c=0, d=0\n\t.endm\n"),
                 error),
             qPrintable(error));
    const auto unwiredFixture = voicegroup_test::copyProject(unwired.path(), error);
    QVERIFY2(unwiredFixture, qPrintable(error));
    const QString unwiredRoot = unwiredFixture->root();
    error.clear();
    QVERIFY(!VoicegroupSource::writeSynthDefinitions(
        unwiredRoot, {{QStringLiteral("DirectSoundSynth_GoldenSun_09090909"), {0, 9, 9, 9, 9}}},
        &error));
    QVERIFY(error.contains(QStringLiteral("direct_sound_synth_data.inc")));
}

void VoicegroupSourceTest::singleColonSymbolsScanAndLoad()
{
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    const QString root = temporary.path();
    QVERIFY(QDir().mkpath(root + QStringLiteral("/sound/direct_sound_samples")));
    QVERIFY(QDir().mkpath(root + QStringLiteral("/sound/programmable_wave_samples")));
    QVERIFY(QDir().mkpath(root + QStringLiteral("/sound/voicegroups")));
    QString error;
    QVERIFY(voicegroup_test::writeFile(
        root + QStringLiteral("/sound/direct_sound_samples/colon_single.bin"), sampleBinary('\x11'),
        error));
    QVERIFY(voicegroup_test::writeFile(
        root + QStringLiteral("/sound/direct_sound_samples/colon_double.bin"), sampleBinary('\x22'),
        error));
    QVERIFY(voicegroup_test::writeFile(
        root + QStringLiteral("/sound/programmable_wave_samples/colon_wave.pcm"),
        QByteArray(16, '\x33'), error));
    QVERIFY(voicegroup_test::writeFile(
        root + QStringLiteral("/sound/direct_sound_data.inc"),
        QByteArrayLiteral(
            "DirectSoundWaveData_colon_double::\n\t.incbin "
            "\"sound/direct_sound_samples/"
            "colon_double.bin\"\nDirectSoundWaveData_colon_single:\n\t.incbin "
            "\"sound/direct_sound_samples/colon_single.bin\"\nColonCheckSynth:\n\tset_synth_25\n"),
        error));
    QVERIFY(voicegroup_test::writeFile(
        root + QStringLiteral("/sound/programmable_wave_data.inc"),
        QByteArrayLiteral("ProgrammableWaveData_colon_wave:\n\t.incbin "
                          "\"sound/programmable_wave_samples/colon_wave.pcm\"\n"),
        error));
    QVERIFY(voicegroup_test::writeFile(
        root + QStringLiteral("/sound/voicegroups/coloncheck.inc"),
        QByteArrayLiteral(
            "voicegroup_coloncheck::\n\tvoice_directsound 60, 0, DirectSoundWaveData_colon_single, "
            "255, 0, 255, 165\n\tvoice_directsound 60, 0, DirectSoundWaveData_colon_double, 255, "
            "0, 255, 165\n\tvoice_programmable_wave 60, 0, ProgrammableWaveData_colon_wave, 0, 0, "
            "15, 3\n"),
        error));

    const VgDirectSoundScan scan = VoicegroupSource::directSoundCatalog(root);
    QVERIFY(scan.directSound.contains(QStringLiteral("DirectSoundWaveData_colon_single")));
    QVERIFY(scan.directSound.contains(QStringLiteral("DirectSoundWaveData_colon_double")));
    QVERIFY(!scan.directSound.contains(QStringLiteral("ColonCheckSynth")));
    QVERIFY(scan.synths.find(QStringLiteral("ColonCheckSynth")));
    QVERIFY(VoicegroupSource::progWaveSymbols(root).contains(
        QStringLiteral("ProgrammableWaveData_colon_wave")));
    const QByteArray rootUtf8 = root.toUtf8();
    LoadedVoiceGroup *const loaded = voicegroup_load(rootUtf8.constData(), "coloncheck", nullptr);
    QVERIFY(loaded);
    QVERIFY(loaded->voices[0].wav);
    QCOMPARE(loaded->voices[0].wav->size, size_t(4));
    QCOMPARE(loaded->voices[0].wav->data[0], uint8_t(0x11));
    QVERIFY(loaded->voices[1].wav);
    QCOMPARE(loaded->voices[1].wav->data[0], uint8_t(0x22));
    QVERIFY(loaded->voices[2].wavePointer);
    voicegroup_free(loaded);
}

void VoicegroupSourceTest::synthDescriptorLoadsThroughVoicegroup()
{
    QVERIFY(m_session);
    VoicegroupSource &source = m_session->source;
    int slot = -1;
    for (int index = 0; index < VOICEGROUP_SIZE; ++index) {
        const VgVoice *const voice = source.voiceAt(index);
        if (voice && voicegroup_test::isDirectSound(voice->macro)) {
            slot = index;
            break;
        }
    }
    QVERIFY2(slot >= 0, "fixture_rich must retain a DirectSound slot");
    const QString synthData =
        m_session->root() + QStringLiteral("/sound/direct_sound_synth_data.inc");
    const QByteArray original = voicegroup_test::readFile(synthData);
    QString error;
    QVERIFY2(voicegroup_test::writeFile(
                 synthData,
                 original + QByteArrayLiteral("\nVgcheckSynthPulse::\n"
                                              "\tset_synth_pulse 0x21, 0x43, 0x65, 0x87\n"),
                 error),
             qPrintable(error));
    VgVoice voice = *source.voiceAt(slot);
    voice.symbol = QStringLiteral("VgcheckSynthPulse");
    QVERIFY(source.setVoice(slot, voice));
    QVERIFY2(source.save(&error), qPrintable(error));
    const QByteArray root = m_session->rootUtf8();
    const QByteArray name = m_session->loadNameUtf8();
    LoadedVoiceGroup *const loaded = voicegroup_load(root.constData(), name.constData(), nullptr);
    QVERIFY(loaded);
    const ToneData &tone = loaded->voices[slot];
    const auto *descriptor = tone.wav ? reinterpret_cast<const uint8_t *>(tone.wav->data) : nullptr;
    QVERIFY((tone.type & ~uint8_t(0x18)) == 0);
    QVERIFY(tone.wav);
    QCOMPARE(tone.wav->size, size_t(0));
    QVERIFY(descriptor);
    QCOMPARE(descriptor[1], uint8_t(0));
    QCOMPARE(descriptor[2], uint8_t(0x21));
    QCOMPARE(descriptor[3], uint8_t(0x43));
    QCOMPARE(descriptor[4], uint8_t(0x65));
    QCOMPARE(descriptor[5], uint8_t(0x87));
    voicegroup_free(loaded);
}

int runVgCheck(const QString &projectRoot, const QString &songLabel, const QStringList &qtArguments)
{
    VoicegroupSourceTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("voicegroup-source")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
