#include "pitchbendgraph.hpp"

#include "songview.h"

#include "ui/keymap.h"
#include "ui/mousehints/mousehints.h"

#include <QCoreApplication>
#include <QCursor>
#include <QFocusEvent>
#include <QGuiApplication>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QWheelEvent>

#include <algorithm>

namespace songview {

PitchBendGraph::PitchBendGraph(QQuickItem *parent) : QQuickItem(parent)
{
    setAcceptedMouseButtons(Qt::NoButton);
    setActiveFocusOnTab(false);
    setCursor(Qt::CrossCursor);
    // Passive hover only: the graph is its own physical hint source and
    // never grabs or focuses for hinting.
    setAcceptHoverEvents(true);
}

void PitchBendGraph::initialize(Initialization initial)
{
    if (m_kernel || !initial.songView)
        return;

    m_engineTrack = initial.engineTrack;
    m_unterminated = initial.unterminated;
    m_bendRange = std::clamp(initial.bendRange, 0, 127);
    m_callbacks = std::move(initial.callbacks);
    m_kernel.emplace(toKernelLane(initial.lane), initial.songView->grid(), initial.geometry,
                     initial.startTick, initial.endTick, std::move(initial.points),
                     initial.endValue);

    setFlag(ItemHasContents, true);
    setAcceptedMouseButtons(Qt::LeftButton);
    setActiveFocusOnTab(true);
    // Native scope recovery recomputes only a currently hovered idle graph;
    // the connection dies with this item and never restores stale targets.
    if (ui::MouseHints *const hints = mouseHints())
        connect(hints, &ui::MouseHints::scopeRefresh, this, [this] { refreshIdleMouseHint(); });
    redraw();
    notifyPresentationChanged();
    notifyLiveValueChanged();
}

void PitchBendGraph::setMetrics(const PitchBendGeometry &geometry)
{
    if (!m_kernel)
        return;
    m_kernel->setMetrics(geometry);
    refreshIdleMouseHint();
    redraw();
    notifyPresentationChanged();
}

void PitchBendGraph::setBendRange(int range)
{
    if (!m_kernel)
        return;
    const int clampedRange = std::clamp(range, 0, 127);
    if (m_bendRange == clampedRange)
        return;
    m_bendRange = clampedRange;
    refreshIdleMouseHint();
    redraw();
    notifyPresentationChanged();
    notifyLiveValueChanged();
}

void PitchBendGraph::setCurve(const std::map<Tick, int> &points, int endValue)
{
    if (!m_kernel)
        return;
    m_kernel->setCurve(points, endValue);
    cancelGesture();
    redraw();
    notifyLiveValueChanged();
}

void PitchBendGraph::resetCurve()
{
    if (!m_kernel)
        return;
    m_kernel->resetCurve();
    cancelGesture();
    notifyPreviewChanged();
    forceActiveFocus(Qt::MouseFocusReason);
    redraw();
    notifyLiveValueChanged();
}

std::optional<Tick> PitchBendGraph::selectedTick() const
{
    return m_kernel ? m_kernel->selectedTick() : std::optional<Tick>{};
}

void PitchBendGraph::setSelectedTick(std::optional<Tick> tick)
{
    if (!m_kernel)
        return;
    if (m_kernel->setSelectedTick(tick))
        redraw();
}

std::optional<std::pair<Tick, int>> PitchBendGraph::hitTest(const QPointF &position) const
{
    if (!m_kernel)
        return std::nullopt;
    return m_kernel->hitTest(position);
}

bool PitchBendGraph::removeSelectedVertex()
{
    if (!m_kernel)
        return false;
    if (!m_kernel->removeSelectedVertex())
        return false;
    redraw();
    notifyPreviewChanged();
    notifyLiveValueChanged();
    notifyCommitRequested();
    return true;
}

QPoint PitchBendGraph::vertexPosition(Tick tick, int value) const
{
    if (!m_kernel)
        return {};
    return m_kernel->vertexPosition(tick, value);
}

void PitchBendGraph::setKeyboardFraction(double fraction)
{
    if (!m_kernel)
        return;
    m_kernel->setKeyboardFraction(fraction);
    redraw();
    notifyLiveValueChanged();
}

void PitchBendGraph::cancelGesture()
{
    if (m_kernel)
        m_kernel->cancelGesture();
    // Every cancel path — Escape, curve replacement, editor undo/dispose —
    // settles the retained profile by the actual cursor position.
    settleMouseHintAtCursor();
}

bool PitchBendGraph::handleKeyPress(QKeyEvent *event)
{
    if (!m_kernel) {
        event->ignore();
        return false;
    }
    if (event->key() == Qt::Key_Escape) {
        cancelGesture();
        notifyCancelRequested();
        event->accept();
        return true;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) && selectedTick()) {
        removeSelectedVertex();
        event->accept();
        return true;
    }
    const auto &keys = keymap::Registry::instance();
    if (keys.matches(event->key(), event->modifiers(), QStringLiteral("transport.play_pause"))) {
        if (!event->isAutoRepeat())
            notifyAuditionRequested();
        event->accept();
        return true;
    }
    if (event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter) {
        notifyCommitRequested();
        event->accept();
        return true;
    }
    event->ignore();
    QQuickItem::keyPressEvent(event);
    return event->isAccepted();
}

