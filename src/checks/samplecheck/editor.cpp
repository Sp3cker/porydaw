#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QDir>
#include <QDoubleSpinBox>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QObject>
#include <QPushButton>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QSpinBox>
#include <QSplitter>
#include <QUndoStack>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "audio/audioengine.h"
#include "audio/sampledoc.h"
#include "checks/support/eventsynth.h"
#include "project/samplereg.h"
#include "project/voicegroupsource.h"
#include "ui/sampleeditordialog.h"
#include "ui/samplelibrarypanel.h"
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

// Click (or double-click) a list item at its visual center.
void clickItem(QListWidget &list, const QListWidgetItem *item, bool doubleClick)
{
    QWidget *view = list.viewport();
    const QPointF center(list.visualItemRect(item).center());
    if (doubleClick) {
        checks::events::sendMouse(*view, QEvent::MouseButtonDblClick, center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
    } else {
        checks::events::sendMouse(*view, QEvent::MouseButtonPress, center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
    }
    checks::events::sendMouse(*view, QEvent::MouseButtonRelease, center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
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

    // ---- Editing an existing sample can become a separate registration
    // without closing the dialog or reusing the original-name validator. ----
    {
        const int before = reporter.failureCount();
        const QString copyName = registeredSampleName + QStringLiteral("_copy");
        const auto originalValidator = [registeredSampleName](const QString &name, QString *) {
            return name == registeredSampleName;
        };
        const auto copyValidator = [copyName](const QString &name, QString *) {
            return name == copyName;
        };
        SampleEditorDialog dialog(hiRes, originalValidator);
        dialog.setEditTarget(registeredSampleName, copyValidator);
        dialog.show();
        QApplication::processEvents();
        auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
        auto *saveAsNew = dialog.findChild<QPushButton *>(QStringLiteral("sampleSaveAsNewButton"));
        auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
        bool accepted = false;
        QObject::connect(&dialog, &QDialog::accepted, &dialog, [&accepted] { accepted = true; });
        reporter.expect(nameEdit && saveAsNew && addButton, "save-as-new controls found");
        if (nameEdit && saveAsNew && addButton) {
            reporter.expect(nameEdit->isReadOnly() && saveAsNew->isVisible(),
                            "edit target locks its name and exposes Save as New Sample");
            saveAsNew->click();
            QApplication::processEvents();
            reporter.expect(!accepted && dialog.saveAsNew(),
                            "Save as New Sample stays open and enters new registration mode");
            reporter.expect(!nameEdit->isReadOnly() && nameEdit->text() == copyName,
                            "Save as New Sample unlocks and suggests a distinct name");
            reporter.expect(!saveAsNew->isVisible(), "Save as New Sample hides after use");
            reporter.expect(addButton->text() == QStringLiteral("Add to Project") &&
                                addButton->isEnabled(),
                            "new registration action is enabled for the suggested name");
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: save as new sample OK\n");
    }
}

void runEditorChecks(Reporter &reporter, const RegisteredSampleProject &project,
                     const DspFixture &dspFixture, const QString &screenshotPath)
{
    const QString &root = project.root;
    const ImportedSample &hiRes = dspFixture.hiRes;
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    const QString sampleDir = root + QStringLiteral("/sound/direct_sound_samples/");
    const QString absDir = QDir(sampleDir).absolutePath();
    const QString libraryWavName = project.registeredSampleName + QStringLiteral(".wav");
    const QString libraryWavAbs = QFileInfo(sampleDir + libraryWavName).absoluteFilePath();
    const QString nestedDir = QDir(sampleDir).filePath(QStringLiteral("nested"));
    const QString nestedWavName = QStringLiteral("nested_tone.wav");
    const QString nestedWavAbs =
        QFileInfo(QDir(nestedDir).filePath(nestedWavName)).absoluteFilePath();
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

    // ---- Sample library panel: discovery, add/dedupe, persistence,
    // engine-less preview refusal, and the load reset. The dialog embeds
    // the panel; everything below drives the public widgets only. ----
    {
        const int before = reporter.failureCount();
        reporter.expect(QDir().mkpath(nestedDir), "sample library creates the nested directory");
        reporter.expect(QFile::exists(libraryWavAbs), "registered sample exists for library setup");
        if (QFile::exists(nestedWavAbs))
            reporter.expect(QFile::remove(nestedWavAbs), "nested library sample resets safely");
        if (QFile::exists(libraryWavAbs))
            reporter.expect(QFile::copy(libraryWavAbs, nestedWavAbs),
                            "sample library copies a compatible nested wav");
        const QString ignoredSf2Name = QStringLiteral("ignored_bank.sf2");
        const QString ignoredTextName = QStringLiteral("ignored_notes.txt");
        reporter.expect(writeFile(QDir(sampleDir).filePath(ignoredSf2Name), QByteArray("ignored")),
                        "sample library writes an incompatible sf2 fixture");
        reporter.expect(writeFile(QDir(sampleDir).filePath(ignoredTextName), QByteArray("ignored")),
                        "sample library writes an incompatible text fixture");

        SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
        dialog.resize(900, 640);
        dialog.show();
        QApplication::processEvents();
        auto *panel = dialog.findChild<SampleLibraryPanel *>(QStringLiteral("sampleLibraryPanel"));
        auto *libraryAdd =
            dialog.findChild<QPushButton *>(QStringLiteral("sampleLibraryAddFolder"));
        auto *libraryRemove =
            dialog.findChild<QPushButton *>(QStringLiteral("sampleLibraryRemoveFolder"));
        auto *folders = dialog.findChild<QListWidget *>(QStringLiteral("sampleLibraryFolders"));
        auto *directories =
            dialog.findChild<QListWidget *>(QStringLiteral("sampleLibraryDirectories"));
        auto *files = dialog.findChild<QListWidget *>(QStringLiteral("sampleLibraryFiles"));
        auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleLibraryStatus"));
        auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
        SampleDocument *doc = dialog.document();
        QUndoStack *undo = dialog.undoStack();
        reporter.expect(panel && libraryAdd && libraryRemove && folders && directories && files &&
                            status && nameEdit,
                        "library panel and controls found");
        if (panel && libraryRemove && folders && directories && files && status && nameEdit) {
            reporter.expect(folders->count() == 0 && directories->count() == 0 &&
                                files->count() == 0,
                            "library lists start empty");
            panel->addFolder(sampleDir);

            {
                auto *rootItem = directories->item(0);
                reporter.expect(rootItem && rootItem->text() == QStringLiteral("This Folder"),
                                "directory list starts with This Folder");
                if (rootItem) {
                    reporter.expectError(rootItem->data(Qt::UserRole).toString(), absDir,
                                         "root directory carries the normalized absolute path");
                }
            }
            {
                auto *nestedItem =
                    directories->findItems(QStringLiteral("nested"), Qt::MatchExactly).value(0);
                reporter.expect(nestedItem != nullptr, "library lists the direct nested directory");
                if (nestedItem) {
                    reporter.expectError(nestedItem->data(Qt::UserRole).toString(),
                                         QFileInfo(nestedDir).absoluteFilePath(),
                                         "nested directory carries its absolute path");
                    clickItem(*directories, nestedItem, false);
                    QApplication::processEvents();
                }
            }
            {
                auto *nestedWavItem = files->findItems(nestedWavName, Qt::MatchExactly).value(0);
                reporter.expect(nestedWavItem != nullptr,
                                "selecting nested lists its compatible wav");
                if (nestedWavItem) {
                    reporter.expectError(nestedWavItem->data(Qt::UserRole).toString(), nestedWavAbs,
                                         "nested file item carries the absolute wav path");
                }
            }
            {
                auto *rootItem = directories->item(0);
                reporter.expect(rootItem != nullptr, "root directory remains selectable");
                if (rootItem) {
                    clickItem(*directories, rootItem, false);
                    QApplication::processEvents();
                }
            }
            {
                auto *rootWavItem = files->findItems(libraryWavName, Qt::MatchExactly).value(0);
                reporter.expect(rootWavItem != nullptr,
                                "reselecting root restores the registered sample");
                if (rootWavItem) {
                    reporter.expectError(rootWavItem->data(Qt::UserRole).toString(), libraryWavAbs,
                                         "root file item carries the absolute wav path");
                }
                reporter.expect(files->findItems(ignoredSf2Name, Qt::MatchExactly).isEmpty() &&
                                    files->findItems(ignoredTextName, Qt::MatchExactly).isEmpty(),
                                "library excludes incompatible files");
            }

            const int foldersAfterAdd = folders->count();
            const int directoriesAfterAdd = directories->count();
            const int filesAfterAdd = files->count();
            panel->addFolder(sampleDir);
            const bool deduped = folders->count() == foldersAfterAdd &&
                                 directories->count() == directoriesAfterAdd &&
                                 files->count() == filesAfterAdd &&
                                 files->findItems(libraryWavName, Qt::MatchExactly).size() == 1;
            reporter.expect(deduped, "re-adding the folder does not duplicate entries");
            QSettings settings;
            reporter.expect(settings.value(QStringLiteral("sampleLibraryFolders"))
                                .toStringList()
                                .contains(absDir),
                            "addFolder persists the normalized folder path");
            settings.sync();

            auto *wavItem = files->findItems(libraryWavName, Qt::MatchExactly).value(0);
            if (wavItem) {
                ImportedSample librarySource;
                QString libraryError;
                reporter.expect(importAudioFile(libraryWavAbs, &librarySource, &libraryError),
                                "library source imports for load defaults");
                const SampleEditParams libraryDefaults =
                    SampleDocument::defaultParams(librarySource);
                auto *cropStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropStart"));
                auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
                auto *fineTune =
                    dialog.findChild<QDoubleSpinBox *>(QStringLiteral("sampleFineTune"));
                auto *normalize =
                    dialog.findChild<QComboBox *>(QStringLiteral("sampleNormalizeMode"));
                auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
                auto *crossfade = dialog.findChild<QCheckBox *>(QStringLiteral("sampleCrossfade"));
                auto *rateCombo = dialog.findChild<QComboBox *>(QStringLiteral("sampleRateCombo"));
                reporter.expect(cropStart && baseKey && fineTune && normalize && loopOn &&
                                    crossfade && rateCombo,
                                "library load reset controls found");
                if (cropStart && baseKey && fineTune && normalize && loopOn && crossfade &&
                    rateCombo) {
                    // Set each retained control to a valid value distinct
                    // from the incoming file's defaults. The post-load
                    // checks below catch UI state that a later edit would
                    // otherwise write back into the replacement document.
                    const int libraryCropLimit = static_cast<int>(libraryDefaults.cropEnd - 1);
                    const int cropStartBeforeLoad =
                        libraryDefaults.cropStart == cropStart->minimum()
                            ? std::min(cropStart->maximum(), libraryCropLimit)
                            : cropStart->minimum();
                    const int baseKeyBeforeLoad = libraryDefaults.baseKey == baseKey->minimum()
                                                      ? baseKey->maximum()
                                                      : baseKey->minimum();
                    const double fineTuneBeforeLoad =
                        libraryDefaults.fineTuneCents == fineTune->minimum() ? fineTune->maximum()
                                                                             : fineTune->minimum();
                    const int libraryNormalizeMode =
                        static_cast<int>(libraryDefaults.normalizeMode);
                    const int normalizeBeforeLoad = libraryNormalizeMode == 0 ? 1 : 0;
                    reporter.expect(cropStartBeforeLoad >= cropStart->minimum() &&
                                        cropStartBeforeLoad != libraryDefaults.cropStart &&
                                        baseKeyBeforeLoad != libraryDefaults.baseKey &&
                                        fineTuneBeforeLoad != libraryDefaults.fineTuneCents &&
                                        normalizeBeforeLoad < normalize->count(),
                                    "library pre-load values differ from its defaults");
                    cropStart->setValue(cropStartBeforeLoad);
                    baseKey->setValue(baseKeyBeforeLoad);
                    fineTune->setValue(fineTuneBeforeLoad);
                    normalize->setCurrentIndex(normalizeBeforeLoad);
                    if (loopOn->isChecked())
                        crossfade->setChecked(!libraryDefaults.crossfadeOn);
                    loopOn->setChecked(!libraryDefaults.loopOn);
                    if (rateCombo->count() > 1)
                        rateCombo->setCurrentIndex(1);
                    reporter.expect(
                        cropStart->value() != libraryDefaults.cropStart &&
                            baseKey->value() != libraryDefaults.baseKey &&
                            std::abs(fineTune->value() - libraryDefaults.fineTuneCents) >= 1e-9 &&
                            normalize->currentIndex() != libraryNormalizeMode &&
                            loopOn->isChecked() != libraryDefaults.loopOn,
                        "editor controls differ before library load");
                    reporter.expect(undo->count() > 0,
                                    "pre-load control edits populate the dialog-local undo");
                    // A click previews: with no engine the dialog refuses
                    // via the status label and the open document is
                    // untouched.
                    const QString sourceBefore = doc->source().sourcePath;
                    clickItem(*files, wavItem, false);
                    QApplication::processEvents();
                    reporter.expectError(status->text(), QStringLiteral("Audio is unavailable."),
                                         "engine-less preview status");
                    reporter.expect(doc->source().sourcePath == sourceBefore,
                                    "a refused preview does not touch the document");
                    // A double-click loads: the document swaps to the
                    // clicked file, the name prefills from its sanitized
                    // basename, each exercised editor control adopts the
                    // replacement params, and the dialog-local undo starts
                    // empty.
                    nameEdit->setText(QStringLiteral("library_edit"));
                    clickItem(*files, wavItem, true);
                    QApplication::processEvents();
                    reporter.expectError(doc->source().sourcePath, libraryWavAbs,
                                         "double-click loads the clicked file");
                    reporter.expectError(
                        dialog.loadedSourceSha256(),
                        SampleRegistrar::sourceHashHex(readFileBytes(libraryWavAbs)),
                        "library load captures the decoded file's source hash");
                    reporter.expectError(nameEdit->text(), project.registeredSampleName,
                                         "load prefills the sanitized basename");
                    reporter.expect(undo->count() == 0, "loading resets the dialog-local undo");
                    reporter.expect(cropStart->value() == doc->params().cropStart &&
                                        baseKey->value() == doc->params().baseKey &&
                                        std::abs(fineTune->value() - doc->params().fineTuneCents) <
                                            1e-9 &&
                                        normalize->currentIndex() == doc->params().normalizeMode &&
                                        loopOn->isChecked() == doc->params().loopOn &&
                                        crossfade->isChecked() == doc->params().crossfadeOn,
                                    "loading resets retained editor controls to document params");
                    if (rateCombo->count() > 1) {
                        reporter.expect(rateCombo->currentIndex() == 0 &&
                                            doc->params().targetRate == doc->source().sampleRate,
                                        "loading resets the target-rate combo to keep source");
                    }
                }
            }
        }
        // The saved folder list restores into a fresh dialog.
        {
            SampleEditorDialog restored(hiRes, [](const QString &, QString *) { return true; });
            restored.show();
            QApplication::processEvents();
            auto *restoredFolders =
                restored.findChild<QListWidget *>(QStringLiteral("sampleLibraryFolders"));
            auto *restoredDirectories =
                restored.findChild<QListWidget *>(QStringLiteral("sampleLibraryDirectories"));
            reporter.expect(restoredFolders && restoredFolders->count() == 1 && restoredDirectories,
                            "a second dialog restores the saved folder");
            if (restoredFolders && restoredFolders->count() == 1) {
                reporter.expectError(restoredFolders->item(0)->text(), absDir,
                                     "restored folder is the saved absolute path");
            }
            if (restoredDirectories) {
                auto *restoredNested =
                    restoredDirectories->findItems(QStringLiteral("nested"), Qt::MatchExactly)
                        .value(0);
                reporter.expect(restoredNested != nullptr,
                                "restored dialog exposes the nested directory");
            }
        }
        if (panel && libraryRemove && folders && directories && files && status) {
            reporter.expect(libraryRemove->isEnabled(),
                            "remove is enabled while the saved folder is selected");
            libraryRemove->click();
            QApplication::processEvents();
            QSettings settings;
            reporter.expect(folders->count() == 0 && directories->count() == 0 &&
                                files->count() == 0 && status->text().isEmpty(),
                            "removing a folder clears the library lists and status");
            reporter.expect(!settings.value(QStringLiteral("sampleLibraryFolders"))
                                 .toStringList()
                                 .contains(absDir),
                            "removing a folder updates persistent settings");

            const QString missingDir =
                QFileInfo(QDir(root).filePath(QStringLiteral("missing-sample-library")))
                    .absoluteFilePath();
            reporter.expect(!QDir(missingDir).exists(), "missing library fixture does not exist");
            panel->addFolder(missingDir);
            QApplication::processEvents();
            reporter.expectError(status->text(),
                                 QStringLiteral("Folder not found: %1").arg(missingDir),
                                 "missing folder reports its absolute path");
            reporter.expect(settings.value(QStringLiteral("sampleLibraryFolders"))
                                .toStringList()
                                .contains(missingDir),
                            "missing folder remains persisted for a disconnected drive");
            reporter.expect(libraryRemove->isEnabled(),
                            "remove remains available for a missing folder");
            libraryRemove->click();
            QApplication::processEvents();
            reporter.expect(
                folders->count() == 0 && directories->count() == 0 && files->count() == 0 &&
                    status->text().isEmpty() &&
                    settings.value(QStringLiteral("sampleLibraryFolders")).toStringList().isEmpty(),
                "removing the missing folder clears UI and persistence");
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: sample library OK\n");
    }

    // ---- A source-less editor keeps the placeholder uncommittable until
    // a library file is loaded, then adopts that file and its provenance. ----
    {
        const int before = reporter.failureCount();
        const QString sourceLessDir = QDir(root).filePath(QStringLiteral("source-less-library"));
        const QString sourceLessWavName = QStringLiteral("source_less_tone.wav");
        const QString sourceLessWavAbs =
            QFileInfo(QDir(sourceLessDir).filePath(sourceLessWavName)).absoluteFilePath();
        const QByteArray sourceLessBytes = dspFixture.hiResWav;
        reporter.expect(writeFile(sourceLessWavAbs, sourceLessBytes),
                        "source-less library fixture writes");
        const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
        SampleEditorDialog dialog([&](const QString &name, QString *validationError) {
            return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
        });
        dialog.resize(900, 640);
        dialog.show();
        QApplication::processEvents();
        auto *editorPane = dialog.findChild<QWidget *>(QStringLiteral("sampleEditorPane"));
        auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
        auto *panel = dialog.findChild<SampleLibraryPanel *>(QStringLiteral("sampleLibraryPanel"));
        auto *directories =
            dialog.findChild<QListWidget *>(QStringLiteral("sampleLibraryDirectories"));
        auto *files = dialog.findChild<QListWidget *>(QStringLiteral("sampleLibraryFiles"));
        auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
        auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleNameStatus"));
        SampleDocument *doc = dialog.document();
        reporter.expect(editorPane && addButton && panel && directories && files && nameEdit &&
                            status && doc,
                        "source-less dialog controls found");
        if (editorPane && addButton && panel && directories && files && nameEdit && status && doc) {
            reporter.expect(!editorPane->isEnabled() && !addButton->isEnabled(),
                            "placeholder editor cannot commit");
            reporter.expect(
                status->text().contains(QStringLiteral("choose"), Qt::CaseInsensitive) &&
                    status->text().contains(QStringLiteral("library"), Qt::CaseInsensitive),
                "source-less status asks to choose from the library");
            panel->addFolder(sourceLessDir);
            QApplication::processEvents();
            auto *rootItem = directories->item(0);
            reporter.expect(rootItem && rootItem->text() == QStringLiteral("This Folder"),
                            "source-less library opens at This Folder");
            if (rootItem) {
                clickItem(*directories, rootItem, false);
                QApplication::processEvents();
            }
            auto *wavItem = files->findItems(sourceLessWavName, Qt::MatchExactly).value(0);
            reporter.expect(wavItem != nullptr, "source-less library lists the root wav");
            if (wavItem) {
                clickItem(*files, wavItem, false);
                QApplication::processEvents();
                clickItem(*files, wavItem, true);
                QApplication::processEvents();
                reporter.expect(editorPane->isEnabled() && addButton->isEnabled(),
                                "library load activates the editor and commit");
                reporter.expectError(nameEdit->text(), QStringLiteral("source_less_tone"),
                                     "source-less load prefills the sample name");
                reporter.expectError(doc->source().sourcePath, sourceLessWavAbs,
                                     "source-less load swaps the document source");
                reporter.expectError(dialog.loadedSourceSha256(),
                                     SampleRegistrar::sourceHashHex(sourceLessBytes),
                                     "source-less load captures decoded file bytes");
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: source-less editor OK\n");
    }

    // ---- Library preview with a live engine: a click auditions the file
    // and clears the status; skipped cleanly without an audio device ----
    {
        const int before = reporter.failureCount();
        AudioEngine engine;
        QString audioError;
        if (!engine.init(&audioError)) {
            std::printf("samplecheck: SKIP library preview (no audio device: %s)\n",
                        qUtf8Printable(audioError));
        } else {
            SampleEditorDialog dialog(
                hiRes, [](const QString &, QString *) { return true; }, &engine);
            dialog.resize(900, 640);
            dialog.show();
            QApplication::processEvents();
            auto *panel =
                dialog.findChild<SampleLibraryPanel *>(QStringLiteral("sampleLibraryPanel"));
            auto *files = dialog.findChild<QListWidget *>(QStringLiteral("sampleLibraryFiles"));
            auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleLibraryStatus"));
            reporter.expect(panel && files && status, "library controls found with an engine");
            if (panel && files && status) {
                // The folder saved above restores itself; the idempotent
                // add also covers runs where persistence was empty.
                panel->addFolder(sampleDir);
                QListWidgetItem *wavItem =
                    files->findItems(libraryWavName, Qt::MatchExactly).value(0);
                reporter.expect(wavItem != nullptr, "restored folder lists the registered sample");
                if (wavItem) {
                    clickItem(*files, wavItem, false);
                    QApplication::processEvents();
                    reporter.expect(status->text().isEmpty(),
                                    "live preview clears the library status");
                }
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: library preview OK\n");
    }
}

} // namespace samplecheck
