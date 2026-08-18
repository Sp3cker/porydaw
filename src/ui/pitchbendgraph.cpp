#include "pitchbendgraph.hpp"
#include "songview.h"

#include "theme/themeruntime.h"
#include "typography.h"
#include "ui/keymap.h"
#include "ui/m4asemantics.h"

#include <QPainter>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <utility>

namespace songview {

PitchBendGraph::PitchBendGraph(::SongView *songView, int engineTrack, uint64_t startTick,
                               uint64_t endTick, bool unterminated, Lane lane, QWidget *parent)
    : QWidget(parent)
    , m_songView(songView)
    , m_engineTrack(engineTrack)
    , m_startTick(startTick)
    , m_endTick(endTick)
    , m_unterminated(unterminated)
    , m_lane(lane)
    , m_keyboardTick(startTick)
{
    setObjectName(lane == Lane::PitchBend ? QStringLiteral("pitchBendGraph")
                                          : QStringLiteral("modWheelGraph"));
    setFocusPolicy(Qt::StrongFocus);
    setMouseTracking(true);
    setCursor(Qt::CrossCursor);
}

void PitchBendGraph::setCallbacks(Callbacks callbacks)
{
    m_callbacks = std::move(callbacks);
}

void PitchBendGraph::setBendRange(int range)
{
    m_bendRange = std::clamp(range, 0, 127);
    update();
}

void PitchBendGraph::setCurve(const std::map<uint64_t, int> &points, int endValue)
{
    m_points = points;
    m_endValue = std::clamp(endValue, minimumValue(), maximumValue());
    m_points[m_endTick] = m_endValue;
    if (m_selectedTick && !m_points.contains(*m_selectedTick))
        m_selectedTick.reset();
    cancelGesture();
    m_keyboardTick = m_startTick;
    m_liveValue = valueAtTick(m_keyboardTick);
    update();
}

void PitchBendGraph::resetCurve()
{
    m_points.clear();
    m_points[m_startTick] = defaultValue();
    m_points[m_endTick] = m_endValue;
    m_selectedTick.reset();
    cancelGesture();
    m_keyboardTick = m_startTick;
    m_liveValue = defaultValue();
    notifyPreviewChanged();
    setFocus(Qt::MouseFocusReason);
    update();
}

std::optional<uint64_t> PitchBendGraph::selectedTick() const
{
    return m_selectedTick;
}

void PitchBendGraph::setSelectedTick(std::optional<uint64_t> tick)
{
    if (tick && !m_points.contains(*tick))
        tick.reset();
    if (m_selectedTick == tick)
        return;
    m_selectedTick = tick;
    update();
}

std::optional<std::pair<uint64_t, int>> PitchBendGraph::hitTest(const QPointF &position) const
{
    const qreal radius = kNodeHitRadius * std::max<qreal>(devicePixelRatioF(), 1.0);
    const qreal radiusSquared = radius * radius;
    qreal nearestDistanceSquared = radiusSquared;
    std::optional<std::pair<uint64_t, int>> nearest;
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
    if (!m_selectedTick || *m_selectedTick == m_startTick || *m_selectedTick == m_endTick)
        return false;
    if (m_points.erase(*m_selectedTick) == 0)
        return false;
    setSelectedTick(std::nullopt);
    notifyPreviewChanged();
    notifyCommitRequested();
    return true;
}

QPoint PitchBendGraph::vertexPosition(uint64_t tick, int value) const
{
    return {xAtTick(tick), yAtValue(value)};
}

void PitchBendGraph::setKeyboardFraction(double fraction)
{
    m_keyboardTick = tickAtFraction(fraction, Sampling::Normal);
    m_liveValue = valueAtTick(m_keyboardTick);
    update();
}

void PitchBendGraph::cancelGesture()
{
    m_strokeState.reset();
    m_vertexDragState.reset();
}

bool PitchBendGraph::handleKeyPress(QKeyEvent *event)
{
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
    QWidget::keyPressEvent(event);
    return event->isAccepted();
}

QRect PitchBendGraph::canvasRect() const
{
    return QRect(kAxisGutter, kGraphTop, kGraphWidth, kGraphHeight);
}

bool PitchBendGraph::hasGesture() const
{
    return m_strokeState || m_vertexDragState;
}

int PitchBendGraph::liveValue() const
{
    return m_liveValue;
}

std::vector<SongDocument::LanePointValue> PitchBendGraph::curvePoints() const
{
    std::vector<SongDocument::LanePointValue> points;
    points.reserve(m_points.size());
    const uint64_t fineTick = m_songView ? m_songView->fineGridTicks() : 1;
    int previous = 0;
    uint64_t previousTick = 0;
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

void PitchBendGraph::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.fillRect(canvasRect(), themes::color(themes::Role::song_view_piano_roll_background));
    painter.save();
    painter.setClipRect(canvasRect());
    paintGrid(painter);
    paintCurve(painter);
    paintLinePreview(painter);
    painter.restore();
    paintAxes(painter);
    paintFocus(painter);
}

void PitchBendGraph::mousePressEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton || !canvasRect().contains(event->position().toPoint())) {
        event->ignore();
        return;
    }
    if (const auto hit = hitTest(event->position())) {
        setFocus(Qt::MouseFocusReason);
        setSelectedTick(hit->first);
        m_vertexDragState.emplace();
        auto &state = *m_vertexDragState;
        state.snapshot = m_points;
        state.originalTick = hit->first;
        m_keyboardTick = hit->first;
        m_liveValue = hit->second;
        notifyPreviewChanged();
        update();
        event->accept();
        return;
    }
    setSelectedTick(std::nullopt);
    setFocus(Qt::MouseFocusReason);
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
    update();
    event->accept();
}

