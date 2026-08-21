#include "ui/editordrawer/automationpaint.h"

#include <algorithm>
#include <cmath>

#include <QLineF>
#include <QPainter>
#include <QPen>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationhover.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationpencilgesture.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace automation::paint {

void paintHover(QPainter &painter, const RowPaintParams &ctx, AutomationPage &page,
                const AutomationGeometry &geometry, const CCLanes &rows,
                const AutomationHoverState &hoverState, bool pencilMode)
{
    const AutomationRow &row = ctx.row;
    const int rowIndex = ctx.rowIndex;
    const QRect &plot = ctx.plot;
    if (rowIndex != hoverState.hover.row)
        return;
    const qreal dpr = painter.device()->devicePixelRatioF();
    const qreal x = page.displayX(hoverState.insertionTick(ctx.proj, row, pencilMode),
                                  geometry.plotOrigin, dpr);
    const QString &text = hoverState.hoverText;
    const auto &label = hoverState.hoverValueLabel;
    const QColor backdrop = themes::color(themes::Role::song_view_piano_roll_accidental_lane);
    const qreal padding = layout::singlePixel();
    if (pencilMode) {
        if (!hoverState.hover.hasPoint) {
            const QPointF center(x,
                                 ctx.proj.pointY(row, rowIndex, hoverState.hoverValue(ctx.proj)));
            paintAutomationNode(painter, geometry,
                                themes::color(themes::Role::song_view_edit_preview_outline),
                                center);
        }
        if (text.isEmpty() || !label.valid || label.row != rowIndex)
            return;
        painter.setFont(label.font);
        painter.fillRect(label.bounds.adjusted(-padding, -padding, padding, padding), backdrop);
        painter.setPen(themes::color(themes::Role::song_view_primary_text));
        painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, text);
        return;
    }
    painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                        layout::singlePixel(), Qt::DotLine));
    painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
    if (!hoverState.hover.hasPoint) {
        int heldValue = 0;
        if (hoverState.hoverValueFor(rows, ctx.proj, row, rowIndex,
                                     hoverState.insertionTick(ctx.proj, row, false), false,
                                     &heldValue)) {
            const QPointF center(x, ctx.proj.pointY(row, rowIndex, heldValue));
            paintAutomationNode(painter, geometry,
                                themes::color(themes::Role::song_view_edit_preview_outline),
                                center);
        }
    }
    if (text.isEmpty() || !label.valid || label.row != rowIndex)
        return;
    painter.setFont(label.font);
    painter.fillRect(label.bounds.adjusted(-padding, -padding, padding, padding), backdrop);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, text);
}

void paintNodeDragPreview(QPainter &painter, const RowPaintParams &ctx,
                          const NodeDragGesture &gesture, AutomationCanvas &area,
                          AutomationPage &page, const AutomationGeometry &geometry,
                          const AutomationHoverState &hoverState)
{
    if (gesture.points.empty() || gesture.grabbedPoint >= gesture.points.size())
        return;
    const AutomationProjection &proj = ctx.proj;
    const AutomationRow &row = ctx.row;
    int rowIndex = ctx.rowIndex;
    const QRect &plot = ctx.plot;
    const std::vector<LanePoint> &points = ctx.points;
    const auto &grabbed = gesture.points[gesture.grabbedPoint];
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto tickX = [&](uint64_t tick) { return page.displayX(tick, geometry.plotOrigin, dpr); };
    const auto valueY = [&](int value) { return qRound(proj.pointY(row, rowIndex, value)); };
    if (gesture.points.size() == 1) {
        if (grabbed.row != rowIndex)
            return;
        const auto isOriginal = [&](const LanePoint &point) {
            return point.tick == grabbed.original.tick && point.value == grabbed.original.value;
        };
        const LanePoint *previous = nullptr;
        const LanePoint *next = nullptr;
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
        const int y = valueY(grabbed.current.value);
        painter.setPen(QPen(previewColor, layout::singlePixel()));
        painter.setBrush(Qt::NoBrush);
        if (previous) {
            const int previousY = valueY(previous->value);
            painter.drawLine(QLineF(tickX(previous->tick), previousY, x, previousY));
            painter.drawLine(QLineF(x, previousY, x, y));
        }
        const qreal nextX = next ? tickX(next->tick) : plot.right();
        painter.drawLine(QLineF(x, y, nextX, y));
        if (next)
            painter.drawLine(QLineF(nextX, y, nextX, valueY(next->value)));
        paintAutomationNode(painter, geometry, previewColor, QPointF(x, y));
        const auto &label = hoverState.previewValueLabel;
        if (label.valid && label.row == rowIndex) {
            painter.setFont(label.font);
            painter.fillRect(label.bounds.adjusted(-layout::singlePixel(), -layout::singlePixel(),
                                                   layout::singlePixel(), layout::singlePixel()),
                             themes::color(themes::Role::song_view_piano_roll_accidental_lane));
            painter.setPen(themes::color(themes::Role::song_view_primary_text));
            painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, label.text);
        }
        return;
    }
    if (rowIndex >= int(gesture.pointIndexesByRow.size()))
        return;
    const QColor selectedColor = area.palette().highlight().color();
    for (const size_t index : gesture.pointIndexesByRow[rowIndex]) {
        if (index >= gesture.points.size())
            continue;
        const auto &point = gesture.points[index];
        const QPointF center(tickX(point.current.tick), valueY(point.current.value));
        paintAutomationNode(painter, geometry, previewColor, center, true, selectedColor);
        if (index != gesture.grabbedPoint)
            continue;
        const auto &label = hoverState.previewValueLabel;
        if (label.valid && label.row == rowIndex) {
            painter.setFont(label.font);
            painter.fillRect(label.bounds.adjusted(-layout::singlePixel(), -layout::singlePixel(),
                                                   layout::singlePixel(), layout::singlePixel()),
                             themes::color(themes::Role::song_view_piano_roll_accidental_lane));
            painter.setPen(themes::color(themes::Role::song_view_primary_text));
            painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, label.text);
        }
    }
}

