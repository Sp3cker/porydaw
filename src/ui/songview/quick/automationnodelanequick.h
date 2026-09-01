#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <utility>
#include <vector>

#include <QColor>
#include <QRect>
#include <QRectF>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace songview {

class NodeLaneQuickPaint final
{
  public:
    struct Context {
        TimelineQuickScene &scene;
        const NodeLane &lane;
        std::span<const NodePoint> points;
        QRect body;
        QRectF plot;
        qreal contentYOffset = 0.0;
        QRectF overflow;
        const AutomationGeometry &geometry;
        const AutomationProjection &projection;
        const NodeLaneHoverState &hoverState;
        LaneHandle handle;
        QColor color;
        QColor selectedColor;
        QColor dimmedColor;
        qreal devicePixelRatio = 1.0;
        std::optional<std::pair<uint64_t, uint64_t>> selectedTickRange;
        bool selectedLane = false;
        bool selectedNodesLane = false;
        bool bandLane = false;
        uint64_t bandFirstTick = 0;
        uint64_t bandLastTick = 0;
        bool multipleSelectedNodes = false;
        bool pencilMode = false;
        const NodeDragGesture *nodeDrag = nullptr;
        const PhantomGesture *phantomGesture = nullptr;
        const SweepGesture *sweep = nullptr;
        const PencilGesture *pencil = nullptr;
        std::optional<OriginPhantom> phantom;
    };

    struct Outputs {
        std::vector<TimelineQuickTextModel::Record> *hoverText = nullptr;
        std::vector<TimelineQuickTextModel::Record> *transientText = nullptr;
    };

    static void composeStatic(const Context &context, bool curves, bool nodes, bool selection);
    static void composeTransient(const Context &context, bool transient, bool bandSelection,
                                 const Outputs &outputs);
    static void composeHover(const Context &context, bool hover, const Outputs &outputs);
};

} // namespace songview
