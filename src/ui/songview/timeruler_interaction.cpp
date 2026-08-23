// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"

#include <QApplication>
#include <QMenu>
#include <QMouseEvent>

#include <algorithm>
#include <cstdint>
#include <utility>

namespace songview {
using namespace songview::detail;

void TimeRuler::mousePressEvent(QMouseEvent *event)
{
    SongDocument *doc = m_sv->document();
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl || event->position().x() < m_geometry.plotOrigin)
        return;
    const uint64_t clickTick =
        m_sv->snapTick(m_sv->tickAtContentX(event->position().x() - m_geometry.plotOrigin));

    if (event->button() == Qt::RightButton) {
        // Deferred until release so the loop/selection menu opens at the
        // original click tick.
        if (!doc)
            return;
        m_rightPress = true;
        m_rightPressPos = event->position();
        m_selAnchor = clickTick;
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    m_dragMarker = doc ? hitMarker(event->position()) : -1;
    if (m_dragMarker >= 0) {
        m_dragTick = clickTick;
        update();
        return;
    }
    uint64_t sigTick;
    int sigNum, sigDen;
    bool sigImplicit;
    if (doc && hitTimeSigChip(event->position(), &sigTick, &sigNum, &sigDen, &sigImplicit) &&
        !sigImplicit) {
        // Drag moves the signature; starting at its own tick keeps a
        // plain click (and the first half of a double-click) a no-op.
        m_dragTimeSig = true;
        m_dragTimeSigFrom = sigTick;
        m_dragTick = sigTick;
        update();
        return;
    }
    m_dragSelEdge = doc ? hitSelEdge(event->position()) : -1;
    if (m_dragSelEdge >= 0)
        return;
    // Elsewhere on the ruler: defer until movement distinguishes a click
    // (place the edit cursor) from a drag (sweep a time selection).
    m_leftPress = true;
    m_multiTrackSweep = event->modifiers() & Qt::ControlModifier;
    m_leftPressPos = event->position();
    m_selAnchor = clickTick;
}

void TimeRuler::mouseMoveEvent(QMouseEvent *event)
{
    const auto dragTick = [this, event] {
        return m_sv->snapTick(m_sv->tickAtContentX(
            std::max(qreal(m_geometry.plotOrigin), event->position().x()) - m_geometry.plotOrigin));
    };
    if (m_rightPress)
        return;
    if (m_leftPress) {
        if (!m_selSweep &&
            (event->position().toPoint() - m_leftPressPos.toPoint()).manhattanLength() >=
                QApplication::startDragDistance())
            m_selSweep = true;
        if (m_selSweep) {
            const uint64_t tick = dragTick();
            EditorSelectionModel::TimeSelection sel;
            sel.startTick = std::min(m_selAnchor, tick);
            sel.endTick = std::max(m_selAnchor, tick);
            TrackMask trackMask = 1u << m_sv->selectionModel().primaryTrack();
            if (m_multiTrackSweep) {
                for (const ViewNote &note : m_sv->model().notes) {
                    if (note.startTick >= sel.endTick)
                        break;
                    if (note.track >= 0 && note.track < 16 && sel.startTick < note.endTick)
                        trackMask |= 1u << note.track;
                }
            }
            m_sv->selectionModel().setTimeSelectionAndTrackScope(std::move(sel), trackMask);
        }
        return;
    }
    if (m_dragMarker >= 0 || m_dragTimeSig) {
        m_dragTick = dragTick();
        update();
        return;
    }
    if (m_dragSelEdge >= 0) {
        // Selection edges move live (view state, unlike the loop
        // markers' commit-on-release document edit).
        EditorSelectionModel::TimeSelection sel = m_sv->selectionModel().timeSelection();
        const uint64_t tick = dragTick();
        if (m_dragSelEdge == 0)
            sel.startTick = tick;
        else
            sel.endTick = tick;
        if (sel.startTick > sel.endTick) {
            std::swap(sel.startTick, sel.endTick);
            m_dragSelEdge ^= 1;
        }
        m_sv->selectionModel().setTimeSelection(sel);
        return;
    }
    uint64_t sigTick;
    int sigNum, sigDen;
    bool sigImplicit;
    setCursor(m_sv->document() &&
                      (hitMarker(event->position()) >= 0 || hitSelEdge(event->position()) >= 0 ||
                       hitTimeSigChip(event->position(), &sigTick, &sigNum, &sigDen, &sigImplicit))
                  ? Qt::SplitHCursor
                  : Qt::ArrowCursor);
}

void TimeRuler::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::RightButton && m_rightPress) {
        m_rightPress = false;
        showRulerMenu(m_selAnchor, event->globalPosition().toPoint());
        return;
    }
    if (event->button() == Qt::LeftButton && m_leftPress) {
        m_leftPress = false;
        m_multiTrackSweep = false;
        if (m_selSweep) {
            m_selSweep = false;
            if (m_sv->selectionModel().timeSelection().active())
                m_sv->announceTimeSelection();
            else
                m_sv->selectionModel().clearTimeSelection();
        } else {
            m_sv->setEditCursorTick(m_selAnchor);
            m_sv->commitEditCursor(m_selAnchor);
        }
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    if (m_dragSelEdge >= 0) {
        m_dragSelEdge = -1;
        if (m_sv->selectionModel().timeSelection().active())
            m_sv->announceTimeSelection();
        else
            m_sv->selectionModel().clearTimeSelection(); // edges dragged together
        return;
    }
    if (m_dragTimeSig) {
        m_dragTimeSig = false;
        if (SongDocument *doc = m_sv->document())
            doc->moveTimeSig(m_dragTimeSigFrom, m_dragTick);
        update();
        return;
    }
    if (m_dragMarker < 0)
        return;
    const bool endMarker = m_dragMarker == 1;
    m_dragMarker = -1;
    if (SongDocument *doc = m_sv->document())
        doc->setLoopTick(endMarker, int64_t(m_dragTick));
    update();
}

