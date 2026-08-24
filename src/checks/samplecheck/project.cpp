#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <cstdio>

#include "project/samplereg.h"
#include "project/voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace samplecheck {
namespace {
const char *const kWav2AgbRules = "SOUND_BIN_DIR := $(OBJ_DIR)/sound\n"
                                  "\n"
                                  "$(SOUND_BIN_DIR)/%.bin: sound/%.wav \n"
                                  "\t$(WAV2AGB) -b $< $@\n";

// One registered entry, LF endings — the shipped pokeemerald layout.
const char *const kIncSeed = "\t.align 2\n"
                             "DirectSoundWaveData_existing::\n"
                             "\t.incbin \"sound/direct_sound_samples/existing.bin\"\n";
} // namespace

std::optional<RegisteredSampleProject>
prepareRegisteredSampleProject(Reporter &reporter, const QString &root, const QString &scratchDir)
{
    if (!(writeFile(root + QStringLiteral("/Makefile"), "include audio_rules.mk\n") &&
          writeFile(root + QStringLiteral("/audio_rules.mk"), kWav2AgbRules) &&
          writeFile(root + QStringLiteral("/sound/direct_sound_data.inc"), kIncSeed) &&
          writeFile(root + QStringLiteral("/sound/direct_sound_samples/existing.wav"),
                    "placeholder") &&
          writeFile(root + QStringLiteral("/sound/direct_sound_samples/orphan.wav"),
                    "placeholder"))) {
        std::fprintf(stderr, "samplecheck: cannot build fake project\n");
        return std::nullopt;
    }

    // ---- probe: the wav2agb project registers, the broken ones refuse ----
    {
        const int before = reporter.failureCount();
        const SampleFormatProbe probe = SampleRegistrar::probeSampleFormat(root);
        reporter.expect(probe.ok() && probe.pipeline == SampleFormatProbe::Wav2Agb,
                        "wav2agb project probes OK");

        const QString aifRoot = scratchDir + QStringLiteral("/aifproj");
        writeFile(aifRoot + QStringLiteral("/audio_rules.mk"),
                  "$(SOUND_BIN_DIR)/%.bin: $(SAMPLE_SUBDIR)/%.aif\n"
                  "\t$(AIF2PCM) $< $@\n");
        writeFile(aifRoot + QStringLiteral("/sound/direct_sound_data.inc"), kIncSeed);
        const SampleFormatProbe aif = SampleRegistrar::probeSampleFormat(aifRoot);
        reporter.expect(aif.pipeline == SampleFormatProbe::LegacyAif,
                        "aif project detected as legacy");
        reporter.expectError(aif.refusal,
                             QStringLiteral("this project predates wav2agb: its samples build from "
                                            ".aif sources via aif2pcm. Port the sample pipeline to "
                                            "wav2agb (pret's current layout), then import again."),
                             "legacy-aif refusal text");

        const QString noRuleRoot = scratchDir + QStringLiteral("/noruleproj");
        writeFile(noRuleRoot + QStringLiteral("/sound/direct_sound_data.inc"), kIncSeed);
        reporter.expectError(SampleRegistrar::probeSampleFormat(noRuleRoot).refusal,
                             QStringLiteral("cannot find a wav2agb build rule (%.bin: %.wav) in "
                                            "the project's make files; add pret's audio_rules.mk "
                                            "pattern rule, then import again."),
                             "missing-rule refusal text");

        const QString noIncRoot = scratchDir + QStringLiteral("/noincproj");
        writeFile(noIncRoot + QStringLiteral("/audio_rules.mk"), kWav2AgbRules);
        reporter.expectError(SampleRegistrar::probeSampleFormat(noIncRoot).refusal,
                             QStringLiteral("cannot find sound/direct_sound_data.inc — samples are "
                                            "registered there. Set up pret's sample layout, then "
                                            "import again."),
                             "missing-inc refusal text");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: pipeline probe OK\n");
    }

    // ---- name sanitizing/validation ----
    {
        const int before = reporter.failureCount();
        reporter.expect(SampleRegistrar::sanitizeSampleName(QStringLiteral("My Sample #2")) ==
                            QStringLiteral("my_sample_2"),
                        "sanitize collapses separators");
        reporter.expect(SampleRegistrar::sanitizeSampleName(QStringLiteral("Bell (C5)")) ==
                            QStringLiteral("bell_c5"),
                        "sanitize trims trailing junk");
        const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
        QString error;
        reporter.expect(SampleRegistrar::validateSampleName(root, QStringLiteral("fresh_tone"),
                                                            symbols, &error),
                        "fresh name validates");
        reporter.expect(!SampleRegistrar::validateSampleName(root, QString(), symbols, &error),
                        "empty name refused");
        reporter.expectError(error, QStringLiteral("sample name is empty."), "empty-name text");
        reporter.expect(
            !SampleRegistrar::validateSampleName(root, QStringLiteral("Bad Name"), symbols, &error),
            "bad grammar refused");
        reporter.expectError(error,
                             QStringLiteral("sample names use lowercase letters, "
                                            "digits, and underscores only."),
                             "grammar text");
        reporter.expect(
            !SampleRegistrar::validateSampleName(root, QStringLiteral("existing"), symbols, &error),
            "symbol collision refused");
        reporter.expectError(
            error, QStringLiteral("DirectSoundWaveData_existing already exists in this project."),
            "symbol-collision text");
        reporter.expect(
            !SampleRegistrar::validateSampleName(root, QStringLiteral("orphan"), symbols, &error),
            "on-disk file collision refused");
        reporter.expectError(error,
                             QStringLiteral("orphan.wav already exists in "
                                            "sound/direct_sound_samples."),
                             "file-collision text");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: name validation OK\n");
    }

    // ---- fixture inspection ----
    FixtureSpec spec;
    for (int i = 0; i < 64; i++)
        spec.samples += char(i * 2); // u8 ramp 0..126
    spec.unityKey = 58;
    spec.pitchFraction = 0x40000000; // 0.25 semitone, standard semantics
    spec.numLoops = 1;
    spec.loopStart = 8;
    spec.loopEndIncl = 47;
    spec.agbp = 15000000;
    spec.agbl = 64;
    const QByteArray fixture = fixtureWav(spec);
    const QString registeredSampleName = QStringLiteral("samplecheck_tone");
    bool sampleRegistered = false;
    {
        const int before = reporter.failureCount();
        SampleWavInfo info;
        QString error;
        reporter.expect(SampleRegistrar::inspectSampleWav(fixture, &info, &error),
                        "fixture inspects OK");
        reporter.expect(info.formatTag == 1 && info.channels == 1 && info.bitsPerSample == 8 &&
                            info.sampleRate == 13379 && info.numSamples == 64,
                        "fmt/data fields");
        reporter.expect(info.hasSmpl && info.midiKey == 58 && info.pitchFraction == 0x40000000 &&
                            info.loopEnabled && info.loopStart == 8 && info.loopEndIncl == 47,
                        "smpl fields");
        reporter.expect(info.agbPitch == 15000000 && info.agbLoopEnd == 64, "agbp/agbl fields");
        // The derived WaveData header: agbp verbatim, agbl overriding size.
        reporter.expect(info.waveFreq == 15000000 && info.waveLoopStart == 8 &&
                            info.waveSize == 64 && info.waveLooped,
                        "derived WaveData projection");

        reporter.expect(
            !SampleRegistrar::inspectSampleWav(QByteArray("not a wav"), nullptr, &error),
            "garbage refused");
        reporter.expectError(error, QStringLiteral("not a RIFF/WAVE file."), "garbage text");
        FixtureSpec stereo = spec;
        stereo.channels = 2;
        reporter.expect(!SampleRegistrar::inspectSampleWav(fixtureWav(stereo), nullptr, &error),
                        "stereo refused");
        reporter.expectError(
            error, QStringLiteral("only mono samples are supported (this file has 2 channels)."),
            "stereo text");
        FixtureSpec twoLoops = spec;
        twoLoops.numLoops = 2;
        reporter.expect(!SampleRegistrar::inspectSampleWav(fixtureWav(twoLoops), nullptr, &error),
                        "multi-loop refused");
        reporter.expectError(error,
                             QStringLiteral("the smpl chunk declares 2 loops; wav2agb "
                                            "supports at most one."),
                             "multi-loop text");
        FixtureSpec backward = spec;
        backward.loopType = 1;
        reporter.expect(!SampleRegistrar::inspectSampleWav(fixtureWav(backward), nullptr, &error),
                        "non-forward loop refused");
        reporter.expectError(error,
                             QStringLiteral("the smpl loop is not a forward loop (type "
                                            "1); wav2agb only supports forward loops."),
                             "loop-type text");
        // No agbp/agbl: freq falls back to the loader's smpl-derived math and
        // size to the smpl loop end.
        FixtureSpec bare = spec;
        bare.agbp = 0;
        bare.agbl = 0;
        SampleWavInfo bareInfo;
        reporter.expect(SampleRegistrar::inspectSampleWav(fixtureWav(bare), &bareInfo, &error) &&
                            bareInfo.waveSize == 48 && bareInfo.waveFreq != 0 &&
                            bareInfo.agbPitch == 0,
                        "smpl-only fallback projection");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: wav inspection OK\n");
    }

    // ---- register + .inc bytes + loader resolution ----
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    {
        const int before = reporter.failureCount();
        QString error;
        sampleRegistered =
            SampleRegistrar::registerSample(root, registeredSampleName, fixture, &error);
        reporter.expect(sampleRegistered, "registerSample succeeds");
        reporter.expect(readFileBytes(root + QStringLiteral("/sound/direct_sound_samples/"
                                                            "samplecheck_tone.wav")) == fixture,
                        "sample .wav copied verbatim");
        const QByteArray expectedInc =
            QByteArray(kIncSeed) +
            "\n"
            "\t.align 2\n"
            "DirectSoundWaveData_samplecheck_tone::\n"
            "\t.incbin \"sound/direct_sound_samples/samplecheck_tone.bin\"\n";
        reporter.expect(readFileBytes(incPath) == expectedInc,
                        ".inc gains exactly the registration block");

        const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
        reporter.expect(symbols.contains(QStringLiteral("DirectSoundWaveData_samplecheck_tone")) &&
                            symbols.contains(QStringLiteral("DirectSoundWaveData_existing")),
                        "directSoundSymbols sees the new symbol");

        // A voicegroup referencing the symbol resolves through the C loader,
        // .wav-first, with the WaveData header the inspector predicted.
        writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_samplecheck.inc"),
                  "voicegroup_samplecheck::\n"
                  "\tvoice_directsound 60, 0, "
                  "DirectSoundWaveData_samplecheck_tone, 255, 165, 90, 178\n");
        const QByteArray rootUtf8 = root.toLocal8Bit();
        LoadedVoiceGroup *vg =
            voicegroup_load(rootUtf8.constData(), "voicegroup_samplecheck", nullptr);
        if (!vg) {
            std::fprintf(stderr, "samplecheck: FAIL: voicegroup_load failed\n");
            reporter.noteFailure();
        } else {
            const ToneData &td = vg->voices[0];
            reporter.expect(td.type == 0 && td.key == 60 && td.attack == 255 && td.decay == 165 &&
                                td.sustain == 90 && td.release == 178,
                            "loaded voice scalars");
            reporter.expect(td.wav && td.wav->freq == 15000000 && td.wav->loopStart == 8 &&
                                td.wav->size == 64 && td.wav->status == 0x4000,
                            "loaded WaveData header matches the inspection");
            bool dataOk = td.wav && td.wav->data;
            for (int i = 0; dataOk && i < 64; i++)
                dataOk = td.wav->data[i] == qint8(i * 2 - 128);
            reporter.expect(dataOk, "loaded sample bytes are the u8 data minus 128");
            reporter.expect(QByteArray(vg->voiceNames[0]) == "samplecheck_tone",
                            "loader-derived voice name");
            voicegroup_free(vg);
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: register + loader resolution OK\n");
    }

    // ---- re-registration refusal leaves the .inc untouched ----
    {
        const int before = reporter.failureCount();
        const QByteArray incBefore = readFileBytes(incPath);
        QString error;
        reporter.expect(!SampleRegistrar::registerSample(root, QStringLiteral("samplecheck_tone"),
                                                         fixture, &error),
                        "duplicate registration refused");
        reporter.expectError(error,
                             QStringLiteral("DirectSoundWaveData_samplecheck_tone "
                                            "already exists in this project."),
                             "duplicate-registration text");
        reporter.expect(readFileBytes(incPath) == incBefore,
                        "refused registration leaves the .inc byte-identical");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: duplicate refusal OK\n");
    }

    // ---- CRLF project: appended block matches the file's line endings ----
    {
        const int before = reporter.failureCount();
        const QString crlfRoot = scratchDir + QStringLiteral("/crlfproj");
        const QByteArray crlfSeed = "\t.align 2\r\n"
                                    "DirectSoundWaveData_existing::\r\n"
                                    "\t.incbin \"sound/direct_sound_samples/existing.bin\"\r\n";
        writeFile(crlfRoot + QStringLiteral("/audio_rules.mk"), kWav2AgbRules);
        writeFile(crlfRoot + QStringLiteral("/sound/direct_sound_data.inc"), crlfSeed);
        QString error;
        reporter.expect(
            SampleRegistrar::registerSample(crlfRoot, QStringLiteral("crlf_tone"), fixture, &error),
            "CRLF-project registration succeeds");
        const QByteArray grown =
            readFileBytes(crlfRoot + QStringLiteral("/sound/direct_sound_data.inc"));
        reporter.expect(grown == crlfSeed +
                                     QByteArray("\r\n"
                                                "\t.align 2\r\n"
                                                "DirectSoundWaveData_crlf_tone::\r\n"
                                                "\t.incbin "
                                                "\"sound/direct_sound_samples/crlf_tone.bin\"\r\n"),
                        "CRLF block appended with CRLF endings");
        bool crlfOk = true;
        for (int i = 0; i < grown.size(); i++) {
            if (grown[i] == '\n' && (i == 0 || grown[i - 1] != '\r'))
                crlfOk = false;
        }
        reporter.expect(crlfOk, "no bare LF snuck into the CRLF .inc");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: CRLF preservation OK\n");
    }
    if (!sampleRegistered)
        return std::nullopt;
    return RegisteredSampleProject{root, fixture, registeredSampleName};
}

} // namespace samplecheck
