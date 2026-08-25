#include <QComboBox>
#include <QCoreApplication>
#include <QDialog>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QLineEdit>
#include <QPointer>
#include <QTimer>
#include <algorithm>
#include <cstdio>

#include "checks/support/eventsynth.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"
#include "project/songregistry.h"
#include "ui/dragspinbox.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/workspaceui.h"

extern "C" {
#include "voicegroup_loader.h"
}

// --vgsavecheck <projectRoot> <song>: unified song+voicegroup undo/save
// check. Song and voicegroup edits share one undo stack and one save, so
// this drives MainWindow itself: a voice edit dirties the song, undo
// restores the byte-exact on-disk state, Save writes the .mid and the
// voicegroup .inc together, and an undone edit saved again round-trips the
// .inc byte-identically. Also proves a -G voicegroup switch keeps unsaved
// voice edits in the undo history (undoing the switch replays them).
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
        return false;
    }
    QString error;
    if (!m_project.open(projectRoot, &error)) {
        std::fprintf(stderr, "vgsavecheck: %s\n", qUtf8Printable(error));
        return false;
    }
    const SongInfo *target = nullptr;
    for (const SongInfo &song : m_project.songs()) {
        if (song.label == songLabel && song.isPlayable())
            target = &song;
    }
    if (!target) {
        std::fprintf(stderr, "vgsavecheck: song '%s' not found or has no MIDI source\n",
                     qUtf8Printable(songLabel));
        return false;
    }
    loadSong(*target);
    SongSession *tab = activeSession();
    if (!m_audio.songLoaded() || !tab || tab->songId < 0) {
        std::fprintf(stderr, "vgsavecheck: song failed to load\n");
        return false;
    }
    if (!tab->vgSource) {
        std::fprintf(stderr, "vgsavecheck: no editable voicegroup source\n");
        return false;
    }
    SongView &view = m_workspace->viewFor(*tab);
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

    // A DirectSound-family voice to edit (scalar fields + a sample symbol).
    int dsSlot = -1;
    for (int i = 0; i < VOICEGROUP_SIZE && dsSlot < 0; i++) {
        const VgVoice *v = tab->vgSource->voiceAt(i);
        if (v && (v->macro == VgMacro::DirectSound || v->macro == VgMacro::DirectSoundNoResample ||
                  v->macro == VgMacro::DirectSoundAlt))
            dsSlot = i;
    }
    if (dsSlot < 0) {
        std::fprintf(stderr, "vgsavecheck: voicegroup has no sample voices\n");
        return false;
    }

    const QString vgPath = tab->vgSource->filePath();
    const QString vgLoadName = tab->vgSource->loadName();
    const QByteArray vgBytesOriginal = readFileBytes(vgPath);
    const QByteArray midBytesOriginal = readFileBytes(tab->doc.midPath());
    const VgVoice original = *tab->vgSource->voiceAt(dsSlot);

    // 1. A voice edit dirties the (one, unified) session.
    VgVoice edited = original;
    edited.release = original.release == 25 ? 26 : 25;
    onVoiceEditRequested(dsSlot, edited, false);
    check(tab->doc.isDirty(), "voice edit did not dirty the song's undo stack");
    check(tab->vgSource->dirty(), "voice edit did not dirty the source");
    check(isWindowModified(), "voice edit did not mark the window modified");
    check(m_audio.voicegroup()->voices[dsSlot].release == uint8_t(edited.release),
          "voice edit did not reach the audio engine");

    // 2. Undo restores the byte-exact on-disk state, nothing written.
    tab->doc.undoStack()->undo();
    check(!tab->doc.isDirty() && !tab->vgSource->dirty(),
          "undo did not return the session to clean");
    check(!isWindowModified(), "undo left the window marked modified");
    check(readFileBytes(vgPath) == vgBytesOriginal, "voicegroup file changed without a save");

    // 3. Redo the voice edit, add a note edit, save once: both files written.
    tab->doc.undoStack()->redo();
    int track = -1;
    for (int t = 0; t < tab->doc.engineTrackCount() && track < 0; t++) {
        if (!tab->doc.notesForTrack(t).empty())
            track = t;
    }
    if (track < 0) {
        std::fprintf(stderr, "vgsavecheck: song has no notes\n");
        return false;
    }
    uint64_t base = 0;
    for (const SmfTrack &tr : tab->doc.smf().tracks)
        base = std::max(base, tr.endTick);
    base += 96;
    tab->doc.addNote(track, base, 72, 24, 93);
    check(saveSession(*tab), "unified save failed");
    check(!tab->doc.isDirty() && !tab->vgSource->dirty(), "still dirty after save");
    check(readFileBytes(vgPath) != vgBytesOriginal, "save did not write the voicegroup file");
    check(readFileBytes(tab->doc.midPath()) != midBytesOriginal, "save did not write the .mid");
    {
        VoicegroupSource fresh;
        check(fresh.open(projectRoot, tab->doc.cfg().voicegroupArg, &error) &&
                  fresh.voiceAt(dsSlot) && fresh.voiceAt(dsSlot)->release == edited.release,
              "saved voice edit not present in a fresh parse");
    }

    // 4. Undo both edits and save again: the voicegroup .inc must come back
    // byte-identical to the original (byte-conservative round trip).
    tab->doc.undoStack()->undo(); // the note
    tab->doc.undoStack()->undo(); // the voice edit
    check(tab->doc.isDirty() && tab->vgSource->dirty(),
          "undo past the save point did not re-dirty the session");
    check(saveSession(*tab), "second unified save failed");
    check(readFileBytes(vgPath) == vgBytesOriginal,
          "undone voice edit did not round-trip the .inc byte-identically");

    // 5. A -G voicegroup switch carries unsaved voice edits in the undo
    // history: undoing the switch replays them into the reopened source.
    QString otherArg;
    for (const QString &arg : SongRegistry::voicegroupArgs(m_project.root())) {
        if (arg == tab->doc.cfg().voicegroupArg)
            continue;
        SongCfg probe = tab->doc.cfg();
        probe.voicegroupArg = arg;
        QString tried;
        if (LoadedVoiceGroup *vg = loadVoicegroupFor(probe, &tried)) {
            voicegroup_free(vg);
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
        onVoiceEditRequested(dsSlot, edited2, false);
        SongCfg cfg = tab->doc.cfg();
        cfg.voicegroupArg = otherArg;
        tab->doc.setCfg(cfg);
        check(tab->vgSource && tab->vgSource->loadName() != vgLoadName,
              "-G switch did not swap the voicegroup source");
        tab->doc.undoStack()->undo(); // the -G switch
        check(tab->vgSource && tab->vgSource->loadName() == vgLoadName,
              "undoing the -G switch did not reopen the old voicegroup");
        check(tab->vgSource && tab->vgSource->voiceAt(dsSlot) &&
                  tab->vgSource->voiceAt(dsSlot)->release == edited2.release &&
                  tab->vgSource->dirty(),
              "undoing the -G switch did not replay the unsaved voice edit");
        tab->doc.undoStack()->undo(); // the voice edit
        check(tab->vgSource && !tab->vgSource->dirty() && !tab->doc.isDirty(),
              "undoing the replayed voice edit did not return to clean");
        check(readFileBytes(vgPath) == vgBytesOriginal,
              "voicegroup file changed during the -G switch round trip");

        // 5b. The dock's voicegroup selector drives the same switch as an
        // undoable cfg edit, and undo refreshes the selector's text. The
        // selector shows args in display form: the leading underscore folds
        // into the fixed "voicegroup_" prefix.
        QComboBox *vgCombo = voicegroupDriver.voicegroupSelector();
        if (check(vgCombo != nullptr, "no voicegroup selector in the dock")) {
            const QString originalArg = tab->doc.cfg().voicegroupArg;
            const QString shown = SongRegistry::voicegroupDisplayName(
                originalArg.isEmpty() ? QStringLiteral("_dummy") : originalArg);
            check(vgCombo->isEnabled() && vgCombo->currentText() == shown,
                  "dock selector does not show the song's voicegroup");
            check(vgCombo->findText(SongRegistry::voicegroupDisplayName(otherArg)) >= 0,
                  "dock selector is missing a known voicegroup arg");
            vgCombo->setCurrentText(SongRegistry::voicegroupDisplayName(otherArg));
            QMetaObject::invokeMethod(vgCombo, "activated", Qt::DirectConnection, Q_ARG(int, 0));
            check(tab->doc.cfg().voicegroupArg == otherArg && tab->doc.isDirty(),
                  "dock selector did not commit an undoable -G switch");
            check(tab->vgSource && tab->vgSource->loadName() != vgLoadName,
                  "dock selector switch did not swap the voicegroup source");
            tab->doc.undoStack()->undo(); // the selector's -G switch
            check(tab->doc.cfg().voicegroupArg == originalArg && !tab->doc.isDirty(),
                  "undoing the dock selector switch did not restore the cfg");
            check(voicegroupDriver.voicegroupSelector() &&
                      voicegroupDriver.voicegroupSelector()->currentText() == shown,
                  "undo did not refresh the dock selector's text");
            check(tab->vgSource && tab->vgSource->loadName() == vgLoadName,
                  "undoing the dock selector switch did not reopen the old "
                  "voicegroup");
        }
    }

    // 5c. Reopening a clean same-name source replaces its backing object
    // without invalidating the undo stack.  Both an executed value command
    // and a command in the redo tail must resolve the current source.
    const auto reopenCleanSameVoicegroup = [&]() {
        const QString expectedLoadName = tab->vgSource ? tab->vgSource->loadName() : QString();
        const QByteArray diskBytes = readFileBytes(vgPath);
        openVoicegroupSource(*tab, tab->doc.cfg());
        updateVoicegroupBrowser();
        return check(tab->vgSource && tab->vgSource->loadName() == expectedLoadName &&
                         !tab->vgSource->dirty() && tab->vgSource->sourceBytes() == diskBytes,
                     "same-loadName reopen did not yield a clean on-disk source");
    };
    if (check(!tab->doc.isDirty() && !tab->vgSource->dirty(),
              "replacement-lifetime setup did not begin clean")) {
        VgVoice refreshEdited = original;
        refreshEdited.release = original.release == 255 ? 254 : original.release + 1;
        onVoiceEditRequested(dsSlot, refreshEdited, false);
        check(tab->vgSource->voiceAt(dsSlot) &&
                  tab->vgSource->voiceAt(dsSlot)->release == refreshEdited.release &&
                  tab->vgSource->dirty(),
              "value command did not execute before clean reopen");
        if (check(saveSession(*tab), "could not save value command before clean reopen") &&
            reopenCleanSameVoicegroup()) {
            const QByteArray refreshedValueBytes = readFileBytes(vgPath);
            tab->doc.undoStack()->undo();
            check(tab->vgSource->voiceAt(dsSlot) &&
                      tab->vgSource->voiceAt(dsSlot)->release == original.release &&
                      tab->vgSource->dirty() && tab->doc.isDirty() &&
                      readFileBytes(vgPath) == refreshedValueBytes,
                  "executed value command undo after reopen lost the current source state");
            tab->doc.undoStack()->redo();
            check(tab->vgSource->voiceAt(dsSlot) &&
                      tab->vgSource->voiceAt(dsSlot)->release == refreshEdited.release &&
                      !tab->vgSource->dirty() && !tab->doc.isDirty() &&
                      tab->vgSource->sourceBytes() == refreshedValueBytes,
                  "executed value command redo after reopen did not restore the clean source");

            // Save the undone state. The command is now a redo-tail command
            // while the freshly reopened source is clean and disk-authoritative.
            tab->doc.undoStack()->undo();
            if (check(saveSession(*tab), "could not restore the value-edit baseline") &&
                check(readFileBytes(vgPath) == vgBytesOriginal,
                      "value-edit baseline did not round-trip before redo-tail reopen") &&
                reopenCleanSameVoicegroup()) {
                tab->doc.undoStack()->redo();
                check(tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->release == refreshEdited.release &&
                          tab->vgSource->dirty() && tab->doc.isDirty() &&
                          readFileBytes(vgPath) == vgBytesOriginal,
                      "redo-tail value command after reopen did not apply to the current source");
                tab->doc.undoStack()->undo();
                check(tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->release == original.release &&
                          !tab->vgSource->dirty() && !tab->doc.isDirty(),
                      "undo after redo-tail reopen did not return to the clean baseline");
            }
        }
    }

    // 5d. A blank-slot command is structural, so replacing source bytes must
    // rebase its delta rather than restoring its old whole-file snapshots.
    int replacementBlankSlot = -1;
    for (int i = 0; i < VOICEGROUP_SIZE && replacementBlankSlot < 0; i++) {
        if (tab->vgSource->kindAt(i) == VgLineKind::None)
            replacementBlankSlot = i;
    }
    if (check(replacementBlankSlot >= 0,
              "voicegroup has no blank slot for replacement-lifetime coverage")) {
        const auto blankDraft = tab->vgSource->voiceDraft(replacementBlankSlot, original);
        if (check(blankDraft.has_value(), "blank slot did not provide a materialization draft")) {
            const VgVoice materialized = blankDraft->voice;
            onVoiceEditRequested(replacementBlankSlot, materialized, true);
            if (check(tab->vgSource->voiceAt(replacementBlankSlot) &&
                          *tab->vgSource->voiceAt(replacementBlankSlot) == materialized &&
                          tab->vgSource->dirty(),
                      "blank-slot command did not materialize before reopen") &&
                check(saveSession(*tab), "could not save blank-slot materialization")) {
                VoicegroupSource sibling;
                QString siblingError;
                VgVoice unrelated = original;
                unrelated.release = original.release == 255 ? 254 : original.release + 1;
                if (check(sibling.open(projectRoot, tab->doc.cfg().voicegroupArg, &siblingError) &&
                              sibling.setVoice(dsSlot, unrelated) && sibling.save(&siblingError),
                          "could not make an unrelated current-source edit") &&
                    reopenCleanSameVoicegroup()) {
                    const QByteArray externallyRefreshedBytes = readFileBytes(vgPath);
                    check(tab->vgSource->voiceAt(replacementBlankSlot) &&
                              tab->vgSource->voiceAt(dsSlot) &&
                              tab->vgSource->voiceAt(dsSlot)->release == unrelated.release &&
                              tab->vgSource->sourceBytes() == externallyRefreshedBytes,
                          "reopened source did not contain the unrelated edit");
                    tab->doc.undoStack()->undo();
                    check(tab->vgSource->kindAt(replacementBlankSlot) == VgLineKind::None &&
                              tab->vgSource->voiceAt(dsSlot) &&
                              tab->vgSource->voiceAt(dsSlot)->release == unrelated.release &&
                              tab->vgSource->dirty() &&
                              tab->vgSource->sourceBytes() != vgBytesOriginal &&
                              tab->vgSource->sourceBytes() != externallyRefreshedBytes &&
                              readFileBytes(vgPath) == externallyRefreshedBytes,
                          "blank-slot undo after reopen restored stale whole-file bytes");
                    tab->doc.undoStack()->redo();
                    check(tab->vgSource->voiceAt(replacementBlankSlot) &&
                              *tab->vgSource->voiceAt(replacementBlankSlot) == materialized &&
                              tab->vgSource->voiceAt(dsSlot) &&
                              tab->vgSource->voiceAt(dsSlot)->release == unrelated.release &&
                              !tab->vgSource->dirty() &&
                              tab->vgSource->sourceBytes() == externallyRefreshedBytes &&
                              readFileBytes(vgPath) == externallyRefreshedBytes,
                          "blank-slot redo after reopen did not preserve the unrelated edit");

                    // Return the scratch fixture to its starting source.
                    tab->doc.undoStack()->undo();
                    onVoiceEditRequested(dsSlot, original, false);
                    check(saveSession(*tab),
                          "could not restore the replacement-lifetime fixture") &&
                        check(readFileBytes(vgPath) == vgBytesOriginal,
                              "replacement-lifetime fixture did not restore original bytes");
                }
            }
        }
    }

    // 6. The dock's editor widgets feed the same pipeline: spinning the
    // Release box must push an undo command, and undoing it must refresh
    // the box back to the original value.
    {
        m_workspace->selectVoicegroupSlot(dsSlot);
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
            check(tab->doc.isDirty() && tab->vgSource->dirty() &&
                      tab->vgSource->voiceAt(dsSlot)->release == uiValue,
                  "editing the Release spin box did not push an undo command");
            tab->doc.undoStack()->undo();
            check(!tab->doc.isDirty() && !tab->vgSource->dirty() &&
                      voicegroupDriver.releaseSpinBox() &&
                      voicegroupDriver.releaseSpinBox()->value() == original.release,
                  "undo did not refresh the Release spin box");
            if (releaseSpin && releaseEdit) {
                releaseSpin->setValue(100);
                dragVertically(releaseEdit, 12, Qt::NoModifier);
                check(releaseSpin->value() == 106 && tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->release == 106,
                      "dragging the Release input up did not increase its value");
                tab->doc.undoStack()->undo();
                check(!tab->doc.isDirty() && !tab->vgSource->dirty() &&
                          voicegroupDriver.releaseSpinBox() &&
                          voicegroupDriver.releaseSpinBox()->value() == original.release,
                      "undo did not restore the upward ADSR drag");

                releaseSpin->setValue(100);
                dragVertically(releaseEdit, -12, Qt::NoModifier);
                check(releaseSpin->value() == 94 && tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->release == 94,
                      "dragging the Release input down did not decrease its value");
                tab->doc.undoStack()->undo();
                check(!tab->doc.isDirty() && !tab->vgSource->dirty() &&
                          voicegroupDriver.releaseSpinBox() &&
                          voicegroupDriver.releaseSpinBox()->value() == original.release,
                      "undo did not restore the downward ADSR drag");

                releaseSpin->setValue(100);
                releaseEdit->clearFocus();
                dragVertically(releaseEdit, 20, Qt::ShiftModifier);
                check(releaseSpin->value() == 104 && tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->release == 104,
                      "Shift-dragging the Release input did not use the precision rate");
                tab->doc.undoStack()->undo();
                check(!tab->doc.isDirty() && !tab->vgSource->dirty() &&
                          voicegroupDriver.releaseSpinBox() &&
                          voicegroupDriver.releaseSpinBox()->value() == original.release,
                      "undo did not restore the precise ADSR drag");
            }
        }
    }

    // 6a. A source-undefined row stays visibly blank, but selecting its
    // DirectSound template and choosing another type creates an undoable
    // structural voice at that exact slot.
    {
        int blankSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE && blankSlot < 0; i++) {
            if (tab->vgSource->kindAt(i) == VgLineKind::None)
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
            m_workspace->selectVoicegroupSlot(blankSlot);
            check(voicegroupDriver.editorNoticeText().isEmpty() &&
                      voicegroupDriver.editorNoticeIsHidden(),
                  "empty slot editor still shows its instructional caption");
            check(voicegroupDriver.sampleActionButtonsHaveMatchingFixedSize(),
                  "sample action buttons do not have matching fixed dimensions");
            if (check(voicegroupDriver.visibleVoiceTypeData() >= 0,
                      "empty slot did not show the type template")) {
                check(voicegroupDriver.visibleVoiceTypeData() == int(VgMacro::DirectSound),
                      "empty slot template is not DirectSound");
                check(voicegroupDriver.activateVoiceType(VgMacro::Square1),
                      "empty slot type template could not activate Square 1");
                const VgVoice *created = tab->vgSource->voiceAt(blankSlot);
                check(created && created->macro == VgMacro::Square1 && tab->doc.isDirty() &&
                          tab->vgSource->dirty() &&
                          m_audio.voicegroup()->voices[blankSlot].type == VOICE_SQUARE_1,
                      "type choice did not create and reload the blank slot");
                tab->doc.undoStack()->undo();
                const QStringList restoredBlankRow = voicegroupDriver.slotRowText(blankSlot);
                check(tab->vgSource->kindAt(blankSlot) == VgLineKind::None && !tab->doc.isDirty() &&
                          !tab->vgSource->dirty() && restoredBlankRow.size() == 3 &&
                          restoredBlankRow.at(0) == QStringLiteral("%1  %2")
                                                        .arg(blankSlot, 3, 10, QLatin1Char('0'))
                                                        .arg(tr("[Blank]")) &&
                          restoredBlankRow.at(1).isEmpty() && restoredBlankRow.at(2).isEmpty(),
                      "undo did not restore the blank slot cleanly");
                tab->doc.undoStack()->redo();
                created = tab->vgSource->voiceAt(blankSlot);
                check(created && created->macro == VgMacro::Square1 &&
                          m_audio.voicegroup()->voices[blankSlot].type == VOICE_SQUARE_1,
                      "redo did not restore the created slot");
                tab->doc.undoStack()->undo();
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
            const VgVoice *v = tab->vgSource->voiceAt(i);
            if (v && vgMacroIsCgb(v->macro))
                cgbSlot = i;
        }
        if (cgbSlot >= 0) {
            // The window must be shown for the measurement: hidden widgets
            // are empty layout items and contribute no minimum.
            show();
            QCoreApplication::processEvents();
            m_workspace->selectVoicegroupSlot(cgbSlot);
            QCoreApplication::processEvents();
            const int cgbMin = voicegroupDriver.browserMinimumSizeHint().width();
            m_workspace->selectVoicegroupSlot(dsSlot);
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
        invalidateVgCatalog();
        updateVoicegroupBrowser(); // hand the browser the new catalog
        const VgSynthCatalog setupCatalog = VoicegroupSource::synthInstruments(projectRoot);
        const int defsAfterSetup = setupCatalog.defs.size();
        const QByteArray synthBytesSetup = readFileBytes(synthPath);
        const int indexBeforeSynth = tab->doc.undoStack()->index();

        // A sample voice that is NOT already a synth (a synth-heavy
        // voicegroup's first DirectSound voice may be one, and switching it
        // to Synth would rightly be a no-op).
        int synthSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE && synthSlot < 0; i++) {
            const VgVoice *v = tab->vgSource->voiceAt(i);
            if (v &&
                (v->macro == VgMacro::DirectSound || v->macro == VgMacro::DirectSoundNoResample ||
                 v->macro == VgMacro::DirectSoundAlt) &&
                !setupCatalog.find(v->symbol))
                synthSlot = i;
        }
        if (synthSlot < 0) {
            std::printf("vgsavecheck: note: every sample voice is already a "
                        "synth, synth section skipped\n");
            std::printf("vgsavecheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
            return failures == 0;
        }
        const VgVoice synthOriginal = *tab->vgSource->voiceAt(synthSlot);

        m_workspace->selectVoicegroupSlot(synthSlot);
        if (check(voicegroupDriver.hasSynthEditorControls(), "synth editor widgets not found") &&
            check(voicegroupDriver.activateSynthType(), "synth type control did not activate")) {
            check(tab->vgSource->voiceAt(synthSlot)->symbol != synthOriginal.symbol,
                  "switching the voice to Synth did not take");
            // Dial a known pulse through several commits (each one mints).
            check(voicegroupDriver.activateSynthWave(0),
                  "synth pulse waveform control did not activate");
            check(voicegroupDriver.setSynthParameterValues(0x21, 0x43, 0x65, 0x87),
                  "synth parameter fields disappeared");
            const QString wantSymbol = vgSynthSymbolName(VgSynthDesc{0, 0x21, 0x43, 0x65, 0x87});
            check(tab->vgSource->voiceAt(synthSlot)->symbol == wantSymbol,
                  "param edits did not land on the param-named symbol");
            check(readFileBytes(synthPath) == synthBytesSetup,
                  "a param edit wrote to the synth data file before save");
            const bool listed = voicegroupDriver.visibleSymbolComboContains(wantSymbol);
            check(!listed, "an unsaved definition appeared in the dropdown");
            const ToneData &td = m_audio.voicegroup()->voices[synthSlot];
            check(td.wav && td.wav->size == 0 && uint8_t(td.wav->data[1]) == 0 &&
                      uint8_t(td.wav->data[2]) == 0x21 && uint8_t(td.wav->data[5]) == 0x87,
                  "param edits were not patched into the loaded tone");
            // The scalar path renames the voice too (param-named symbols):
            // voiceNames feeds track labels and the browser tree.
            check(QString::fromUtf8(m_audio.voicegroup()->voiceNames[synthSlot]) == wantSymbol,
                  "param edits did not sync the loaded voice name");

            // Save: exactly one definition (the referenced one) is written,
            // it now shows up in the dropdown, and the synth data file is
            // wired into the build (sound_data.s .include).
            check(saveSession(*tab), "synth save failed");
            check(readFileBytes(synthPath).contains(wantSymbol.toUtf8() + "::"),
                  "save did not write the referenced synth definition");
            bool wired = false;
            for (const QString &dir : {projectRoot + QStringLiteral("/data"), projectRoot}) {
                QDirIterator wiredIt(dir, {QStringLiteral("*.s")}, QDir::Files);
                while (wiredIt.hasNext() && !wired)
                    wired = readFileBytes(wiredIt.next()).contains("direct_sound_synth_data.inc");
            }
            check(wired, "save did not wire the synth data file into the build");
            check(VoicegroupSource::synthInstruments(projectRoot).defs.size() == defsAfterSetup + 1,
                  "save wrote more than the one referenced definition");
            check(voicegroupDriver.visibleSymbolComboContains(wantSymbol),
                  "the saved definition did not appear in the dropdown");

            // Waveform flips: to Saw the edit dedupes onto the setup's
            // on-disk definition; back to Pulse it must adopt the 50%-square
            // default, not commit the saw's zeroed (silent, duty-0) params.
            const int indexBeforeFlips = tab->doc.undoStack()->index();
            check(voicegroupDriver.activateSynthWave(1),
                  "synth saw waveform control did not activate");
            const QString sawSymbol = tab->vgSource->voiceAt(synthSlot)->symbol;
            // find() points into the catalog: it must outlive the pointer.
            const VgSynthCatalog sawCatalog = VoicegroupSource::synthInstruments(projectRoot);
            const VgSynthDesc *sawDef = sawCatalog.find(sawSymbol);
            check(sawDef && sawDef->waveform == 1,
                  "waveform flip to saw did not dedupe onto an on-disk saw");
            check(voicegroupDriver.activateSynthWave(0),
                  "synth pulse waveform control did not reactivate");
            // Deduped onto an on-disk 50% pulse when the project has one,
            // minted under the param name otherwise — never the duty-0 name.
            const QString pulseSymbol = tab->vgSource->voiceAt(synthSlot)->symbol;
            const VgSynthCatalog pulseCatalog = VoicegroupSource::synthInstruments(projectRoot);
            const VgSynthDesc *pulseDef = pulseCatalog.find(pulseSymbol);
            check((pulseDef && *pulseDef == VgSynthDesc{}) ||
                      pulseSymbol == vgSynthSymbolName(VgSynthDesc{}),
                  "waveform flip back to pulse did not adopt the 50% default");
            while (tab->doc.undoStack()->index() > indexBeforeFlips)
                tab->doc.undoStack()->undo();
            check(tab->vgSource->voiceAt(synthSlot)->symbol == wantSymbol,
                  "undoing the waveform flips did not restore the voice");

            // Back to the original voice; the .inc round-trips, and no
            // further definitions are written.
            const QByteArray synthBytesSaved = readFileBytes(synthPath);
            while (tab->doc.undoStack()->index() > indexBeforeSynth)
                tab->doc.undoStack()->undo();
            check(saveSession(*tab), "post-undo save failed");
            check(readFileBytes(vgPath) == vgBytesOriginal,
                  "undone synth edits did not round-trip the .inc");
            check(readFileBytes(synthPath) == synthBytesSaved,
                  "the post-undo save wrote synth definitions");
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
            check(m_workspace->currentVoicegroupSlot() == prog,
                  "reveal did not select the track's program");

            if (unused >= 0) {
                // Explicit-program path (the event list's context menu).
                view.revealVoice(unused);
                check(m_workspace->currentVoicegroupSlot() == unused,
                      "revealVoice did not select the requested slot");

                // A new voice change gains the mark; undoing it clears it.
                tab->doc.addLanePoint(track, DOC_CC_VOICE, 480, unused);
                check(voicegroupDriver.slotIsMarkedUsed(unused),
                      "a new voice change did not gain the used mark");
                tab->doc.undoStack()->undo();
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
        const QString argBefore = tab->doc.cfg().voicegroupArg;
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
                    check(tab->doc.cfg().voicegroupArg == otherArg,
                          "the mid-press -G edit did not commit");
                    if (!row.isNull()) {
                        checks::events::sendMouse(*row, QEvent::MouseButtonRelease, QPointF(pos),
                                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                    }
                }
                QCoreApplication::processEvents(); // deferred row deletion
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
                tab->doc.undoStack()->undo(); // the mid-press -G switch
                check(tab->doc.cfg().voicegroupArg == argBefore && tab->vgSource &&
                          tab->vgSource->loadName() == vgLoadName,
                      "undo did not restore the mid-press -G switch");
            }
        }
    }

    // 10. The sample picker (the Sample field for DirectSound voices):
    // replaces the giant combo, filters by typed text, auditions the
    // highlighted sample, marks looped samples, commits an undoable symbol
    // change, and still accepts an unlisted typed symbol.
    {
        m_workspace->revealVoicegroupSlot(dsSlot);
        QCoreApplication::processEvents();
        if (check(voicegroupDriver.hasSamplePickerEditor(), "no sample picker in the editor")) {
            check(voicegroupDriver.samplePickerReplacesSymbolCombo(),
                  "sample voice does not show the picker instead of the combo");
            const VgVoice before = *tab->vgSource->voiceAt(dsSlot);
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
                // data drives at least one loop badge (vanilla projects have
                // plenty of looped instruments).
                check(voicegroupDriver.samplePickerSymbolRowCount() >= 2,
                      "picker lists fewer than two symbols");
                check(voicegroupDriver.samplePickerBadgedRowCount() > 0,
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
                // row again commits the undoable voice edit.
                const QString target =
                    voicegroupDriver.firstAlternatePlainPickerSymbol(before.symbol);
                if (check(!target.isEmpty(), "no alternate sample to pick")) {
                    search->setText(target);
                    check(auditioned.contains(target),
                          "filtering onto a sample did not audition it");
                    if (check(voicegroupDriver.currentPickerRowSymbol() == target,
                              "filter did not select the target sample")) {
                        voicegroupDriver.clickCurrentPickerRow();
                        check(voicegroupDriver.samplePickerPopupIsVisible() &&
                                  tab->vgSource->voiceAt(dsSlot) &&
                                  tab->vgSource->voiceAt(dsSlot)->symbol == before.symbol,
                              "first sample click committed instead of selecting");
                        voicegroupDriver.clickCurrentPickerRow();
                    }
                    check(!voicegroupDriver.samplePickerPopupIsVisible(),
                          "second sample click did not close the popup");
                    check(stops > 0, "closing the popup did not stop audition");
                    check(tab->vgSource->voiceAt(dsSlot) &&
                              tab->vgSource->voiceAt(dsSlot)->symbol == target,
                          "the picked symbol did not commit");
                    check(tab->doc.isDirty(), "the picked symbol did not push an undo command");
                    tab->doc.undoStack()->undo();
                    check(tab->vgSource->voiceAt(dsSlot) &&
                              tab->vgSource->voiceAt(dsSlot)->symbol == before.symbol,
                          "undo did not restore the picked symbol");
                    check(voicegroupDriver.samplePickerCurrentSymbol() == before.symbol,
                          "undo did not refresh the picker's label");
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
                check(tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->symbol == unlisted,
                      "an unlisted typed symbol did not commit");
                tab->doc.undoStack()->undo();
                check(tab->vgSource->voiceAt(dsSlot) &&
                          tab->vgSource->voiceAt(dsSlot)->symbol == before.symbol,
                      "undo did not restore the unlisted symbol");

                // Wave voices share the picker: switching the Type swaps the
                // list to the project's programmable waves, and highlighting
                // one auditions it as a CGB wave.
                if (vgCatalog().progWave.isEmpty()) {
                    std::printf("vgsavecheck: note: no programmable waves, "
                                "wave picker section skipped\n");
                } else {
                    int undos = 0;
                    if (check(voicegroupDriver.activateVoiceType(VgMacro::ProgWave),
                              "no Type combo")) {
                        undos++;
                        const VgVoice *waveVoice = tab->vgSource->voiceAt(dsSlot);
                        check(waveVoice && waveVoice->macro == VgMacro::ProgWave,
                              "type switch to Prog Wave did not take");
                        check(voicegroupDriver.samplePickerIsVisible() &&
                                  voicegroupDriver.samplePickerCurrentSymbol() == waveVoice->symbol,
                              "wave voice does not show the picker");

                        voicegroupDriver.openSamplePickerPopup();
                        const QString otherWave =
                            voicegroupDriver.firstAlternatePickerSymbol(waveVoice->symbol);
                        const QStringList pickerSymbols = voicegroupDriver.pickerSymbols();
                        check(std::all_of(pickerSymbols.cbegin(), pickerSymbols.cend(),
                                          [this](const QString &symbol) {
                                              return vgCatalog().progWave.contains(symbol);
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
                            check(tab->vgSource->voiceAt(dsSlot) &&
                                      tab->vgSource->voiceAt(dsSlot)->symbol == otherWave,
                                  "the picked wave did not commit");
                        }
                        while (undos-- > 0)
                            tab->doc.undoStack()->undo();
                        const VgVoice *restored = tab->vgSource->voiceAt(dsSlot);
                        check(restored && restored->macro == before.macro &&
                                  restored->symbol == before.symbol,
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
        const QString argBefore = tab->doc.cfg().voicegroupArg;
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
        newVoicegroup();
        check(QFile::exists(projectRoot + QStringLiteral("/sound/voicegroups/") + newName +
                            QStringLiteral(".inc")),
              "New… did not create the voicegroup file");
        check(tab->doc.cfg().voicegroupArg == QStringLiteral("_") + newName && tab->doc.isDirty(),
              "New… did not auto-assign the voicegroup as an undoable edit");
        check(tab->vgSource && tab->vgSource->filePath().endsWith(newName + QStringLiteral(".inc")),
              "New… auto-assign did not swap the voicegroup source");
        tab->doc.undoStack()->undo();
        check(tab->doc.cfg().voicegroupArg == argBefore && tab->vgSource &&
                  tab->vgSource->loadName() == vgLoadName,
              "undoing the New… auto-assign did not restore the voicegroup");
    }

    std::printf("vgsavecheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

int runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                   const QString &screenshotPath)
{
    MainWindow window;
    return window.runVgSaveCheck(projectRoot, songLabel, screenshotPath) ? 0 : 1;
}
