#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <optional>
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

void AutomationCanvas::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const AutomationProjection proj = projection();
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto selectedTickRange = [&]() -> std::optional<std::pair<uint64_t, uint64_t>> {
        if (m_band.active) {
            const auto range = TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
            if (!range)
                return std::nullopt;
            return std::pair{range->firstTick, range->lastTick};
        }
        return m_laneSelection.activeTickRange();
    }();
    const auto selectedRange = [&]() -> std::optional<TickRange> {
        if (!selectedTickRange)
            return std::nullopt;
        return TickRange::orderedNonEmpty(selectedTickRange->first, selectedTickRange->second);
    }();
    const auto laneSelected = [this](const NodeLaneSlot &slot) {
        return m_laneSelection.coversLane(slot.id);
    };
    const auto nodeSelected = [this](const NodeLaneSlot &slot) {
        return m_laneSelection.coversNodes(slot.id);
    };
    std::vector<std::vector<NodePoint>> pointsBySlot(m_nodeStack.size());
    for (std::size_t index = 0; index < m_nodeStack.size(); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[index];
        if (slot.lane)
            pointsBySlot[index] = slot.lane->points();
    }
    int selectedCount = 0;
    bool multipleSelectedNodes = false;
    if (selectedTickRange) {
        for (std::size_t index = 0; index < m_nodeStack.size(); ++index) {
            const NodeLaneSlot &slot = m_nodeStack[index];
            const LaneHandle handle{int(index)};
            if (!nodeSelected(slot) && !bandPreviewContainsLane(handle))
                continue;
            const auto &points = pointsBySlot[index];
            for (const NodePoint &point : points) {
                if (point.tick < selectedTickRange->first ||
                    point.tick >= selectedTickRange->second)
                    continue;
                if (++selectedCount > 1) {
                    multipleSelectedNodes = true;
                    break;
                }
            }
            if (multipleSelectedNodes)
                break;
        }
    }
    const QFont &titleFont = m_laneTitleFont;
    const QFont &captionFont = m_laneCaptionFont;
    const auto &textLayout = *m_laneTextLayout;
    const QColor selectedColor = palette().highlight().color();
    const QColor dimmedColor = palette().mid().color();
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
    const uint64_t bandFirst = std::min(m_band.startTick, m_band.endTick);
    const uint64_t bandLast = std::max(m_band.startTick, m_band.endTick);
    auto paintLaneBody = [&](LaneHandle handle, const NodeLane &lane,
                             std::span<const NodePoint> points, const QRect &body,
                             const QColor &color, bool selectedLane, bool selectedNodesLane,
                             bool bandLane, bool preparedPreview) {
        const QRect plot(m_geometry.plotOrigin, body.top(),
                         std::max(0, width() - m_geometry.plotOrigin), body.height());
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        if (!m_page->paintGrid(painter, plot, m_geometry.plotOrigin))
            paintPlainGridFallback(painter, plot, *m_page, m_geometry.plotOrigin, dpr);
        painter.restore();
        std::optional<nodelane::OriginPhantomPaint> phantom;
        if (phantomGesture && phantomGesture->lane == handle) {
            phantom =
                nodelane::OriginPhantomPaint{OriginPhantom{handle, phantomGesture->point.current,
                                                           phantomGesture->point.minimumValue,
                                                           phantomGesture->point.maximumValue},
                                             phantomGesture->point.original};
        } else if (const auto current = originPhantom(handle, proj, points)) {
            phantom = nodelane::OriginPhantomPaint{*current, std::nullopt};
        }
        nodelane::paintNodeLane(
            painter, nodelane::NodeLanePaint{
                         .lane = lane,
                         .points = points,
                         .body = body,
                         .geometry = m_geometry,
                         .projection = proj,
                         .color = color,
                         .handle = handle,
                         .hoverState = m_hoverState,
                         .nodeDrag = nodeDrag,
                         .sweep = sweep,
                         .pencil = pencil,
                         .pencilMode = m_pencilMode,
                         .multipleSelectedNodes = multipleSelectedNodes,
                         .selectedLane = selectedLane,
                         .selectedTickRange = selectedNodesLane
                                                  ? selectedTickRange
                                                  : std::optional<std::pair<uint64_t, uint64_t>>{},
                         .bandLane = bandLane,
                         .bandFirstTick = bandFirst,
                         .bandLastTick = bandLast,
                         .preparedPreviewCurve = preparedPreview,
                         .selectedColor = selectedColor,
                         .dimmedColor = preparedPreview ? color : dimmedColor,
                         .phantom = phantom,
                     });
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        paintEditCursor(painter, plot, proj.displayX(m_page->liveState().editCursorTick, dpr));
        painter.restore();
    };
    auto paintLaneReticle = [&](const QRect &bounds) {
        paintSelectionReticle(painter, *selectedRange, proj, bounds, dpr);
    };
    auto paintTempoSlot = [&](LaneHandle handle, const NodeLaneSlot &slot,
                              std::span<const NodePoint> points, bool selectedLane,
                              bool selectedNodesLane, bool bandLane, QRect reticleBounds) {
        const bool expanded = m_tempoLane.expanded();
        if (m_page->document()) {
            const QRect band = expanded ? slot.body : m_tempoLane.headerRect();
            if (!expanded)
                reticleBounds = band;
            painter.save();
            painter.setClipRect(band, Qt::IntersectClip);
            painter.fillRect(band, themes::color(themes::Role::song_view_piano_roll_background));
            painter.setPen(themes::color(themes::Role::song_view_separator));
            painter.drawLine(band.left(), band.bottom(), band.right(), band.bottom());
            painter.restore();
            if (!expanded && selectedRange && selectedLane)
                paintLaneReticle(band);
            const QRect strip(band.left(), band.top(), band.width(), m_geometry.addLaneStripHeight);
            const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
            const QRect arrow(m_labelGutter.left(), strip.center().y() - arrowSize / 2, arrowSize,
                              arrowSize);
            const QRect textBounds(
                m_labelGutter.x() + arrowSize + layout::space(layout::Space::One), strip.top(),
                std::max(0, m_labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
                strip.height());
            const QRect summaryBounds(textBounds.x(), strip.top() + strip.height(),
                                      textBounds.width(), strip.height());
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
                    .titleFont = titleFont,
                    .captionFont = captionFont,
                    .title = tr("Tempo (BPM)"),
                    .secondaryText =
                        expanded ? tr("%n point(s)", nullptr, int(points.size())) : QString(),
                });
        } else if (!expanded) {
            return;
        }
        if (!expanded)
            return;
        painter.save();
        painter.setClipRect(slot.body, Qt::IntersectClip);
        paintLaneBody(handle, *slot.lane, points, slot.body,
                      themes::color(themes::Role::song_view_automation_tempo_curve), selectedLane,
                      selectedNodesLane, bandLane, true);
        painter.restore();
        if (selectedRange && selectedLane)
            paintLaneReticle(reticleBounds);
    };
    auto paintCcSlot = [&](LaneHandle handle, const NodeLaneSlot &slot,
                           std::span<const NodePoint> points, bool selectedLane,
                           bool selectedNodesLane, bool bandLane, const QRect &reticleBounds) {
        if (!slot.text)
            return;
        auto &rowText = *slot.text;
        const QRect bounds(layout::space(layout::Space::Zero), slot.body.top(), width(),
                           slot.body.height());
        const QRect textBounds(m_labelGutter.x(), bounds.top(), m_labelGutter.width(),
                               bounds.height());
        const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
        const QColor color =
            themes::trackIdentityColor(slot.id.track % themes::trackIdentityColorCount);
        painter.save();
        painter.setClipRect(bounds, Qt::IntersectClip);
        QString secondaryText;
        if (!points.empty()) {
            const std::size_t pointCount = points.size();
            const int minimum = slot.lane->minimumValue();
            const int maximum = slot.lane->maximumValue();
            if (rowText.summaryKind != CCLanes::SummaryKind::Points ||
                rowText.pointCount != pointCount || rowText.minimum != minimum ||
                rowText.maximum != maximum) {
                rowText.secondary =
                    tr("%1 points · %2..%3").arg(pointCount).arg(minimum).arg(maximum);
                rowText.summaryKind = CCLanes::SummaryKind::Points;
                rowText.pointCount = pointCount;
                rowText.minimum = minimum;
                rowText.maximum = maximum;
            }
            secondaryText = rowText.secondary;
        } else {
            if (rowText.summaryKind != CCLanes::SummaryKind::EmptyControl) {
                rowText.secondary = tr("empty · click to add points");
                rowText.summaryKind = CCLanes::SummaryKind::EmptyControl;
            }
            secondaryText = rowText.secondary;
        }
        nodelane::paintLaneHeader(painter,
                                  nodelane::LaneHeaderPaint{
                                      .band = bounds,
                                      .primary = textBoxes.primary,
                                      .secondary = textBoxes.secondary,
                                      .textClip = textBoxes.primary.united(textBoxes.secondary),
                                      .arrow = std::nullopt,
                                      .expanded = true,
                                      .titleFont = titleFont,
                                      .captionFont = captionFont,
                                      .title = rowText.title,
                                      .secondaryText = secondaryText,
                                  });
        paintLaneBody(handle, *slot.lane, points, slot.body, color, selectedLane, selectedNodesLane,
                      bandLane, false);
        painter.restore();
        if (selectedRange && selectedLane)
            paintLaneReticle(reticleBounds);
    };
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), addLaneStripTop(), width(),
                        m_geometry.addLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(
            add.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                         -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
            Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add CC lane"));
    }
    for (std::size_t index = m_nodeStack.size(); index-- > 0;) {
        const NodeLaneSlot &slot = m_nodeStack[index];
        if (!slot.lane)
            continue;
        const LaneHandle handle{int(index)};
        const std::span<const NodePoint> points = pointsBySlot[index];
        const bool bandLane = bandPreviewContainsLane(handle);
        const bool selectedLane = laneSelected(slot) || bandLane;
        const bool selectedNodesLane = nodeSelected(slot) || bandLane;
        const QRect reticleBounds(m_geometry.plotOrigin, slot.body.top(),
                                  std::max(0, width() - m_geometry.plotOrigin), slot.body.height());
        slot.visit(
            [&] {
                paintTempoSlot(handle, slot, points, selectedLane, selectedNodesLane, bandLane,
                               reticleBounds);
            },
            [&] {
                paintCcSlot(handle, slot, points, selectedLane, selectedNodesLane, bandLane,
                            reticleBounds);
            });
    }
}