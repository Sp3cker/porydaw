#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDoubleSpinBox>
#include <QFileInfo>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QScrollBar>
#include <QSpinBox>
#include <QSplitter>
#include <QUndoStack>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "audio/audioengine.h"
#include "audio/sampledoc.h"
#include "checks/support/eventsynth.h"
#include "project/samplereg.h"
#include "project/voicegroupsource.h"
#include "ui/sampleeditordialog.h"
#include "ui/waveformview.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace {

void sendSpaceStroke(QObject &target, Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    checks::events::sendKey(target, QEvent::KeyPress, Qt::Key_Space, modifiers, QStringLiteral(" "),
                            autoRepeat, 1);
    checks::events::sendKey(target, QEvent::KeyRelease, Qt::Key_Space, modifiers,
                            QStringLiteral(" "), autoRepeat, 1);
}

} // namespace

namespace samplecheck {

void runPipelineDialogChecks(Reporter &reporter, const RegisteredSampleProject &project,
                             const DspFixture &dspFixture)
{
    const QString &root = project.root;
    const QString &registeredSampleName = project.registeredSampleName;
    const ImportedSample &hiRes = dspFixture.hiRes;
    // ---- the dialog, offscreen: pipeline controls + commit validation ----
    {
        const int before = reporter.failureCount();
        ImportedSample prepared;
        QString error;
        reporter.expect(importAudioFile(root + QStringLiteral("/sound/direct_sound_samples/") +
                                            registeredSampleName + QStringLiteral(".wav"),
                                        &prepared, &error),
                        "prepared sample re-imports from the project");
        const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
        SampleEditorDialog dialog(prepared, [&](const QString &name, QString *validationError) {
            return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
        });
        auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
        auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
        auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleNameStatus"));
        auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
        auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
        auto *rateCombo = dialog.findChild<QComboBox *>(QStringLiteral("sampleRateCombo"));
        auto *fineTune = dialog.findChild<QDoubleSpinBox *>(QStringLiteral("sampleFineTune"));
        reporter.expect(nameEdit && addButton && status && baseKey && loopOn && rateCombo &&
                            fineTune,
                        "dialog widgets found");
        if (nameEdit && addButton && status && baseKey && loopOn && rateCombo && fineTune) {
            // Prefill comes from the source basename — here a collision.
            reporter.expect(nameEdit->text() == registeredSampleName,
                            "name prefilled from the source file");
            reporter.expect(!addButton->isEnabled(), "collision disables the commit");
            reporter.expectError(
                status->text(),
                QStringLiteral("DirectSoundWaveData_%1 already exists in this project.")
                    .arg(registeredSampleName),
                "collision status text");
            nameEdit->setText(QStringLiteral("fresh_tone"));
            reporter.expect(addButton->isEnabled(), "valid name enables the commit");
            reporter.expectError(status->text(),
                                 QStringLiteral("Registers as DirectSoundWaveData_fresh_tone"),
                                 "valid status text");
            reporter.expect(dialog.sampleName() == QStringLiteral("fresh_tone"),
                            "sampleName returns the edited name");
            nameEdit->setText(QStringLiteral("Bad Name"));
            reporter.expect(!addButton->isEnabled(), "bad grammar disables the commit");
            nameEdit->setText(QStringLiteral("fresh_tone"));

            // Prepared-shape defaults: byte-faithful no-op pipeline, source
            // agbp carried verbatim.
            const ProcessedSample &initial = dialog.document()->processed();
            reporter.expect(initial.freq == 15000000 && initial.size == 64 && initial.looped &&
                                initial.loopStart == 8,
                            "prepared defaults keep the source header verbatim");
            reporter.expect(baseKey->value() == 58 && std::abs(fineTune->value() - 25.0) < 1e-9,
                            "key/cents prefilled from smpl");
            bool dataFaithful = true;
            for (int i = 0; i < 64; i++)
                dataFaithful = dataFaithful && initial.s8[i] == char(qint8(i * 2 - 128));
            reporter.expect(dataFaithful, "prepared defaults render the data verbatim");

            // Editing the key drops the verbatim agbp and recomputes.
            baseKey->setValue(59);
            reporter.expect(dialog.document()->params().baseKey == 59 &&
                                dialog.document()->params().exactPitchOverride == 0 &&
                                dialog.document()->processed().freq != 15000000,
                            "key edit flows into the render and drops the override");
            baseKey->setValue(58);
            reporter.expect(dialog.document()->processed().freq == 15000000,
                            "restoring the source key restores the verbatim agbp");

            // Loop off: the render becomes a one-shot of the crop.
            loopOn->setChecked(false);
            reporter.expect(!dialog.document()->processed().looped &&
                                dialog.document()->processed().size == 64,
                            "loop toggle renders a one-shot");

            // Free-entry rate applies on commit (editingFinished), not per
            // keystroke — every apply is a full synchronous render.
            rateCombo->setEditText(QStringLiteral("6689.5"));
            reporter.expect(dialog.document()->params().targetRate != 6689.5,
                            "typing a rate does not re-render per keystroke");
            rateCombo->lineEdit()->editingFinished();
            reporter.expect(dialog.document()->params().targetRate == 6689.5 &&
                                dialog.document()->processed().declaredRate == 6690,
                            "committed target rate flows into the render");
            reporter.expect(dialog.document()->params().exactPitchOverride == 0,
                            "rate edit drops the verbatim agbp");

            // Crop and normalize controls flow through too. The index is
            // still 0 (free entry only changed the text), so bounce it to
            // fire currentIndexChanged and restore "keep source".
            rateCombo->setCurrentIndex(1);
            rateCombo->setCurrentIndex(0);
            reporter.expect(dialog.document()->params().targetRate ==
                                dialog.document()->source().sampleRate,
                            "preset pick applies and restores the source rate");
            auto *cropEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropEnd"));
            auto *normalize = dialog.findChild<QComboBox *>(QStringLiteral("sampleNormalizeMode"));
            reporter.expect(cropEnd && normalize, "crop/normalize widgets found");
            if (cropEnd && normalize) {
                cropEnd->setValue(32);
                reporter.expect(dialog.document()->processed().size == 32,
                                "crop end trims the one-shot render");
                normalize->setCurrentIndex(2); // One-shot (peak)
                reporter.expect(dialog.document()->params().normalizeMode ==
                                        SampleEditParams::NormalizeOneShot &&
                                    dialog.document()->processed().normalizeGain != 1.0,
                                "normalize mode applies gain to the render");
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: dialog validation OK\n");
    }
}

void runEditorChecks(Reporter &reporter, const RegisteredSampleProject &project,
                     const DspFixture &dspFixture, const QString &screenshotPath)
{
    const QString &root = project.root;
    const ImportedSample &hiRes = dspFixture.hiRes;
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    // ---- the editor, offscreen (phase 3): waveform drags, suggest chips,
    // pitch prefill, dialog-local undo, commit re-runs the §1 assertions ----
    {
        const int before = reporter.failureCount();
        const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
        SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
            return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
        });
        dialog.resize(900, 640);
        dialog.show();
        QApplication::processEvents();
        WaveformView *wave = dialog.waveform();
        SampleDocument *doc = dialog.document();
        QUndoStack *undo = dialog.undoStack();
        reporter.expect(wave && wave->width() > 200, "waveform view laid out");
        reporter.expect(doc->params().loopOn && doc->params().loopStart == 2000,
                        "hi-res fixture opens with its smpl loop");

        // 1. Drag the loop-start handle to ~sample 3000: params update live,
        // the whole gesture is one undo entry, and the render re-seats.
        const QPoint fromPt = wave->handlePoint(WaveformView::LoopStartHandle);
        const QPoint toPt(wave->xForSample(3000), fromPt.y());
        checks::events::sendMouse(*wave, QEvent::MouseButtonPress, QPointF(fromPt), Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        const QPoint midpoint = (fromPt + toPt) / 2;
        checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(midpoint), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(toPt), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*wave, QEvent::MouseButtonRelease, QPointF(toPt), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        reporter.expect(std::llabs(doc->params().loopStart - 3000) <= 40,
                        "loop-start handle drag lands near the target");
        reporter.expect(undo->count() == 1, "handle drag is one undo entry");
        reporter.expect(doc->processed().looped && doc->processed().seam.valid,
                        "drag re-renders with live seam metrics");
        undo->undo();
        reporter.expect(doc->params().loopStart == 2000, "undo restores the pre-drag loop");
        undo->redo();
        reporter.expect(std::llabs(doc->params().loopStart - 3000) <= 40,
                        "redo re-applies the drag");

        // 2. Pitch mismatch hint: the fixture's smpl claims unity 60 but
        // the tone sounds at 220 Hz (A3 + a few cents), so the detect
        // chrome shows at open; one Apply click adopts the detection and
        // the chrome hides again (agreement is the quiet state).
        auto *pitchApply = dialog.findChild<QPushButton *>(QStringLiteral("samplePitchApply"));
        auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
        auto *fineTune = dialog.findChild<QDoubleSpinBox *>(QStringLiteral("sampleFineTune"));
        reporter.expect(pitchApply && baseKey && fineTune, "pitch widgets found");
        if (pitchApply && baseKey && fineTune) {
            reporter.expect(baseKey->value() == 60, "smpl metadata wins over detection at open");
            // The 220 Hz tone detects as A3; the button names the key and
            // the tooltip carries the cents/Hz detail.
            reporter.expect(pitchApply->isVisible() &&
                                pitchApply->text().contains(QStringLiteral("A3")) &&
                                pitchApply->toolTip().contains(QStringLiteral("220")),
                            "metadata/detection mismatch surfaces the hint");
            // Evidence while the mismatch chrome is showing (every later
            // screenshot has it hidden by agreement).
            if (!screenshotPath.isEmpty()) {
                QApplication::processEvents();
                QImage pitchShot(dialog.size(), QImage::Format_ARGB32_Premultiplied);
                pitchShot.fill(Qt::white);
                dialog.render(&pitchShot);
                const QFileInfo info(screenshotPath);
                pitchShot.save(info.path() + QLatin1Char('/') + info.completeBaseName() +
                               QStringLiteral("-pitch.") + info.suffix());
            }
            pitchApply->click();
            reporter.expect(baseKey->value() == 57 && std::abs(fineTune->value() - 3.93) < 1.5 &&
                                undo->count() == 2,
                            "the button adopts the detected pitch as one undo entry");
            reporter.expect(!pitchApply->isVisible(), "agreement hides the detect chrome");
        }

        // 3. Auto-populate: disabling the loop hides the loop frame
        // entirely; zeroing the loop points and re-enabling seeds the
        // analyzer's best candidate as ONE undo entry (clean seam on this
        // pure tone, so no crossfade bake). "Try another loop" cycles
        // candidates, and a deliberately misaligned loop surfaces the
        // crossfade Fix.
        auto *group = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
        auto *loopBody = dialog.findChild<QWidget *>(QStringLiteral("sampleLoopBody"));
        auto *loopStartSpin = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
        auto *loopEndSpin = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
        auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
        reporter.expect(group && loopBody && loopStartSpin && loopEndSpin && badge,
                        "loop group widgets found");
        if (group && loopBody && loopStartSpin && loopEndSpin && badge) {
            reporter.expect(loopBody->isVisible(), "loop body shows while looped");
            group->setChecked(false); // undo 3
            reporter.expect(!doc->params().loopOn && !loopBody->isVisible(),
                            "unchecking the group hides the loop chrome");
            loopEndSpin->setValue(0);   // undo 4
            loopStartSpin->setValue(0); // undo 5
            reporter.expect(undo->count() == 5, "loop reset landed");
            group->setChecked(true); // auto-populate, undo 6
            reporter.expect(doc->params().loopOn &&
                                doc->params().loopStart != doc->params().loopEnd,
                            "re-enabling seeds a loop");
            reporter.expect(undo->count() == 6, "auto-populate is one undo entry");
            reporter.expect(!doc->params().crossfadeOn, "clean tone needs no crossfade bake");
            const ProcessedSample &out = doc->processed();
            reporter.expect(out.looped && out.seam.valid && out.seam.ampLsb <= 2 &&
                                out.seam.derivLsb <= 3 &&
                                (!out.seam.nccValid || out.seam.ncc >= 0.95),
                            "auto-populated loop is clean");
            reporter.expect(badge->isVisible() && badge->text() == QStringLiteral("seam: clean"),
                            "seam badge reads clean");
            reporter.expect(loopBody->isVisible(), "loop chrome is back");
            undo->undo();
            reporter.expect(!doc->params().loopOn, "undo re-disables the auto-populated loop");
            undo->redo();
            reporter.expect(doc->params().loopOn, "redo re-enables it");

            auto *tryLoop = dialog.findChild<QPushButton *>(QStringLiteral("sampleTryLoop"));
            reporter.expect(tryLoop != nullptr, "try-another button found");
            if (tryLoop) {
                tryLoop->click();
                reporter.expect(doc->params().loopOn && doc->processed().looped,
                                "try-another keeps a valid loop");
            }

            // Misaligned loop (220.5 Hz sine, period 200 — a 137-sample
            // loop cannot seat cleanly): the badge goes non-green. Also
            // the bad-seam state the refine/crossfade sections below run
            // from.
            loopStartSpin->setValue(2000);
            loopEndSpin->setValue(2137);
            reporter.expect(doc->processed().seam.valid && badge->isVisible() &&
                                badge->text() != QStringLiteral("seam: clean"),
                            "misaligned loop is not clean");
        }

        // 4. Refine is a no-worse local re-seat and one undo entry at most.
        auto *refine = dialog.findChild<QPushButton *>(QStringLiteral("sampleRefineLoop"));
        const double nccBeforeRefine = doc->processed().seam.ncc;
        if (refine) {
            refine->click();
            reporter.expect(doc->processed().seam.ncc >= nccBeforeRefine - 0.02,
                            "refine keeps the seam at least as clean");
        }
        const int refineCount = undo->count(); // 3 or 4 (no-op refine skips)

        // 5. Crossfade toggle flows into the params, and the seam inset
        // renders the PROCESSED windows, so baking visibly reshapes them.
        auto *crossfade = dialog.findChild<QCheckBox *>(QStringLiteral("sampleCrossfade"));
        reporter.expect(crossfade != nullptr, "crossfade toggle found");
        if (crossfade) {
            const std::vector<float> endBefore = wave->seamEndWindow();
            const std::vector<float> startBefore = wave->seamStartWindow();
            reporter.expect(!endBefore.empty() && endBefore.size() == startBefore.size(),
                            "looped render feeds the seam overlay");
            crossfade->setChecked(true);
            reporter.expect(doc->params().crossfadeOn && undo->count() == refineCount + 1,
                            "crossfade toggle is undoable");
            reporter.expect(wave->seamEndWindow() != endBefore ||
                                wave->seamStartWindow() != startBefore,
                            "crossfade bake reshapes the seam overlay");
            crossfade->setChecked(false);
        }

        // 6. No engine was passed: the audition strip is disabled.
        auto *playBtn = dialog.findChild<QPushButton *>(QStringLiteral("sampleAuditionPlay"));
        reporter.expect(playBtn && !playBtn->isEnabled(), "audition strip disabled without audio");

        // 7. Full undo walks back to the import defaults.
        while (undo->canUndo())
            undo->undo();
        reporter.expect(doc->params() == SampleDocument::defaultParams(hiRes),
                        "full undo restores the import defaults");
        while (undo->canRedo())
            undo->redo();

        // 8. Squeeze-then-scroll: a too-short window scrolls the control
        // column instead of squashing the loop/Advanced frames.
        auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
        reporter.expect(scroll != nullptr, "control-column scroll area found");
        if (scroll) {
            dialog.resize(900, 280);
            QApplication::processEvents();
            reporter.expect(scroll->verticalScrollBar()->maximum() > 0,
                            "short window scrolls the controls");
            dialog.resize(900, 640);
            QApplication::processEvents();
        }

        // 8b. The waveform/controls splitter makes the waveform height
        // user-resizable.
        auto *split = dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit"));
        reporter.expect(split != nullptr, "waveform splitter found");
        if (split && wave) {
            const int tall = wave->height();
            split->setSizes({wave->minimumSizeHint().height(), 10000});
            QApplication::processEvents();
            reporter.expect(wave->height() < tall, "splitter drag shrinks the waveform");
            split->setSizes({10000, split->sizes().value(1)});
            QApplication::processEvents();
        }

        // Layout evidence: the looped dialog, plus a -oneshot variant
        // (loop unchecked — the loop frame is gone entirely, not an empty
        // box). The toggle round-trips through plain param edits, so the
        // commit below still renders the redone state.
        if (!screenshotPath.isEmpty()) {
            QApplication::processEvents();
            QImage image(dialog.size(), QImage::Format_ARGB32_Premultiplied);
            image.fill(Qt::white);
            dialog.render(&image);
            image.save(screenshotPath);
            if (group) {
                group->setChecked(false);
                QApplication::processEvents();
                QImage oneShot(dialog.size(), QImage::Format_ARGB32_Premultiplied);
                oneShot.fill(Qt::white);
                dialog.render(&oneShot);
                const QFileInfo info(screenshotPath);
                oneShot.save(info.path() + QLatin1Char('/') + info.completeBaseName() +
                             QStringLiteral("-oneshot.") + info.suffix());
                group->setChecked(true);
                QApplication::processEvents();
            }
        }

        // 9. Commit: register the render and re-run the §1 assertions.
        auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
        reporter.expect(nameEdit != nullptr, "name field found");
        if (nameEdit) {
            nameEdit->setText(QStringLiteral("phase3_tone"));
            const QByteArray incBefore = readFileBytes(incPath);
            QString error;
            reporter.expect(SampleRegistrar::registerSample(root, dialog.sampleName(),
                                                            dialog.wavBytes(), &error),
                            "phase-3 commit registers");
            reporter.expect(readFileBytes(incPath) ==
                                incBefore + QByteArray("\n\t.align 2\n"
                                                       "DirectSoundWaveData_phase3_tone::\n"
                                                       "\t.incbin \"sound/direct_sound_samples/"
                                                       "phase3_tone.bin\"\n"),
                            "commit appends exactly the registration block");
            writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_phase3.inc"),
                      "voicegroup_phase3::\n"
                      "\tvoice_directsound 60, 0, "
                      "DirectSoundWaveData_phase3_tone, 255, 0, 255, 165\n");
            const QByteArray rootUtf8 = root.toLocal8Bit();
            LoadedVoiceGroup *vg =
                voicegroup_load(rootUtf8.constData(), "voicegroup_phase3", nullptr);
            const ProcessedSample &out = doc->processed();
            if (!vg) {
                std::fprintf(stderr, "samplecheck: FAIL: phase3 voicegroup_load\n");
                reporter.noteFailure();
            } else {
                const WaveData *wd = vg->voices[0].wav;
                reporter.expect(wd && wd->freq == out.freq && wd->loopStart == out.loopStart &&
                                    wd->size == out.size &&
                                    wd->status == (out.looped ? 0x4000 : 0) && wd->data &&
                                    std::memcmp(wd->data, out.s8.constData(), out.size) == 0,
                                "committed sample loads back identical (audition == "
                                "build)");
                voicegroup_free(vg);
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: editor phase-3 OK\n");
    }

    // ---- Space toggles the audition from anywhere in the dialog ----
    // Needs a live engine (the strip is disabled without one); skips
    // cleanly on machines with no audio device, like transportcheck.
    {
        const int before = reporter.failureCount();
        AudioEngine engine;
        QString audioError;
        if (!engine.init(&audioError)) {
            std::printf("samplecheck: SKIP space audition (no audio device: %s)\n",
                        qUtf8Printable(audioError));
        } else {
            SampleEditorDialog dialog(
                hiRes, [](const QString &, QString *) { return true; }, &engine);
            dialog.resize(900, 640);
            dialog.show();
            QApplication::processEvents();
            auto *play = dialog.findChild<QPushButton *>(QStringLiteral("sampleAuditionPlay"));
            auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
            auto *keySpin = dialog.findChild<QSpinBox *>(QStringLiteral("sampleAuditionKey"));
            reporter.expect(play && play->isEnabled() && nameEdit && keySpin,
                            "audition strip is live with an engine");
            if (play && play->isEnabled() && nameEdit && keySpin) {
                sendSpaceStroke(dialog, Qt::NoModifier, false);
                reporter.expect(play->text() == QStringLiteral("Stop"),
                                "Space starts the audition");
                sendSpaceStroke(dialog, Qt::NoModifier, false);
                reporter.expect(play->text() == QStringLiteral("Play"), "Space again stops it");

                // A focused input can't swallow the key: the toggle fires
                // and no space lands in the name.
                const QString nameBefore = nameEdit->text();
                sendSpaceStroke(*nameEdit, Qt::NoModifier, false);
                reporter.expect(play->text() == QStringLiteral("Stop") &&
                                    nameEdit->text() == nameBefore,
                                "Space in the name field auditions instead of typing");
                sendSpaceStroke(*keySpin, Qt::NoModifier, false);
                reporter.expect(play->text() == QStringLiteral("Play"),
                                "Space on the key spin box toggles too");

                // Only plain Space is the toggle: a modified press and a
                // held-key auto-repeat both leave the audition alone.
                sendSpaceStroke(dialog, Qt::ControlModifier, false);
                reporter.expect(play->text() == QStringLiteral("Play"),
                                "Ctrl+Space is not the toggle");
                sendSpaceStroke(dialog, Qt::NoModifier, true);
                reporter.expect(play->text() == QStringLiteral("Play"),
                                "auto-repeat Space does not re-toggle");
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: space audition OK\n");
    }
}

} // namespace samplecheck
