#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QKeyEvent>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QSignalSpy>
#include <QStatusBar>
#include <QTimer>
#include <QToolButton>
#include <QtTest>

#include <algorithm>
#include <functional>
#include <utility>

#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"
#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "project/samplereg.h"
#include "project/voicegroupsource.h"
#include "ui/dragspinbox.h"
#include "ui/sampleeditordialog.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/soundbrowser/soundbrowser.h"
#include "ui/workspaceui.h"

namespace checks {
namespace {

int adjacentRelease(int value)
{
    return value < 255 ? value + 1 : value - 1;
}

uint64_t appendTick(const SongDocument &document)
{
    uint64_t end = 0;
    for (const SmfTrack &track : document.smf().tracks)
        end = std::max(end, uint64_t(track.endTick));
    return end + 96;
}

class SampleDialogDriver
{
  public:
    SampleDialogDriver()
    {
        QObject::connect(&m_timer, &QTimer::timeout, &m_timer, [this] {
            auto *modal = qobject_cast<QDialog *>(QApplication::activeModalWidget());
            if (!modal)
                return;
            auto *editor = qobject_cast<SampleEditorDialog *>(modal);
            if (!editor || !m_prepare) {
                auto *message = qobject_cast<QMessageBox *>(modal);
                error = message ? message->text() : QStringLiteral("Unexpected sample dialog");
                modal->reject();
                return;
            }
            auto prepare = std::exchange(m_prepare, {});
            error = prepare(*editor);
            auto *accept = editor->findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
            if (error.isEmpty() && (!accept || !accept->isEnabled()))
                error = QStringLiteral("Sample editor refused the prepared commit");
            handled = true;
            if (error.isEmpty())
                accept->click();
            else
                editor->reject();
        });
        m_timer.start(10);
    }

    void expect(std::function<QString(SampleEditorDialog &)> prepare)
    {
        handled = false;
        error.clear();
        m_prepare = std::move(prepare);
    }

    bool handled = false;
    QString error;

