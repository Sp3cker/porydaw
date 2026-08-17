#pragma once

#include <cstdint>
#include <optional>
#include <vector>

#include <QColor>
#include <QPointF>
#include <QRect>

#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationprojection.h"

class AutomationArea;
struct AutomationHoverState;
class AutomationPage;
class PencilGesture;
class AutomationRows;
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
    uint32_t usedTrackMask = 0;
    const ValuePoint *omitted = nullptr;
    const ValuePoint *replacement = nullptr;
    bool multipleSelectedNodes = false;
};

void paintAutomationNode(QPainter &painter, const AutomationGeometry &geometry, const QColor &color,
                         const QPointF &center, bool selected = false,
                         const QColor &selectedColor = {}, bool dimUnselected = false,
                         const QColor &dimmedColor = {});

void paintRow(QPainter &painter, const RowPaintParams &ctx, const QRect &bounds,
              const QFont &titleFont, const QFont &captionFont, const QRect &primaryTextBox,
              const QRect &secondaryTextBox, AutomationArea &area, AutomationPage &page,
              const AutomationGeometry &geometry, AutomationRows &rows,
              const AutomationHoverState &hoverState,
              const std::optional<ActiveGesture> &activeGesture, bool pencilMode);

void paintHover(QPainter &painter, const RowPaintParams &ctx, AutomationPage &page,
                const AutomationGeometry &geometry, const AutomationRows &rows,
                const AutomationHoverState &hoverState, bool pencilMode);

void paintNodeDragPreview(QPainter &painter, const RowPaintParams &ctx,
                          const NodeDragGesture &gesture, AutomationArea &area,
                          AutomationPage &page, const AutomationGeometry &geometry,
                          const AutomationHoverState &hoverState);

void paintPencilPreview(QPainter &painter, const RowPaintParams &ctx, const PencilGesture &gesture,
                        AutomationPage &page, const AutomationGeometry &geometry,
                        const AutomationHoverState &hoverState);

void paintCurve(QPainter &painter, const RowPaintParams &ctx, AutomationArea &area,
                AutomationPage &page, const AutomationGeometry &geometry,
                const AutomationRows &rows);

void paintCurveNodes(QPainter &painter, const RowPaintParams &ctx, AutomationArea &area,
                     AutomationPage &page, const AutomationGeometry &geometry,
                     const AutomationRows &rows);

void paintVoiceRow(QPainter &painter, const QRect &plot, AutomationPage &page,
                   const AutomationGeometry &geometry, AutomationRows &rows);

} // namespace automation::paint
