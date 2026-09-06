#pragma once

#include <QColor>
#include <QPointF>
#include <QRectF>
#include <QtGlobal>
#include <vector>

class QSGNode;

namespace songview {

struct TimelineQuickRect {
    QRectF rect;
    QColor topLeft;
    QColor topRight;
    QColor bottomRight;
    QColor bottomLeft;
};

struct TimelineQuickTriangle {
    QPointF first;
    QPointF second;
    QPointF third;
    QColor firstColor;
    QColor secondColor;
    QColor thirdColor;
};

struct TimelineQuickLayerData {
    std::vector<TimelineQuickRect> rects;
    std::vector<TimelineQuickTriangle> triangles;
    quint64 revision = 0;
};

namespace timeline_quick {

QSGNode *syncLayerNode(QSGNode *oldNode, const TimelineQuickLayerData *data);
void resetLayer(TimelineQuickLayerData &data);
void addRect(TimelineQuickLayerData &data, const QRectF &rect, const QColor &color,
             const QRectF &clip);
void addHorizontalGradient(TimelineQuickLayerData &data, const QRectF &rect, const QColor &left,
                           const QColor &right, const QRectF &clip);
void addHorizontalLine(TimelineQuickLayerData &data, qreal x0, qreal x1, qreal y, qreal width,
                       const QColor &color, const QRectF &clip);
void addVerticalLine(TimelineQuickLayerData &data, qreal x, qreal y0, qreal y1, qreal width,
                     const QColor &color, const QRectF &clip);
void addDashedVertical(TimelineQuickLayerData &data, qreal x, qreal y0, qreal y1, qreal width,
                       qreal dash, qreal gap, const QColor &color, const QRectF &clip);
void addDashedHorizontal(TimelineQuickLayerData &data, qreal x0, qreal x1, qreal y, qreal width,
                         qreal dash, qreal gap, const QColor &color, const QRectF &clip);
void addSelectionReticle(TimelineQuickLayerData &data, const QRectF &rect, const QRectF &clip);
void addClippedTriangle(TimelineQuickLayerData &data, const QPointF &first, const QPointF &second,
                        const QPointF &third, const QColor &color, const QRectF &clip);
void addLine(TimelineQuickLayerData &data, const QPointF &from, const QPointF &to, qreal width,
             const QColor &color, const QRectF &clip);
void addEllipse(TimelineQuickLayerData &data, const QPointF &center, qreal radiusX, qreal radiusY,
                const QColor &color, const QRectF &clip);
void addEllipseRing(TimelineQuickLayerData &data, const QPointF &center, qreal radiusX,
                    qreal radiusY, qreal width, const QColor &color, const QRectF &clip);

} // namespace timeline_quick

} // namespace songview
