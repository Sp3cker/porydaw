#pragma once

#include <QRect>

class AutomationProjection;
class NodeLane;
class QPainter;
struct AutomationGeometry;
struct NodeLaneHoverState;

namespace nodelane {

QRect plotRect(const QRect &body, const AutomationGeometry &geometry);
qreal valueY(const NodeLane &lane, const QRect &body, const AutomationGeometry &geometry,
             int value);
qreal hoverRingRadius(const AutomationGeometry &geometry);

void paintHover(QPainter &painter, const NodeLane &lane, const QRect &body,
                const AutomationGeometry &geometry, const AutomationProjection &projection,
                const NodeLaneHoverState &hoverState, bool pencilMode);

} // namespace nodelane
