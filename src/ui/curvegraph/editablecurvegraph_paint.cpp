#include "editablecurvegraph.hpp"

#include "ui/typography.h"

#include <QPainter>
#include <algorithm>
#include <iterator>

namespace songview {

void EditableCurveGraph::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.fillRect(canvasRect(), m_spec.colors.background);
    painter.save();
    painter.setClipRect(canvasRect());
    paintGrid(painter);
    paintCurve(painter);
    painter.restore();
    paintAxes(painter);
    paintFocus(painter);
}

void EditableCurveGraph::paintGrid(QPainter &painter)
{
    painter.setPen(QPen(m_spec.colors.grid, 1));
    for (const double x : m_spec.gridLines) {
        if (x > m_spec.xAxis.minimum && x < m_spec.xAxis.maximum)
            painter.drawLine(pixelX(x), canvasRect().top(), pixelX(x), canvasRect().bottom());
    }
    if (m_spec.yAxis.minimum <= 0.0 && m_spec.yAxis.maximum >= 0.0) {
        painter.setPen(QPen(m_spec.colors.separator, 1, Qt::DashLine));
        painter.drawLine(canvasRect().left(), pixelY(0.0), canvasRect().right(), pixelY(0.0));
    }
}

void EditableCurveGraph::paintCurve(QPainter &painter)
{
    painter.save();
    painter.setClipRect(canvasRect(), Qt::IntersectClip);
    painter.setPen(QPen(m_spec.colors.curve, 2));
    for (auto it = m_points.cbegin(); it != m_points.cend(); ++it) {
        const auto next = std::next(it);
        const int x0 = pixelX(it->x);
        const int x1 = next == m_points.cend() ? canvasRect().right() : pixelX(next->x);
        if (next != m_points.cend() && isLinearSegment(it->x, next->x)) {
            painter.drawLine(x0, pixelY(it->y), x1, pixelY(next->y));
        } else {
            painter.drawLine(x0, pixelY(it->y), x1, pixelY(it->y));
            if (next != m_points.cend())
                painter.drawLine(x1, pixelY(it->y), x1, pixelY(next->y));
        }
    }
    const bool antialiasing = painter.testRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::Antialiasing, true);
    for (const CurvePoint &point : m_points) {
        const QPointF center(pointPosition(point));
        const bool selected = m_selectedX && *m_selectedX == point.x;
        if (selected) {
            painter.setPen(QPen(m_spec.colors.focus, 1.5));
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(center, kSelectedNodeRingRadius, kSelectedNodeRingRadius);
            painter.setPen(Qt::NoPen);
            painter.setBrush(m_spec.colors.curve);
            painter.drawEllipse(center, kNodePaintRadius, kNodePaintRadius);
            continue;
        }
        painter.setPen(Qt::NoPen);
        painter.setBrush(point.x == m_spec.xAxis.minimum || point.x == m_spec.xAxis.maximum
                             ? m_spec.colors.endpoint
                             : m_spec.colors.curve);
        const qreal radius = point.x == m_spec.xAxis.minimum || point.x == m_spec.xAxis.maximum
                                 ? std::max(1, kNodePaintRadius - 1)
                                 : kNodePaintRadius;
        painter.drawEllipse(center, radius, radius);
    }
    painter.setRenderHint(QPainter::Antialiasing, antialiasing);
    painter.setPen(QPen(m_spec.colors.previewOutline, 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(pointPosition({m_keyboardX, m_liveValue}), 3, 3);
    painter.restore();
}

void EditableCurveGraph::paintAxes(QPainter &painter)
{
    const QRect graph = canvasRect();
    painter.setFont(typography::caption(font()));
    painter.setPen(m_spec.colors.text);
    const QRect axisRect(8, graph.top() - 7, kAxisGutter - 12, 14);
    const QRect titleRect(graph.left(), 3, graph.width() - 68, 17);
    painter.drawText(titleRect, Qt::AlignLeft | Qt::AlignVCenter, m_spec.title);
    if (m_spec.text.formatLiveValue)
        painter.drawText(titleRect, Qt::AlignRight | Qt::AlignVCenter,
                         m_spec.text.formatLiveValue(m_liveValue));
    if (m_spec.text.formatRangeLimit)
        painter.drawText(axisRect, Qt::AlignRight | Qt::AlignVCenter,
                         m_spec.text.formatRangeLimit(true));
    if (m_spec.text.showZeroLabel)
        painter.drawText(axisRect.translated(0, pixelY(0.0) - graph.top()),
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.zeroLabel);
    if (m_spec.text.formatRangeLimit)
        painter.drawText(axisRect.translated(0, graph.bottom() - graph.top()),
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.formatRangeLimit(false));
    painter.drawText(QRect(graph.left(), graph.bottom() + 2, graph.width(), kAxisLabelHeight),
                     Qt::AlignLeft | Qt::AlignVCenter, m_spec.startLabel);
    painter.drawText(QRect(graph.left(), graph.bottom() + 2, graph.width(), kAxisLabelHeight),
                     Qt::AlignRight | Qt::AlignVCenter, m_spec.endLabel);
}

void EditableCurveGraph::paintFocus(QPainter &painter)
{
    if (!hasFocus() && (!parentWidget() || !parentWidget()->hasFocus()))
        return;
    painter.setPen(QPen(m_spec.colors.focus, 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawRect(canvasRect().adjusted(1, 1, -1, -1));
}

} // namespace songview
