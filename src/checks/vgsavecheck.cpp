#include <algorithm>

#include <QComboBox>
#include <QCoreApplication>
#include <QDialog>
#include <QDir>
#include <QDirIterator>
#include <QEvent>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QLineEdit>
#include <QPointer>
#include <QStatusBar>
#include <QTimer>
#include <cstdio>
#include <memory>
#include <variant>

#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"
#include "project/songregistry.h"
#include "project/voicegroupsource.h"
#include "ui/dragspinbox.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/workspaceui.h"

extern "C" {
#include "voicegroup_loader.h"
}

// --vgsavecheck <projectRoot> <song>: unified song+voicegroup undo/save
// check, driven end to end through the production seams. The project and the
// song open through WorkspaceUi's semantic requests; voice edits go through
// the browser's picker pipeline (the WorkspaceUi edit entry the browser's
// voiceEditRequested path drives, reached here through the check browser
// driver), undo/redo through WorkspaceUi::requestUndo/requestRedo (document
// entries cross in place, shared-bank entries round-trip the worker), and
// saves through WorkspaceUi::saveSelectedSong's semantic SaveSongInput. The
// worker owns the canonical bank and publishes LoadedBankView copies, so
// every bank assertion observes the tab's lease, the workspace's bank view,
// and the engine. Song and voicegroup edits share one undo stack and one
// save: a voice edit dirties the bank (never the document, never the window
// title), undo restores the byte-exact on-disk state, Save writes the .mid
// and the voicegroup .inc together, and an undone edit saved again
// round-trips the .inc byte-identically. Also proves a -G voicegroup switch
// keeps unsaved voice edits in the worker's canonical bank (undoing the
// switch replays them), the blank-slot materialization/revert token
// lifecycle, the Golden Sun synth definition flow, and the sample picker.
// Writes into the project: run against a scratch copy.

namespace {

QByteArray readFileBytes(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return QByteArray();
    return f.readAll();
}

} // namespace

