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
#include <QSplitter>
#include <QTemporaryDir>
#include <QTreeWidget>
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
    QVERIFY(scratch.isValid());
    const QString lib = scratch.filePath(QStringLiteral("lib"));
    QVERIFY(QDir().mkpath(lib + QStringLiteral("/sub")));
    for (const QString &suffix :
         {QStringLiteral("wav"), QStringLiteral("AIF"), QStringLiteral("aiff"),
          QStringLiteral("MP3"), QStringLiteral("flac"), QStringLiteral("ogg")})
        QVERIFY(writeFile(lib + QStringLiteral("/tone.") + suffix, preparedSampleWav()));
    QVERIFY(writeFile(lib + QStringLiteral("/notes.txt"), QByteArray("not audio")));
    QVERIFY(writeFile(lib + QStringLiteral("/font.sf2"), QByteArray("not audio")));
    QVERIFY(writeFile(lib + QStringLiteral("/sub/inner.wav"), preparedSampleWav()));
    SampleLibraryPanel panel;
    auto *files = panel.findChild<QListView *>(QStringLiteral("sampleLibraryFiles"));
    auto *folders = panel.findChild<QTreeWidget *>(QStringLiteral("sampleLibraryFolders"));
    auto *status = panel.findChild<QLabel *>(QStringLiteral("sampleLibraryStatus"));
    auto *previewButton = panel.findChild<QPushButton *>(QStringLiteral("sampleLibraryPreview"));
    auto *loadButton = panel.findChild<QPushButton *>(QStringLiteral("sampleLibraryLoad"));
    auto *remove = panel.findChild<QPushButton *>(QStringLiteral("sampleLibraryRemove"));
    QVERIFY(files && folders && status && previewButton && loadButton && remove);
    QVERIFY(!status->text().isEmpty());
    QVERIFY(!loadButton->isEnabled() && !previewButton->isEnabled() && !remove->isEnabled());
    panel.setFolders({lib + QStringLiteral("/./"), lib, lib + QStringLiteral("/sub/..")});
    const QString clean = QDir::cleanPath(QDir(lib).absolutePath());
    QCOMPARE(panel.savedFolders(), QStringList({clean}));
    {
        SampleLibraryPanel recreated;
        QCOMPARE(recreated.savedFolders(), QStringList({clean}));
    }
    panel.show();
    auto *model = files->model();
    QTRY_COMPARE_WITH_TIMEOUT(model->rowCount(files->rootIndex()), 6, 5000);
    QVERIFY(!findRow(model, files->rootIndex(), QStringLiteral("sub")).isValid());
    QVERIFY(!findRow(model, files->rootIndex(), QStringLiteral("notes.txt")).isValid());
    QVERIFY(!findRow(model, files->rootIndex(), QStringLiteral("font.sf2")).isValid());
    QVERIFY(findRow(model, files->rootIndex(), QStringLiteral("tone.MP3")).isValid());
    QVERIFY(!loadButton->isEnabled() && !previewButton->isEnabled());
    QSignalSpy preview(&panel, &SampleLibraryPanel::previewRequested);
    QSignalSpy stop(&panel, &SampleLibraryPanel::previewStopRequested);
    QSignalSpy load(&panel, &SampleLibraryPanel::loadRequested);
    const QPersistentModelIndex tone(
        findRow(model, files->rootIndex(), QStringLiteral("tone.wav")));
    QVERIFY(tone.isValid());
    files->scrollTo(tone);
    QTest::mouseClick(files->viewport(), Qt::LeftButton, Qt::NoModifier,
                      files->visualRect(tone).center());
    QCOMPARE(preview.count(), 1);
    QCOMPARE(load.count(), 0);
    QVERIFY(previewButton->isEnabled() && loadButton->isEnabled());
    previewButton->click();
    QCOMPARE(preview.count(), 2);
    QCOMPARE(preview.constFirst().constFirst().toString(), lib + QStringLiteral("/tone.wav"));
    panel.setPreviewingPath(lib + QStringLiteral("/tone.wav"));
    sendSpaceStroke(*files);
    QCOMPARE(stop.count(), 1);
    panel.setPreviewingPath(QString());
    QTest::keyClick(files, Qt::Key_Return);
    QCOMPARE(preview.count(), 3);
    QCOMPARE(load.count(), 0);
    loadButton->click();
    QCOMPARE(load.count(), 1);
    QTest::mouseDClick(files->viewport(), Qt::LeftButton, Qt::NoModifier,
                       files->visualRect(tone).center());
    QCOMPARE(load.count(), 2);
    const int previewsAfterActivation = preview.count();
    panel.showMessage(QStringLiteral("decode failed"));
    QApplication::processEvents();
    QCOMPARE(status->text(), QStringLiteral("decode failed"));
    files->setCurrentIndex(findRow(model, files->rootIndex(), QStringLiteral("tone.MP3")));
    QCOMPARE(preview.count(), previewsAfterActivation);
    QCOMPARE(load.count(), 2);
    QVERIFY(status->text() != QStringLiteral("decode failed"));
    // A pointer click replaces an existing preview, rather than merely
    // stopping it. Keyboard/current-index selection above remains silent.
    panel.setPreviewingPath(lib + QStringLiteral("/tone.wav"));
    const QModelIndex mp3 = files->currentIndex();
    files->scrollTo(mp3);
    QTest::mouseClick(files->viewport(), Qt::LeftButton, Qt::NoModifier,
                      files->visualRect(mp3).center());
    QCOMPARE(preview.count(), previewsAfterActivation + 1);
    QCOMPARE(preview.constLast().constFirst().toString(), lib + QStringLiteral("/tone.MP3"));
    QCOMPARE(stop.count(), 1);
    panel.setPreviewingPath(QString());

    // The only top-level navigation destinations are bookmarks. Descendants
    // stay under that root and never expose a parent-directory entry.
    QCOMPARE(folders->topLevelItemCount(), 1);
    auto *root = folders->topLevelItem(0);
    QCOMPARE(root->text(0), QStringLiteral("lib"));
    QCOMPARE(root->toolTip(0), clean);
    QVERIFY(root->isExpanded());
    QCOMPARE(root->childCount(), 1);
    folders->setCurrentItem(root->child(0));
    QTRY_VERIFY_WITH_TIMEOUT(
        findRow(model, files->rootIndex(), QStringLiteral("inner.wav")).isValid(), 5000);
    QVERIFY(!loadButton->isEnabled());
    folders->setCurrentItem(root);
    QTRY_COMPARE_WITH_TIMEOUT(model->rowCount(files->rootIndex()), 6, 5000);
    remove->click();
    QVERIFY(panel.savedFolders().isEmpty());
    QVERIFY(QFileInfo::exists(lib + QStringLiteral("/tone.wav")));
    QVERIFY(!files->isVisible());
    QVERIFY(!remove->isEnabled() && !loadButton->isEnabled());
    const QString empty = scratch.filePath(QStringLiteral("empty"));
    QVERIFY(QDir().mkpath(empty));
    panel.setFolders({empty});
    QTRY_VERIFY_WITH_TIMEOUT(!status->text().contains(QStringLiteral("Listing")), 5000);
    QVERIFY(!status->text().isEmpty());
    QCOMPARE(model->rowCount(files->rootIndex()), 0);
    QVERIFY(!loadButton->isEnabled() && !previewButton->isEnabled());
    panel.setFolders({scratch.filePath(QStringLiteral("gone"))});
    QVERIFY(!files->isVisible());
    QVERIFY(!status->text().isEmpty());
    QVERIFY(remove->isEnabled());
    QVERIFY(!loadButton->isEnabled() && !previewButton->isEnabled());
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
        m_audio.browser());
    auto *panel = dialog.findChild<SampleLibraryPanel *>();
    auto *outer = dialog.findChild<QSplitter *>(QStringLiteral("sampleBrowserSplit"));
    auto *editor = dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit"));
    QVERIFY(panel && outer && editor);
    QCOMPARE(outer->orientation(), Qt::Horizontal);
    QCOMPARE(outer->widget(0), panel);
    QCOMPARE(outer->widget(1), editor);
    QCOMPARE(editor->orientation(), Qt::Vertical);
    QCOMPARE(editor->count(), 2);
    QVERIFY(outer->isCollapsible(0));
    QVERIFY(!outer->isCollapsible(1));
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
    auto *loaded = panel->findChild<QLabel *>(QStringLiteral("sampleLibraryLoaded"));
    QVERIFY(loaded);
    QCOMPARE(loaded->toolTip(), QFileInfo(srcPath).absoluteFilePath());
    QVERIFY(loaded->text().contains(QFileInfo(srcPath).fileName()));
    QCOMPARE(nameEdit->text(), QStringLiteral("hires_tone"));
    QVERIFY2(addButton->isEnabled(), "a successful load enables the commit");
    QVERIFY2(dialog.undoStack()->count() == 0, "a load resets the undo stack");
    QVERIFY2(playButton->isEnabled(), "a successful load enables document audition");
    QCOMPARE(cropEnd->maximum(), int(dialog.document()->source().frameCount()));

    // Exercise routing inside the real dialog: its editor-wide Space
    // filter must not supersede the file list's explicit preview surface.
    panel->setFolders({QFileInfo(srcPath).absolutePath()});
    auto *files = panel->findChild<QListView *>(QStringLiteral("sampleLibraryFiles"));
    auto *previewSource = panel->findChild<QLabel *>(QStringLiteral("sampleLibraryPreviewing"));
    QVERIFY(files && previewSource);
    dialog.show();
    QTRY_VERIFY_WITH_TIMEOUT(
        findRow(files->model(), files->rootIndex(), QFileInfo(srcPath).fileName()).isValid(), 5000);
    files->setCurrentIndex(
        findRow(files->model(), files->rootIndex(), QFileInfo(srcPath).fileName()));
    QSignalSpy preview(panel, &SampleLibraryPanel::previewRequested);
    QSignalSpy stopPreview(panel, &SampleLibraryPanel::previewStopRequested);
    const QString idlePlayText = playButton->text();
    sendSpaceStroke(*files);
    QCOMPARE(preview.count(), 1);
    QCOMPARE(previewSource->toolTip(), srcPath);
    QCOMPARE(playButton->text(), idlePlayText);
    sendSpaceStroke(*files);
    QCOMPARE(stopPreview.count(), 1);
    QVERIFY(previewSource->toolTip().isEmpty());
    QCOMPARE(playButton->text(), idlePlayText);
    sendSpaceStroke(*nameEdit);
    QVERIFY(playButton->text() != idlePlayText);
    QCOMPARE(preview.count(), 1);
    sendSpaceStroke(*nameEdit);
    QCOMPARE(playButton->text(), idlePlayText);

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
        m_audio.browser());
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
    SampleEditorDialog dialog(docSource, [](const QString &, QString *) { return true; }, browser);
    SampleEditorDialog other(docSource, [](const QString &, QString *) { return true; }, browser);
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

    // Rendered PCM uses the same owner arbitration as raw-file preview.
    const ProcessedSample &rendered = dialog.document()->processed();
    const AuditionSlots::Adsr fast{255, 0, 255, 0};
    QObject firstOwner;
    QObject secondOwner;
    const auto publish = [&](QObject *owner) {
        return browser.auditionRenderedSample(owner, rendered.s8, rendered.freq, 0, true, 60, fast)
            .status;
    };
    QCOMPARE(publish(&firstOwner), soundbrowser::AuditionStatus::Started);
    QVERIFY(peakOf(renderSeconds(engine, 0.2)) >= 0.01);
    browser.stop(&secondOwner);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) >= 0.01,
             "a non-owner cannot stop rendered audition");
    browser.clearProjectSamples();
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) >= 0.01,
             "rendered audition survives catalog clearing");
    QCOMPARE(publish(&secondOwner), soundbrowser::AuditionStatus::Started);
    browser.stop(&firstOwner);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) >= 0.01,
             "a displaced rendered owner cannot release its successor");
    browser.stop(&secondOwner);
    renderSeconds(engine, 4.0);
    QVERIFY(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7);
    {
        QObject temporaryOwner;
        QCOMPARE(publish(&temporaryOwner), soundbrowser::AuditionStatus::Started);
        QVERIFY(peakOf(renderSeconds(engine, 0.2)) >= 0.01);
    }
    renderSeconds(engine, 4.0);
    QVERIFY2(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7,
             "destroying the rendered owner releases its sample lane");

    // With the real callback parked, a publication storm exhausts slots.
    for (int i = 0; i < AuditionSlots::kSlots; ++i)
        QCOMPARE(publish(&firstOwner), soundbrowser::AuditionStatus::Started);
    QCOMPARE(publish(&firstOwner), soundbrowser::AuditionStatus::Busy);
    SampleEditorDialog retryDialog(
        docSource, [](const QString &, QString *) { return true; }, browser);
    sendSpaceStroke(retryDialog);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) <= 1.0e-7,
             "Busy does not publish a stale note while slots retire");
    // Only the GUI timer may retry; the audio callback has now retired slots.
    QTRY_VERIFY_WITH_TIMEOUT(peakOf(renderSeconds(engine, 0.1)) >= 0.01, 2000);
    retryDialog.reject();
    renderSeconds(engine, 4.0);
    QVERIFY(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7);

    // A processed-document owner must not release a newer library owner.
    SampleEditorDialog displaced(
        docSource, [](const QString &, QString *) { return true; }, browser);
    sendSpaceStroke(displaced);
    QVERIFY(peakOf(renderSeconds(engine, 0.2)) >= 0.01);
    QCOMPARE(publish(&secondOwner), soundbrowser::AuditionStatus::Started);
    displaced.reject();
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) >= 0.01,
             "closing a displaced document audition preserves the current owner");
    browser.stop(&secondOwner);
    renderSeconds(engine, 4.0);
    QVERIFY(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7);
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
        m_audio.browser());
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
        m_audio.browser());
    locked.show();
    QApplication::processEvents();
    auto *lockedButton = locked.findChild<QPushButton *>(QStringLiteral("sampleSaveAsNewButton"));
    QVERIFY2(lockedButton && !lockedButton->isVisible(),
             "the single-argument edit target never offers Save as New");
}

} // namespace samplecheck
