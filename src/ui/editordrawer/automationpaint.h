#pragma once

#include <cstdint>
#include <optional>

#include <QColor>
#include <QPointF>
#include <QRect>

#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationprojection.h"

class AutomationCanvas;
struct NodeLaneHoverState;
class AutomationPage;
class PencilGesture;
class CCLanes;
class QFont;
class QPainter;

namespace automation::paint {

struct RowPaintParams {
    const AutomationProjection &proj;
    const AutomationRow &row;
    int rowIndex = -1;
    QRect plot;
    const std::vector<LanePoint> &points;
    QColor color;
    const ValuePoint *omitted = nullptr;
    const ValuePoint *replacement = nullptr;
    bool multipleSelectedNodes = false;
};

struct TickRange {
    uint64_t firstTick = 0;
    uint64_t lastTick = 0;

    [[nodiscard]] static std::optional<TickRange> orderedNonEmpty(uint64_t firstTick,
                                                                  uint64_t secondTick) noexcept;
};

void paintAutomationNode(QPainter &painter, const AutomationGeometry &geometry, const QColor &color,
                         const QPointF &center, bool selected = false,
                         const QColor &selectedColor = {}, bool dimUnselected = false,
                         const QColor &dimmedColor = {});

void paintPlainGridFallback(QPainter &painter, const QRect &plot, AutomationPage &page,
                            qreal plotOriginX, qreal dpr);

void paintEditCursor(QPainter &painter, const QRect &plot, qreal cursorX);
void paintSelectionReticle(QPainter &painter, const TickRange &range,
                           const AutomationProjection &projection, const QRect &bounds,
                           qreal devicePixelRatio);

void paintRow(QPainter &painter, const RowPaintParams &ctx, const QRect &bounds,
              const QFont &titleFont, const QFont &captionFont, const QRect &primaryTextBox,
              const QRect &secondaryTextBox, AutomationCanvas &area, AutomationPage &page,
              const AutomationGeometry &geometry, CCLanes &rows,
              const NodeLaneHoverState &hoverState,
              const std::optional<ActiveGesture> &activeGesture, bool pencilMode);

void paintNodeDragPreview(QPainter &painter, const RowPaintParams &ctx,
                          const NodeDragGesture &gesture, AutomationCanvas &area,
                          AutomationPage &page, const AutomationGeometry &geometry,
                          const NodeLaneHoverState &hoverState);

void paintPencilPreview(QPainter &painter, const RowPaintParams &ctx, const PencilGesture &gesture,
                        AutomationPage &page, const AutomationGeometry &geometry,
                        const NodeLaneHoverState &hoverState);

void paintCurve(QPainter &painter, const RowPaintParams &ctx, AutomationCanvas &area,
                AutomationPage &page, const AutomationGeometry &geometry, const CCLanes &rows);

void paintCurveNodes(QPainter &painter, const RowPaintParams &ctx, AutomationCanvas &area,
                     AutomationPage &page, const AutomationGeometry &geometry, const CCLanes &rows);

} // namespace automation::paint
