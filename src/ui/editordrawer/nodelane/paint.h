#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <utility>

#include <QColor>
#include <QFont>
#include <QPainter>
#include <QRect>
#include <QString>

#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationProjection;
struct AutomationGeometry;
struct NodeDragGesture;
struct NodeLaneHoverState;
struct PencilGesture;
struct SweepGesture;

namespace nodelane {

QRect plotRect(const QRect &body, const AutomationGeometry &geometry);
qreal valueY(const NodeLane &lane, const QRect &body, const AutomationGeometry &geometry,
             int value);
qreal hoverRingRadius(const AutomationGeometry &geometry);
void paintHover(QPainter &painter, const NodeLane &lane, const QRect &body,
                const AutomationGeometry &geometry, const AutomationProjection &projection,
                const NodeLaneHoverState &hoverState, bool pencilMode);

// Chrome only; callers own background fill and outer clip rects. The
// arrow/title/caption are drawn inside textClip; the separator (when enabled)
// spans band.bottom() unclipped so collapsed lanes can paint their reticle
// over it.
struct LaneHeaderPaint {
    QRect band;
    QRect primary;
    QRect secondary;
    QRect textClip;
    std::optional<QRect> arrow;
    bool expanded = true;
    bool separator = true;
    QFont titleFont;
    QFont captionFont;
    QString title;
    QString secondaryText;
};

void paintLaneHeader(QPainter &painter, const LaneHeaderPaint &paint);

struct OriginPhantomPaint {
    OriginPhantom current;
    std::optional<NodePoint> original;
};

struct NodeLanePaint {
    const NodeLane &lane;
    std::span<const NodePoint> points;
    QRect body;
    const AutomationGeometry &geometry;
    const AutomationProjection &projection;
    QColor color;
    LaneHandle handle;
    const NodeLaneHoverState &hoverState;
    const NodeDragGesture *nodeDrag = nullptr;
    const SweepGesture *sweep = nullptr;
    const PencilGesture *pencil = nullptr;
    bool pencilMode = false;
    bool multipleSelectedNodes = false;
    bool selectedLane = false;
    std::optional<std::pair<uint64_t, uint64_t>> selectedTickRange;
    bool bandLane = false;
    uint64_t bandFirstTick = 0;
    uint64_t bandLastTick = 0;
    bool preparedPreviewCurve = false;
    QColor selectedColor;
    QColor dimmedColor;
    std::optional<OriginPhantomPaint> phantom;
};

void paintNodeLane(QPainter &painter, const NodeLanePaint &paint);

} // namespace nodelane
