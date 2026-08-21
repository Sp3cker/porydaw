#include "curvegraph.hpp"

#include "ui/layout.h"
#include "ui/typography.h"

#include <QFontMetrics>
#include <QPainter>
#include <algorithm>
#include <iterator>

namespace {

QFont valueLabelFont(const QFont &font)
{
    return typography::caption(font);
}

QRect hoverValueRect(const QRect &canvas, const QPoint &anchor, const QFontMetrics &metrics,
                     const QString &text)
{
    if (canvas.isEmpty() || text.isEmpty())
        return {};

    const int textWidth = std::min(metrics.horizontalAdvance(text), canvas.width());
    const int textHeight = std::min(metrics.height(), canvas.height());
    const int gap = layout::space(layout::Space::One);
    int textX = anchor.x() - gap - textWidth;
    int textY = anchor.y() - gap - textHeight;
    if (textX < canvas.left())
        textX = anchor.x() + gap;
    if (textY < canvas.top())
        textY = anchor.y() + gap;
    textX =
        std::clamp(textX, canvas.left(), std::max(canvas.left(), canvas.right() - textWidth + 1));
    textY =
        std::clamp(textY, canvas.top(), std::max(canvas.top(), canvas.bottom() - textHeight + 1));
    return {textX, textY, textWidth, textHeight};
}

void paintHoverValueChip(QPainter &painter, const QRect &canvas, const QPoint &anchor,
                         const QFont &font, const QString &text, const QColor &backdrop,
                         const QColor &foreground)
{
    const QFont labelFont = valueLabelFont(font);
    const QFontMetrics metrics(labelFont);
    const int padding = layout::singlePixel();
    const QRect innerCanvas = canvas.adjusted(padding, padding, -padding, -padding);
    const QRect effectiveCanvas = innerCanvas.isValid() ? innerCanvas : canvas;
    const QString label = metrics.elidedText(text, Qt::ElideRight, effectiveCanvas.width());
    const QRect textRect = hoverValueRect(effectiveCanvas, anchor, metrics, label);
    if (textRect.isEmpty())
        return;

    painter.save();
    painter.setClipRect(canvas, Qt::IntersectClip);
    painter.setFont(labelFont);
    painter.fillRect(textRect.adjusted(-padding, -padding, padding, padding), backdrop);
    painter.setPen(foreground);
    painter.drawText(textRect, Qt::AlignHCenter | Qt::AlignVCenter, label);
    painter.restore();
}

} // namespace

namespace songview {

void CurveGraph::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    const CurveGeometry geometry =
        CurveGeometry::resolve(font(), painter.device()->devicePixelRatioF());
    painter.fillRect(canvasRect(), m_spec.colors.background);
    painter.save();
    painter.setClipRect(canvasRect());
    paintGrid(painter, geometry);
    paintCurve(painter, geometry);
    painter.restore();
    paintAxes(painter, geometry);
    paintFocus(painter, geometry);
}

void CurveGraph::paintGrid(QPainter &painter, const CurveGeometry &geometry)
{
    painter.setPen(QPen(m_spec.colors.grid, geometry.physicalPixel));
    for (const double x : m_spec.gridLines) {
        const int px = pixelX(x);
        painter.drawLine(px, canvasRect().top(), px, canvasRect().bottom());
    }
    if (m_spec.yAxis.minimum <= 0.0 && m_spec.yAxis.maximum >= 0.0) {
        const int py = pixelY(0.0);
        painter.drawLine(canvasRect().left(), py, canvasRect().right(), py);
    }
}

