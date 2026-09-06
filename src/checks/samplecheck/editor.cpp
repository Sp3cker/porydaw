#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QByteArray>
#include <QCheckBox>
#include <QComboBox>
#include <QDoubleSpinBox>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QScrollBar>
#include <QSpinBox>
#include <QSplitter>
#include <QTemporaryDir>
#include <QUndoStack>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <span>
#include <vector>

#include "audio/audioengine.h"
#include "audio/sampledoc.h"
#include "audio/sampleimport.h"
#include "checks/support/audioengineaccess.h"
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

class ScopedNullAudioBackend final
{
  public:
    ScopedNullAudioBackend()
        : m_wasSet(qEnvironmentVariableIsSet("PORYDAW_AUDIO_BACKEND"))
        , m_previous(qgetenv("PORYDAW_AUDIO_BACKEND"))
    {
        qputenv("PORYDAW_AUDIO_BACKEND", "null");
    }

    ~ScopedNullAudioBackend()
    {
        if (m_wasSet)
            qputenv("PORYDAW_AUDIO_BACKEND", m_previous);
        else
            qunsetenv("PORYDAW_AUDIO_BACKEND");
    }

  private:
    bool m_wasSet;
    QByteArray m_previous;
};

} // namespace

namespace samplecheck {

void SampleProcessingTest::pipelinePrefillCollision()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "pipeline-prefill scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "pipeline-prefill synthetic project is created");
    const QString registeredSampleName = QStringLiteral("samplecheck_tone");
    const QByteArray preparedWav = preparedSampleWav();
    QString error;
    QVERIFY2(SampleRegistrar::registerSample(root, registeredSampleName, preparedWav, &error),
             qPrintable(error));
    ImportedSample prepared;
    QVERIFY2(importAudioFile(root + QStringLiteral("/sound/direct_sound_samples/") +
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
    QVERIFY2(nameEdit && addButton && status, "pipeline prefill widgets found");
    QVERIFY2(nameEdit->text() == registeredSampleName, "name prefilled from the source file");
    QVERIFY2(!addButton->isEnabled(), "collision disables the commit");
    QVERIFY2(!status->text().isEmpty(), "collision displays validation status");
    nameEdit->setText(QStringLiteral("fresh_tone"));
    QVERIFY2(addButton->isEnabled(), "valid name enables the commit");
    QVERIFY2(!status->text().isEmpty(), "valid name displays registration status");
    QVERIFY2(dialog.sampleName() == QStringLiteral("fresh_tone"),
             "sampleName returns the edited name");
    nameEdit->setText(QStringLiteral("Bad Name"));
    QVERIFY2(!addButton->isEnabled(), "bad grammar disables the commit");
}

void SampleProcessingTest::pipelinePreparedDefaults()
{
    ImportedSample prepared;
    QString error;
    QVERIFY2(importAudioBytes(preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"),
                              &prepared, &error),
             qPrintable(error));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
    auto *fineTune = dialog.findChild<QDoubleSpinBox *>(QStringLiteral("sampleFineTune"));
    SampleDocument *document = dialog.document();
    QVERIFY2(baseKey && fineTune && document, "prepared pipeline controls found");
    const ProcessedSample &initial = document->processed();
    QVERIFY2(initial.freq == 15000000 && initial.size == 64 && initial.looped &&
                 initial.loopStart == 8,
             "prepared defaults keep the source header verbatim");
    QVERIFY2(baseKey->value() == 58 && std::abs(fineTune->value() - 25.0) < 1e-9,
             "key/cents prefilled from smpl");
    bool dataFaithful = true;
    for (int i = 0; i < 64; ++i)
        dataFaithful = dataFaithful && initial.s8[i] == char(qint8(i * 2 - 128));
    QVERIFY2(dataFaithful, "prepared defaults render the data verbatim");
}

void SampleProcessingTest::pipelineKeyOverride()
{
    ImportedSample prepared;
    QString error;
    QVERIFY2(importAudioBytes(preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"),
                              &prepared, &error),
             qPrintable(error));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
    SampleDocument *document = dialog.document();
    QVERIFY2(baseKey && document, "pipeline key controls found");
    baseKey->setValue(59);
    QVERIFY2(document->params().baseKey == 59 && document->params().exactPitchOverride == 0 &&
                 document->processed().freq != 15000000,
             "key edit flows into the render and drops the override");
    baseKey->setValue(58);
    QVERIFY2(document->processed().freq == 15000000,
             "restoring the source key restores the verbatim agbp");
}

void SampleProcessingTest::pipelineLoopToggle()
{
    ImportedSample prepared;
    QString error;
    QVERIFY2(importAudioBytes(preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"),
                              &prepared, &error),
             qPrintable(error));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    SampleDocument *document = dialog.document();
    QVERIFY2(loopOn && document, "pipeline loop controls found");
    loopOn->setChecked(false);
    QVERIFY2(!document->processed().looped && document->processed().size == 64,
             "loop toggle renders a one-shot");
}

void SampleProcessingTest::pipelineRateCommit_data()
{
    QTest::addColumn<double>("targetRate");
    QTest::addColumn<int>("declaredRate");
    QTest::newRow("fractional-free-entry") << 6689.5 << 6690;
}

void SampleProcessingTest::pipelineRateCommit()
{
    QFETCH(double, targetRate);
    QFETCH(int, declaredRate);
    ImportedSample prepared;
    QString error;
    QVERIFY2(importAudioBytes(preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"),
                              &prepared, &error),
             qPrintable(error));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *rateCombo = dialog.findChild<QComboBox *>(QStringLiteral("sampleRateCombo"));
    SampleDocument *document = dialog.document();
    QVERIFY2(loopOn && rateCombo && rateCombo->lineEdit() && document,
             "pipeline rate controls found");

    // The legacy oracle committed the rate after switching this prepared
    // loop to one-shot mode. Keep that precondition explicit: loop-preserving
    // renders are allowed to nudge their exact output rate so the loop length
    // lands on an integer sample.
    loopOn->setChecked(false);
    QVERIFY2(!document->processed().looped, "rate fixture is in one-shot mode");

    QLineEdit *rateEdit = rateCombo->lineEdit();
    rateEdit->selectAll();
    QTest::keyClicks(rateEdit, QString::number(targetRate));
    QVERIFY2(document->params().targetRate != targetRate,
             "typing a rate does not re-render per keystroke");
    QTest::keyClick(rateEdit, Qt::Key_Return);
    QCOMPARE(document->params().targetRate, targetRate);
    QCOMPARE(document->processed().declaredRate, quint32(declaredRate));
    QVERIFY2(document->params().exactPitchOverride == 0, "rate edit drops the verbatim agbp");
    rateCombo->setCurrentIndex(1);
    rateCombo->setCurrentIndex(0);
    QVERIFY2(document->params().targetRate == document->source().sampleRate,
             "preset pick applies and restores the source rate");
}

void SampleProcessingTest::pipelineCropNormalize()
{
    ImportedSample prepared;
    QString error;
    QVERIFY2(importAudioBytes(preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"),
                              &prepared, &error),
             qPrintable(error));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *cropEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropEnd"));
    auto *normalize = dialog.findChild<QComboBox *>(QStringLiteral("sampleNormalizeMode"));
    SampleDocument *document = dialog.document();
    QVERIFY2(loopOn && cropEnd && normalize && document, "pipeline crop controls found");
    loopOn->setChecked(false);
    cropEnd->setValue(32);
    QVERIFY2(document->processed().size == 32, "crop end trims the one-shot render");
    normalize->setCurrentIndex(2);
    QVERIFY2(document->params().normalizeMode == SampleEditParams::NormalizeOneShot &&
                 document->processed().normalizeGain != 1.0,
             "normalize mode applies gain to the render");
}

void SampleProcessingTest::editorDrag()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-drag scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-drag synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    WaveformView *wave = dialog.waveform();
    SampleDocument *document = dialog.document();
    QUndoStack *undo = dialog.undoStack();
    QVERIFY2(wave && document && undo && wave->width() > 200, "waveform view laid out");
    QVERIFY2(document->params().loopOn && document->params().loopStart == 2000,
             "hi-res fixture opens with its smpl loop");
    const QPoint fromPoint = wave->handlePoint(WaveformView::LoopStartHandle);
    const QPoint toPoint(wave->xForSample(3000), fromPoint.y());
    checks::events::sendMouse(*wave, QEvent::MouseButtonPress, QPointF(fromPoint), Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    const QPoint midpoint = (fromPoint + toPoint) / 2;
    checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(midpoint), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(toPoint), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*wave, QEvent::MouseButtonRelease, QPointF(toPoint), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QVERIFY2(std::llabs(document->params().loopStart - 3000) <= 40,
             "loop-start handle drag lands near the target");
    QVERIFY2(undo->count() == 1, "handle drag is one undo entry");
    QVERIFY2(document->processed().looped && document->processed().seam.valid,
             "drag re-renders with live seam metrics");
    undo->undo();
    QVERIFY2(document->params().loopStart == 2000, "undo restores the pre-drag loop");
    undo->redo();
    QVERIFY2(std::llabs(document->params().loopStart - 3000) <= 40, "redo re-applies the drag");
}

void SampleProcessingTest::editorPitchAdoption()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-pitch scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-pitch synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    auto *pitchApply = dialog.findChild<QPushButton *>(QStringLiteral("samplePitchApply"));
    auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
    auto *fineTune = dialog.findChild<QDoubleSpinBox *>(QStringLiteral("sampleFineTune"));
    QUndoStack *undo = dialog.undoStack();
    QVERIFY2(pitchApply && baseKey && fineTune && undo, "pitch widgets found");
    QVERIFY2(pitchApply->isVisible(), "metadata/detection mismatch exposes an adopt action");
    pitchApply->click();
    QVERIFY2(baseKey->value() == 57 && std::abs(fineTune->value() - 3.93) < 1.5 &&
                 undo->count() == 1,
             "the button adopts the detected pitch as one undo entry");
    QVERIFY2(!pitchApply->isVisible(), "agreement hides the detect chrome");
}

void SampleProcessingTest::editorLoopPopulate()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-populate scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-populate synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    SampleDocument *document = dialog.document();
    QUndoStack *undo = dialog.undoStack();
    auto *group = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *loopBody = dialog.findChild<QWidget *>(QStringLiteral("sampleLoopBody"));
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    QVERIFY2(document && undo && group && loopBody && loopStart && loopEnd && badge,
             "loop-populate widgets found");
    QVERIFY2(loopBody->isVisible(), "loop body shows while looped");
    group->setChecked(false);
    QVERIFY2(!document->params().loopOn && !loopBody->isVisible(),
             "unchecking the group hides the loop chrome");
    loopEnd->setValue(0);
    loopStart->setValue(0);
    QVERIFY2(undo->count() == 3, "loop reset landed");
    group->setChecked(true);
    QVERIFY2(document->params().loopOn &&
                 document->params().loopStart != document->params().loopEnd,
             "re-enabling seeds a loop");
    QVERIFY2(undo->count() == 4, "auto-populate is one undo entry");
    QVERIFY2(!document->params().crossfadeOn, "clean tone needs no crossfade bake");
    const ProcessedSample &out = document->processed();
    QVERIFY2(out.looped && out.seam.valid && out.seam.ampLsb <= 2 && out.seam.derivLsb <= 3 &&
                 (!out.seam.nccValid || out.seam.ncc >= 0.95),
             "auto-populated loop is clean");
    QVERIFY2(badge->isVisible(), "clean loop exposes seam status");
    QVERIFY2(loopBody->isVisible(), "loop chrome is back");
    undo->undo();
    QVERIFY2(!document->params().loopOn, "undo re-disables the auto-populated loop");
    undo->redo();
    QVERIFY2(document->params().loopOn, "redo re-enables it");
    auto *tryLoop = dialog.findChild<QPushButton *>(QStringLiteral("sampleTryLoop"));
    QVERIFY2(tryLoop, "try-another button found");
    tryLoop->click();
    QVERIFY2(document->params().loopOn && document->processed().looped,
             "try-another keeps a valid loop");
}