void TimeRuler::mouseDoubleClickEvent(QMouseEvent *event)
{
    SongDocument *doc = m_sv->document();
    uint64_t sigTick;
    int numerator, denomPow2;
    bool implicit;
    if (event->button() != Qt::LeftButton || !doc ||
        !hitTimeSigChip(event->position(), &sigTick, &numerator, &denomPow2, &implicit))
        return;
    // The first press of the double-click armed a chip drag; cancel it
    // before the modal editor swallows the release.
    m_dragTimeSig = false;
    if (askTimeSignature(this, &numerator, &denomPow2))
        doc->setTimeSig(sigTick, numerator, denomPow2);
    update();
}

void TimeRuler::showRulerMenu(uint64_t clickTick, const QPoint &globalPos)
{
    SongDocument *doc = m_sv->document();
    const MidiTimeline *tl = m_sv->timeline();
    if (!doc || !tl)
        return;
    QMenu menu(this);
    QAction *setStart = menu.addAction(SongView::tr("Set loop start here"));
    QAction *setEnd = menu.addAction(SongView::tr("Set loop end here"));
    QAction *remove = menu.addAction(SongView::tr("Remove loop markers"));
    remove->setEnabled(tl->loopStartTick != UINT64_MAX || tl->loopEndTick != UINT64_MAX);
    QAction *loopFromSel = nullptr;
    QAction *insertBlank = nullptr;
    QAction *duplicate = nullptr;
    QAction *removeContents = nullptr;
    QAction *clearSel = nullptr;
    const EditorSelectionModel::TimeSelection sel = m_sv->selectionModel().timeSelection();
    if (sel.active()) {
        menu.addSeparator();
        loopFromSel = menu.addAction(SongView::tr("Set loop to selection"));
        insertBlank = menu.addAction(SongView::tr("Insert blank time"));
        duplicate = menu.addAction(SongView::tr("Duplicate time"));
        duplicate->setShortcut(
            keymap::Registry::instance().bindings(QStringLiteral("roll.duplicate_time")).value(0));
        removeContents = menu.addAction(SongView::tr("Remove contents (shift left)"));
        clearSel = menu.addAction(SongView::tr("Clear time selection"));
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
    QAction *chosen = menu.exec(globalPos);
    if (chosen == setStart) {
        doc->setLoopTick(false, int64_t(clickTick));
    } else if (chosen == setEnd) {
        doc->setLoopTick(true, int64_t(clickTick));
    } else if (chosen == remove) {
        // Two commands; undo restores them one at a time.
        if (tl->loopStartTick != UINT64_MAX)
            doc->setLoopTick(false, -1);
        if (m_sv->timeline()->loopEndTick != UINT64_MAX)
            doc->setLoopTick(true, -1);
    } else if (chosen && chosen == loopFromSel) {
        // Same two-command shape as "Remove loop markers".
        doc->setLoopTick(false, int64_t(sel.startTick));
        doc->setLoopTick(true, int64_t(sel.endTick));
    } else if (chosen && chosen == insertBlank) {
        m_sv->insertBlankTime();
    } else if (chosen && chosen == duplicate) {
        m_sv->duplicateTimeSelection();
    } else if (chosen && chosen == removeContents) {
        m_sv->removeTimeSelectionContents();
    } else if (chosen && chosen == clearSel) {
        m_sv->selectionModel().clearTimeSelection();
    } else if (chosen == editSig) {
        if (askTimeSignature(this, &sigNum, &sigDen))
            doc->setTimeSig(sigTick, sigNum, sigDen);
    } else if (chosen == removeSig) {
        doc->deleteTimeSig(sigTick);
    }
}

} // namespace songview
