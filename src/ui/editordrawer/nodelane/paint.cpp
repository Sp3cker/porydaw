#include "ui/editordrawer/nodelane/paint.h"

#include <algorithm>

#include <QPainter>
#include <QPen>

#include "ui/editordrawer/automationpaint.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace nodelane {

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
            automation::paint::paintAutomationNode(
                painter, geometry, themes::color(themes::Role::song_view_edit_preview_outline),
                center);
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
            automation::paint::paintAutomationNode(
                painter, geometry, themes::color(themes::Role::song_view_edit_preview_outline),
                center);
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

} // namespace nodelane
