#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QAbstractItemModel>
#include <QApplication>
#include <QByteArray>
#include <QCheckBox>
#include <QComboBox>
#include <QFileInfo>
#include <QLabel>
#include <QLineEdit>
#include <QListView>
#include <QPushButton>
#include <QSettings>
#include <QSignalSpy>
#include <QSpinBox>
#include <QTemporaryDir>
#include <QtTest>

#include <cmath>
#include <cstdint>
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
#include "ui/soundbrowser/samplelibrarypanel.h"
#include "ui/soundbrowser/soundbrowser.h"

namespace {

// The panel persists through default-constructed QSettings. Save every
// process-global setting that this scope changes, redirect Ini UserScope to
// scratch storage, and restore the actual prior Ini base directory.
class ScopedTestSettings final
{
  public:
    ScopedTestSettings()
        : m_defaultFormat(QSettings::defaultFormat())
        , m_organization(QCoreApplication::organizationName())
        , m_application(QCoreApplication::applicationName())
    {
        const QSettings probe(QSettings::IniFormat, QSettings::UserScope,
                              QStringLiteral("__porydaw_settings_probe__"),
                              QStringLiteral("sample-library"));
        QDir base = QFileInfo(probe.fileName()).absoluteDir();
        base.cdUp();
        m_iniUserPath = base.absolutePath();

        QVERIFY2(m_directory.isValid(), "settings scratch directory is available");
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QCoreApplication::setOrganizationName(QStringLiteral("porydaw-checks"));
        QCoreApplication::setApplicationName(QStringLiteral("sample-library"));
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_directory.path());
    }

    ~ScopedTestSettings()
    {
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_iniUserPath);
        QSettings::setDefaultFormat(m_defaultFormat);
        QCoreApplication::setOrganizationName(m_organization);
        QCoreApplication::setApplicationName(m_application);
    }

  private:
    QSettings::Format m_defaultFormat;
    QString m_organization;
    QString m_application;
    QString m_iniUserPath;
    QTemporaryDir m_directory;
};

std::vector<float> renderSeconds(AudioEngine &engine, double seconds)
{
    const auto frames = std::max(uint32_t{1}, uint32_t(std::ceil(seconds * engine.sampleRate())));
    std::vector<float> pcm(static_cast<std::size_t>(frames) * 2);
    checks::AudioEngineTestAccess::renderParked(engine, std::span<float>(pcm));
    return pcm;
}

double peakOf(const std::vector<float> &pcm)
{
    double result = 0.0;
    for (const float sample : pcm)
        result = std::max(result, std::abs(double(sample)));
    return result;
}

void sendSpaceStroke(QObject &target)
{
    checks::events::sendKey(target, QEvent::KeyPress, Qt::Key_Space, Qt::NoModifier,
                            QStringLiteral(" "), false, 1);
    checks::events::sendKey(target, QEvent::KeyRelease, Qt::Key_Space, Qt::NoModifier,
                            QStringLiteral(" "), false, 1);
}

// A long tone for browse-preview capture: short fixtures would end before
// the ownership assertions render.
QByteArray longToneWav()
{
    auto spec = FixtureSpec{};
    spec.bits = 16;
    spec.rate = 22050;
    spec.withSmpl = false;
    const int frames = 22050 * 12;
    for (int i = 0; i < frames; ++i) {
        const double value = 0.5 * std::sin(2.0 * 3.14159265358979323846 * 220.0 * i / 22050.0);
        putU16(&spec.samples, quint16(qint16(std::lround(value * 32000.0))));
    }
    return fixtureWav(spec);
}

QModelIndex findRow(QAbstractItemModel *model, const QModelIndex &root, const QString &fileName)
{
    for (int row = 0; row < model->rowCount(root); ++row) {
        const QModelIndex index = model->index(row, 0, root);
        if (index.data().toString() == fileName)
            return index;
    }
    return QModelIndex();
}

} // namespace

