#include "curvegraph.hpp"

#include "ui/layout.h"
#include "ui/typography.h"

#include <QApplication>
#include <QCoreApplication>
#include <QFontMetrics>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <utility>

namespace songview {

CurveGeometry CurveGeometry::resolve(const QFont &font, qreal dpr)
{
    CurveGeometry geometry;
    geometry.physicalPixel = qreal(layout::singlePixel()) / std::max(dpr, qreal(1.0));
    geometry.labelGap = layout::space(layout::Space::One) + layout::singlePixel();
    geometry.labelHeight = QFontMetrics(typography::caption(font)).lineSpacing();
    geometry.axisGutter = layout::fontPx(4.0) + geometry.labelGap;
    geometry.topBandHeight = geometry.labelHeight + 2 * layout::space(layout::Space::Half);
    geometry.bottomBandHeight = geometry.labelHeight + geometry.labelGap;
    geometry.rightInset = 2 * geometry.labelGap;
    geometry.curveWidth = 2.0 * geometry.physicalPixel;
    geometry.nodeRadius = layout::space(layout::Space::Half) + layout::singlePixel();
    geometry.nodeOutlineWidth = 2.0 * geometry.physicalPixel;
    geometry.ringRadius = layout::fontPxF(1.0 / 2.0);
    geometry.ringOutlineWidth = 2.0 * geometry.physicalPixel;
    geometry.hitRadius = 8.0 * std::max(dpr, qreal(1.0));
    geometry.previewRadius = geometry.nodeRadius;
    return geometry;
}

CurveGraph::CurveGraph(CurveSpec spec, QWidget *parent)
    : QWidget(parent)
    , m_spec(std::move(spec))
    , m_keyboardX(m_spec.xAxis.minimum)
    , m_liveValue(m_spec.defaultY)
{
    setFocusPolicy(Qt::StrongFocus);
    setAccessibleName(QCoreApplication::translate("CurveGraph", "Envelope curve"));
    setMouseTracking(true);
    setCursor(Qt::ArrowCursor);
}

void CurveGraph::setSpec(CurveSpec spec)
{
    cancelGesture();
    m_spec = std::move(spec);
    materializeEndpoints();
    m_keyboardX = std::clamp(m_keyboardX, m_spec.xAxis.minimum, m_spec.xAxis.maximum);
    m_liveValue = valueAtX(m_keyboardX);
    if (m_selectedX && std::none_of(m_points.begin(), m_points.end(),
                                    [this](const auto &point) { return point.x == *m_selectedX; }))
        m_selectedX.reset();
    if (m_hoverX) {
        m_hoverX.reset();
        setCursor(Qt::ArrowCursor);
    }
    update();
}

void CurveGraph::setPoints(std::vector<CurvePoint> points)
{
    cancelGesture();
    m_points = std::move(points);
    materializeEndpoints();
    m_selectedX.reset();
    if (m_hoverX) {
        m_hoverX.reset();
        setCursor(Qt::ArrowCursor);
    }
    m_keyboardX = m_spec.xAxis.minimum;
    m_liveValue = valueAtX(m_keyboardX);
    update();
}

const std::vector<CurvePoint> &CurveGraph::points() const
{
    return m_points;
}

void CurveGraph::resetCurve()
{
    cancelGesture();
    const double endValue = endpointValue();
    m_points.clear();
    insertOrReplace(m_spec.xAxis.minimum, m_spec.defaultY);
    insertOrReplace(m_spec.xAxis.maximum, endValue);
    m_keyboardX = m_spec.xAxis.minimum;
    m_liveValue = m_spec.defaultY;
    if (m_hoverX) {
        m_hoverX.reset();
        setCursor(Qt::ArrowCursor);
    }
    if (m_callbacks.previewChanged)
        m_callbacks.previewChanged();
    setFocus(Qt::MouseFocusReason);
    update();
}

std::optional<double> CurveGraph::selectedX() const
{
    return m_selectedX;
}

void CurveGraph::setSelectedX(std::optional<double> x)
{
    if (x && std::none_of(m_points.begin(), m_points.end(),
                          [x](const auto &point) { return point.x == *x; }))
        x.reset();
    if (m_selectedX == x)
        return;
    m_selectedX = x;
    update();
}

std::optional<CurvePoint> CurveGraph::hitTest(const QPointF &position) const
{
    const qreal radius = CurveGeometry::resolve(font(), devicePixelRatioF()).hitRadius;
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

QPoint CurveGraph::pointPosition(const CurvePoint &point) const
{
    return {pixelX(point.x), pixelY(point.y)};
}

void CurveGraph::setKeyboardFraction(double fraction)
{
    m_keyboardX = tickAtFraction(fraction, Sampling::Normal);
    m_liveValue = valueAtX(m_keyboardX);
    update();
}

void CurveGraph::setCallbacks(Callbacks callbacks)
{
    m_callbacks = std::move(callbacks);
}

QRect CurveGraph::canvasRect() const
{
    return m_spec.canvasRect;
}

double CurveGraph::liveValue() const
{
    return m_liveValue;
}

void CurveGraph::materializeEndpoints()
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

bool CurveGraph::isLinearSegment(double x0, double x1) const
{
    return m_spec.segments.allLinear || (m_spec.segments.linearSampleSpacing > 0.0 && x1 > x0 &&
                                         x1 - x0 == m_spec.segments.linearSampleSpacing);
}

double CurveGraph::tickAtFraction(double fraction, Sampling sampling) const
{
    if (fraction <= 0.0)
        return m_spec.xAxis.minimum;
    if (fraction >= 1.0)
        return lastEditableX(sampling);
    const double raw =
        m_spec.xAxis.minimum + fraction * (m_spec.xAxis.maximum - m_spec.xAxis.minimum);
    return snapX(raw, sampling);
}

double CurveGraph::xAtPosition(qreal x, Sampling sampling) const
{
    const double raw = valueAtPixel(x, m_spec.xAxis, false);
    if (raw <= m_spec.xAxis.minimum)
        return m_spec.xAxis.minimum;
    if (raw >= m_spec.xAxis.maximum)
        return lastEditableX(sampling);
    return snapX(raw, sampling);
}

double CurveGraph::yAt(qreal y) const
{
    return valueAtPixel(y, m_spec.yAxis, true);
}

double CurveGraph::endpointValue() const
{
    if (!m_points.empty() && m_points.back().x == m_spec.xAxis.maximum)
        return m_points.back().y;
    return std::clamp(m_spec.defaultY, m_spec.yAxis.minimum, m_spec.yAxis.maximum);
}

double CurveGraph::valueAtX(double x) const
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

double CurveGraph::minimumInteriorX() const
{
    return m_spec.xAxis.minimum + m_spec.sampling.endpointInset;
}

double CurveGraph::maximumInteriorX() const
{
    return m_spec.xAxis.maximum - m_spec.sampling.endpointInset;
}

double CurveGraph::snapX(double x, Sampling sampling) const
{
    const double clamped = std::clamp(x, m_spec.xAxis.minimum, m_spec.xAxis.maximum);
    return m_spec.sampling.snap ? std::clamp(m_spec.sampling.snap(clamped, sampling),
                                             m_spec.xAxis.minimum, m_spec.xAxis.maximum)
                                : clamped;
}

double CurveGraph::nextSampleX(double x, Sampling sampling) const
{
    if (m_spec.sampling.nextSample)
        return std::min(m_spec.xAxis.maximum, m_spec.sampling.nextSample(x, sampling));
    return std::min(m_spec.xAxis.maximum, x + std::max(1e-9, m_spec.sampling.interiorStep));
}

double CurveGraph::lastEditableX(Sampling sampling) const
{
    if (m_spec.sampling.lastEditable)
        return std::clamp(m_spec.sampling.lastEditable(sampling), m_spec.xAxis.minimum,
                          m_spec.xAxis.maximum);
    return std::max(m_spec.xAxis.minimum, m_spec.xAxis.maximum - m_spec.sampling.endpointInset);
}

double CurveGraph::valueAtPixel(qreal pixel, const CurveAxisSpec &axis, bool vertical) const
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

int CurveGraph::pixelAtValue(double value, const CurveAxisSpec &axis, bool vertical) const
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

double CurveGraph::quantizeAxisValue(double value, const CurveAxisSpec &axis) const
{
    const double clamped = std::clamp(value, axis.minimum, axis.maximum);
    if (axis.quantizationStep <= 0.0 || clamped == axis.minimum || clamped == axis.maximum)
        return clamped;
    return std::clamp(double(qRound(clamped / axis.quantizationStep)) * axis.quantizationStep,
                      axis.minimum, axis.maximum);
}

double CurveGraph::bipolarFractionAtValue(double value, const CurveAxisSpec &axis) const
{
    const double clamped = std::clamp(value, axis.minimum, axis.maximum);
    if (clamped >= 0.0)
        return axis.maximum > 0.0 ? clamped / axis.maximum : 0.0;
    return axis.minimum < 0.0 ? clamped / -axis.minimum : 0.0;
}

double CurveGraph::bipolarValueAtFraction(double fraction, const CurveAxisSpec &axis) const
{
    const double clamped = std::clamp(fraction, -1.0, 1.0);
    const double value = clamped >= 0.0 ? clamped * axis.maximum : -clamped * axis.minimum;
    return quantizeAxisValue(value, axis);
}

int CurveGraph::pixelX(double x) const
{
    return pixelAtValue(x, m_spec.xAxis, false);
}

int CurveGraph::pixelY(double y) const
{
    return pixelAtValue(y, m_spec.yAxis, true);
}

void CurveGraph::insertOrReplace(double x, double y)
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

void CurveGraph::sortPoints()
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
