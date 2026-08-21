#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <optional>

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

void AutomationCanvas::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const AutomationProjection proj = projection();
    const bool multipleSelectedNodes = m_rowData.selectionHasMultipleNodes();
    const QFont titleFont = typography::bold(typography::caption(font()));
    const QFont captionFont = captionLabelFont();
    m_tempoLane.paint(painter, m_geometry, m_labelGutter, titleFont, captionFont, m_hoverState,
                      m_pencilMode);
    m_voiceLane.paint(painter, *this, m_geometry, m_labelGutter, titleFont, captionFont);
    const auto textLayout =
        layout::twoLineText(titleFont, titleFont, captionFont, layout::Space::Zero);
    const auto &rows = m_rowData.rows();
    const qreal dpr = painter.device()->devicePixelRatioF();
    const QColor selectedColor = palette().highlight().color();
    const QColor dimmedColor = palette().mid().color();
    const NodeDragGesture *nodeDrag = nullptr;
    const SweepGesture *sweep = nullptr;
    const PencilGesture *pencil = nullptr;
    if (m_activeGesture) {
        nodeDrag = std::get_if<NodeDragGesture>(&*m_activeGesture);
        sweep = std::get_if<SweepGesture>(&*m_activeGesture);
        pencil = std::get_if<PencilGesture>(&*m_activeGesture);
    }
    const uint64_t bandFirst = std::min(m_band.startTick, m_band.endTick);
    const uint64_t bandLast = std::max(m_band.startTick, m_band.endTick);
    for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
        const AutomationRow &row = rows[std::size_t(rowIndex)];
        const int height = proj.rowHeight(row);
        const QRect bounds(layout::space(layout::Space::Zero), proj.rowTop(rowIndex), width(),
                           height);
        const QRect plot(m_geometry.plotOrigin, bounds.top(),
                         std::max(0, width() - m_geometry.plotOrigin), bounds.height());
        const QRect textBounds(m_labelGutter.x(), bounds.top(), m_labelGutter.width(),
                               bounds.height());
        const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
        const auto &points = m_rowData.pointsFor(row, proj);
        const QColor color =
            themes::trackIdentityColor(row.id.track % themes::trackIdentityColorCount);
        painter.save();
        painter.setClipRect(bounds, Qt::IntersectClip);
        painter.setPen(themes::color(themes::Role::song_view_separator));
        painter.drawLine(bounds.left(), bounds.bottom(), bounds.right(), bounds.bottom());
        painter.save();
        painter.setClipRect(textBoxes.primary.united(textBoxes.secondary), Qt::IntersectClip);
        painter.setFont(titleFont);
        painter.setPen(themes::color(themes::Role::song_view_primary_text));
        auto &rowText = m_rowData.rowText()[std::size_t(rowIndex)];
        painter.drawText(textBoxes.primary, Qt::AlignLeft | Qt::AlignVCenter, rowText.title);
        painter.setFont(captionFont);
        if (!points.empty()) {
            const std::size_t pointCount = points.size();
            const int minimum = proj.rowMinimum(row);
            const int maximum = proj.rowMaximum(row);
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
            painter.setPen(themes::color(themes::Role::song_view_secondary_text));
            painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                             rowText.secondary);
        } else if (row.id.kind == EditorAutomationRowKind::ControlChange) {
            if (rowText.summaryKind != CCLanes::SummaryKind::EmptyControl) {
                rowText.secondary = tr("empty · click to add points");
                rowText.summaryKind = CCLanes::SummaryKind::EmptyControl;
            }
            painter.setPen(themes::color(themes::Role::song_view_secondary_text));
            painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                             rowText.secondary);
        }
        painter.restore();
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        if (!m_page->paintGrid(painter, plot, m_geometry.plotOrigin))
            paintPlainGridFallback(painter, plot, *m_page, m_geometry.plotOrigin, dpr);
        painter.restore();
        const NodeLane *lane = nullptr;
        QRect body;
        const LaneHandle handle{rowIndex + 1};
        if (resolveLane(handle, &lane, &body) && lane) {
            const bool bandLane = bandPreviewContainsRow(rowIndex);
            const auto laneId = m_rowData.rowIdentity(row);
            const auto &timeSelection = m_rowData.timeSelection();
            const bool selectedLane =
                (timeSelection.active() && timeSelection.coversLane(laneId.first, laneId.second)) ||
                bandLane;
            nodelane::paintNodeLane(painter, nodelane::NodeLanePaint{
                                                 .lane = *lane,
                                                 .body = body,
                                                 .geometry = m_geometry,
                                                 .projection = proj,
                                                 .color = color,
                                                 .handle = handle,
                                                 .hoverState = m_hoverState,
                                                 .nodeDrag = nodeDrag,
                                                 .sweep = sweep,
                                                 .pencil = pencil,
                                                 .gestureRow = rowIndex,
                                                 .pencilMode = m_pencilMode,
                                                 .multipleSelectedNodes = multipleSelectedNodes,
                                                 .selectedLane = selectedLane,
                                                 .bandLane = bandLane,
                                                 .bandFirstTick = bandFirst,
                                                 .bandLastTick = bandLast,
                                                 .selectedColor = selectedColor,
                                                 .dimmedColor = dimmedColor,
                                             });
        }
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        paintEditCursor(painter, plot, proj.displayX(m_page->liveState().editCursorTick, dpr));
        painter.restore();
        painter.restore();
    }
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), proj.rowTop(int(rows.size())), width(),
                        m_geometry.addLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(
            add.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                         -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
            Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add lane"));
    }
    const auto selectedRange = [&] {
        if (m_band.active)
            return TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
        const auto &selection = m_rowData.timeSelection();
        if (!selection.active())
            return std::optional<TickRange>{};
        return TickRange::orderedNonEmpty(selection.startTick, selection.endTick);
    }();
    if (m_band.active) {
        const int firstRow = std::min(m_bandRightRow, m_bandEndRow);
        const int lastRow = std::max(m_bandRightRow, m_bandEndRow);
        if (selectedRange && firstRow >= 0 && lastRow >= firstRow) {
            const int top = proj.rowTop(firstRow);
            const QRect bounds(m_geometry.plotOrigin, top,
                               std::max(0, width() - m_geometry.plotOrigin),
                               proj.rowTop(lastRow + 1) - top);
            paintSelectionReticle(painter, *selectedRange, proj, bounds, dpr);
        }
    } else if (selectedRange) {
        const auto &selection = m_rowData.timeSelection();
        for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
            const auto lane = m_rowData.rowIdentity(rows[std::size_t(rowIndex)]);
            if (!selection.coversLane(lane.first, lane.second))
                continue;
            const QRect bounds(m_geometry.plotOrigin, proj.rowTop(rowIndex),
                               std::max(0, width() - m_geometry.plotOrigin),
                               proj.rowHeight(rows[std::size_t(rowIndex)]));
            paintSelectionReticle(painter, *selectedRange, proj, bounds, dpr);
        }
    }
}
