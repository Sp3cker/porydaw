#include "ui/editordrawer/nodelane/paint.h"

#include <algorithm>

#include <QLineF>
#include <QPainter>
#include <QPen>
#include <QRectF>

#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace nodelane {
namespace {

void paintNode(QPainter &painter, const AutomationGeometry &geometry, const QColor &color,
               const QPointF &center, bool selected = false, const QColor &selectedColor = {},
               bool dimUnselected = false, const QColor &dimmedColor = {})
{
    const bool antialiasing = painter.testRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const auto nodeRadius = geometry.nodePaintRadius;
    if (selected && selectedColor.isValid()) {
        painter.setPen(QPen(selectedColor, geometry.selectedNodeRingDipWidth));
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(center, geometry.selectedNodeRingRadius,
                            geometry.selectedNodeRingRadius);
    }
    if (dimUnselected && !selected) {
        painter.setPen(Qt::NoPen);
        painter.setBrush(dimmedColor.isValid()
                             ? dimmedColor
                             : themes::color(themes::Role::song_view_secondary_text));
    } else {
        painter.setPen(QPen(color, geometry.nodeOutlineDipWidth * 2.0));
        painter.setBrush(themes::color(themes::Role::song_view_piano_roll_background));
    }
    painter.drawEllipse(center, nodeRadius, nodeRadius);
    painter.setRenderHint(QPainter::Antialiasing, antialiasing);
}

bool omittedPoint(const NodePoint &point, const NodePoint *omitted, const NodePoint *replacement)
{
    if (omitted && point.tick == omitted->tick && point.value == omitted->value)
        return true;
    return omitted && replacement && replacement->tick != omitted->tick &&
           point.tick == replacement->tick;
}

void paintPreviewLabel(QPainter &painter, const NodeLaneHoverState &hoverState, LaneHandle handle)
{
    const auto &label = hoverState.previewValueLabel;
    if (!label.valid || label.lane != handle)
        return;
    const qreal padding = layout::singlePixel();
    painter.setFont(label.font);
    painter.fillRect(label.bounds.adjusted(-padding, -padding, padding, padding),
                     themes::color(themes::Role::song_view_piano_roll_accidental_lane));
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, label.text);
}

void paintStepCurve(QPainter &painter, const std::vector<NodePoint> &points, const QRect &plot,
                    const NodeLanePaint &paint, const QColor &color, qreal dpr,
                    const NodePoint *omitted, const NodePoint *replacement)
{
    if (points.empty())
        return;
    painter.setPen(QPen(color, layout::singlePixel() + layout::singlePixel()));
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    if (paint.leadIn) {
        const qreal x = paint.projection.displayX(points.front().tick, dpr);
        const qreal y = yAt(points.front().value);
        const qreal leadY = yAt(paint.leadIn->value);
        painter.drawLine(
            QLineF(paint.projection.displayX(paint.leadIn->tick, dpr), leadY, x, leadY));
        if (y != leadY)
            painter.drawLine(QLineF(x, leadY, x, y));
    }
    for (size_t index = 0; index < points.size(); ++index) {
        const bool currentOmitted = omittedPoint(points[index], omitted, replacement);
        const bool nextOmitted =
            index + 1 < points.size() && omittedPoint(points[index + 1], omitted, replacement);
        if (currentOmitted || nextOmitted)
            continue;
        const qreal x0 = paint.projection.displayX(points[index].tick, dpr);
        const qreal x1 = index + 1 < points.size()
                             ? paint.projection.displayX(points[index + 1].tick, dpr)
                             : plot.right();
        if (x1 < plot.left() || x0 > plot.right())
            continue;
        const qreal y = yAt(points[index].value);
        painter.drawLine(QLineF(x0, y, x1, y));
        if (index + 1 < points.size())
            painter.drawLine(QLineF(x1, y, x1, yAt(points[index + 1].value)));
    }
}

bool pointPaintSelected(const NodeLanePaint &paint, uint64_t tick)
{
    if (paint.lane.pointSelected(tick))
        return true;
    return paint.bandLane && tick >= paint.bandFirstTick && tick < paint.bandLastTick;
}