void PitchBendGraph::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_strokeState && !m_vertexDragState) {
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
    if (event->button() != Qt::LeftButton || (!m_strokeState && !m_vertexDragState)) {
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
    if (m_lane != Lane::PitchBend || !canvasRect().contains(event->position().toPoint())) {
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
        QWidget::keyPressEvent(event);
}

void PitchBendGraph::focusInEvent(QFocusEvent *event)
{
    QWidget::focusInEvent(event);
    update();
}

void PitchBendGraph::focusOutEvent(QFocusEvent *event)
{
    QWidget::focusOutEvent(event);
    update();
}

void PitchBendGraph::paintGrid(QPainter &painter)
{
    painter.setPen(QPen(themes::color(themes::Role::song_view_grid), 1));
    if (m_songView && m_endTick > m_startTick) {
        uint64_t segmentTick = m_startTick;
        while (segmentTick < m_endTick) {
            const SongView::GridSeg segment = m_songView->gridSegAt(segmentTick);
            const uint64_t segmentEnd = std::min(m_endTick, segment.next);
            const uint64_t cell = normalCellTicksAt(segmentTick);
            const uint64_t anchor = segment.start;
            const uint64_t offset = segmentTick > anchor ? segmentTick - anchor : 0;
            const uint64_t quotient = offset / cell;
            uint64_t tick = anchor;
            if (quotient < UINT64_MAX / cell)
                tick = anchor + (quotient + 1) * cell;
            while (tick < segmentEnd) {
                const int x = xAtTick(tick);
                painter.drawLine(x, canvasRect().top(), x, canvasRect().bottom());
                if (UINT64_MAX - tick < cell)
                    break;
                tick += cell;
            }
            if (segmentEnd >= m_endTick)
                break;
            segmentTick = segmentEnd;
        }
    }
    painter.setPen(QPen(themes::color(themes::Role::song_view_separator), 1, Qt::DashLine));
    painter.drawLine(canvasRect().left(), yAtValue(0), canvasRect().right(), yAtValue(0));
}

void PitchBendGraph::paintCurve(QPainter &painter)
{
    const QColor curveColor = SongView::trackColor(m_engineTrack);
    const QColor endpointColor = themes::color(themes::Role::song_view_secondary_text);
    const QColor selectedRing = themes::color(themes::Role::focus_outline);
    painter.save();
    painter.setClipRect(canvasRect(), Qt::IntersectClip);
    painter.setPen(QPen(curveColor, 2));
    const uint64_t fineTick = m_songView ? m_songView->fineGridTicks() : 1;
    for (auto it = m_points.cbegin(); it != m_points.cend(); ++it) {
        const auto next = std::next(it);
        const int x0 = xAtTick(it->first);
        const int x1 = next == m_points.cend() ? canvasRect().right() : xAtTick(next->first);
        const int y = yAtValue(it->second);
        const bool angled = next != m_points.cend() && next->first > it->first &&
                            next->first - it->first == fineTick;
        if (angled) {
            painter.drawLine(x0, y, x1, yAtValue(next->second));
        } else {
            painter.drawLine(x0, y, x1, y);
            if (next != m_points.cend())
                painter.drawLine(x1, y, x1, yAtValue(next->second));
        }
    }
    const bool antialiasing = painter.testRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::Antialiasing, true);
    for (const auto &[tick, value] : m_points) {
        const QPointF center(vertexPosition(tick, value));
        const bool selected = m_selectedTick && *m_selectedTick == tick;
        if (selected) {
            painter.setPen(QPen(selectedRing, 1.5));
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(center, kSelectedNodeRingRadius, kSelectedNodeRingRadius);
            painter.setPen(Qt::NoPen);
            painter.setBrush(curveColor);
            painter.drawEllipse(center, kNodePaintRadius, kNodePaintRadius);
            continue;
        }
        painter.setPen(Qt::NoPen);
        painter.setBrush(tick == m_startTick || tick == m_endTick ? endpointColor : curveColor);
        const qreal radius = tick == m_startTick || tick == m_endTick
                                 ? std::max(1, kNodePaintRadius - 1)
                                 : kNodePaintRadius;
        painter.drawEllipse(center, radius, radius);
    }
    painter.setRenderHint(QPainter::Antialiasing, antialiasing);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline), 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(vertexPosition(m_keyboardTick, m_liveValue), 3, 3);
    painter.restore();
}

