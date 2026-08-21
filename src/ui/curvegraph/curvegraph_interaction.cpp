#include "curvegraph.hpp"

#include <QApplication>
#include <algorithm>
#include <type_traits>
#include <utility>

namespace songview {

bool CurveGraph::removeSelectedPoint()
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

void CurveGraph::cancelGesture()
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

bool CurveGraph::handleKeyPress(QKeyEvent *event)
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

bool CurveGraph::hasGesture() const
{
    return !std::holds_alternative<std::monostate>(m_gesture);
}

void CurveGraph::mousePressEvent(QMouseEvent *event)
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
        state.grabOffset = event->position() - QPointF(pointPosition(*hit));
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

void CurveGraph::updateGesture(const QPointF &position, Qt::KeyboardModifiers modifiers)
{
    if (std::holds_alternative<VertexDragState>(m_gesture))
        updateVertexDrag(position, modifiers);
    else
        updateStroke(position);
}

void CurveGraph::mouseMoveEvent(QMouseEvent *event)
{
    if (!hasGesture()) {
        event->ignore();
        return;
    }
    updateGesture(event->position(), event->modifiers());
    event->accept();
}

void CurveGraph::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton || !hasGesture()) {
        event->ignore();
        return;
    }
    updateGesture(event->position(), event->modifiers());
    finishGesture();
    event->accept();
}

void CurveGraph::wheelEvent(QWheelEvent *event)
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

void CurveGraph::keyPressEvent(QKeyEvent *event)
{
    if (!handleKeyPress(event))
        QWidget::keyPressEvent(event);
}

void CurveGraph::focusInEvent(QFocusEvent *event)
{
    QWidget::focusInEvent(event);
    update();
}

void CurveGraph::focusOutEvent(QFocusEvent *event)
{
    QWidget::focusOutEvent(event);
    update();
}

void CurveGraph::updateStroke(const QPointF &position)
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

void CurveGraph::updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers)
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
    const QPointF pointPosition = position - state->grabOffset;
    double y = yAt(pointPosition.y());
    double x = state->originalX;
    const bool endpoint = x == m_spec.xAxis.minimum || x == m_spec.xAxis.maximum;
    if (!endpoint && maximumInteriorX() >= minimumInteriorX()) {
        const Sampling sampling = modifiers & Qt::AltModifier ? Sampling::Fine : Sampling::Normal;
        x = std::clamp(xAtPosition(pointPosition.x(), sampling), minimumInteriorX(),
                       maximumInteriorX());
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

void CurveGraph::finishGesture()
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

void CurveGraph::replaceSegment(double x0, double y0, double x1, double y1, Sampling sampling)
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

bool CurveGraph::isLineGesture() const
{
    const auto *state = std::get_if<StrokeState>(&m_gesture);
    return state && state->mode == StrokeMode::AngledLine;
}

CurveGraph::Sampling CurveGraph::gestureSampling() const
{
    return isLineGesture() ? Sampling::Fine : Sampling::Normal;
}

} // namespace songview
