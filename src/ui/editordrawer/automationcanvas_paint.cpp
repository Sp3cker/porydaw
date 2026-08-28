#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <optional>
#include <ranges>
#include <span>

#include <QPainter>
#include <QPen>

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/nodelane/paint.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

// PaintFrame and LanePaintItem live only for one synchronous paintContent call.
// Gesture pointers borrow alternatives in m_activeGesture; font/layout references
// borrow AutomationCanvas caches. No paint helper may retain either object. The two
// selected ranges describe the same half-open interval: selectedTickRange is the
// NodeLanePaint form, while selectedRange is the non-empty reticle form.
struct AutomationCanvas::PaintFrame {
    const AutomationProjection projection;
    const qreal devicePixelRatio;
    const std::optional<std::pair<uint64_t, uint64_t>> selectedTickRange;
    const std::optional<TickRange> selectedRange;
    const QColor selectedColor;
    const QColor dimmedColor;
    const uint64_t bandFirst;
    const uint64_t bandLast;
    const NodeDragGesture *const nodeDrag;
    const PhantomGesture *const phantomGesture;
    const SweepGesture *const sweep;
    const PencilGesture *const pencil;
    const bool pencilMode;
    const bool multipleSelectedNodes;
    const QFont &titleFont;
    const QFont &captionFont;
    const layout::TwoLineTextLayout &textLayout;
};

struct AutomationCanvas::LanePaintItem {
    const LaneHandle handle;
    const NodeLaneSlot &slot;
    const std::span<const NodePoint> points;
    const bool selectedLane;
    const bool selectedNodesLane;
    const bool bandLane;
    const QRect reticleBounds;
};

std::optional<AutomationCanvas::TickRange>
AutomationCanvas::TickRange::orderedNonEmpty(uint64_t firstTick, uint64_t secondTick) noexcept
{
    const uint64_t first = std::min(firstTick, secondTick);
    const uint64_t last = std::max(firstTick, secondTick);
    if (first == last)
        return std::nullopt;
    return TickRange{first, last};
}

void AutomationCanvas::paintPlainGridFallback(QPainter &painter, const QRect &plot,
                                              AutomationPage &page, qreal plotOriginX, qreal dpr)
{
    const uint64_t length = page.timeline()->lengthTicks;
    painter.setPen(QPen(themes::color(themes::Role::song_view_grid), layout::singlePixel()));
    for (uint64_t tick = 0;;) {
        const qreal x = page.displayX(tick, plotOriginX, dpr);
        if (x >= plot.left() && x <= plot.right())
            painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
        if (tick >= length)
            break;
        tick = page.nextGridTick(tick, false, length);
    }
}

void AutomationCanvas::paintEditCursor(QPainter &painter, const QRect &plot, qreal cursorX)
{
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                        Qt::DashLine));
    painter.drawLine(QPointF(cursorX, plot.top()), QPointF(cursorX, plot.bottom()));
}

void AutomationCanvas::paintSelectionReticle(QPainter &painter, const TickRange &range,
                                             const AutomationProjection &projection,
                                             const QRect &bounds, qreal devicePixelRatio)
{
    const qreal first = projection.displayX(range.firstTick, devicePixelRatio);
    const qreal last = projection.displayX(range.lastTick, devicePixelRatio);
    painter.save();
    painter.setClipRect(bounds, Qt::IntersectClip);
    songview::paintSelectionReticle(painter,
                                    QRectF(first, bounds.top(), last - first, bounds.height()));
    painter.restore();
}

void AutomationCanvas::rebuildFontCache()
{
    m_laneTitleFont = typography::bold(typography::caption(font()));
    m_laneCaptionFont = typography::regular(typography::caption(font()));
    m_laneTextLayout = layout::twoLineText(m_laneTitleFont, m_laneTitleFont, m_laneCaptionFont,
                                           layout::Space::Zero);
}

AutomationCanvas::LanePointSnapshots AutomationCanvas::snapshotLanePoints() const
{
    auto pointsBySlot = LanePointSnapshots(m_nodeStack.size());
    for (auto index = std::size_t{0}; index < m_nodeStack.size(); ++index) {
        const auto &slot = m_nodeStack[index];
        if (slot.lane)
            pointsBySlot[index] = slot.lane->points();
    }
    return pointsBySlot;
}

