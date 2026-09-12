#include "pitchbendgraph.hpp"

#include "songview.h"

#include "ui/keymap.h"

#include <QFocusEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>
#include <iterator>
#include <utility>

namespace songview {

PitchBendGraph::PitchBendGraph(QQuickItem *parent) : QQuickItem(parent)
{
    setAcceptedMouseButtons(Qt::NoButton);
    setActiveFocusOnTab(false);
    setCursor(Qt::CrossCursor);
}

void PitchBendGraph::initialize(Initialization initial)
{
    if (m_initialized || !initial.songView)
        return;

    m_songView = initial.songView;
    m_grid = &m_songView->grid();
    m_engineTrack = initial.engineTrack;
    m_startTick = initial.startTick;
    m_endTick = initial.endTick;
    m_unterminated = initial.unterminated;
    m_lane = initial.lane;
    m_geometry = initial.geometry;
    m_bendRange = std::clamp(initial.bendRange, 0, 127);
    m_points = std::move(initial.points);
    m_endValue = std::clamp(initial.endValue, minimumValue(), maximumValue());
    m_points[m_endTick] = m_endValue;
    m_callbacks = std::move(initial.callbacks);
    m_rangeWheelRemainder = 0.0;
    m_strokeState.reset();
    m_vertexDragState.reset();
    m_selectedTick.reset();
    m_keyboardTick = m_startTick;
    m_liveValue = valueAtTick(m_keyboardTick);

    m_initialized = true;
    setFlag(ItemHasContents, true);
    setAcceptedMouseButtons(Qt::LeftButton);
    setActiveFocusOnTab(true);
    redraw();
    notifyPresentationChanged();
    notifyLiveValueChanged();
}

void PitchBendGraph::setMetrics(const PitchBendGeometry &geometry)
{
    if (!m_initialized)
        return;
    m_geometry = geometry;
    redraw();
    notifyPresentationChanged();
}

void PitchBendGraph::setBendRange(int range)
{
    if (!m_initialized)
        return;
    const int clampedRange = std::clamp(range, 0, 127);
    if (m_bendRange == clampedRange)
        return;
    m_bendRange = clampedRange;
    redraw();
    notifyPresentationChanged();
    notifyLiveValueChanged();
}

void PitchBendGraph::setCurve(const std::map<Tick, int> &points, int endValue)
{
    if (!m_initialized)
        return;
    m_points = points;
    m_endValue = std::clamp(endValue, minimumValue(), maximumValue());
    m_points[m_endTick] = m_endValue;
    if (m_selectedTick && !m_points.contains(*m_selectedTick))
        m_selectedTick.reset();
    cancelGesture();
    m_keyboardTick = m_startTick;
    m_liveValue = valueAtTick(m_keyboardTick);
    redraw();
    notifyLiveValueChanged();
}

void PitchBendGraph::resetCurve()
{
    if (!m_initialized)
        return;
    m_points.clear();
    m_points[m_startTick] = defaultValue();
    m_points[m_endTick] = m_endValue;
    m_selectedTick.reset();
    cancelGesture();
    m_keyboardTick = m_startTick;
    m_liveValue = defaultValue();
    notifyPreviewChanged();
    forceActiveFocus(Qt::MouseFocusReason);
    redraw();
    notifyLiveValueChanged();
}

std::optional<Tick> PitchBendGraph::selectedTick() const
{
    return m_selectedTick;
}

void PitchBendGraph::setSelectedTick(std::optional<Tick> tick)
{
    if (!m_initialized)
        return;
    if (tick && !m_points.contains(*tick))
        tick.reset();
    if (m_selectedTick == tick)
        return;
    m_selectedTick = tick;
    redraw();
}

std::optional<std::pair<Tick, int>> PitchBendGraph::hitTest(const QPointF &position) const
{
    if (!m_initialized)
        return std::nullopt;
    // Node radii are DIPs; Quick delivers item-local points, so unlike the
    // widget surface there is no per-window DPR multiplier here.
    const qreal radiusSquared = m_geometry.nodeHitRadius * m_geometry.nodeHitRadius;
    qreal nearestDistanceSquared = radiusSquared;
    std::optional<std::pair<Tick, int>> nearest;
    for (const auto &[tick, value] : m_points) {
        const QPoint center = vertexPosition(tick, value);
        const qreal dx = position.x() - center.x();
        const qreal dy = position.y() - center.y();
        const qreal distanceSquared = dx * dx + dy * dy;
        if (distanceSquared > radiusSquared)
            continue;
        if (!nearest || distanceSquared < nearestDistanceSquared ||
            (qFuzzyCompare(distanceSquared, nearestDistanceSquared) && tick < nearest->first)) {
            nearestDistanceSquared = distanceSquared;
            nearest = std::pair{tick, value};
        }
    }
    return nearest;
}

bool PitchBendGraph::removeSelectedVertex()
{
    if (!m_initialized || !m_selectedTick || *m_selectedTick == m_startTick ||
        *m_selectedTick == m_endTick) {
        return false;
    }
    if (m_points.erase(*m_selectedTick) == 0)
        return false;
    setSelectedTick(std::nullopt);
    m_liveValue = valueAtTick(m_keyboardTick);
    notifyPreviewChanged();
    notifyLiveValueChanged();
    notifyCommitRequested();
    return true;
}

QPoint PitchBendGraph::vertexPosition(Tick tick, int value) const
{
    if (!m_initialized)
        return {};
    return {xAtTick(tick), yAtValue(value)};
}

void PitchBendGraph::setKeyboardFraction(double fraction)
{
    if (!m_initialized)
        return;
    m_keyboardTick = tickAtFraction(fraction, Sampling::Normal);
    m_liveValue = valueAtTick(m_keyboardTick);
    redraw();
    notifyLiveValueChanged();
}

void PitchBendGraph::cancelGesture()
{
    m_strokeState.reset();
    m_vertexDragState.reset();
}

bool PitchBendGraph::handleKeyPress(QKeyEvent *event)
{
    if (!m_initialized) {
        event->ignore();
        return false;
    }
    if (event->key() == Qt::Key_Escape) {
        cancelGesture();
        notifyCancelRequested();
        event->accept();
        return true;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) && m_selectedTick) {
        removeSelectedVertex();
        event->accept();
        return true;
    }
    const auto &keys = keymap::Registry::instance();
    if (keys.matches(event, QStringLiteral("transport.play_pause"))) {
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
    return m_initialized ? m_geometry.canvas : QRect{};
}

bool PitchBendGraph::hasGesture() const
{
    return m_initialized && (m_strokeState || m_vertexDragState);
}

int PitchBendGraph::liveValue() const
{
    return m_initialized ? m_liveValue : 0;
}

std::vector<SongDocument::LanePointValue> PitchBendGraph::curvePoints() const
{
    if (!m_initialized)
        return {};
    std::vector<SongDocument::LanePointValue> points;
    points.reserve(m_points.size());
    const uint32_t fineTick = m_grid ? m_grid->fineGridTicks() : 1;
    int previous = 0;
    Tick previousTick = 0;
    bool havePrevious = false;
    for (const auto &[tick, value] : m_points) {
        const bool endpoint = tick == m_startTick || tick == m_endTick;
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
    return m_lane;
}

QString PitchBendGraph::laneTitle() const
{
    return m_lane == Lane::PitchBend ? SongView::tr("Pitch bend (BEND)")
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
    return m_lane == Lane::PitchBend;
}

void PitchBendGraph::redraw()
{
    if (!m_initialized)
        return;
    rebuildLayer();
    update();
}

void PitchBendGraph::notifyPresentationChanged()
{
    if (m_initialized)
        emit presentationChanged();
}

void PitchBendGraph::notifyLiveValueChanged()
{
    if (m_initialized)
        emit liveValueChanged();
}

void PitchBendGraph::mousePressEvent(QMouseEvent *event)
{
    if (!m_initialized || event->button() != Qt::LeftButton ||
        !canvasRect().contains(event->position().toPoint())) {
        event->ignore();
        return;
    }
    if (const auto hit = hitTest(event->position())) {
        forceActiveFocus(Qt::MouseFocusReason);
        setSelectedTick(hit->first);
        m_vertexDragState.emplace();
        auto &state = *m_vertexDragState;
        state.snapshot = m_points;
        state.originalTick = hit->first;
        m_keyboardTick = hit->first;
        m_liveValue = hit->second;
        notifyPreviewChanged();
        redraw();
        notifyLiveValueChanged();
        event->accept();
        return;
    }
    setSelectedTick(std::nullopt);
    forceActiveFocus(Qt::MouseFocusReason);
    m_strokeState.emplace();
    auto &state = *m_strokeState;
    state.mode = (event->modifiers() & (Qt::ShiftModifier | Qt::AltModifier))
                     ? StrokeMode::AngledLine
                     : StrokeMode::Freehand;
    if (isLineGesture())
        state.snapshot = m_points;
    state.previousTick = tickAtX(event->position().x(), gestureSampling());
    state.previousValue = valueAtY(event->position().y());
    state.anchorTick = state.previousTick;
    state.anchorValue = state.previousValue;
    replaceSegment(state.previousTick, state.previousValue, state.previousTick, state.previousValue,
                   gestureSampling());
    m_keyboardTick = state.previousTick;
    m_liveValue = state.previousValue;
    notifyPreviewChanged();
    redraw();
    notifyLiveValueChanged();
    event->accept();
}

void PitchBendGraph::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_initialized || (!m_strokeState && !m_vertexDragState)) {
        event->ignore();
        return;
    }
    if (m_vertexDragState)
        updateVertexDrag(event->position(), event->modifiers());
    else
        updateStroke(event->position());
    event->accept();
}

