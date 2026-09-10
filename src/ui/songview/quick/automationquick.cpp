#include "ui/editordrawer/automationcanvas.h"

#include <QPalette>

#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/songview/quick/automationnodelanequick.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace songview {
namespace {

using timeline_quick::addHorizontalLine;
using timeline_quick::addRect;
using timeline_quick::composeBandedGrid;
using timeline_quick::resetLayer;

QColor opaqueColor(themes::Role role)
{
    QColor color = themes::color(role);
    color.setAlpha(255);
    return color;
}

void appendText(std::vector<TimelineQuickTextModel::Record> &records, TimelineQuickTextKeyKind kind,
                quint64 ordinal, const QRectF &rect, const QString &text, const QColor &color,
                const QFont &font, Qt::Alignment horizontal = Qt::AlignLeft, QRectF clip = {})
{
    if ((!clip.isNull() && !rect.intersects(clip)) || rect.width() <= 0.0 || rect.height() <= 0.0 ||
        text.isEmpty())
        return;
    records.push_back(
        {{kind, {}, ordinal}, rect, text, color, font, horizontal, Qt::AlignVCenter, clip});
}

void addBandFrame(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal top, qreal bottom,
                  qreal width, const QRectF &clip)
{
    const qreal stroke = layout::singlePixel();
    const QColor color = themes::color(themes::Role::song_view_separator);
    addHorizontalLine(scene.layer(layer), 0.0, width, top, stroke, color, clip);
    addHorizontalLine(scene.layer(layer), 0.0, width, bottom, stroke, color, clip);
}

} // namespace
} // namespace songview

