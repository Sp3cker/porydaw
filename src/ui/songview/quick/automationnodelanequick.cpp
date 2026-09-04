#include "ui/songview/quick/automationnodelanequick.h"

#include <algorithm>

#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace songview {
namespace {

using timeline_quick::addEllipse;
using timeline_quick::addEllipseRing;
using timeline_quick::addLine;
using timeline_quick::addRect;
using timeline_quick::addSelectionReticle;

struct PointReplacement {
    NodePoint original;
    NodePoint current;
};

bool isReplaced(const NodePoint &point, const std::optional<PointReplacement> &replacement)
{
    if (!replacement)
        return false;
    if (point.tick == replacement->original.tick && point.value == replacement->original.value)
        return true;
    return replacement->current.tick != replacement->original.tick &&
           point.tick == replacement->current.tick;
}

bool fullLaneOmitted(const NodeLaneQuickPaint::Context &context)
{
    if (context.pencil && context.pencil->lane == context.handle)
        return true;
    if (!context.nodeDrag || context.nodeDrag->points.size() < 2)
        return false;
    return std::any_of(context.nodeDrag->points.cbegin(), context.nodeDrag->points.cend(),
                       [&context](const NodeDrag &point) { return point.lane == context.handle; });
}

std::optional<PointReplacement> pointReplacement(const NodeLaneQuickPaint::Context &context)
{
    if (context.nodeDrag && context.nodeDrag->points.size() == 1 &&
        context.nodeDrag->lane == context.handle &&
        context.nodeDrag->grabbedPoint < context.nodeDrag->points.size()) {
        const NodeDrag &point = context.nodeDrag->points[context.nodeDrag->grabbedPoint];
        return PointReplacement{point.original, point.current};
    }
    if (context.phantomGesture && context.phantomGesture->lane == context.handle) {
        const NodeDrag &point = context.phantomGesture->point;
        return PointReplacement{point.original, point.current};
    }
    return std::nullopt;
}

bool pointSelected(const NodeLaneQuickPaint::Context &context, uint64_t tick)
{
    if (context.selectedNodesLane && context.selectedTickRange) {
        const auto [firstTick, lastTick] = *context.selectedTickRange;
        if (tick >= firstTick && tick < lastTick)
            return true;
    }
    return context.bandLane && tick >= context.bandFirstTick && tick < context.bandLastTick;
}

void addNode(TimelineQuickScene &scene, TimelineQuickLayer layer,
             const NodeLaneQuickPaint::Context &context, const QPointF &center, const QColor &color,
             bool selected = false, bool dimUnselected = false)
{
    if (selected && context.selectedColor.isValid()) {
        addEllipseRing(scene, layer, center, context.geometry.selectedNodeRingRadius,
                       context.geometry.selectedNodeRingRadius,
                       context.geometry.selectedNodeRingDipWidth, context.selectedColor,
                       context.overflow);
    }
    if (dimUnselected && !selected) {
        const QColor dimmed = context.dimmedColor.isValid()
                                  ? context.dimmedColor
                                  : themes::color(themes::Role::song_view_secondary_text);
        addEllipse(scene, layer, center, context.geometry.nodePaintRadius,
                   context.geometry.nodePaintRadius, dimmed, context.overflow);
        return;
    }
    addEllipse(scene, layer, center, context.geometry.nodePaintRadius,
               context.geometry.nodePaintRadius,
               themes::color(themes::Role::song_view_piano_roll_background), context.overflow);
    addEllipseRing(scene, layer, center, context.geometry.nodePaintRadius,
                   context.geometry.nodePaintRadius, context.geometry.nodeOutlineDipWidth * 2.0,
                   color, context.overflow);
}

qreal nodeY(const NodeLaneQuickPaint::Context &context, int value)
{
    return nodelane::valueY(context.lane, context.body, context.geometry, value);
}

qreal tickX(const NodeLaneQuickPaint::Context &context, uint64_t tick)
{
    return context.projection.displayX(tick, context.devicePixelRatio);
}

void addStepCurve(const NodeLaneQuickPaint::Context &context, TimelineQuickLayer layer,
                  std::span<const NodePoint> points, const QColor &color,
                  const std::optional<PointReplacement> &replacement)
{
    if (points.empty())
        return;
    const qreal width = layout::singlePixel() + layout::singlePixel();
    if (const std::optional<NodePoint> leadIn = context.lane.leadIn()) {
        const qreal x = tickX(context, points.front().tick);
        const qreal y = nodeY(context, points.front().value);
        const qreal leadY = nodeY(context, leadIn->value);
        addLine(context.scene, layer, QPointF(tickX(context, leadIn->tick), leadY),
                QPointF(x, leadY), width, color, context.plot);
        if (y != leadY)
            addLine(context.scene, layer, QPointF(x, leadY), QPointF(x, y), width, color,
                    context.plot);
    }
    for (std::size_t index = 0; index < points.size(); ++index) {
        const bool currentOmitted = isReplaced(points[index], replacement);
        const bool nextOmitted =
            index + 1 < points.size() && isReplaced(points[index + 1], replacement);
        if (currentOmitted || nextOmitted)
            continue;
        const qreal x0 = tickX(context, points[index].tick);
        const qreal x1 = index + 1 < points.size() ? tickX(context, points[index + 1].tick)
                                                   : context.plot.right();
        if (x1 < context.plot.left() || x0 > context.plot.right())
            continue;
        const qreal y = nodeY(context, points[index].value);
        addLine(context.scene, layer, QPointF(x0, y), QPointF(x1, y), width, color, context.plot);
        if (index + 1 < points.size()) {
            addLine(context.scene, layer, QPointF(x1, y),
                    QPointF(x1, nodeY(context, points[index + 1].value)), width, color,
                    context.plot);
        }
    }
}

void addNodes(const NodeLaneQuickPaint::Context &context, TimelineQuickLayer layer,
              std::span<const NodePoint> points, const QColor &color,
              const std::optional<PointReplacement> &replacement)
{
    if (!context.projection.nodeMarkersVisible())
        return;
    const qreal nodeExtent =
        std::max<qreal>(context.geometry.nodePaintRadius, context.geometry.selectedNodeRingRadius) +
        layout::singlePixel();
    const bool dimLane = context.multipleSelectedNodes && !context.selectedLane;
    const auto addPass = [&](bool selectedPass) {
        for (const NodePoint &point : points) {
            if (isReplaced(point, replacement))
                continue;
            const bool selected = pointSelected(context, point.tick);
            if (selected != selectedPass)
                continue;
            const QPointF center(tickX(context, point.tick), nodeY(context, point.value));
            const QRectF bounds(center.x() - nodeExtent, center.y() - nodeExtent, 2 * nodeExtent,
                                2 * nodeExtent);
            if (!bounds.intersects(context.overflow))
                continue;
            addNode(context.scene, layer, context, center, color, selected, dimLane);
        }
    };
    addPass(false);
    addPass(true);
}

void addPhantomCurvePreview(const NodeLaneQuickPaint::Context &context, TimelineQuickLayer layer,
                            std::span<const NodePoint> points, const OriginPhantom &phantom)
{
    const auto next =
        std::upper_bound(points.begin(), points.end(), phantom.point.tick,
                         [](uint64_t tick, const NodePoint &point) { return tick < point.tick; });
    const qreal y =
        AutomationProjection::valueY(context.body, context.geometry, phantom.minimumValue,
                                     phantom.maximumValue, phantom.point.value);
    const qreal nextX = next == points.end() ? context.plot.right() : tickX(context, next->tick);
    const QColor preview = themes::color(themes::Role::song_view_edit_preview_outline);
    addLine(context.scene, layer, QPointF(context.plot.left(), y), QPointF(nextX, y),
            layout::singlePixel(), preview, context.plot);
    if (next != points.end()) {
        addLine(context.scene, layer, QPointF(nextX, y),
                QPointF(nextX, AutomationProjection::valueY(context.body, context.geometry,
                                                            phantom.minimumValue,
                                                            phantom.maximumValue, next->value)),
                layout::singlePixel(), preview, context.plot);
    }
}

void addPhantomNode(const NodeLaneQuickPaint::Context &context, TimelineQuickLayer layer,
                    const OriginPhantom &phantom, const QColor &color)
{
    const QPointF center(context.plot.left(),
                         AutomationProjection::valueY(context.body, context.geometry,
                                                      phantom.minimumValue, phantom.maximumValue,
                                                      phantom.point.value));
    addNode(context.scene, layer, context, center, color);
}

void appendValueLabel(std::vector<TimelineQuickTextModel::Record> *records,
                      TimelineQuickTextKeyKind kind, const NodeLaneQuickPaint::Context &context,
                      const NodeLaneHoverState::ValueLabelCache &label)
{
    if (!records || !label.valid || label.lane != context.handle)
        return;
    const QRectF rect =
        label.rect.translated(0.0, -context.contentYOffset).intersected(context.overflow);
    if (rect.isEmpty() || label.text.isEmpty())
        return;
    records->push_back({{kind, {}, quint64(context.handle.index)},
                        rect,
                        label.text,
                        themes::color(themes::Role::song_view_primary_text),
                        label.font,
                        Qt::AlignHCenter,
                        Qt::AlignVCenter});
}

void addValueLabelBackdrop(const NodeLaneQuickPaint::Context &context, TimelineQuickLayer layer,
                           const NodeLaneHoverState::ValueLabelCache &label)
{
    if (!label.valid || label.lane != context.handle)
        return;
    const qreal padding = layout::singlePixel();
    const QRectF bounds = QRectF(label.bounds)
                              .translated(0.0, -context.contentYOffset)
                              .adjusted(-padding, -padding, padding, padding);
    addRect(context.scene, layer, bounds,
            themes::color(themes::Role::song_view_piano_roll_accidental_lane), context.overflow);
}

void addPreviewLabel(const NodeLaneQuickPaint::Context &context,
                     const NodeLaneQuickPaint::Outputs &outputs)
{
    const auto &label = context.hoverState.previewValueLabel;
    if (!label.valid || label.lane != context.handle)
        return;
    addValueLabelBackdrop(context, TimelineQuickLayer::AutomationTransient, label);
    appendValueLabel(outputs.transientText, TimelineQuickTextKeyKind::AutomationTransient, context,
                     label);
}

void addSingleDragPreview(const NodeLaneQuickPaint::Context &context,
                          const NodeLaneQuickPaint::Outputs &outputs,
                          const NodeDragGesture &gesture)
{
    if (gesture.grabbedPoint >= gesture.points.size() || gesture.lane != context.handle)
        return;
    const NodeDrag &grabbed = gesture.points[gesture.grabbedPoint];
    const auto sameOriginal = [&grabbed](const NodePoint &point) {
        return point.tick == grabbed.original.tick && point.value == grabbed.original.value;
    };
    const NodePoint *previous = nullptr;
    const NodePoint *next = nullptr;
    for (const NodePoint &point : context.points) {
        if (sameOriginal(point) || point.tick == grabbed.current.tick)
            continue;
        if (point.tick < grabbed.current.tick) {
            previous = &point;
            continue;
        }
        next = &point;
        break;
    }
    const QColor preview = themes::color(themes::Role::song_view_edit_preview_outline);
    const qreal x = tickX(context, grabbed.current.tick);
    const qreal y = nodeY(context, grabbed.current.value);
    if (previous) {
        const qreal previousY = nodeY(context, previous->value);
        addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                QPointF(tickX(context, previous->tick), previousY), QPointF(x, previousY),
                layout::singlePixel(), preview, context.plot);
        addLine(context.scene, TimelineQuickLayer::AutomationTransient, QPointF(x, previousY),
                QPointF(x, y), layout::singlePixel(), preview, context.plot);
    }
    const qreal nextX = next ? tickX(context, next->tick) : context.plot.right();
    addLine(context.scene, TimelineQuickLayer::AutomationTransient, QPointF(x, y),
            QPointF(nextX, y), layout::singlePixel(), preview, context.plot);
    if (next) {
        addLine(context.scene, TimelineQuickLayer::AutomationTransient, QPointF(nextX, y),
                QPointF(nextX, nodeY(context, next->value)), layout::singlePixel(), preview,
                context.plot);
    }
    addNode(context.scene, TimelineQuickLayer::AutomationTransient, context, QPointF(x, y),
            preview);
    addPreviewLabel(context, outputs);
}