QRect PitchBendGraph::canvasRect() const
{
    return m_kernel ? m_kernel->canvasRect() : QRect{};
}

bool PitchBendGraph::hasGesture() const
{
    return m_kernel && m_kernel->hasGesture();
}

int PitchBendGraph::liveValue() const
{
    return m_kernel ? m_kernel->liveValue() : 0;
}

std::vector<SongDocument::LanePointValue> PitchBendGraph::curvePoints() const
{
    if (!m_kernel)
        return {};
    std::vector<SongDocument::LanePointValue> points;
    points.reserve(m_kernel->points().size());
    const uint32_t fineTick = m_kernel->fineGridTicks();
    int previous = 0;
    Tick previousTick = 0;
    bool havePrevious = false;
    for (const auto &[tick, value] : m_kernel->points()) {
        const bool endpoint = tick == m_kernel->startTick() || tick == m_kernel->endTick();
        const bool fineSample =
            havePrevious && tick > previousTick && tick - previousTick == fineTick;
        if (endpoint || !havePrevious || value != previous || fineSample)
            points.push_back({tick, value});
        previous = value;
        previousTick = tick;
        havePrevious = true;
    }
    return points;
}

PitchBendGraph::Lane PitchBendGraph::lane() const
{
    if (m_kernel)
        return fromKernelLane(m_kernel->lane());
    return Lane::PitchBend;
}

QString PitchBendGraph::laneTitle() const
{
    return lane() == Lane::PitchBend ? SongView::tr("Pitch bend (BEND)")
                                     : SongView::tr("Mod wheel (CC1)");
}

QString PitchBendGraph::liveValueText() const
{
    return formatLiveValue();
}

QString PitchBendGraph::upperValueText() const
{
    return formatRangeLimit(true);
}

QString PitchBendGraph::lowerValueText() const
{
    return formatRangeLimit(false);
}

QString PitchBendGraph::endLabel() const
{
    return m_unterminated ? SongView::tr("Song end") : SongView::tr("Note off");
}

bool PitchBendGraph::bipolar() const
{
    return lane() == Lane::PitchBend;
}

void PitchBendGraph::redraw()
{
    if (!m_kernel)
        return;
    rebuildLayer();
    update();
}

void PitchBendGraph::notifyPresentationChanged()
{
    if (m_kernel)
        emit presentationChanged();
}

void PitchBendGraph::notifyLiveValueChanged()
{
    if (m_kernel)
        emit liveValueChanged();
}

void PitchBendGraph::mousePressEvent(QMouseEvent *event)
{
    if (!m_kernel || event->button() != Qt::LeftButton ||
        !canvasRect().contains(event->position().toPoint())) {
        event->ignore();
        return;
    }
    if (const auto hit = hitTest(event->position())) {
        forceActiveFocus(Qt::MouseFocusReason);
        m_kernel->beginVertexDrag(hit->first);
        // The press position's profile becomes the gesture's originating
        // hint, retained until the release/ungrab settle.
        publishMouseHintAt(event->position());
        notifyPreviewChanged();
        redraw();
        notifyLiveValueChanged();
        event->accept();
        return;
    }
    forceActiveFocus(Qt::MouseFocusReason);
    const bool lineGesture = event->modifiers().testFlag(Qt::ShiftModifier) ||
                             event->modifiers().testFlag(Qt::AltModifier);
    m_kernel->beginStroke(event->position(), lineGesture);
    publishMouseHintAt(event->position());
    notifyPreviewChanged();
    redraw();
    notifyLiveValueChanged();
    event->accept();
}

