// ---------------------------------------------------------------- PianoRoll pointer interaction

#include "ui/songview/pianoroll.h"

#include "ui/songview.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelinequickview.h"

namespace songview {

bool PianoRoll::pointerPress(const TimelinePointerInput &input)
{
    if (!m_sv->timeline())
        return false;
    m_inputHost->requestFocus(Qt::MouseFocusReason);
    m_sv->setProjectionLocked(true);
    if (input.button == Qt::MiddleButton) {
        beginPanGesture(input);
        return true;
    }
    if (input.position.x() < m_geometry.pianoKeyboardWidth) {
        if (input.button != Qt::LeftButton)
            return false;
        beginKbdAudition(input);
        return true;
    }
    if (input.button == Qt::RightButton) {
        if (!m_sv->document())
            return false;
        beginPendingMenu(input, hitNote(input.position));
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    pressContent(input);
    return true;
}

bool PianoRoll::pointerDoubleClick(const TimelinePointerInput &input)
{
    // Double-click on empty space drops a grid-sized note (committed on
    // release; dragging before release still sizes it); on a note it
    // deletes that note. Anywhere else a fast click-click behaves as two
    // presses — Qt replaces the second press with this event.
    SongDocument *doc = m_sv->document();
    if (input.button != Qt::LeftButton || !doc ||
        input.position.x() < m_geometry.pianoKeyboardWidth)
        return pointerPress(input);
    m_sv->setProjectionLocked(true);
    m_inputHost->requestFocus(Qt::MouseFocusReason);
    if (const ViewNote *hit = hitNote(input.position)) {
        DocNote note;
        if (doc->findNote(hit->noteId, &note)) {
            const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
            doc->deleteNotes({note});
            m_sv->selectionModel().clearNoteSelection();
        }
        return true;
    }
    beginLeftPress(input);
    beginDraw();
    return true;
}

bool PianoRoll::pointerMove(const TimelinePointerInput &input)
{
    updateHoverKey(input);
    if (m_panning) {
        panMove(input);
        return true;
    }
    if (m_kbdKey >= 0) {
        kbdGlissandoMove(input);
        return true;
    }
    m_curPos = input.position;
    if (!resolvePendingPresses(input))
        return true;
    if (!dragLive()) {
        refreshHoverCursor(input.position, input.modifiers);
        return true;
    }
    dispatchLiveDragMove(input);
    return true;
}

bool PianoRoll::resolvePendingPresses(const TimelinePointerInput &input)
{
    if (m_rightDrag == RightDrag::PendingMenu)
        resolveRightPress(input);
    if (m_leftDrag == LeftDrag::PendingDraw && !dragLive())
        resolveDrawPress(input);
    if (m_leftDrag == LeftDrag::PendingVelocity && !dragLive())
        return resolveVelocityPress(input);
    return true;
}

void PianoRoll::dispatchLiveDragMove(const TimelinePointerInput &input)
{
    if (m_rightDrag == RightDrag::Band) {
        updateBandDrag();
        return;
    }
    if (m_rightDrag == RightDrag::TimeSel) {
        updateTimeSelDrag(input);
        return;
    }
    updateLeftDragMove(input);
}

void PianoRoll::updateLeftDragMove(const TimelinePointerInput &input)
{
    if (m_leftDrag == LeftDrag::Move)
        updateMoveDrag(input);
    else if (m_leftDrag == LeftDrag::Resize || m_leftDrag == LeftDrag::ResizeLeft)
        updateResizeDrag(input);
    else if (m_leftDrag == LeftDrag::Velocity)
        updateVelocityDrag(input);
    else if (m_leftDrag == LeftDrag::Draw)
        updateDrawDrag(input);
}

void PianoRoll::pointerLeave()
{
    setHoverKey(-1);
}

bool PianoRoll::pointerRelease(const TimelinePointerInput &input)
{
    if (input.button == Qt::MiddleButton && m_panning) {
        endPanGesture();
        return true;
    }
    if (m_kbdKey >= 0) {
        endKbdAudition();
    }
    if (input.button == Qt::RightButton && m_rightDrag != RightDrag::None) {
        releaseRightPress(input);
        return true;
    }
    if (releasePendingLeftPress(input))
        return true;
    if (finishReleaseWithoutCommit(input))
        return true;
    commitDrag();
    return true;
}

bool PianoRoll::releasePendingLeftPress(const TimelinePointerInput &input)
{
    if (input.button == Qt::LeftButton && m_leftDrag == LeftDrag::PendingDraw) {
        m_leftDrag = LeftDrag::None;
        if (!dragLive()) {
            releasePendingDrawClick(input);
            return true;
        }
        // live right drag: fall through to commitDrag (clears the right token)
    }
    if (input.button == Qt::LeftButton && m_leftDrag == LeftDrag::PendingVelocity) {
        m_leftDrag = LeftDrag::None;
        releasePendingVelocityClick();
        return true; // intentionally no dragLive gate/token clear
    }
    return false;
}

bool PianoRoll::finishReleaseWithoutCommit(const TimelinePointerInput &input)
{
    // catch-all stays LAST — the only projection guarantee for stray releases
    if (input.button != Qt::LeftButton || !dragLive()) {
        if (input.button != Qt::LeftButton && m_leftDrag == LeftDrag::Velocity)
            cancelVelocityInteraction();
        completeProjectionGesture();
        stopNoteAudition();
        return true;
    }
    return false;
}

void PianoRoll::updateHoverKey(const TimelinePointerInput &input)
{
    setHoverKey(m_leftDrag == LeftDrag::Velocity ? m_velAnchor.key : yToKey(input.position.y()));
}

void PianoRoll::panMove(const TimelinePointerInput &input)
{
    const QPointF d = input.globalPosition - m_panPos;
    m_panPos = input.globalPosition;
    m_sv->scrollByPx(-d.x());
    m_sv->scrollRollBy(-d.y());
}

void PianoRoll::kbdGlissandoMove(const TimelinePointerInput &input)
{
    const int key = yToKey(input.position.y());
    if (key != m_kbdKey) {
        m_kbdKey = key;
        auditionKey(m_kbdKey, 100);
    }
}

void PianoRoll::endPanGesture()
{
    m_panning = false;
    if (m_inputHost)
        m_inputHost->clearCursor();
    completeProjectionGesture();
}

void PianoRoll::endKbdAudition()
{
    auditionKey(m_kbdKey, 0);
    m_kbdKey = -1;
}

void PianoRoll::stopNoteAudition()
{
    if (!m_auditioned)
        return;
    auditionKey(0, 0);
    m_auditioned = false;
}

void PianoRoll::auditionKey(int key, int velocity)
{
    m_sv->audition(m_sv->selectionModel().primaryTrack(), key, velocity);
    const int sounding = velocity > 0 ? key : -1;
    if (sounding != m_soundingKey) {
        m_soundingKey = sounding;
        requestQuickUpdate(PianoRollQuickDirty::KeyboardHighlights);
    }
}

void PianoRoll::inputCancelled(TimelineInputCancelReason)
{
    // Mirrors the former event() rule for every cancellation cause: only a
    // pending or active velocity drag cancels. Song/tab/project cancellation
    // takes the stronger cancelTransientInput() route instead.
    if (m_leftDrag == LeftDrag::Velocity || m_leftDrag == LeftDrag::PendingVelocity)
        cancelVelocityInteraction();
}
} // namespace songview