void PitchBendGraph::paintLinePreview(QPainter &painter)
{
    if (!m_strokeState || !isLineGesture())
        return;
    const StrokeState &state = *m_strokeState;
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline), 1));
    painter.drawLine(QPointF(vertexPosition(state.anchorTick, state.anchorValue)),
                     QPointF(vertexPosition(state.previousTick, state.previousValue)));
}

void PitchBendGraph::paintAxes(QPainter &painter)
{
    const QRect graph = canvasRect();
    const QFont captionFont = typography::caption(font());
    painter.setFont(captionFont);
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    const QRect axisRect(8, graph.top() - 7, kAxisGutter - 12, 14);
    const QRect titleRect(graph.left(), 3, graph.width() - 68, 17);
    painter.drawText(titleRect, Qt::AlignLeft | Qt::AlignVCenter, laneTitle());
    painter.drawText(titleRect, Qt::AlignRight | Qt::AlignVCenter, formatLiveValue());
    painter.drawText(axisRect, Qt::AlignRight | Qt::AlignVCenter, formatRangeLimit(true));
    if (m_lane == Lane::PitchBend) {
        painter.drawText(axisRect.translated(0, yAtValue(0) - graph.top()),
                         Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("0"));
    }
    painter.drawText(axisRect.translated(0, graph.bottom() - graph.top()),
                     Qt::AlignRight | Qt::AlignVCenter, formatRangeLimit(false));
    painter.drawText(QRect(graph.left(), graph.bottom() + 2, graph.width(), kAxisLabelHeight),
                     Qt::AlignLeft | Qt::AlignVCenter, SongView::tr("Note on"));
    painter.drawText(QRect(graph.left(), graph.bottom() + 2, graph.width(), kAxisLabelHeight),
                     Qt::AlignRight | Qt::AlignVCenter,
                     m_unterminated ? SongView::tr("Song end") : SongView::tr("Note off"));
}