bool MainWindow::runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                                const QString &screenshotPath)
{
    m_persistSession = false;
    if (!m_audioOk) {
        std::fprintf(stderr, "vgsavecheck: no audio device available\n");
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    const auto requestedSong = SongName::create(songLabel);
    if (!requestedSong) {
        std::fprintf(stderr, "vgsavecheck: invalid song label '%s'\n", qUtf8Printable(songLabel));
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    const SongName name = *requestedSong;

    // Open the project and the song through the workspace's semantic seams;
    // readiness is SongTab::isReady() and the workspace's own settlement gate.
    m_workspace->requestProjectOpenAt(projectRoot);
    if (checks::async_wait::waitUntil([] { return true; },
                                      [this] {
                                          return m_workspace->projectState().state ==
                                                 ProjectOpenState::Ready;
                                      }) != checks::async_wait::Result::Ready) {
        std::fprintf(stderr, "vgsavecheck: project failed to open\n");
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    const SongInfo *target = nullptr;
    for (const SongInfo &song : m_workspace->projectState().snapshot.songs()) {
        if (song.label == songLabel && song.isPlayable())
            target = &song;
    }
    if (!target) {
        std::fprintf(stderr, "vgsavecheck: song '%s' not found or has no MIDI source\n",
                     qUtf8Printable(songLabel));
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    m_workspace->requestSongOpen(name);
    SongTab *tab = m_workspace->selectedSongTab();
    const auto loadWait = checks::async_wait::waitUntil(
        [this, tab, &name] { return m_workspace->songTabFor(name) == tab; },
        [tab] { return tab && tab->isReady(); });
    if (loadWait != checks::async_wait::Result::Ready) {
        const char *reason = loadWait == checks::async_wait::Result::Destroyed
                                 ? "tab destroyed before async load completed"
                                 : "timed out waiting for the song's terminal VoicegroupBound";
        std::fprintf(stderr, "vgsavecheck: %s for '%s'\n", reason, qUtf8Printable(target->label));
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    // The engine handoff is MainWindow's own duty: bind, then assert.
    if (checks::async_wait::waitUntil([] { return true; },
                                      [this, tab] {
                                          return m_workspace->openProjectEnabled() &&
                                                 m_audio.songLoaded() &&
                                                 tab->voicegroupId() != nullptr;
                                      }) != checks::async_wait::Result::Ready) {
        std::fprintf(stderr, "vgsavecheck: song failed to bind the audio engine\n");
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    SongView &view = tab->view();
    // The tab's document is published read-only; its mutable surface is the
    // paired view's own document pointer, the same object every production
    // edit path drives.
    SongDocument &doc = *view.document();
    checks::VoicegroupBrowserDriver voicegroupDriver(*m_workspace);
    if (!voicegroupDriver.isAvailable()) {
        std::fprintf(stderr, "vgsavecheck: voicegroup browser or dock was not constructed\n");
        return false;
    }

    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "vgsavecheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };

    // Typed publication receipts from the production streams: the save
    // terminal and the keyed failure publications the check awaits. Nothing
    // is driven through these; they only observe.
    int savedReceipts = 0;
    QStringList failedPublications;
    const QMetaObject::Connection receiptConnection =
        connect(m_projectWorkspace.get(), &ProjectWorkspace::songUpdatePublished, this,
                [&savedReceipts, &failedPublications, name](const SongUpdate &update) {
                    if (update.song != name)
                        return;
                    if (std::holds_alternative<SongSaved>(update.payload))
                        savedReceipts++;
                    else if (const auto *failed = std::get_if<SongFailed>(&update.payload))
                        failedPublications.append(failed->message);
                });

    // The one settlement barrier: the tab is still live, no project operation
    // is in flight (openProjectEnabled gates loads, saves, dialog work,
    // tombstones, and the bank transition gate), and pred observes the
    // awaited state.
    const auto settled = [this, tab, name](auto pred) {
        return checks::async_wait::waitUntil(
            [this, tab, name] { return m_workspace->songTabFor(name) == tab; },
            [this, &pred] { return m_workspace->openProjectEnabled() && pred(); });
    };

    // One undo/redo step through the production seam: a document entry
    // crosses synchronously, a shared-bank entry returns the exact worker
    // draft, and the settle barrier waits out its typed applied receipt.
    const auto historyStep = [this, &settled, &check](bool undo, const char *what) {
        if (!check(settled([] { return true; }) == checks::async_wait::Result::Ready, what))
            return false;
        if (undo)
            m_workspace->requestUndo();
        else
            m_workspace->requestRedo();
        return check(settled([] { return true; }) == checks::async_wait::Result::Ready, what);
    };

    // The semantic save seam: submit SaveSongInput for the selected tab and
    // await its typed SongSaved receipt plus the clean document and bank.
    const auto waitForSave = [this, tab, &voicegroupDriver, &savedReceipts, &settled,
                              &check](const char *what) {
        const LoadedBankView *const pending = voicegroupDriver.selectedBankView();
        if (!check(tab->document().isDirty() || (pending && pending->dirty),
                   QStringLiteral("%1: nothing to save").arg(what).toUtf8().constData()))
            return false;
        const int before = savedReceipts;
        m_workspace->saveSelectedSong();
        return check(settled([&] {
                         const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                         return savedReceipts > before && !tab->document().isDirty() &&
                                !(applied && applied->dirty);
                     }) == checks::async_wait::Result::Ready,
                     what);
    };

    const LoadedBankView *const initialView = voicegroupDriver.selectedBankView();
    if (!check(initialView != nullptr, "no bank view was published for the song")) {
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    const VoicegroupId homeId = *tab->voicegroupId();
    const QString vgPath = QDir(projectRoot).filePath(homeId.sourceRelativePath());
    const QString vgLoadName = initialView->loadName;

    // A DirectSound-family voice to edit (scalar fields + a sample symbol).
    int dsSlot = -1;
    for (int i = 0; i < VOICEGROUP_SIZE && dsSlot < 0; i++) {
        const std::optional<VgVoice> &slotVoice = initialView->slotViews.at(i).voice;
        if (slotVoice && (slotVoice->macro == VgMacro::DirectSound ||
                          slotVoice->macro == VgMacro::DirectSoundNoResample ||
                          slotVoice->macro == VgMacro::DirectSoundAlt))
            dsSlot = i;
    }
    if (dsSlot < 0) {
        std::fprintf(stderr, "vgsavecheck: voicegroup has no sample voices\n");
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }

    const QByteArray vgBytesOriginal = readFileBytes(vgPath);
    const QByteArray midBytesOriginal = readFileBytes(tab->document().midPath());
    const VgVoice original = *initialView->slotViews.at(dsSlot).voice;

    // 0a. A failed voicegroup rebind must leave the bound voicegroup usable:
    // the tab keeps its binding and lease, the browser keeps its rows and
    // layout, the failure is reported, and no loading placeholder appears
    // for an already-loaded tab.
    {
        const LoadedVoiceGroup *const retainedLease = tab->voicegroupLease().get();
        const QStringList retainedRow = voicegroupDriver.slotRowText(dsSlot);
        const QSize retainedMinimumSize = voicegroupDriver.browserMinimumSizeHint();
        const QRect retainedDockGeometry = voicegroupDriver.dockGeometry();
        QComboBox *const vgCombo = voicegroupDriver.voicegroupSelector();
        if (check(vgCombo != nullptr, "no voicegroup selector in the dock")) {
            const QString missingArg = QStringLiteral("_porydaw_missing_voicegroup");
            vgCombo->setCurrentText(missingArg);
            QMetaObject::invokeMethod(vgCombo, "activated", Qt::DirectConnection, Q_ARG(int, 0));
            // The -G switch is an undoable document edit; its bank rebind
            // fails and the keyed SongFailed publication reports it.
            const auto failedRebindWait = settled([&] {
                return !failedPublications.isEmpty() &&
                       tab->document().cfg().voicegroupArg == missingArg;
            });
            check(failedRebindWait == checks::async_wait::Result::Ready,
                  "failed voicegroup rebind did not complete");
            check(statusBar()->currentMessage().contains(missingArg),
                  "failed voicegroup rebind did not report its error");
            check(tab->voicegroupId() && *tab->voicegroupId() == homeId &&
                      tab->voicegroupLease().get() == retainedLease,
                  "failed voicegroup rebind replaced the bound voicegroup");
            check(!voicegroupDriver.isLoading(), "failed voicegroup rebind showed loading");
            check(voicegroupDriver.voicegroupSelector() &&
                      voicegroupDriver.voicegroupSelector()->isEnabled() &&
                      voicegroupDriver.releaseSpinBox() &&
                      voicegroupDriver.releaseSpinBox()->isEnabled(),
                  "failed voicegroup rebind left the browser inert");
            check(voicegroupDriver.slotRowText(dsSlot) == retainedRow,
                  "failed voicegroup rebind did not restore the retained row");
            check(voicegroupDriver.browserMinimumSizeHint() == retainedMinimumSize,
                  "failed voicegroup rebind shifted browser layout");
            check(voicegroupDriver.dockGeometry() == retainedDockGeometry,
                  "failed voicegroup rebind shifted the visible dock");
            // Undo the bogus -G switch: the document entry crosses and the
            // original binding reloads in place.
            if (historyStep(true, "undoing the failed -G switch did not settle")) {
                const auto restoreWait = settled([&] {
                    return tab->voicegroupId() && *tab->voicegroupId() == homeId &&
                           !tab->document().isDirty();
                });
                check(restoreWait == checks::async_wait::Result::Ready,
                      "undoing the failed -G switch did not restore the binding");
            }
        }
    }

    // 0b. If the catalog scan cannot reach the project's sound data, the
    // failure must be reported without discarding the bound group or the
    // last valid catalog, and the catalog must recover afterwards.
    {
        QDir projectDir(projectRoot);
        const QString soundBackupName = QStringLiteral("sound.vgsavecheck-unavailable");
        const QStringList catalogBefore = m_workspace->projectState().catalog.groupArgs;
        if (check(projectDir.rename(QStringLiteral("sound"), soundBackupName),
                  "could not hide the sound directory for catalog failure")) {
            m_projectWorkspace->submit(ProjectOperation{RefreshCatalogInput{}});
            const auto failedCatalogWait = settled([&] {
                return statusBar()->currentMessage().contains(
                    QStringLiteral("sound directory is unavailable"));
            });
            check(failedCatalogWait == checks::async_wait::Result::Ready,
                  "failed catalog request did not complete");
            check(m_workspace->projectState().catalog.groupArgs == catalogBefore,
                  "failed catalog request discarded the last valid catalog");
            check(tab->voicegroupId() && *tab->voicegroupId() == homeId,
                  "failed catalog request replaced the bound voicegroup");
            check(!voicegroupDriver.isLoading(), "failed catalog request left loading visible");
            check(voicegroupDriver.voicegroupSelector() &&
                      voicegroupDriver.voicegroupSelector()->isEnabled() &&
                      voicegroupDriver.releaseSpinBox() &&
                      voicegroupDriver.releaseSpinBox()->isEnabled(),
                  "failed catalog request left the browser inert");
            const bool soundRestored = projectDir.rename(soundBackupName, QStringLiteral("sound"));
            check(soundRestored, "could not restore the sound directory after catalog failure");
            if (soundRestored) {
                m_projectWorkspace->submit(ProjectOperation{RefreshCatalogInput{}});
                const auto recoveredWait = settled(
                    [&] { return m_workspace->projectState().catalog.groupArgs == catalogBefore; });
                check(recoveredWait == checks::async_wait::Result::Ready,
                      "voicegroup catalog did not recover after the failure check");
                check(!voicegroupDriver.isLoading(),
                      "recovered voicegroup catalog left loading visible");
            }
        }
    }

    // 1. A voice edit is a bank edit: the shared bank view dirties, the
    // document and the window title stay clean, and the engine converges on
    // the edited voice.
    VgVoice edited = original;
    edited.release = original.release == 25 ? 26 : 25;
    voicegroupDriver.submitPickerEdit(dsSlot, edited);
    check(settled([&] {
              const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
              return applied && applied->dirty && !tab->document().isDirty() &&
                     applied->slotViews.at(dsSlot).voice &&
                     applied->slotViews.at(dsSlot).voice->release == edited.release;
          }) == checks::async_wait::Result::Ready,
          "voice edit did not land in the bank view");
    check(!isWindowModified(), "a bank-only voice edit must not mark the window modified");
    const auto scalarEditWait = settled([this, dsSlot, &edited] {
        const LoadedVoiceGroup *engine = m_audio.voicegroup();
        return engine && engine->voices[dsSlot].release == uint8_t(edited.release);
    });
    check(scalarEditWait == checks::async_wait::Result::Ready,
          "voice edit did not reach the audio engine");

    // 2. Undo restores the byte-exact on-disk state, nothing written.
    if (historyStep(true, "undoing the voice edit did not settle")) {
        const auto undoWait = settled([this, tab, dsSlot, &voicegroupDriver, &original] {
            const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
            const LoadedVoiceGroup *engine = m_audio.voicegroup();
            return applied && !applied->dirty && !tab->document().isDirty() &&
                   (!engine || engine->voices[dsSlot].release == original.release);
        });
        check(undoWait == checks::async_wait::Result::Ready,
              "undo did not return the bank to clean");
        check(!isWindowModified(), "undo left the window marked modified");
        check(readFileBytes(vgPath) == vgBytesOriginal, "voicegroup file changed without a save");
    }

    // 3. Redo the voice edit, add a note edit, save once: both files written.
    historyStep(false, "redoing the voice edit did not settle");
    int track = -1;
    for (int t = 0; t < tab->document().engineTrackCount() && track < 0; t++) {
        if (!tab->document().notesForTrack(t).empty())
            track = t;
    }
    if (track < 0) {
        std::fprintf(stderr, "vgsavecheck: song has no notes\n");
        std::fprintf(stderr, "vgsavecheck: FAIL (early exit)\n");
        return false;
    }
    uint64_t base = 0;
    for (const SmfTrack &tr : tab->document().smf().tracks)
        base = std::max(base, tr.endTick);
    base += 96;
    doc.addNote(track, base, 72, 24, 93);
    check(isWindowModified(), "the note edit did not mark the window modified");
    check(waitForSave("unified save"), "unified save failed");
    {
        const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
        check(!tab->document().isDirty() && applied && !applied->dirty, "still dirty after save");
    }
    check(readFileBytes(vgPath) != vgBytesOriginal, "save did not write the voicegroup file");
    check(readFileBytes(tab->document().midPath()) != midBytesOriginal,
          "save did not write the .mid");

    // 3a. A dirty save is queued without blocking the GUI turn. Edit the
    // document again before the completion arrives: the stale snapshot must
    // not clear the newer edit, and a retry must persist that newer state.
    const uint64_t staleTick = base + 192;
    const uint64_t newerTick = base + 288;
    doc.addNote(track, staleTick, 74, 24, 91);
    check(tab->document().isDirty(), "precondition edit did not dirty the document");
    struct SaveTurnState {
        bool heartbeat = false;
        bool completedInline = false;
        bool saveReturned = false;
    };
    const auto saveTurn = std::make_shared<SaveTurnState>();
    const int savesBeforeTurn = savedReceipts;
    QEventLoop saveLoop;
    QPointer<QEventLoop> saveLoopGuard = &saveLoop;
    QTimer saveTimeout;
    saveTimeout.setSingleShot(true);
    QObject::connect(&saveTimeout, &QTimer::timeout, &saveLoop, &QEventLoop::quit);
    QTimer savePoll;
    QObject::connect(&savePoll, &QTimer::timeout, &saveLoop,
                     [&saveTurn, &savedReceipts, savesBeforeTurn, &saveLoop] {
                         if (saveTurn->heartbeat && savedReceipts > savesBeforeTurn)
                             saveLoop.quit();
                     });
    QMetaObject::invokeMethod(
        this,
        [saveTurn, saveLoopGuard, &savedReceipts, savesBeforeTurn] {
            saveTurn->heartbeat = true;
            // A receipt that raced ahead of the queued heartbeat would mean
            // the save completed on the submitting GUI turn.
            saveTurn->completedInline = savedReceipts > savesBeforeTurn;
            if (savedReceipts > savesBeforeTurn && saveLoopGuard)
                saveLoopGuard->quit();
        },
        Qt::QueuedConnection);
    const QByteArray staleMidi = tab->captureSaveSnapshot().smf.write();
    m_workspace->saveSelectedSong(); // captures its snapshot on this GUI turn
    saveTurn->saveReturned = true;
    doc.addNote(track, newerTick, 76, 24, 89);
    const QByteArray newerMidi = tab->captureSaveSnapshot().smf.write();
    if (!saveTurn->heartbeat || savedReceipts <= savesBeforeTurn) {
        saveTimeout.start(30000);
        savePoll.start(10);
        saveLoop.exec();
        saveTimeout.stop();
        savePoll.stop();
    }
    check(saveTurn->heartbeat && savedReceipts > savesBeforeTurn && !saveTurn->completedInline,
          "the semantic save completed inline or missed the queued GUI turn");
    check(readFileBytes(tab->document().midPath()) == staleMidi,
          "the queued save did not write its captured snapshot");
    check(tab->document().isDirty(), "a stale save adoption cleaned a newer document edit");
    check(waitForSave("newer-state retry save"), "retry save with newer state failed");
    check(!tab->document().isDirty(), "retry save did not clean the newer document state");
    check(readFileBytes(tab->document().midPath()) == newerMidi,
          "retry save did not persist the newer document state");
    // Leave the two probe edits behind the existing undo/save round trip.
    historyStep(true, "undoing the newer-state probe edit did not settle");
    historyStep(true, "undoing the stale-state probe edit did not settle");
    {
        const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
        check(tab->document().isDirty() && applied && !applied->dirty,
              "undoing the probe edits did not leave only the document dirty");
    }
    {
        QString error;
        VoicegroupSource fresh;
        check(fresh.open(projectRoot, tab->document().cfg().voicegroupArg, &error) &&
                  fresh.voiceAt(dsSlot) && fresh.voiceAt(dsSlot)->release == edited.release,
              "saved voice edit not present in a fresh parse");
    }

    // 4. Undo both edits and save again: the voicegroup .inc must come back
    // byte-identical to the original (byte-conservative round trip).
    historyStep(true, "undoing the note edit did not settle");  // the note
    historyStep(true, "undoing the voice edit did not settle"); // the voice edit
    {
        const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
        check(tab->document().isDirty() && applied && applied->dirty,
              "undo past the save point did not re-dirty the session");
    }
    check(waitForSave("second unified save"), "second unified save failed");
    check(readFileBytes(vgPath) == vgBytesOriginal,
          "undone voice edit did not round-trip the .inc byte-identically");

    // 5. A -G voicegroup switch carries unsaved voice edits in the worker's
    // canonical bank: undoing the switch replays them into the reopened
    // source.
    QString otherArg;
    for (const QString &arg : m_workspace->projectState().catalog.groupArgs) {
        if (arg != tab->document().cfg().voicegroupArg) {
            otherArg = arg;
            break;
        }
    }
    if (otherArg.isEmpty()) {
        std::printf("vgsavecheck: note: no second voicegroup found, "
                    "-G switch replay skipped\n");
    } else {
        VgVoice edited2 = original;
        edited2.release = original.release == 25 ? 26 : 25;
        voicegroupDriver.submitPickerEdit(dsSlot, edited2);
        check(settled([&] {
                  const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                  return applied && applied->dirty && applied->slotViews.at(dsSlot).voice &&
                         applied->slotViews.at(dsSlot).voice->release == edited2.release;
              }) == checks::async_wait::Result::Ready,
              "the -G journey's voice edit did not land");
        const QString originalArg = tab->document().cfg().voicegroupArg;
        SongCfg cfg = tab->document().cfg();
        cfg.voicegroupArg = otherArg;
        doc.setCfg(cfg);
        const auto switchWait = settled([&] {
            return tab->document().cfg().voicegroupArg == otherArg && tab->voicegroupId() &&
                   *tab->voicegroupId() != homeId;
        });
        check(switchWait == checks::async_wait::Result::Ready,
              "-G switch voicegroup load did not complete");
        check(tab->voicegroupId() && *tab->voicegroupId() != homeId,
              "-G switch did not swap the voicegroup source");
        historyStep(true, "undoing the -G switch did not settle"); // the -G switch
        const auto undoSwitchWait = settled([this, tab, dsSlot, &voicegroupDriver, homeId,
                                             &originalArg, &vgLoadName, &edited2] {
            const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
            const LoadedVoiceGroup *engine = m_audio.voicegroup();
            return tab->document().cfg().voicegroupArg == originalArg && tab->voicegroupId() &&
                   *tab->voicegroupId() == homeId && applied && applied->loadName == vgLoadName &&
                   applied->dirty && applied->slotViews.at(dsSlot).voice &&
                   applied->slotViews.at(dsSlot).voice->release == edited2.release &&
                   (!engine || engine->voices[dsSlot].release == uint8_t(edited2.release));
        });
        check(undoSwitchWait == checks::async_wait::Result::Ready,
              "undoing the -G switch voicegroup load did not complete");
        check(tab->voicegroupId() && *tab->voicegroupId() == homeId &&
                  voicegroupDriver.selectedBankView() &&
                  voicegroupDriver.selectedBankView()->loadName == vgLoadName,
              "undoing the -G switch did not reopen the old voicegroup");
        check(voicegroupDriver.selectedBankView() &&
                  voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice &&
                  voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice->release ==
                      edited2.release &&
                  voicegroupDriver.selectedBankView()->dirty,
              "undoing the -G switch did not replay the unsaved voice edit");
        historyStep(true, "undoing the replayed voice edit did not settle"); // the voice edit
        {
            const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
            check(applied && !applied->dirty && !tab->document().isDirty(),
                  "undoing the replayed voice edit did not return to clean");
        }
        check(readFileBytes(vgPath) == vgBytesOriginal,
              "voicegroup file changed during the -G switch round trip");

        // 5b. The dock's voicegroup selector drives the same switch as an
        // undoable cfg edit, and undo refreshes the selector's text. The
        // selector shows args in display form: the leading underscore folds
        // into the fixed "voicegroup_" prefix.
        QComboBox *vgCombo = voicegroupDriver.voicegroupSelector();
        if (check(vgCombo != nullptr, "no voicegroup selector in the dock")) {
            const QString shown = SongRegistry::voicegroupDisplayName(originalArg);
            check(vgCombo->isEnabled() && vgCombo->currentText() == shown,
                  "dock selector does not show the song's voicegroup");
            check(vgCombo->findText(SongRegistry::voicegroupDisplayName(otherArg)) >= 0,
                  "dock selector is missing a known voicegroup arg");
            vgCombo->setCurrentText(SongRegistry::voicegroupDisplayName(otherArg));
            QMetaObject::invokeMethod(vgCombo, "activated", Qt::DirectConnection, Q_ARG(int, 0));
            const auto selectorSwitchWait = settled([&] {
                return tab->document().cfg().voicegroupArg == otherArg && tab->voicegroupId() &&
                       *tab->voicegroupId() != homeId;
            });
            check(selectorSwitchWait == checks::async_wait::Result::Ready,
                  "dock selector voicegroup load did not complete");
            check(tab->document().cfg().voicegroupArg == otherArg && tab->document().isDirty(),
                  "dock selector did not commit an undoable -G switch");
            check(tab->voicegroupId() && *tab->voicegroupId() != homeId,
                  "dock selector switch did not swap the voicegroup source");
            historyStep(true, "undoing the dock selector's -G switch did not settle");
            const auto selectorUndoWait =
                settled([this, tab, &voicegroupDriver, homeId, &originalArg] {
                    return tab->document().cfg().voicegroupArg == originalArg &&
                           tab->voicegroupId() && *tab->voicegroupId() == homeId;
                });
            check(selectorUndoWait == checks::async_wait::Result::Ready,
                  "undoing the dock selector voicegroup load did not complete");
            check(tab->document().cfg().voicegroupArg == originalArg && !tab->document().isDirty(),
                  "undoing the dock selector switch did not restore the cfg");
            check(voicegroupDriver.voicegroupSelector() &&
                      voicegroupDriver.voicegroupSelector()->currentText() == shown,
                  "undo did not refresh the dock selector's text");
            check(tab->voicegroupId() && *tab->voicegroupId() == homeId,
                  "undoing the dock selector switch did not reopen the old voicegroup");
        }
    }

    // 5c. Rebinding away and back replaces the tab's bank binding in place
    // without invalidating the undo stack: both an executed value command
    // and a command in the redo tail must still resolve the worker's
    // current canonical record.
    const auto reopenCleanSameVoicegroup = [&]() -> bool {
        const QString expectedLoadName = voicegroupDriver.selectedBankView()
                                             ? voicegroupDriver.selectedBankView()->loadName
                                             : QString();
        const QByteArray diskBytes = readFileBytes(vgPath);
        if (otherArg.isEmpty())
            return check(false, "same-name reopen has no second voicegroup to round-trip");
        SongCfg switched = tab->document().cfg();
        switched.voicegroupArg = otherArg;
        doc.setCfg(switched);
        if (!check(settled([&] { return tab->voicegroupId() && *tab->voicegroupId() != homeId; }) ==
                       checks::async_wait::Result::Ready,
                   "the reopen round-trip switch did not complete"))
            return false;
        if (!historyStep(true, "the reopen round-trip undo did not settle"))
            return false;
        return check(settled([&] {
                         const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                         return tab->voicegroupId() && *tab->voicegroupId() == homeId && applied &&
                                applied->loadName == expectedLoadName && !applied->dirty &&
                                readFileBytes(vgPath) == diskBytes;
                     }) == checks::async_wait::Result::Ready,
                     "same-loadName reopen did not yield a clean on-disk source");
    };
    if (!otherArg.isEmpty() &&
        check(!tab->document().isDirty() && voicegroupDriver.selectedBankView() &&
                  !voicegroupDriver.selectedBankView()->dirty,
              "replacement-lifetime setup did not begin clean")) {
        VgVoice refreshEdited = original;
        refreshEdited.release = original.release == 255 ? 254 : original.release + 1;
        voicegroupDriver.submitPickerEdit(dsSlot, refreshEdited);
        if (check(settled([&] {
                      const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                      return applied && applied->dirty && applied->slotViews.at(dsSlot).voice &&
                             applied->slotViews.at(dsSlot).voice->release == refreshEdited.release;
                  }) == checks::async_wait::Result::Ready,
                  "value command did not execute before clean reopen") &&
            waitForSave("could not save value command before clean reopen") &&
            reopenCleanSameVoicegroup()) {
            const QByteArray refreshedValueBytes = readFileBytes(vgPath);
            historyStep(true, "undoing the executed value command did not settle");
            {
                const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                check(applied && applied->slotViews.at(dsSlot).voice &&
                          applied->slotViews.at(dsSlot).voice->release == original.release &&
                          applied->dirty && !tab->document().isDirty() &&
                          readFileBytes(vgPath) == refreshedValueBytes,
                      "executed value command undo after reopen lost the current source state");
            }
            historyStep(false, "redoing the executed value command did not settle");
            {
                const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                check(applied && applied->slotViews.at(dsSlot).voice &&
                          applied->slotViews.at(dsSlot).voice->release == refreshEdited.release &&
                          !applied->dirty && !tab->document().isDirty() &&
                          readFileBytes(vgPath) == refreshedValueBytes,
                      "executed value command redo after reopen did not restore the clean source");
            }

            // Saving the undone state refreshes the canonical bank while the
            // value command remains in the redo tail.
            historyStep(true, "restoring the value-edit baseline did not settle");
            if (waitForSave("could not restore the value-edit baseline") &&
                check(readFileBytes(vgPath) == vgBytesOriginal,
                      "value-edit baseline did not round-trip before redo-tail replay")) {
                historyStep(false, "the redo-tail value command did not settle");
                {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    check(applied && applied->slotViews.at(dsSlot).voice &&
                              applied->slotViews.at(dsSlot).voice->release ==
                                  refreshEdited.release &&
                              applied->dirty && !tab->document().isDirty() &&
                              readFileBytes(vgPath) == vgBytesOriginal,
                          "redo-tail value command after refresh did not apply to the current "
                          "source");
                }
                historyStep(true, "undoing the redo-tail value command did not settle");
                {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    check(applied && applied->slotViews.at(dsSlot).voice &&
                              applied->slotViews.at(dsSlot).voice->release == original.release &&
                              !applied->dirty && !tab->document().isDirty(),
                          "undo after redo-tail refresh did not return to the clean baseline");
                }
            }
        }
    }

    // 5d. A blank-slot command is structural, so replacing source bytes must
    // rebase its revert token rather than restoring its old whole-file
    // snapshots.
    int replacementBlankSlot = -1;
    for (int i = 0; i < VOICEGROUP_SIZE && replacementBlankSlot < 0; i++) {
        if (!voicegroupDriver.selectedBankView()->slotViews.at(i).voice)
            replacementBlankSlot = i;
    }
    if (check(replacementBlankSlot >= 0,
              "voicegroup has no blank slot for replacement-lifetime coverage")) {
        // The worker materializes the slot under a revertable token; the
        // applied receipt carries the fresh token the history entry adopts.
        const VgVoice materialized = original;
        voicegroupDriver.submitPickerEdit(replacementBlankSlot, materialized);
        if (check(settled([&] {
                      const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                      return applied && applied->dirty && !tab->document().isDirty() &&
                             applied->slotViews.at(replacementBlankSlot).voice &&
                             *applied->slotViews.at(replacementBlankSlot).voice == materialized;
                  }) == checks::async_wait::Result::Ready,
                  "blank-slot command did not materialize before reopen") &&
            waitForSave("could not save blank-slot materialization")) {
            VoicegroupSource sibling;
            QString siblingError;
            VgVoice unrelated = original;
            unrelated.release = original.release == 255 ? 254 : original.release + 1;
            if (check(
                    sibling.open(projectRoot, tab->document().cfg().voicegroupArg, &siblingError) &&
                        sibling.setVoice(dsSlot, unrelated) && sibling.save(&siblingError),
                    "could not make an unrelated current-source edit") &&
                reopenCleanSameVoicegroup()) {
                const QByteArray externallyRefreshedBytes = readFileBytes(vgPath);
                {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    check(applied && applied->slotViews.at(replacementBlankSlot).voice &&
                              applied->slotViews.at(dsSlot).voice &&
                              applied->slotViews.at(dsSlot).voice->release == unrelated.release &&
                              !applied->dirty && readFileBytes(vgPath) == externallyRefreshedBytes,
                          "reopened source did not contain the unrelated edit");
                }
                historyStep(true, "undoing the blank materialization did not settle");
                {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    check(applied && !applied->slotViews.at(replacementBlankSlot).voice &&
                              applied->slotViews.at(dsSlot).voice &&
                              applied->slotViews.at(dsSlot).voice->release == unrelated.release &&
                              applied->dirty && readFileBytes(vgPath) == externallyRefreshedBytes,
                          "blank-slot undo after reopen restored stale whole-file bytes");
                }
                historyStep(false, "redoing the blank materialization did not settle");
                {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    check(applied && applied->slotViews.at(replacementBlankSlot).voice &&
                              *applied->slotViews.at(replacementBlankSlot).voice == materialized &&
                              applied->slotViews.at(dsSlot).voice &&
                              applied->slotViews.at(dsSlot).voice->release == unrelated.release &&
                              !applied->dirty && readFileBytes(vgPath) == externallyRefreshedBytes,
                          "blank-slot redo after reopen did not preserve the unrelated edit");
                }

                // Return the scratch fixture to its starting source.
                historyStep(true, "reverting the blank materialization did not settle");
                voicegroupDriver.submitPickerEdit(dsSlot, original);
                check(settled([&] {
                          const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                          return applied && applied->dirty && applied->slotViews.at(dsSlot).voice &&
                                 applied->slotViews.at(dsSlot).voice->release == original.release;
                      }) == checks::async_wait::Result::Ready,
                      "restoring the unrelated slot did not settle") &&
                    waitForSave("could not restore the replacement-lifetime fixture") &&
                    check(readFileBytes(vgPath) == vgBytesOriginal,
                          "replacement-lifetime fixture did not restore original bytes");
            }
        }
    }

    // 6. The dock's editor widgets feed the same pipeline: spinning the
    // Release box must push an undo command, and undoing it must refresh
    // the box back to the original value.
    {
        voicegroupDriver.selectSlot(dsSlot);
        DragSpinBox *releaseSpin = voicegroupDriver.releaseSpinBox();
        QLineEdit *releaseEdit = voicegroupDriver.releaseField();
        if (check(releaseSpin != nullptr, "no Release spin box in the editor")) {
            check(releaseEdit != nullptr, "Release input has no line edit");
            const auto dragVertically = [&](QWidget *field, int pixelsUp,
                                            Qt::KeyboardModifiers modifiers) {
                const QPoint start = field->rect().center();
                const int direction = pixelsUp > 0 ? 1 : -1;
                const QPoint activated = start - QPoint(0, direction * 3);
                const QPoint finish = activated - QPoint(0, pixelsUp);
                field->clearFocus();
                const QRect fieldGeometry = field->geometry();
                const QRect rowGeometry = field->parentWidget()->geometry();
                const QSize browserMinimumSize = voicegroupDriver.browserMinimumSizeHint();
                checks::events::sendMouse(*field, QEvent::MouseButtonPress, QPointF(start),
                                          Qt::LeftButton, Qt::LeftButton, modifiers);
                check(!field->hasFocus(), "pressing an ADSR input moved focus before dragging");
                checks::events::sendMouse(*field, QEvent::MouseMove, QPointF(activated),
                                          Qt::NoButton, Qt::LeftButton, modifiers);
                checks::events::sendMouse(*field, QEvent::MouseMove, QPointF(finish), Qt::NoButton,
                                          Qt::LeftButton, modifiers);
                check(field->geometry() == fieldGeometry &&
                          field->parentWidget()->geometry() == rowGeometry &&
                          voicegroupDriver.browserMinimumSizeHint() == browserMinimumSize,
                      "ADSR input geometry shifted when dragging began");
                checks::events::sendMouse(*field, QEvent::MouseButtonRelease, QPointF(finish),
                                          Qt::LeftButton, Qt::NoButton, modifiers);
            };
            const int uiValue = original.release == 25 ? 26 : 25;
            releaseSpin->setValue(uiValue);
            check(settled([&] {
                      const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                      return applied && applied->dirty && !tab->document().isDirty() &&
                             applied->slotViews.at(dsSlot).voice &&
                             applied->slotViews.at(dsSlot).voice->release == uiValue &&
                             voicegroupDriver.releaseSpinBox() &&
                             voicegroupDriver.releaseSpinBox()->value() == uiValue;
                  }) == checks::async_wait::Result::Ready,
                  "editing the Release spin box did not push an undo command");
            historyStep(true, "undoing the Release spin edit did not settle");
            check(settled([&] {
                      const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                      return applied && !applied->dirty && !tab->document().isDirty() &&
                             voicegroupDriver.releaseSpinBox() &&
                             voicegroupDriver.releaseSpinBox()->value() == original.release;
                  }) == checks::async_wait::Result::Ready,
                  "undo did not refresh the Release spin box");
            if (releaseSpin && releaseEdit) {
                // Each gesture is one commit (the spin emits one
                // valueChanged), and the preceding baseline setValue merges
                // with it: one undo per drag restores the original.
                const auto dragTo = [&](int pixels, Qt::KeyboardModifiers modifiers,
                                        int expectedValue, const char *what) {
                    releaseSpin->setValue(100);
                    if (!check(settled([&] {
                                   const LoadedBankView *const applied =
                                       voicegroupDriver.selectedBankView();
                                   return applied && applied->slotViews.at(dsSlot).voice &&
                                          applied->slotViews.at(dsSlot).voice->release == 100;
                               }) == checks::async_wait::Result::Ready,
                               what))
                        return;
                    dragVertically(releaseEdit, pixels, modifiers);
                    check(settled([&] {
                              const LoadedBankView *const applied =
                                  voicegroupDriver.selectedBankView();
                              return applied && applied->slotViews.at(dsSlot).voice &&
                                     applied->slotViews.at(dsSlot).voice->release ==
                                         expectedValue &&
                                     voicegroupDriver.releaseSpinBox() &&
                                     voicegroupDriver.releaseSpinBox()->value() == expectedValue;
                          }) == checks::async_wait::Result::Ready,
                          what);
                    historyStep(true, what);
                    check(settled([&] {
                              const LoadedBankView *const applied =
                                  voicegroupDriver.selectedBankView();
                              return applied && !applied->dirty && !tab->document().isDirty() &&
                                     voicegroupDriver.releaseSpinBox() &&
                                     voicegroupDriver.releaseSpinBox()->value() == original.release;
                          }) == checks::async_wait::Result::Ready,
                          what);
                };
                dragTo(12, Qt::NoModifier, 106,
                       "dragging the Release input up did not increase its value");
                dragTo(-12, Qt::NoModifier, 94,
                       "dragging the Release input down did not decrease its value");
                dragTo(20, Qt::ShiftModifier, 104,
                       "Shift-dragging the Release input did not use the precision rate");
            }
        }
    }

    // 6a. A source-undefined row stays visibly blank, but selecting its
    // DirectSound template and choosing another type creates an undoable
    // structural voice at that exact slot.
    {
        int blankSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE && blankSlot < 0; i++) {
            if (!voicegroupDriver.selectedBankView()->slotViews.at(i).voice)
                blankSlot = i;
        }
        const QStringList blankRow =
            blankSlot >= 0 ? voicegroupDriver.slotRowText(blankSlot) : QStringList();
        if (check(blankSlot >= 0, "voicegroup has no undefined slot") &&
            check(blankRow.size() == 3, "voicegroup browser has no row for the blank slot")) {
            check(blankRow.at(0) == QStringLiteral("%1  %2")
                                        .arg(blankSlot, 3, 10, QLatin1Char('0'))
                                        .arg(tr("[Blank]")) &&
                      blankRow.at(1).isEmpty() && blankRow.at(2).isEmpty(),
                  "undefined voice row does not show [Blank] in the Voice column");
            voicegroupDriver.selectSlot(blankSlot);
            check(voicegroupDriver.editorNoticeText().isEmpty() &&
                      voicegroupDriver.editorNoticeIsHidden(),
                  "empty slot editor still shows its instructional caption");
            check(voicegroupDriver.sampleActionButtonsHaveMatchingFixedSize(),
                  "sample action buttons do not have matching fixed dimensions");
            if (check(voicegroupDriver.visibleVoiceTypeData() >= 0,
                      "empty slot did not show the type template")) {
                check(voicegroupDriver.visibleVoiceTypeData() == int(VgMacro::DirectSound),
                      "empty slot template is not DirectSound");
                if (check(voicegroupDriver.activateVoiceType(VgMacro::Square1),
                          "empty slot type template could not activate Square 1")) {
                    // The blank-slot materialization is a bank edit: the
                    // applied view must show the Square 1 voice and the
                    // engine must have reloaded the slot.
                    const auto createdWait = settled([this, tab, blankSlot] {
                        const LoadedVoiceGroup *engine = m_audio.voicegroup();
                        return tab->voicegroupId() && engine &&
                               engine->voices[blankSlot].type == VOICE_SQUARE_1;
                    });
                    check(createdWait == checks::async_wait::Result::Ready,
                          "structural blank-slot voicegroup load did not complete");
                }
                const LoadedBankView *created = voicegroupDriver.selectedBankView();
                check(created && created->slotViews.at(blankSlot).voice &&
                          created->slotViews.at(blankSlot).voice->macro == VgMacro::Square1 &&
                          created->dirty && !tab->document().isDirty() && m_audio.voicegroup() &&
                          m_audio.voicegroup()->voices[blankSlot].type == VOICE_SQUARE_1,
                      "type choice did not create and reload the blank slot");
                historyStep(true, "undoing the blank-slot type choice did not settle");
                const QStringList restoredBlankRow = voicegroupDriver.slotRowText(blankSlot);
                {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    check(applied && !applied->slotViews.at(blankSlot).voice &&
                              !tab->document().isDirty() && !applied->dirty &&
                              restoredBlankRow.size() == 3 &&
                              restoredBlankRow.at(0) == QStringLiteral("%1  %2")
                                                            .arg(blankSlot, 3, 10, QLatin1Char('0'))
                                                            .arg(tr("[Blank]")) &&
                              restoredBlankRow.at(1).isEmpty() && restoredBlankRow.at(2).isEmpty(),
                          "undo did not restore the blank slot cleanly");
                }
                historyStep(false, "redoing the blank-slot type choice did not settle");
                check(settled([this, tab, blankSlot] {
                          const LoadedVoiceGroup *engine = m_audio.voicegroup();
                          return engine && engine->voices[blankSlot].type == VOICE_SQUARE_1;
                      }) == checks::async_wait::Result::Ready,
                      "redo did not reload the created slot");
                created = voicegroupDriver.selectedBankView();
                check(created && created->slotViews.at(blankSlot).voice &&
                          created->slotViews.at(blankSlot).voice->macro == VgMacro::Square1 &&
                          m_audio.voicegroup() &&
                          m_audio.voicegroup()->voices[blankSlot].type == VOICE_SQUARE_1,
                      "redo did not restore the created slot");
                historyStep(true, "undoing the redone blank-slot type choice did not settle");
                check(settled([&] {
                          const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                          return applied && !applied->slotViews.at(blankSlot).voice;
                      }) == checks::async_wait::Result::Ready,
                      "the final blank-slot undo did not settle");
            }
        }
    }

    // 6b. Selecting voices of different families must not change the dock's
    // minimum width: the editor adapts to the dock width the user set, never
    // pushes the dock open (a DS voice's three-digit ADSR spins used to
    // widen it relative to a CGB voice's one-digit ones).
    {
        int cgbSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE && cgbSlot < 0; i++) {
            const std::optional<VgVoice> &slotVoice =
                voicegroupDriver.selectedBankView()->slotViews.at(i).voice;
            if (slotVoice && vgMacroIsCgb(slotVoice->macro))
                cgbSlot = i;
        }
        if (cgbSlot >= 0) {
            // The window must be shown for the measurement: hidden widgets
            // are empty layout items and contribute no minimum.
            show();
            QCoreApplication::processEvents();
            voicegroupDriver.selectSlot(cgbSlot);
            QCoreApplication::processEvents();
            const int cgbMin = voicegroupDriver.browserMinimumSizeHint().width();
            voicegroupDriver.selectSlot(dsSlot);
            QCoreApplication::processEvents();
            check(voicegroupDriver.browserMinimumSizeHint().width() == cgbMin,
                  "voice selection changed the voicegroup dock's minimum width");
        } else {
            std::printf("vgsavecheck: note: no CGB voice found, "
                        "dock-width check skipped\n");
        }
    }

    // 7. Golden Sun synth param edits: minted definitions live in memory
    // only (no disk write, not in the definition dropdown) until the
    // voicegroup saves — and the save writes exactly the definitions the
    // saved state references, never the abandoned intermediate tweaks.
    {
        // Give the scratch project synth support: the macros (gate) and one
        // definition, appended so a project that already has them is fine.
        const QString synthPath =
            projectRoot + QStringLiteral("/sound/direct_sound_synth_data.inc");
        QDir().mkpath(projectRoot + QStringLiteral("/asm/macros"));
        bool wrote = false;
        {
            QFile macros(projectRoot + QStringLiteral("/asm/macros/vgsavecheck_synth.inc"));
            wrote = macros.open(QIODevice::WriteOnly) &&
                    macros.write("\t.macro set_synth_pulse base_duty=0x80, "
                                 "duty_step=0x00, mod_depth=0x00, duty_phase=0x00\n"
                                 "\t.endm\n"
                                 "\t.macro set_synth_saw\n\t.endm\n"
                                 "\t.macro set_synth_triangle\n\t.endm\n") > 0;
        }
        {
            QFile data(synthPath);
            wrote = wrote && data.open(QIODevice::WriteOnly | QIODevice::Append) &&
                    data.write("\n\t.align 2\nVgSaveCheckSaw::\n\tset_synth_saw\n") > 0;
        }
        if (!check(wrote, "cannot write synth support files"))
            return false;
        // The worker owns the catalog now: rescan through the typed seam and
        // await the new definition in the published state before touching
        // the retained editor.
        m_projectWorkspace->submit(ProjectOperation{RefreshCatalogInput{}});
        check(settled([&] {
                  return m_workspace->projectState().catalog.synths.find(
                             QStringLiteral("VgSaveCheckSaw")) != nullptr;
              }) == checks::async_wait::Result::Ready,
              "synth catalog refresh did not finish");
        const VgSynthCatalog setupCatalog = VoicegroupSource::synthInstruments(projectRoot);
        const int defsAfterSetup = setupCatalog.defs.size();
        const QByteArray synthBytesSetup = readFileBytes(synthPath);
        const int indexBeforeSynth = doc.undoStack()->index();

        // A sample voice that is NOT already a synth (a synth-heavy
        // voicegroup's first DirectSound voice may be one, and switching it
        // to Synth would rightly be a no-op).
        int synthSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE && synthSlot < 0; i++) {
            const std::optional<VgVoice> &slotVoice =
                voicegroupDriver.selectedBankView()->slotViews.at(i).voice;
            if (slotVoice &&
                (slotVoice->macro == VgMacro::DirectSound ||
                 slotVoice->macro == VgMacro::DirectSoundNoResample ||
                 slotVoice->macro == VgMacro::DirectSoundAlt) &&
                !setupCatalog.find(slotVoice->symbol))
                synthSlot = i;
        }
        if (synthSlot < 0) {
            std::printf("vgsavecheck: note: every sample voice is already a "
                        "synth, synth section skipped\n");
            std::printf("vgsavecheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
            return failures == 0;
        }
        const VgVoice synthOriginal =
            *voicegroupDriver.selectedBankView()->slotViews.at(synthSlot).voice;

        voicegroupDriver.selectSlot(synthSlot);
        if (check(voicegroupDriver.hasSynthEditorControls(), "synth editor widgets not found") &&
            check(voicegroupDriver.activateSynthType(), "synth type control did not activate")) {
            const auto synthTypeWait =
                settled([this, tab, synthSlot, &voicegroupDriver, &synthOriginal] {
                    const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                    const LoadedVoiceGroup *engine = m_audio.voicegroup();
                    const ToneData *tone = engine ? &engine->voices[synthSlot] : nullptr;
                    return applied && applied->slotViews.at(synthSlot).voice &&
                           applied->slotViews.at(synthSlot).voice->symbol != synthOriginal.symbol &&
                           tone && tone->wav && tone->wav->size == 0;
                });
            check(synthTypeWait == checks::async_wait::Result::Ready,
                  "synth type voicegroup load did not complete");
            check(voicegroupDriver.selectedBankView()->slotViews.at(synthSlot).voice->symbol !=
                      synthOriginal.symbol,
                  "switching the voice to Synth did not take");
            // The 50%-square default: flipping the saw definition to Pulse
            // adopts the default instead of the saw's zeroed (silent,
            // duty-0) params. Each param commit renames the voice to its
            // param-named symbol; the pending bank gate commits one edit per
            // worker round trip, so the fields settle one by one, like a
            // real-user pacing.
            check(voicegroupDriver.activateSynthWave(0),
                  "synth pulse waveform control did not activate");
            const QString defaultPulseSymbol = vgSynthSymbolName(VgSynthDesc{});
            check(settled([this, synthSlot, &voicegroupDriver, &defaultPulseSymbol] {
                      const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                      return applied && applied->slotViews.at(synthSlot).voice &&
                             applied->slotViews.at(synthSlot).voice->symbol == defaultPulseSymbol;
                  }) == checks::async_wait::Result::Ready,
                  "the pulse flip did not adopt the 50% default");
            struct SynthParam {
                int value;
                int VgSynthDesc::*field;
                const char *what;
            };
            const SynthParam paramScript[] = {
                {0x21, &VgSynthDesc::baseDuty, "the base duty edit did not land"},
                {0x43, &VgSynthDesc::dutyStep, "the duty LFO step edit did not land"},
                {0x65, &VgSynthDesc::modDepth, "the modulation depth edit did not land"},
                {0x87, &VgSynthDesc::phase, "the phase edit did not land"},
            };
            VgSynthDesc soFar{};
            bool paramsOk = true;
            for (int index = 0; index < int(std::size(paramScript)); ++index) {
                const SynthParam &param = paramScript[index];
                QSpinBox *const field = voicegroupDriver.synthParameterField(index);
                if (!check(field != nullptr, "synth parameter fields disappeared")) {
                    paramsOk = false;
                    break;
                }
                soFar.*param.field = param.value;
                field->setValue(param.value);
                const QString stepSymbol = vgSynthSymbolName(soFar);
                if (!check(settled([this, synthSlot, &voicegroupDriver, &stepSymbol] {
                               const LoadedBankView *const applied =
                                   voicegroupDriver.selectedBankView();
                               return applied && applied->slotViews.at(synthSlot).voice &&
                                      applied->slotViews.at(synthSlot).voice->symbol == stepSymbol;
                           }) == checks::async_wait::Result::Ready,
                           param.what)) {
                    paramsOk = false;
                    break;
                }
            }
            const QString wantSymbol = vgSynthSymbolName(VgSynthDesc{0, 0x21, 0x43, 0x65, 0x87});
            if (check(paramsOk, "a synth param edit did not land on the param-named symbol") &&
                check(voicegroupDriver.selectedBankView()->slotViews.at(synthSlot).voice->symbol ==
                          wantSymbol,
                      "param edits did not land on the param-named symbol")) {
                check(readFileBytes(synthPath) == synthBytesSetup,
                      "a param edit wrote to the synth data file before save");
                const bool listed = voicegroupDriver.visibleSymbolComboContains(wantSymbol);
                check(!listed, "an unsaved definition appeared in the dropdown");
                const auto paramEditWait = settled([this, synthSlot, &wantSymbol] {
                    const LoadedVoiceGroup *engine = m_audio.voicegroup();
                    return engine && engine->voices[synthSlot].wav &&
                           engine->voices[synthSlot].wav->size == 0 &&
                           uint8_t(engine->voices[synthSlot].wav->data[1]) == 0 &&
                           uint8_t(engine->voices[synthSlot].wav->data[2]) == 0x21 &&
                           uint8_t(engine->voices[synthSlot].wav->data[5]) == 0x87 &&
                           QString::fromUtf8(engine->voiceNames[synthSlot]) == wantSymbol;
                });
                check(paramEditWait == checks::async_wait::Result::Ready,
                      "param edits were not patched into the loaded tone");

                // Save: exactly one definition (the referenced one) is
                // written, it reaches the published catalog (and then the
                // dropdown), and the synth data file is wired into the build
                // (sound_data.s .include).
                check(waitForSave("synth save"), "synth save failed");
                check(readFileBytes(synthPath).contains(wantSymbol.toUtf8() + "::"),
                      "save did not write the referenced synth definition");
                bool wired = false;
                for (const QString &dir : {projectRoot + QStringLiteral("/data"), projectRoot}) {
                    QDirIterator wiredIt(dir, {QStringLiteral("*.s")}, QDir::Files);
                    while (wiredIt.hasNext() && !wired)
                        wired =
                            readFileBytes(wiredIt.next()).contains("direct_sound_synth_data.inc");
                }
                check(wired, "save did not wire the synth data file into the build");
                check(VoicegroupSource::synthInstruments(projectRoot).defs.size() ==
                          defsAfterSetup + 1,
                      "save wrote more than the one referenced definition");
                m_projectWorkspace->submit(ProjectOperation{RefreshCatalogInput{}});
                check(settled([&] {
                          return m_workspace->projectState().catalog.synths.find(wantSymbol) !=
                                 nullptr;
                      }) == checks::async_wait::Result::Ready,
                      "the saved synth definition did not reach the catalog");
                check(voicegroupDriver.visibleSymbolComboContains(wantSymbol),
                      "the saved definition did not appear in the dropdown");

                // Waveform flips: to Saw the edit dedupes onto the setup's
                // on-disk definition; back to Pulse it must adopt the 50%
                // square default, not commit the saw's zeroed (silent,
                // duty-0) params.
                const int indexBeforeFlips = doc.undoStack()->index();
                check(voicegroupDriver.activateSynthWave(1),
                      "synth saw waveform control did not activate");
                check(settled([this, synthSlot, &voicegroupDriver, &wantSymbol] {
                          const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                          return applied && applied->slotViews.at(synthSlot).voice &&
                                 applied->slotViews.at(synthSlot).voice->symbol != wantSymbol;
                      }) == checks::async_wait::Result::Ready,
                      "the saw flip did not land");
                const QString sawSymbol =
                    voicegroupDriver.selectedBankView()->slotViews.at(synthSlot).voice->symbol;
                // find() points into the catalog: it must outlive the pointer.
                const VgSynthCatalog sawCatalog = VoicegroupSource::synthInstruments(projectRoot);
                const VgSynthDesc *sawDef = sawCatalog.find(sawSymbol);
                check(sawDef && sawDef->waveform == 1,
                      "waveform flip to saw did not dedupe onto an on-disk saw");
                check(voicegroupDriver.activateSynthWave(0),
                      "synth pulse waveform control did not reactivate");
                check(settled([this, synthSlot, &voicegroupDriver, &sawSymbol] {
                          const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                          return applied && applied->slotViews.at(synthSlot).voice &&
                                 applied->slotViews.at(synthSlot).voice->symbol != sawSymbol;
                      }) == checks::async_wait::Result::Ready,
                      "the pulse reactivation did not land");
                // Deduped onto an on-disk 50% pulse when the project has
                // one, minted under the param name otherwise — never the
                // duty-0 name.
                const QString pulseSymbol =
                    voicegroupDriver.selectedBankView()->slotViews.at(synthSlot).voice->symbol;
                const VgSynthCatalog pulseCatalog = VoicegroupSource::synthInstruments(projectRoot);
                const VgSynthDesc *pulseDef = pulseCatalog.find(pulseSymbol);
                check((pulseDef && *pulseDef == VgSynthDesc{}) ||
                          pulseSymbol == vgSynthSymbolName(VgSynthDesc{}),
                      "waveform flip back to pulse did not adopt the 50% default");
                while (doc.undoStack()->index() > indexBeforeFlips)
                    historyStep(true, "undoing the waveform flips did not settle");
                check(voicegroupDriver.selectedBankView()->slotViews.at(synthSlot).voice->symbol ==
                          wantSymbol,
                      "undoing the waveform flips did not restore the voice");

                // Back to the original voice; the .inc round-trips, and no
                // further definitions are written.
                const QByteArray synthBytesSaved = readFileBytes(synthPath);
                while (doc.undoStack()->index() > indexBeforeSynth)
                    historyStep(true, "undoing the synth edits did not settle");
                check(waitForSave("post-undo save"), "post-undo save failed");
                check(readFileBytes(vgPath) == vgBytesOriginal,
                      "undone synth edits did not round-trip the .inc");
                check(readFileBytes(synthPath) == synthBytesSaved,
                      "the post-undo save wrote synth definitions");
            }
        }
    }

    // Jump-from-context reveal and used-voice marks: rows for programs the
    // song references render with a highlighted background, revealTrackVoice
    // raises the dock and selects the track's current program, and document
    // edits that add or remove voice changes keep the marks in sync.
    {
        if (check(!voicegroupDriver.slotRowText(0).isEmpty(),
                  "voicegroup browser has no tree rows")) {
            const QSet<int> used = view.usedVoices();
            check(!used.isEmpty(), "song reports no used voices");
            int unused = -1;
            for (int i = 0; i < VOICEGROUP_SIZE && unused < 0; i++) {
                if (!used.contains(i))
                    unused = i;
            }
            const bool marksOk =
                std::all_of(used.cbegin(), used.cend(), [&voicegroupDriver](int slot) {
                    return voicegroupDriver.slotIsMarkedUsed(slot);
                });
            check(marksOk, "used voices are not highlighted in the dock");
            check(unused < 0 || !voicegroupDriver.slotIsMarkedUsed(unused),
                  "an unused voice is highlighted");

            // Track-header path: the dock reappears and the track's current
            // program becomes the selected slot.
            voicegroupDriver.hideDock();
            const int prog = view.currentProgram(track);
            check(prog >= 0, "track under test has no program");
            view.revealTrackVoice(track);
            check(!voicegroupDriver.dockIsHidden(), "reveal did not show the voicegroup dock");
            check(voicegroupDriver.currentSlot() == prog,
                  "reveal did not select the track's program");

            if (unused >= 0) {
                // Explicit-program path (the event list's context menu).
                view.revealVoice(unused);
                check(voicegroupDriver.currentSlot() == unused,
                      "revealVoice did not select the requested slot");

                // A new voice change gains the mark; undoing it clears it.
                doc.addLanePoint(track, DOC_CC_VOICE, 480, unused);
                check(voicegroupDriver.slotIsMarkedUsed(unused),
                      "a new voice change did not gain the used mark");
                historyStep(true, "undoing the voice change did not settle");
                check(!voicegroupDriver.slotIsMarkedUsed(unused),
                      "undoing the voice change did not clear the used mark");
            }
        }
    }

    // 9. A structural commit fired from inside a track header's own mouse
    // press must not free that header row mid-event: with a changed arg
    // typed into the voicegroup selector's line edit, clicking a header
    // focuses the roll (selectTrack), which fires editingFinished — an
    // undoable -G switch whose voicegroup swap rebuilds the header panel
    // while the clicked row's mousePressEvent is still on the stack. The
    // row has to survive its own press (deferred deletion), or this is a
    // use-after-free crash. (The sample symbol box that originally hit this
    // is now the picker, which commits from its popup instead of on focus
    // loss — the selector keeps the scenario alive.)
    if (otherArg.isEmpty()) {
        std::printf("vgsavecheck: note: no second voicegroup found, "
                    "mid-press structural rebuild skipped\n");
    } else {
        show();
        activateWindow();
        QCoreApplication::processEvents();
        const QString argBefore = tab->document().cfg().voicegroupArg;
        QComboBox *vgCombo = voicegroupDriver.voicegroupSelector();
        int otherTrack = -1;
        const MidiTimeline *tl = view.timeline();
        for (int t = 0; t < 16 && otherTrack < 0 && tl; t++) {
            if (t != view.selectionModel().primaryTrack() && tl->tracks[t].used)
                otherTrack = t;
        }
        if (check(vgCombo && otherTrack >= 0,
                  "no vg selector or second track for the mid-press commit")) {
            QLineEdit *edit = vgCombo->lineEdit();
            edit->setFocus();
            QCoreApplication::processEvents();
            if (check(edit->hasFocus(), "vg selector did not take focus")) {
                edit->setText(otherArg);
                QPointer<QWidget> row =
                    view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(otherTrack));
                if (check(row != nullptr, "no header row for the other track")) {
                    const QPoint pos(5, 5);
                    checks::events::sendMouse(*row, QEvent::MouseButtonPress, QPointF(pos),
                                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                    check(!row.isNull(), "header rebuild freed the row inside its own press");
                    check(view.selectionModel().primaryTrack() == otherTrack,
                          "the header click did not select its track");
                    check(tab->document().cfg().voicegroupArg == otherArg,
                          "the mid-press -G edit did not commit");
                    if (!row.isNull()) {
                        checks::events::sendMouse(*row, QEvent::MouseButtonRelease, QPointF(pos),
                                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                    }
                }
                QCoreApplication::processEvents(); // deferred row deletion
                const auto midPressSwitchWait = settled([&] {
                    return tab->document().cfg().voicegroupArg == otherArg && tab->voicegroupId() &&
                           *tab->voicegroupId() != homeId;
                });
                check(midPressSwitchWait == checks::async_wait::Result::Ready,
                      "mid-press voicegroup load did not complete");
                // The rebuilt panel is functional: its fresh rows select.
                QWidget *fresh =
                    view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
                if (check(fresh != nullptr, "no rebuilt header row") && track != otherTrack) {
                    checks::events::sendMouse(*fresh, QEvent::MouseButtonPress,
                                              QPointF(QPoint(5, 5)), Qt::LeftButton, Qt::LeftButton,
                                              Qt::NoModifier);
                    checks::events::sendMouse(*fresh, QEvent::MouseButtonRelease,
                                              QPointF(QPoint(5, 5)), Qt::LeftButton, Qt::NoButton,
                                              Qt::NoModifier);
                    QCoreApplication::processEvents();
                    check(view.selectionModel().primaryTrack() == track,
                          "a rebuilt header row did not select its track");
                }
                historyStep(true, "undoing the mid-press -G switch did not settle");
                const auto midPressUndoWait =
                    settled([this, tab, &voicegroupDriver, homeId, &argBefore] {
                        return tab->document().cfg().voicegroupArg == argBefore &&
                               tab->voicegroupId() && *tab->voicegroupId() == homeId;
                    });
                check(midPressUndoWait == checks::async_wait::Result::Ready,
                      "undoing the mid-press voicegroup load did not complete");
                check(tab->document().cfg().voicegroupArg == argBefore && tab->voicegroupId() &&
                          *tab->voicegroupId() == homeId,
                      "undo did not restore the mid-press -G switch");
            }
        }
    }

    // 10. The sample picker (the Sample field for DirectSound voices):
    // replaces the giant combo, filters by typed text, auditions the
    // highlighted sample, marks looped samples, commits an undoable symbol
    // change, and still accepts an unlisted typed symbol.
    {
        // The catalog (samples, waves, keysplits) arrives through the
        // published project state; the popup renders from it alone.
        const QStringList progWaves = m_workspace->projectState().catalog.progWave;
        voicegroupDriver.revealSlot(dsSlot);
        QCoreApplication::processEvents();
        if (check(voicegroupDriver.hasSamplePickerEditor(), "no sample picker in the editor")) {
            check(voicegroupDriver.samplePickerReplacesSymbolCombo(),
                  "sample voice does not show the picker instead of the combo");
            const VgVoice before = *voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice;
            check(voicegroupDriver.samplePickerCurrentSymbol() == before.symbol,
                  "picker does not show the voice's symbol");

            QStringList auditioned;
            QList<VgAuditionKind> auditionKinds;
            int stops = 0;
            QMetaObject::Connection c1 =
                connect(m_workspace.get(), &WorkspaceUi::sampleAuditionRequested, this,
                        [&auditioned, &auditionKinds](const QString &s, VgAuditionKind kind,
                                                      const AuditionSlots::Adsr &) {
                            auditioned.append(s);
                            auditionKinds.append(kind);
                        });
            QMetaObject::Connection c2 =
                connect(m_workspace.get(), &WorkspaceUi::sampleAuditionStopRequested, this,
                        [&stops] { stops++; });

            voicegroupDriver.openSamplePickerPopup();
            QLineEdit *search = voicegroupDriver.samplePickerFilterField();
            if (check(search && voicegroupDriver.samplePickerPopupIsVisible(),
                      "picker popup did not open")) {
                // The popup floats over the browser, so it carries the menu
                // outline; its corner pixel is that border.
                check(voicegroupDriver.samplePickerPopupCornerColor() ==
                          themes::color(themes::Role::menu_outline),
                      "the picker popup is missing the menu outline");
                // Every catalog sample is listed, and the committed sample
                // data drives at least one loop badge after its lazy load.
                check(voicegroupDriver.samplePickerSymbolRowCount() >= 2,
                      "picker lists fewer than two symbols");
                check(settled([&] { return voicegroupDriver.samplePickerBadgedRowCount() > 0; }) ==
                          checks::async_wait::Result::Ready,
                      "no loop badges on any sample row");

                // Keysplit rows audition too — the resolved sub-voice plays
                // (MainWindow::auditionKeysplit), so browsing them is
                // audible like everything else.
                const int keysplitSeen = auditioned.size();
                if (voicegroupDriver.selectFirstKeysplitPickerRow()) {
                    check(auditioned.size() == keysplitSeen + 1 &&
                              auditionKinds.last() == VgAuditionKind::Keysplit,
                          "keysplit row did not audition as a keysplit");
                } else {
                    std::printf("vgsavecheck: note: no keysplit instruments, "
                                "keysplit audition skipped\n");
                }

                if (!screenshotPath.isEmpty()) {
                    check(voicegroupDriver.saveSamplePickerPopup(screenshotPath),
                          "could not save the picker screenshot");
                    // A -dock variant of the browser itself: the editor
                    // panel's Sample row (picker + glyph tool buttons).
                    const QFileInfo info(screenshotPath);
                    check(voicegroupDriver.saveBrowser(info.path() + QLatin1Char('/') +
                                                       info.completeBaseName() +
                                                       QStringLiteral("-dock.") + info.suffix()),
                          "could not save the dock screenshot");
                }

                // Filtering highlights and auditions a different plain sample.
                // The first mouse click only selects it; clicking that same
                // row again commits the undoable voice edit. The highlight
                // audition lazily loads the shared sample set through the
                // production relay.
                const QString target =
                    voicegroupDriver.firstAlternatePlainPickerSymbol(before.symbol);
                if (check(!target.isEmpty(), "no alternate sample to pick")) {
                    search->setText(target);
                    check(auditioned.contains(target),
                          "filtering onto a sample did not audition it");
                    check(settled([] { return true; }) == checks::async_wait::Result::Ready &&
                              m_workspace->sampleSet() != nullptr,
                          "the picker's first audition did not load the shared sample set");
                    if (check(voicegroupDriver.currentPickerRowSymbol() == target,
                              "filter did not select the target sample")) {
                        voicegroupDriver.clickCurrentPickerRow();
                        check(voicegroupDriver.samplePickerPopupIsVisible() &&
                                  voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice &&
                                  voicegroupDriver.selectedBankView()
                                          ->slotViews.at(dsSlot)
                                          .voice->symbol == before.symbol,
                              "first sample click committed instead of selecting");
                        voicegroupDriver.clickCurrentPickerRow();
                        check(!voicegroupDriver.samplePickerPopupIsVisible(),
                              "second sample click did not close the popup");
                        check(stops > 0, "closing the popup did not stop audition");
                        check(settled([&] {
                                  const LoadedBankView *const applied =
                                      voicegroupDriver.selectedBankView();
                                  return applied && applied->slotViews.at(dsSlot).voice &&
                                         applied->slotViews.at(dsSlot).voice->symbol == target;
                              }) == checks::async_wait::Result::Ready,
                              "the picked symbol did not commit");
                        check(!tab->document().isDirty() &&
                                  voicegroupDriver.selectedBankView()->dirty,
                              "the picked symbol dirtied the bank, not the document");
                        historyStep(true, "undoing the picked sample did not settle");
                        check(settled([&] {
                                  const LoadedBankView *const applied =
                                      voicegroupDriver.selectedBankView();
                                  return applied && applied->slotViews.at(dsSlot).voice &&
                                         applied->slotViews.at(dsSlot).voice->symbol ==
                                             before.symbol;
                              }) == checks::async_wait::Result::Ready,
                              "undoing the picked sample preview did not complete");
                        check(voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice &&
                                  voicegroupDriver.selectedBankView()
                                          ->slotViews.at(dsSlot)
                                          .voice->symbol == before.symbol,
                              "undo did not restore the picked symbol");
                        check(voicegroupDriver.samplePickerCurrentSymbol() == before.symbol,
                              "undo did not refresh the picker's label");
                    }
                }

                // An unlisted symbol still commits via the typed-text row
                // (the editable combo's old superpower).
                voicegroupDriver.openSamplePickerPopup();
                const QString unlisted = QStringLiteral("VgSaveCheckUnlisted");
                search = voicegroupDriver.samplePickerFilterField();
                if (check(search != nullptr, "picker filter disappeared after reopening")) {
                    search->setText(unlisted);
                    checks::events::sendKey(*search, QEvent::KeyPress, Qt::Key_Return,
                                            Qt::NoModifier, QString(), false, 1);
                }
                check(settled([&] {
                          const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                          return applied && applied->slotViews.at(dsSlot).voice &&
                                 applied->slotViews.at(dsSlot).voice->symbol == unlisted;
                      }) == checks::async_wait::Result::Ready,
                      "an unlisted typed symbol did not commit");
                historyStep(true, "undoing the typed sample did not settle");
                check(settled([&] {
                          const LoadedBankView *const applied = voicegroupDriver.selectedBankView();
                          return applied && applied->slotViews.at(dsSlot).voice &&
                                 applied->slotViews.at(dsSlot).voice->symbol == before.symbol;
                      }) == checks::async_wait::Result::Ready,
                      "undoing the typed sample preview did not complete");
                check(voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice &&
                          voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice->symbol ==
                              before.symbol,
                      "undo did not restore the unlisted symbol");

                // Wave voices share the picker: switching the Type swaps the
                // list to the project's programmable waves, and highlighting
                // one auditions it as a CGB wave.
                if (progWaves.isEmpty()) {
                    std::printf("vgsavecheck: note: no programmable waves, "
                                "wave picker section skipped\n");
                } else {
                    int undos = 0;
                    if (check(voicegroupDriver.activateVoiceType(VgMacro::ProgWave),
                              "no Type combo")) {
                        undos++;
                        check(settled([this, tab, dsSlot, &voicegroupDriver] {
                                  const LoadedBankView *const applied =
                                      voicegroupDriver.selectedBankView();
                                  return applied && applied->slotViews.at(dsSlot).voice &&
                                         applied->slotViews.at(dsSlot).voice->macro ==
                                             VgMacro::ProgWave;
                              }) == checks::async_wait::Result::Ready,
                              "switching to a wave voice did not finish its preview");
                        const VgVoice waveVoice =
                            *voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice;
                        check(waveVoice.macro == VgMacro::ProgWave,
                              "type switch to Prog Wave did not take");
                        check(voicegroupDriver.samplePickerIsVisible() &&
                                  voicegroupDriver.samplePickerCurrentSymbol() == waveVoice.symbol,
                              "wave voice does not show the picker");

                        voicegroupDriver.openSamplePickerPopup();
                        const QString otherWave =
                            voicegroupDriver.firstAlternatePickerSymbol(waveVoice.symbol);
                        const QStringList pickerSymbols = voicegroupDriver.pickerSymbols();
                        check(std::all_of(pickerSymbols.cbegin(), pickerSymbols.cend(),
                                          [&progWaves](const QString &symbol) {
                                              return progWaves.contains(symbol);
                                          }),
                              "wave picker lists a non-wave symbol");
                        // Waves show the verbatim symbol (samples strip
                        // their shared prefix; waves don't).
                        check(voicegroupDriver.pickerRowsShowFullSymbols(),
                              "wave row does not show its full symbol");
                        if (otherWave.isEmpty()) {
                            std::printf("vgsavecheck: note: single wave, "
                                        "wave audition/pick skipped\n");
                            voicegroupDriver.hideSamplePickerPopup();
                        } else {
                            const int seen = auditioned.size();
                            search = voicegroupDriver.samplePickerFilterField();
                            check(search != nullptr, "wave picker filter disappeared");
                            if (search)
                                search->setText(otherWave);
                            check(auditioned.size() > seen && auditioned.last() == otherWave &&
                                      auditionKinds.last() == VgAuditionKind::Wave,
                                  "filtering onto a wave did not audition "
                                  "it as a wave");
                            if (search) {
                                checks::events::sendKey(*search, QEvent::KeyPress, Qt::Key_Return,
                                                        Qt::NoModifier, QString(), false, 1);
                            }
                            undos++;
                            check(settled([&] {
                                      const LoadedBankView *const applied =
                                          voicegroupDriver.selectedBankView();
                                      return applied && applied->slotViews.at(dsSlot).voice &&
                                             applied->slotViews.at(dsSlot).voice->symbol ==
                                                 otherWave;
                                  }) == checks::async_wait::Result::Ready,
                                  "the picked wave did not commit");
                        }
                        while (undos-- > 0)
                            historyStep(true, "undoing the wave round trip did not settle");
                        check(
                            settled([&] {
                                const LoadedBankView *const applied =
                                    voicegroupDriver.selectedBankView();
                                return applied && applied->slotViews.at(dsSlot).voice &&
                                       applied->slotViews.at(dsSlot).voice->macro == before.macro &&
                                       applied->slotViews.at(dsSlot).voice->symbol == before.symbol;
                            }) == checks::async_wait::Result::Ready,
                            "undoing the wave round trip did not finish its preview");
                        const VgVoice restored =
                            *voicegroupDriver.selectedBankView()->slotViews.at(dsSlot).voice;
                        check(restored.macro == before.macro && restored.symbol == before.symbol,
                              "undo did not restore the sample voice after "
                              "the wave round trip");
                    }
                }
            }
            disconnect(c1);
            disconnect(c2);
        }
    }

    // 11. New… creates the voicegroup file AND assigns it to the current
    // song — the same undoable cfg edit the selector makes, so undo returns
    // to the previous voicegroup. The modal dialog is filled and accepted
    // from a timer inside its own exec() loop.
    {
        const QString argBefore = tab->document().cfg().voicegroupArg;
        const QString newName = QStringLiteral("vgsavecheck_created");
        QTimer::singleShot(0, this, [this, newName] {
            for (QDialog *d : findChildren<QDialog *>()) {
                if (!d->isVisible() || d->windowTitle() != tr("New Voicegroup"))
                    continue;
                if (QLineEdit *edit = d->findChild<QLineEdit *>()) {
                    edit->setText(newName);
                    d->accept();
                } else {
                    d->reject(); // never hang the harness in exec()
                }
                return;
            }
        });
        m_workspace->runCreateVoicegroupFlow();
        const auto createWait = settled([this, tab, &projectRoot, &newName] {
            return tab->document().cfg().voicegroupArg == QStringLiteral("_") + newName &&
                   QFile::exists(projectRoot + QStringLiteral("/sound/voicegroups/") + newName +
                                 QStringLiteral(".inc")) &&
                   tab->voicegroupId() &&
                   tab->voicegroupId()->sourceRelativePath().endsWith(newName +
                                                                      QStringLiteral(".inc"));
        });
        check(createWait == checks::async_wait::Result::Ready,
              "New… voicegroup creation/load did not complete");
        check(QFile::exists(projectRoot + QStringLiteral("/sound/voicegroups/") + newName +
                            QStringLiteral(".inc")),
              "New… did not create the voicegroup file");
        check(tab->document().cfg().voicegroupArg == QStringLiteral("_") + newName &&
                  tab->document().isDirty(),
              "New… did not auto-assign the voicegroup as an undoable edit");
        check(tab->voicegroupId() && tab->voicegroupId()->sourceRelativePath().endsWith(
                                         newName + QStringLiteral(".inc")),
              "New… auto-assign did not swap the voicegroup source");
        historyStep(true, "undoing the New… auto-assign did not settle");
        const auto undoCreateWait =
            settled([this, tab, &voicegroupDriver, homeId, &argBefore, &vgLoadName] {
                return tab->document().cfg().voicegroupArg == argBefore && tab->voicegroupId() &&
                       *tab->voicegroupId() == homeId && voicegroupDriver.selectedBankView() &&
                       voicegroupDriver.selectedBankView()->loadName == vgLoadName;
            });
        check(undoCreateWait == checks::async_wait::Result::Ready,
              "undoing the New… voicegroup load did not complete");
        check(tab->document().cfg().voicegroupArg == argBefore && tab->voicegroupId() &&
                  *tab->voicegroupId() == homeId,
              "undoing the New… auto-assign did not restore the voicegroup");
    }

    disconnect(receiptConnection);
    std::fprintf(stderr, "vgsavecheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

int runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                   const QString &screenshotPath)
{
    MainWindow window;
    return window.runVgSaveCheck(projectRoot, songLabel, screenshotPath) ? 0 : 1;
}