void PitchBendGraph::mouseReleaseEvent(QMouseEvent *event)
{
    if (!m_initialized || event->button() != Qt::LeftButton ||
        (!m_strokeState && !m_vertexDragState)) {
        event->ignore();
        return;
    }
    if (m_vertexDragState)
        updateVertexDrag(event->position(), event->modifiers());
    else
        updateStroke(event->position());
    finishGesture();
    event->accept();
}

void PitchBendGraph::wheelEvent(QWheelEvent *event)
{
    if (!m_initialized || m_lane != Lane::PitchBend ||
        !canvasRect().contains(event->position().toPoint())) {
        event->ignore();
        return;
    }
    const QPoint delta = event->pixelDelta().isNull() ? event->angleDelta() : event->pixelDelta();
    const double units = event->phase() == Qt::ScrollMomentum
                             ? 0.0
                             : double(delta.y()) * (event->pixelDelta().isNull() ? 1.0 : 5.0);
    m_rangeWheelRemainder += units;
    const int steps = int(m_rangeWheelRemainder / 120.0);
    if (steps != 0) {
        m_rangeWheelRemainder -= double(steps) * 120.0;
        if (m_callbacks.rangeChangeRequested)
            m_callbacks.rangeChangeRequested(steps);
    }
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
    if (m_initialized)
        redraw();
}

