#include "ui/editordrawer/automationpaint.h"

#include <algorithm>
#include <cmath>

#include <QFontMetricsF>
#include <QLineF>
#include <QPainter>
#include <QPen>
#include <functional>
#include <limits>

#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationhover.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationpencilgesture.h"
#include "ui/editordrawer/automationrows.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace automation::paint {
namespace {

template <class... Ts>
struct Visitor : Ts... {
    using Ts::operator()...;
};
template <class... Ts>
Visitor(Ts...) -> Visitor<Ts...>;

} // namespace

void paintAutomationNode(QPainter &painter, const AutomationGeometry &geometry, const QColor &color,
                         const QPointF &center, bool selected, const QColor &selectedColor,
                         bool dimUnselected, const QColor &dimmedColor)
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

void paintRow(QPainter &painter, const RowPaintParams &ctx, const QRect &bounds,
              const QFont &titleFont, const QFont &captionFont, const QRect &primaryTextBox,
              const QRect &secondaryTextBox, AutomationArea &area, AutomationPage &page,
              const AutomationGeometry &geometry, AutomationRows &rows,
              const AutomationHoverState &hoverState,
              const std::optional<ActiveGesture> &activeGesture, bool pencilMode)
{
    const AutomationProjection &proj = ctx.proj;
    const AutomationRow &row = ctx.row;
    int rowIndex = ctx.rowIndex;
    const QRect &plot = ctx.plot;
    const std::vector<LanePoint> &points = ctx.points;
    const QColor &color = ctx.color;
    bool multipleSelectedNodes = ctx.multipleSelectedNodes;

    painter.save();
    painter.setClipRect(bounds, Qt::IntersectClip);
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(bounds.left(), bounds.bottom(), bounds.right(), bounds.bottom());
    painter.save();
    painter.setClipRect(primaryTextBox.united(secondaryTextBox), Qt::IntersectClip);
    painter.setFont(titleFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    auto &rowText = rows.rowText()[std::size_t(rowIndex)];
    painter.drawText(primaryTextBox, Qt::AlignLeft | Qt::AlignVCenter, rowText.title);
    painter.setFont(captionFont);
    if (!points.empty()) {
        const std::size_t pointCount = points.size();
        const int minimum = proj.rowMinimum(row);
        const int maximum = proj.rowMaximum(row);
        if (rowText.summaryKind != AutomationRows::SummaryKind::Points ||
            rowText.pointCount != pointCount || rowText.minimum != minimum ||
            rowText.maximum != maximum) {
            rowText.secondary =
                AutomationArea::tr("%1 points · %2..%3").arg(pointCount).arg(minimum).arg(maximum);
            rowText.summaryKind = AutomationRows::SummaryKind::Points;
            rowText.pointCount = pointCount;
            rowText.minimum = minimum;
            rowText.maximum = maximum;
        }
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(secondaryTextBox, Qt::AlignLeft | Qt::AlignVCenter, rowText.secondary);
    } else if (row.id.kind == EditorAutomationRowKind::ControlChange) {
        if (rowText.summaryKind != AutomationRows::SummaryKind::EmptyControl) {
            rowText.secondary = AutomationArea::tr("empty · click to add points");
            rowText.summaryKind = AutomationRows::SummaryKind::EmptyControl;
        }
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(secondaryTextBox, Qt::AlignLeft | Qt::AlignVCenter, rowText.secondary);
    } else if (row.id.kind == EditorAutomationRowKind::Voice && page.document()) {
        const int changeCount = int(
            std::count_if(page.model().voices.cbegin(), page.model().voices.cend(),
                          [&page](const VoiceChange &change) {
                              return change.track == page.m_owner.selectionModel().primaryTrack();
                          }));
        if (rowText.summaryKind != AutomationRows::SummaryKind::VoiceChanges ||
            rowText.changeCount != changeCount) {
            rowText.secondary = changeCount ? AutomationArea::tr("%n change(s) · click to edit",
                                                                 nullptr, changeCount)
                                            : AutomationArea::tr("no voice set · click to add");
            rowText.summaryKind = AutomationRows::SummaryKind::VoiceChanges;
            rowText.changeCount = changeCount;
        }
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(secondaryTextBox, Qt::AlignLeft | Qt::AlignVCenter, rowText.secondary);
    }
    painter.restore();
    painter.setClipRect(plot, Qt::IntersectClip);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const bool hostPaintedGrid = page.paintGrid(painter, plot, geometry.plotOrigin);
    if (!hostPaintedGrid) {
        const uint64_t length = page.timeline()->lengthTicks;
        const double pxPerTick =
            page.pxPerBeat() / double(std::max(1u, page.timeline()->ticksPerBeat));
        if (row.id.kind == EditorAutomationRowKind::Voice) {
            if (page.ready()) {
                QColor subdivision = themes::color(themes::Role::song_view_grid);
                subdivision.setAlpha((subdivision.alpha() * 125 + 127) / 255);
                painter.setPen(QPen(subdivision, layout::singlePixel()));
                const double firstVisibleTick =
                    std::max(0.0, page.tickAtContentX(layout::space(layout::Space::Zero)));
                for (uint64_t tick = page.snapTick(firstVisibleTick, false);;) {
                    const auto state = page.gridState(tick, false);
                    const qreal x = page.displayX(tick, geometry.plotOrigin, dpr);
                    if (x > plot.right())
                        break;
                    if (state.snapTicks < state.gridTicks &&
                        pxPerTick * double(state.snapTicks) >= geometry.gridMinimumCellWidth &&
                        x >= plot.left())
                        painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
                    if (tick >= length)
                        break;
                    const uint64_t next = page.snapTick(
                        double(tick) + double(std::max<uint64_t>(1, state.snapTicks)) * 0.75,
                        false);
                    if (next <= tick)
                        break;
                    tick = std::min(next, length);
                }
            }
        }
        painter.setPen(QPen(themes::color(themes::Role::song_view_grid), layout::singlePixel()));
        for (uint64_t tick = 0;;) {
            const qreal x = page.displayX(tick, geometry.plotOrigin, dpr);
            if (x >= plot.left() && x <= plot.right())
                painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
            if (tick >= length)
                break;
            tick = page.nextGridTick(tick, false, length);
        }
    }
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        painter.setFont(captionFont);
        paintVoiceRow(painter, plot, page, geometry, rows);
    } else {
        const auto paintUnchangedCurve = [&] {
            paintCurve(painter, ctx, area, page, geometry, rows);
        };
        if (activeGesture) {
            std::visit(
                Visitor{[&](const NodeDragGesture &gesture) {
                            if (gesture.points.size() > 1) {
                                if (rowIndex < int(gesture.previewPoints.size()) &&
                                    !gesture.previewPoints[rowIndex].empty()) {
                                    RowPaintParams previewCtx{proj,
                                                              row,
                                                              rowIndex,
                                                              plot,
                                                              gesture.previewPoints[rowIndex],
                                                              color,
                                                              ctx.usedTrackMask,
                                                              nullptr,
                                                              nullptr,
                                                              multipleSelectedNodes};
                                    paintCurve(painter, previewCtx, area, page, geometry, rows);
                                } else
                                    paintUnchangedCurve();
                            } else if (rowIndex == gesture.row) {
                                const auto &point = gesture.points[gesture.grabbedPoint];
                                const ValuePoint original = point.original;
                                RowPaintParams dragCtx{proj,
                                                       row,
                                                       rowIndex,
                                                       plot,
                                                       points,
                                                       color,
                                                       ctx.usedTrackMask,
                                                       &original,
                                                       &point.current,
                                                       multipleSelectedNodes};
                                paintCurve(painter, dragCtx, area, page, geometry, rows);
                            } else {
                                paintUnchangedCurve();
                            }
                        },
                        [&](const SweepGesture &) { paintUnchangedCurve(); },
                        [&](const PencilGesture &gesture) {
                            if (rowIndex == gesture.row)
                                paintPencilPreview(painter, ctx, gesture, page, geometry,
                                                   hoverState);
                            else
                                paintUnchangedCurve();
                        }},
                *activeGesture);
        } else {
            paintUnchangedCurve();
        }
        if (rowIndex == hoverState.hover.row && hoverState.hover.hasPoint) {
            const qreal nodeRadius =
                geometry.nodePaintRadius + geometry.nodeOutlineDipWidth + layout::singlePixel();
            const QPointF center(
                page.displayX(hoverState.hover.point.tick, geometry.plotOrigin, dpr),
                proj.pointY(row, rowIndex, hoverState.hover.point.value));
            const bool antialiasing = painter.testRenderHint(QPainter::Antialiasing);
            painter.setRenderHint(QPainter::Antialiasing, true);
            painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline),
                                2 * layout::singlePixel()));
            painter.setBrush(Qt::NoBrush);
            painter.drawEllipse(center, nodeRadius, nodeRadius);
            painter.setRenderHint(QPainter::Antialiasing, antialiasing);
        }
    }
    if (activeGesture) {
        const auto valueY = [&](int value) { return proj.pointY(row, rowIndex, value); };
        const auto tickX = [&](uint64_t tick) {
            return page.displayX(tick, geometry.plotOrigin, dpr);
        };
        const auto paintCurrent = [&](const ValuePoint &current) {
            const qreal x = tickX(current.tick);
            const int y = valueY(current.value);
            paintAutomationNode(painter, geometry,
                                themes::color(themes::Role::song_view_edit_preview_outline),
                                QPointF(x, y));
            const auto &label = hoverState.previewValueLabel;
            if (!label.valid || label.row != rowIndex)
                return;
            painter.setFont(label.font);
            painter.fillRect(label.bounds.adjusted(-layout::singlePixel(), -layout::singlePixel(),
                                                   layout::singlePixel(), layout::singlePixel()),
                             themes::color(themes::Role::song_view_piano_roll_accidental_lane));
            painter.setPen(themes::color(themes::Role::song_view_primary_text));
            painter.drawText(label.rect, Qt::AlignHCenter | Qt::AlignVCenter, label.text);
        };
        painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline),
                            layout::singlePixel()));
        painter.setBrush(Qt::NoBrush);
        std::visit(
            Visitor{[&](const NodeDragGesture &gesture) {
                        if (gesture.points.size() > 1 || rowIndex == gesture.row)
                            paintNodeDragPreview(painter, ctx, gesture, area, page, geometry,
                                                 hoverState);
                    },
                    [&](const SweepGesture &gesture) {
                        if (rowIndex != gesture.row)
                            return;
                        if (gesture.mode == SweepGesture::Mode::Ramp) {
                            painter.drawLine(
                                QLineF(tickX(gesture.anchor.tick), valueY(gesture.anchor.value),
                                       tickX(gesture.current.tick), valueY(gesture.current.value)));
                        } else if (gesture.points.size() > 1) {
                            for (size_t index = 0; index + 1 < gesture.points.size(); ++index) {
                                const int y = valueY(gesture.points[index].value);
                                painter.drawLine(QLineF(tickX(gesture.points[index].tick), y,
                                                        tickX(gesture.points[index + 1].tick), y));
                                painter.drawLine(QLineF(tickX(gesture.points[index + 1].tick), y,
                                                        tickX(gesture.points[index + 1].tick),
                                                        valueY(gesture.points[index + 1].value)));
                            }
                        }
                        paintCurrent(gesture.current);
                    },
                    [&](const PencilGesture &) {}},
            *activeGesture);
    }
    paintHover(painter, ctx, page, geometry, rows, hoverState, pencilMode);
    const qreal cursorX = page.displayX(page.liveState().editCursorTick, geometry.plotOrigin, dpr);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                        Qt::DashLine));
    painter.drawLine(QPointF(cursorX, plot.top()), QPointF(cursorX, plot.bottom()));
    painter.restore();
}