namespace samplecheck {

void SampleProcessingTest::libraryFolders()
{
    ScopedTestSettings settings;
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "library-folders scratch directory is available");
    const QString lib = scratch.filePath(QStringLiteral("lib"));
    QVERIFY(QDir().mkpath(lib + QStringLiteral("/sub")));
    QVERIFY(writeFile(lib + QStringLiteral("/tone.wav"), preparedSampleWav()));
    QVERIFY(writeFile(lib + QStringLiteral("/LOUDER.MP3"), preparedSampleWav()));
    QVERIFY(writeFile(lib + QStringLiteral("/notes.txt"), QByteArray("not audio")));
    QVERIFY(writeFile(lib + QStringLiteral("/font.sf2"), QByteArray("not a soundfont")));
    QVERIFY(writeFile(lib + QStringLiteral("/sub/inner.wav"), preparedSampleWav()));

    SampleLibraryPanel panel;
    // Normalization and dedupe: trailing dots, repeats and dot-dots
    // collapse to one absolute clean path.
    panel.setFolders({lib + QStringLiteral("/./"), lib, lib + QStringLiteral("/sub/..")});
    const QString clean = QDir::cleanPath(QDir(lib).absolutePath());
    QCOMPARE(panel.savedFolders(), QStringList({clean}));
    // Persistence across recreation through the shared settings key.
    {
        SampleLibraryPanel recreated;
        QCOMPARE(recreated.savedFolders(), QStringList({clean}));
    }

    auto *files = panel.findChild<QListView *>(QStringLiteral("sampleLibraryFiles"));
    auto *status = panel.findChild<QLabel *>(QStringLiteral("sampleLibraryStatus"));
    QVERIFY2(files && status, "library file list and status found");
    panel.show();
    QApplication::processEvents();
    QAbstractItemModel *model = files->model();
    QVERIFY(model);
    const QModelIndex root = files->rootIndex();
    QTRY_VERIFY_WITH_TIMEOUT((model->rowCount(root) > 0), 5000);
    QTRY_VERIFY_WITH_TIMEOUT((findRow(model, root, QStringLiteral("tone.wav")).isValid()), 5000);

    // Case-insensitive audio filtering drops notes/soundfonts from the
    // visible rows but keeps navigable subdirectories and upper-case
    // suffixes.
    QCOMPARE(model->rowCount(root), 3);
    QVERIFY(findRow(model, root, QStringLiteral("LOUDER.MP3")).isValid());
    QVERIFY(findRow(model, root, QStringLiteral("tone.wav")).isValid());
    const QPersistentModelIndex subRow(findRow(model, root, QStringLiteral("sub")));
    QVERIFY(subRow.isValid());
    QVERIFY(!findRow(model, root, QStringLiteral("notes.txt")).isValid());
    QVERIFY(!findRow(model, root, QStringLiteral("font.sf2")).isValid());

    // Distinct preview/load actions on a file row.
    QSignalSpy preview(&panel, &SampleLibraryPanel::previewRequested);
    QSignalSpy load(&panel, &SampleLibraryPanel::loadRequested);
    QVERIFY(preview.isValid() && load.isValid());
    // QFileSystemModel populates asynchronously; persistent indexes survive
    // the listing update while the test waits for the row.
    const QPersistentModelIndex toneRow(
        findRow(model, files->rootIndex(), QStringLiteral("tone.wav")));
    files->scrollTo(toneRow);
    QApplication::processEvents();
    QTest::mouseClick(files->viewport(), Qt::LeftButton, Qt::NoModifier,
                      files->visualRect(toneRow).center());
    QCOMPARE(preview.count(), 1);
    QCOMPARE(load.count(), 0);
    QCOMPARE(preview.constFirst().constFirst().toString(),
             QFileInfo(lib + QStringLiteral("/tone.wav")).absoluteFilePath());
    preview.clear();
    QTest::mouseDClick(files->viewport(), Qt::LeftButton, Qt::NoModifier,
                       files->visualRect(toneRow).center());
    QCOMPARE(load.count(), 1);
    QCOMPARE(load.constFirst().constFirst().toString(),
             QFileInfo(lib + QStringLiteral("/tone.wav")).absoluteFilePath());