void PitchBendGraph::focusOutEvent(QFocusEvent *event)
{
    // Ordinary focus movement between popup controls must not dismiss or
    // cancel anything; it only repaints the focus frame.
    QQuickItem::focusOutEvent(event);
    if (m_initialized)
        redraw();
}

void PitchBendGraph::mouseUngrabEvent()
{
    if (!m_initialized || (!m_strokeState && !m_vertexDragState))
        return; // Normal release already settled the gesture; never double-fire.
    // Keep the drawn preview; the session resolves the unsettled preview by
    // close reason instead of treating grab loss as Escape or commit.
    cancelGesture();
    redraw();
    notifyGrabLost();
}

void PitchBendGraph::notifyPreviewChanged()
{
    if (m_initialized && m_callbacks.previewChanged)
        m_callbacks.previewChanged();
}

void PitchBendGraph::notifyCommitRequested()
{
    if (m_initialized && m_callbacks.commitRequested)
        m_callbacks.commitRequested();
}

void PitchBendGraph::notifyCancelRequested()
{
    if (m_initialized && m_callbacks.cancelRequested)
        m_callbacks.cancelRequested();
}

void PitchBendGraph::notifyAuditionRequested()
{
    if (m_initialized && m_callbacks.auditionRequested)
        m_callbacks.auditionRequested();
}