void PitchBendGraph::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_kernel || !m_kernel->hasGesture()) {
        event->ignore();
        return;
    }
    m_kernel->updateGestureAt(event->position(), event->modifiers().testFlag(Qt::AltModifier));
    notifyPreviewChanged();
    redraw();
    notifyLiveValueChanged();
    event->accept();
}

void PitchBendGraph::mouseReleaseEvent(QMouseEvent *event)
{
    if (!m_kernel || event->button() != Qt::LeftButton || !m_kernel->hasGesture()) {
        event->ignore();
        return;
    }
    m_kernel->updateGestureAt(event->position(), event->modifiers().testFlag(Qt::AltModifier));
    finishGesture();
    // The actual release position settles the retained profile: inside the
    // item keeps/refreshes the current target, outside clears it.
    settleMouseHintAt(event->position());
    event->accept();
}

void PitchBendGraph::wheelEvent(QWheelEvent *event)
{
    if (!m_kernel || lane() != Lane::PitchBend ||
        !canvasRect().contains(event->position().toPoint())) {
        event->ignore();
        return;
    }
    const QPoint delta = event->pixelDelta().isNull() ? event->angleDelta() : event->pixelDelta();
    const double units = event->phase() == Qt::ScrollMomentum
                             ? 0.0
                             : double(delta.y()) * (event->pixelDelta().isNull() ? 1.0 : 5.0);
    const int steps = m_kernel->accumulateWheel(units);
    if (steps != 0 && m_callbacks.rangeChangeRequested)
        m_callbacks.rangeChangeRequested(steps);
    event->accept();
}

void PitchBendGraph::keyPressEvent(QKeyEvent *event)
{
    if (!handleKeyPress(event))
        QQuickItem::keyPressEvent(event);
}

void PitchBendGraph::focusInEvent(QFocusEvent *event)
{
    QQuickItem::focusInEvent(event);
    if (m_kernel)
        redraw();
}

void PitchBendGraph::focusOutEvent(QFocusEvent *event)
{
    // Ordinary focus movement between popup controls must not dismiss or
    // cancel anything; it only repaints the focus frame.
    QQuickItem::focusOutEvent(event);
    if (m_kernel)
        redraw();
}

void PitchBendGraph::mouseUngrabEvent()
{
    if (!m_kernel || !m_kernel->hasGesture())
        return; // Normal release already settled the gesture; never double-fire.
    // Keep the drawn preview; the session resolves the unsettled preview by
    // close reason instead of treating grab loss as Escape or commit.
    cancelGesture();
    redraw();
    notifyGrabLost();
}

void PitchBendGraph::hoverEnterEvent(QHoverEvent *event)
{
    m_hovered = true;
    updateMouseHint(event->position());
    event->accept();
}

void PitchBendGraph::hoverMoveEvent(QHoverEvent *event)
{
    // Delivery implies membership; keep the flag honest even if an enter
    // was missed.
    m_hovered = true;
    updateMouseHint(event->position());
    event->accept();
}

void PitchBendGraph::hoverLeaveEvent(QHoverEvent *event)
{
    m_hovered = false;
    // An active gesture retains its source: Qt freezes ordinary hover
    // during the grab and the release/ungrab settle decides by actual
    // position. Focus loss alone never reaches this path.
    if (!hasGesture())
        clearMouseHint();
    event->accept();
}

void PitchBendGraph::itemChange(ItemChange change, const ItemChangeData &data)
{
    // Hide and window detachment always terminate this physical source,
    // including during a grab; the service's own observations clear too,
    // this keeps the item authoritative without depending on signal order.
    if ((change == ItemVisibleHasChanged && !data.boolValue) ||
        (change == ItemSceneChange && !data.window)) {
        m_hovered = false;
        clearMouseHint();
    }
    QQuickItem::itemChange(change, data);
}

ui::MouseHints *PitchBendGraph::mouseHints() const
{
    // Borrow once and cache through QPointer. instance() asserts on a dead
    // or closing application, so a late borrow during teardown stays null
    // instead of recreating the singleton.
    if (!m_mouseHints && qApp && !QCoreApplication::closingDown())
        m_mouseHints = &ui::MouseHints::instance();
    return m_mouseHints;
}

void PitchBendGraph::clearMouseHint()
{
    if (ui::MouseHints *const hints = mouseHints())
        hints->clear(this);
}

bool PitchBendGraph::hintSourceActive() const
{
    if (m_hovered)
        return true;
    const QQuickWindow *const itemWindow = window();
    return itemWindow && itemWindow->mouseGrabberItem() == this;
}