void SampleProcessingTest::editorLoopRefine()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-refine scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-refine synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    SampleDocument *document = dialog.document();
    QUndoStack *undo = dialog.undoStack();
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    auto *refine = dialog.findChild<QPushButton *>(QStringLiteral("sampleRefineLoop"));
    QVERIFY2(document && undo && loopStart && loopEnd && badge && refine, "refine widgets found");
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    QVERIFY2(document->processed().seam.valid && badge->isVisible() &&
                 (document->processed().seam.ampLsb > 2 || document->processed().seam.derivLsb > 3),
             "misaligned loop exposes non-clean seam metrics");
    const double nccBeforeRefine = document->processed().seam.ncc;
    const int undoBeforeRefine = undo->count();
    refine->click();
    QVERIFY2(document->processed().seam.ncc >= nccBeforeRefine - 0.02,
             "refine keeps the seam at least as clean");
    QVERIFY2(undo->count() >= undoBeforeRefine && undo->count() <= undoBeforeRefine + 1,
             "refine contributes at most one undo entry");
}

void SampleProcessingTest::editorCrossfade()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-crossfade scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-crossfade synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    WaveformView *wave = dialog.waveform();
    SampleDocument *document = dialog.document();
    QUndoStack *undo = dialog.undoStack();
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *crossfade = dialog.findChild<QCheckBox *>(QStringLiteral("sampleCrossfade"));
    QVERIFY2(wave && document && undo && loopStart && loopEnd && crossfade,
             "crossfade controls found");
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    const std::vector<float> endBefore = wave->seamEndWindow();
    const std::vector<float> startBefore = wave->seamStartWindow();
    QVERIFY2(!endBefore.empty() && endBefore.size() == startBefore.size(),
             "looped render feeds the seam overlay");
    const int undoBeforeCrossfade = undo->count();
    crossfade->setChecked(true);
    QVERIFY2(document->params().crossfadeOn && undo->count() == undoBeforeCrossfade + 1,
             "crossfade toggle is undoable");
    QVERIFY2(wave->seamEndWindow() != endBefore || wave->seamStartWindow() != startBefore,
             "crossfade bake reshapes the seam overlay");
    crossfade->setChecked(false);
}

