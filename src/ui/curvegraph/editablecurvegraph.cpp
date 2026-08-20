#include "editablecurvegraph.hpp"

#include <QApplication>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <type_traits>
#include <utility>

namespace songview {

EditableCurveGraph::EditableCurveGraph(CurveSpec spec, QWidget *parent)
    : QWidget(parent)
    , m_spec(std::move(spec))
    , m_keyboardX(m_spec.xAxis.minimum)
    , m_liveValue(m_spec.defaultY)
{
    setFocusPolicy(Qt::StrongFocus);
    setMouseTracking(true);
    setCursor(Qt::ArrowCursor);
}
void EditableCurveGraph::setSpec(CurveSpec spec)
{
    cancelGesture();
    m_spec = std::move(spec);
    materializeEndpoints();
    m_keyboardX = std::clamp(m_keyboardX, m_spec.xAxis.minimum, m_spec.xAxis.maximum);
    m_liveValue = valueAtX(m_keyboardX);
    if (m_selectedX && std::none_of(m_points.begin(), m_points.end(),
                                    [this](const auto &point) { return point.x == *m_selectedX; }))
        m_selectedX.reset();
    update();
}
void EditableCurveGraph::setPoints(std::vector<CurvePoint> points)
{
    cancelGesture();
    m_points = std::move(points);
    materializeEndpoints();
    m_selectedX.reset();
    m_keyboardX = m_spec.xAxis.minimum;
    m_liveValue = valueAtX(m_keyboardX);
    update();
}
const std::vector<CurvePoint> &EditableCurveGraph::points() const
{
    return m_points;
}
void EditableCurveGraph::resetCurve()
{
    cancelGesture();
    const double endValue = endpointValue();
    m_points.clear();
    insertOrReplace(m_spec.xAxis.minimum, m_spec.defaultY);
    insertOrReplace(m_spec.xAxis.maximum, endValue);
    m_keyboardX = m_spec.xAxis.minimum;
    m_liveValue = m_spec.defaultY;
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
    setFocus(Qt::MouseFocusReason);
    update();
}
std::optional<double> EditableCurveGraph::selectedX() const
{
    return m_selectedX;
}
void EditableCurveGraph::setSelectedX(std::optional<double> x)
{
    if (x && std::none_of(m_points.begin(), m_points.end(),
                          [x](const auto &point) { return point.x == *x; }))
        x.reset();
    if (m_selectedX == x)
        return;
    m_selectedX = x;
    update();
}
std::optional<CurvePoint> EditableCurveGraph::hitTest(const QPointF &position) const
{
    const qreal radius = kNodeHitRadius * std::max<qreal>(devicePixelRatioF(), 1.0);
    const qreal radiusSquared = radius * radius;
    qreal nearestDistanceSquared = radiusSquared;
    std::optional<CurvePoint> nearest;
    for (const CurvePoint &point : m_points) {
        const QPoint center = pointPosition(point);
        const qreal dx = position.x() - center.x();
        const qreal dy = position.y() - center.y();
        const qreal distanceSquared = dx * dx + dy * dy;
        if (distanceSquared > radiusSquared)
            continue;
        if (!nearest || distanceSquared < nearestDistanceSquared ||
            (qFuzzyCompare(distanceSquared, nearestDistanceSquared) && point.x < nearest->x)) {
            nearestDistanceSquared = distanceSquared;
            nearest = point;
        }
    }
    return nearest;
}
bool EditableCurveGraph::removeSelectedPoint()
{
    if (!m_selectedX || *m_selectedX == m_spec.xAxis.minimum ||
        *m_selectedX == m_spec.xAxis.maximum)
        return false;
    const auto it = std::find_if(m_points.begin(), m_points.end(),
                                 [this](const auto &point) { return point.x == *m_selectedX; });
    if (it == m_points.end())
        return false;
    m_points.erase(it);
    m_selectedX.reset();
    m_liveValue = valueAtX(m_keyboardX);
    update();
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
    if (m_callbacks.commitRequested)
        m_callbacks.commitRequested();
    return true;
}
QPoint EditableCurveGraph::pointPosition(const CurvePoint &point) const
{
    return {pixelX(point.x), pixelY(point.y)};
}
void EditableCurveGraph::setKeyboardFraction(double fraction)
{
    m_keyboardX = tickAtFraction(fraction, Sampling::Normal);
    m_liveValue = valueAtX(m_keyboardX);
    update();
}
void EditableCurveGraph::cancelGesture()
{
    std::visit(
        [this](const auto &state) {
            using State = std::decay_t<decltype(state)>;
            if constexpr (!std::is_same_v<State, std::monostate>)
                m_points = state.snapshot;
        },
        m_gesture);
    m_gesture = std::monostate{};
    m_liveValue = valueAtX(m_keyboardX);
    update();
}
bool EditableCurveGraph::handleKeyPress(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        cancelGesture();
        if (m_callbacks.cancelRequested)
            m_callbacks.cancelRequested();
        event->accept();
        return true;
    }
    if ((event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) && m_selectedX) {
        removeSelectedPoint();
        event->accept();
        return true;
    }
    if (m_spec.matchesAuditionKey && m_spec.matchesAuditionKey(*event)) {
        if (!event->isAutoRepeat() && m_callbacks.auditionRequested)
            m_callbacks.auditionRequested();
        event->accept();
        return true;
    }
    if (event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter) {
        if (m_callbacks.commitRequested)
            m_callbacks.commitRequested();
        event->accept();
        return true;
    }
    event->ignore();
    return false;
}
void EditableCurveGraph::setCallbacks(Callbacks callbacks)
{
    m_callbacks = std::move(callbacks);
}
QRect EditableCurveGraph::canvasRect() const
{
    return m_spec.canvasRect;
}
bool EditableCurveGraph::hasGesture() const
{
    return !std::holds_alternative<std::monostate>(m_gesture);
}
double EditableCurveGraph::liveValue() const
{
    return m_liveValue;
}
void EditableCurveGraph::mousePressEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton || !canvasRect().contains(event->position().toPoint())) {
        event->ignore();
        return;
    }
    if (const auto hit = hitTest(event->position())) {
        setFocus(Qt::MouseFocusReason);
        setSelectedX(hit->x);
        auto &state = m_gesture.emplace<VertexDragState>();
        state.snapshot = m_points;
        state.pressPosition = event->position();
        state.originalX = hit->x;
        m_keyboardX = hit->x;
        m_liveValue = hit->y;
        update();
        event->accept();
        return;
    }
    setSelectedX(std::nullopt);
    setFocus(Qt::MouseFocusReason);
    auto &state = m_gesture.emplace<StrokeState>();
    state.mode = (event->modifiers() & (Qt::ShiftModifier | Qt::AltModifier))
                     ? StrokeMode::AngledLine
                     : StrokeMode::Freehand;
    state.snapshot = m_points;
    const Sampling sampling = gestureSampling();
    state.previousX = xAtPosition(event->position().x(), sampling);
    state.previousY = yAt(event->position().y());
    state.anchorX = state.previousX;
    state.anchorY = state.previousY;
    replaceSegment(state.previousX, state.previousY, state.previousX, state.previousY, sampling);
    m_keyboardX = state.previousX;
    m_liveValue = state.previousY;
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
    update();
    event->accept();
}
void EditableCurveGraph::updateGesture(const QPointF &position, Qt::KeyboardModifiers modifiers)
{
    if (std::holds_alternative<VertexDragState>(m_gesture))
        updateVertexDrag(position, modifiers);
    else
        updateStroke(position);
}
void EditableCurveGraph::mouseMoveEvent(QMouseEvent *event)
{
    if (!hasGesture()) {
        event->ignore();
        return;
    }
    updateGesture(event->position(), event->modifiers());
    event->accept();
}
void EditableCurveGraph::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton || !hasGesture()) {
        event->ignore();
        return;
    }
    updateGesture(event->position(), event->modifiers());
    finishGesture();
    event->accept();
}
void EditableCurveGraph::wheelEvent(QWheelEvent *event)
{
    if (!m_callbacks.wheelChanged || !canvasRect().contains(event->position().toPoint())) {
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
        m_callbacks.wheelChanged(steps);
    }
    event->accept();
}
void EditableCurveGraph::keyPressEvent(QKeyEvent *event)
{
    if (!handleKeyPress(event))
        QWidget::keyPressEvent(event);
}
void EditableCurveGraph::focusInEvent(QFocusEvent *event)
{
    QWidget::focusInEvent(event);
    update();
}
void EditableCurveGraph::focusOutEvent(QFocusEvent *event)
{
    QWidget::focusOutEvent(event);
    update();
}
void EditableCurveGraph::updateStroke(const QPointF &position)
{
    auto *state = std::get_if<StrokeState>(&m_gesture);
    if (!state)
        return;
    const Sampling sampling = gestureSampling();
    const double x = xAtPosition(position.x(), sampling);
    const double y = yAt(position.y());
    if (isLineGesture()) {
        m_points = state->snapshot;
        replaceSegment(state->anchorX, state->anchorY, x, y, sampling);
    } else {
        replaceSegment(state->previousX, state->previousY, x, y, sampling);
    }
    state->previousX = x;
    state->previousY = y;
    m_keyboardX = x;
    m_liveValue = y;
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
    update();
}
void EditableCurveGraph::updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers)
{
    auto *state = std::get_if<VertexDragState>(&m_gesture);
    if (!state)
        return;
    if (!state->hasMoved) {
        if ((position - state->pressPosition).manhattanLength() <=
            QApplication::startDragDistance())
            return;
        state->hasMoved = true;
    }
    m_points = state->snapshot;
    double y = yAt(position.y());
    double x = state->originalX;
    const bool endpoint = x == m_spec.xAxis.minimum || x == m_spec.xAxis.maximum;
    if (!endpoint && maximumInteriorX() >= minimumInteriorX()) {
        const Sampling sampling = modifiers & Qt::AltModifier ? Sampling::Fine : Sampling::Normal;
        x = std::clamp(xAtPosition(position.x(), sampling), minimumInteriorX(), maximumInteriorX());
        if (x != state->originalX && std::any_of(m_points.begin(), m_points.end(),
                                                 [x](const auto &point) { return point.x == x; })) {
            const double step = std::max(1e-9, m_spec.sampling.interiorStep);
            const int direction = x > state->originalX ? 1 : -1;
            bool found = false;
            double candidate = x;
            while (true) {
                candidate += direction * step;
                if (candidate < minimumInteriorX() || candidate > maximumInteriorX())
                    break;
                if (std::none_of(m_points.begin(), m_points.end(),
                                 [candidate](const auto &point) { return point.x == candidate; })) {
                    x = candidate;
                    found = true;
                    break;
                }
            }
            if (!found)
                x = state->originalX;
        }
    }
    if (x != state->originalX)
        m_points.erase(std::remove_if(m_points.begin(), m_points.end(),
                                      [original = state->originalX](const auto &point) {
                                          return point.x == original;
                                      }),
                       m_points.end());
    const double storedValue = state->originalX == m_spec.xAxis.maximum ? endpointValue() : y;
    insertOrReplace(x, storedValue);
    m_selectedX = x;
    m_keyboardX = x;
    m_liveValue = valueAtX(x);
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
    update();
}
void EditableCurveGraph::finishGesture()
{
    const auto *vertex = std::get_if<VertexDragState>(&m_gesture);
    const bool deleteVertex = vertex && !vertex->hasMoved &&
                              vertex->originalX != m_spec.xAxis.minimum &&
                              vertex->originalX != m_spec.xAxis.maximum;
    m_gesture = std::monostate{};
    if (deleteVertex && removeSelectedPoint())
        return;
    if (m_callbacks.commitRequested)
        m_callbacks.commitRequested();
}
void EditableCurveGraph::replaceSegment(double x0, double y0, double x1, double y1,
                                        Sampling sampling)
{
    const double endValue = endpointValue();
    const double low = std::min(x0, x1);
    const double high = std::max(x0, x1);
    m_points.erase(std::remove_if(m_points.begin(), m_points.end(),
                                  [low, high](const auto &point) {
                                      return point.x >= low && point.x <= high;
                                  }),
                   m_points.end());
    const auto writeSample = [&](double sampleX) {
        const double fraction = x1 == x0 ? 1.0 : std::clamp((sampleX - x0) / (x1 - x0), 0.0, 1.0);
        insertOrReplace(sampleX, std::clamp(y0 + fraction * (y1 - y0), m_spec.yAxis.minimum,
                                            m_spec.yAxis.maximum));
    };
    writeSample(low);
    double x = low;
    while (x < high) {
        const double next = nextSampleX(x, sampling);
        if (next <= x || next >= high)
            break;
        writeSample(next);
        x = next;
    }
    if (high != low)
        writeSample(high);
    insertOrReplace(m_spec.xAxis.maximum, endValue);
}
bool EditableCurveGraph::isLineGesture() const
{
    const auto *state = std::get_if<StrokeState>(&m_gesture);
    return state && state->mode == StrokeMode::AngledLine;
}
void EditableCurveGraph::materializeEndpoints()
{
    sortPoints();
    const double defaultValue =
        std::clamp(m_spec.defaultY, m_spec.yAxis.minimum, m_spec.yAxis.maximum);
    const auto hasPointAt = [this](double x) {
        return std::any_of(m_points.begin(), m_points.end(),
                           [x](const auto &point) { return point.x == x; });
    };
    if (!hasPointAt(m_spec.xAxis.minimum))
        m_points.insert(m_points.begin(), {m_spec.xAxis.minimum, defaultValue});
    else if (m_spec.lockStartEndpointY)
        m_points.front().y = defaultValue;
    if (!hasPointAt(m_spec.xAxis.maximum))
        m_points.push_back({m_spec.xAxis.maximum, defaultValue});
}
bool EditableCurveGraph::isLinearSegment(double x0, double x1) const
{
    return m_spec.segments.allLinear || (m_spec.segments.linearSampleSpacing > 0.0 && x1 > x0 &&
                                         x1 - x0 == m_spec.segments.linearSampleSpacing);
}
EditableCurveGraph::Sampling EditableCurveGraph::gestureSampling() const
{
    return isLineGesture() ? Sampling::Fine : Sampling::Normal;
}
double EditableCurveGraph::tickAtFraction(double fraction, Sampling sampling) const
{
    if (fraction <= 0.0)
        return m_spec.xAxis.minimum;
    if (fraction >= 1.0)
        return lastEditableX(sampling);
    const double raw =
        m_spec.xAxis.minimum + fraction * (m_spec.xAxis.maximum - m_spec.xAxis.minimum);
    return snapX(raw, sampling);
}
double EditableCurveGraph::xAtPosition(qreal x, Sampling sampling) const
{
    const double raw = valueAtPixel(x, m_spec.xAxis, false);
    if (raw <= m_spec.xAxis.minimum)
        return m_spec.xAxis.minimum;
    if (raw >= m_spec.xAxis.maximum)
        return lastEditableX(sampling);
    return snapX(raw, sampling);
}
double EditableCurveGraph::yAt(qreal y) const
{
    return valueAtPixel(y, m_spec.yAxis, true);
}
double EditableCurveGraph::endpointValue() const
{
    if (!m_points.empty() && m_points.back().x == m_spec.xAxis.maximum)
        return m_points.back().y;
    return std::clamp(m_spec.defaultY, m_spec.yAxis.minimum, m_spec.yAxis.maximum);
}
double EditableCurveGraph::valueAtX(double x) const
{
    const auto it =
        std::upper_bound(m_points.begin(), m_points.end(), x,
                         [](double value, const auto &point) { return value < point.x; });
    if (it == m_points.begin())
        return m_spec.defaultY;
    const auto previous = std::prev(it);
    if (it == m_points.end() || !isLinearSegment(previous->x, it->x))
        return previous->y;
    const double fraction = (x - previous->x) / (it->x - previous->x);
    return previous->y + fraction * (it->y - previous->y);
}
double EditableCurveGraph::minimumInteriorX() const
{
    return m_spec.xAxis.minimum + m_spec.sampling.endpointInset;
}
double EditableCurveGraph::maximumInteriorX() const
{
    return m_spec.xAxis.maximum - m_spec.sampling.endpointInset;
}
double EditableCurveGraph::snapX(double x, Sampling sampling) const
{
    const double clamped = std::clamp(x, m_spec.xAxis.minimum, m_spec.xAxis.maximum);
    return m_spec.sampling.snap ? std::clamp(m_spec.sampling.snap(clamped, sampling),
                                             m_spec.xAxis.minimum, m_spec.xAxis.maximum)
                                : clamped;
}
double EditableCurveGraph::nextSampleX(double x, Sampling sampling) const
{
    if (m_spec.sampling.nextSample)
        return std::min(m_spec.xAxis.maximum, m_spec.sampling.nextSample(x, sampling));
    return std::min(m_spec.xAxis.maximum, x + std::max(1e-9, m_spec.sampling.interiorStep));
}
double EditableCurveGraph::lastEditableX(Sampling sampling) const
{
    if (m_spec.sampling.lastEditable)
        return std::clamp(m_spec.sampling.lastEditable(sampling), m_spec.xAxis.minimum,
                          m_spec.xAxis.maximum);
    return std::max(m_spec.xAxis.minimum, m_spec.xAxis.maximum - m_spec.sampling.endpointInset);
}
double EditableCurveGraph::valueAtPixel(qreal pixel, const CurveAxisSpec &axis, bool vertical) const
{
    const QRect graph = canvasRect();
    if (!vertical) {
        const qreal clamped = std::clamp(pixel, qreal(graph.left()), qreal(graph.right()));
        const double fraction = (clamped - graph.left()) / double(std::max(1, graph.width() - 1));
        return quantizeAxisValue(axis.minimum + fraction * (axis.maximum - axis.minimum), axis);
    }
    const qreal clamped = std::clamp(pixel, qreal(graph.top()), qreal(graph.bottom()));
    const qreal mapped = axis.quantizationStep > 0.0 ? qRound(clamped) : clamped;
    if (axis.mapping == CurveAxisMapping::BipolarCenter) {
        const qreal center = graph.center().y();
        if (std::abs(mapped - center) <= axis.zeroDetentPixels)
            return 0.0;
        const double fraction =
            mapped <= center
                ? (center - mapped) / double(std::max(1, graph.center().y() - graph.top()))
                : (center - mapped) / double(std::max(1, graph.bottom() - graph.center().y()));
        return bipolarValueAtFraction(fraction, axis);
    }
    const double fraction = (graph.bottom() - mapped) / double(std::max(1, graph.height()));
    return quantizeAxisValue(axis.minimum + fraction * (axis.maximum - axis.minimum), axis);
}
int EditableCurveGraph::pixelAtValue(double value, const CurveAxisSpec &axis, bool vertical) const
{
    const QRect graph = canvasRect();
    const double clamped = std::clamp(value, axis.minimum, axis.maximum);
    if (!vertical) {
        const double fraction = axis.maximum > axis.minimum
                                    ? (clamped - axis.minimum) / (axis.maximum - axis.minimum)
                                    : 0.0;
        return graph.left() + qRound(fraction * (graph.width() - 1));
    }
    if (axis.mapping == CurveAxisMapping::BipolarCenter) {
        const int center = graph.center().y();
        const double fraction = bipolarFractionAtValue(clamped, axis);
        if (fraction >= 0.0)
            return center - qRound(fraction * (center - graph.top()));
        return center + qRound(-fraction * (graph.bottom() - center));
    }
    const double fraction = axis.maximum > axis.minimum
                                ? (clamped - axis.minimum) / (axis.maximum - axis.minimum)
                                : 0.0;
    return graph.bottom() - qRound(fraction * graph.height());
}
double EditableCurveGraph::quantizeAxisValue(double value, const CurveAxisSpec &axis) const
{
    const double clamped = std::clamp(value, axis.minimum, axis.maximum);
    if (axis.quantizationStep <= 0.0 || clamped == axis.minimum || clamped == axis.maximum)
        return clamped;
    return std::clamp(double(qRound(clamped / axis.quantizationStep)) * axis.quantizationStep,
                      axis.minimum, axis.maximum);
}
double EditableCurveGraph::bipolarFractionAtValue(double value, const CurveAxisSpec &axis) const
{
    const double clamped = std::clamp(value, axis.minimum, axis.maximum);
    if (clamped >= 0.0)
        return axis.maximum > 0.0 ? clamped / axis.maximum : 0.0;
    return axis.minimum < 0.0 ? clamped / -axis.minimum : 0.0;
}
double EditableCurveGraph::bipolarValueAtFraction(double fraction, const CurveAxisSpec &axis) const
{
    const double clamped = std::clamp(fraction, -1.0, 1.0);
    const double value = clamped >= 0.0 ? clamped * axis.maximum : -clamped * axis.minimum;
    return quantizeAxisValue(value, axis);
}
int EditableCurveGraph::pixelX(double x) const
{
    return pixelAtValue(x, m_spec.xAxis, false);
}
int EditableCurveGraph::pixelY(double y) const
{
    return pixelAtValue(y, m_spec.yAxis, true);
}
void EditableCurveGraph::insertOrReplace(double x, double y)
{
    x = std::clamp(x, m_spec.xAxis.minimum, m_spec.xAxis.maximum);
    if (x == m_spec.xAxis.minimum && m_spec.lockStartEndpointY)
        y = m_spec.defaultY;
    y = std::clamp(y, m_spec.yAxis.minimum, m_spec.yAxis.maximum);
    const auto it = std::find_if(m_points.begin(), m_points.end(),
                                 [x](const auto &point) { return point.x == x; });
    if (it == m_points.end())
        m_points.push_back({x, y});
    else
        it->y = y;
    sortPoints();
}
void EditableCurveGraph::sortPoints()
{
    for (CurvePoint &point : m_points) {
        point.x = std::clamp(point.x, m_spec.xAxis.minimum, m_spec.xAxis.maximum);
        point.y = std::clamp(point.y, m_spec.yAxis.minimum, m_spec.yAxis.maximum);
    }
    std::sort(m_points.begin(), m_points.end(),
              [](const auto &lhs, const auto &rhs) { return lhs.x < rhs.x; });
    auto duplicate = std::unique(m_points.begin(), m_points.end(),
                                 [](const auto &lhs, const auto &rhs) { return lhs.x == rhs.x; });
    m_points.erase(duplicate, m_points.end());
}
} // namespace songview