void addMultiDragPreview(const NodeLaneQuickPaint::Context &context,
                         const NodeLaneQuickPaint::Outputs &outputs, const NodeDragGesture &gesture)
{
    if (!context.handle.valid() || context.handle.index >= int(gesture.previewPoints.size()))
        return;
    const std::vector<NodePoint> &preview =
        gesture.previewPoints[std::size_t(context.handle.index)];
    if (preview.empty())
        return;
    const QColor curve = context.multipleSelectedNodes && !context.selectedLane
                             ? context.dimmedColor
                             : context.color;
    addStepCurve(context, TimelineQuickLayer::AutomationTransient, preview, curve, std::nullopt);
    addNodes(context, TimelineQuickLayer::AutomationTransient, preview, context.color,
             std::nullopt);
    if (context.handle.index >= int(gesture.pointIndexesByLane.size()))
        return;
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    for (const std::size_t index : gesture.pointIndexesByLane[std::size_t(context.handle.index)]) {
        if (index >= gesture.points.size())
            continue;
        const NodeDrag &point = gesture.points[index];
        const QPointF center(tickX(context, point.current.tick),
                             nodeY(context, point.current.value));
        addNode(context.scene, TimelineQuickLayer::AutomationTransient, context, center,
                previewColor, true);
        if (index == gesture.grabbedPoint)
            addPreviewLabel(context, outputs);
    }
}