AutomationCanvas::PaintFrame
AutomationCanvas::preparePaintFrame(qreal devicePixelRatio,
                                    std::span<const std::vector<NodePoint>> pointsBySlot) const
{
    const auto selectedTickRange = [&]() -> std::optional<std::pair<uint64_t, uint64_t>> {
        if (m_band.active) {
            const auto range = TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
            if (!range)
                return std::nullopt;
            return std::pair{range->firstTick, range->lastTick};
        }
        return m_laneSelection.activeTickRange();
    }();
    const auto selectedPair = selectedTickRange.value_or(std::pair<uint64_t, uint64_t>{});
    const auto selectedRange = TickRange::orderedNonEmpty(selectedPair.first, selectedPair.second);
    const NodeDragGesture *nodeDrag = nullptr;
    const PhantomGesture *phantomGesture = nullptr;
    const SweepGesture *sweep = nullptr;
    const PencilGesture *pencil = nullptr;
    if (m_activeGesture) {
        nodeDrag = std::get_if<NodeDragGesture>(&*m_activeGesture);
        phantomGesture = std::get_if<PhantomGesture>(&*m_activeGesture);
        sweep = std::get_if<SweepGesture>(&*m_activeGesture);
        pencil = std::get_if<PencilGesture>(&*m_activeGesture);
    }
    auto selectedCount = 0;
    auto multipleSelectedNodes = false;
    if (selectedTickRange) {
        // The index view keeps each slot aligned with its one snapshot. The nested
        // scans preserve slot/point order and stop immediately on the second match.
        const auto slotIndices = std::views::iota(std::size_t{0}, m_nodeStack.size());
        multipleSelectedNodes = std::ranges::any_of(slotIndices, [&](std::size_t index) {
            const auto &slot = m_nodeStack[index];
            const LaneHandle handle{int(index)};
            if (!m_laneSelection.coversNodes(slot.id) && !bandPreviewContainsLane(handle))
                return false;
            return std::ranges::any_of(pointsBySlot[index], [&](const NodePoint &point) {
                if (point.tick < selectedTickRange->first ||
                    point.tick >= selectedTickRange->second)
                    return false;
                return ++selectedCount > 1;
            });
        });
    }
    return PaintFrame{
        .projection = projection(),
        .devicePixelRatio = devicePixelRatio,
        .selectedTickRange = selectedTickRange,
        .selectedRange = selectedRange,
        .selectedColor = palette().highlight().color(),
        .dimmedColor = palette().mid().color(),
        .bandFirst = std::min(m_band.startTick, m_band.endTick),
        .bandLast = std::max(m_band.startTick, m_band.endTick),
        .nodeDrag = nodeDrag,
        .phantomGesture = phantomGesture,
        .sweep = sweep,
        .pencil = pencil,
        .pencilMode = m_pencilMode,
        .multipleSelectedNodes = multipleSelectedNodes,
        .titleFont = m_laneTitleFont,
        .captionFont = m_laneCaptionFont,
        .textLayout = *m_laneTextLayout,
    };
}

