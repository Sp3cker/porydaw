// ---------------------------------------------------------------- PianoRoll active gestures

#include "ui/songview/pianoroll.h"

#include "core/mid2agbtables.h"
#include "porydaw_scale.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace songview {

void PianoRoll::updateMoveDrag(const TimelinePointerInput &input)
{
    const double tick = m_sv->tickAtContentX(input.position.x() - m_geometry.pianoKeyboardWidth);
    const int64_t grid = int64_t(m_sv->snapTicksAt(uint64_t(std::max(0.0, m_pressTick))));
    const int64_t snappedD = int64_t(std::llround((tick - m_pressTick) / double(grid))) * grid;
    const int dKey = m_sv->scaleFold() ? foldDegreeDeltaForPointer(input.position.y())
                                       : yToKey(input.position.y()) - m_pressKey;
    if (snappedD != m_dTick || dKey != m_dKey) {
        m_dTick = snappedD;
        if (dKey != m_dKey) {
            m_dKey = dKey;
            auditionMovedSelection();
        }
        requestQuickUpdate(cNoteMutationDirty);
    }
}

void PianoRoll::auditionMovedSelection()
{
    const std::vector<DocNote> notes = resolveSelection();
    if (!notes.empty()) {
        const int key = m_sv->scaleFold()
                            ? porydaw_scale::nextScalePitch(m_sv->scaleId(), m_sv->scaleRoot(),
                                                            notes.front().key, m_dKey)
                            : std::clamp(int(notes.front().key) + m_dKey, 0, 127);
        if (key >= 0) {
            auditionKey(key, notes.front().velocity);
            m_auditioned = true;
        }
    }
}

void PianoRoll::updateResizeDrag(const TimelinePointerInput &input)
{
    const double tick = m_sv->tickAtContentX(input.position.x() - m_geometry.pianoKeyboardWidth);
    const double desired = double(m_gripTick) + (tick - m_pressTick);
    const uint64_t snapped =
        m_leftDrag == LeftDrag::Resize
            ? std::max(m_sv->snapTick(desired), m_sv->snapTickUp(double(m_gripOpposite) + 1.0))
            : std::min(m_sv->snapTick(desired), m_sv->snapTickDown(double(m_gripOpposite) - 1.0));
    const int64_t delta =
        std::abs(desired - double(m_gripTick)) < std::abs(desired - double(snapped))
            ? 0
            : int64_t(snapped) - int64_t(m_gripTick);
    int64_t &target = m_leftDrag == LeftDrag::Resize ? m_dDur : m_dTick;
    if (delta != target) {
        target = delta;
        requestQuickUpdate(cNoteMutationDirty);
    }
}

void PianoRoll::updateVelocityDrag(const TimelinePointerInput &input)
{
    const int dv = m_pressPos.toPoint().y() - input.position.toPoint().y(); // up = louder
    if (dv != m_dVel) {
        m_dVel = dv;
        const int vel = std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127);
        ViewNote preview = m_velAnchor;
        preview.velocity = uint8_t(vel);
        m_sv->announceNote(preview);
        const int eff = mid2agbEffectiveVelocity(vel);
        if (eff != m_velAudEff) { // audition only on effective-velocity step
            m_velAudEff = eff;
            auditionKey(m_velAnchor.key, vel);
            m_auditioned = true;
        }
        requestQuickUpdate(cVelocityMutationDirty);
        m_sv->updateVelocityGestureByDelta(m_dVel);
    }
}

void PianoRoll::updateDrawDrag(const TimelinePointerInput &input)
{
    const double tick = m_sv->tickAtContentX(input.position.x() - m_geometry.pianoKeyboardWidth);
    const uint64_t grid = m_sv->snapTicksAt(uint64_t(std::max(0.0, m_pressTick)));
    uint64_t start;
    int64_t dur;
    drawSpanAt(tick, grid, start, dur);
    const int key = yToKey(input.position.y());
    const bool isScaleKey = isDrawableKey(key);
    if (start != m_drawTick || dur != m_drawDur || (isScaleKey && key != m_drawKey)) {
        m_drawTick = start;
        m_drawDur = dur;
        if (isScaleKey && key != m_drawKey) {
            m_drawKey = key;
            auditionKey(m_drawKey, m_lastVelocity);
            m_auditioned = true;
        }
        requestQuickUpdate(PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::Overlay |
                           PianoRollQuickDirty::NoteText);
    }
}