void addSweepPreview(const NodeLaneQuickPaint::Context &context,
                     const NodeLaneQuickPaint::Outputs &outputs, const SweepGesture &gesture)
{
    if (gesture.lane != context.handle)
        return;
    const QColor preview = themes::color(themes::Role::song_view_edit_preview_outline);
    if (gesture.mode == SweepGesture::Mode::Ramp) {
        addLine(
            context.scene, TimelineQuickLayer::AutomationTransient,
            QPointF(tickX(context, gesture.anchor.tick), nodeY(context, gesture.anchor.value)),
            QPointF(tickX(context, gesture.current.tick), nodeY(context, gesture.current.value)),
            layout::singlePixel(), preview, context.plot);
    } else if (gesture.points.size() > 1) {
        for (std::size_t index = 0; index + 1 < gesture.points.size(); ++index) {
            const qreal y = nodeY(context, gesture.points[index].value);
            const qreal nextX = tickX(context, gesture.points[index + 1].tick);
            addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                    QPointF(tickX(context, gesture.points[index].tick), y), QPointF(nextX, y),
                    layout::singlePixel(), preview, context.plot);
            addLine(context.scene, TimelineQuickLayer::AutomationTransient, QPointF(nextX, y),
                    QPointF(nextX, nodeY(context, gesture.points[index + 1].value)),
                    layout::singlePixel(), preview, context.plot);
        }
    }
    addNode(context.scene, TimelineQuickLayer::AutomationTransient, context,
            QPointF(tickX(context, gesture.current.tick), nodeY(context, gesture.current.value)),
            preview);
    addPreviewLabel(context, outputs);
}