  private:
    QTimer m_timer;
    std::function<QString(SampleEditorDialog &)> m_prepare;
};

bool enableSampleRegistration(const QString &root)
{
    return ::writeFile(root + QStringLiteral("/audio_rules.mk"),
                       "%.bin: %.wav\n\t$(WAV2AGB) -b $< $@\n") &&
           SampleRegistrar::probeSampleFormat(root).ok();
}

} // namespace

void VoicegroupSaveTest::failedRebindRetainsBinding()
{
    const LoadedVoiceGroup *const retainedLease = m_tab->voicegroupLease().get();
    const QStringList retainedRow = m_browser->slotRowText(m_dsSlot);
    const QSize retainedMinimum = m_browser->browserMinimumSizeHint();
    const QRect retainedGeometry = m_browser->dockGeometry();
    QComboBox *const selector = m_browser->voicegroupSelector();
    QVERIFY(selector);

    const QString missingArg = QStringLiteral("_porydaw_missing_voicegroup");
    selector->setCurrentText(missingArg);
    QVERIFY(QMetaObject::invokeMethod(selector, "activated", Qt::DirectConnection, Q_ARG(int, 0)));
    QVERIFY2(settle([this, &missingArg] {
                 return !m_failures.isEmpty() && m_document->cfg().voicegroupArg == missingArg;
             }),
             "missing -G did not publish its failure and cfg edit");
    QVERIFY(m_window->statusBar()->currentMessage().contains(missingArg));
    QVERIFY(m_tab->voicegroupId() && *m_tab->voicegroupId() == *m_homeId);
    QCOMPARE(m_tab->voicegroupLease().get(), retainedLease);
    QVERIFY(!m_browser->isLoading());
    QVERIFY(selector->isEnabled());
    QVERIFY(m_browser->releaseSpinBox());
    QVERIFY(m_browser->releaseSpinBox()->isEnabled());
    QCOMPARE(m_browser->slotRowText(m_dsSlot), retainedRow);
    QCOMPARE(m_browser->browserMinimumSizeHint(), retainedMinimum);
    QCOMPARE(m_browser->dockGeometry(), retainedGeometry);

    requestUndo();
    QVERIFY2(waitForVoicegroup(m_homeArg, *m_homeId),
             "undo did not restore the pre-failure voicegroup binding");
    QVERIFY(!m_document->isDirty());
}

void VoicegroupSaveTest::catalogOutageRetainsLastValid()
{
    QDir project(m_project->root());
    const QString backup = QStringLiteral("sound.vgsavecheck-unavailable");
    const QStringList catalogBefore = m_window->m_workspace->projectState().catalog.groupArgs;
    QVERIFY2(project.rename(QStringLiteral("sound"), backup),
             "could not hide fixture sound directory");
    struct Restore final {
        QDir project;
        QString backup;
        ~Restore()
        {
            if (project.exists(backup) && !project.exists(QStringLiteral("sound")))
                project.rename(backup, QStringLiteral("sound"));
        }
    } restore{project, backup};

    m_window->m_projectWorkspace->submit(ProjectOperation{RefreshCatalogInput{}});
    QVERIFY2(settle([this] {
                 return m_window->statusBar()->currentMessage().contains(
                     QStringLiteral("sound directory is unavailable"));
             }),
             "catalog outage did not reach the production error boundary");
    QCOMPARE(m_window->m_workspace->projectState().catalog.groupArgs, catalogBefore);
    QVERIFY(m_tab->voicegroupId() && *m_tab->voicegroupId() == *m_homeId);
    QVERIFY(!m_browser->isLoading());
    QVERIFY(m_browser->voicegroupSelector() && m_browser->voicegroupSelector()->isEnabled());
    QVERIFY(m_browser->releaseSpinBox() && m_browser->releaseSpinBox()->isEnabled());

    QVERIFY2(project.rename(backup, QStringLiteral("sound")),
             "could not restore fixture sound directory");
    QVERIFY2(refreshCatalog(), "catalog refresh did not settle after sound recovery");
    QCOMPARE(m_window->m_workspace->projectState().catalog.groupArgs, catalogBefore);
    QVERIFY(!m_browser->isLoading());
}

void VoicegroupSaveTest::releaseEditDirtiesOnlyBank_data()
{
    QTest::addColumn<int>("releaseKind");
    QTest::newRow("adjacent") << -1;
    QTest::newRow("lower-bound") << 0;
    QTest::newRow("upper-bound") << 255;
}

void VoicegroupSaveTest::releaseEditDirtiesOnlyBank()
{
    QFETCH(int, releaseKind);
    const int release = releaseKind < 0 ? adjacentRelease(m_originalVoice.release) : releaseKind;
    QVERIFY2(release != m_originalVoice.release,
             "fixture release unexpectedly equals boundary row");

    m_browser->selectSlot(m_dsSlot);
    DragSpinBox *const spin = m_browser->releaseSpinBox();
    QVERIFY(spin);
    spin->setValue(release);
    QVERIFY2(waitForBankRelease(m_dsSlot, release, true),
             "release edit did not dirty the bank and converge in the engine");
    QVERIFY(!m_document->isDirty());
    QVERIFY(!m_window->isWindowModified());
}

void VoicegroupSaveTest::undoShortcutRestoresWithoutWrite()
{
    const int edited = adjacentRelease(m_originalVoice.release);
    m_browser->selectSlot(m_dsSlot);
    DragSpinBox *const spin = m_browser->releaseSpinBox();
    QLineEdit *const field = m_browser->releaseField();
    QVERIFY(spin);
    QVERIFY(field);
    spin->setValue(edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited, true), "setup release edit did not converge");

    QAction *const undoAction = m_window->m_undoAction;
    QVERIFY(undoAction);
    QCOMPARE(undoAction->shortcutContext(), Qt::WindowShortcut);
    QVERIFY(!undoAction->shortcuts().isEmpty());
    QSignalSpy triggered(undoAction, &QAction::triggered);
    QVERIFY(triggered.isValid());

    m_window->show();
    m_window->activateWindow();
    m_window->raise();
    QCoreApplication::processEvents();
    spin->setFocus(Qt::OtherFocusReason);
    QCoreApplication::processEvents();
    QWidget *const target = QApplication::focusWidget();
    QVERIFY(target && (target == spin || spin->isAncestorOf(target)));

