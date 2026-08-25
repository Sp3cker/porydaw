#include "ui/editordrawer/nodelane/hover.h"

#include <algorithm>

#include "ui/editordrawer/automationprojection.h"
#include <QFontMetrics>
#include <QRegion>

#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/nodelane/paint.h"
#include "ui/layout.h"
#include "ui/typography.h"

namespace {

int valueAtY(const NodeLane &lane, const QRect &body, const AutomationGeometry &geometry, qreal y)
{
    return std::clamp(qRound(AutomationProjection::valueAtY(body, geometry, lane.minimumValue(),
                                                            lane.maximumValue(), y)),
                      lane.minimumValue(), lane.maximumValue());
}

} // namespace

void NodeLaneHoverState::invalidateCaches()
{
    pointCache = {};
    hoverTextCache = {};
}

void NodeLaneHoverState::invalidateFontCache()
{
    m_valueLabelFontCache = {};
}

const std::vector<NodePoint> &
NodeLaneHoverState::cachedPoints(const NodeLane &lane, LaneHandle handle, uint64_t revision) const
{
    if (pointCache.valid && pointCache.handle == handle && pointCache.revision == revision)
        return pointCache.points;
    pointCache.points = lane.points();
    pointCache.handle = handle;
    pointCache.revision = revision;
    pointCache.valid = true;
    return pointCache.points;
}

double NodeLaneHoverState::hoverTick(const AutomationProjection &projection) const
{
    return hover.hasPoint ? double(hover.point.tick) : projection.rawTickAt(hover.pos.x());
}

double NodeLaneHoverState::insertionTick(const AutomationProjection &projection,
                                         bool pencilMode) const
{
    const double tick = hoverTick(projection);
    if (hover.hasPoint)
        return tick;
    if (!pencilMode)
        return double(projection.fineSnapTick(tick));
    return double(projection.snapCellAt(tick).tickBegin);
}

int NodeLaneHoverState::hoverValue(const NodeLane &lane, const QRect &body,
                                   const AutomationGeometry &geometry) const
{
    return hover.hasPoint ? hover.point.value : valueAtY(lane, body, geometry, hover.pos.y());
}

bool NodeLaneHoverState::hoverValueFor(const NodeLane &lane, const QRect &body,
                                       const AutomationGeometry &geometry,
                                       const AutomationProjection &, double tick, bool pencilMode,
                                       uint64_t revision, int *value) const
{
    if (hover.hasPoint || pencilMode) {
        *value = hoverValue(lane, body, geometry);
        return true;
    }
    const auto &points = cachedPoints(lane, hover.lane, revision);
    const NodePoint *held = nullptr;
    for (const auto &point : points) {
        if (double(point.tick) > tick)
            break;
        held = &point;
    }
    if (!held)
        return false;
    *value = held->value;
    return true;
}

QString NodeLaneHoverState::hoverTextFor(const NodeLaneHoverTarget &target, const NodeLane &lane,
                                         const QRect &body, const AutomationGeometry &geometry,
                                         const AutomationProjection &projection, double tick,
                                         bool pencilMode) const
{
    if (!target.ready)
        return {};
    int value = 0;
    return hoverValueFor(lane, body, geometry, projection, tick, pencilMode,
                         target.documentRevision, &value)
               ? lane.valueText(value)
               : QString{};
}

const QString &NodeLaneHoverState::hoverTextCached(const NodeLaneHoverTarget &target,
                                                   const NodeLane &lane, const QRect &body,
                                                   const AutomationGeometry &geometry,
                                                   const AutomationProjection &projection,
                                                   double tick, qreal x, bool pencilMode) const
{
    const uint64_t revision = target.documentRevision;
    if (hoverTextCache.key == HoverTextCache::Key{hover.lane, tick, x, revision, pencilMode})
        return hoverTextCache.text;
    hoverTextCache.text = hoverTextFor(target, lane, body, geometry, projection, tick, pencilMode);
    hoverTextCache.key = {hover.lane, tick, x, revision, pencilMode};
    return hoverTextCache.text;
}