void addPencilPreview(const NodeLaneQuickPaint::Context &context,
                      const NodeLaneQuickPaint::Outputs &outputs, const PencilGesture &gesture)
{
    if (gesture.lane != context.handle)
        return;
    const NodeLaneEdit::Completion &preview = gesture.stroke.preview();
    const auto addHeld = [&](uint64_t first, uint64_t last, int value, const QColor &color) {
        if (first >= last)
            return;
        addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                QPointF(tickX(context, first), nodeY(context, value)),
                QPointF(tickX(context, last), nodeY(context, value)),
                layout::singlePixel() + layout::singlePixel(), color, context.plot);
    };
    std::optional<int> heldBefore;
    const NodePoint *nextAfterRange = nullptr;
    for (const NodePoint &point : context.points) {
        if (point.tick < preview.tickBegin)
            heldBefore = point.value;
        if (point.tick > preview.tickEnd) {
            nextAfterRange = &point;
            break;
        }
    }
    for (std::size_t index = 0; index < context.points.size(); ++index) {
        const NodePoint &point = context.points[index];
        const uint64_t nextTick =
            index + 1 < context.points.size() ? context.points[index + 1].tick : preview.tickBegin;
        if (point.tick < preview.tickBegin) {
            addHeld(point.tick, std::min(nextTick, preview.tickBegin), point.value, context.color);
            if (nextTick < preview.tickBegin) {
                addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                        QPointF(tickX(context, nextTick), nodeY(context, point.value)),
                        QPointF(tickX(context, nextTick),
                                nodeY(context, context.points[index + 1].value)),
                        layout::singlePixel() + layout::singlePixel(), context.color, context.plot);
            }
        } else if (point.tick > preview.tickEnd) {
            if (index + 1 < context.points.size()) {
                const uint64_t last = context.points[index + 1].tick;
                addHeld(point.tick, last, point.value, context.color);
                addLine(
                    context.scene, TimelineQuickLayer::AutomationTransient,
                    QPointF(tickX(context, last), nodeY(context, point.value)),
                    QPointF(tickX(context, last), nodeY(context, context.points[index + 1].value)),
                    layout::singlePixel() + layout::singlePixel(), context.color, context.plot);
            } else {
                addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                        QPointF(tickX(context, point.tick), nodeY(context, point.value)),
                        QPointF(context.plot.right(), nodeY(context, point.value)),
                        layout::singlePixel() + layout::singlePixel(), context.color, context.plot);
            }
        }
    }
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    std::optional<int> previewValue = heldBefore;
    uint64_t cursor = preview.tickBegin;
    for (const NodePoint &point : preview.points) {
        if (point.tick < preview.tickBegin || point.tick > preview.tickEnd)
            continue;
        if (previewValue)
            addHeld(cursor, point.tick, *previewValue, previewColor);
        if (previewValue && *previewValue != point.value) {
            addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                    QPointF(tickX(context, point.tick), nodeY(context, *previewValue)),
                    QPointF(tickX(context, point.tick), nodeY(context, point.value)),
                    layout::singlePixel(), previewColor, context.plot);
        }
        previewValue = point.value;
        cursor = point.tick;
    }
    if (previewValue)
        addHeld(cursor, preview.tickEnd, *previewValue, previewColor);
    if (previewValue && nextAfterRange) {
        addHeld(preview.tickEnd, nextAfterRange->tick, *previewValue, previewColor);
        if (*previewValue != nextAfterRange->value) {
            addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                    QPointF(tickX(context, nextAfterRange->tick), nodeY(context, *previewValue)),
                    QPointF(tickX(context, nextAfterRange->tick),
                            nodeY(context, nextAfterRange->value)),
                    layout::singlePixel(), previewColor, context.plot);
        }
    } else if (previewValue) {
        addLine(context.scene, TimelineQuickLayer::AutomationTransient,
                QPointF(tickX(context, preview.tickEnd), nodeY(context, *previewValue)),
                QPointF(context.plot.right(), nodeY(context, *previewValue)),
                layout::singlePixel() + layout::singlePixel(), previewColor, context.plot);
    }
    if (context.projection.nodeMarkersVisible()) {
        const qreal nodeExtent = context.geometry.nodePaintRadius + layout::singlePixel();
        for (const NodePoint &point : context.points) {
            if (point.tick >= preview.tickBegin && point.tick <= preview.tickEnd)
                continue;
            const QPointF center(tickX(context, point.tick), nodeY(context, point.value));
            const QRectF bounds(center.x() - nodeExtent, center.y() - nodeExtent, 2 * nodeExtent,
                                2 * nodeExtent);
            if (bounds.intersects(context.overflow))
                addNode(context.scene, TimelineQuickLayer::AutomationTransient, context, center,
                        context.color);
        }
        for (const NodePoint &point : preview.points) {
            const QPointF center(tickX(context, point.tick), nodeY(context, point.value));
            const QRectF bounds(center.x() - nodeExtent, center.y() - nodeExtent, 2 * nodeExtent,
                                2 * nodeExtent);
            if (bounds.intersects(context.overflow))
                addNode(context.scene, TimelineQuickLayer::AutomationTransient, context, center,
                        previewColor);
        }
    }
    addPreviewLabel(context, outputs);
}

