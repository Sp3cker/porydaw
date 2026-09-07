// ---------------------------------------------------------------- PianoRoll document commands

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

#include <QApplication>
#include <QMetaObject>
#include <QObject>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>
#include <utility>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::pianoroll_detail;

bool PianoRoll::keyPress(const TimelineKeyInput &input)
{
    if (!input.autoRepeat && keymap::Registry::isModifierKey(input.key))
        requestQuickUpdate(PianoRollQuickDirty::NoteText);
    // Escape arbitration belongs to the shared command policy. The pitch-bend
    // popup keeps its own local Escape behavior rather than being torn down
    // through the parent band's pointer cancellation path.
    return false;
}

bool PianoRoll::keyRelease(const TimelineKeyInput &input)
{
    if (!input.autoRepeat && keymap::Registry::isModifierKey(input.key)) {
        requestQuickUpdate(PianoRollQuickDirty::NoteText);
    }
    // The transpose audition ends through finishKeyboardAudition() on the
    // shared release path, not here: the chord can come up while another
    // band or the Quick root holds focus.
    return false;
}

bool PianoRoll::finishKeyboardAudition()
{
    // A release consumes only an actual keyboard-command audition; a pointer
    // drag keeps its own preview, and stray releases propagate normally.
    if (dragLive() || !m_auditioned)
        return false;
    stopNoteAudition();
    return true;
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
    double noteFraction = -1.0;
    QRect noteGlobal;
    for (const ViewNote &viewNote : m_sv->model().notes) {
        if (viewNote.noteId != notes.front().noteId)
            continue;
        const QRectF noteLocalRect = noteRect(viewNote);
        const QPointF noteTopGlobal = m_inputHost->mapToGlobal(noteLocalRect.topLeft());
        const QPointF noteBottomGlobal = m_inputHost->mapToGlobal(noteLocalRect.bottomRight());
        noteGlobal = QRect(noteTopGlobal.toPoint(), noteBottomGlobal.toPoint());
        // Fractional opening only when the retained pointer position sits
        // on the selected note; keyboard G without a known inside pointer
        // keeps the -1 fallback.
        if (m_curPosValid && noteLocalRect.contains(m_curPos)) {
            noteFraction =
                double(m_camera.tickAtContentX(m_curPos.x()) - double(notes.front().tick)) /
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
        // The pointer can be stationary when the overlay disappears and Qt
        // will not deliver a fresh hover. Queue the refresh so popup teardown
        // finishes first; QObject cancels it if the roll is destroyed.
        QMetaObject::invokeMethod(
            this,
            [this] {
                if (m_curPosValid && m_inputHost && m_inputHost->bounds().contains(m_curPos))
                    refreshHoverCursor(m_curPos, QApplication::keyboardModifiers());
            },
            Qt::QueuedConnection);
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

void PianoRoll::transposeSelectedNotes(int semitones)
{
    // Fold projection moves by scale degrees; plain transpose by semitones.
    if (m_sv->scaleFold() && (semitones == 1 || semitones == -1))
        m_sv->foldTransposeSelection(semitones);
    else
        transposeSelection(semitones);
}

void PianoRoll::nudgeSelectedNotes(bool right)
{
    SongDocument *doc = m_sv->document();
    const std::vector<DocNote> notes = resolveSelection();
    if (!doc || notes.empty())
        return;
    uint64_t anchor = UINT64_MAX;
    for (const DocNote &note : notes)
        anchor = std::min(anchor, note.tick);
    const uint64_t snapped =
        right ? m_grid.snapTickUp(double(anchor) + 1.0) : m_grid.snapTickDown(double(anchor) - 1.0);
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

void PianoRoll::cutSelectedNotes()
{
    const std::vector<DocNote> notes = resolveSelection();
    SongDocument *doc = m_sv->document();
    if (!doc || notes.empty())
        return;
    copyNotes(notes);
    const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
    doc->deleteNotes(notes);
    m_sv->selectionModel().clearNoteSelection();
}

void PianoRoll::deleteSelectedNotes()
{
    const std::vector<DocNote> notes = resolveSelection();
    SongDocument *doc = m_sv->document();
    if (!doc || notes.empty())
        return;
    const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
    doc->deleteNotes(notes);
    m_sv->selectionModel().clearNoteSelection();
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
                            note.duration ? note.duration : uint32_t(m_grid.gridTicksAt(note.tick)),
                            note.velocity});
    clip.tracks.push_back(std::move(ct));
    writeClipboard(clip, m_sv->timeline()->ticksPerBeat);
    m_sv->announce(SongView::tr("Copied %n note(s)", nullptr, int(notes.size())));
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
    const ViewNote *hit = m_sv->document() ? hitNote(pos) : nullptr;
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
    case NoteMenuChoice::Cut:
        cutSelectedNotes();
        break;
    case NoteMenuChoice::Velocity:
        openVelocityPrompt(notes);
        break;
    case NoteMenuChoice::Delete:
        deleteSelectedNotes();
        break;
    case NoteMenuChoice::None:
        break;
    }
}

int PianoRoll::velocityPromptInitialValue() const noexcept
{
    return m_pendingVelocityPrompt ? m_pendingVelocityPrompt->initialValue
                                   : velocityPromptMinimumValue();
}

QString PianoRoll::velocityPromptTitle() const
{
    return SongView::tr("Note velocity");
}

QString PianoRoll::velocityPromptLabel() const
{
    return SongView::tr("Velocity (1-127):");
}

QVariantMap PianoRoll::velocityPromptAppearance() const
{
    QVariantMap appearance;
    appearance.insert(QStringLiteral("font"), m_sv->font());
    appearance.insert(QStringLiteral("background"), themes::color(themes::Role::window_background));
    appearance.insert(QStringLiteral("outline"), themes::color(themes::Role::palette_outline));
    appearance.insert(QStringLiteral("text"), themes::color(themes::Role::window_text));
    appearance.insert(QStringLiteral("focus"), themes::color(themes::Role::focus_outline));
    appearance.insert(QStringLiteral("buttonBackground"),
                      themes::color(themes::Role::button_background));
    appearance.insert(QStringLiteral("buttonText"), themes::color(themes::Role::button_text));
    appearance.insert(QStringLiteral("pressedBackground"),
                      themes::color(themes::Role::button_pressed_background));
    appearance.insert(QStringLiteral("borderWidth"), lyt::singlePixel());
    appearance.insert(QStringLiteral("radius"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("dialogPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("horizontalPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("verticalPadding"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("buttonPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("spacing"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("dragThreshold"), lyt::fontPxF(1.0));
    return appearance;
}

void PianoRoll::openVelocityPrompt(const std::vector<DocNote> &notes)
{
    SongDocument *const document = m_sv->document();
    songview::TimelineQuickView *const quick = m_sv->quickView();
    songview::QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    if (!document || !session || notes.empty())
        return;

    // Replacement ends the active shared-popup session before this bridge
    // publishes a new guarded target.
    session->cancel(/*restoreFocus=*/false);
    if (m_pendingVelocityPrompt)
        cancelVelocityPromptWithoutFocus();

    PendingVelocityPrompt pending;
    pending.targets.reserve(notes.size());
    for (const DocNote &note : notes)
        pending.targets.push_back(note.noteId);
    pending.document = document;

    pending.documentRevision = document->revision();
    pending.initialValue = notes.front().velocity;
    m_pendingVelocityPrompt = std::move(pending);
    QObject::disconnect(m_velocityPromptCancellation);
    m_velocityPromptCancellation =
        connect(session, &QuickPopupSession::cancelled, this,
                [this](bool restoreFocus) { clearVelocityPrompt(restoreFocus); });
    if (!session->openForm(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/VelocityPrompt.qml")),
                           this)) {
        clearVelocityPrompt(/*restoreFocus=*/true);
    }
}

void PianoRoll::acceptVelocityPrompt(int velocity)
{
    if (velocity < velocityPromptMinimumValue() || velocity > velocityPromptMaximumValue() ||
        !m_pendingVelocityPrompt)
        return;

    const PendingVelocityPrompt pending = std::move(*m_pendingVelocityPrompt);
    m_pendingVelocityPrompt.reset(); // Never expose a pending target while mutating the document.
    QObject::disconnect(m_velocityPromptCancellation);
    m_velocityPromptCancellation = {};
    if (songview::TimelineQuickView *const quick = m_sv->quickView()) {
        if (songview::QuickPopupSession *const session = quick->popupSession();
            session && session->owns(this)) {
            session->close();
        }
    }
    SongDocument *const document = m_sv->document();
    if (document == pending.document && document->revision() == pending.documentRevision) {
        std::vector<DocNote> notes;
        notes.reserve(pending.targets.size());
        for (NoteId id : pending.targets) {
            DocNote note;
            if (!document->findNote(id, &note)) {
                notes.clear();
                break;
            }
            notes.push_back(note);
        }
        if (!notes.empty()) {
            const SongView::DocumentSwapHintScope swapHint{*m_sv, cVelocityMutationDirty};
            document->setNotesVelocity(notes, uint8_t(velocity));
            // Latch the chosen value even when the document operation becomes
            // a no-op so subsequent drawn notes retain the chosen velocity.
            m_lastVelocity = uint8_t(velocity);
        }
    }
    restoreVelocityPromptFocus();
}

void PianoRoll::cancelVelocityPrompt()
{
    if (!m_pendingVelocityPrompt)
        return;
    songview::TimelineQuickView *const quick = m_sv->quickView();
    songview::QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    const bool ownsSession = session && session->owns(this);
    if (ownsSession)
        session->cancel();
    if (m_pendingVelocityPrompt)
        clearVelocityPrompt(ownsSession);
}

void PianoRoll::cancelVelocityPromptWithoutFocus()
{
    songview::TimelineQuickView *const quick = m_sv->quickView();
    songview::QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    const bool ownsSession = m_pendingVelocityPrompt && session && session->owns(this);
    m_pendingVelocityPrompt.reset();
    QObject::disconnect(m_velocityPromptCancellation);
    m_velocityPromptCancellation = {};
    if (ownsSession)
        session->cancel(/*restoreFocus=*/false);
}

void PianoRoll::clearVelocityPrompt(bool restoreFocus)
{
    m_pendingVelocityPrompt.reset();
    QObject::disconnect(m_velocityPromptCancellation);
    m_velocityPromptCancellation = {};
    if (restoreFocus)
        restoreVelocityPromptFocus();
}

void PianoRoll::restoreVelocityPromptFocus()
{
    m_sv->focusTimelineBand(TimelineBand::Roll, Qt::OtherFocusReason);
}

} // namespace songview