QRect NodeLaneHoverState::hoverValueRect(const NodeLaneHoverTarget &target, const NodeLane &lane,
                                         const QRect &body, const AutomationGeometry &geometry,
                                         const AutomationProjection &projection, qreal x,
                                         bool pencilMode) const
{
    const QRect plot = nodelane::plotRect(body, geometry);
    qreal anchorX = x;
    int mappedValue = 0;
    if (!hoverValueFor(lane, body, geometry, projection, insertionTick(projection, pencilMode),
                       pencilMode, target.documentRevision, &mappedValue))
        return {};
    if (hover.hasPoint)
        anchorX = hover.originPhantom
                      ? qreal(plot.left())
                      : projection.displayX(hover.point.tick, target.devicePixelRatio);
    const int anchorY = qRound(nodelane::valueY(lane, body, geometry, mappedValue));
    const auto &fontCache = valueLabelFontCache(target.font);
    const int textWidth = fontCache.width;
    const int textHeight = fontCache.height;
    const int gap = layout::space(layout::Space::One);
    int textX = qCeil(anchorX - gap - textWidth);
    int textY = anchorY - gap - textHeight;
    if (textX < plot.left())
        textX = qFloor(anchorX + gap);
    if (textY < plot.top())
        textY = anchorY + gap;
    textX = std::clamp(textX, plot.left(), std::max(plot.left(), plot.right() - textWidth + 1));
    textY = std::clamp(textY, plot.top(), std::max(plot.top(), plot.bottom() - textHeight + 1));
    return {textX, textY, textWidth, textHeight};
}

QRect NodeLaneHoverState::hoverPaintBounds(const NodeLaneHoverTarget &target, const NodeLane *lane,
                                           const QRect &body, const AutomationGeometry &geometry,
                                           const AutomationProjection &projection,
                                           bool pencilMode) const
{
    if (!target.ready || !lane || !hover.lane.valid())
        return {};
    const double tick = insertionTick(projection, pencilMode);
    const QRect plot = nodelane::plotRect(body, geometry);
    const qreal x = projection.displayX(uint64_t(std::max(0.0, tick)), target.devicePixelRatio);
    const QString &text = hoverTextCache.text;
    const int paintPadding = geometry.hoverPaintPadding;
    QRect bounds =
        QRectF(x - paintPadding, plot.top(), 2 * paintPadding, plot.height()).toAlignedRect();
    if (hover.hasPoint) {
        const qreal nodeRadius = nodelane::hoverRingRadius(geometry);
        const qreal outerRadius = nodeRadius + paintPadding;
        const qreal centerX = hover.originPhantom
                                  ? qreal(plot.left())
                                  : projection.displayX(hover.point.tick, target.devicePixelRatio);
        const QPointF center(centerX, nodelane::valueY(*lane, body, geometry, hover.point.value));
        bounds = bounds.united(QRectF(center.x() - outerRadius, center.y() - outerRadius,
                                      2 * outerRadius, 2 * outerRadius)
                                   .toAlignedRect());
    } else {
        const qreal outerRadius =
            geometry.nodePaintRadius + geometry.nodeOutlineDipWidth + paintPadding;
        if (pencilMode) {
            const QPointF center(
                x, nodelane::valueY(*lane, body, geometry, hoverValue(*lane, body, geometry)));
            bounds = bounds.united(QRectF(center.x() - outerRadius, center.y() - outerRadius,
                                          2 * outerRadius, 2 * outerRadius)
                                       .toAlignedRect());
        } else {
            int heldValue = 0;
            if (hoverValueFor(*lane, body, geometry, projection, tick, false,
                              target.documentRevision, &heldValue)) {
                const QPointF center(x, nodelane::valueY(*lane, body, geometry, heldValue));
                bounds = bounds.united(QRectF(center.x() - outerRadius, center.y() - outerRadius,
                                              2 * outerRadius, 2 * outerRadius)
                                           .toAlignedRect());
            }
        }
    }
    if (text.isEmpty())
        return bounds.intersected(target.widgetBounds);
    if (hoverValueLabel.valid && hoverValueLabel.lane == hover.lane)
        bounds = bounds.united(hoverValueLabel.bounds.adjusted(-paintPadding, -paintPadding,
                                                               paintPadding, paintPadding));
    return bounds.intersected(target.widgetBounds);
}

