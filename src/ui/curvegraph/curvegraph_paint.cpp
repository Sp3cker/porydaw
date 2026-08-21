#include "curvegraph.hpp"

#include "ui/typography.h"

#include <QPainter>
#include <algorithm>
#include <iterator>

namespace songview {

void CurveGraph::paintEvent(QPaintEvent *)
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

void CurveGraph::paintGrid(QPainter &painter)
{
    painter.setPen(QPen(m_spec.colors.grid, 1));
    for (const double x : m_spec.gridLines) {
        const int px = pixelX(x);
        painter.drawLine(px, canvasRect().top(), px, canvasRect().bottom());
    }
    if (m_spec.yAxis.minimum <= 0.0 && m_spec.yAxis.maximum >= 0.0) {
        const int py = pixelY(0.0);
        painter.drawLine(canvasRect().left(), py, canvasRect().right(), py);
    }
}

void CurveGraph::paintCurve(QPainter &painter)
{
    painter.save();
    painter.setClipRect(canvasRect(), Qt::IntersectClip);
    painter.setPen(QPen(m_spec.colors.curve, 2));
    for (auto it = m_points.cbegin(); it != m_points.cend(); ++it) {
        const auto next = std::next(it);
        if (next == m_points.cend())
            break;
        const QPoint p0 = pointPosition(*it);
        const QPoint p1 = pointPosition(*next);
        if (isLinearSegment(it->x, next->x)) {
            painter.drawLine(p0, p1);
        } else {
            painter.drawLine(p0, QPoint(p1.x(), p0.y()));
            painter.drawLine(QPoint(p1.x(), p0.y()), p1);
        }
    }
    const bool antialiasing = painter.testRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::Antialiasing, true);
    for (const CurvePoint &point : m_points) {
        const QPoint center = pointPosition(point);
        const bool selected = m_selectedX && *m_selectedX == point.x;
        if (selected) {
            painter.setPen(QPen(m_spec.colors.focus, 2));
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(center, kSelectedNodeRingRadius, kSelectedNodeRingRadius);
        }
        const bool endpoint = point.x == m_spec.xAxis.minimum || point.x == m_spec.xAxis.maximum;
        painter.setPen(Qt::NoPen);
        painter.setBrush(endpoint ? m_spec.colors.endpoint : m_spec.colors.curve);
        painter.drawEllipse(center, kNodePaintRadius, kNodePaintRadius);
    }
    painter.setRenderHint(QPainter::Antialiasing, antialiasing);
    painter.setPen(QPen(m_spec.colors.previewOutline, 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(pointPosition({m_keyboardX, m_liveValue}), 3, 3);
    painter.restore();
}

void CurveGraph::paintAxes(QPainter &painter)
{
    const QRect graph = canvasRect();
    painter.setFont(typography::caption(font()));
    painter.setPen(m_spec.colors.text);
    if (!m_spec.title.isEmpty())
        painter.drawText(graph.left(), graph.top() - 24, graph.width(), kAxisLabelHeight,
                         Qt::AlignLeft | Qt::AlignVCenter, m_spec.title);
    if (!m_spec.startLabel.isEmpty())
        painter.drawText(graph.left(), graph.bottom() + 4, graph.width() / 2, kAxisLabelHeight,
                         Qt::AlignLeft | Qt::AlignVCenter, m_spec.startLabel);
    if (!m_spec.endLabel.isEmpty())
        painter.drawText(graph.left() + graph.width() / 2, graph.bottom() + 4, graph.width() / 2,
                         kAxisLabelHeight, Qt::AlignRight | Qt::AlignVCenter, m_spec.endLabel);
    if (m_spec.text.formatRangeLimit) {
        painter.drawText(0, graph.top() - kAxisLabelHeight / 2, graph.left() - 8, kAxisLabelHeight,
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.formatRangeLimit(true));
        painter.drawText(0, graph.bottom() - kAxisLabelHeight / 2, graph.left() - 8,
                         kAxisLabelHeight, Qt::AlignRight | Qt::AlignVCenter,
                         m_spec.text.formatRangeLimit(false));
    }
    if (m_spec.text.showZeroLabel && !m_spec.text.zeroLabel.isEmpty())
        painter.drawText(0, pixelY(0.0) - kAxisLabelHeight / 2, graph.left() - 8, kAxisLabelHeight,
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.zeroLabel);
    if (m_spec.text.formatLiveValue)
        painter.drawText(graph.left(), graph.top() - 24, graph.width(), kAxisLabelHeight,
                         Qt::AlignRight | Qt::AlignVCenter,
                         m_spec.text.formatLiveValue(m_liveValue));
}

void CurveGraph::paintFocus(QPainter &painter)
{
    if (!hasFocus() && (!parentWidget() || !parentWidget()->hasFocus()))
        return;
    painter.setPen(QPen(m_spec.colors.focus, 1));
    painter.setBrush(Qt::NoBrush);
    painter.drawRect(canvasRect().adjusted(-1, -1, 1, 1));
}

} // namespace songview