void AutomationCanvas::rebuildQuickScene(songview::TimelineQuickScene &scene,
                                         songview::AutomationRefreshSet refresh)
{
    using namespace songview;
    const bool gutterContent = refresh.testFlag(AutomationRefresh::Content);
    const bool content = gutterContent || refresh.testFlag(AutomationRefresh::HorizontalPan);
    const bool transient = refresh.testFlag(AutomationRefresh::Transient);
    const bool hover = refresh.testFlag(AutomationRefresh::Hover);
    // Publish each text model once below. Clearing first destroys its QML delegates.
    if (gutterContent)
        resetLayer(scene.layer(TimelineQuickLayer::AutomationGutterChrome));
    if (content) {
        resetLayer(scene.layer(TimelineQuickLayer::AutomationGrid));
        resetLayer(scene.layer(TimelineQuickLayer::AutomationCurves));
        resetLayer(scene.layer(TimelineQuickLayer::AutomationNodes));
        resetLayer(scene.layer(TimelineQuickLayer::AutomationSelection));
    }
    if (transient)
        resetLayer(scene.layer(TimelineQuickLayer::AutomationTransient));
    if (hover)
        resetLayer(scene.layer(TimelineQuickLayer::AutomationHover));
    const QRectF viewport = m_inputHost ? m_inputHost->bounds() : QRectF{};
    if (!m_inputHost || !m_page.document() || viewport.height() <= 0.0) {
        if (gutterContent)
            scene.setAutomationTextRecords({});
        if (transient)
            scene.setAutomationTransientTextRecords({});
        if (hover)
            scene.setAutomationHoverTextRecords({});
        return;
    }
    const auto &bandGeometry =
        m_page.m_owner.timelineBandLayout().geometry(TimelineBand::Automation);
    const QRect gutter = bandGeometry ? bandGeometry->gutterRect() : QRect{};
    const QRectF gutterViewport(0.0, 0.0, gutter.width(), gutter.height());
    const qreal dpr = m_inputHost->devicePixelRatio();
    const AutomationProjection projection = this->projection();
    const auto selectedTickRange = [this]() -> std::optional<std::pair<uint64_t, uint64_t>> {
        if (m_band.active) {
            const uint64_t first = std::min(m_band.startTick, m_band.endTick);
            const uint64_t last = std::max(m_band.startTick, m_band.endTick);
            if (first != last)
                return std::pair{first, last};
            return std::nullopt;
        }
        return m_laneSelection.activeTickRange();
    }();
    const uint64_t bandFirst = std::min(m_band.startTick, m_band.endTick);
    const uint64_t bandLast = std::max(m_band.startTick, m_band.endTick);
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

    struct VisibleLane {
        LaneHandle handle;
        const NodeLaneSlot *slot = nullptr;
        QRect body;
        QRectF plot;
        QRectF overflow;
        bool tempo = false;
        bool selectedLane = false;
        bool selectedNodesLane = false;
        bool bandLane = false;
        std::vector<NodePoint> points;
    };

    // Zero or one visible slot: exactly the active parameter renders and
    // hit-tests in the one full-height plot. Every other logical lane keeps
    // its adapter in m_nodeStack for shared selection, command targets, and
    // cross-lane batch edits, with the same plot rectangle for value
    // geometry.
    std::optional<VisibleLane> active;
    const LaneHandle activeHandle = activeLane();
    if (const NodeLaneSlot *slot = resolveSlot(activeHandle)) {
        const bool bandLane = bandPreviewContainsLane(activeHandle);
        const bool needsTransientPoints =
            transient &&
            (m_band.active ||
             (nodeDrag && nodeDrag->points.size() == 1 && nodeDrag->lane == activeHandle) ||
             (phantomGesture && phantomGesture->lane == activeHandle) ||
             (pencil && pencil->lane == activeHandle));
        const bool needsHoverPoints = hover && m_hoverState.hover.lane == activeHandle;
        const QRect body = slot->body;
        active = VisibleLane{.handle = activeHandle,
                             .slot = slot,
                             .body = body,
                             .plot = viewport,
                             .overflow =
                                 nodelane::nodeOverflowClip(body, m_geometry).intersected(viewport),
                             .tempo = slot->isTempo(),
                             .selectedLane = m_laneSelection.coversLane(slot->id) || bandLane,
                             .selectedNodesLane = m_laneSelection.coversNodes(slot->id) || bandLane,
                             .bandLane = bandLane,
                             .points = content || needsTransientPoints || needsHoverPoints
                                           ? slot->lane->points()
                                           : std::vector<NodePoint>{}};
    }
    const bool multipleSelectedNodes = hasMultipleSelectedNodes(selectedTickRange);

    std::vector<TimelineQuickTextModel::Record> hoverTextRecords;
    std::vector<TimelineQuickTextModel::Record> transientTextRecords;

    if (hover)
        hoverTextRecords.reserve(1);
    if (transient)
        transientTextRecords.reserve(1);
    const NodeLaneQuickPaint::Outputs outputs;
    const QColor background = opaqueColor(themes::Role::song_view_piano_roll_background);
    // One grid and one band frame span the whole viewport. The stacked
    // per-row separators, pinned Tempo header, and Add-lane strip are gone
    // with the shared plot; the gutter belongs to the QML parameter
    // selector, so its stale stacked text records are cleared, not painted.
    if (content) {
        addRect(scene.layer(TimelineQuickLayer::AutomationGrid), viewport, background, viewport);
        composeBandedGrid(scene, TimelineQuickLayer::AutomationGrid, m_page.m_owner, viewport, 0.0,
                          dpr);
        addBandFrame(scene, TimelineQuickLayer::AutomationGrid, viewport.top(), viewport.bottom(),
                     viewport.width(), viewport);
    }
    if (gutterContent) {
        addRect(scene.layer(TimelineQuickLayer::AutomationGutterChrome), gutterViewport, background,
                gutterViewport);
        addBandFrame(scene, TimelineQuickLayer::AutomationGutterChrome, viewport.top(),
                     viewport.bottom(), gutter.width(), gutterViewport);
        scene.setAutomationTextRecords({});
    }

    if (active) {
        const VisibleLane &lane = *active;
        const QColor color =
            lane.tempo
                ? themes::color(themes::Role::song_view_automation_tempo_curve)
                : themes::trackIdentityColor(lane.slot->id.track % themes::trackIdentityColorCount);
        // Unchanged phantom handoff: a provisional phantom gesture paints its
        // own held origin; otherwise the lane's origin phantom is derived from
        // its points.
        const auto phantom =
            phantomGesture && phantomGesture->lane == lane.handle
                ? std::optional<OriginPhantom>{OriginPhantom{
                      lane.handle, phantomGesture->point.current,
                      phantomGesture->point.minimumValue, phantomGesture->point.maximumValue}}
                : originPhantom(lane.handle, projection, lane.points);
        NodeLaneQuickPaint::Context context{
            .scene = scene,
            .lane = *lane.slot->lane,
            .points = lane.points,
            .body = lane.body,
            .plot = lane.plot,
            .contentYOffset = 0.0,
            .overflow = lane.overflow,
            .geometry = m_geometry,
            .projection = projection,
            .hoverState = m_hoverState,
            .handle = lane.handle,
            .color = color,
            .selectedColor = m_inputHost->palette().highlight().color(),
            .dimmedColor = m_inputHost->palette().mid().color(),
            .devicePixelRatio = dpr,
            .selectedTickRange = selectedTickRange,
            .selectedLane = lane.selectedLane,
            .selectedNodesLane = lane.selectedNodesLane,
            .bandLane = lane.bandLane,
            .bandFirstTick = bandFirst,
            .bandLastTick = bandLast,
            .multipleSelectedNodes = multipleSelectedNodes,
            .pencilMode = m_pencilMode,
            .nodeDrag = nodeDrag,
            .phantomGesture = phantomGesture,
            .sweep = sweep,
            .pencil = pencil,
            .phantom = phantom,
        };
        NodeLaneQuickPaint::Context staticContext = context;
        if (m_band.active) {
            staticContext.selectedTickRange = std::nullopt;
            staticContext.selectedLane = false;
            staticContext.selectedNodesLane = false;
            staticContext.bandLane = false;
            staticContext.multipleSelectedNodes = false;
        }
        NodeLaneQuickPaint::composeStatic(staticContext, content, content,
                                          content && !m_band.active);
        NodeLaneQuickPaint::composeTransient(context, transient, m_band.active, outputs);
        NodeLaneQuickPaint::composeHover(context, hover, outputs);
    }
    // Plot value labels keep their pre-clip rectangles and clip against the
    // lane overflow, unchanged from the stacked renderer.
    const auto appendValueLabel = [&active](std::vector<TimelineQuickTextModel::Record> &records,
                                            TimelineQuickTextKeyKind kind,
                                            const NodeLaneHoverState::ValueLabelCache &label) {
        if (!label.valid || label.text.isEmpty() || !active || active->handle != label.lane)
            return;
        appendText(records, kind, quint64(label.lane.index), QRectF(label.rect), label.text,
                   themes::color(themes::Role::song_view_primary_text), label.font,
                   Qt::AlignHCenter, active->overflow);
    };
    if (hover)
        appendValueLabel(hoverTextRecords, TimelineQuickTextKeyKind::AutomationHover,
                         m_hoverState.hoverValueLabel);
    if (transient && m_activeGesture)
        appendValueLabel(transientTextRecords, TimelineQuickTextKeyKind::AutomationTransient,
                         m_hoverState.previewValueLabel);

    if (hover)
        scene.setAutomationHoverTextRecords(hoverTextRecords);
    if (transient)
        scene.setAutomationTransientTextRecords(transientTextRecords);
}