bool PianoRoll::isDrawableKey(int key) const
{
    return !m_sv->scaleFold() ||
           (key >= 0 && porydaw_scale::isScalePitch(m_sv->scaleId(), m_sv->scaleRoot(), key));
}

void PianoRoll::drawSpanAt(double tick, uint64_t grid, uint64_t &start, int64_t &dur) const
{
    const uint64_t anchor = m_drawAnchor;
    start = anchor;
    if (tick >= double(anchor)) {
        const uint64_t end = std::max(anchor + grid, m_sv->snapTickUp(tick));
        dur = int64_t(end - anchor);
    } else {
        start = m_sv->snapTickDown(tick);
        dur = int64_t(anchor + grid - start);
    }
}

void PianoRoll::updateTimeSelDrag(const TimelinePointerInput &input)
{
    const double tick = m_sv->tickAtContentX(input.position.x() - m_geometry.pianoKeyboardWidth);
    const uint64_t t = m_sv->snapTick(tick);
    EditorSelectionModel::TimeSelection sel;
    sel.startTick = std::min(m_rightAnchorTick, t);
    sel.endTick = std::max(m_rightAnchorTick, t);
    m_sv->selectionModel().setTimeSelection(sel);
}

void PianoRoll::updateBandDrag()
{
    auditionBandEntrants(QRectF(m_pressPos, m_curPos).normalized());
    requestQuickUpdate(PianoRollQuickDirty::Overlay | PianoRollQuickDirty::NoteBordersAndSelection);
}

void PianoRoll::completeProjectionGesture()
{
    m_sv->setProjectionLocked(false);
    m_sv->flushProjectionIfDirty();
}

void PianoRoll::abortLiveLeftDrag()
{
    if (m_leftDrag == LeftDrag::Velocity) {
        cancelVelocityInteraction();
    } else if (isLiveDrag(m_leftDrag)) {
        m_leftDrag = LeftDrag::None;
    }
}

void PianoRoll::releaseRightPress(const TimelinePointerInput &input)
{
    SongDocument *doc = m_sv->document();
    const RightDrag drag = m_rightDrag; // snapshot first
    m_rightDrag = RightDrag::None;
    abortLiveLeftDrag(); // rule 3: aborts live left, no commit
    if (drag == RightDrag::TimeSel) {
        if (m_sv->selectionModel().timeSelection().active())
            m_sv->announceTimeSelection();
        else
            m_sv->selectionModel().clearTimeSelection();
    } else if (drag == RightDrag::Band) {
        stopBandAuditions();
        selectBand(QRectF(m_pressPos, m_curPos).normalized(),
                   input.modifiers & Qt::ControlModifier);
    } else {
        releasePendingMenu(input, doc);
    }
    requestQuickUpdate(PianoRollQuickDirty::NoteBordersAndSelection | PianoRollQuickDirty::Overlay);
    completeProjectionGesture(); // NO stopNoteAudition on this path
}

void PianoRoll::releasePendingMenu(const TimelinePointerInput &input, SongDocument *doc)
{
    if (doc && m_rightHit) {
        const auto &selection = m_sv->selectionModel().noteSelection();
        if (std::find(selection.begin(), selection.end(), m_rightHitId) == selection.end())
            m_sv->selectionModel().setNoteSelection({m_rightHitId});
        showNoteMenu(input.position);
    } else if (insideTimeSelection(input.position.x())) {
        m_sv->showTimeSelectionMenu(input.globalPosition.toPoint());
    } else {
        m_sv->selectionModel().clearNoteSelection();
        m_sv->selectionModel().clearTimeSelection();
    }
}

void PianoRoll::releasePendingDrawClick(const TimelinePointerInput &input)
{
    if (insideTimeSelection(input.position.x()))
        m_sv->selectionModel().clearTimeSelection();
    m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
    requestQuickUpdate(PianoRollQuickDirty::NoteBordersAndSelection | PianoRollQuickDirty::Overlay);
    completeProjectionGesture();
    stopNoteAudition(); // unique tail order: invalidate -> complete -> stop
}

void PianoRoll::releasePendingVelocityClick()
{
    const NoteId id = m_velAnchor.noteId;
    if (m_velModMods & Qt::ControlModifier) {
        const auto &storedSelection = m_sv->selectionModel().noteSelection();
        std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
        if (std::erase(ids, id) == 0)
            ids.push_back(id);
        m_sv->selectionModel().setNoteSelection(std::move(ids));
    } else if (noteRequiresSelectionUpdate(m_velAnchor)) {
        m_sv->selectionModel().setNoteSelection({id});
    }
    requestQuickUpdate(PianoRollQuickDirty::NoteBordersAndSelection);
    completeProjectionGesture();
    stopNoteAudition();
}