void CurveGraph::paintCurve(QPainter &painter, const CurveGeometry &geometry)
{
    painter.save();
    painter.setClipRect(canvasRect(), Qt::IntersectClip);
    painter.setPen(QPen(m_spec.colors.curve, geometry.curveWidth));
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
        const QPointF center = pointPosition(point);
        const bool selected = m_selectedX && *m_selectedX == point.x;
        const bool hovered = m_hoverX && *m_hoverX == point.x;
        if (selected || hovered) {
            QColor ringColor = m_spec.colors.curve;
            if (!selected)
                ringColor.setAlpha(112);
            painter.setPen(QPen(ringColor, geometry.ringOutlineWidth));
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(center, geometry.ringRadius, geometry.ringRadius);
        }
        painter.setPen(QPen(m_spec.colors.curve, geometry.nodeOutlineWidth));
        painter.setBrush(m_spec.colors.background);
        painter.drawEllipse(center, geometry.nodeRadius, geometry.nodeRadius);
    }
    painter.setRenderHint(QPainter::Antialiasing, antialiasing);
    painter.setPen(QPen(m_spec.colors.previewOutline, geometry.physicalPixel));
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(QPointF(pointPosition({m_keyboardX, m_liveValue})), geometry.previewRadius,
                        geometry.previewRadius);
    painter.restore();
    if (!m_hoverX || !m_spec.text.formatLiveValue)
        return;
    const auto hovered =
        std::find_if(m_points.cbegin(), m_points.cend(),
                     [this](const CurvePoint &point) { return point.x == *m_hoverX; });
    if (hovered == m_points.cend())
        return;
    paintHoverValueChip(painter, canvasRect(), pointPosition(*hovered), font(),
                        m_spec.text.formatLiveValue(hovered->y), m_spec.colors.background,
                        m_spec.colors.text);
}

void CurveGraph::paintAxes(QPainter &painter, const CurveGeometry &geometry)
{
    const QRect graph = canvasRect();
    painter.setFont(typography::caption(font()));
    painter.setPen(m_spec.colors.text);
    const QRect topLabelRect(graph.left(), graph.top() - geometry.topBandHeight, graph.width(),
                             geometry.labelHeight);
    if (!m_spec.title.isEmpty())
        painter.drawText(topLabelRect, Qt::AlignLeft | Qt::AlignVCenter, m_spec.title);
    if (!m_spec.startLabel.isEmpty())
        painter.drawText(graph.left(), graph.bottom() + geometry.labelGap, graph.width() / 2,
                         geometry.labelHeight, Qt::AlignLeft | Qt::AlignVCenter, m_spec.startLabel);
    if (!m_spec.endLabel.isEmpty())
        painter.drawText(graph.left() + graph.width() / 2, graph.bottom() + geometry.labelGap,
                         graph.width() / 2, geometry.labelHeight, Qt::AlignRight | Qt::AlignVCenter,
                         m_spec.endLabel);
    if (m_spec.text.formatRangeLimit) {
        painter.drawText(0, graph.top() - geometry.labelHeight / 2,
                         graph.left() - geometry.rightInset, geometry.labelHeight,
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.formatRangeLimit(true));
        painter.drawText(0, graph.bottom() - geometry.labelHeight / 2,
                         graph.left() - geometry.rightInset, geometry.labelHeight,
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.formatRangeLimit(false));
    }
    if (m_spec.text.showZeroLabel && !m_spec.text.zeroLabel.isEmpty())
        painter.drawText(0, pixelY(0.0) - geometry.labelHeight / 2,
                         graph.left() - geometry.rightInset, geometry.labelHeight,
                         Qt::AlignRight | Qt::AlignVCenter, m_spec.text.zeroLabel);
    if (m_spec.text.formatLiveValue)
        painter.drawText(topLabelRect, Qt::AlignRight | Qt::AlignVCenter,
                         m_spec.text.formatLiveValue(m_liveValue));
}

void CurveGraph::paintFocus(QPainter &painter, const CurveGeometry &geometry)
{
    if (!hasFocus() && (!parentWidget() || !parentWidget()->hasFocus()))
        return;
    painter.setPen(QPen(m_spec.colors.focusOutline, geometry.physicalPixel));
    painter.setBrush(Qt::NoBrush);
    const qreal outline = geometry.physicalPixel;
    painter.drawRect(QRectF(canvasRect()).adjusted(-outline, -outline, outline, outline));
}

} // namespace songview