void paintNodes(QPainter &painter, const std::vector<NodePoint> &points, const QRect &plot,
                const NodeLanePaint &paint, qreal dpr, const NodePoint *omitted)
{
    if (!paint.projection.nodeMarkersVisible())
        return;
    const QRectF nodeClip = painter.clipBoundingRect().intersected(QRectF(plot));
    const qreal nodeExtent =
        std::max(paint.geometry.nodePaintRadius, paint.geometry.selectedNodeRingRadius) +
        layout::singlePixel();
    const bool dimLane = paint.multipleSelectedNodes && !paint.selectedLane;
    const auto paintPass = [&](bool selectedPass) {
        for (const auto &point : points) {
            if (omitted && point.tick == omitted->tick && point.value == omitted->value)
                continue;
            const bool selected = pointPaintSelected(paint, point.tick);
            if (selected != selectedPass)
                continue;
            const qreal x = paint.projection.displayX(point.tick, dpr);
            const qreal y = valueY(paint.lane, paint.body, paint.geometry, point.value);
            if (!nodeClip.intersects(
                    QRectF(x - nodeExtent, y - nodeExtent, 2 * nodeExtent, 2 * nodeExtent)))
                continue;
            paintNode(painter, paint.geometry, paint.color, QPointF(x, y), selected,
                      paint.selectedColor, dimLane, paint.dimmedColor);
        }
    };
    paintPass(false);
    paintPass(true);
}

void paintDragPreview(QPainter &painter, const std::vector<NodePoint> &points, const QRect &plot,
                      const NodeLanePaint &paint, const NodeDragGesture &gesture, qreal dpr)
{
    if (gesture.points.empty() || gesture.grabbedPoint >= gesture.points.size())
        return;
    const int rowIndex = paint.gestureRow;
    const auto &grabbed = gesture.points[gesture.grabbedPoint];
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    const auto tickX = [&](uint64_t tick) { return paint.projection.displayX(tick, dpr); };
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    if (gesture.points.size() == 1 && !paint.preparedPreviewCurve) {
        if (grabbed.row != rowIndex)
            return;
        const auto isOriginal = [&](const NodePoint &point) {
            return point.tick == grabbed.original.tick && point.value == grabbed.original.value;
        };
        const NodePoint *previous = nullptr;
        const NodePoint *next = nullptr;
        for (const auto &point : points) {
            if (isOriginal(point) || point.tick == grabbed.current.tick)
                continue;
            if (point.tick < grabbed.current.tick) {
                previous = &point;
                continue;
            }
            next = &point;
            break;
        }
        const qreal x = tickX(grabbed.current.tick);
        const qreal y = yAt(grabbed.current.value);
        painter.setPen(QPen(previewColor, layout::singlePixel()));
        painter.setBrush(Qt::NoBrush);
        if (previous) {
            const qreal previousY = yAt(previous->value);
            painter.drawLine(QLineF(tickX(previous->tick), previousY, x, previousY));
            painter.drawLine(QLineF(x, previousY, x, y));
        }
        const qreal nextX = next ? tickX(next->tick) : plot.right();
        painter.drawLine(QLineF(x, y, nextX, y));
        if (next)
            painter.drawLine(QLineF(nextX, y, nextX, yAt(next->value)));
        paintNode(painter, paint.geometry, previewColor, QPointF(x, y));
        paintPreviewLabel(painter, paint.hoverState, paint.handle);
        return;
    }
    if (rowIndex < 0 || rowIndex >= int(gesture.pointIndexesByRow.size()))
        return;
    for (const size_t index : gesture.pointIndexesByRow[std::size_t(rowIndex)]) {
        if (index >= gesture.points.size())
            continue;
        const auto &point = gesture.points[index];
        const QPointF center(tickX(point.current.tick), yAt(point.current.value));
        paintNode(painter, paint.geometry, previewColor, center, true, paint.selectedColor);
        if (index == gesture.grabbedPoint)
            paintPreviewLabel(painter, paint.hoverState, paint.handle);
    }
}