void AutomationCanvas::paintLaneBody(QPainter &painter, const PaintFrame &frame,
                                     const LanePaintItem &item, const QColor &color,
                                     bool preparedPreviewCurve)
{
    const QRect plot(m_geometry.plotOrigin, item.slot.body.top(),
                     std::max(0, width() - m_geometry.plotOrigin), item.slot.body.height());
    painter.save();
    painter.setClipRect(plot, Qt::IntersectClip);
    if (!m_page->paintGrid(painter, plot, m_geometry.plotOrigin))
        paintPlainGridFallback(painter, plot, *m_page, m_geometry.plotOrigin,
                               frame.devicePixelRatio);
    painter.restore();
    std::optional<nodelane::OriginPhantomPaint> phantom;
    if (frame.phantomGesture && frame.phantomGesture->lane == item.handle) {
        phantom = nodelane::OriginPhantomPaint{
            OriginPhantom{item.handle, frame.phantomGesture->point.current,
                          frame.phantomGesture->point.minimumValue,
                          frame.phantomGesture->point.maximumValue},
            frame.phantomGesture->point.original};
    } else if (const auto current = originPhantom(item.handle, frame.projection, item.points)) {
        phantom = nodelane::OriginPhantomPaint{*current, std::nullopt};
    }
    nodelane::paintNodeLane(
        painter, nodelane::NodeLanePaint{
                     .lane = *item.slot.lane,
                     .points = item.points,
                     .body = item.slot.body,
                     .geometry = m_geometry,
                     .projection = frame.projection,
                     .color = color,
                     .handle = item.handle,
                     .hoverState = m_hoverState,
                     .nodeDrag = frame.nodeDrag,
                     .sweep = frame.sweep,
                     .pencil = frame.pencil,
                     .pencilMode = frame.pencilMode,
                     .multipleSelectedNodes = frame.multipleSelectedNodes,
                     .selectedLane = item.selectedLane,
                     .selectedTickRange = item.selectedNodesLane
                                              ? frame.selectedTickRange
                                              : std::optional<std::pair<uint64_t, uint64_t>>{},
                     .bandLane = item.bandLane,
                     .bandFirstTick = frame.bandFirst,
                     .bandLastTick = frame.bandLast,
                     .preparedPreviewCurve = preparedPreviewCurve,
                     .selectedColor = frame.selectedColor,
                     .dimmedColor = preparedPreviewCurve ? color : frame.dimmedColor,
                     .phantom = phantom,
                 });
    painter.save();
    painter.setClipRect(plot, Qt::IntersectClip);
    paintEditCursor(
        painter, plot,
        frame.projection.displayX(m_page->liveState().editCursorTick, frame.devicePixelRatio));
    painter.restore();
}

