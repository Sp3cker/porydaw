// ---------------------------------------------------------------- PianoRoll document commands

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/detail.h"

#include <QCursor>
#include <QInputDialog>
#include <QKeyEvent>
#include <QMetaObject>
#include <QObject>
#include <QPointer>

#include <algorithm>
#include <climits>
#include <cmath>
#include <utility>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;
using namespace songview::pianoroll_detail;

void PianoRoll::keyPressEvent(QKeyEvent *event)
{
    if (!event->isAutoRepeat() && keymap::Registry::isModifierKey(event->key()))
        invalidateContent();
    const auto &keys = keymap::Registry::instance();
    SongDocument *doc = m_sv->document();
    if (doc && keys.matches(event, QStringLiteral("roll.paste"))) {
        pasteAtEditCursor();
        event->accept();
        return;
    }
    // Shared Copy dispatch runs first so time and note selections use the
    // same command from every editor surface.
    if (m_sv->handleEditKey(event))
        return;
    if (doc && keys.matches(event, QStringLiteral("roll.cut"))) {
        const std::vector<DocNote> notes = resolveSelection();
        if (!notes.empty()) {
            copyNotes(notes);
            doc->deleteNotes(notes);
            m_sv->selectionModel().clearNoteSelection();
        }
        event->accept();
        return;
    }
    if (doc && keys.matches(event, QStringLiteral("roll.select_all"))) {
        selectAllNotes();
        event->accept();
        return;
    }
    if (doc && keys.matches(event, QStringLiteral("roll.delete"))) {
        const std::vector<DocNote> notes = resolveSelection();
        if (!notes.empty()) {
            doc->deleteNotes(notes);
            m_sv->selectionModel().clearNoteSelection();
        }
        event->accept();
        return;
    }
    if (doc && keys.matches(event, QStringLiteral("roll.pitch_bend"))) {
        if (!event->isAutoRepeat())
            openPitchBendEditor();
        event->accept();
        return;
    }
    if (doc) {
        const int transpose = m_sv->transposeStepFor(event);
        if (transpose != 0) {
            if (m_sv->scaleFold() && (transpose == 1 || transpose == -1)) {
                m_sv->foldTransposeSelection(transpose);
            } else {
                transposeSelection(transpose);
            }
            event->accept();
            return;
        }
    }
    if (doc && (keys.matches(event, QStringLiteral("roll.nudge_left")) ||
                keys.matches(event, QStringLiteral("roll.nudge_right")))) {
        nudgeSelection(keys.matches(event, QStringLiteral("roll.nudge_right")));
        event->accept();
        return;
    }
    if (event->key() == Qt::Key_Escape) {
        cancelVelocityInteraction();
        m_drag = Drag::None;
        m_leftPress = false;
        m_rightPress = false;
        stopBandAuditions();
        m_sv->selectionModel().clearNoteSelection();
        m_sv->selectionModel().clearTimeSelection();
        invalidateContent();
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void PianoRoll::keyReleaseEvent(QKeyEvent *event)
{
    if (!event->isAutoRepeat() && keymap::Registry::isModifierKey(event->key())) {
        m_suppressNextVelocitySelectionAdd = false;
        m_lastModifierVelocityDragNote = {};
        invalidateContent();
    }
    // End the transpose audition when the shortcut's keys come up.
    // Autorepeat releases are skipped so a held Ctrl+Up keeps sounding
    // the moving pitch; the Drag::None guard keeps a stray key release
    // from cutting a mouse gesture's preview short.
    if (!event->isAutoRepeat() && m_drag == Drag::None)
        stopNoteAudition();
    QWidget::keyReleaseEvent(event);
}

void PianoRoll::beginDraw()
{
    if (m_sv->scaleFold() && (m_pressKey < 0 || !m_sv->isScalePitch(m_pressKey))) {
        return;
    }
    m_drawAnchor = m_sv->snapTickDown(m_pressTick);
    m_drawTick = m_drawAnchor;
    m_drawDur = int64_t(m_sv->gridTicksAt(m_drawAnchor));
    m_drawKey = m_pressKey;
    m_drag = Drag::Draw;
    m_sv->selectionModel().clearNoteSelection();
    ViewNote pending{};
    pending.startTick = uint32_t(m_drawTick);
    pending.endTick = uint32_t(m_drawTick + uint64_t(m_drawDur));
    pending.key = uint8_t(m_drawKey);
    pending.velocity = m_lastVelocity;
    pending.track = uint8_t(m_sv->selectionModel().primaryTrack());
    m_sv->announceNote(pending);
    // The empty-space press already sounds this row; don't re-attack it.
    if (m_soundingKey != m_drawKey)
        auditionKey(m_drawKey, m_lastVelocity);
    m_auditioned = true;
    invalidateContent();
}

void PianoRoll::openPitchBendEditor()
{
    const std::vector<DocNote> notes = resolveSelection();
    if (notes.size() != 1) {
        m_sv->announce(SongView::tr("Select one note to edit pitch bend."));
        return;
    }
    if (m_bendPopup) {
        m_bendPopup->cancelAndCloseWithoutFocus();
        m_bendPopup = nullptr;
    }
    auto *popup =
        new PitchBendEditor(m_sv, m_sv->document(), notes.front(), QPointer<QWidget>(this),
                            [this](QPointF globalPos) { return focusNoteUnderCursor(globalPos); });
    if (!popup->hasEditableSpan()) {
        popup->deleteLater();
        m_sv->announce(SongView::tr("Select one note to edit pitch bend."));
        return;
    }
    const QPoint cursorLocal = mapFromGlobal(QCursor::pos());
    double noteFraction = -1.0;
    QRect noteGlobal;
    for (const ViewNote &viewNote : m_sv->model().notes) {
        if (viewNote.noteId != notes.front().noteId)
            continue;
        const QRect noteLocal = noteRect(viewNote).toAlignedRect();
        noteGlobal = QRect(mapToGlobal(noteLocal.topLeft()), mapToGlobal(noteLocal.bottomRight()));
        if (noteLocal.contains(cursorLocal)) {
            noteFraction =
                double(m_sv->tickAtContentX(cursorLocal.x() - m_geometry.pianoKeyboardWidth) -
                       double(notes.front().tick)) /
                double(popup->endTick() - notes.front().tick);
            noteFraction = std::clamp(noteFraction, 0.0, 1.0);
        }
        break;
    }
    if (noteGlobal.isEmpty()) {
        popup->deleteLater();
        m_sv->announce(SongView::tr("Select one note to edit pitch bend."));
        return;
    }
    m_bendPopup = popup;
    connect(popup, &QObject::destroyed, this, [this, popup] {
        if (m_bendPopup == popup)
            m_bendPopup = nullptr;
        // The pointer can be stationary when the overlay disappears.
        // Recompute after the platform has applied any pending cursor warp.
        QMetaObject::invokeMethod(this, [this] { refreshHoverAtCursor(); }, Qt::QueuedConnection);
    });
    popup->openAt(noteGlobal, noteFraction);
}

std::vector<DocNote> PianoRoll::resolveSelection() const
{
    std::vector<DocNote> notes;
    SongDocument *doc = m_sv->document();
    if (!doc)
        return notes;
    for (NoteId id : m_sv->selectionModel().noteSelection()) {
        DocNote note;
        if (doc->findNote(id, &note) && note.engineTrack == m_sv->selectionModel().primaryTrack())
            notes.push_back(note);
    }
    return notes;
}

std::vector<NoteId> PianoRoll::insertedNoteIds(int track, const std::vector<DocNote> &before) const
{
    std::vector<NoteId> ids;
    SongDocument *doc = m_sv->document();
    if (!doc)
        return ids;
    for (const DocNote &candidate : doc->notesForTrack(track)) {
        const bool existed =
            std::any_of(before.begin(), before.end(), [&](const DocNote &previous) {
                return previous.noteId == candidate.noteId;
            });
        if (!existed)
            ids.push_back(candidate.noteId);
    }
    return ids;
}

void PianoRoll::transposeSelection(int dKey)
{
    SongDocument *doc = m_sv->document();
    const std::vector<DocNote> notes = resolveSelection();
    if (!doc || notes.empty())
        return;
    for (const DocNote &note : notes) {
        const int key = int(note.key) + dKey;
        if (key < 0 || key > 127)
            return;
    }
    doc->moveNotes(notes, 0, dKey, /*mergeable=*/true);
    // Keep the moved notes in sight: the row the move headed toward
    // scrolls into view just enough (no re-centering).
    int edge = int(notes.front().key) + dKey;
    for (const DocNote &note : notes) {
        const int key = int(note.key) + dKey;
        edge = dKey > 0 ? std::max(edge, key) : std::min(edge, key);
    }
    m_sv->ensureKeyVisible(edge);
    auditionKey(int(notes.front().key) + dKey, notes.front().velocity);
    m_auditioned = true;
    invalidateContent();
}

void PianoRoll::nudgeSelection(bool right)
{
    SongDocument *doc = m_sv->document();
    const std::vector<DocNote> notes = resolveSelection();
    if (!doc || notes.empty())
        return;
    uint64_t anchor = UINT64_MAX;
    for (const DocNote &note : notes)
        anchor = std::min(anchor, note.tick);
    const uint64_t snapped =
        right ? m_sv->snapTickUp(double(anchor) + 1.0) : m_sv->snapTickDown(double(anchor) - 1.0);
    const int64_t dTick = int64_t(snapped) - int64_t(anchor);
    if (dTick == 0)
        return;
    doc->moveNotes(notes, dTick, 0, /*mergeable=*/true);
    // Keep the moved notes in sight, scrolling just enough.
    uint64_t lo = UINT64_MAX, hi = 0;
    for (const DocNote &note : notes) {
        const uint64_t tick = uint64_t(int64_t(note.tick) + dTick);
        lo = std::min(lo, tick);
        hi = std::max(hi, tick + note.duration);
    }
    m_sv->ensureRangeVisible(lo, hi, right);
    invalidateContent();
}

void PianoRoll::copySelectedNotes()
{
    const std::vector<DocNote> notes = resolveSelection();
    if (!notes.empty())
        copyNotes(notes);
}

void PianoRoll::copyNotes(const std::vector<DocNote> &notes)
{
    uint64_t base = UINT64_MAX;
    for (const DocNote &note : notes)
        base = std::min(base, note.tick);
    Clip clip;
    ClipTrack ct{m_sv->selectionModel().primaryTrack(), {}};
    for (const DocNote &note : notes)
        ct.notes.push_back({uint32_t(note.tick - base), note.key,
                            note.duration ? note.duration : uint32_t(m_sv->gridTicksAt(note.tick)),
                            note.velocity});
    clip.tracks.push_back(std::move(ct));
    writeClipboard(clip, m_sv->timeline()->ticksPerBeat);
    m_sv->announce(SongView::tr("Copied %n note(s)", nullptr, int(notes.size())));
}

void PianoRoll::pasteAtEditCursor()
{
    // Every paste path (roll keys, drawer-canvas keys, the time-selection
    // menu) shares the one entry on SongView, which owns the read, the
    // span-0 vs span>0 dispatch, and the cursors-and-announce tail.
    m_sv->pasteFromClipboard();
}

void PianoRoll::selectAllNotes()
{
    std::vector<NoteId> ids;
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track == m_sv->selectionModel().primaryTrack() && note.noteId.isAssigned())
            ids.push_back(note.noteId);
    }
    m_sv->selectionModel().setNoteSelection(std::move(ids));
}

