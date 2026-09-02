// ---------------------------------------------------------------- PianoRoll document commands

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QCursor>
#include <QInputDialog>
#include <QMetaObject>
#include <QObject>

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

bool PianoRoll::keyPress(const TimelineKeyInput &input)
{
    if (!input.autoRepeat && keymap::Registry::isModifierKey(input.key))
        requestQuickUpdate(PianoRollQuickDirty::NoteText);
    const auto &keys = keymap::Registry::instance();
    const auto matches = [&keys, &input](const char *id) {
        return keys.matches(input.key, input.modifiers, QLatin1String(id));
    };
    SongDocument *doc = m_sv->document();
    if (doc && matches("roll.paste")) {
        pasteAtEditCursor();
        return true;
    }
    // Shared Copy dispatch runs first so time and note selections use the
    // same command from every editor surface.
    if (m_sv->handleEditKey(input))
        return true;
    if (doc && matches("roll.cut")) {
        const std::vector<DocNote> notes = resolveSelection();
        if (!notes.empty()) {
            copyNotes(notes);
            const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
            doc->deleteNotes(notes);
            m_sv->selectionModel().clearNoteSelection();
        }
        return true;
    }
    if (doc && matches("roll.select_all")) {
        selectAllNotes();
        return true;
    }
    if (doc && matches("roll.delete")) {
        const std::vector<DocNote> notes = resolveSelection();
        if (!notes.empty()) {
            const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
            doc->deleteNotes(notes);
            m_sv->selectionModel().clearNoteSelection();
        }
        return true;
    }
    if (doc && matches("roll.pitch_bend")) {
        if (!input.autoRepeat)
            openPitchBendEditor();
        return true;
    }
    if (doc) {
        const int transpose = m_sv->transposeStepFor(input);
        if (transpose != 0) {
            if (m_sv->scaleFold() && (transpose == 1 || transpose == -1)) {
                m_sv->foldTransposeSelection(transpose);
            } else {
                transposeSelection(transpose);
            }
            return true;
        }
    }
    if (doc && (matches("roll.nudge_left") || matches("roll.nudge_right"))) {
        nudgeSelection(matches("roll.nudge_right"));
        return true;
    }
    if (input.key == Qt::Key_Escape) {
        cancelVelocityInteraction();
        m_leftDrag = LeftDrag::None;
        m_rightDrag = RightDrag::None;
        stopBandAuditions();
        m_sv->selectionModel().clearNoteSelection();
        m_sv->selectionModel().clearTimeSelection();
        requestQuickUpdate(cDrawCommitDirty);
        return true;
    }
    return false;
}

bool PianoRoll::keyRelease(const TimelineKeyInput &input)
{
    if (!input.autoRepeat && keymap::Registry::isModifierKey(input.key)) {
        requestQuickUpdate(PianoRollQuickDirty::NoteText);
    }
    // End the transpose audition when the shortcut's keys come up.
    // Autorepeat releases are skipped so a held transpose key keeps sounding
    // the moving pitch; the idle-state guard keeps a stray key release
    // from cutting a mouse gesture's preview short.
    if (!input.autoRepeat && !dragLive())
        stopNoteAudition();
    return false;
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
        new PitchBendEditor(m_sv, m_sv->document(), notes.front(),
                            [this](QPointF globalPos) { return focusNoteUnderCursor(globalPos); });
    if (!popup->hasEditableSpan()) {
        popup->deleteLater();
        m_sv->announce(SongView::tr("Select one note to edit pitch bend."));
        return;
    }
    const QPointF cursorLocal = m_inputHost->mapFromGlobal(QCursor::pos());
    double noteFraction = -1.0;
    QRect noteGlobal;
    for (const ViewNote &viewNote : m_sv->model().notes) {
        if (viewNote.noteId != notes.front().noteId)
            continue;
        const QRectF noteLocalRect = noteRect(viewNote);
        const QPointF noteTopGlobal = m_inputHost->mapToGlobal(noteLocalRect.topLeft());
        const QPointF noteBottomGlobal = m_inputHost->mapToGlobal(noteLocalRect.bottomRight());
        noteGlobal = QRect(noteTopGlobal.toPoint(), noteBottomGlobal.toPoint());
        if (noteLocalRect.contains(cursorLocal)) {
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
    const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
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
    // Only note pixels changed here; the ensureKeyVisible reveal and any
    // fold-projection rebuild queue their own requests, which coalesce.
    requestQuickUpdate(cNoteMutationDirty);
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
    const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
    doc->moveNotes(notes, dTick, 0, /*mergeable=*/true);
    // Keep the moved notes in sight, scrolling just enough.
    uint64_t lo = UINT64_MAX, hi = 0;
    for (const DocNote &note : notes) {
        const uint64_t tick = uint64_t(int64_t(note.tick) + dTick);
        lo = std::min(lo, tick);
        hi = std::max(hi, tick + note.duration);
    }
    m_sv->ensureRangeVisible(lo, hi, right);
    // Only note pixels changed here; the ensureRangeVisible reveal above
    // queues its own camera request when it actually scrolls.
    requestQuickUpdate(cNoteMutationDirty);
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
    m_noteMenu->showMenuAt(m_inputHost->mapToGlobal(localPos).toPoint(), notes.front().velocity);
}

bool PianoRoll::focusNoteUnderCursor(QPointF globalPos)
{
    const QPointF pos = m_inputHost->mapFromGlobal(globalPos);
    const ViewNote *hit =
        m_sv->document() && pos.x() >= m_geometry.pianoKeyboardWidth ? hitNote(pos) : nullptr;
    if (!hit)
        return false;
    if (hit->track != m_sv->selectionModel().primaryTrack() || !hit->noteId.isAssigned() ||
        !m_sv->selectionModel().isNoteSelected(hit->noteId))
        m_sv->selectionModel().setNoteSelection({hit->noteId});
    m_inputHost->requestFocus(Qt::MouseFocusReason);
    requestQuickUpdate(PianoRollQuickDirty::NoteBordersAndSelection);
    return true;
}

bool PianoRoll::moveNoteMenu(QPointF globalPos)
{
    if (!focusNoteUnderCursor(globalPos))
        return false;
    showNoteMenu(m_inputHost->mapFromGlobal(globalPos));
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
    case NoteMenuChoice::Cut: {
        copyNotes(notes);
        const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
        doc->deleteNotes(notes);
        m_sv->selectionModel().clearNoteSelection();
        break;
    }
    case NoteMenuChoice::Velocity: {
        bool ok = false;
        const int velocity = QInputDialog::getInt(m_sv, SongView::tr("Note velocity"),
                                                  SongView::tr("Velocity (1-127):"),
                                                  notes.front().velocity, 1, 127, 1, &ok);
        if (ok) {
            const SongView::DocumentSwapHintScope swapHint{*m_sv, cVelocityMutationDirty};
            doc->setNotesVelocity(notes, uint8_t(velocity));
            m_lastVelocity = uint8_t(velocity);
        }
        break;
    }
    case NoteMenuChoice::Delete: {
        const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
        doc->deleteNotes(notes);
        m_sv->selectionModel().clearNoteSelection();
        break;
    }
    case NoteMenuChoice::None:
        break;
    }
}

} // namespace songview
