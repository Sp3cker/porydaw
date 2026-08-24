#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QFile>
#include <QLineEdit>
#include <QPushButton>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "audio/audioengine.h"
#include "audio/sampledoc.h"
#include "audio/sampleimport.h"
#include "audio/samplewav.h"
#include "project/samplereg.h"
#include "ui/sampleeditordialog.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace samplecheck {

void runEngineLoopChecks(Reporter &reporter, const RegisteredSampleProject &project,
                         const DspFixture &dspFixture)
{
    const QString &root = project.root;
    const ImportedSample &hiRes = dspFixture.hiRes;
    // ---- loop through the engine (DSP.md §9 item 8, phase 6): a committed
    // looped sample renders ≥ 4 loop wraps through m4a_channel and the wrap
    // steps stay in family with the loop body ----
    {
        const int before = reporter.failureCount();
        // A cleanly loopable render: the fixture loop is 40 exact 220.5 Hz
        // periods (2000..9999 at 44100), resampled onto the GBA mix ladder.
        SampleEditParams p = SampleDocument::defaultParams(hiRes);
        p.targetRate = 13379.0;
        SampleDocument doc(hiRes);
        doc.setParams(p);
        const ProcessedSample &out = doc.processed();
        reporter.expect(out.looped && out.size > out.loopStart + 100,
                        "engine-loop fixture renders looped");
        QString error;
        reporter.expect(SampleRegistrar::registerSample(root, QStringLiteral("engineloop_tone"),
                                                        writeSampleWav(out), &error),
                        "engine-loop sample registers");
        writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_engineloop.inc"),
                  "voicegroup_engineloop::\n"
                  "\tvoice_directsound 60, 0, "
                  "DirectSoundWaveData_engineloop_tone, 255, 0, 255, 0\n");
        const QByteArray rootUtf8 = root.toLocal8Bit();
        LoadedVoiceGroup *vg =
            voicegroup_load(rootUtf8.constData(), "voicegroup_engineloop", nullptr);
        if (!vg) {
            std::fprintf(stderr, "samplecheck: FAIL: engineloop voicegroup_load\n");
            reporter.noteFailure();
        } else {
            // The hardware frontend requires an integral host rate. Use the
            // nearest rate to the sample's effective frequency, then let the
            // PCM mixer follow it.
            auto *engine = new M4AEngine();
            const float hostRate = float(std::round(double(out.freq) / 1024.0));
            const bool initialized = m4a_engine_init(engine, hostRate);
            reporter.expect(initialized, "engine-loop initializes at an integral host rate");
            if (initialized) {
                m4a_engine_set_pcm_mix_rate(engine, 0.0f);
                m4a_engine_set_voicegroup(engine, vg->voices);
                m4a_engine_program_change(engine, 0, 0);
                m4a_engine_note_on(engine, 0, 60, 127);
                const M4APCMChannel *ch = nullptr;
                for (int i = 0; i < MAX_PCM_CHANNELS; i++) {
                    if (engine->pcmChannels[i].status & CHN_ON)
                        ch = &engine->pcmChannels[i];
                }
                reporter.expect(ch != nullptr, "engine-loop note keys a channel");
                double maxRenderedStep = 0.0, peak = 0.0;
                if (ch) {
                    const quint64 loopLength = quint64(out.size) - out.loopStart;
                    const quint64 measurementStart = quint64(out.size) + 4 * loopLength;
                    const quint64 renderFrames = measurementStart + loopLength;
                    constexpr quint64 kMaxRenderFrames = 400000;
                    reporter.expect(renderFrames <= kMaxRenderFrames,
                                    "engine-loop fixture fits render window");
                    if (renderFrames <= kMaxRenderFrames) {
                        float l = 0.0f, r = 0.0f;
                        double prev = 0.0;
                        for (quint64 i = 0; i < renderFrames; i++) {
                            m4a_engine_process(engine, &l, &r, 1);
                            const double v = double(l);
                            if (i >= measurementStart) {
                                maxRenderedStep = qMax(maxRenderedStep, std::abs(v - prev));
                                peak = qMax(peak, std::abs(v));
                            }
                            prev = v;
                        }
                        reporter.expect((ch->status & CHN_ON) && peak > 0.0,
                                        "at least 4 full loop wraps rendered");
                    }
                }
                // Compare the rendered loop's largest step against the source
                // loop, including its seam. One LSB in output units is derived
                // from the loop region's peak s8 value.
                int maxS8 = 1;
                int maxSourceStep = 0;
                for (quint32 i = out.loopStart; i < out.size; i++) {
                    const int sample = int(qint8(out.s8.at(qsizetype(i))));
                    const quint32 nextIndex = i + 1 < out.size ? i + 1 : out.loopStart;
                    const int next = int(qint8(out.s8.at(qsizetype(nextIndex))));
                    maxS8 = qMax(maxS8, std::abs(sample));
                    maxSourceStep = qMax(maxSourceStep, std::abs(next - sample));
                }
                const double lsb = peak / double(maxS8);
                reporter.expect(peak > 0.0 && maxRenderedStep <=
                                                  double(maxSourceStep) * lsb + 2.0 * lsb + 1e-9,
                                "loop-wrap steps stay within source steps + 2 LSB");
            }
            m4a_engine_destroy(engine);
            delete engine;
            voicegroup_free(vg);
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: engine loop integration OK\n");
    }
}