void paintSweepPreview(QPainter &painter, const NodeLanePaint &paint, const SweepGesture &gesture,
                       qreal dpr)
{
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    const auto tickX = [&](uint64_t tick) { return paint.projection.displayX(tick, dpr); };
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    painter.setPen(QPen(previewColor, layout::singlePixel()));
    painter.setBrush(Qt::NoBrush);
    if (gesture.mode == SweepGesture::Mode::Ramp) {
        painter.drawLine(QLineF(tickX(gesture.anchor.tick), yAt(gesture.anchor.value),
                                tickX(gesture.current.tick), yAt(gesture.current.value)));
    } else if (gesture.points.size() > 1) {
        for (size_t index = 0; index + 1 < gesture.points.size(); ++index) {
            const qreal y = yAt(gesture.points[index].value);
            painter.drawLine(QLineF(tickX(gesture.points[index].tick), y,
                                    tickX(gesture.points[index + 1].tick), y));
            painter.drawLine(QLineF(tickX(gesture.points[index + 1].tick), y,
                                    tickX(gesture.points[index + 1].tick),
                                    yAt(gesture.points[index + 1].value)));
        }
    }
    paintNode(painter, paint.geometry, previewColor,
              QPointF(tickX(gesture.current.tick), yAt(gesture.current.value)));
    paintPreviewLabel(painter, paint.hoverState, paint.handle);
}

void paintPencilPreview(QPainter &painter, const std::vector<NodePoint> &points, const QRect &plot,
                        const NodeLanePaint &paint, const PencilGesture &gesture, qreal dpr)
{
    const NodeLaneEdit::Completion &preview = gesture.stroke.preview();
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    const auto tickX = [&](uint64_t tick) { return paint.projection.displayX(tick, dpr); };
    const auto drawHeld = [&](uint64_t first, uint64_t last, int value, const QColor &stroke) {
        if (first >= last)
            return;
        painter.setPen(QPen(stroke, layout::singlePixel() + layout::singlePixel()));
        painter.drawLine(QLineF(tickX(first), yAt(value), tickX(last), yAt(value)));
    };
    std::optional<int> heldBefore;
    const NodePoint *nextAfterRange = nullptr;
    for (const auto &point : points) {
        if (point.tick < preview.tickBegin)
            heldBefore = point.value;
        if (point.tick > preview.tickEnd) {
            nextAfterRange = &point;
            break;
        }
    }
    for (size_t index = 0; index < points.size(); ++index) {
        const auto &point = points[index];
        const uint64_t nextTick =
            index + 1 < points.size() ? points[index + 1].tick : preview.tickBegin;
        if (point.tick < preview.tickBegin) {
            drawHeld(point.tick, std::min(nextTick, preview.tickBegin), point.value, paint.color);
            if (nextTick < preview.tickBegin)
                painter.drawLine(QLineF(tickX(nextTick), yAt(point.value), tickX(nextTick),
                                        yAt(points[index + 1].value)));
        } else if (point.tick > preview.tickEnd) {
            if (index + 1 < points.size()) {
                const uint64_t last = points[index + 1].tick;
                drawHeld(point.tick, last, point.value, paint.color);
                painter.drawLine(QLineF(tickX(last), yAt(point.value), tickX(last),
                                        yAt(points[index + 1].value)));
            } else {
                painter.setPen(QPen(paint.color, layout::singlePixel() + layout::singlePixel()));
                painter.drawLine(
                    QLineF(tickX(point.tick), yAt(point.value), plot.right(), yAt(point.value)));
            }
        }
    }
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    std::optional<int> previewValue = heldBefore;
    uint64_t cursor = preview.tickBegin;
    for (const auto &point : preview.points) {
        if (point.tick < preview.tickBegin || point.tick > preview.tickEnd)
            continue;
        if (previewValue)
            drawHeld(cursor, point.tick, *previewValue, previewColor);
        if (previewValue && *previewValue != point.value)
            painter.drawLine(
                QLineF(tickX(point.tick), yAt(*previewValue), tickX(point.tick), yAt(point.value)));
        previewValue = point.value;
        cursor = point.tick;
    }
    if (previewValue)
        drawHeld(cursor, preview.tickEnd, *previewValue, previewColor);
    if (previewValue && nextAfterRange) {
        drawHeld(preview.tickEnd, nextAfterRange->tick, *previewValue, previewColor);
        if (*previewValue != nextAfterRange->value)
            painter.drawLine(QLineF(tickX(nextAfterRange->tick), yAt(*previewValue),
                                    tickX(nextAfterRange->tick), yAt(nextAfterRange->value)));
    } else if (previewValue) {
        painter.setPen(QPen(previewColor, layout::singlePixel() + layout::singlePixel()));
        painter.drawLine(
            QLineF(tickX(preview.tickEnd), yAt(*previewValue), plot.right(), yAt(*previewValue)));
    }
    if (paint.projection.nodeMarkersVisible()) {
        const QRectF nodeClip = painter.clipBoundingRect().intersected(QRectF(plot));
        const qreal nodeExtent = paint.geometry.nodePaintRadius + layout::singlePixel();
        for (const auto &point : points) {
            if (point.tick >= preview.tickBegin && point.tick <= preview.tickEnd)
                continue;
            const QPointF center(tickX(point.tick), yAt(point.value));
            if (nodeClip.intersects(QRectF(center.x() - nodeExtent, center.y() - nodeExtent,
                                           2 * nodeExtent, 2 * nodeExtent)))
                paintNode(painter, paint.geometry, paint.color, center);
        }
        for (const auto &point : preview.points) {
            const QPointF center(tickX(point.tick), yAt(point.value));
            if (nodeClip.intersects(QRectF(center.x() - nodeExtent, center.y() - nodeExtent,
                                           2 * nodeExtent, 2 * nodeExtent)))
                paintNode(painter, paint.geometry, previewColor, center);
        }
    }
    paintPreviewLabel(painter, paint.hoverState, paint.handle);
}

