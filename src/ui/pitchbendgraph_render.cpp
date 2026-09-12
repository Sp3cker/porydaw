#include "pitchbendgraph.hpp"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/grid.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QFontMetrics>
#include <QSGNode>
#include <algorithm>

namespace songview {
namespace {
using timeline_quick::addDashedHorizontal;
using timeline_quick::addEllipse;
using timeline_quick::addEllipseRing;
using timeline_quick::addHorizontalLine;
using timeline_quick::addLine;
using timeline_quick::addRect;
using timeline_quick::addVerticalLine;
using timeline_quick::resetLayer;

// Qt::DashLine dash/gap proportions on a hairline pen.
constexpr qreal kDashMultiplier = 4.0;
constexpr qreal kGapMultiplier = 2.0;
// Widget-era selected-node ring pen was 1.5× the hairline.
constexpr qreal kSelectedRingWidthMultiplier = 1.5;

void addRectOutline(TimelineQuickLayerData &data, const QRectF &rect, qreal width,
                    const QColor &color, const QRectF &clip)
{
    addHorizontalLine(data, rect.left(), rect.right(), rect.top(), width, color, clip);
    addHorizontalLine(data, rect.left(), rect.right(), rect.bottom(), width, color, clip);
    addVerticalLine(data, rect.left(), rect.top(), rect.bottom(), width, color, clip);
    addVerticalLine(data, rect.right(), rect.top(), rect.bottom(), width, color, clip);
}
} // namespace

PitchBendGeometry PitchBendGeometry::resolve(const QFont &font, qreal dpr)
{
    const QFontMetrics boldMetrics(typography::bold(font));
    const QFontMetrics captionMetrics(typography::caption(font));
    const int inset = layout::fontPx(4.0 / 7.0);
    const int axisGutter = layout::fontPx(26.0 / 7.0);
    const int canvasWidth = layout::fontPx(20.0);
    const int canvasHeight = layout::fontPx(8.0);

    PitchBendGeometry geometry;
    geometry.outerInset = inset;
    geometry.titleHeight = boldMetrics.height();
    geometry.descriptionHeight = captionMetrics.height();
    geometry.fieldHeight = layout::fontPx(12.0 / 7.0);
    geometry.controlsHeight = geometry.fieldHeight;
    geometry.fieldWidth = layout::fontPx(39.0 / 7.0);
    geometry.resetWidth = layout::fontPx(30.0 / 7.0);
    geometry.resetHeight = layout::fontPx(13.0 / 7.0);
    geometry.axisLabelHeight = captionMetrics.height() + layout::space(layout::Space::One);
    geometry.headerHeight = inset + geometry.titleHeight + geometry.descriptionHeight +
                            layout::space(layout::Space::One) + geometry.controlsHeight +
                            layout::space(layout::Space::One);
    geometry.canvas = QRect(axisGutter, geometry.titleHeight + layout::space(layout::Space::Six),
                            canvasWidth, canvasHeight);
    geometry.graphHeight = geometry.canvas.top() + canvasHeight + geometry.axisLabelHeight +
                           layout::space(layout::Space::One);
    geometry.popupSize =
        QSize(axisGutter + canvasWidth + inset, geometry.headerHeight + 2 * geometry.graphHeight);
    const qreal physicalPixel = detail::logicalPhysicalPixel(dpr);
    geometry.zeroDetent = layout::fontPxF(4.0 / 7.0);
    geometry.nodeHitRadius = layout::fontPxF(4.0 / 7.0);
    geometry.nodePaintRadius = layout::fontPxF(3.0 / 14.0);
    geometry.selectedRingRadius = layout::fontPxF(3.0 / 7.0);
    geometry.curveStroke = layout::fontPxF(1.0 / 7.0);
    geometry.scrubThreshold = layout::fontPxF(3.0 / 14.0);
    geometry.hairline = physicalPixel;
    return geometry;
}

QSGNode *PitchBendGraph::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    // A QML-created graph remains render-inert until initialize() gives it a
    // complete GUI-thread snapshot.
    if (!m_initialized)
        return nullptr;
    // Render-thread sync reads only the item-owned layer buffer; every
    // document, theme, and grid read happened in rebuildLayer() on the GUI
    // thread.
    return timeline_quick::syncLayerNode(oldNode, &m_layer);
}

void PitchBendGraph::rebuildLayer()
{
    if (!m_initialized)
        return;
    resetLayer(m_layer);
    const QRect canvas = canvasRect();
    if (canvas.isEmpty())
        return;
    const QRectF plot(canvas);
    addRect(m_layer, plot, themes::color(themes::Role::song_view_piano_roll_background), plot);
    buildGrid(plot);
    buildCurve(plot);
    buildLinePreview(plot);
    buildFocusFrame();
}