void addBandNodes(const NodeLaneQuickPaint::Context &context)
{
    if (!context.projection.nodeMarkersVisible())
        return;
    const qreal extent =
        std::max<qreal>(context.geometry.nodePaintRadius, context.geometry.selectedNodeRingRadius) +
        layout::singlePixel();
    for (const NodePoint &point : context.points) {
        const QPointF center(tickX(context, point.tick), nodeY(context, point.value));
        const QRectF bounds(center.x() - extent, center.y() - extent, 2 * extent, 2 * extent);
        if (!bounds.intersects(context.overflow))
            continue;
        const bool selected = pointSelected(context, point.tick);
        if (selected)
            addNode(context.scene, TimelineQuickLayer::AutomationTransient, context, center,
                    context.color, true);
        else if (context.multipleSelectedNodes && !context.selectedLane)
            addNode(context.scene, TimelineQuickLayer::AutomationTransient, context, center,
                    context.color, false, true);
    }
}

} // namespace

void NodeLaneQuickPaint::composeStatic(const Context &context, bool curves, bool nodes,
                                       bool selection)
{
    const bool omitted = fullLaneOmitted(context);
    const std::optional<PointReplacement> replacement = pointReplacement(context);
    if (curves && !omitted) {
        const QColor curveColor = context.multipleSelectedNodes && !context.selectedLane
                                      ? context.dimmedColor
                                      : context.color;
        addStepCurve(context, TimelineQuickLayer::AutomationCurves, context.points, curveColor,
                     replacement);
    }
    if (nodes && !omitted) {
        addNodes(context, TimelineQuickLayer::AutomationNodes, context.points, context.color,
                 replacement);
        if (context.phantom && !context.phantomGesture) {
            addPhantomNode(context, TimelineQuickLayer::AutomationNodes, *context.phantom,
                           context.color);
        }
    }
    if (selection && context.selectedTickRange && context.selectedLane) {
        const auto [firstTick, lastTick] = *context.selectedTickRange;
        const QRectF bounds(context.plot.left(), context.body.top(), context.plot.width(),
                            context.body.height());
        addSelectionReticle(context.scene, TimelineQuickLayer::AutomationSelection,
                            QRectF(tickX(context, firstTick), bounds.top(),
                                   tickX(context, lastTick) - tickX(context, firstTick),
                                   bounds.height()),
                            context.plot);
    }
}

