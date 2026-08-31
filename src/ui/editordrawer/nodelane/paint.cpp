#include "ui/editordrawer/nodelane/paint.h"

#include <algorithm>

#include <QLineF>
#include <QPainter>
#include <QPen>
#include <QPolygon>
#include <QRectF>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/gesture.h"
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

void paintPhantom(QPainter &painter, const AutomationGeometry &geometry, const QRect &body,
                  const QColor &color, const OriginPhantom &phantom)
{
    const QPointF center(qreal(geometry.plotOrigin),
                         AutomationProjection::valueY(body, geometry, phantom.minimumValue,
                                                      phantom.maximumValue, phantom.point.value));
    paintNode(painter, geometry, color, center);
}

// Right edge where a held segment terminates: the song end when it falls
// inside the plot, otherwise the plot edge itself.
[[nodiscard]] inline qreal heldEndX(const AutomationProjection &projection, const QRect &plot,
                                    qreal dpr)
{
    const std::optional<qreal> endX = projection.songEndX(dpr);
    return endX ? std::min(qreal(plot.right()), *endX) : qreal(plot.right());
}

void paintPhantomCurvePreview(QPainter &painter, const AutomationGeometry &geometry,
                              const QRect &body, const AutomationProjection &projection,
                              std::span<const NodePoint> points, const QRect &plot,
                              const OriginPhantom &phantom, qreal dpr)
{
    const auto next =
        std::upper_bound(points.begin(), points.end(), phantom.point.tick,
                         [](uint64_t tick, const NodePoint &point) { return tick < point.tick; });
    const qreal y = AutomationProjection::valueY(body, geometry, phantom.minimumValue,
                                                 phantom.maximumValue, phantom.point.value);
    const qreal nextX = next == points.end() ? heldEndX(projection, plot, dpr)
                                             : projection.displayX(next->tick, dpr);
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    painter.setPen(QPen(previewColor, layout::singlePixel()));
    painter.drawLine(QLineF(qreal(plot.left()), y, nextX, y));
    if (next != points.end()) {
        const qreal nextY = AutomationProjection::valueY(body, geometry, phantom.minimumValue,
                                                         phantom.maximumValue, next->value);
        painter.drawLine(QLineF(nextX, y, nextX, nextY));
    }
}
struct PointReplacement {
    NodePoint original;
    NodePoint current;
};