void PitchBendGraph::notifyGrabLost()
{
    if (m_initialized && m_callbacks.grabLost)
        m_callbacks.grabLost();
}

void PitchBendGraph::updateStroke(const QPointF &position)
{
    if (!m_initialized || !m_strokeState)
        return;
    auto &state = *m_strokeState;
    const Tick tick = tickAtX(position.x(), gestureSampling());
    const int value = valueAtY(position.y());
    if (isLineGesture()) {
        m_points = state.snapshot;
        replaceSegment(state.anchorTick, state.anchorValue, tick, value, gestureSampling());
    } else {
        replaceSegment(state.previousTick, state.previousValue, tick, value, gestureSampling());
    }
    state.previousTick = tick;
    state.previousValue = value;
    m_keyboardTick = tick;
    m_liveValue = value;
    notifyPreviewChanged();
    redraw();
    notifyLiveValueChanged();
}

void PitchBendGraph::updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers)
{
    if (!m_initialized || !m_vertexDragState)
        return;
    auto &state = *m_vertexDragState;
    m_points = state.snapshot;
    const int value = valueAtY(position.y());
    Tick tick = state.originalTick;
    const bool endpoint = tick == m_startTick || tick == m_endTick;
    if (!endpoint && m_endTick > m_startTick + 1) {
        const Sampling sampling = modifiers & Qt::AltModifier ? Sampling::Fine : Sampling::Normal;
        const Tick minimumTick = m_startTick + 1;
        const Tick maximumTick = m_endTick - 1;
        tick = std::clamp(tickAtX(position.x(), sampling), minimumTick, maximumTick);
        if (tick != state.originalTick && m_points.contains(tick)) {
            const int direction = tick > state.originalTick ? 1 : -1;
            Tick candidate = tick;
            bool found = false;
            while (true) {
                if (direction > 0) {
                    if (candidate >= maximumTick)
                        break;
                    ++candidate;
                } else {
                    if (candidate <= minimumTick)
                        break;
                    --candidate;
                }
                if (!m_points.contains(candidate)) {
                    tick = candidate;
                    found = true;
                    break;
                }
            }
            if (!found)
                tick = state.originalTick;
        }
    }
    if (tick != state.originalTick)
        m_points.erase(state.originalTick);
    const int storedValue = state.originalTick == m_endTick ? m_endValue : value;
    m_points[tick] = storedValue;
    m_points[m_endTick] = m_endValue;
    m_selectedTick = tick;
    m_keyboardTick = tick;
    m_liveValue = storedValue;
    notifyPreviewChanged();
    redraw();
    notifyLiveValueChanged();
}

void PitchBendGraph::finishGesture()
{
    cancelGesture();
    redraw();
    notifyCommitRequested();
}

void PitchBendGraph::replaceSegment(Tick tick0, int value0, Tick tick1, int value1,
                                    Sampling sampling)
{
    const Tick low = std::min(tick0, tick1);
    const Tick high = std::max(tick0, tick1);
    const auto eraseBegin = m_points.lower_bound(low);
    const auto eraseEnd = m_points.upper_bound(high);
    m_points.erase(eraseBegin, eraseEnd);
    const auto writeSample = [&](Tick sampleTick) {
        const double fraction =
            tick1 == tick0
                ? 1.0
                : std::clamp((double(sampleTick) - double(tick0)) / (double(tick1) - double(tick0)),
                             0.0, 1.0);
        m_points[sampleTick] = std::clamp(value0 + qRound(fraction * double(value1 - value0)),
                                          minimumValue(), maximumValue());
    };
    writeSample(low);
    Tick tick = low;
    while (tick < high) {
        const Tick next = nextSampleTick(tick, sampling);
        if (next <= tick || next >= high)
            break;
        writeSample(next);
        tick = next;
    }
    if (high != low)
        writeSample(high);
    m_points[m_endTick] = m_endValue;
}