void NodeLaneQuickPaint::composeTransient(const Context &context, bool transient,
                                          bool bandSelection, const Outputs &outputs)
{
    if (!transient)
        return;
    if (context.nodeDrag) {
        if (context.nodeDrag->points.size() > 1)
            addMultiDragPreview(context, outputs, *context.nodeDrag);
        else
            addSingleDragPreview(context, outputs, *context.nodeDrag);
    } else if (context.phantomGesture && context.phantomGesture->lane == context.handle &&
               context.phantom) {
        addPhantomCurvePreview(context, TimelineQuickLayer::AutomationTransient, context.points,
                               *context.phantom);
        addPhantomNode(context, TimelineQuickLayer::AutomationTransient, *context.phantom,
                       themes::color(themes::Role::song_view_edit_preview_outline));
        addPreviewLabel(context, outputs);
    } else if (context.sweep) {
        addSweepPreview(context, outputs, *context.sweep);
    } else if (context.pencil) {
        addPencilPreview(context, outputs, *context.pencil);
    }
    if (bandSelection) {
        addBandNodes(context);
        if (context.selectedTickRange && context.selectedLane) {
            const auto [firstTick, lastTick] = *context.selectedTickRange;
            const QRectF bounds(context.plot.left(), context.body.top(), context.plot.width(),
                                context.body.height());
            addSelectionReticle(context.scene, TimelineQuickLayer::AutomationTransient,
                                QRectF(tickX(context, firstTick), bounds.top(),
                                       tickX(context, lastTick) - tickX(context, firstTick),
                                       bounds.height()),
                                context.plot);
        }
    }
}

