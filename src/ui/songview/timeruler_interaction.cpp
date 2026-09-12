// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/grid.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QApplication>

#include <algorithm>
#include <cstdint>
#include <utility>

namespace songview {

namespace {

QQuickWindow *quickWindowFor(SongView &owner)
{
    const TimelineQuickView *const quick = owner.quickView();
    return quick ? quick->quickWindow() : nullptr;
}

QuickPopupSession *quickSessionFor(SongView &owner)
{
    const TimelineQuickView *const quick = owner.quickView();
    return quick ? quick->popupSession() : nullptr;
}

} // namespace

bool TimeRuler::pointerPress(const TimelinePointerInput &input)
{
    SongDocument *doc = m_owner.document();
    const MidiTimeline *timeline = m_owner.timeline();
    if (!timeline || input.surface != TimelineInputSurface::Plot)
        return false;
    if (input.button == Qt::RightButton) {
        // Deferred until release so the context menu opens at the release
        // point. The press captures the raw unsnapped coordinate and the
        // exact chip identity — never the left-drag snapped anchor — and
        // showRulerMenu consumes it through the two terminal
        // target-establishment paths.
        if (!doc)
            return false;
        m_rightPress = true;
        m_rightPressTick = m_camera.tickAtContentX(input.position.x());
        int sigNum, sigDen;
        bool sigImplicit;
        m_rightPressChip = m_inputHost && hitTimeSigChip(input.position, &m_rightPressChipTick,
                                                         &sigNum, &sigDen, &sigImplicit);
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    const uint64_t clickTick = m_grid.snapTick(m_camera.tickAtContentX(input.position.x()));
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
        if (QQuickWindow *const window = quickWindowFor(m_owner))
            showRulerMenu(window->mapFromGlobal(m_inputHost->mapToGlobal(input.position)));
        else
            clearRightPressTarget();
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
    // End the double-click's implicit grab before publishing the form. The
    // resulting PointerUngrabbed cancellation synchronously clears the old
    // ruler gesture and popup state; publishing first would cancel this form.
    m_dragTimeSig = false;
    if (TimelineInputHost *const host = input.host ? input.host : m_inputHost)
        host->releasePointerGrab();
    openTimeSigPrompt(sigTick, numerator, denomPow2);
    requestQuickUpdate();
    return true;
}

void TimeRuler::editTimeSignatureAtCursor()
{
    if (!m_owner.document())
        return;
    const uint64_t tick = m_owner.editCursorTick();
    int numerator, denomPow2;
    sigAtTick(tick, &numerator, &denomPow2);
    openTimeSigPrompt(tick, numerator, denomPow2);
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

void TimeRuler::inputCancelled(TimelineInputCancelReason reason)
{
    // Gesture state is always cancelled below. The popup teardown is the
    // only conditional part: opening this ruler's shared menu hands window
    // focus to the menu panel (FocusLost on the band item), and the
    // release's mouse ungrab lands right after the open (PointerUngrabbed).
    // Exactly those two self-inflicted cancellations must not tear the
    // menu back down while this ruler's menu host owns the open session —
    // every other reason (Hidden, WindowDeactivated), and any session
    // owned by a foreign popup, keeps the full teardown.
    QuickPopupSession *const session = quickSessionFor(m_owner);
    const bool menuOwnsSession =
        m_menuHost && session && session->isOpen() && session->owns(m_menuHost);
    const bool menuTookTheInput =
        menuOwnsSession && (reason == TimelineInputCancelReason::FocusLost ||
                            reason == TimelineInputCancelReason::PointerUngrabbed);
    if (!menuTookTheInput)
        closePopups();
    clearRightPressTarget();
    cancelInteraction();
}

void TimeRuler::clearRightPressTarget()
{
    m_rightPressTick = 0.0;
    m_rightPressChip = false;
    m_rightPressChipTick = 0;
}

void TimeRuler::showRulerMenu(const QPointF &scenePos)
{
    // Consume the right-press target before anything else: no clicked
    // target survives the menu open, whether it succeeds or not.
    const double rawTick = m_rightPressTick;
    const bool onChip = m_rightPressChip;
    const uint64_t chipTick = m_rightPressChipTick;
    clearRightPressTarget();

    SongDocument *doc = m_owner.document();
    const MidiTimeline *timeline = m_owner.timeline();
    QuickPopupSession *const session = quickSessionFor(m_owner);
    const EditActions *const actions = m_owner.editActions();
    if (!doc || !timeline || !session || !actions)
        return;

    // Target establishment (spec.md#target-establishment): the selection
    // path takes the exact chip tick or the raw background coordinate and
    // finishes without snapping, committing a cursor, or seeking. Only the
    // cursor path — reached when the press lies outside the active
    // half-open interval or no interval exists — clears the selection and
    // commits the exact chip tick or grid-snapped background tick, which
    // seeks through the existing editCursorMoved handoff.
    const EditorSelectionModel::TimeSelection selection = m_owner.selectionModel().timeSelection();
    const double insideTick = onChip ? double(chipTick) : rawTick;
    const bool inside = selection.active() && insideTick >= double(selection.startTick) &&
                        insideTick < double(selection.endTick);
    if (!inside) {
        m_owner.selectionModel().clearTimeSelection();
        m_owner.commitEditCursor(onChip ? chipTick : m_grid.snapTick(rawTick));
    }

    // Both compositions project the canonical actions directly; the ruler
    // owns its own row sets and never consumes buildTimeSelectionItems.
    // The inside menu carries selection operations and the nonpositional
    // Remove Loop Markers — no positional or signature rows.
    const auto actionRow = [actions](SongView::EditCommand command, RulerMenuAction id) {
        QAction *const action = actions->action(command);
        Q_ASSERT(action);
        if (!action)
            return QuickMenuItem::makeSeparator();
        return QuickMenuItem::fromAction(*action, int(id));
    };
    std::vector<QuickMenuItem> rows;
    if (inside) {
        rows.reserve(7);
        rows.push_back(actionRow(SongView::EditCommand::LoopFromSelection,
                                 RulerMenuAction::LoopFromSelection));
        rows.push_back(actionRow(SongView::EditCommand::InsertTime, RulerMenuAction::InsertBlank));
        rows.push_back(actionRow(SongView::EditCommand::DuplicateTime, RulerMenuAction::Duplicate));
        rows.push_back(
            actionRow(SongView::EditCommand::DeleteTime, RulerMenuAction::RemoveContents));
        rows.push_back(
            actionRow(SongView::EditCommand::ClearTimeSelection, RulerMenuAction::ClearSelection));
        rows.push_back(QuickMenuItem::makeSeparator());
        rows.push_back(actionRow(SongView::EditCommand::RemoveLoop, RulerMenuAction::RemoveLoop));
    } else {
        rows.reserve(9);
        rows.push_back(actionRow(SongView::EditCommand::InsertTime, RulerMenuAction::InsertBlank));
        rows.push_back(actionRow(SongView::EditCommand::Paste, RulerMenuAction::Paste));
        rows.push_back(QuickMenuItem::makeSeparator());
        rows.push_back(
            actionRow(SongView::EditCommand::SetLoopStart, RulerMenuAction::SetLoopStart));
        rows.push_back(actionRow(SongView::EditCommand::SetLoopEnd, RulerMenuAction::SetLoopEnd));
        rows.push_back(actionRow(SongView::EditCommand::RemoveLoop, RulerMenuAction::RemoveLoop));
        rows.push_back(QuickMenuItem::makeSeparator());
        rows.push_back(
            actionRow(SongView::EditCommand::EditTimeSignature, RulerMenuAction::EditTimeSig));
        rows.push_back(
            actionRow(SongView::EditCommand::RemoveTimeSignature, RulerMenuAction::RemoveTimeSig));
    }

    ensureMenuAdapters();
    m_menuHost->setPopupSession(session);
    m_rulerMenuModel->setItems(std::move(rows));
    m_menuHost->open(m_rulerMenuModel, scenePos);
}

} // namespace songview