void PianoRoll::commitDrawDrag()
{
    SongDocument *doc = m_sv->document();
    if (!doc)
        return;
    const int selectedTrack = m_sv->selectionModel().primaryTrack();
    const std::vector<DocNote> before = doc->notesForTrack(selectedTrack);
    const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
    doc->addNote(selectedTrack, m_drawTick, uint8_t(m_drawKey), uint32_t(m_drawDur),
                 m_lastVelocity);
    m_sv->selectionModel().setNoteSelection(doc->insertedNoteIds(selectedTrack, before));
}

void PianoRoll::commitMoveDrag()
{
    SongDocument *doc = m_sv->document();
    if (!doc || (m_dTick == 0 && m_dKey == 0))
        return;
    std::vector<DocNote> notes = resolveSelection();
    if (notes.empty())
        m_sv->selectionModel().clearNoteSelection();
    else
        commitResolvedMove(*doc, notes);
}

void PianoRoll::commitResolvedMove(SongDocument &doc, std::vector<DocNote> &notes)
{
    if (m_sv->scaleFold() && m_dKey != 0) {
        std::vector<uint8_t> destinations;
        if (!m_sv->resolveFoldDestinations(notes, m_dKey, destinations))
            return;
        const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
        const bool moved = doc.moveNotesToPitches(notes, destinations, m_dTick);
        if (!moved)
            return;
    } else {
        const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
        doc.moveNotes(notes, m_dTick, m_dKey);
    }
    std::vector<NoteId> ids;
    ids.reserve(notes.size());
    for (const DocNote &note : notes)
        ids.push_back(note.noteId);
    m_sv->selectionModel().setNoteSelection(std::move(ids));
}

void PianoRoll::commitResizeDrag(LeftDrag drag, SongDocument *doc)
{
    if (doc && drag == LeftDrag::Resize && m_dDur != 0) {
        const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
        doc->resizeNotes(resolveSelection(), m_dDur);
    } else if (doc && drag == LeftDrag::ResizeLeft && m_dTick != 0) {
        const std::vector<DocNote> notes = resolveSelection();
        const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
        doc->resizeNotesLeft(notes, m_dTick);
    }
}

void PianoRoll::commitVelocityDrag(SongView::VelocityCommitResult result)
{
    const bool velocityCommitted = result == SongView::VelocityCommitResult::Committed ||
                                   result == SongView::VelocityCommitResult::Unchanged;
    if (m_dVel != 0 && velocityCommitted)
        m_lastVelocity = uint8_t(std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127));
}

void PianoRoll::commitDrag()
{
    const LeftDrag drag = m_leftDrag; // snapshot kind first
    clearLiveDragToken();             // before any commit; kills either channel
    SongView::VelocityCommitResult velocityResult = SongView::VelocityCommitResult::NoGesture;
    if (drag == LeftDrag::Velocity)
        velocityResult = m_sv->commitVelocityGesture();
    SongDocument *doc = m_sv->document();
    if (drag == LeftDrag::Draw) {
        commitDrawDrag();
    } else if (drag == LeftDrag::Move) {
        commitMoveDrag();
    } else if (drag == LeftDrag::Resize || drag == LeftDrag::ResizeLeft) {
        commitResizeDrag(drag, doc);
    } else if (drag == LeftDrag::Velocity) {
        commitVelocityDrag(velocityResult);
    }
    stopNoteAudition(); // shared tail verbatim
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    // The committed drag kind selects exactly the domains the commit touched;
    // camera and projection helpers queue their own requests, which coalesce.
    PianoRollQuickDirtySet dirty = PianoRollQuickDirty::None;
    if (drag == LeftDrag::Draw) // committed note replaces the draw preview
        dirty = cDrawCommitDirty;
    else if (drag == LeftDrag::Move || drag == LeftDrag::Resize || drag == LeftDrag::ResizeLeft)
        dirty = cNoteMutationDirty;
    else if (drag == LeftDrag::Velocity)
        dirty = cVelocityMutationDirty;
    else // no commit: a fall-through release killed a live right-drag token
        dirty = PianoRollQuickDirty::Overlay | PianoRollQuickDirty::NoteBordersAndSelection;
    requestQuickUpdate(dirty);
    completeProjectionGesture();
}

} // namespace songview