const NodeLaneHoverState::ValueLabelFontCache &
NodeLaneHoverState::valueLabelFontCache(const QFont &font) const
{
    if (!m_valueLabelFontCache.valid) {
        m_valueLabelFontCache.font = typography::noteName(font);
        const QFontMetrics metrics(m_valueLabelFontCache.font);
        m_valueLabelFontCache.width = metrics.horizontalAdvance(QStringLiteral("0000"));
        m_valueLabelFontCache.height = metrics.height();
        m_valueLabelFontCache.valid = true;
    }
    return m_valueLabelFontCache;
}

NodeLaneHoverState::ClampedValueLabel
NodeLaneHoverState::clampedValueLabel(qreal x, int y, const QRect &plot,
                                      const ValueLabelFontCache &fontCache) const
{
    const int gap = layout::space(layout::Space::One);
    const int half = layout::space(layout::Space::Half);
    const int width = fontCache.width;
    const int height = fontCache.height;
    QRect textRect(qCeil(x + gap + half), y - gap - height, width, height);
    if (textRect.right() > plot.right())
        textRect.moveRight(plot.right());
    if (textRect.left() < plot.left())
        textRect.moveLeft(plot.left());
    if (textRect.top() < plot.top())
        textRect.moveTop(plot.top());
    if (textRect.bottom() > plot.bottom())
        textRect.moveBottom(plot.bottom());
    return {textRect};
}

QRegion NodeLaneHoverState::updateHoverValueLabel(const NodeLaneHoverTarget &target,
                                                  const AutomationGeometry &geometry,
                                                  const NodeLane *lane, const QRect &body,
                                                  const AutomationProjection &projection,
                                                  bool pencilMode)
{
    const QRect previousBounds = hoverDirtyBounds;
    hoverValueLabel = {};
    const auto syncDirtyBounds = [&] {
        hoverDirtyBounds = hoverPaintBounds(target, lane, body, geometry, projection, pencilMode);
    };
    const auto dirtyRegion = [this, previousBounds] {
        QRegion dirty(previousBounds);
        dirty += hoverDirtyBounds;
        return dirty;
    };
    if (!target.ready || !lane || !hover.lane.valid()) {
        syncDirtyBounds();
        return dirtyRegion();
    }
    const double tick = insertionTick(projection, pencilMode);
    const qreal x = projection.displayX(uint64_t(std::max(0.0, tick)), target.devicePixelRatio);
    const QString &text =
        hoverTextCached(target, *lane, body, geometry, projection, tick, x, pencilMode);
    if (text.isEmpty()) {
        syncDirtyBounds();
        return dirtyRegion();
    }
    auto &label = hoverValueLabel;
    label.lane = hover.lane;
    const auto &fontCache = valueLabelFontCache(target.font);
    label.font = fontCache.font;
    const QRect plot = nodelane::plotRect(body, geometry);
    if (pencilMode) {
        const int gap = layout::space(layout::Space::One);
        const int width = fontCache.width;
        const int height = fontCache.height;
        const QRect bounds(qFloor(x + gap), plot.top() + (plot.height() - height) / 2, width,
                           height);
        label.rect = bounds;
        label.bounds = bounds;
    } else {
        const QRect bounds =
            hoverValueRect(target, *lane, body, geometry, projection, x, pencilMode);
        label.rect = bounds;
        label.bounds = bounds;
    }
    label.valid = true;
    syncDirtyBounds();
    return dirtyRegion();
}

QRegion NodeLaneHoverState::updatePreviewValueLabel(const NodeLaneHoverTarget &target,
                                                    const AutomationGeometry &geometry,
                                                    const NodeLane *lane, const QRect &body,
                                                    LaneHandle handle, qreal x, int value)
{
    const QRect previousBounds = previewValueLabel.valid ? previewValueLabel.bounds : QRect{};
    previewValueLabel = {};
    if (!target.ready || !lane || !handle.valid())
        return QRegion(previousBounds);
    const int y = qRound(nodelane::valueY(*lane, body, geometry, value));
    const QRect plot = nodelane::plotRect(body, geometry);
    const auto &fontCache = valueLabelFontCache(target.font);
    const auto clamped = clampedValueLabel(x, y, plot, fontCache);
    auto &label = previewValueLabel;
    label.lane = handle;
    label.text = lane->valueText(value);
    label.font = fontCache.font;
    label.rect = clamped.bounds;
    label.bounds = clamped.bounds;
    label.valid = true;
    QRegion dirty(previousBounds);
    dirty += label.bounds;
    return dirty;
}

