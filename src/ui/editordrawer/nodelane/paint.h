#pragma once

#include <cstdint>
#include <optional>

#include <QColor>
#include <QRect>

#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationProjection;
class QPainter;
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

struct NodeLanePaint {
    const NodeLane &lane;
    QRect body;
    const AutomationGeometry &geometry;
    const AutomationProjection &projection;
    QColor color;
    std::optional<NodePoint> leadIn;
    LaneHandle handle;
    const NodeLaneHoverState &hoverState;
    const NodeDragGesture *nodeDrag = nullptr;
    const SweepGesture *sweep = nullptr;
    const PencilGesture *pencil = nullptr;
    int gestureRow = -1;
    bool pencilMode = false;
    bool multipleSelectedNodes = false;
    bool selectedLane = false;
    bool bandLane = false;
    uint64_t bandFirstTick = 0;
    uint64_t bandLastTick = 0;
    bool preparedPreviewCurve = false;
    QColor selectedColor;
    QColor dimmedColor;
};

void paintNodeLane(QPainter &painter, const NodeLanePaint &paint);

} // namespace nodelane