    // Direct-child navigation in place, then back out with Up. A single
    // click drives the real clicked path (the panel navigates on click);
    // QTest::mouseDClick alone would not emit clicked first.
    QTest::mouseClick(files->viewport(), Qt::LeftButton, Qt::NoModifier,
                      files->visualRect(subRow).center());
    QTRY_VERIFY_WITH_TIMEOUT(
        (findRow(model, files->rootIndex(), QStringLiteral("inner.wav")).isValid()), 5000);
    QCOMPARE(model->rowCount(files->rootIndex()), 1);
    QVERIFY(!findRow(model, files->rootIndex(), QStringLiteral("tone.wav")).isValid());
    auto *up = panel.findChild<QPushButton *>(QStringLiteral("sampleLibraryUp"));
    QVERIFY(up);
    up->click();
    QTRY_VERIFY_WITH_TIMEOUT(
        (findRow(model, files->rootIndex(), QStringLiteral("tone.wav")).isValid()), 5000);
    QCOMPARE(model->rowCount(files->rootIndex()), 3);

    // Removal drops the folder; a missing folder stays listed with a
    // visible notice instead of being silently dropped.
    const QString lib2 = scratch.filePath(QStringLiteral("lib2"));
    QVERIFY(QDir().mkpath(lib2));
    panel.setFolders({clean, lib2});
    QCOMPARE(panel.savedFolders().size(), 2);
    panel.setFolders({clean});
    QCOMPARE(panel.savedFolders(), QStringList({clean}));
    panel.setFolders({scratch.filePath(QStringLiteral("gone"))});
    QVERIFY2(!status->text().isEmpty(), "missing folder produces a visible notice");
}

void SampleProcessingTest::librarySourceLoad()
{
    ScopedTestSettings settings;
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "library-load scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "library-load synthetic project is created");
    const QString srcPath = scratch.filePath(QStringLiteral("sources/hires_tone.wav"));
    const QByteArray firstBytes = hiResSampleWav();
    QVERIFY(writeFile(srcPath, firstBytes));

    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);
    SampleEditorDialog dialog(
        [&](const QString &name, QString *validationError) {
            return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
        },
        m_audio.engine(), m_audio.browser());
    auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
    auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    QVERIFY2(addButton && nameEdit, "library load commit controls found");
    auto *playButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAuditionPlay"));
    auto *cropEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropEnd"));
    auto *normalize = dialog.findChild<QComboBox *>(QStringLiteral("sampleNormalizeMode"));
    QVERIFY2(playButton && cropEnd && normalize, "source-dependent controls found");
    QVERIFY2(!addButton->isEnabled(), "a source-less dialog cannot commit");
    QVERIFY2(!playButton->isEnabled(), "a source-less dialog cannot play a document");

    QString error;
    QVERIFY2(dialog.loadLibrarySample(srcPath, &error), qPrintable(error));
    QCOMPARE(dialog.loadedSourceSha256(), SampleRegistrar::sourceHashHex(firstBytes));
    QCOMPARE(dialog.loadedSourcePath(), QFileInfo(srcPath).absoluteFilePath());
    QCOMPARE(nameEdit->text(), QStringLiteral("hires_tone"));
    QVERIFY2(addButton->isEnabled(), "a successful load enables the commit");
    QVERIFY2(dialog.undoStack()->count() == 0, "a load resets the undo stack");
    QVERIFY2(playButton->isEnabled(), "a successful load enables document audition");
    QCOMPARE(cropEnd->maximum(), int(dialog.document()->source().frameCount()));

    // Tweak, then load a second source: undo, loop chrome and the name
    // follow the new source while a corrupt load preserves everything.
    SampleEditParams tweaked = dialog.document()->params();
    tweaked.loopOn = true;
    tweaked.baseKey = 40;
    dialog.applyParamsExternal(tweaked);
    const QString secondPath = scratch.filePath(QStringLiteral("sources/prepared_tone.wav"));
    const QByteArray secondBytes = preparedSampleWav();
    QVERIFY(writeFile(secondPath, secondBytes));
    QVERIFY2(dialog.loadLibrarySample(secondPath, &error), qPrintable(error));
    auto *sourceName = dialog.findChild<QLabel *>(QStringLiteral("sampleSourceName"));
    QVERIFY(sourceName);
    QCOMPARE(sourceName->text(), QFileInfo(secondPath).fileName());
    QCOMPARE(sourceName->toolTip(), QFileInfo(secondPath).absoluteFilePath());
    QVERIFY2(dialog.undoStack()->count() == 0, "a second load clears the undo stack again");
    QCOMPARE(nameEdit->text(), QStringLiteral("prepared_tone"));
    QCOMPARE(cropEnd->maximum(), int(dialog.document()->source().frameCount()));
    QCOMPARE(dialog.loadedSourceSha256(), SampleRegistrar::sourceHashHex(secondBytes));
    QVERIFY(dialog.document()->source().exactPitch != 0);
    normalize->setCurrentIndex(normalize->currentIndex() == 0 ? 1 : 0);
    QCOMPARE(dialog.document()->params().exactPitchOverride,
             dialog.document()->source().exactPitch);
    auto *loopCheck = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopCheck);
    QCOMPARE(dialog.document()->params().loopOn, dialog.document()->source().hasLoop);

    const qint64 framesBefore = dialog.document()->source().frameCount();
    const QString pathBefore = dialog.loadedSourcePath();
    const QString shaBefore = dialog.loadedSourceSha256();
    const QString nameBefore = nameEdit->text();
    const int undoBefore = dialog.undoStack()->count();
    const QString badPath = scratch.filePath(QStringLiteral("sources/bad_tone.wav"));
    QVERIFY(writeFile(badPath, QByteArray("not audio bytes")));
    QVERIFY2(!dialog.loadLibrarySample(badPath, &error), "a corrupt file fails the load");
    QVERIFY2(!error.isEmpty(), "a failed load reports an error");
    QCOMPARE(dialog.document()->source().frameCount(), framesBefore);
    QCOMPARE(dialog.loadedSourcePath(), pathBefore);
    QCOMPARE(dialog.loadedSourceSha256(), shaBefore);
    QCOMPARE(nameEdit->text(), nameBefore);
    QCOMPARE(dialog.undoStack()->count(), undoBefore);

    // A locked registered edit target keeps its name across loads.
    ImportedSample hiRes;
    QVERIFY2(importAudioBytes(firstBytes, QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
             qPrintable(error));
    SampleEditorDialog editDialog(
        hiRes,
        [](const QString &candidate, QString *refusal) {
            if (candidate == QStringLiteral("locked_tone"))
                return true;
            if (refusal)
                *refusal = QStringLiteral("the sample keeps its registered name.");
            return false;
        },
        m_audio.engine(), m_audio.browser());
    editDialog.setEditTarget(QStringLiteral("locked_tone"));
    QVERIFY2(editDialog.loadLibrarySample(secondPath, &error), qPrintable(error));
    auto *editName = editDialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    QVERIFY2(editName && editName->text() == QStringLiteral("locked_tone"),
             "a locked edit target keeps its name");
    QCOMPARE(editDialog.loadedSourceSha256(), SampleRegistrar::sourceHashHex(secondBytes));
}