void paintHover(QPainter &painter, const RowPaintParams &ctx, AutomationPage &page,
                const AutomationGeometry &geometry, const AutomationRows &rows,
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
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                            layout::singlePixel(), Qt::DotLine));
        painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
        return;
    }
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
                          const NodeDragGesture &gesture, AutomationArea &area,
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
    const AutomationLaneEdit::Completion &preview = gesture.stroke.preview();
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

void paintCurve(QPainter &painter, const RowPaintParams &ctx, AutomationArea &area,
                AutomationPage &page, const AutomationGeometry &geometry,
                const AutomationRows &rows)
{
    const std::vector<LanePoint> &points = ctx.points;
    if (points.empty())
        return;
    const AutomationProjection &proj = ctx.proj;
    const AutomationRow &row = ctx.row;
    int rowIndex = ctx.rowIndex;
    const QRect &plot = ctx.plot;
    const QColor &color = ctx.color;
    const ValuePoint *omitted = ctx.omitted;
    const ValuePoint *replacement = ctx.replacement;
    const auto valueY = [&](int value) { return qRound(proj.pointY(row, rowIndex, value)); };
    const auto isOmitted = [&](const LanePoint &point) {
        if (omitted && point.tick == omitted->tick && point.value == omitted->value)
            return true;
        return omitted && replacement && replacement->tick != omitted->tick &&
               point.tick == replacement->tick;
    };
    const qreal dpr = painter.device()->devicePixelRatioF();
    const qreal curveStrokeWidth = layout::singlePixel() + layout::singlePixel();
    const auto &timeSelection = page.m_owner.selectionModel().timeSelection();
    const auto lane = rows.rowIdentity(row);
    const bool selectedLane =
        timeSelection.active() && page.m_owner.selectionModel().timeSelectionCoversLane(
                                      lane.first, lane.second, ctx.usedTrackMask);
    const QColor curveColor =
        ctx.multipleSelectedNodes && !selectedLane ? area.palette().mid().color() : color;
    painter.setPen(QPen(curveColor, curveStrokeWidth));
    for (size_t index = 0; index < points.size(); ++index) {
        const bool currentOmitted = isOmitted(points[index]);
        const bool nextOmitted = index + 1 < points.size() && isOmitted(points[index + 1]);
        if (currentOmitted || nextOmitted)
            continue;
        const qreal x0 = page.displayX(points[index].tick, geometry.plotOrigin, dpr);
        const qreal x1 = index + 1 < points.size()
                             ? page.displayX(points[index + 1].tick, geometry.plotOrigin, dpr)
                             : plot.right();
        if (x1 < plot.left() || x0 > plot.right())
            continue;
        const int y = valueY(points[index].value);
        painter.drawLine(QLineF(x0, y, x1, y));
        if (index + 1 < points.size())
            painter.drawLine(QLineF(x1, y, x1, valueY(points[index + 1].value)));
    }
    if (!proj.nodeMarkersVisible())
        return;
    paintCurveNodes(painter, ctx, area, page, geometry, rows);
}