void AutomationCanvas::paintTempoSlot(QPainter &painter, const PaintFrame &frame,
                                      const LanePaintItem &item)
{
    const bool expanded = m_tempoLane.expanded();
    const bool selectedLane = frame.selectedRange.has_value() && item.selectedLane;
    if (m_page->document()) {
        const QRect band = expanded ? item.slot.body : m_tempoLane.headerRect();
        painter.save();
        painter.setClipRect(band, Qt::IntersectClip);
        painter.fillRect(band, themes::color(themes::Role::song_view_piano_roll_background));
        painter.setPen(themes::color(themes::Role::song_view_separator));
        painter.drawLine(band.left(), band.bottom(), band.right(), band.bottom());
        painter.restore();
        if (!expanded && selectedLane)
            paintSelectionReticle(painter, *frame.selectedRange, frame.projection, band,
                                  frame.devicePixelRatio);
        const QRect strip(band.left(), band.top(), band.width(), m_geometry.addLaneStripHeight);
        const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
        const QRect arrow(m_labelGutter.left(), strip.center().y() - arrowSize / 2, arrowSize,
                          arrowSize);
        const QRect textBounds(
            m_labelGutter.x() + arrowSize + layout::space(layout::Space::One), strip.top(),
            std::max(0, m_labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
            strip.height());
        const QRect summaryBounds(textBounds.x(), strip.top() + strip.height(), textBounds.width(),
                                  strip.height());
        nodelane::paintLaneHeader(
            painter,
            nodelane::LaneHeaderPaint{
                .band = band,
                .primary = textBounds,
                .secondary = summaryBounds,
                .textClip =
                    QRect(m_labelGutter.x(), band.top(), m_labelGutter.width(), band.height()),
                .arrow = arrow,
                .expanded = expanded,
                .separator = false,
                .titleFont = frame.titleFont,
                .captionFont = frame.captionFont,
                .title = tr("Tempo (BPM)"),
                .secondaryText =
                    expanded ? tr("%n point(s)", nullptr, int(item.points.size())) : QString(),
            });
    }
    if (!expanded)
        return;
    painter.save();
    painter.setClipRect(item.slot.body, Qt::IntersectClip);
    paintLaneBody(painter, frame, item,
                  themes::color(themes::Role::song_view_automation_tempo_curve), true);
    painter.restore();
    if (selectedLane)
        paintSelectionReticle(painter, *frame.selectedRange, frame.projection, item.reticleBounds,
                              frame.devicePixelRatio);
}

const QString &AutomationCanvas::refreshCcSummaryText(CCLanes::RowTextCache &cache,
                                                      std::span<const NodePoint> points,
                                                      const NodeLane &lane)
{
    if (!points.empty()) {
        const auto pointCount = points.size();
        const int minimum = lane.minimumValue();
        const int maximum = lane.maximumValue();
        if (cache.summaryKind != CCLanes::SummaryKind::Points || cache.pointCount != pointCount ||
            cache.minimum != minimum || cache.maximum != maximum) {
            cache.secondary = tr("%1 points · %2..%3").arg(pointCount).arg(minimum).arg(maximum);
            cache.summaryKind = CCLanes::SummaryKind::Points;
            cache.pointCount = pointCount;
            cache.minimum = minimum;
            cache.maximum = maximum;
        }
        return cache.secondary;
    }
    if (cache.summaryKind != CCLanes::SummaryKind::EmptyControl) {
        cache.secondary = tr("empty · click to add points");
        cache.summaryKind = CCLanes::SummaryKind::EmptyControl;
    }
    return cache.secondary;
}

void AutomationCanvas::paintCcSlot(QPainter &painter, const PaintFrame &frame,
                                   const LanePaintItem &item)
{
    if (!item.slot.text)
        return;
    auto &rowText = *item.slot.text;
    const QRect bounds(layout::space(layout::Space::Zero), item.slot.body.top(), width(),
                       item.slot.body.height());
    const QRect textBounds(m_labelGutter.x(), bounds.top(), m_labelGutter.width(), bounds.height());
    const auto textBoxes = frame.textLayout.align(textBounds, layout::VerticalAlignment::Center);
    const QColor color =
        themes::trackIdentityColor(item.slot.id.track % themes::trackIdentityColorCount);
    painter.save();
    painter.setClipRect(bounds, Qt::IntersectClip);
    const QString &secondaryText = refreshCcSummaryText(rowText, item.points, *item.slot.lane);
    nodelane::paintLaneHeader(painter,
                              nodelane::LaneHeaderPaint{
                                  .band = bounds,
                                  .primary = textBoxes.primary,
                                  .secondary = textBoxes.secondary,
                                  .textClip = textBoxes.primary.united(textBoxes.secondary),
                                  .arrow = std::nullopt,
                                  .expanded = true,
                                  .titleFont = frame.titleFont,
                                  .captionFont = frame.captionFont,
                                  .title = rowText.title,
                                  .secondaryText = secondaryText,
                              });
    paintLaneBody(painter, frame, item, color, false);
    painter.restore();
    if (frame.selectedRange && item.selectedLane)
        paintSelectionReticle(painter, *frame.selectedRange, frame.projection, item.reticleBounds,
                              frame.devicePixelRatio);
}

void AutomationCanvas::paintLaneStack(QPainter &painter, const PaintFrame &frame,
                                      const LanePointSnapshots &pointsBySlot)
{
    for (auto index = m_nodeStack.size(); index-- > 0;) {
        const auto &slot = m_nodeStack[index];
        if (!slot.lane)
            continue;
        const LaneHandle handle{int(index)};
        const bool bandLane = bandPreviewContainsLane(handle);
        const LanePaintItem item{
            .handle = handle,
            .slot = slot,
            .points = pointsBySlot[index],
            .selectedLane = m_laneSelection.coversLane(slot.id) || bandLane,
            .selectedNodesLane = m_laneSelection.coversNodes(slot.id) || bandLane,
            .bandLane = bandLane,
            .reticleBounds =
                QRect(m_geometry.plotOrigin, slot.body.top(),
                      std::max(0, width() - m_geometry.plotOrigin), slot.body.height()),
        };
        slot.visit([&] { paintTempoSlot(painter, frame, item); },
                   [&] { paintCcSlot(painter, frame, item); });
    }
}

void AutomationCanvas::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const qreal dpr = painter.device()->devicePixelRatioF();
    const LanePointSnapshots pointsBySlot = snapshotLanePoints();
    const PaintFrame frame = preparePaintFrame(dpr, pointsBySlot);
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), addLaneStripTop(), width(),
                        m_geometry.addLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(
            add.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                         -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
            Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add CC lane"));
    }
    paintLaneStack(painter, frame, pointsBySlot);
}