QRectF nodeOverflowClip(const QRect &plot, const AutomationGeometry &geometry)
{
    const qreal extent =
        std::max(geometry.nodePaintRadius, geometry.selectedNodeRingRadius) + layout::singlePixel();
    return QRectF(plot).adjusted(-extent, -extent, extent, extent);
}

} // namespace

QRect plotRect(const QRect &body, const AutomationGeometry &geometry)
{
    return {geometry.plotOrigin, body.top(), std::max(0, body.width() - geometry.plotOrigin),
            body.height()};
}

qreal valueY(const NodeLane &lane, const QRect &body, const AutomationGeometry &geometry, int value)
{
    return AutomationProjection::valueY(body, geometry, lane.minimumValue(), lane.maximumValue(),
                                        value);
}

qreal hoverRingRadius(const AutomationGeometry &geometry)
{
    return geometry.nodePaintRadius + geometry.nodeOutlineDipWidth + layout::singlePixel();
}

void paintHover(QPainter &painter, const NodeLane &lane, const QRect &body,
                const AutomationGeometry &geometry, const AutomationProjection &projection,
                const NodeLaneHoverState &hoverState, bool pencilMode)
{
    if (!hoverState.hover.lane.valid())
        return;
    const QRect plot = plotRect(body, geometry);
    painter.save();
    painter.setClipRect(plot, Qt::IntersectClip);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const qreal x = projection.displayX(
        uint64_t(std::max(0.0, hoverState.insertionTick(projection, pencilMode))), dpr);
    const QString &text = hoverState.hoverTextCache.text;
    const auto &label = hoverState.hoverValueLabel;
    const QColor backdrop = themes::color(themes::Role::song_view_piano_roll_accidental_lane);
    const qreal padding = layout::singlePixel();
    if (hoverState.hover.hasPoint) {
        const qreal nodeRadius = hoverRingRadius(geometry);
        const QPointF center(projection.displayX(hoverState.hover.point.tick, dpr),
                             valueY(lane, body, geometry, hoverState.hover.point.value));
        const bool antialiasing = painter.testRenderHint(QPainter::Antialiasing);
        painter.setRenderHint(QPainter::Antialiasing, true);
        painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline),
                            2 * layout::singlePixel()));
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(center, nodeRadius, nodeRadius);
        painter.setRenderHint(QPainter::Antialiasing, antialiasing);
    }
    if (pencilMode) {
        if (!hoverState.hover.hasPoint) {
            const QPointF center(
                x, valueY(lane, body, geometry, hoverState.hoverValue(lane, body, geometry)));
            paintNode(painter, geometry,
                      themes::color(themes::Role::song_view_edit_preview_outline), center);
        }
        if (!text.isEmpty() && label.valid && label.lane == hoverState.hover.lane) {
            painter.setFont(label.font);
            painter.fillRect(label.bounds.adjusted(-padding, -padding, padding, padding), backdrop);
            painter.setPen(themes::color(themes::Role::song_view_primary_text));
            painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, text);
        }
        painter.restore();
        return;
    }
    painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                        layout::singlePixel(), Qt::DotLine));
    painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
    if (!hoverState.hover.hasPoint) {
        int heldValue = 0;
        if (hoverState.hoverValueFor(lane, body, geometry, projection,
                                     hoverState.insertionTick(projection, false), false,
                                     hoverState.pointCache.revision, &heldValue)) {
            const QPointF center(x, valueY(lane, body, geometry, heldValue));
            paintNode(painter, geometry,
                      themes::color(themes::Role::song_view_edit_preview_outline), center);
        }
    }
    if (!text.isEmpty() && label.valid && label.lane == hoverState.hover.lane) {
        painter.setFont(label.font);
        painter.fillRect(label.bounds.adjusted(-padding, -padding, padding, padding), backdrop);
        painter.setPen(themes::color(themes::Role::song_view_primary_text));
        painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, text);
    }
    painter.restore();
}