ui::hint_profiles::Id PitchBendGraph::hintProfileAt(const QPointF &position) const
{
    if (!canvasRect().contains(position.toPoint()))
        return ui::hint_profiles::Id::Empty;
    if (const auto hit = hitTest(position)) {
        // Pinned endpoints cannot move in time; they claim an empty profile
        // rather than advertising the interior vertex's Alt fine-time drag.
        if (m_kernel && (hit->first == m_kernel->startTick() || hit->first == m_kernel->endTick()))
            return ui::hint_profiles::Id::Empty;
        return ui::hint_profiles::Id::PitchBendVertex;
    }
    // Shift and Alt are two equivalent chords for the same line-drawing
    // alternative, never a combined Shift+Alt.
    return ui::hint_profiles::Id::PitchBendBackground;
}

void PitchBendGraph::publishMouseHintAt(const QPointF &position)
{
    m_gestureProfile = hintProfileAt(position);
    ui::MouseHints *const hints = mouseHints();
    if (!hints || !hintSourceActive())
        return;
    hints->claim(this, m_gestureProfile);
}

void PitchBendGraph::updateMouseHint(const QPointF &position)
{
    if (hasGesture()) {
        // Retain the originating profile for the whole gesture; hinting
        // never enters a mutating gesture path.
        if (ui::MouseHints *const hints = mouseHints())
            hints->claim(this, m_gestureProfile);
        return;
    }
    publishMouseHintAt(position);
}

void PitchBendGraph::refreshIdleMouseHint()
{
    // Only a currently hovered, gesture-free graph recomputes; a cursor
    // that left the item clears instead of restoring a stale target.
    if (m_hovered && !hasGesture())
        settleMouseHintAtCursor();
}

void PitchBendGraph::settleMouseHintAt(const QPointF &position)
{
    if (boundingRect().contains(position))
        publishMouseHintAt(position);
    else
        clearMouseHint();
}

void PitchBendGraph::settleMouseHintAtCursor()
{
    QQuickWindow *const itemWindow = window();
    if (!itemWindow) {
        clearMouseHint();
        return;
    }
    settleMouseHintAt(mapFromScene(itemWindow->mapFromGlobal(QCursor::pos())));
}

void PitchBendGraph::notifyPreviewChanged()
{
    if (m_kernel && m_callbacks.previewChanged)
        m_callbacks.previewChanged();
}

void PitchBendGraph::notifyCommitRequested()
{
    if (m_kernel && m_callbacks.commitRequested)
        m_callbacks.commitRequested();
}

void PitchBendGraph::notifyCancelRequested()
{
    if (m_kernel && m_callbacks.cancelRequested)
        m_callbacks.cancelRequested();
}

void PitchBendGraph::notifyAuditionRequested()
{
    if (m_kernel && m_callbacks.auditionRequested)
        m_callbacks.auditionRequested();
}

void PitchBendGraph::notifyGrabLost()
{
    if (m_kernel && m_callbacks.grabLost)
        m_callbacks.grabLost();
}

void PitchBendGraph::finishGesture()
{
    if (m_kernel)
        m_kernel->endGesture();
    redraw();
    notifyCommitRequested();
}

PitchBendKernel::Lane PitchBendGraph::toKernelLane(Lane lane)
{
    return lane == Lane::ModWheel ? PitchBendKernel::Lane::ModWheel
                                  : PitchBendKernel::Lane::PitchBend;
}

PitchBendGraph::Lane PitchBendGraph::fromKernelLane(PitchBendKernel::Lane lane)
{
    return lane == PitchBendKernel::Lane::ModWheel ? Lane::ModWheel : Lane::PitchBend;
}

QString PitchBendGraph::formatLiveValue() const
{
    const int live = liveValue();
    if (lane() == Lane::ModWheel)
        return QString::number(live);
    if (live == 0 || m_bendRange == 0)
        return SongView::tr("0 st");
    const double semitones = double(live) * double(m_bendRange) / double(live > 0 ? 8191 : 8192);
    return SongView::tr("%1%2 st")
        .arg(semitones > 0 ? QStringLiteral("+") : QString())
        .arg(semitones, 0, 'f', 2);
}

QString PitchBendGraph::formatRangeLimit(bool positive) const
{
    if (lane() == Lane::ModWheel)
        return positive ? QStringLiteral("127") : QStringLiteral("0");
    if (m_bendRange == 0)
        return SongView::tr("0 st");
    return SongView::tr("%1%2 st")
        .arg(positive ? QStringLiteral("+") : QStringLiteral("-"))
        .arg(m_bendRange);
}

} // namespace songview
