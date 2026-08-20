#include "ui/editordrawer/tempolane.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

#include <QCoreApplication>
#include <QFontMetricsF>
#include <QLineF>
#include <QPainter>
#include <QPen>
#include <QPolygon>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationpaint.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/theme/themeruntime.h"

namespace {

template <class Points, class ValueY>
void paintStepCurve(QPainter &painter, const Points &points, const QRect &plot,
                    const AutomationProjection &projection, const QColor &color, qreal dpr,
                    ValueY &&valueY,
                    const std::optional<std::pair<uint64_t, qreal>> &initial = std::nullopt)
{
    if (points.empty())
        return;
    painter.setPen(QPen(color, layout::singlePixel() + layout::singlePixel()));
    if (initial) {
        const qreal x = projection.displayX(points.front().tick, dpr);
        const qreal y = valueY(points.front());
        painter.drawLine(
            QLineF(projection.displayX(initial->first, dpr), initial->second, x, initial->second));
        if (y != initial->second)
            painter.drawLine(QLineF(x, initial->second, x, y));
    }
    for (std::size_t index = 0; index < points.size(); ++index) {
        const qreal x0 = projection.displayX(points[index].tick, dpr);
        const qreal x1 = index + 1 < points.size()
                             ? projection.displayX(points[index + 1].tick, dpr)
                             : plot.right();
        if (x1 < plot.left() || x0 > plot.right())
            continue;
        const qreal y = valueY(points[index]);
        painter.drawLine(QLineF(x0, y, x1, y));
        if (index + 1 < points.size())
            painter.drawLine(QLineF(x1, y, x1, valueY(points[index + 1])));
    }
}

} // namespace

void TempoLane::paint(QPainter &painter, const AutomationGeometry &geometry,
                      const QRect &labelGutter, const QFont &titleFont, const QFont &captionFont)
{
    if (!m_page || !m_page->ready() || !m_page->timeline() || !m_page->document())
        return;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto &points = m_page->document()->tempoPoints();
    painter.save();
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(m_header.left(), m_header.bottom(), m_header.right(), m_header.bottom());
    if (hasTimeSelection()) {
        const auto &selection = m_page->m_owner.selectionModel().timeSelection();
        const qreal first = projection.displayX(selection.startTick, dpr);
        const qreal last = projection.displayX(selection.endTick, dpr);
        const QRect selectionBounds = m_expanded ? m_body : m_header;
        songview::paintSelectionReticle(painter,
                                        QRectF(std::min(first, last), selectionBounds.top(),
                                               std::abs(first - last), selectionBounds.height()));
    }
    const int arrowSize = std::max(layout::fontPx(0.5), m_header.height() / 3);
    const QRect arrow(labelGutter.left(), m_header.center().y() - arrowSize / 2, arrowSize,
                      arrowSize);
    const QPolygon triangle = m_expanded ? QPolygon{{arrow.left(), arrow.top()},
                                                    {arrow.right(), arrow.top()},
                                                    {arrow.center().x(), arrow.bottom()}}
                                         : QPolygon{{arrow.left(), arrow.top()},
                                                    {arrow.right(), arrow.center().y()},
                                                    {arrow.left(), arrow.bottom()}};
    painter.setPen(Qt::NoPen);
    painter.setBrush(themes::color(themes::Role::song_view_primary_text));
    painter.drawPolygon(triangle);
    const QRect title(
        labelGutter.x() + arrowSize + layout::space(layout::Space::One), m_header.top(),
        std::max(0, labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
        m_header.height());
    painter.setFont(titleFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(title, Qt::AlignLeft | Qt::AlignVCenter,
                     QCoreApplication::translate("AutomationArea", "Tempo (BPM)"));
    painter.setFont(captionFont);
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    painter.drawText(
        m_header.adjusted(geometry.plotOrigin, 0, -layout::space(layout::Space::One), 0),
        Qt::AlignRight | Qt::AlignVCenter,
        QCoreApplication::translate("AutomationArea", "%n point(s)", nullptr, int(points.size())));
    if (!m_expanded) {
        painter.restore();
        return;
    }
    const QRect plot(geometry.plotOrigin, m_body.top(),
                     std::max(0, m_body.right() - geometry.plotOrigin + 1), m_body.height());
    painter.setClipRect(m_body, Qt::IntersectClip);
    if (!m_page->paintGrid(painter, plot, geometry.plotOrigin)) {
        painter.setPen(QPen(themes::color(themes::Role::song_view_grid), layout::singlePixel()));
        const uint64_t length = m_page->timeline()->lengthTicks;
        for (uint64_t tick = 0;;) {
            const qreal x = projection.displayX(tick, dpr);
            if (x >= plot.left() && x <= plot.right())
                painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
            if (tick >= length)
                break;
            tick = m_page->nextGridTick(tick, false, length);
        }
    }
    const QColor color = themes::color(themes::Role::song_view_automation_tempo_curve);
    const auto pointY = [this, &geometry](const TempoPoint &point) {
        return AutomationProjection::valueY(
            m_body, geometry, CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm,
            CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote));
    };
    const std::optional<std::pair<uint64_t, qreal>> initial{
        std::in_place, uint64_t{0},
        AutomationProjection::valueY(m_body, geometry, CoreTimeDefaults::kMinTempoBpm,
                                     CoreTimeDefaults::kMaxTempoBpm, CoreTimeDefaults::kTempoBpm)};
    paintStepCurve(painter, points, plot, projection, color, dpr, pointY, initial);
    for (const TempoPoint &point : points)
        automation::paint::paintAutomationNode(
            painter, geometry, color, QPointF(projection.displayX(point.tick, dpr), pointY(point)));
    if (m_drag)
        automation::paint::paintAutomationNode(
            painter, geometry, themes::color(themes::Role::song_view_edit_preview_outline),
            QPointF(projection.displayX(m_drag->current.tick, dpr), pointY(m_drag->current)));
    if (m_draw)
        for (const TempoPoint &point : m_draw->points)
            automation::paint::paintAutomationNode(
                painter, geometry, themes::color(themes::Role::song_view_edit_preview_outline),
                QPointF(projection.displayX(point.tick, dpr), pointY(point)));
    if (m_hoveredPoint && *m_hoveredPoint < points.size()) {
        const TempoPoint &point = points[*m_hoveredPoint];
        const QPointF center(projection.displayX(point.tick, dpr), pointY(point));
        const QString text = bpmText(point.microsecondsPerQuarterNote);
        const QFontMetricsF metrics(captionFont);
        const QRectF textBounds = metrics.boundingRect(text);
        const QRectF label(center.x() + layout::space(layout::Space::One),
                           center.y() - textBounds.height() - layout::space(layout::Space::One),
                           textBounds.width() + 2 * layout::space(layout::Space::One),
                           textBounds.height());
        painter.fillRect(label, themes::color(themes::Role::song_view_piano_roll_accidental_lane));
        painter.setFont(captionFont);
        painter.setPen(themes::color(themes::Role::song_view_primary_text));
        painter.drawText(label, Qt::AlignHCenter | Qt::AlignVCenter, text);
    }
    const qreal cursor = projection.displayX(m_page->liveState().editCursorTick, dpr);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                        Qt::DashLine));
    painter.drawLine(QPointF(cursor, plot.top()), QPointF(cursor, plot.bottom()));
    painter.restore();
}
