#include "pitchbendgraph.hpp"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QFont>
#include <QFontMetrics>
#include <QSGNode>
#include <algorithm>
#include <iterator>
#include <map>
#include <optional>

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
    if (!m_kernel)
        return nullptr;
    // Render-thread sync reads only the item-owned layer buffer; every
    // document, theme, and grid read happened in rebuildLayer() on the GUI
    // thread.
    return timeline_quick::syncLayerNode(oldNode, &m_layer);
}

void PitchBendGraph::rebuildLayer()
{
    if (!m_kernel)
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
    const PitchBendGeometry &geometry = m_kernel->geometry();
    const QColor gridColor = themes::color(themes::Role::song_view_grid);
    if (m_kernel->endTick() > m_kernel->startTick()) {
        // The editing lattice, one line per snap position: segment-anchored
        // for Auto/Musical, absolute for Clock — nextSnapTickAfter owns the
        // anchor and seam rules. Signature seams carry their own marker, so
        // a lattice tick landing exactly on one is not repainted.
        for (Tick tick = m_kernel->nextSnapTickAfter(m_kernel->startTick());
             tick < m_kernel->endTick(); tick = m_kernel->nextSnapTickAfter(tick)) {
            if (tick == m_kernel->segmentStartAt(tick))
                continue;
            addVerticalLine(m_layer, m_kernel->xAtTick(tick), plot.top(), plot.bottom(),
                            geometry.hairline, gridColor, plot);
        }
    }
    addDashedHorizontal(m_layer, plot.left(), plot.right(), m_kernel->yAtValue(0),
                        geometry.hairline, kDashMultiplier * geometry.hairline,
                        kGapMultiplier * geometry.hairline,
                        themes::color(themes::Role::song_view_separator), plot);
}

void PitchBendGraph::buildCurve(const QRectF &plot)
{
    const PitchBendGeometry &geometry = m_kernel->geometry();
    const QColor curveColor = SongView::trackColor(m_engineTrack);
    const QColor endpointColor = themes::color(themes::Role::song_view_secondary_text);
    const QColor selectedRing = themes::color(themes::Role::focus_outline);
    const uint32_t fineTick = m_kernel->fineGridTicks();
    const std::map<Tick, int> &points = m_kernel->points();
    for (auto it = points.cbegin(); it != points.cend(); ++it) {
        const auto next = std::next(it);
        const qreal x0 = m_kernel->xAtTick(it->first);
        const qreal x1 = next == points.cend() ? plot.right() : m_kernel->xAtTick(next->first);
        const qreal y = m_kernel->yAtValue(it->second);
        const bool angled =
            next != points.cend() && next->first > it->first && next->first - it->first == fineTick;
        if (angled) {
            addLine(m_layer, {x0, y}, {x1, qreal(m_kernel->yAtValue(next->second))},
                    geometry.curveStroke, curveColor, plot);
        } else {
            addLine(m_layer, {x0, y}, {x1, y}, geometry.curveStroke, curveColor, plot);
            if (next != points.cend())
                addLine(m_layer, {x1, y}, {x1, qreal(m_kernel->yAtValue(next->second))},
                        geometry.curveStroke, curveColor, plot);
        }
    }
    const std::optional<Tick> selected = m_kernel->selectedTick();
    const Tick startTick = m_kernel->startTick();
    const Tick endTick = m_kernel->endTick();
    for (const auto &[tick, value] : points) {
        const QPointF center(m_kernel->vertexPosition(tick, value));
        if (selected && *selected == tick) {
            addEllipseRing(m_layer, center, geometry.selectedRingRadius,
                           geometry.selectedRingRadius,
                           kSelectedRingWidthMultiplier * geometry.hairline, selectedRing, plot);
            addEllipse(m_layer, center, geometry.nodePaintRadius, geometry.nodePaintRadius,
                       curveColor, plot);
            continue;
        }
        const bool endpoint = tick == startTick || tick == endTick;
        const qreal endpointRadius =
            std::max(geometry.hairline, geometry.nodePaintRadius - geometry.hairline);
        addEllipse(m_layer, center, endpointRadius, endpointRadius,
                   endpoint ? endpointColor : curveColor, plot);
    }
    addEllipseRing(
        m_layer, QPointF(m_kernel->vertexPosition(m_kernel->keyboardTick(), m_kernel->liveValue())),
        geometry.nodePaintRadius, geometry.nodePaintRadius, geometry.hairline,
        themes::color(themes::Role::song_view_edit_preview_outline), plot);
}

void PitchBendGraph::buildLinePreview(const QRectF &plot)
{
    const std::optional<PitchBendKernel::LinePreview> preview = m_kernel->linePreview();
    if (!preview)
        return;
    addLine(m_layer, QPointF(m_kernel->vertexPosition(preview->anchorTick, preview->anchorValue)),
            QPointF(m_kernel->vertexPosition(preview->previousTick, preview->previousValue)),
            m_kernel->geometry().hairline,
            themes::color(themes::Role::song_view_edit_preview_outline), plot);
}

void PitchBendGraph::buildFocusFrame()
{
    if (!hasActiveFocus())
        return;
    const qreal hairline = m_kernel->geometry().hairline;
    const QRectF frame = QRectF(canvasRect()).adjusted(hairline, hairline, -hairline, -hairline);
    addRectOutline(m_layer, frame, hairline, themes::color(themes::Role::focus_outline),
                   QRectF(0, 0, width(), height()));
}

} // namespace songview
