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
    const auto selectedRange = [&] {
        if (m_band.active)
            return automation::paint::TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
        if (!hasTimeSelection())
            return std::optional<automation::paint::TickRange>{};
        const auto &selection = m_page->m_owner.selectionModel().timeSelection();
        return automation::paint::TickRange::orderedNonEmpty(selection.startTick,
                                                             selection.endTick);
    }();

    const QRect band = m_expanded ? m_body : m_header;
    painter.save();
    painter.setClipRect(band, Qt::IntersectClip);
    painter.fillRect(band, themes::color(themes::Role::song_view_piano_roll_background));
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(band.left(), band.bottom(), band.right(), band.bottom());
    painter.restore();
    if (!m_expanded && selectedRange)
        automation::paint::paintSelectionReticle(painter, *selectedRange, projection, band, dpr);
    painter.save();
    // The label gutter spans the whole drawer; clip it to this lane's band so
    // header text never bleeds into neighbouring rows.
    painter.setClipRect(QRect(labelGutter.x(), band.top(), labelGutter.width(), band.height()),
                        Qt::IntersectClip);
    // The collapse strip is the top slice of the band in both states, so the
    // caret and label stay in-line and never shift when toggling.
    const QRect strip(band.left(), band.top(), band.width(), geometry.addLaneStripHeight);
    const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
    const QRect arrow(labelGutter.left(), strip.center().y() - arrowSize / 2, arrowSize, arrowSize);
    const QPolygon triangle = m_expanded ? QPolygon{{arrow.left(), arrow.top()},
                                                    {arrow.right(), arrow.top()},
                                                    {arrow.center().x(), arrow.bottom()}}
                                         : QPolygon{{arrow.left(), arrow.top()},
                                                    {arrow.right(), arrow.center().y()},
                                                    {arrow.left(), arrow.bottom()}};
    painter.setPen(Qt::NoPen);
    painter.setBrush(themes::color(themes::Role::song_view_primary_text));
    painter.drawPolygon(triangle);
    const QRect textBounds(
        labelGutter.x() + arrowSize + layout::space(layout::Space::One), strip.top(),
        std::max(0, labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
        strip.height());
    painter.setFont(m_expanded ? titleFont : captionFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(textBounds, Qt::AlignLeft | Qt::AlignVCenter,
                     QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)"));
    if (m_expanded) {
        const QRect summaryBounds(textBounds.x(), strip.top() + strip.height(), textBounds.width(),
                                  strip.height());
        painter.setFont(captionFont);
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(summaryBounds, Qt::AlignLeft | Qt::AlignVCenter,
                         QCoreApplication::translate("AutomationCanvas", "%n point(s)", nullptr,
                                                     int(points.size())));
    }
    painter.restore();
    if (!m_expanded)
        return;

    const QRect plot(geometry.plotOrigin, m_body.top(),
                     std::max(0, m_body.width() - geometry.plotOrigin), m_body.height());
    painter.save();
    painter.setClipRect(plot, Qt::IntersectClip);
    if (selectedRange)
        automation::paint::paintSelectionReticle(painter, *selectedRange, projection, m_body, dpr);
    if (!m_page->paintGrid(painter, plot, geometry.plotOrigin))
        automation::paint::paintPlainGridFallback(painter, plot, *m_page, geometry.plotOrigin, dpr);
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
    std::vector<TempoPoint> previewCurve;
    const NodeDragGesture *nodeGesture = nullptr;
    const SweepGesture *sweepGesture = nullptr;
    if (m_activeGesture) {
        nodeGesture = std::get_if<NodeDragGesture>(&*m_activeGesture);
        sweepGesture = std::get_if<SweepGesture>(&*m_activeGesture);
    }
    if (nodeGesture && !nodeGesture->previewPoints.empty()) {
        previewCurve.reserve(nodeGesture->previewPoints.front().size());
        for (const ValuePoint &point : nodeGesture->previewPoints.front())
            previewCurve.push_back(
                {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
    }
    const auto &curvePoints = previewCurve.empty() ? points : previewCurve;
    paintStepCurve(painter, curvePoints, plot, projection, color, dpr, pointY, initial);
    const QColor selectedColor = m_page->palette().highlight().color();
    const int selectedNodeCount = int(
        std::count_if(curvePoints.cbegin(), curvePoints.cend(), [this](const TempoPoint &point) {
            return pointInTimeSelection(point.tick);
        }));
    for (const TempoPoint &point : curvePoints) {
        const bool selected = pointInTimeSelection(point.tick);
        automation::paint::paintAutomationNode(
            painter, geometry, color, QPointF(projection.displayX(point.tick, dpr), pointY(point)),
            selected, selectedColor, selectedNodeCount > 1 && !selected, color);
    }
    if (nodeGesture) {
        for (const NodeDrag &point : nodeGesture->points) {
            const TempoPoint preview{
                point.current.tick,
                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.current.value)};
            automation::paint::paintAutomationNode(
                painter, geometry, themes::color(themes::Role::song_view_edit_preview_outline),
                QPointF(projection.displayX(preview.tick, dpr), pointY(preview)), true,
                selectedColor);
        }
    } else if (sweepGesture) {
        const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
        if (sweepGesture->mode == SweepGesture::Mode::Ramp) {
            const TempoPoint anchor{
                sweepGesture->anchor.tick,
                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(sweepGesture->anchor.value)};
            const TempoPoint current{
                sweepGesture->current.tick,
                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(sweepGesture->current.value)};
            painter.setPen(QPen(previewColor, layout::singlePixel()));
            painter.drawLine(QLineF(projection.displayX(anchor.tick, dpr), pointY(anchor),
                                    projection.displayX(current.tick, dpr), pointY(current)));
        } else if (!sweepGesture->points.empty()) {
            std::vector<TempoPoint> sweepPoints;
            sweepPoints.reserve(sweepGesture->points.size());
            for (const ValuePoint &point : sweepGesture->points)
                sweepPoints.push_back(
                    {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
            paintStepCurve(painter, sweepPoints, plot, projection, previewColor, dpr, pointY);
        }
        const TempoPoint current{
            sweepGesture->current.tick,
            CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(sweepGesture->current.value)};
        automation::paint::paintAutomationNode(
            painter, geometry, previewColor,
            QPointF(projection.displayX(current.tick, dpr), pointY(current)));
    }
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
    automation::paint::paintEditCursor(painter, plot, cursor);
    painter.restore();
}