void PitchBendGraph::buildGrid(const QRectF &plot)
{
    const QColor gridColor = themes::color(themes::Role::song_view_grid);
    if (m_grid && m_endTick > m_startTick) {
        Tick segmentTick = m_startTick;
        while (segmentTick < m_endTick) {
            const Grid::Segment segment = m_grid->segmentAt(segmentTick);
            const Tick segmentEnd = std::min(m_endTick, segment.next);
            const uint32_t cell = normalCellTicksAt(segmentTick);
            const Tick anchor = segment.start;
            const uint64_t offset = segmentTick > anchor ? segmentTick - anchor : 0;
            const uint64_t quotient = offset / cell;
            uint64_t tick = uint64_t(anchor) + (quotient + 1) * cell;
            while (tick < segmentEnd) {
                addVerticalLine(m_layer, xAtTick(Tick(tick)), plot.top(), plot.bottom(),
                                m_geometry.hairline, gridColor, plot);
                tick += cell;
            }
            if (segmentEnd >= m_endTick)
                break;
            segmentTick = segmentEnd;
        }
    }
    addDashedHorizontal(m_layer, plot.left(), plot.right(), yAtValue(0), m_geometry.hairline,
                        kDashMultiplier * m_geometry.hairline, kGapMultiplier * m_geometry.hairline,
                        themes::color(themes::Role::song_view_separator), plot);
}

void PitchBendGraph::buildCurve(const QRectF &plot)
{
    const QColor curveColor = SongView::trackColor(m_engineTrack);
    const QColor endpointColor = themes::color(themes::Role::song_view_secondary_text);
    const QColor selectedRing = themes::color(themes::Role::focus_outline);
    const uint32_t fineTick = m_grid ? m_grid->fineGridTicks() : 1;
    for (auto it = m_points.cbegin(); it != m_points.cend(); ++it) {
        const auto next = std::next(it);
        const qreal x0 = xAtTick(it->first);
        const qreal x1 = next == m_points.cend() ? plot.right() : xAtTick(next->first);
        const qreal y = yAtValue(it->second);
        const bool angled = next != m_points.cend() && next->first > it->first &&
                            next->first - it->first == fineTick;
        if (angled) {
            addLine(m_layer, {x0, y}, {x1, qreal(yAtValue(next->second))}, m_geometry.curveStroke,
                    curveColor, plot);
        } else {
            addLine(m_layer, {x0, y}, {x1, y}, m_geometry.curveStroke, curveColor, plot);
            if (next != m_points.cend())
                addLine(m_layer, {x1, y}, {x1, qreal(yAtValue(next->second))},
                        m_geometry.curveStroke, curveColor, plot);
        }
    }
    for (const auto &[tick, value] : m_points) {
        const QPointF center(vertexPosition(tick, value));
        if (m_selectedTick && *m_selectedTick == tick) {
            addEllipseRing(m_layer, center, m_geometry.selectedRingRadius,
                           m_geometry.selectedRingRadius,
                           kSelectedRingWidthMultiplier * m_geometry.hairline, selectedRing, plot);
            addEllipse(m_layer, center, m_geometry.nodePaintRadius, m_geometry.nodePaintRadius,
                       curveColor, plot);
            continue;
        }
        const bool endpoint = tick == m_startTick || tick == m_endTick;
        const qreal endpointRadius =
            std::max(m_geometry.hairline, m_geometry.nodePaintRadius - m_geometry.hairline);
        addEllipse(m_layer, center, endpointRadius, endpointRadius,
                   endpoint ? endpointColor : curveColor, plot);
    }
    addEllipseRing(m_layer, QPointF(vertexPosition(m_keyboardTick, m_liveValue)),
                   m_geometry.nodePaintRadius, m_geometry.nodePaintRadius, m_geometry.hairline,
                   themes::color(themes::Role::song_view_edit_preview_outline), plot);
}

void PitchBendGraph::buildLinePreview(const QRectF &plot)
{
    if (!m_strokeState || !isLineGesture())
        return;
    const StrokeState &state = *m_strokeState;
    addLine(m_layer, QPointF(vertexPosition(state.anchorTick, state.anchorValue)),
            QPointF(vertexPosition(state.previousTick, state.previousValue)), m_geometry.hairline,
            themes::color(themes::Role::song_view_edit_preview_outline), plot);
}

void PitchBendGraph::buildFocusFrame()
{
    if (!hasActiveFocus())
        return;
    const QRectF frame = QRectF(canvasRect())
                             .adjusted(m_geometry.hairline, m_geometry.hairline,
                                       -m_geometry.hairline, -m_geometry.hairline);
    addRectOutline(m_layer, frame, m_geometry.hairline, themes::color(themes::Role::focus_outline),
                   QRectF(0, 0, width(), height()));
}

} // namespace songview