void paintCurveNodes(QPainter &painter, const RowPaintParams &ctx, AutomationArea &area,
                     AutomationPage &page, const AutomationGeometry &geometry,
                     const AutomationRows &rows)
{
    const AutomationProjection &proj = ctx.proj;
    const AutomationRow &row = ctx.row;
    int rowIndex = ctx.rowIndex;
    const QRect &plot = ctx.plot;
    const std::vector<LanePoint> &points = ctx.points;
    const QColor &color = ctx.color;
    const ValuePoint *omitted = ctx.omitted;
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto valueY = [&](int value) { return qRound(proj.pointY(row, rowIndex, value)); };
    const QRectF nodeClip = painter.clipBoundingRect().intersected(QRectF(plot));
    const qreal nodeExtent =
        std::max(geometry.nodePaintRadius, geometry.selectedNodeRingRadius) + layout::singlePixel();
    const auto lane = rows.rowIdentity(row);
    const auto &ownerSelection = page.m_owner.selectionModel().timeSelection();
    const SongDocument::TimeRange timeRange{ownerSelection.startTick, ownerSelection.endTick};
    const bool committedRange =
        ownerSelection.active() && page.m_owner.selectionModel().timeSelectionCoversLane(
                                       lane.first, lane.second, ctx.usedTrackMask);
    const bool provisionalLane = area.bandPreviewContainsRow(rowIndex);
    const bool selectedLane = committedRange || provisionalLane;
    const bool dimLane = ctx.multipleSelectedNodes && !selectedLane;
    const QColor selectedColor = area.palette().highlight().color();
    const QColor dimmedColor = area.palette().mid().color();
    // Selected nodes paint after unselected so rings sit on top.
    const auto paintPass = [&](bool selectedPass) {
        for (const auto &point : points) {
            if (omitted && point.tick == omitted->tick && point.value == omitted->value)
                continue;
            const bool selected = (committedRange && timeRange.contains(point.tick)) ||
                                  area.bandPreviewContains(rowIndex, point.tick);
            if (selected != selectedPass)
                continue;
            const qreal x = page.displayX(point.tick, geometry.plotOrigin, dpr);
            const qreal y = valueY(point.value);
            if (!nodeClip.intersects(
                    QRectF(x - nodeExtent, y - nodeExtent, 2 * nodeExtent, 2 * nodeExtent)))
                continue;
            paintAutomationNode(painter, geometry, color, QPointF(x, y), selected, selectedColor,
                                dimLane, dimmedColor);
        }
    };
    paintPass(false);
    paintPass(true);
}