void SampleProcessingTest::libraryPreviewIsolation()
{
    ScopedTestSettings settings;
    AudioEngine &engine = m_audio.engine();

    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "library-preview scratch directory is available");
    const QString previewPath = scratch.filePath(QStringLiteral("sources/long_tone.wav"));
    const QByteArray previewBytes = longToneWav();
    QVERIFY(writeFile(previewPath, previewBytes));

    ImportedSample docSource;
    QString error;
    QVERIFY2(importAudioBytes(previewBytes, previewPath, &docSource, &error), qPrintable(error));
    soundbrowser::SoundBrowser &browser = m_audio.browser();
    SampleEditorDialog dialog(
        docSource, [](const QString &, QString *) { return true; }, engine, browser);
    SampleEditorDialog other(
        docSource, [](const QString &, QString *) { return true; }, engine, browser);
    dialog.show();
    other.show();
    QApplication::processEvents();

    const SampleEditParams paramsBefore = dialog.document()->params();
    dialog.previewLibrarySample(previewPath);
    QVERIFY2(peakOf(renderSeconds(engine, 0.3)) >= 0.01, "library preview renders");
    // Preview never touches the edited document or its provenance.
    QVERIFY2(dialog.document()->params() == paramsBefore,
             "library preview leaves the edited document alone");
    QVERIFY(dialog.loadedSourcePath().isEmpty() && dialog.loadedSourceSha256().isEmpty());
    // Starting the editor's own audition stops the library preview: after
    // the own audition stops too, the long preview would still sound if it
    // had survived — silence proves the stop.
    sendSpaceStroke(dialog);
    QApplication::processEvents();
    QVERIFY2(peakOf(renderSeconds(engine, 0.5)) >= 0.01, "the editor audition sounds");
    sendSpaceStroke(dialog);
    QApplication::processEvents();
    renderSeconds(engine, 4.0); // drain the real release envelope
    QVERIFY2(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7,
             "stopping the own audition leaves silence: the preview was stopped first");

    // An idle old dialog's close must not stop a newer browse owner.
    dialog.previewLibrarySample(previewPath);
    other.previewLibrarySample(previewPath);
    QVERIFY2(peakOf(renderSeconds(engine, 0.3)) >= 0.01, "the newer preview sounds");
    dialog.reject(); // idle old owner closes: a non-owner stop is a no-op
    QApplication::processEvents();
    QVERIFY2(peakOf(renderSeconds(engine, 0.3)) >= 0.01,
             "closing the displaced dialog leaves the newer preview sounding");
    other.reject();
    renderSeconds(engine, 4.0);
    QVERIFY2(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7,
             "closing the owning dialog releases its preview");
}