void PianoRoll::selectBand(const QRectF &band, bool additive)
{
    std::vector<NoteId> ids;
    if (additive) {
        const auto &storedSelection = m_sv->selectionModel().noteSelection();
        ids.assign(storedSelection.begin(), storedSelection.end());
    }
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track != m_sv->selectionModel().primaryTrack() ||
            !noteRect(note).intersects(band) || !note.noteId.isAssigned())
            continue;
        if (std::find(ids.begin(), ids.end(), note.noteId) == ids.end())
            ids.push_back(note.noteId);
    }
    m_sv->selectionModel().setNoteSelection(std::move(ids));
}

void PianoRoll::showNoteMenu(QPointF localPos)
{
    SongDocument *doc = m_sv->document();
    if (!doc)
        return;
    const std::vector<DocNote> notes = resolveSelection();
    if (notes.empty())
        return;
    m_noteMenu->showMenuAt(mapToGlobal(localPos.toPoint()), notes.front().velocity);
}

bool PianoRoll::focusNoteUnderCursor(QPointF globalPos)
{
    const QPointF pos =
        globalPos - QPointF(mapToGlobal(QPoint(lyt::space(Space::Zero), lyt::space(Space::Zero))));
    const ViewNote *hit =
        m_sv->document() && pos.x() >= m_geometry.pianoKeyboardWidth ? hitNote(pos) : nullptr;
    if (!hit)
        return false;
    if (hit->track != m_sv->selectionModel().primaryTrack() || !hit->noteId.isAssigned() ||
        !m_sv->selectionModel().isNoteSelected(hit->noteId))
        m_sv->selectionModel().setNoteSelection({hit->noteId});
    setFocus(Qt::MouseFocusReason);
    invalidateContent();
    return true;
}

