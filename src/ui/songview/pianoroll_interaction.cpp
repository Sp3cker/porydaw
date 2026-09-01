// ---------------------------------------------------------------- PianoRoll pointer interaction

#include "ui/songview/pianoroll.h"

#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QEvent>
#include <QMouseEvent>

namespace songview {

void PianoRoll::mousePressEvent(QMouseEvent *event)
{
    setFocus();
    if (!m_sv->timeline())
        return;
    m_sv->setProjectionLocked(true);
    if (event->button() == Qt::MiddleButton) {
        beginPanGesture(event);
        return;
    }
    if (event->position().x() < m_geometry.pianoKeyboardWidth) {
        if (event->button() == Qt::LeftButton)
            beginKbdAudition(event);
        return;
    }
    if (event->button() == Qt::RightButton) {
        if (m_sv->document())
            beginPendingMenu(event, hitNote(event->position()));
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    pressContent(event);
}

void PianoRoll::mouseDoubleClickEvent(QMouseEvent *event)
{
    // Double-click on empty space drops a grid-sized note (committed on
    // release; dragging before release still sizes it); on a note it
    // deletes that note. Anywhere else a fast click-click behaves as two
    // presses — Qt replaces the second press with this event.
    SongDocument *doc = m_sv->document();
    if (event->button() == Qt::LeftButton && doc &&
        event->position().x() >= m_geometry.pianoKeyboardWidth) {
        m_sv->setProjectionLocked(true);
        setFocus();
        if (const ViewNote *hit = hitNote(event->position())) {
            DocNote note;
            if (doc->findNote(hit->noteId, &note)) {
                const SongView::DocumentSwapHintScope swapHint{*m_sv, cNoteMutationDirty};
                doc->deleteNotes({note});
                m_sv->selectionModel().clearNoteSelection();
            }
            return;
        }
        beginLeftPress(event);
        beginDraw();
        return;
    }
    mousePressEvent(event);
}

void PianoRoll::mouseMoveEvent(QMouseEvent *event)
{
    updateHoverKey(event);
    if (m_panning) {
        panMove(event);
        return;
    }
    if (m_kbdKey >= 0) {
        kbdGlissandoMove(event);
        return;
    }
    m_curPos = event->position();
    if (!resolvePendingPresses(event))
        return;
    if (!dragLive()) {
        refreshHoverCursor(event->position(), event->modifiers());
        return;
    }
    dispatchLiveDragMove(event);
}

bool PianoRoll::resolvePendingPresses(const QMouseEvent *event)
{
    if (m_rightDrag == RightDrag::PendingMenu)
        resolveRightPress(event);
    if (m_leftDrag == LeftDrag::PendingDraw && !dragLive())
        resolveDrawPress(event);
    if (m_leftDrag == LeftDrag::PendingVelocity && !dragLive())
        return resolveVelocityPress(event);
    return true;
}

void PianoRoll::dispatchLiveDragMove(const QMouseEvent *event)
{
    if (m_rightDrag == RightDrag::Band) {
        updateBandDrag();
        return;
    }
    if (m_rightDrag == RightDrag::TimeSel) {
        updateTimeSelDrag(event);
        return;
    }
    updateLeftDragMove(event);
}

void PianoRoll::updateLeftDragMove(const QMouseEvent *event)
{
    if (m_leftDrag == LeftDrag::Move)
        updateMoveDrag(event);
    else if (m_leftDrag == LeftDrag::Resize || m_leftDrag == LeftDrag::ResizeLeft)
        updateResizeDrag(event);
    else if (m_leftDrag == LeftDrag::Velocity)
        updateVelocityDrag(event);
    else if (m_leftDrag == LeftDrag::Draw)
        updateDrawDrag(event);
}

void PianoRoll::leaveEvent(QEvent *)
{
    setHoverKey(-1);
}

void PianoRoll::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_panning) {
        endPanGesture();
        return;
    }
    if (m_kbdKey >= 0) {
        endKbdAudition();
    }
    if (event->button() == Qt::RightButton && m_rightDrag != RightDrag::None) {
        releaseRightPress(event);
        return;
    }
    if (releasePendingLeftPress(event))
        return;
    if (finishReleaseWithoutCommit(event))
        return;
    commitDrag(event);
}

bool PianoRoll::releasePendingLeftPress(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && m_leftDrag == LeftDrag::PendingDraw) {
        m_leftDrag = LeftDrag::None;
        if (!dragLive()) {
            releasePendingDrawClick(event);
            return true;
        }
        // live right drag: fall through to commitDrag (clears the right token)
    }
    if (event->button() == Qt::LeftButton && m_leftDrag == LeftDrag::PendingVelocity) {
        m_leftDrag = LeftDrag::None;
        releasePendingVelocityClick(event);
        return true; // intentionally no dragLive gate/token clear
    }
    return false;
}

bool PianoRoll::finishReleaseWithoutCommit(const QMouseEvent *event)
{
    // catch-all stays LAST — the only projection guarantee for stray releases
    if (event->button() != Qt::LeftButton || !dragLive()) {
        if (event->button() != Qt::LeftButton && m_leftDrag == LeftDrag::Velocity)
            cancelVelocityInteraction();
        completeProjectionGesture();
        stopNoteAudition();
        return true;
    }
    return false;
}

void PianoRoll::updateHoverKey(const QMouseEvent *event)
{
    setHoverKey(m_leftDrag == LeftDrag::Velocity ? m_velAnchor.key : yToKey(event->position().y()));
}

void PianoRoll::panMove(const QMouseEvent *event)
{
    const QPointF d = event->globalPosition() - m_panPos;
    m_panPos = event->globalPosition();
    m_sv->scrollByPx(-d.x());
    m_sv->scrollRollBy(-d.y());
}

void PianoRoll::kbdGlissandoMove(const QMouseEvent *event)
{
    const int key = yToKey(event->position().y());
    if (key != m_kbdKey) {
        m_kbdKey = key;
        auditionKey(m_kbdKey, 100);
    }
}

void PianoRoll::endPanGesture()
{
    m_panning = false;
    setCursor(Qt::ArrowCursor);
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
} // namespace songview