void PitchBendGraph::paintFocus(QPainter &painter)
{
    if (!hasFocus() && (!parentWidget() || !parentWidget()->hasFocus()))
        return;
    painter.setPen(QPen(themes::color(themes::Role::focus_outline), 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawRect(canvasRect().adjusted(1, 1, -1, -1));
}

void PitchBendGraph::notifyPreviewChanged()
{
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
}

void PitchBendGraph::notifyCommitRequested()
{
    if (m_callbacks.commitRequested)
        m_callbacks.commitRequested();
}

void PitchBendGraph::notifyCancelRequested()
{
    if (m_callbacks.cancelRequested)
        m_callbacks.cancelRequested();
}

void PitchBendGraph::notifyAuditionRequested()
{
    if (m_callbacks.auditionRequested)
        m_callbacks.auditionRequested();
}

void PitchBendGraph::updateStroke(const QPointF &position)
{
    if (!m_strokeState)
        return;
    auto &state = *m_strokeState;
    const uint64_t tick = tickAtX(position.x(), gestureSampling());
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
    update();
}

void PitchBendGraph::updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers)
{
    if (!m_vertexDragState)
        return;
    auto &state = *m_vertexDragState;
    m_points = state.snapshot;
    const int value = valueAtY(position.y());
    uint64_t tick = state.originalTick;
    const bool endpoint = tick == m_startTick || tick == m_endTick;
    if (!endpoint && m_endTick > m_startTick + 1) {
        const Sampling sampling = modifiers & Qt::AltModifier ? Sampling::Fine : Sampling::Normal;
        const uint64_t minimumTick = m_startTick + 1;
        const uint64_t maximumTick = m_endTick - 1;
        tick = std::clamp(tickAtX(position.x(), sampling), minimumTick, maximumTick);
        if (tick != state.originalTick && m_points.contains(tick)) {
            const int direction = tick > state.originalTick ? 1 : -1;
            uint64_t candidate = tick;
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
    update();
}

void PitchBendGraph::finishGesture()
{
    cancelGesture();
    notifyCommitRequested();
}

void PitchBendGraph::replaceSegment(uint64_t tick0, int value0, uint64_t tick1, int value1,
                                    Sampling sampling)
{
    const uint64_t low = std::min(tick0, tick1);
    const uint64_t high = std::max(tick0, tick1);
    const auto eraseBegin = m_points.lower_bound(low);
    const auto eraseEnd = m_points.upper_bound(high);
    m_points.erase(eraseBegin, eraseEnd);
    const auto writeSample = [&](uint64_t sampleTick) {
        const double fraction =
            tick1 == tick0
                ? 1.0
                : std::clamp((double(sampleTick) - double(tick0)) / (double(tick1) - double(tick0)),
                             0.0, 1.0);
        m_points[sampleTick] = std::clamp(value0 + qRound(fraction * double(value1 - value0)),
                                          minimumValue(), maximumValue());
    };
    writeSample(low);
    uint64_t tick = low;
    while (tick < high) {
        const uint64_t next = nextSampleTick(tick, sampling);
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

uint64_t PitchBendGraph::normalCellTicksAt(uint64_t tick) const
{
    if (!m_songView)
        return 1;
    const uint64_t span = std::max<uint64_t>(1, m_endTick - m_startTick);
    const double pixelsPerTick = double(canvasRect().width() - 1) / double(span);
    return std::max<uint64_t>(1, m_songView->gridTicksAtScale(tick, pixelsPerTick));
}

uint64_t PitchBendGraph::samplingCellTicksAt(uint64_t tick, Sampling sampling) const
{
    return sampling == Sampling::Fine ? (m_songView ? m_songView->fineGridTicks() : 1)
                                      : normalCellTicksAt(tick);
}

uint64_t PitchBendGraph::nextSampleTick(uint64_t tick, Sampling sampling) const
{
    if (tick >= m_endTick)
        return m_endTick;
    const uint64_t cell = std::max<uint64_t>(1, samplingCellTicksAt(tick, sampling));
    uint64_t segmentEnd = m_endTick;
    const uint64_t anchor =
        sampling == Sampling::Fine ? 0 : (m_songView ? m_songView->gridSegAt(tick).start : 0);
    if (sampling == Sampling::Normal && m_songView)
        segmentEnd = std::min(m_endTick, m_songView->gridSegAt(tick).next);
    const uint64_t offset = tick > anchor ? tick - anchor : 0;
    const uint64_t quotient = offset / cell;
    if (quotient >= UINT64_MAX / cell)
        return segmentEnd;
    const uint64_t aligned = anchor + (quotient + 1) * cell;
    if (aligned > tick)
        return std::min(aligned, segmentEnd);
    if (tick == UINT64_MAX)
        return segmentEnd;
    return std::min(tick + 1, segmentEnd);
}

uint64_t PitchBendGraph::lastEditableTick(Sampling sampling) const
{
    if (m_endTick <= m_startTick + 1)
        return m_startTick;
    const uint64_t lastRaw = m_endTick - 1;
    const uint64_t cell = std::max<uint64_t>(1, samplingCellTicksAt(lastRaw, sampling));
    const uint64_t anchor =
        sampling == Sampling::Fine ? 0 : (m_songView ? m_songView->gridSegAt(lastRaw).start : 0);
    const uint64_t tick =
        lastRaw < anchor ? m_startTick : anchor + ((lastRaw - anchor) / cell) * cell;
    return std::clamp(tick, m_startTick, lastRaw);
}
uint64_t PitchBendGraph::tickAtFraction(double fraction, Sampling sampling) const
{
    if (fraction <= 0.0)
        return m_startTick;
    if (fraction >= 1.0)
        return lastEditableTick(sampling);
    const double raw = double(m_startTick) + fraction * double(m_endTick - m_startTick);
    const uint64_t rawTick =
        std::clamp<uint64_t>(uint64_t(std::max(0.0, std::round(raw))), m_startTick, m_endTick);
    const uint64_t cell = std::max<uint64_t>(1, samplingCellTicksAt(rawTick, sampling));
    const uint64_t anchor =
        sampling == Sampling::Fine ? 0 : (m_songView ? m_songView->gridSegAt(rawTick).start : 0);
    const double snapped =
        double(anchor) + std::round((raw - double(anchor)) / double(cell)) * cell;
    if (snapped <= double(m_startTick))
        return m_startTick;
    if (sampling == Sampling::Normal && m_songView) {
        const uint64_t segmentEnd = std::min(m_endTick, m_songView->gridSegAt(rawTick).next);
        if (snapped >= double(segmentEnd) && segmentEnd < m_endTick)
            return segmentEnd;
    }
    return std::min<uint64_t>(uint64_t(snapped), lastEditableTick(sampling));
}

uint64_t PitchBendGraph::tickAtX(qreal x, Sampling sampling) const
{
    const QRect graph = canvasRect();
    const double fraction =
        std::clamp((x - graph.left()) / double(std::max(1, graph.width() - 1)), 0.0, 1.0);
    return tickAtFraction(fraction, sampling);
}

int PitchBendGraph::xAtTick(uint64_t tick) const
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
    if (std::abs(clampedY - center) <= kZeroDetentPixels)
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

int PitchBendGraph::valueAtTick(uint64_t tick) const
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

QString PitchBendGraph::laneTitle() const
{
    return m_lane == Lane::PitchBend ? SongView::tr("Pitch bend (BEND)")
                                     : SongView::tr("Mod wheel (CC1)");
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