bool PitchBendGraph::isLineGesture() const
{
    return m_strokeState && m_strokeState->mode == StrokeMode::AngledLine;
}

PitchBendGraph::Sampling PitchBendGraph::gestureSampling() const
{
    return isLineGesture() ? Sampling::Fine : Sampling::Normal;
}

uint32_t PitchBendGraph::normalCellTicksAt(Tick tick) const
{
    if (!m_grid)
        return 1;
    const uint32_t span = std::max<Tick>(1, m_endTick - m_startTick);
    const double pixelsPerTick = double(canvasRect().width() - 1) / double(span);
    return m_grid->gridTicksAtScale(tick, pixelsPerTick);
}

uint32_t PitchBendGraph::samplingCellTicksAt(Tick tick, Sampling sampling) const
{
    return sampling == Sampling::Fine ? (m_grid ? m_grid->fineGridTicks() : 1)
                                      : normalCellTicksAt(tick);
}

Tick PitchBendGraph::nextSampleTick(Tick tick, Sampling sampling) const
{
    if (tick >= m_endTick)
        return m_endTick;
    const uint32_t cell = samplingCellTicksAt(tick, sampling);
    Tick segmentEnd = m_endTick;
    const Tick anchor =
        sampling == Sampling::Fine ? 0 : (m_grid ? m_grid->segmentAt(tick).start : 0);
    if (sampling == Sampling::Normal && m_grid)
        segmentEnd = std::min(m_endTick, m_grid->segmentAt(tick).next);
    const uint64_t offset = tick > anchor ? tick - anchor : 0;
    const uint64_t quotient = offset / cell;
    const uint64_t aligned = uint64_t(anchor) + (quotient + 1) * cell;
    if (aligned > tick)
        return std::min(Tick(aligned), segmentEnd);
    return std::min(Tick(tick + 1), segmentEnd);
}

Tick PitchBendGraph::lastEditableTick(Sampling sampling) const
{
    if (m_endTick <= m_startTick + 1)
        return m_startTick;
    const Tick lastRaw = m_endTick - 1;
    const uint32_t cell = samplingCellTicksAt(lastRaw, sampling);
    const Tick anchor =
        sampling == Sampling::Fine ? 0 : (m_grid ? m_grid->segmentAt(lastRaw).start : 0);
    const Tick tick = lastRaw < anchor ? m_startTick : anchor + ((lastRaw - anchor) / cell) * cell;
    return std::clamp(tick, m_startTick, lastRaw);
}
Tick PitchBendGraph::tickAtFraction(double fraction, Sampling sampling) const
{
    if (fraction <= 0.0)
        return m_startTick;
    if (fraction >= 1.0)
        return lastEditableTick(sampling);
    const double raw = double(m_startTick) + fraction * double(m_endTick - m_startTick);
    const Tick rawTick =
        std::clamp<Tick>(CoreTimeDefaults::tickFromDouble(std::round(raw)), m_startTick, m_endTick);
    const uint32_t cell = samplingCellTicksAt(rawTick, sampling);
    const Tick anchor =
        sampling == Sampling::Fine ? 0 : (m_grid ? m_grid->segmentAt(rawTick).start : 0);
    const double snapped =
        double(anchor) + std::round((raw - double(anchor)) / double(cell)) * cell;
    if (snapped <= double(m_startTick))
        return m_startTick;
    if (sampling == Sampling::Normal && m_grid) {
        const Tick segmentEnd = std::min(m_endTick, m_grid->segmentAt(rawTick).next);
        if (snapped >= double(segmentEnd) && segmentEnd < m_endTick)
            return segmentEnd;
    }
    return std::min<Tick>(CoreTimeDefaults::tickFromDouble(snapped), lastEditableTick(sampling));
}