void SampleProcessingTest::editorAuditionStrip()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-strip scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-strip synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    auto *play = dialog.findChild<QPushButton *>(QStringLiteral("sampleAuditionPlay"));
    QVERIFY2(play && !play->isEnabled(), "audition strip disabled without audio");
}

void SampleProcessingTest::editorUndo()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-undo scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-undo synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    SampleDocument *document = dialog.document();
    QUndoStack *undo = dialog.undoStack();
    auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
    QVERIFY2(document && undo && baseKey, "undo controls found");
    baseKey->setValue(57);
    QVERIFY2(undo->count() == 1, "key edit creates an undo entry");
    while (undo->canUndo())
        undo->undo();
    QVERIFY2(document->params() == SampleDocument::defaultParams(hiRes),
             "full undo restores the import defaults");
    while (undo->canRedo())
        undo->redo();
    QVERIFY2(document->params().baseKey == 57, "full redo restores the edited state");
}

void SampleProcessingTest::editorScroll()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-scroll scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-scroll synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY2(scroll, "control-column scroll area found");
    dialog.resize(900, 280);
    QApplication::processEvents();
    QVERIFY2(scroll->verticalScrollBar()->maximum() > 0, "short window scrolls the controls");
    dialog.resize(900, 640);
    QApplication::processEvents();
}