    const QKeyCombination undoKey = undoAction->shortcuts().constFirst()[0];
    QKeyEvent overrideEvent(QEvent::ShortcutOverride, undoKey.key(), undoKey.keyboardModifiers());
    overrideEvent.ignore();
    QApplication::sendEvent(target, &overrideEvent);
    QVERIFY(!overrideEvent.isAccepted());
    events::sendKey(*target, QEvent::KeyPress, undoKey.key(), undoKey.keyboardModifiers(),
                    QString(), false, 1);
    events::sendKey(*target, QEvent::KeyRelease, undoKey.key(), undoKey.keyboardModifiers(),
                    QString(), false, 1);
    QCOMPARE(triggered.count(), 1);
    QVERIFY2(waitForBankRelease(m_dsSlot, m_originalVoice.release, false),
             "shortcut undo did not restore the bank and engine");
    QVERIFY(!m_document->isDirty());
    QVERIFY(!m_window->isWindowModified());
    QCOMPARE(readFileBytes(m_voicegroupPath), m_voicegroupBytes);
}

void VoicegroupSaveTest::unifiedSavePersistsSongAndBank()
{
    const int edited = adjacentRelease(m_originalVoice.release);
    m_browser->selectSlot(m_dsSlot);
    QVERIFY(m_browser->releaseSpinBox());
    m_browser->releaseSpinBox()->setValue(edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited, true), "voice edit did not settle before save");

    const uint64_t tick = appendTick(*m_document);
    m_document->addNote(m_track, tick, 72, 24, 93);
    QVERIFY(m_window->isWindowModified());
    const int receiptsBefore = m_savedReceipts;
    QVERIFY2(saveSelectedSong(), "unified save had no dirty state to submit");
    QVERIFY2(waitForCleanSave(receiptsBefore), "unified save did not publish a clean receipt");
    QCOMPARE(readFileBytes(m_voicegroupPath) == m_voicegroupBytes, false);
    QCOMPARE(readFileBytes(m_document->midPath()) == m_midiBytes, false);
}

void VoicegroupSaveTest::queuedSaveSnapshotPreservesNewerEdit()
{
    const int edited = adjacentRelease(m_originalVoice.release);
    m_browser->selectSlot(m_dsSlot);
    QVERIFY(m_browser->releaseSpinBox());
    m_browser->releaseSpinBox()->setValue(edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited, true), "setup voice edit did not settle");

    const uint64_t base = appendTick(*m_document);
    const uint64_t staleTick = base + 96;
    const uint64_t newerTick = base + 192;
    m_document->addNote(m_track, staleTick, 74, 24, 91);
    const QByteArray staleMidi = m_tab->captureSaveSnapshot().smf.write();
    const int receiptsBefore = m_savedReceipts;
    struct SaveTurn final {
        bool heartbeat = false;
        bool completedInline = false;
    } turn;
    QMetaObject::invokeMethod(
        m_window.get(),
        [this, &turn, receiptsBefore] {
            turn.heartbeat = true;
            turn.completedInline = m_savedReceipts > receiptsBefore;
        },
        Qt::QueuedConnection);
    QVERIFY2(saveSelectedSong(), "stale snapshot save was not submitted");
    m_document->addNote(m_track, newerTick, 76, 24, 89);
    const QByteArray newerMidi = m_tab->captureSaveSnapshot().smf.write();
    QTRY_VERIFY_WITH_TIMEOUT(turn.heartbeat && m_savedReceipts > receiptsBefore, 5000);
    QVERIFY(!turn.completedInline);
    QCOMPARE(readFileBytes(m_document->midPath()), staleMidi);
    QVERIFY(m_document->isDirty());

    const int retryReceipts = m_savedReceipts;
    QVERIFY2(saveSelectedSong(), "newer-state retry had no dirty state");
    QVERIFY2(waitForCleanSave(retryReceipts), "newer-state retry did not clean the session");
    QCOMPARE(readFileBytes(m_document->midPath()), newerMidi);

    requestUndo();
    QVERIFY2(settle([this] { return m_document->isDirty(); }), "newer probe undo did not apply");
    requestUndo();
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return m_document->isDirty() && bank && !bank->dirty;
             }),
             "stale probe undo did not leave only the document dirty");
    VoicegroupSource fresh;
    QString error;
    QVERIFY2(fresh.open(m_project->root(), m_document->cfg().voicegroupArg, &error),
             qPrintable(error));
    QVERIFY(fresh.voiceAt(m_dsSlot));
    QCOMPARE(fresh.voiceAt(m_dsSlot)->release, edited);
}