bool omittedPoint(const NodePoint &point, const std::optional<PointReplacement> &replacement)
{
    if (!replacement)
        return false;
    if (point.tick == replacement->original.tick && point.value == replacement->original.value)
        return true;
    return replacement->current.tick != replacement->original.tick &&
           point.tick == replacement->current.tick;
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

void paintStepCurve(QPainter &painter, std::span<const NodePoint> points, const QRect &plot,
                    const NodeLanePaint &paint, const QColor &color, qreal dpr,
                    const std::optional<PointReplacement> &replacement)
{
    if (points.empty())
        return;
    painter.setPen(QPen(color, layout::singlePixel() + layout::singlePixel()));
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    const std::optional<NodePoint> leadIn = paint.lane.leadIn();
    if (leadIn) {
        const qreal x = paint.projection.displayX(points.front().tick, dpr);
        const qreal y = yAt(points.front().value);
        const qreal leadY = yAt(leadIn->value);
        painter.drawLine(QLineF(paint.projection.displayX(leadIn->tick, dpr), leadY, x, leadY));
        if (y != leadY)
            painter.drawLine(QLineF(x, leadY, x, y));
    }
    for (size_t index = 0; index < points.size(); ++index) {
        const bool currentOmitted = omittedPoint(points[index], replacement);
        const bool nextOmitted =
            index + 1 < points.size() && omittedPoint(points[index + 1], replacement);
        if (currentOmitted || nextOmitted)
            continue;
        const qreal x0 = paint.projection.displayX(points[index].tick, dpr);
        const bool terminal = index + 1 == points.size();
        const qreal x1 = terminal ? heldEndX(paint.projection, plot, dpr)
                                  : paint.projection.displayX(points[index + 1].tick, dpr);
        if (x1 < plot.left() || x0 > plot.right() || (terminal && x0 >= x1))
            continue;
        const qreal y = yAt(points[index].value);
        painter.drawLine(QLineF(x0, y, x1, y));
        if (!terminal)
            painter.drawLine(QLineF(x1, y, x1, yAt(points[index + 1].value)));
    }
}

bool pointPaintSelected(const NodeLanePaint &paint, uint64_t tick)
{
    if (paint.selectedTickRange) {
        const auto [firstTick, lastTick] = *paint.selectedTickRange;
        if (tick >= firstTick && tick < lastTick)
            return true;
    }
    return paint.bandLane && tick >= paint.bandFirstTick && tick < paint.bandLastTick;
}

void paintNodes(QPainter &painter, std::span<const NodePoint> points, const QRect &plot,
                const NodeLanePaint &paint, qreal dpr,
                const std::optional<PointReplacement> &replacement)
{
    if (!paint.projection.nodeMarkersVisible())
        return;
    const QRectF nodeClip = painter.clipBoundingRect().intersected(QRectF(plot));
    const qreal nodeExtent =
        std::max<qreal>(paint.geometry.nodePaintRadius, paint.geometry.selectedNodeRingRadius) +
        layout::singlePixel();
    const bool dimLane = paint.multipleSelectedNodes && !paint.selectedLane;
    const auto paintPass = [&](bool selectedPass) {
        for (const auto &point : points) {
            if (omittedPoint(point, replacement))
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

void paintDragPreview(QPainter &painter, std::span<const NodePoint> points, const QRect &plot,
                      const NodeLanePaint &paint, const NodeDragGesture &gesture, qreal dpr)
{
    if (gesture.points.empty() || gesture.grabbedPoint >= gesture.points.size())
        return;
    const LaneHandle handle = paint.handle;
    const auto &grabbed = gesture.points[gesture.grabbedPoint];
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    const auto tickX = [&](uint64_t tick) { return paint.projection.displayX(tick, dpr); };
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    const bool hasPreparedPreview = paint.preparedPreviewCurve && handle.valid() &&
                                    handle.index < int(gesture.previewPoints.size()) &&
                                    !gesture.previewPoints[std::size_t(handle.index)].empty();
    if (gesture.points.size() == 1 && !hasPreparedPreview) {
        if (grabbed.lane != handle)
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
        const qreal endX = heldEndX(paint.projection, plot, dpr);
        painter.setPen(QPen(previewColor, layout::singlePixel()));
        painter.setBrush(Qt::NoBrush);
        if (previous) {
            const qreal previousY = yAt(previous->value);
            const qreal holdEnd = std::min(x, endX);
            if (holdEnd > tickX(previous->tick)) {
                painter.drawLine(QLineF(tickX(previous->tick), previousY, holdEnd, previousY));
                painter.drawLine(QLineF(holdEnd, previousY, holdEnd, y));
            }
        }
        if (next) {
            const qreal nextX = tickX(next->tick);
            painter.drawLine(QLineF(x, y, nextX, y));
            painter.drawLine(QLineF(nextX, y, nextX, yAt(next->value)));
        } else if (x < endX) {
            painter.drawLine(QLineF(x, y, endX, y));
        }
        paintNode(painter, paint.geometry, previewColor, QPointF(x, y));
        paintPreviewLabel(painter, paint.hoverState, paint.handle);
        return;
    }
    if (!handle.valid() || handle.index >= int(gesture.pointIndexesByLane.size()))
        return;
    for (const size_t index : gesture.pointIndexesByLane[std::size_t(handle.index)]) {
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

void paintPencilPreview(QPainter &painter, std::span<const NodePoint> points, const QRect &plot,
                        const NodeLanePaint &paint, const PencilGesture &gesture, qreal dpr)
{
    const NodeLaneEdit::Completion &preview = gesture.stroke.preview();
    const auto yAt = [&](int value) {
        return valueY(paint.lane, paint.body, paint.geometry, value);
    };
    const auto tickX = [&](uint64_t tick) { return paint.projection.displayX(tick, dpr); };
    const qreal endX = heldEndX(paint.projection, plot, dpr);
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
            drawHeld(point.tick, std::min<uint64_t>(nextTick, preview.tickBegin), point.value,
                     paint.color);
            if (nextTick < preview.tickBegin)
                painter.drawLine(QLineF(tickX(nextTick), yAt(point.value), tickX(nextTick),
                                        yAt(points[index + 1].value)));
        } else if (point.tick > preview.tickEnd) {
            if (index + 1 < points.size()) {
                const uint64_t last = points[index + 1].tick;
                drawHeld(point.tick, last, point.value, paint.color);
                painter.drawLine(QLineF(tickX(last), yAt(point.value), tickX(last),
                                        yAt(points[index + 1].value)));
            } else if (tickX(point.tick) < endX) {
                painter.setPen(QPen(paint.color, layout::singlePixel() + layout::singlePixel()));
                painter.drawLine(
                    QLineF(tickX(point.tick), yAt(point.value), endX, yAt(point.value)));
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
    } else if (previewValue && tickX(preview.tickEnd) < endX) {
        painter.setPen(QPen(previewColor, layout::singlePixel() + layout::singlePixel()));
        painter.drawLine(
            QLineF(tickX(preview.tickEnd), yAt(*previewValue), endX, yAt(*previewValue)));
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
        std::max<qreal>(geometry.nodePaintRadius, geometry.selectedNodeRingRadius) +
        layout::singlePixel();
    return QRectF(plot).adjusted(-extent, -extent, extent, extent);
}

} // namespace

void paintLaneHeader(QPainter &painter, const LaneHeaderPaint &paint)
{
    if (paint.separator) {
        painter.save();
        painter.setPen(themes::color(themes::Role::song_view_separator));
        painter.drawLine(paint.band.left(), paint.band.bottom(), paint.band.right(),
                         paint.band.bottom());
        painter.restore();
    }
    painter.save();
    painter.setClipRect(paint.textClip, Qt::IntersectClip);
    if (paint.arrow) {
        const QRect &arrow = *paint.arrow;
        const QPolygon triangle = paint.expanded ? QPolygon{{arrow.left(), arrow.top()},
                                                            {arrow.right(), arrow.top()},
                                                            {arrow.center().x(), arrow.bottom()}}
                                                 : QPolygon{{arrow.left(), arrow.top()},
                                                            {arrow.right(), arrow.center().y()},
                                                            {arrow.left(), arrow.bottom()}};
        painter.setPen(Qt::NoPen);
        painter.setBrush(themes::color(themes::Role::song_view_primary_text));
        painter.drawPolygon(triangle);
    }
    painter.setFont(paint.expanded ? paint.titleFont : paint.captionFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(paint.primary, Qt::AlignLeft | Qt::AlignVCenter, paint.title);
    if (!paint.secondaryText.isEmpty()) {
        painter.setFont(paint.captionFont);
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(paint.secondary, Qt::AlignLeft | Qt::AlignVCenter, paint.secondaryText);
    }
    painter.restore();
}

QRect plotRect(const QRect &body, const AutomationGeometry &geometry)
{
    return {geometry.plotOrigin, body.top(), std::max<int>(0, body.width() - geometry.plotOrigin),
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
        uint64_t(std::max<double>(0.0, hoverState.insertionTick(projection, pencilMode))), dpr);
    const QString &text = hoverState.hoverTextCache.text;
    const auto &label = hoverState.hoverValueLabel;
    const QColor backdrop = themes::color(themes::Role::song_view_piano_roll_accidental_lane);
    const qreal padding = layout::singlePixel();
    if (hoverState.hover.hasPoint) {
        const qreal nodeRadius = hoverRingRadius(geometry);
        const qreal displayX = hoverState.hover.originPhantom
                                   ? qreal(geometry.plotOrigin)
                                   : projection.displayX(hoverState.hover.point.tick, dpr);
        const QPointF center(displayX, valueY(lane, body, geometry, hoverState.hover.point.value));
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
    const LaneHandle handle = paint.handle;
    if (paint.pencil && paint.pencil->lane == handle) {
        painter.setClipRect(overflow, Qt::IntersectClip);
        paintPencilPreview(painter, paint.points, plot, paint, *paint.pencil, dpr);
    } else {
        std::optional<PointReplacement> replacement;
        std::span<const NodePoint> curve = paint.points;
        if (const NodeDragGesture *gesture = paint.nodeDrag) {
            const bool usePreview = (gesture->points.size() > 1 || paint.preparedPreviewCurve) &&
                                    handle.valid() &&
                                    handle.index < int(gesture->previewPoints.size()) &&
                                    !gesture->previewPoints[std::size_t(handle.index)].empty();
            if (usePreview) {
                curve = gesture->previewPoints[std::size_t(handle.index)];
            } else if (handle == gesture->lane && gesture->grabbedPoint < gesture->points.size()) {
                const auto &point = gesture->points[gesture->grabbedPoint];
                replacement = PointReplacement{point.original, point.current};
            }
        } else if (paint.phantom && paint.phantom->original) {
            replacement = PointReplacement{*paint.phantom->original, paint.phantom->current.point};
        }
        const QColor curveColor =
            paint.multipleSelectedNodes && !paint.selectedLane ? paint.dimmedColor : paint.color;
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        paintStepCurve(painter, curve, plot, paint, curveColor, dpr, replacement);
        if (paint.phantom && paint.phantom->original)
            paintPhantomCurvePreview(painter, paint.geometry, paint.body, paint.projection, curve,
                                     plot, paint.phantom->current, dpr);
        painter.restore();
        painter.setClipRect(overflow, Qt::IntersectClip);
        paintNodes(painter, curve, plot, paint, dpr, replacement);
        if (paint.nodeDrag && (paint.nodeDrag->points.size() > 1 || handle == paint.nodeDrag->lane))
            paintDragPreview(painter, paint.points, plot, paint, *paint.nodeDrag, dpr);
        else if (paint.sweep && handle == paint.sweep->lane)
            paintSweepPreview(painter, paint, *paint.sweep, dpr);
    }
    if (paint.phantom) {
        paintPhantom(painter, paint.geometry, paint.body, paint.color, paint.phantom->current);
        if (paint.phantom->original)
            paintPreviewLabel(painter, paint.hoverState, paint.handle);
    }
    if (paint.hoverState.hover.lane == paint.handle)
        paintHover(painter, paint.lane, paint.body, paint.geometry, paint.projection,
                   paint.hoverState, paint.pencilMode);
    painter.restore();
}

} // namespace nodelane