void SampleProcessingTest::librarySaveAsNew()
{
    ScopedTestSettings settings;
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "library-saveasnew scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "library-saveasnew synthetic project is created");
    QString error;
    QVERIFY2(SampleRegistrar::registerSample(root, QStringLiteral("orig_tone"), preparedSampleWav(),
                                             &error),
             qPrintable(error));
    const QStringList symbols = VoicegroupSource::directSoundSymbols(root);

    ImportedSample hiRes;
    QVERIFY2(
        importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
        qPrintable(error));
    SampleEditorDialog dialog(
        hiRes,
        [](const QString &candidate, QString *refusal) {
            if (candidate == QStringLiteral("orig_tone"))
                return true;
            if (refusal)
                *refusal = QStringLiteral("the sample keeps its registered name.");
            return false;
        },
        m_audio.engine(), m_audio.browser());
    dialog.setEditTarget(
        QStringLiteral("orig_tone"), [&](const QString &name, QString *validationError) {
            return SampleRegistrar::validateSampleName(root, name, symbols, validationError);
        });
    auto *saveAsNewButton =
        dialog.findChild<QPushButton *>(QStringLiteral("sampleSaveAsNewButton"));
    auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
    QVERIFY2(saveAsNewButton && nameEdit && addButton, "save-as-new controls found");
    dialog.show();
    QApplication::processEvents();
    QVERIFY2(saveAsNewButton->isVisible(), "the validator overload offers Save as New");

    saveAsNewButton->click();
    QVERIFY2(!nameEdit->isReadOnly(), "save as new unlocks the name");
    QCOMPARE(nameEdit->text(), QStringLiteral("orig_tone_copy"));
    QVERIFY2(addButton->isEnabled(), "the validated suggestion enables the commit");

    // An occupied name is rejected; a fresh one accepted.
    nameEdit->setText(QStringLiteral("orig_tone"));
    QVERIFY2(!addButton->isEnabled(), "the occupied original name is rejected");
    nameEdit->setText(QStringLiteral("brand_new"));
    QVERIFY2(addButton->isEnabled(), "a fresh name is accepted");
    QCOMPARE(dialog.sampleName(), QStringLiteral("brand_new"));

    // Repeated activation never appends another "_copy".
    dialog.saveAsNew();
    QCOMPARE(nameEdit->text(), QStringLiteral("orig_tone_copy"));

    const QString replacement = scratch.filePath(QStringLiteral("replacement.wav"));
    QVERIFY(writeFile(replacement, preparedSampleWav()));
    QVERIFY2(dialog.loadLibrarySample(replacement, &error), qPrintable(error));
    QCOMPARE(dialog.sampleName(), QStringLiteral("replacement"));

    // The single-argument form stays update-only: no Save as New offer.
    SampleEditorDialog locked(
        hiRes,
        [](const QString &candidate, QString *) {
            return candidate == QStringLiteral("orig_tone");
        },
        m_audio.engine(), m_audio.browser());
    locked.show();
    QApplication::processEvents();
    auto *lockedButton = locked.findChild<QPushButton *>(QStringLiteral("sampleSaveAsNewButton"));
    QVERIFY2(lockedButton && !lockedButton->isVisible(),
             "the single-argument edit target never offers Save as New");
}

} // namespace samplecheck