namespace {
struct VoiceLabelLayout {
    QString text;
    QRectF rect;
    bool offscreen = true;
};

std::vector<VoiceLabelLayout> layoutVoiceLabels(const QRect &plot, const SongViewModel &model,
                                                int track, const AutomationRows &rows,
                                                const QFontMetricsF &fm, qreal pad, qreal gap,
                                                qreal stairStep, bool canStair, qreal centerY,
                                                std::function<qreal(uint32_t)> displayX)
{
    std::vector<VoiceLabelLayout> out;
    out.reserve(model.voices.size());
    qreal lastXEnd = -std::numeric_limits<qreal>::infinity();
    bool stairUp = true;
    for (const auto &change : model.voices) {
        if (change.track != track)
            continue;
        const qreal labelX = displayX(change.tick) + pad;
        QString text = rows.voicePaintTextFor(change.program).label;
        if (text.isEmpty())
            text = AutomationArea::tr("No voice");
        const qreal maxW = std::max<qreal>(0, plot.right() - labelX);
        if (fm.horizontalAdvance(text) > maxW && maxW > 0)
            text = fm.elidedText(text, Qt::ElideRight, int(std::floor(maxW)));
        const qreal w = std::min(fm.horizontalAdvance(text), maxW);
        const bool offscreen = labelX + w < plot.left() || labelX > plot.right() || w <= 0;
        qreal y = centerY;
        if (!offscreen) {
            const bool close = labelX < lastXEnd + gap;
            if (close && canStair)
                stairUp = !stairUp;
            else
                stairUp = true;
            if (close && canStair)
                y = stairUp ? centerY - stairStep : centerY + stairStep;
            y = std::clamp(y, qreal(plot.top()) + pad, qreal(plot.bottom()) - fm.height() - pad);
            lastXEnd = labelX + w + gap;
        }
        out.push_back({std::move(text), QRectF(labelX, y, w, fm.height()), offscreen});
    }
    return out;
}
} // namespace