QRegion NodeLaneHoverState::updateHover(const NodeLaneHoverTarget &target,
                                        const AutomationGeometry &geometry, const NodeLane &lane,
                                        const QRect &body, LaneHandle handle,
                                        const AutomationProjection &projection, qreal x, int y,
                                        bool pencilMode)
{
    int mappedValue = 0;
    if (pencilMode)
        mappedValue = valueAtY(lane, body, geometry, y);
    if (handle == hover.lane && hover.pos == QPointF(x, y) &&
        (!pencilMode || mappedValue == hoverValue(lane, body, geometry)))
        return {};
    const QRect previousBounds = hoverDirtyBounds;
    hover.lane = handle;
    hover.pos = QPointF(x, y);
    hover.hasPoint = false;
    hover.originPhantom = false;
    const auto &points = cachedPoints(lane, handle, target.documentRevision);
    if (!pencilMode || projection.nodeMarkersVisible()) {
        if (const auto hit = nearestPointInRadius(
                points, projection.rawTickAt(x), hover.pos, geometry.pointHitRadius,
                [&projection, &target](const NodePoint &point) {
                    return projection.displayX(point.tick, target.devicePixelRatio);
                },
                [&lane, &body, &geometry](const NodePoint &point) {
                    return nodelane::valueY(lane, body, geometry, point.value);
                })) {
            hover.hasPoint = true;
            hover.point = points[*hit];
        } else if (const auto phantom = originPhantomAt(
                       points, handle, lane.minimumValue(), lane.maximumValue(),
                       double(geometry.plotOrigin), [&projection, &target](uint64_t tick) {
                           return projection.displayX(tick, target.devicePixelRatio);
                       })) {
            const QPointF center(qreal(geometry.plotOrigin),
                                 nodelane::valueY(lane, body, geometry, phantom->point.value));
            if (pointDistanceSquared(hover.pos, center) <=
                geometry.pointHitRadius * geometry.pointHitRadius) {
                hover.hasPoint = true;
                hover.originPhantom = true;
                hover.point = phantom->point;
            }
        }
    }
    hoverTextCache = {};
    const QRegion currentDirty =
        updateHoverValueLabel(target, geometry, &lane, body, projection, pencilMode);
    QRegion dirty(previousBounds);
    dirty += currentDirty;
    return dirty;
}

QRegion NodeLaneHoverState::setContextPointHighlight(
    const NodeLaneHoverTarget &target, const AutomationGeometry &geometry, const NodeLane &lane,
    const QRect &body, LaneHandle handle, const AutomationProjection &projection,
    const QPointF &position, const NodePoint &point, bool pencilMode)
{
    invalidateCaches();
    const QRect previousBounds = hoverDirtyBounds;
    hover.lane = handle;
    hover.pos = position;
    hover.hasPoint = true;
    hover.point = point;
    hover.originPhantom = false;
    hover.highlightLocked = true;
    const QRegion currentDirty =
        updateHoverValueLabel(target, geometry, &lane, body, projection, pencilMode);
    QRegion dirty(previousBounds);
    dirty += currentDirty;
    return dirty;
}

QRegion NodeLaneHoverState::clearHover()
{
    if (hover.highlightLocked)
        return {};
    const QRect previousBounds = hoverDirtyBounds;
    hoverDirtyBounds = {};
    invalidateCaches();
    hoverValueLabel = {};
    if (!hover.lane.valid())
        return QRegion(previousBounds);
    hover.lane = {};
    hover.hasPoint = false;
    hover.originPhantom = false;
    hover.pos = {};
    return QRegion(previousBounds);
}