void SampleProcessingTest::editorSplitter()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-splitter scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-splitter synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    WaveformView *wave = dialog.waveform();
    auto *split = dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit"));
    QVERIFY2(wave && split, "waveform splitter found");
    const int tall = wave->height();
    split->setSizes({wave->minimumSizeHint().height(), 10000});
    QApplication::processEvents();
    QVERIFY2(wave->height() < tall, "splitter drag shrinks the waveform");
    split->setSizes({10000, split->sizes().value(1)});
    QApplication::processEvents();
}

void SampleProcessingTest::editorCommit()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "editor-commit scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "editor-commit synthetic project is created");
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(hiRes, [&](const QString &name, QString *validationError) {
        return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
    });
    auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    auto *baseKey = dialog.findChild<QSpinBox *>(QStringLiteral("sampleBaseKey"));
    SampleDocument *document = dialog.document();
    QVERIFY2(nameEdit && document && baseKey, "commit controls found");
    baseKey->setValue(57);
    QVERIFY2(document->params().baseKey == 57 && document->params().exactPitchOverride == 0,
             "commit preserves edited render parameters");
    nameEdit->setText(QStringLiteral("phase3_tone"));
    const QByteArray incBefore = readFileBytes(incPath);
    QString error;
    QVERIFY2(SampleRegistrar::registerSample(root, dialog.sampleName(), dialog.wavBytes(), &error),
             qPrintable(error));
    QVERIFY2(readFileBytes(incPath) ==
                 incBefore +
                     QByteArray("\n\t.align 2\n"
                                "DirectSoundWaveData_phase3_tone::\n"
                                "\t.incbin \"sound/direct_sound_samples/phase3_tone.bin\"\n"),
             "commit appends exactly the registration block");
    QVERIFY(writeFile(
        root + QStringLiteral("/sound/voicegroups/voicegroup_phase3.inc"),
        "voicegroup_phase3::\n"
        "\tvoice_directsound 60, 0, DirectSoundWaveData_phase3_tone, 255, 0, 255, 165\n"));
    const QByteArray rootUtf8 = root.toLocal8Bit();
    std::unique_ptr<LoadedVoiceGroup, decltype(&voicegroup_free)> voicegroup(
        voicegroup_load(rootUtf8.constData(), "voicegroup_phase3", nullptr), voicegroup_free);
    QVERIFY2(voicegroup, "phase-3 voicegroup resolves");
    const ProcessedSample &out = document->processed();
    const WaveData *wave = voicegroup->voices[0].wav;
    QVERIFY2(wave && wave->freq == out.freq && wave->loopStart == out.loopStart &&
                 wave->size == out.size && wave->status == (out.looped ? 0x4000 : 0) &&
                 wave->data && std::memcmp(wave->data, out.s8.constData(), out.size) == 0,
             "committed sample loads back identical (audition == build)");
}

