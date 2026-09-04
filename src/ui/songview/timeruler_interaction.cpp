// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/grid.h"

#include <QApplication>
#include <QMenu>

#include <algorithm>
#include <cstdint>
#include <utility>

namespace songview {
using namespace songview::detail;

bool TimeRuler::pointerPress(const TimelinePointerInput &input)
{
    SongDocument *doc = m_owner.document();
    const MidiTimeline *timeline = m_owner.timeline();
    if (!timeline || input.surface != TimelineInputSurface::Plot)
        return false;
    const uint64_t clickTick = m_grid.snapTick(m_camera.tickAtContentX(input.position.x()));

    if (input.button == Qt::RightButton) {
        // Deferred until release so the loop/selection menu opens at the
        // original click tick.
        if (!doc)
            return false;
        m_rightPress = true;
        m_rightPressPos = input.position;
        m_selAnchor = clickTick;
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    m_dragMarker = doc ? hitMarker(input.position) : -1;
    if (m_dragMarker >= 0) {
        m_dragTick = clickTick;
        requestQuickUpdate();
        return true;
    }
    uint64_t sigTick;
    int sigNum, sigDen;
    bool sigImplicit;
    if (doc && hitTimeSigChip(input.position, &sigTick, &sigNum, &sigDen, &sigImplicit) &&
        !sigImplicit) {
        // Drag moves the signature; starting at its own tick keeps a
        // plain click (and the first half of a double-click) a no-op.
        m_dragTimeSig = true;
        m_dragTimeSigFrom = sigTick;
        m_dragTick = sigTick;
        requestQuickUpdate();
        return true;
    }
    m_dragSelEdge = doc ? hitSelEdge(input.position) : -1;
    if (m_dragSelEdge >= 0)
        return true;
    // Elsewhere on the ruler: defer until movement distinguishes a click
    // (place the edit cursor) from a drag (sweep a time selection).
    m_leftPress = true;
    m_multiTrackSweep = input.modifiers & Qt::ControlModifier;
    m_leftPressPos = input.position;
    m_selAnchor = clickTick;
    return true;
}

bool TimeRuler::pointerMove(const TimelinePointerInput &input)
{
    if (input.surface != TimelineInputSurface::Plot)
        return false;
    const auto dragTick = [this, &input] {
        return m_grid.snapTick(m_camera.tickAtContentX(std::max(0.0, input.position.x())));
    };
    if (m_rightPress)
        return true;
    if (m_leftPress) {
        if (!m_selSweep &&
            (input.position.toPoint() - m_leftPressPos.toPoint()).manhattanLength() >=
                QApplication::startDragDistance()) {
            m_selSweep = true;
        }
        if (m_selSweep) {
            const uint64_t tick = dragTick();
            EditorSelectionModel::TimeSelection selection;
            selection.startTick = std::min(m_selAnchor, tick);
            selection.endTick = std::max(m_selAnchor, tick);
            TrackMask trackMask = 1u << m_owner.selectionModel().primaryTrack();
            if (m_multiTrackSweep) {
                for (const ViewNote &note : m_owner.model().notes) {
                    if (note.startTick >= selection.endTick)
                        break;
                    if (note.track >= 0 && note.track < 16 && selection.startTick < note.endTick) {
                        trackMask |= 1u << note.track;
                    }
                }
            }
            m_owner.selectionModel().setTimeSelectionAndTrackScope(std::move(selection), trackMask);
        }
        return true;
    }
    if (m_dragMarker >= 0 || m_dragTimeSig) {
        m_dragTick = dragTick();
        requestQuickUpdate();
        return true;
    }
    if (m_dragSelEdge >= 0) {
        // Selection edges move live (view state, unlike the loop
        // markers' commit-on-release document edit).
        EditorSelectionModel::TimeSelection selection = m_owner.selectionModel().timeSelection();
        const uint64_t tick = dragTick();
        if (m_dragSelEdge == 0)
            selection.startTick = tick;
        else
            selection.endTick = tick;
        if (selection.startTick > selection.endTick) {
            std::swap(selection.startTick, selection.endTick);
            m_dragSelEdge ^= 1;
        }
        m_owner.selectionModel().setTimeSelection(selection);
        return true;
    }
    uint64_t sigTick;
    int sigNum, sigDen;
    bool sigImplicit;
    m_inputHost->setCursor(
        m_owner.document() &&
                (hitMarker(input.position) >= 0 || hitSelEdge(input.position) >= 0 ||
                 hitTimeSigChip(input.position, &sigTick, &sigNum, &sigDen, &sigImplicit))
            ? Qt::SplitHCursor
            : Qt::ArrowCursor);
    return true;
}

bool TimeRuler::pointerRelease(const TimelinePointerInput &input)
{
    if (input.surface != TimelineInputSurface::Plot)
        return false;

    if (input.button == Qt::RightButton && m_rightPress) {
        m_rightPress = false;
        showRulerMenu(m_selAnchor, input.globalPosition.toPoint());
        return true;
    }
    if (input.button == Qt::LeftButton && m_leftPress) {
        m_leftPress = false;
        m_multiTrackSweep = false;
        if (m_selSweep) {
            m_selSweep = false;
            if (m_owner.selectionModel().timeSelection().active())
                m_owner.announceTimeSelection();
            else
                m_owner.selectionModel().clearTimeSelection();
        } else {
            m_owner.setEditCursorTick(m_selAnchor);
            m_owner.commitEditCursor(m_selAnchor);
        }
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    if (m_dragSelEdge >= 0) {
        m_dragSelEdge = -1;
        if (m_owner.selectionModel().timeSelection().active())
            m_owner.announceTimeSelection();
        else
            m_owner.selectionModel().clearTimeSelection(); // edges dragged together
        return true;
    }
    if (m_dragTimeSig) {
        m_dragTimeSig = false;
        if (SongDocument *doc = m_owner.document())
            doc->moveTimeSig(m_dragTimeSigFrom, m_dragTick);
        requestQuickUpdate();
        return true;
    }
    if (m_dragMarker < 0)
        return false;
    const bool endMarker = m_dragMarker == 1;
    m_dragMarker = -1;
    if (SongDocument *doc = m_owner.document())
        doc->setLoopTick(endMarker, int64_t(m_dragTick));
    requestQuickUpdate();
    return true;
}

bool TimeRuler::pointerDoubleClick(const TimelinePointerInput &input)
{
    if (input.surface != TimelineInputSurface::Plot)
        return false;

    SongDocument *doc = m_owner.document();
    uint64_t sigTick;
    int numerator, denomPow2;
    bool implicit;
    if (input.button != Qt::LeftButton || !doc ||
        !hitTimeSigChip(input.position, &sigTick, &numerator, &denomPow2, &implicit)) {
        return false;
    }
    // The first press of the double-click armed a chip drag; cancel it
    // before the modal editor swallows the release.
    m_dragTimeSig = false;
    if (askTimeSignature(&m_owner, &numerator, &denomPow2))
        doc->setTimeSig(sigTick, numerator, denomPow2);
    requestQuickUpdate();
    return true;
}

void TimeRuler::pointerLeave()
{
    if (m_inputHost)
        m_inputHost->clearCursor();
}

bool TimeRuler::wheel(const TimelineWheelInput &input)
{
    if (input.surface != TimelineInputSurface::Plot)
        return false;
    // Same bindings as the roll's notes area: plain wheel zooms the
    // timeline; Shift (or a trackpad's horizontal delta) scrolls it.
    const QPoint delta = input.pixelDelta.isNull() ? input.angleDelta : input.pixelDelta;
    if (input.modifiers & Qt::ShiftModifier) {
        m_owner.scrollByPx(-(delta.y() ? delta.y() : delta.x()));
    } else if (delta.x() && !delta.y()) {
        m_owner.scrollByPx(-delta.x());
    } else {
        m_owner.zoomTimelineAtWheel(input, input.position.x());
    }
    return true;
}

void TimeRuler::inputCancelled(TimelineInputCancelReason)
{
    closePopups();
    cancelInteraction();
}

void TimeRuler::showRulerMenu(uint64_t clickTick, const QPoint &globalPos)
{
    SongDocument *doc = m_owner.document();
    const MidiTimeline *timeline = m_owner.timeline();
    if (!doc || !timeline)
        return;
    QMenu menu(&m_owner);
    QAction *setStart = menu.addAction(SongView::tr("Set loop start here"));
    QAction *setEnd = menu.addAction(SongView::tr("Set loop end here"));
    QAction *remove = menu.addAction(SongView::tr("Remove loop markers"));
    remove->setEnabled(timeline->loopStartTick != UINT64_MAX ||
                       timeline->loopEndTick != UINT64_MAX);
    QAction *loopFromSelection = nullptr;
    QAction *insertBlank = nullptr;
    QAction *duplicate = nullptr;
    QAction *removeContents = nullptr;
    QAction *clearSelection = nullptr;
    const EditorSelectionModel::TimeSelection selection = m_owner.selectionModel().timeSelection();
    if (selection.active()) {
        menu.addSeparator();
        loopFromSelection = menu.addAction(SongView::tr("Set loop to selection"));
        insertBlank = menu.addAction(SongView::tr("Insert blank time"));
        duplicate = menu.addAction(SongView::tr("Duplicate time"));
        duplicate->setShortcut(
            keymap::Registry::instance().bindings(QStringLiteral("roll.duplicate_time")).value(0));
        removeContents = menu.addAction(SongView::tr("Remove contents (shift left)"));
        clearSelection = menu.addAction(SongView::tr("Clear time selection"));
    }
    menu.addSeparator();
    uint64_t sigTick = clickTick;
    int sigNum, sigDen;
    bool sigImplicit = true;
    const bool onChip = hitTimeSigChip(m_rightPressPos, &sigTick, &sigNum, &sigDen, &sigImplicit);
    if (!onChip)
        sigAtTick(clickTick, &sigNum, &sigDen);
    QAction *editSig = menu.addAction(onChip ? SongView::tr("Edit time signature…")
                                             : SongView::tr("Set time signature here…"));
    QAction *removeSig = menu.addAction(SongView::tr("Remove time signature"));
    removeSig->setEnabled(onChip && !sigImplicit);
    m_openMenu = &menu;
    QAction *chosen = menu.exec(globalPos);
    if (m_openMenu.data() == &menu)
        m_openMenu.clear();
    if (chosen == setStart) {
        doc->setLoopTick(false, int64_t(clickTick));
    } else if (chosen == setEnd) {
        doc->setLoopTick(true, int64_t(clickTick));
    } else if (chosen == remove) {
        // Two commands; undo restores them one at a time.
        if (timeline->loopStartTick != UINT64_MAX)
            doc->setLoopTick(false, -1);
        if (m_owner.timeline()->loopEndTick != UINT64_MAX)
            doc->setLoopTick(true, -1);
    } else if (chosen && chosen == loopFromSelection) {
        // Same two-command shape as "Remove loop markers".
        doc->setLoopTick(false, int64_t(selection.startTick));
        doc->setLoopTick(true, int64_t(selection.endTick));
    } else if (chosen && chosen == insertBlank) {
        m_owner.insertBlankTime();
    } else if (chosen && chosen == duplicate) {
        m_owner.duplicateTimeSelection();
    } else if (chosen && chosen == removeContents) {
        m_owner.removeTimeSelectionContents();
    } else if (chosen && chosen == clearSelection) {
        m_owner.selectionModel().clearTimeSelection();
    } else if (chosen == editSig) {
        if (askTimeSignature(&m_owner, &sigNum, &sigDen))
            doc->setTimeSig(sigTick, sigNum, sigDen);
    } else if (chosen == removeSig) {
        doc->deleteTimeSig(sigTick);
    }
}

} // namespace songview