Tick PitchBendGraph::tickAtX(qreal x, Sampling sampling) const
{
    const QRect graph = canvasRect();
    const double fraction =
        std::clamp((x - graph.left()) / double(std::max(1, graph.width() - 1)), 0.0, 1.0);
    return tickAtFraction(fraction, sampling);
}

int PitchBendGraph::xAtTick(Tick tick) const
{
    const QRect graph = canvasRect();
    const double fraction = m_endTick > m_startTick && tick >= m_startTick
                                ? double(tick - m_startTick) / double(m_endTick - m_startTick)
                                : 0.0;
    return graph.left() + qRound(std::clamp(fraction, 0.0, 1.0) * (graph.width() - 1));
}

int PitchBendGraph::valueAtY(qreal y) const
{
    const QRect graph = canvasRect();
    const int clampedY = std::clamp(qRound(y), graph.top(), graph.bottom());
    if (m_lane == Lane::ModWheel) {
        return std::clamp(
            qRound(double(graph.bottom() - clampedY) * 127.0 / double(std::max(1, graph.height()))),
            0, 127);
    }
    const int center = graph.center().y();
    if (std::abs(clampedY - center) <= m_geometry.zeroDetent)
        return 0;
    int value = 0;
    if (clampedY <= center)
        value =
            qRound(double(center - clampedY) * 8191.0 / double(std::max(1, center - graph.top())));
    else
        value = -qRound(double(clampedY - center) * 8192.0 /
                        double(std::max(1, graph.bottom() - center)));
    if (value == -8192 || value == 8191)
        return value;
    return std::clamp(qRound(double(value) / kBendStep) * kBendStep, -8192, 8191);
}

int PitchBendGraph::yAtValue(int value) const
{
    const QRect graph = canvasRect();
    if (m_lane == Lane::ModWheel)
        return graph.bottom() - qRound(double(std::clamp(value, 0, 127)) * graph.height() / 127.0);
    const int center = graph.center().y();
    if (value >= 0)
        return center - qRound(double(value) * double(center - graph.top()) / 8191.0);
    return center + qRound(double(-value) * double(graph.bottom() - center) / 8192.0);
}

int PitchBendGraph::valueAtTick(Tick tick) const
{
    const auto it = m_points.upper_bound(tick);
    if (it == m_points.begin())
        return defaultValue();
    return std::prev(it)->second;
}

int PitchBendGraph::minimumValue() const
{
    return m_lane == Lane::PitchBend ? -8192 : 0;
}

int PitchBendGraph::maximumValue() const
{
    return m_lane == Lane::PitchBend ? 8191 : 127;
}

int PitchBendGraph::defaultValue() const
{
    return 0;
}

QString PitchBendGraph::formatLiveValue() const
{
    if (m_lane == Lane::ModWheel)
        return QString::number(m_liveValue);
    if (m_liveValue == 0 || m_bendRange == 0)
        return SongView::tr("0 st");
    const double semitones =
        double(m_liveValue) * double(m_bendRange) / double(m_liveValue > 0 ? 8191 : 8192);
    return SongView::tr("%1%2 st")
        .arg(semitones > 0 ? QStringLiteral("+") : QString())
        .arg(semitones, 0, 'f', 2);
}

QString PitchBendGraph::formatRangeLimit(bool positive) const
{
    if (m_lane == Lane::ModWheel)
        return positive ? QStringLiteral("127") : QStringLiteral("0");
    if (m_bendRange == 0)
        return SongView::tr("0 st");
    return SongView::tr("%1%2 st")
        .arg(positive ? QStringLiteral("+") : QStringLiteral("-"))
        .arg(m_bendRange);
}

} // namespace songview
