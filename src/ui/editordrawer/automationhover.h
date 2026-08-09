#pragma once

#include <cstdint>
#include <optional>

#include <QFont>
#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QString>

#include "ui/editordrawer/automationgesture.h"

class AutomationArea;
class AutomationPage;
class AutomationProjection;
class AutomationRows;
struct AutomationGeometry;
struct AutomationRow;

struct AutomationHoverState {
    struct HoverState {
        int row = -1;
        QPointF pos;
        bool hasPoint = false;
        ValuePoint point;
        bool highlightLocked = false;
        bool nodeDeleted = false;
    };
    HoverState hover;

    struct ValueLabelCache {
        int row = -1;
        QString text;
        QFont font;
        QRectF rect;
        QRect bounds;
        bool valid = false;
    };

    mutable QString hoverText;
    mutable int hoverTextRow = -1;
    mutable double hoverTextTick = 0.0;
    mutable qreal hoverTextX = 0.0;
    mutable uint64_t hoverTextRevision = 0;
    mutable bool hoverTextPencilMode = false;
    mutable QFont valueLabelFontCache;
    mutable bool valueLabelFontValid = false;
    ValueLabelCache hoverValueLabel;
    ValueLabelCache previewValueLabel;
    QRect hoverDirtyBounds;
    double hoverTick(const AutomationProjection &projection) const;
    double insertionTick(const AutomationProjection &projection, const AutomationRow &row,
                         bool pencilMode) const;
    int hoverValue(const AutomationProjection &projection) const;

    bool hoverValueFor(const AutomationRows &rows, const AutomationProjection &projection,
                       const AutomationRow &row, int rowIndex, double tick, bool pencilMode,
                       int *value) const;
    QString hoverTextFor(const AutomationArea &area, const AutomationPage &page,
                         const AutomationGeometry &geometry, const AutomationRows &rows,
                         const AutomationProjection &projection, const AutomationRow &row,
                         int rowIndex, double tick, qreal x, bool pencilMode) const;
    const QString &hoverTextCached(const AutomationArea &area, const AutomationPage &page,
                                   const AutomationGeometry &geometry, const AutomationRows &rows,
                                   const AutomationProjection &projection, int rowIndex,
                                   double tick, qreal x, bool pencilMode) const;
    QRect hoverValueRect(const AutomationArea &area, const AutomationPage &page,
                         const AutomationGeometry &geometry, const AutomationRows &rows,
                         const AutomationProjection &projection, const AutomationRow &row,
                         int rowIndex, qreal x, bool pencilMode) const;
    QRect hoverPaintBounds(const AutomationArea &area, const AutomationPage *page,
                           const AutomationGeometry &geometry, const AutomationRows &rows,
                           const AutomationProjection &projection, int rowIndex,
                           bool pencilMode) const;
    void updateHover(AutomationArea &area, AutomationPage &page, const AutomationGeometry &geometry,
                     const AutomationRows &rows, const AutomationProjection &projection, qreal x,
                     int y, bool pencilMode);
    void setContextPointHighlight(AutomationArea &area, const AutomationPage *page,
                                  const AutomationGeometry &geometry, const AutomationRows &rows,
                                  const AutomationProjection &projection, int rowIndex,
                                  const QPointF &position, const DocLanePoint &point,
                                  bool pencilMode);
    void clearHover(AutomationArea &area);
    QFont valueLabelFont(const QFont &font) const;

    struct ClampedValueLabel {
        QRect bounds;
    };
    ClampedValueLabel clampedValueLabel(qreal x, int y, const QRect &plot, const QFont &font) const;
    void updateHoverValueLabel(const AutomationArea &area, const AutomationPage *page,
                               const AutomationGeometry &geometry, const AutomationRows &rows,
                               const AutomationProjection &projection, bool pencilMode);
    void updatePreviewValueLabel(const AutomationArea &area, const AutomationPage *page,
                                 const AutomationGeometry &geometry, const AutomationRows &rows,
                                 const AutomationProjection &projection,
                                 const std::optional<ActiveGesture> &activeGesture);
};