void paintNodeLane(QPainter &painter, const NodeLanePaint &paint)
{
    const QRect plot = plotRect(paint.body, paint.geometry);
    const QRectF overflow = nodeOverflowClip(plot, paint.geometry);
    painter.save();
    const qreal dpr = painter.device()->devicePixelRatioF();
    const std::vector<NodePoint> points = paint.lane.points();
    const int row = paint.gestureRow;
    if (paint.pencil && paint.pencil->row == row) {
        painter.setClipRect(overflow, Qt::IntersectClip);
        paintPencilPreview(painter, points, plot, paint, *paint.pencil, dpr);
    } else {
        const NodePoint *omitted = nullptr;
        const NodePoint *replacement = nullptr;
        NodePoint omittedStore;
        NodePoint replacementStore;
        const std::vector<NodePoint> *curve = &points;
        std::vector<NodePoint> previewCurve;
        if (const NodeDragGesture *gesture = paint.nodeDrag) {
            const bool usePreview = (gesture->points.size() > 1 || paint.preparedPreviewCurve) &&
                                    row >= 0 && row < int(gesture->previewPoints.size()) &&
                                    !gesture->previewPoints[std::size_t(row)].empty();
            if (usePreview) {
                previewCurve.reserve(gesture->previewPoints[std::size_t(row)].size());
                for (const ValuePoint &point : gesture->previewPoints[std::size_t(row)])
                    previewCurve.push_back({point.tick, point.value});
                curve = &previewCurve;
            } else if (row == gesture->row && gesture->grabbedPoint < gesture->points.size()) {
                const auto &point = gesture->points[gesture->grabbedPoint];
                omittedStore = {point.original.tick, point.original.value};
                replacementStore = {point.current.tick, point.current.value};
                omitted = &omittedStore;
                replacement = &replacementStore;
            }
        }
        const QColor curveColor =
            paint.multipleSelectedNodes && !paint.selectedLane ? paint.dimmedColor : paint.color;
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        paintStepCurve(painter, *curve, plot, paint, curveColor, dpr, omitted, replacement);
        painter.restore();
        painter.setClipRect(overflow, Qt::IntersectClip);
        paintNodes(painter, *curve, plot, paint, dpr, omitted);
        if (paint.nodeDrag && (paint.nodeDrag->points.size() > 1 || row == paint.nodeDrag->row))
            paintDragPreview(painter, points, plot, paint, *paint.nodeDrag, dpr);
        else if (paint.sweep && row == paint.sweep->row)
            paintSweepPreview(painter, paint, *paint.sweep, dpr);
    }
    if (paint.hoverState.hover.lane == paint.handle)
        paintHover(painter, paint.lane, paint.body, paint.geometry, paint.projection,
                   paint.hoverState, paint.pencilMode);
    painter.restore();
}

} // namespace nodelane