void runProvenanceChecks(Reporter &reporter, const RegisteredSampleProject &project,
                         const DspFixture &dspFixture, const QString &scratchDir)
{
    const QString &root = project.root;
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    const ImportedSample &hiRes = dspFixture.hiRes;
    // ---- provenance sidecar + edit-in-place (phase 6): sidecar round-trip,
    // hash guard, committed-.wav fallback, updateSample, edit-mode dialog ----
    {
        const int before = reporter.failureCount();
        // The "external" hi-res source file the sidecar points back at.
        const QString sourcePath = scratchDir + QStringLiteral("/sources/hires_tone.wav");
        const QByteArray sourceBytes = dspFixture.hiResWav;
        writeFile(sourcePath, sourceBytes);

        // Commit a non-trivial render of it, exactly as MainWindow does.
        SampleEditParams p = SampleDocument::defaultParams(hiRes);
        p.cropStart = 150;
        p.targetRate = 13379.0;
        p.baseKey = 59;
        p.fineTuneCents = 25.0;
        SampleDocument doc(hiRes);
        doc.setParams(p);
        const QByteArray committed = writeSampleWav(doc.processed());
        QString error;
        reporter.expect(SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"),
                                                        committed, &error),
                        "provenance sample registers");
        SampleSidecar sc;
        sc.sourcePath = sourcePath;
        sc.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
        sc.params = p;
        reporter.expect(SampleRegistrar::writeSampleSidecar(root, QStringLiteral("provenance_tone"),
                                                            sc, &error),
                        "sidecar writes");

        SampleSidecar back;
        reporter.expect(
            SampleRegistrar::readSampleSidecar(root, QStringLiteral("provenance_tone"), &back),
            "sidecar reads back");
        reporter.expect(back.version == 1 && back.sourcePath == sc.sourcePath &&
                            back.sourceSha256 == sc.sourceSha256 && back.leftOnly == sc.leftOnly &&
                            back.sf2Zone == sc.sf2Zone && back.params == sc.params,
                        "sidecar round-trips every field");

        // PLAN §6 acceptance: reopen from the sidecar, re-render, and the
        // bytes equal the committed .wav exactly.
        {
            const QByteArray reread = readFileBytes(back.sourcePath);
            reporter.expect(SampleRegistrar::sourceHashHex(reread) == back.sourceSha256,
                            "sidecar hash matches the untouched source");
            ImportedSample reopened;
            reporter.expect(
                importAudioBytes(reread, back.sourcePath, &reopened, &error, back.leftOnly),
                "sidecar source re-imports");
            SampleDocument redoc(reopened);
            redoc.setParams(back.params);
            reporter.expect(writeSampleWav(redoc.processed()) == committed,
                            "sidecar re-render equals the committed bytes");
        }

        // A touched source is detectable (the edit flow offers re-import).
        writeFile(sourcePath, sourceBytes + QByteArray(4, '\0'));
        reporter.expect(SampleRegistrar::sourceHashHex(readFileBytes(sourcePath)) !=
                            back.sourceSha256,
                        "a touched source no longer matches the sidecar hash");
        writeFile(sourcePath, sourceBytes);

        // Missing-sidecar fallback: the committed 8-bit .wav re-imports
        // GBA-ready and its no-op default render is byte-faithful.
        {
            ImportedSample fallback;
            reporter.expect(importAudioBytes(committed, QStringLiteral("x/provenance_tone.wav"),
                                             &fallback, &error),
                            "committed .wav re-imports");
            reporter.expect(fallback.gbaReady, "committed .wav re-imports GBA-ready");
            SampleDocument fdoc(fallback);
            fdoc.setParams(SampleDocument::defaultParams(fallback));
            reporter.expect(writeSampleWav(fdoc.processed()) == committed,
                            "no-op fallback render is byte-identical");
        }

        // updateSample overwrites the .wav in place and leaves the .inc
        // byte-identical; refusals for anything not updatable exact-match.
        SampleEditParams p2 = p;
        p2.fineTuneCents = 40.0;
        doc.setParams(p2);
        const QByteArray updated = writeSampleWav(doc.processed());
        reporter.expect(updated != committed, "updated render differs");
        const QByteArray incBefore = readFileBytes(incPath);
        reporter.expect(
            SampleRegistrar::updateSample(root, QStringLiteral("provenance_tone"), updated, &error),
            "updateSample succeeds");
        reporter.expect(readFileBytes(incPath) == incBefore,
                        "update leaves the .inc byte-identical");
        reporter.expect(readFileBytes(root + QStringLiteral("/sound/direct_sound_samples/"
                                                            "provenance_tone.wav")) == updated,
                        "update replaces the .wav bytes");
        reporter.expect(!SampleRegistrar::updateSample(root, QStringLiteral("never_registered"),
                                                       updated, &error),
                        "updating an unregistered sample refuses");
        reporter.expectError(error,
                             QStringLiteral("DirectSoundWaveData_never_registered is not "
                                            "registered in this project; use Import Sample to "
                                            "add new samples."),
                             "unregistered-update refusal text");
        // A symbol registered without a .wav source (a .bin-only legacy
        // sample) refuses too. Appended after the byte-identity assertions
        // above so it can't disturb them.
        constexpr char binOnlyFixture[] = "\n\t.align 2\nDirectSoundWaveData_binonly::\n"
                                          "\t.incbin \"sound/direct_sound_samples/binonly.bin\"\n";
        bool appendedBinOnlyFixture = false;
        {
            QFile inc(incPath);
            appendedBinOnlyFixture =
                inc.open(QIODevice::Append) &&
                inc.write(binOnlyFixture) == qint64(sizeof(binOnlyFixture) - 1);
        }
        reporter.expect(appendedBinOnlyFixture, "append .bin-only sample fixture");
        if (appendedBinOnlyFixture) {
            reporter.expect(
                !SampleRegistrar::updateSample(root, QStringLiteral("binonly"), updated, &error),
                "updating a .wav-less symbol refuses");
            reporter.expectError(error,
                                 QStringLiteral("binonly.wav does not exist in "
                                                "sound/direct_sound_samples — only samples with a "
                                                ".wav source can be updated."),
                                 "wav-less-update refusal text");
        }

        // The dialog in edit mode: locked name, "Save Sample" commit, and
        // sidecar params applied as the baseline (not an undo entry).
        {
            SampleEditorDialog dialog(hiRes, [](const QString &candidate, QString *err) {
                if (candidate == QStringLiteral("provenance_tone"))
                    return true;
                if (err)
                    *err = QStringLiteral("the sample keeps its "
                                          "registered name.");
                return false;
            });
            dialog.setEditTarget(QStringLiteral("provenance_tone"));
            dialog.applyParamsExternal(p);
            dialog.show();
            QApplication::processEvents();
            auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
            auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
            reporter.expect(nameEdit && nameEdit->isReadOnly() &&
                                nameEdit->text() == QStringLiteral("provenance_tone"),
                            "edit mode locks the name");
            reporter.expect(addButton && addButton->isEnabled() &&
                                addButton->text() == QStringLiteral("Save Sample"),
                            "edit mode arms Save Sample");
            reporter.expect(dialog.document()->params() == p && dialog.undoStack()->count() == 0,
                            "sidecar params are the baseline, not an undo entry");
        }

        SampleRegistrar::removeSampleSidecar(root, QStringLiteral("provenance_tone"));
        reporter.expect(
            !SampleRegistrar::readSampleSidecar(root, QStringLiteral("provenance_tone"), &back),
            "removed sidecar no longer reads");
        if (reporter.failureCount() == before)
            std::printf("samplecheck: provenance sidecar OK\n");
    }
}

} // namespace samplecheck