void VoicegroupSaveTest::undoSaveRoundTripsBankBytes()
{
    const int edited = adjacentRelease(m_originalVoice.release);
    m_browser->selectSlot(m_dsSlot);
    QVERIFY(m_browser->releaseSpinBox());
    m_browser->releaseSpinBox()->setValue(edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited, true), "voice edit did not settle");
    m_document->addNote(m_track, appendTick(*m_document), 72, 24, 93);
    const int firstSave = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(firstSave), "initial save did not clean both resources");

    requestUndo();
    QVERIFY2(settle([this] { return m_document->isDirty(); }), "note undo did not apply");
    requestUndo();
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return m_document->isDirty() && bank && bank->dirty;
             }),
             "undo past save point did not re-dirty both resources");
    const int secondSave = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(secondSave), "round-trip save did not clean both resources");
    QCOMPARE(readFileBytes(m_voicegroupPath), m_voicegroupBytes);
}

void VoicegroupSaveTest::cleanSaveEmitsNoReceipt()
{
    const int receiptsBefore = m_savedReceipts;
    QVERIFY(!m_document->isDirty());
    QVERIFY(m_browser->selectedBankView());
    QVERIFY(!m_browser->selectedBankView()->dirty);
    QVERIFY(!saveSelectedSong());
    QCoreApplication::processEvents();
    QCOMPARE(m_savedReceipts, receiptsBefore);
}
void VoicegroupSaveTest::sampleCommitRefreshPreservesDirtyBank()
{
    const QString root = m_project->root();
    QVERIFY(enableSampleRegistration(root));
    const int edited = adjacentRelease(m_originalVoice.release);
    m_window->show();
    m_browser->revealSlot(m_dsSlot);
    QVERIFY(m_browser->releaseSpinBox());
    m_browser->releaseSpinBox()->setValue(edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited, true), "setup voice edit did not settle");

    const QString srcPath = QDir(root).filePath(QStringLiteral("libsrc/commit_tone.wav"));
    QVERIFY(::writeFile(srcPath, samplecheck::hiResSampleWav()));
    SampleDialogDriver driver;
    driver.expect([&](SampleEditorDialog &dialog) {
        QString error;
        dialog.loadLibrarySample(srcPath, &error);
        return error;
    });
    auto *newSample = m_window->findChild<QToolButton *>(QStringLiteral("vgNewSampleButton"));
    QVERIFY(newSample && newSample->isEnabled());
    newSample->click();

    const QString symbol = QStringLiteral("DirectSoundWaveData_commit_tone");
    QVERIFY2(
        settle([&] {
            const LoadedBankView *bank = m_browser->selectedBankView();
            return !driver.error.isEmpty() ||
                   (driver.handled &&
                    m_window->m_workspace->projectState().catalog.directSound.contains(symbol) &&
                    m_window->m_workspace->sampleSet() && bank &&
                    bank->slotViews.at(m_dsSlot).voice->symbol == symbol);
        }),
        "library-first registration did not settle");
    QVERIFY2(driver.error.isEmpty(), qPrintable(driver.error));
    const LoadedBankView *bank = m_browser->selectedBankView();
    QVERIFY(bank && bank->dirty);
    QCOMPARE(bank->slotViews.at(m_dsSlot).voice->release, edited);
    QVERIFY(m_window->m_workspace->soundBrowser()->sampleInfo(symbol).known);

    // Registration assigns the slot through a second ordinary bank edit.
    requestUndo();
    QVERIFY2(settle([&] {
                 const auto &voice = m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice;
                 return voice && voice->symbol == m_originalVoice.symbol;
             }),
             "assignment undo did not restore the original sample");
    QVERIFY(waitForBankRelease(m_dsSlot, edited, true));
    requestUndo();
    QVERIFY2(waitForBankRelease(m_dsSlot, m_originalVoice.release, false),
             "the pre-registration dirty edit lost its undo history");
}

