// ---------------------------------------------------------------- PianoRoll document commands

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/detail.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/promptappearance.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QApplication>
#include <QGuiApplication>
#include <QMetaObject>
#include <QObject>
#include <QQuickWindow>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>
#include <utility>
#include <vector>

namespace songview {
using namespace songview::detail;
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
    // Old close-controller rule: any note under an outside press consumes it
    // once (retargeting selection) and commits the popup with focus restore;
    // every other outside press passes through. Scene presses map through
    // global coordinates so the shared hit-test helpers stay unchanged.
    auto *popup =
        new PitchBendEditor(m_sv, m_sv->document(), notes.front(), [this](QPointF scenePos) {
            TimelineQuickView *const quick = m_sv->quickView();
            QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
            if (!window || !m_inputHost)
                return false;
            return focusNoteUnderCursor(window->mapToGlobal(scenePos));
        });
    if (!popup->hasEditableSpan()) {
        popup->deleteLater();
        m_sv->announce(SongView::tr("Select one note to edit pitch bend."));
        return;
    }
    double noteFraction = -1.0;
    QRectF noteScene;
    // Canonical anchor: the Quick window is the viewport (origin 0), so the
    // canonical roll plotRect origin plus the plot-local note rect is the
    // window-scene anchor rect handed to the shared popup session. Never map
    // through the live input item here: G is keyboard-driven and can arrive
    // before the first band publication moves the item to the plot origin,
    // and the anchor then misses by exactly the item origin.
    QQuickWindow *const anchorWindow =
        m_sv->quickView() ? m_sv->quickView()->quickWindow() : nullptr;
    const TimelineBandGeometry rollGeometry =
        m_sv->timelineBandLayout().geometry(TimelineBand::Roll).value_or(TimelineBandGeometry{});
    for (const ViewNote &viewNote : m_sv->model().notes) {
        if (viewNote.noteId != notes.front().noteId)
            continue;
        if (!anchorWindow || rollGeometry.plotRect.isNull())
            break;
        const QRectF noteLocalRect = noteRect(viewNote);
        noteScene = QRect(rollGeometry.plotRect.topLeft() + noteLocalRect.topLeft().toPoint(),
                          rollGeometry.plotRect.topLeft() + noteLocalRect.bottomRight().toPoint());
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
    if (noteScene.isNull()) {
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
    popup->openAt(noteScene, noteFraction);
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
    Tick anchor = CoreTimeDefaults::kNoTick;
    for (const DocNote &note : notes)
        anchor = std::min(anchor, note.tick);
    const Tick snapped =
        right ? m_grid.snapTickUp(double(anchor) + 1.0) : m_grid.snapTickDown(double(anchor) - 1.0);
    const int64_t dTick = int64_t(snapped) - int64_t(anchor);
    if (dTick == 0)
        return;
    const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
    const uint64_t revision = doc->revision();
    doc->moveNotes(notes, dTick, 0, /*mergeable=*/true);
    // A rejected or no-op move leaves the revision untouched; there is no
    // accepted destination to reveal.
    if (doc->revision() == revision)
        return;
    // Keep the moved notes in sight, scrolling just enough.
    Tick lo = CoreTimeDefaults::kNoTick, hi = 0;
    for (const DocNote &note : notes) {
        const Tick tick = CoreTimeDefaults::shiftTickClamped(note.tick, dTick);
        lo = std::min(lo, tick);
        // The mathematical end can pass the display domain; saturate at the
        // checked Tick conversion instead of narrowing into a wrap.
        const uint64_t end = uint64_t(tick) + note.duration;
        hi = std::max(hi, Tick(std::min<uint64_t>(end, CoreTimeDefaults::kMaxTick)));
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
    Tick base = CoreTimeDefaults::kNoTick;
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
    // The menu only opens over a live note selection; every row then
    // re-resolves that selection at activation through its canonical action.
    if (resolveSelection().empty())
        return;
    songview::TimelineQuickView *const quick = m_sv->quickView();
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    if (!window || !m_inputHost)
        return;
    // The canonical rows need the view's bound action set; without it there
    // is nothing to project and no menu opens.
    const songview::EditActions *const actions = m_sv->editActions();
    QAction *const velocityAction =
        actions ? actions->action(SongView::EditCommand::SetVelocity) : nullptr;
    QAction *const copyAction = actions ? actions->action(SongView::EditCommand::Copy) : nullptr;
    QAction *const cutAction = actions ? actions->action(SongView::EditCommand::Cut) : nullptr;
    QAction *const deleteAction =
        actions ? actions->action(SongView::EditCommand::Delete) : nullptr;
    if (!velocityAction || !copyAction || !cutAction || !deleteAction)
        return;

    // Same four rows as the former native menu, now projected from the
    // canonical command actions: labels, shortcuts and enablement come from
    // the bound QActions, and the host's guarded trigger replaces the old
    // dispatch-time switch. Set Velocity carries its static action label.
    std::vector<QuickMenuItem> rows;
    rows.reserve(5);
    rows.push_back(QuickMenuItem::fromAction(*velocityAction, int(NoteMenuAction::Velocity)));
    rows.push_back(QuickMenuItem::makeSeparator());
    rows.push_back(QuickMenuItem::fromAction(*copyAction, int(NoteMenuAction::Copy)));
    rows.push_back(QuickMenuItem::fromAction(*cutAction, int(NoteMenuAction::Cut)));
    rows.push_back(QuickMenuItem::fromAction(*deleteAction, int(NoteMenuAction::Delete)));
    m_noteMenuModel->setItems(std::move(rows));

    const QPointF scenePos = window->mapFromGlobal(m_inputHost->mapToGlobal(localPos));
    m_noteMenuHost->open(m_noteMenuModel, scenePos);
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

void PianoRoll::moveNoteMenu(QPointF globalPos)
{
    if (focusNoteUnderCursor(globalPos))
        showNoteMenu(m_inputHost->mapFromGlobal(globalPos));
}

void PianoRoll::retargetNoteMenu(QPointF scenePos)
{
    // The host forward already proved the canvas stayed idle. Map the press
    // to global coordinates so the shared hit-test helpers stay unchanged.
    songview::TimelineQuickView *const quick = m_sv->quickView();
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    if (!window || !m_inputHost)
        return;
    moveNoteMenu(window->mapToGlobal(scenePos));
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
    return promptDialogAppearance(QGuiApplication::font());
}

void PianoRoll::openSelectedVelocityPrompt()
{
    // The shared Set Velocity entry resolves the live selection; the guarded
    // snapshot, initial value, bounds, and one-undo acceptance all stay in
    // openVelocityPrompt. No menu snapshot is consulted.
    const std::vector<DocNote> notes = resolveSelection();
    if (notes.empty())
        return;
    openVelocityPrompt(notes);
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