void NodeLaneQuickPaint::composeHover(const Context &context, bool hover, const Outputs &outputs)
{
    if (!hover || context.hoverState.hover.lane != context.handle)
        return;
    const NodeLaneHoverState::HoverState &hoverState = context.hoverState.hover;
    const qreal x =
        tickX(context, uint64_t(std::max(0.0, context.hoverState.insertionTick(
                                                  context.projection, context.pencilMode))));
    const QString &text = context.hoverState.hoverTextCache.text;
    const auto &label = context.hoverState.hoverValueLabel;
    if (hoverState.hasPoint) {
        const qreal displayX =
            hoverState.originPhantom ? context.plot.left() : tickX(context, hoverState.point.tick);
        addEllipseRing(context.scene, TimelineQuickLayer::AutomationHover,
                       QPointF(displayX, nodeY(context, hoverState.point.value)),
                       nodelane::hoverRingRadius(context.geometry),
                       nodelane::hoverRingRadius(context.geometry), 2 * layout::singlePixel(),
                       themes::color(themes::Role::song_view_edit_preview_outline), context.plot);
    }
    if (context.pencilMode) {
        if (!hoverState.hasPoint) {
            const int value = AutomationProjection::valueAtY(
                context.body, context.geometry, context.lane.minimumValue(),
                context.lane.maximumValue(), hoverState.pos.y() - context.contentYOffset);
            addNode(context.scene, TimelineQuickLayer::AutomationHover, context,
                    QPointF(x, nodeY(context, value)),
                    themes::color(themes::Role::song_view_edit_preview_outline));
        }
    } else {
        if (!hoverState.hasPoint) {
            const double tick = context.hoverState.insertionTick(context.projection, false);
            const auto position =
                std::upper_bound(context.points.begin(), context.points.end(), tick,
                                 [](double current, const NodePoint &point) {
                                     return current < double(point.tick);
                                 });
            if (position != context.points.begin()) {
                const NodePoint &held = *std::prev(position);
                addNode(context.scene, TimelineQuickLayer::AutomationHover, context,
                        QPointF(x, nodeY(context, held.value)),
                        themes::color(themes::Role::song_view_edit_preview_outline));
            }
        }
    }
    if (!text.isEmpty() && label.valid && label.lane == context.handle) {
        addValueLabelBackdrop(context, TimelineQuickLayer::AutomationHover, label);
        appendValueLabel(outputs.hoverText, TimelineQuickTextKeyKind::AutomationHover, context,
                         label);
    }
}

} // namespace songview