void VoicegroupSaveTest::saveAsNewKeepsOriginalVoice()
{
    const QString root = m_project->root();
    QVERIFY(enableSampleRegistration(root));
    m_window->show();
    m_browser->revealSlot(m_dsSlot);
    const QString srcPath = QDir(root).filePath(QStringLiteral("libsrc/vgsave_orig.wav"));
    const QByteArray sourceBytes = samplecheck::hiResSampleWav();
    QVERIFY(::writeFile(srcPath, sourceBytes));
    SampleDialogDriver driver;
    driver.expect([&](SampleEditorDialog &dialog) {
        QString error;
        dialog.loadLibrarySample(srcPath, &error);
        return error;
    });
    auto *newSample = m_window->findChild<QToolButton *>(QStringLiteral("vgNewSampleButton"));
    QVERIFY(newSample && newSample->isEnabled());
    newSample->click();
    const QString origSymbol = QStringLiteral("DirectSoundWaveData_vgsave_orig");
    QVERIFY2(settle([&] {
                 const LoadedBankView *bank = m_browser->selectedBankView();
                 return !driver.error.isEmpty() ||
                        (driver.handled && m_window->m_workspace->sampleSet() && bank &&
                         bank->slotViews.at(m_dsSlot).voice->symbol == origSymbol);
             }),
             "original library registration did not settle");
    QVERIFY2(driver.error.isEmpty(), qPrintable(driver.error));
    const VgVoice originalVoice = *m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice;
    const QString wavPath = root + QStringLiteral("/sound/direct_sound_samples/vgsave_orig.wav");
    const QString sidecarPath =
        SampleRegistrar::sampleSidecarPath(root, QStringLiteral("vgsave_orig"));
    const QByteArray originalWav = readFileBytes(wavPath);
    const QByteArray originalSidecar = readFileBytes(sidecarPath);
    QVERIFY(!originalWav.isEmpty() && !originalSidecar.isEmpty());

    for (const bool sourceAvailable : {true, false}) {
        if (!sourceAvailable)
            QVERIFY(QFile::remove(srcPath)); // forces the committed-WAV fallback, not a new sidecar
        const QString name =
            sourceAvailable ? QStringLiteral("vgsave_copy") : QStringLiteral("vgsave_fallback");
        driver.expect([&](SampleEditorDialog &dialog) {
            dialog.saveAsNew();
            auto *edit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
            auto *accept = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
            if (!edit || !accept)
                return QStringLiteral("Missing Save as New controls");
            edit->setText(QStringLiteral("vgsave_orig"));
            if (accept->isEnabled())
                return QStringLiteral("Save as New accepted the occupied original name");
            edit->setText(name);
            return QString();
        });
        auto *editSample = m_window->findChild<QToolButton *>(QStringLiteral("vgEditSampleButton"));
        QVERIFY(editSample && editSample->isEnabled());
        editSample->click();
        const QString symbol = QStringLiteral("DirectSoundWaveData_") + name;
        QVERIFY2(
            settle([&] {
                return !driver.error.isEmpty() ||
                       (driver.handled && m_window->m_workspace->sampleSet() &&
                        m_window->m_workspace->projectState().catalog.directSound.contains(symbol));
            }),
            "Save as New registration did not settle");
        QVERIFY2(driver.error.isEmpty(), qPrintable(driver.error));
        QCOMPARE(readFileBytes(wavPath), originalWav);
        QCOMPARE(readFileBytes(sidecarPath), originalSidecar);
        QCOMPARE(*m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice, originalVoice);
        QVERIFY(QFile::exists(root + QStringLiteral("/sound/direct_sound_samples/") + name +
                              QStringLiteral(".wav")));
        if (sourceAvailable) {
            SampleSidecar sidecar;
            QVERIFY(SampleRegistrar::readSampleSidecar(root, name, &sidecar));
            QCOMPARE(sidecar.sourcePath, srcPath);
            QCOMPARE(sidecar.sourceSha256, SampleRegistrar::sourceHashHex(sourceBytes));
        } else {
            QVERIFY(!QFile::exists(SampleRegistrar::sampleSidecarPath(root, name)));
        }
    }
}

} // namespace checks
