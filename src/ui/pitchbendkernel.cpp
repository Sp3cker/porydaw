#include "pitchbendkernel.h"

#include <QtGlobal>

#include <algorithm>
#include <cmath>

namespace songview {

PitchBendKernel::PitchBendKernel(Lane lane, const Grid &grid, PitchBendGeometry geometry,
                                 Tick startTick, Tick endTick, std::map<Tick, int> points,
                                 int endValue)
    : m_lane(lane)
    , m_grid(&grid)
    , m_geometry(geometry)
    , m_startTick(startTick)
    , m_endTick(endTick)
    , m_points(std::move(points))
    , m_wheelRemainder(0.0)
{
    m_endValue = std::clamp(endValue, minimumValue(), maximumValue());
    m_points[m_endTick] = m_endValue;
    m_strokeState.reset();
    m_vertexDragState.reset();
    m_selectedTick.reset();
    m_keyboardTick = m_startTick;
    m_liveValue = valueAtTick(m_keyboardTick);
}

void PitchBendKernel::setMetrics(const PitchBendGeometry &geometry)
{
    m_geometry = geometry;
}

void PitchBendKernel::setCurve(const std::map<Tick, int> &points, int endValue)
{
    m_points = points;
    m_endValue = std::clamp(endValue, minimumValue(), maximumValue());
    m_points[m_endTick] = m_endValue;
    if (m_selectedTick && !m_points.contains(*m_selectedTick))
        m_selectedTick.reset();
    cancelGesture();
    m_keyboardTick = m_startTick;
    m_liveValue = valueAtTick(m_keyboardTick);
}

void PitchBendKernel::resetCurve()
{
    m_points.clear();
    m_points[m_startTick] = defaultValue();
    m_points[m_endTick] = m_endValue;
    m_selectedTick.reset();
    cancelGesture();
    m_keyboardTick = m_startTick;
    m_liveValue = defaultValue();
}

int PitchBendKernel::minimumValue() const
{
    return m_lane == Lane::PitchBend ? -8192 : 0;
}

int PitchBendKernel::maximumValue() const
{
    return m_lane == Lane::PitchBend ? 8191 : 127;
}

int PitchBendKernel::defaultValue() const
{
    return 0;
}

bool PitchBendKernel::setSelectedTick(std::optional<Tick> tick)
{
    if (tick && !m_points.contains(*tick))
        tick.reset();
    if (m_selectedTick == tick)
        return false;
    m_selectedTick = tick;
    return true;
}

bool PitchBendKernel::removeSelectedVertex()
{
    if (!m_selectedTick || *m_selectedTick == m_startTick || *m_selectedTick == m_endTick)
        return false;
    if (m_points.erase(*m_selectedTick) == 0)
        return false;
    setSelectedTick(std::nullopt);
    m_liveValue = valueAtTick(m_keyboardTick);
    return true;
}

void PitchBendKernel::setKeyboardFraction(double fraction)
{
    m_keyboardTick = tickAtFraction(fraction, Sampling::Normal);
    m_liveValue = valueAtTick(m_keyboardTick);
}

std::optional<std::pair<Tick, int>> PitchBendKernel::hitTest(const QPointF &position) const
{
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

QPoint PitchBendKernel::vertexPosition(Tick tick, int value) const
{
    return {xAtTick(tick), yAtValue(value)};
}

int PitchBendKernel::xAtTick(Tick tick) const
{
    const QRect graph = m_geometry.canvas;
    const double fraction = m_endTick > m_startTick && tick >= m_startTick
                                ? double(tick - m_startTick) / double(m_endTick - m_startTick)
                                : 0.0;
    return graph.left() + qRound(std::clamp(fraction, 0.0, 1.0) * (graph.width() - 1));
}

int PitchBendKernel::yAtValue(int value) const
{
    const QRect graph = m_geometry.canvas;
    if (m_lane == Lane::ModWheel)
        return graph.bottom() - qRound(double(std::clamp(value, 0, 127)) * graph.height() / 127.0);
    const int center = graph.center().y();
    if (value >= 0)
        return center - qRound(double(value) * double(center - graph.top()) / 8191.0);
    return center + qRound(double(-value) * double(graph.bottom() - center) / 8192.0);
}

int PitchBendKernel::valueAtY(qreal y) const
{
    const QRect graph = m_geometry.canvas;
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

int PitchBendKernel::valueAtTick(Tick tick) const
{
    const auto it = m_points.upper_bound(tick);
    if (it == m_points.begin())
        return defaultValue();
    return std::prev(it)->second;
}

Tick PitchBendKernel::nextSnapTickAfter(Tick tick) const
{
    if (tick >= m_endTick)
        return m_endTick;
    return std::min(m_endTick, m_grid->nextSnapTickAfter(tick));
}

Tick PitchBendKernel::segmentStartAt(Tick tick) const
{
    return m_grid->segmentAt(tick).start;
}

uint32_t PitchBendKernel::fineGridTicks() const
{
    return m_grid->fineGridTicks();
}

void PitchBendKernel::beginStroke(const QPointF &position, bool lineGesture)
{
    m_selectedTick.reset();
    m_strokeState.emplace();
    auto &state = *m_strokeState;
    state.mode = lineGesture ? StrokeMode::AngledLine : StrokeMode::Freehand;
    if (isLineGesture())
        state.snapshot = m_points;
    state.previousTick = tickAtX(position.x(), gestureSampling());
    state.previousValue = valueAtY(position.y());
    state.anchorTick = state.previousTick;
    state.anchorValue = state.previousValue;
    replaceSegment(state.previousTick, state.previousValue, state.previousTick, state.previousValue,
                   gestureSampling());
    m_keyboardTick = state.previousTick;
    m_liveValue = state.previousValue;
}

bool PitchBendKernel::beginVertexDrag(Tick tick)
{
    const auto it = m_points.find(tick);
    if (it == m_points.end())
        return false;
    m_selectedTick = tick;
    m_vertexDragState.emplace();
    auto &state = *m_vertexDragState;
    state.snapshot = m_points;
    state.originalTick = tick;
    m_keyboardTick = tick;
    m_liveValue = it->second;
    return true;
}

bool PitchBendKernel::updateStroke(const QPointF &position)
{
    if (!m_strokeState)
        return false;
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
    return true;
}

bool PitchBendKernel::updateVertexDrag(const QPointF &position, bool fine)
{
    if (!m_vertexDragState)
        return false;
    auto &state = *m_vertexDragState;
    m_points = state.snapshot;
    const int value = valueAtY(position.y());
    Tick tick = state.originalTick;
    const bool endpoint = tick == m_startTick || tick == m_endTick;
    if (!endpoint && m_endTick > m_startTick + 1) {
        const Sampling sampling = fine ? Sampling::Fine : Sampling::Normal;
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
    return true;
}

bool PitchBendKernel::updateGestureAt(const QPointF &position, bool fine)
{
    if (m_vertexDragState)
        return updateVertexDrag(position, fine);
    if (m_strokeState)
        return updateStroke(position);
    return false;
}

void PitchBendKernel::endGesture()
{
    m_strokeState.reset();
    m_vertexDragState.reset();
}

void PitchBendKernel::cancelGesture()
{
    m_strokeState.reset();
    m_vertexDragState.reset();
}

std::optional<PitchBendKernel::LinePreview> PitchBendKernel::linePreview() const
{
    if (!m_strokeState || !isLineGesture())
        return std::nullopt;
    const StrokeState &state = *m_strokeState;
    return LinePreview{state.anchorTick, state.anchorValue, state.previousTick,
                       state.previousValue};
}

int PitchBendKernel::accumulateWheel(double units)
{
    m_wheelRemainder += units;
    const int steps = int(m_wheelRemainder / 120.0);
    if (steps != 0)
        m_wheelRemainder -= double(steps) * 120.0;
    return steps;
}

bool PitchBendKernel::isLineGesture() const
{
    return m_strokeState && m_strokeState->mode == StrokeMode::AngledLine;
}

PitchBendKernel::Sampling PitchBendKernel::gestureSampling() const
{
    return isLineGesture() ? Sampling::Fine : Sampling::Normal;
}

Tick PitchBendKernel::nextSampleTick(Tick tick, Sampling sampling) const
{
    if (tick >= m_endTick)
        return m_endTick;
    return std::min(m_endTick, m_grid->nextSnapTickAfter(tick, sampling == Sampling::Fine));
}

Tick PitchBendKernel::lastEditableTick(Sampling sampling) const
{
    if (m_endTick <= m_startTick + 1)
        return m_startTick;
    const Tick lastRaw = m_endTick - 1;
    const Tick tick = m_grid->snapTickDown(double(lastRaw), sampling == Sampling::Fine);
    return std::clamp(tick, m_startTick, lastRaw);
}

Tick PitchBendKernel::tickAtFraction(double fraction, Sampling sampling) const
{
    if (fraction <= 0.0)
        return m_startTick;
    if (fraction >= 1.0)
        return lastEditableTick(sampling);
    const double raw = double(m_startTick) + fraction * double(m_endTick - m_startTick);
    const Tick snapped = m_grid->snapTick(raw, sampling == Sampling::Fine);
    if (snapped <= m_startTick)
        return m_startTick;
    return std::min(snapped, lastEditableTick(sampling));
}

Tick PitchBendKernel::tickAtX(qreal x, Sampling sampling) const
{
    const QRect graph = m_geometry.canvas;
    const double fraction =
        std::clamp((x - graph.left()) / double(std::max(1, graph.width() - 1)), 0.0, 1.0);
    return tickAtFraction(fraction, sampling);
}

void PitchBendKernel::replaceSegment(Tick tick0, int value0, Tick tick1, int value1,
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

} // namespace songview