void paintVoiceRow(QPainter &painter, const QRect &plot, AutomationPage &page,
                   const AutomationGeometry &geometry, AutomationRows &rows)
{
    const int track = page.m_owner.selectionModel().primaryTrack();
    const auto &live = page.liveState();
    const double contextTick =
        live.playback.playing ? live.playback.playheadTick : double(live.editCursorTick);
    const auto context =
        page.voiceContext(static_cast<uint64_t>(std::round(std::max(0.0, contextTick))));
    const QString contextText = context.voiceSlot >= 0 && context.voiceSlot < VOICEGROUP_SIZE
                                    ? rows.voicePaintTextFor(context.voiceSlot).label
                                    : AutomationArea::tr("No voice");
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    painter.drawText(
        plot.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                      -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
        Qt::AlignRight | Qt::AlignVCenter, contextText);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const qreal pad = layout::space(layout::Space::One);
    const qreal gap =
        std::max<qreal>(geometry.hoverPaintPadding, layout::space(layout::Space::One));
    const QFontMetricsF fm(painter.font());
    const qreal labelH = fm.height();
    const qreal centerY = plot.center().y() - labelH / 2.0;
    const qreal stairStep = std::min<qreal>(layout::space(layout::Space::Four),
                                            (plot.height() - labelH - 2 * pad) / 2.0);
    const bool canStair = stairStep > 1.0;
    auto displayX = [&](uint32_t tick) { return page.displayX(tick, geometry.plotOrigin, dpr); };
    const auto layouts = layoutVoiceLabels(plot, page.model(), track, rows, fm, pad, gap, stairStep,
                                           canStair, centerY, displayX);
    const QColor trackColor = themes::trackIdentityColor(track % themes::trackIdentityColorCount);
    const qreal markerW = layout::singlePixel() + layout::singlePixel();
    for (const auto &lt : layouts) {
        const qreal x = lt.rect.left() - pad;
        painter.setPen(QPen(trackColor, markerW));
        painter.drawLine(QPointF(x, plot.top() + pad), QPointF(x, plot.bottom() - pad));
    }
    const QColor primary = themes::color(themes::Role::song_view_primary_text);
    painter.setPen(primary);
    for (const auto &lt : layouts)
        if (!lt.offscreen)
            painter.drawText(lt.rect, Qt::AlignLeft | Qt::AlignVCenter, lt.text);
}

} // namespace automation::paint