bool PianoRoll::moveNoteMenu(QPointF globalPos)
{
    if (!focusNoteUnderCursor(globalPos))
        return false;
    const QPointF pos = globalPos - QPointF(mapToGlobal(QPoint(0, 0)));
    showNoteMenu(pos);
    return true;
}

void PianoRoll::handleNoteMenuChoice(NoteMenuChoice choice)
{
    SongDocument *doc = m_sv->document();
    if (!doc)
        return;
    const std::vector<DocNote> notes = resolveSelection();
    if (notes.empty())
        return;
    switch (choice) {
    case NoteMenuChoice::Copy:
        copyNotes(notes);
        break;
    case NoteMenuChoice::Cut:
        copyNotes(notes);
        doc->deleteNotes(notes);
        m_sv->selectionModel().clearNoteSelection();
        break;
    case NoteMenuChoice::Velocity: {
        bool ok = false;
        const int velocity = QInputDialog::getInt(this, SongView::tr("Note velocity"),
                                                  SongView::tr("Velocity (1-127):"),
                                                  notes.front().velocity, 1, 127, 1, &ok);
        if (ok) {
            doc->setNotesVelocity(notes, uint8_t(velocity));
            m_lastVelocity = uint8_t(velocity);
        }
        break;
    }
    case NoteMenuChoice::Delete:
        doc->deleteNotes(notes);
        m_sv->selectionModel().clearNoteSelection();
        break;
    case NoteMenuChoice::None:
        break;
    }
}

} // namespace songview