void SampleProcessingTest::spaceAudition()
{
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));

    // Use the required production null backend, then park its callback so
    // the actual AudioEngine process path can be rendered deterministically.
    ScopedNullAudioBackend nullBackend;
    AudioEngine engine;
    QString audioError;
    QVERIFY2(engine.init(&audioError), qPrintable(audioError));
    QVERIFY2(engine.nullBackendForced() && engine.usingNullBackend(),
             "Space audition uses the required production null backend");
    QVERIFY2(checks::AudioEngineTestAccess::parkDevice(engine),
             "Space audition parks the null device for deterministic PCM capture");

    const auto renderFrames = [&](uint32_t frames) {
        auto pcm = std::vector<float>(static_cast<std::size_t>(frames) * 2);
        checks::AudioEngineTestAccess::renderParked(engine, std::span<float>(pcm));
        return pcm;
    };
    const auto renderSeconds = [&](double seconds) {
        const auto frames =
            std::max(uint32_t{1}, uint32_t(std::ceil(seconds * engine.sampleRate())));
        return renderFrames(frames);
    };
    const auto peak = [](const std::vector<float> &pcm) {
        auto result = 0.0;
        for (const float sample : pcm)
            result = std::max(result, std::abs(double(sample)));
        return result;
    };

    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; }, &engine);
    dialog.resize(900, 640);
    dialog.show();
    QApplication::processEvents();
    auto *play = dialog.findChild<QPushButton *>(QStringLiteral("sampleAuditionPlay"));
    auto *auditionNameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    auto *keySpin = dialog.findChild<QSpinBox *>(QStringLiteral("sampleAuditionKey"));
    QVERIFY2(play && play->isEnabled() && auditionNameEdit && keySpin,
             "audition controls are enabled by a live AudioEngine");
    const QString idlePresentation = play->text();
    const auto idlePcm = renderFrames(512);
    QVERIFY2(peak(idlePcm) <= 1.0e-7, "parked engine is silent before the Space audition");

    sendSpaceStroke(dialog, Qt::NoModifier, false);
    const auto startedPcm = renderSeconds(0.25);
    QVERIFY2(peak(startedPcm) >= 0.01 && rmsOf(startedPcm, 0, startedPcm.size()) >= 0.001,
             "Space produces sustained non-silent PCM through the production audition engine");
    QVERIFY2(play->text() != idlePresentation, "Space starts an engine-backed audition");
    sendSpaceStroke(dialog, Qt::NoModifier, false);
    renderSeconds(2.0); // drain the real release envelope
    const auto stoppedPcm = renderFrames(512);
    QVERIFY2(peak(stoppedPcm) <= 1.0e-7, "Space stop leaves digitally silent engine output");
    QCOMPARE(play->text(), idlePresentation);

    const QString nameBefore = auditionNameEdit->text();
    sendSpaceStroke(*auditionNameEdit, Qt::NoModifier, false);
    const auto focusedPcm = renderSeconds(0.25);
    QVERIFY2(peak(focusedPcm) >= 0.01 && rmsOf(focusedPcm, 0, focusedPcm.size()) >= 0.001,
             "Space in the name field reaches the production audition engine");
    QCOMPARE(auditionNameEdit->text(), nameBefore);
    sendSpaceStroke(*keySpin, Qt::NoModifier, false);
    renderSeconds(2.0); // drain the real release envelope
    const auto focusedStopPcm = renderFrames(512);
    QVERIFY2(peak(focusedStopPcm) <= 1.0e-7, "Space on the key spin box stops the audition output");

    sendSpaceStroke(dialog, Qt::ControlModifier, false);
    sendSpaceStroke(dialog, Qt::NoModifier, true);
    const auto ignoredPcm = renderFrames(512);
    QVERIFY2(peak(ignoredPcm) <= 1.0e-7,
             "modified and auto-repeat Space do not restart audition output");
    QCOMPARE(play->text(), idlePresentation);
}

} // namespace samplecheck
