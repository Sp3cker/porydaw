#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <optional>

#include <QFontMetricsF>
#include <QPainter>
#include <QPen>

#include "core/timedefaults.h"
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
    m_laneCaptionHeight = QFontMetricsF(m_laneCaptionFont).height();
}

void AutomationCanvas::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const AutomationProjection proj = projection();
    int selectedCount = 0;
    bool multipleSelectedNodes = false;
    for (const NodeLaneSlot &slot : m_nodeStack) {
        if (!slot.lane)
            continue;
        for (const NodePoint &point : slot.lane->points()) {
            if (!slot.lane->pointSelected(point.tick))
                continue;
            if (++selectedCount > 1) {
                multipleSelectedNodes = true;
                break;
            }
        }
        if (multipleSelectedNodes)
            break;
    }
    const QFont &titleFont = m_laneTitleFont;
    const QFont &captionFont = m_laneCaptionFont;
    m_voiceLane.paint(painter, *this, m_geometry, m_labelGutter, titleFont, captionFont,
                      *m_laneTextLayout, m_laneCaptionHeight);
    const auto &textLayout = *m_laneTextLayout;
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto &rows = m_rowData.rows();
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
    auto paintLaneBody = [&](LaneHandle handle, const NodeLane &lane, const QRect &body,
                             const QColor &color, bool selectedLane, bool bandLane,
                             bool preparedPreview, std::optional<NodePoint> leadIn) {
        const QRect plot(m_geometry.plotOrigin, body.top(),
                         std::max(0, width() - m_geometry.plotOrigin), body.height());
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        if (!m_page->paintGrid(painter, plot, m_geometry.plotOrigin))
            paintPlainGridFallback(painter, plot, *m_page, m_geometry.plotOrigin, dpr);
        painter.restore();
        nodelane::paintNodeLane(painter, nodelane::NodeLanePaint{
                                             .lane = lane,
                                             .body = body,
                                             .geometry = m_geometry,
                                             .projection = proj,
                                             .color = color,
                                             .leadIn = leadIn,
                                             .handle = handle,
                                             .hoverState = m_hoverState,
                                             .nodeDrag = nodeDrag,
                                             .sweep = sweep,
                                             .pencil = pencil,
                                             .pencilMode = m_pencilMode,
                                             .multipleSelectedNodes = multipleSelectedNodes,
                                             .selectedLane = selectedLane,
                                             .bandLane = bandLane,
                                             .bandFirstTick = bandFirst,
                                             .bandLastTick = bandLast,
                                             .preparedPreviewCurve = preparedPreview,
                                             .selectedColor = selectedColor,
                                             .dimmedColor = preparedPreview ? color : dimmedColor,
                                         });
        painter.save();
        painter.setClipRect(plot, Qt::IntersectClip);
        paintEditCursor(painter, plot, proj.displayX(m_page->liveState().editCursorTick, dpr));
        painter.restore();
    };
    for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
        const AutomationRow &row = rows[std::size_t(rowIndex)];
        const LaneHandle handle{rowIndex + 1};
        const NodeLane *lane = nullptr;
        QRect body;
        if (!resolveLane(handle, &lane, &body) || !lane)
            continue;
        const QRect bounds(layout::space(layout::Space::Zero), body.top(), width(), body.height());
        const QRect textBounds(m_labelGutter.x(), bounds.top(), m_labelGutter.width(),
                               bounds.height());
        const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
        const auto points = lane->points();
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
            const int minimum = lane->minimumValue();
            const int maximum = lane->maximumValue();
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
        const bool bandLane = bandPreviewContainsLane(handle);
        const auto laneId = m_rowData.rowIdentity(row);
        const auto &timeSelection = m_rowData.timeSelection();
        const bool selectedLane =
            (timeSelection.active() && timeSelection.coversLane(laneId.first, laneId.second)) ||
            bandLane;
        paintLaneBody(handle, *lane, body, color, selectedLane, bandLane, false, {});
        painter.restore();
    }
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), addLaneStripTop(), width(),
                        m_geometry.addLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(
            add.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                         -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
            Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add CC lane"));
    }
    const auto selectedRange = [&] {
        if (m_band.active)
            return TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
        const auto &selection = m_page->m_owner.selectionModel().timeSelection();
        if (!selection.active())
            return std::optional<TickRange>{};
        return TickRange::orderedNonEmpty(selection.startTick, selection.endTick);
    }();
    auto paintLaneReticle = [&](const QRect &body) {
        const QRect bounds(m_geometry.plotOrigin, body.top(),
                           std::max(0, width() - m_geometry.plotOrigin), body.height());
        paintSelectionReticle(painter, *selectedRange, proj, bounds, dpr);
    };
    if (selectedRange) {
        if (m_band.active) {
            const int first = std::min(m_bandStart.index, m_bandEnd.index);
            const int last = std::max(m_bandStart.index, m_bandEnd.index);
            for (int index = std::max(1, first); index <= last && index < int(m_nodeStack.size());
                 ++index) {
                paintLaneReticle(m_nodeStack[std::size_t(index)].body);
            }
        } else {
            const auto &selection = m_page->m_owner.selectionModel().timeSelection();
            for (int rowIndex = 0; rowIndex < int(rows.size()); ++rowIndex) {
                const auto lane = m_rowData.rowIdentity(rows[std::size_t(rowIndex)]);
                if (!selection.active() ||
                    !m_rowData.timeSelection().coversLane(lane.first, lane.second))
                    continue;
                const LaneHandle handle{rowIndex + 1};
                const NodeLane *ignored = nullptr;
                QRect body;
                if (resolveLane(handle, &ignored, &body))
                    paintLaneReticle(body);
            }
        }
    }

    m_tempoLane.paint(painter, m_geometry, m_labelGutter, titleFont, captionFont);
    if (!m_tempoLane.expanded() || m_nodeStack.empty() || !m_nodeStack.front().lane)
        return;

    const LaneHandle tempoHandle{0};
    const QRect &tempoBody = m_nodeStack.front().body;
    const bool tempoBandLane = bandPreviewContainsLane(tempoHandle);
    const auto tempoPoints = m_nodeStack.front().lane->points();
    std::optional<NodePoint> tempoLeadIn;
    if (!tempoPoints.empty() && tempoPoints.front().tick > 0)
        tempoLeadIn = NodePoint{0, CoreTimeDefaults::kTempoBpm};
    painter.save();
    painter.setClipRect(tempoBody, Qt::IntersectClip);
    paintLaneBody(tempoHandle, *m_nodeStack.front().lane, tempoBody,
                  themes::color(themes::Role::song_view_automation_tempo_curve),
                  m_tempoLane.hasTimeSelection() || tempoBandLane, tempoBandLane, true,
                  tempoLeadIn);
    painter.restore();

    if (!selectedRange)
        return;
    if (m_band.active) {
        const int first = std::min(m_bandStart.index, m_bandEnd.index);
        const int last = std::max(m_bandStart.index, m_bandEnd.index);
        if (first <= 0 && last >= 0)
            paintLaneReticle(tempoBody);
    } else if (m_tempoLane.hasTimeSelection()) {
        paintLaneReticle(tempoBody);
    }
}
