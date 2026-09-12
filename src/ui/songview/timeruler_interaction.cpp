// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/grid.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QApplication>

#include <algorithm>
#include <cstdint>
#include <utility>

namespace songview {
using namespace songview::detail;

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
    const Tick clickTick = m_grid.snapTick(m_camera.tickAtContentX(input.position.x()));

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
    Tick sigTick;
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
            const Tick tick = dragTick();
            EditorSelectionModel::TimeSelection selection;
            selection.startTick = std::min(m_selAnchor, tick);
            selection.endTick = std::max(m_selAnchor, tick);
            TrackMask trackMask = 1u << m_owner.selectionModel().primaryTrack();
            if (m_multiTrackSweep) {
                for (const ViewNote &note : m_owner.model().notes) {
                    if (note.startTick >= selection.endTick)
                        break;
                    if (note.track >= 0 && note.track < 16 &&
                        selection.startTick < note.endTick()) {
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
        const Tick tick = dragTick();
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
    Tick sigTick;
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
            showRulerMenu(m_selAnchor,
                          window->mapFromGlobal(m_inputHost->mapToGlobal(input.position)));
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
    Tick sigTick;
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
    cancelInteraction();
}

void TimeRuler::showRulerMenu(Tick clickTick, const QPointF &scenePos)
{
    SongDocument *doc = m_owner.document();
    const MidiTimeline *timeline = m_owner.timeline();
    QuickPopupSession *const session = quickSessionFor(m_owner);
    if (!doc || !timeline || !session)
        return;

    // Chip hit snapshotted at open from the press position: it decides the
    // Edit/Remove time-signature rows and the prompt's initial values.
    Tick sigTick = clickTick;
    int sigNum, sigDen;
    bool sigImplicit = true;
    const bool onChip = hitTimeSigChip(m_rightPressPos, &sigTick, &sigNum, &sigDen, &sigImplicit);
    if (!onChip)
        sigAtTick(clickTick, &sigNum, &sigDen);

    // Same rows, order, labels, and enablement as the former native menu;
    // ids carry the RulerMenuAction values the handler consumes.
    std::vector<QuickMenuItem> rows;
    rows.reserve(12);
    const auto addRow = [&rows](RulerMenuAction action, QString text, bool enabled = true) {
        QuickMenuItem item;
        item.id = static_cast<int>(action);
        item.text = std::move(text);
        item.enabled = enabled;
        rows.push_back(std::move(item));
    };
    addRow(RulerMenuAction::SetLoopStart, SongView::tr("Set loop start here"));
    addRow(RulerMenuAction::SetLoopEnd, SongView::tr("Set loop end here"));
    addRow(RulerMenuAction::RemoveLoop, SongView::tr("Remove loop markers"),
           timeline->loopStartTick != CoreTimeDefaults::kNoTick ||
               timeline->loopEndTick != CoreTimeDefaults::kNoTick);
    const EditorSelectionModel::TimeSelection selection = m_owner.selectionModel().timeSelection();
    if (selection.active()) {
        rows.push_back(QuickMenuItem::makeSeparator());
        addRow(RulerMenuAction::LoopFromSelection, SongView::tr("Set loop to selection"));
        addRow(RulerMenuAction::InsertBlank, SongView::tr("Insert blank time"));
        addRow(RulerMenuAction::Duplicate, SongView::tr("Duplicate time"));
        rows.back().shortcutText = contextShortcutText(QStringLiteral("roll.duplicate_time"));
        addRow(RulerMenuAction::RemoveContents, SongView::tr("Remove contents (shift left)"));
        addRow(RulerMenuAction::ClearSelection, SongView::tr("Clear time selection"));
    }
    rows.push_back(QuickMenuItem::makeSeparator());
    addRow(RulerMenuAction::EditTimeSig, onChip ? SongView::tr("Edit time signature…")
                                                : SongView::tr("Set time signature here…"));
    addRow(RulerMenuAction::RemoveTimeSig, SongView::tr("Remove time signature"),
           onChip && !sigImplicit);

    ensureMenuAdapters();
    m_menuHost->setPopupSession(session);
    m_rulerMenuModel->setItems(std::move(rows));

    // Snapshot the guarded open-time target first, but publish it only
    // after open()'s implicit cancellation of a displaced session has
    // completed: no callback can observe a half-published target, and an
    // open failure publishes nothing. The snapshot travels through the
    // session close until activation consumes it; cancellation clears it.
    PendingRulerMenu target;
    target.document = doc;
    target.documentRevision = doc->revision();
    target.clickTick = clickTick;
    target.sigTick = sigTick;
    target.sigNumerator = sigNum;
    target.sigDenominatorPow2 = sigDen;
    target.selection = selection;
    target.trackScope = m_owner.selectionModel().storedTrackScope();

    m_menuHost->open(m_rulerMenuModel, scenePos);
    if (!m_menuHost->isOpen())
        return;
    m_pendingRulerMenu = std::move(target);
}

// Selection-scoped rows may only act on the selection the user saw when the
// menu opened; a live selection that drifted or went inactive turns every
// range command into a stale action.
bool TimeRuler::menuSelectionStale(const PendingRulerMenu &target) const
{
    const EditorSelectionModel::TimeSelection &current = m_owner.selectionModel().timeSelection();
    return !current.active() || current.startTick != target.selection.startTick ||
           current.endTick != target.selection.endTick || current.scope != target.selection.scope ||
           current.tempo != target.selection.tempo || current.lanes != target.selection.lanes ||
           (current.scope == EditorSelectionModel::TimeSelection::Tracks &&
            m_owner.selectionModel().storedTrackScope() != target.trackScope);
}

void TimeRuler::handleRulerMenuAction(int id)
{
    if (!m_pendingRulerMenu)
        return;
    // Consume before any command: the dispatch may open the time-signature
    // form as a new session, and a target must never fire twice.
    const PendingRulerMenu target = std::move(*m_pendingRulerMenu);
    m_pendingRulerMenu.reset();
    SongDocument *const doc = m_owner.document();
    if (!doc || doc != target.document || doc->revision() != target.documentRevision)
        return;
    switch (static_cast<RulerMenuAction>(id)) {
    case RulerMenuAction::SetLoopStart:
        doc->setLoopTick(false, int64_t(target.clickTick));
        break;
    case RulerMenuAction::SetLoopEnd:
        doc->setLoopTick(true, int64_t(target.clickTick));
        break;
    case RulerMenuAction::RemoveLoop:
        // Two commands; undo restores them one at a time.
        if (m_owner.timeline()->loopStartTick != CoreTimeDefaults::kNoTick)
            doc->setLoopTick(false, -1);
        if (m_owner.timeline()->loopEndTick != CoreTimeDefaults::kNoTick)
            doc->setLoopTick(true, -1);
        break;
    case RulerMenuAction::LoopFromSelection:
        if (menuSelectionStale(target))
            return;
        // Same two-command shape as "Remove loop markers".
        doc->setLoopTick(false, int64_t(target.selection.startTick));
        doc->setLoopTick(true, int64_t(target.selection.endTick));
        break;
    case RulerMenuAction::InsertBlank:
        if (menuSelectionStale(target))
            return;
        m_owner.insertBlankTime();
        break;
    case RulerMenuAction::Duplicate:
        if (menuSelectionStale(target))
            return;
        m_owner.duplicateTimeSelection();
        break;
    case RulerMenuAction::RemoveContents:
        if (menuSelectionStale(target))
            return;
        m_owner.removeTimeSelectionContents();
        break;
    case RulerMenuAction::ClearSelection:
        if (menuSelectionStale(target))
            return;
        m_owner.selectionModel().clearTimeSelection();
        break;
    case RulerMenuAction::EditTimeSig:
        // The host closed the menu session before emitting activated(), so
        // the already-landed prompt bridge opens into a settled canvas and
        // owns focus until the user dismisses it.
        openTimeSigPrompt(target.sigTick, target.sigNumerator, target.sigDenominatorPow2);
        break;
    case RulerMenuAction::RemoveTimeSig:
        doc->deleteTimeSig(target.sigTick);
        break;
    default:
        return; // Unknown id: no command ran, nothing to focus.
    }
    // Terminal focus return, after the command so announce and camera
    // follow observe the focused surface — skipped when the dispatch itself
    // opened a new shared popup session (the time-signature form owns focus
    // until the user dismisses it).
    if (QuickPopupSession *const session = quickSessionFor(m_owner); session && session->isOpen())
        return;
    restoreRulerFocus();
}

} // namespace songview