void paintPencilPreview(QPainter &painter, const RowPaintParams &ctx, const PencilGesture &gesture,
                        AutomationPage &page, const AutomationGeometry &geometry,
                        const AutomationHoverState &hoverState)
{
    const AutomationProjection &proj = ctx.proj;
    const AutomationRow &row = ctx.row;
    int rowIndex = ctx.rowIndex;
    const QRect &plot = ctx.plot;
    const std::vector<LanePoint> &points = ctx.points;
    const QColor &color = ctx.color;
    const NodeLaneEdit::Completion &preview = gesture.stroke.preview();
    const auto valueY = [&](int value) { return qRound(proj.pointY(row, rowIndex, value)); };
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto tickX = [&](uint64_t tick) { return page.displayX(tick, geometry.plotOrigin, dpr); };
    const auto drawHeld = [&](uint64_t first, uint64_t last, int value, const QColor &stroke) {
        if (first >= last)
            return;
        painter.setPen(QPen(stroke, layout::singlePixel() + layout::singlePixel()));
        painter.drawLine(QLineF(tickX(first), valueY(value), tickX(last), valueY(value)));
    };

    std::optional<int> heldBefore;
    const LanePoint *nextAfterRange = nullptr;
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
            drawHeld(point.tick, std::min(nextTick, preview.tickBegin), point.value, color);
            if (nextTick < preview.tickBegin)
                painter.drawLine(QLineF(tickX(nextTick), valueY(point.value), tickX(nextTick),
                                        valueY(points[index + 1].value)));
        } else if (point.tick > preview.tickEnd) {
            if (index + 1 < points.size()) {
                const uint64_t last = points[index + 1].tick;
                drawHeld(point.tick, last, point.value, color);
                painter.drawLine(QLineF(tickX(last), valueY(point.value), tickX(last),
                                        valueY(points[index + 1].value)));
            } else {
                painter.setPen(QPen(color, layout::singlePixel() + layout::singlePixel()));
                painter.drawLine(QLineF(tickX(point.tick), valueY(point.value), plot.right(),
                                        valueY(point.value)));
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
            painter.drawLine(QLineF(tickX(point.tick), valueY(*previewValue), tickX(point.tick),
                                    valueY(point.value)));
        previewValue = point.value;
        cursor = point.tick;
    }
    if (previewValue)
        drawHeld(cursor, preview.tickEnd, *previewValue, previewColor);
    if (previewValue && nextAfterRange) {
        drawHeld(preview.tickEnd, nextAfterRange->tick, *previewValue, previewColor);
        if (*previewValue != nextAfterRange->value)
            painter.drawLine(QLineF(tickX(nextAfterRange->tick), valueY(*previewValue),
                                    tickX(nextAfterRange->tick), valueY(nextAfterRange->value)));
    } else if (previewValue) {
        painter.setPen(QPen(previewColor, layout::singlePixel() + layout::singlePixel()));
        painter.drawLine(QLineF(tickX(preview.tickEnd), valueY(*previewValue), plot.right(),
                                valueY(*previewValue)));
    }

    if (proj.nodeMarkersVisible()) {
        const QRectF nodeClip = painter.clipBoundingRect().intersected(QRectF(plot));
        const qreal nodeExtent = geometry.nodePaintRadius + layout::singlePixel();
        for (const auto &point : points) {
            if (point.tick >= preview.tickBegin && point.tick <= preview.tickEnd)
                continue;
            const QPointF center(tickX(point.tick), valueY(point.value));
            if (nodeClip.intersects(QRectF(center.x() - nodeExtent, center.y() - nodeExtent,
                                           2 * nodeExtent, 2 * nodeExtent)))
                paintAutomationNode(painter, geometry, color, center);
        }
        for (const auto &point : preview.points) {
            const QPointF center(tickX(point.tick), valueY(point.value));
            if (nodeClip.intersects(QRectF(center.x() - nodeExtent, center.y() - nodeExtent,
                                           2 * nodeExtent, 2 * nodeExtent)))
                paintAutomationNode(painter, geometry, previewColor, center);
        }
    }

    const auto &label = hoverState.previewValueLabel;
    if (!label.valid || label.row != rowIndex)
        return;
    painter.setFont(label.font);
    painter.fillRect(label.bounds.adjusted(-layout::singlePixel(), -layout::singlePixel(),
                                           layout::singlePixel(), layout::singlePixel()),
                     themes::color(themes::Role::song_view_piano_roll_accidental_lane));
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, label.text);
}

} // namespace automation::paint
