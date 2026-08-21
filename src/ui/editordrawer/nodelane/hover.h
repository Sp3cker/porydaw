#pragma once

#include <cstdint>

#include <QFont>
#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QString>

#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationCanvas;
class AutomationPage;
class AutomationProjection;
struct AutomationGeometry;

struct NodeLaneHoverState {
    struct HoverState {
        LaneHandle lane;
        QPointF pos;
        bool hasPoint = false;
        NodePoint point;
        bool highlightLocked = false;
    };
    HoverState hover;

    struct ValueLabelCache {
        LaneHandle lane;
        QString text;
        QFont font;
        QRectF rect;
        QRect bounds;
        bool valid = false;
    };

    struct PointCache {
        LaneHandle handle;
        uint64_t revision = 0;
        std::vector<NodePoint> points;
        bool valid = false;
    };
    mutable PointCache pointCache;

    struct HoverTextCache {
        struct Key {
            LaneHandle lane;
            double tick = 0.0;
            qreal x = 0.0;
            uint64_t revision = 0;
            bool pencilMode = false;
            constexpr bool operator==(const Key &) const noexcept = default;
        };
        Key key;
        QString text;
    };
    mutable HoverTextCache hoverTextCache;
    mutable QFont valueLabelFontCache;
    mutable bool valueLabelFontValid = false;
    ValueLabelCache hoverValueLabel;
    ValueLabelCache previewValueLabel;
    QRect hoverDirtyBounds;
    double hoverTick(const AutomationProjection &projection) const;
    double insertionTick(const AutomationProjection &projection, bool pencilMode) const;
    int hoverValue(const NodeLane &lane, const QRect &body,
                   const AutomationGeometry &geometry) const;

    bool hoverValueFor(const NodeLane &lane, const QRect &body, const AutomationGeometry &geometry,
                       const AutomationProjection &projection, double tick, bool pencilMode,
                       uint64_t revision, int *value) const;
    QString hoverTextFor(const AutomationPage &page, const NodeLane &lane, const QRect &body,
                         const AutomationGeometry &geometry, const AutomationProjection &projection,
                         double tick, bool pencilMode) const;
    const QString &hoverTextCached(const AutomationPage &page, const NodeLane &lane,
                                   const QRect &body, const AutomationGeometry &geometry,
                                   const AutomationProjection &projection, double tick, qreal x,
                                   bool pencilMode) const;
    QRect hoverValueRect(const AutomationCanvas &area, const AutomationPage &page,
                         const NodeLane &lane, const QRect &body,
                         const AutomationGeometry &geometry, const AutomationProjection &projection,
                         qreal x, bool pencilMode) const;
    QRect hoverPaintBounds(const AutomationCanvas &area, const AutomationPage *page,
                           const NodeLane *lane, const QRect &body,
                           const AutomationGeometry &geometry,
                           const AutomationProjection &projection, bool pencilMode) const;
    void updateHover(AutomationCanvas &area, AutomationPage &page,
                     const AutomationGeometry &geometry, const NodeLane &lane, const QRect &body,
                     LaneHandle handle, const AutomationProjection &projection, qreal x, int y,
                     bool pencilMode);
    void setContextPointHighlight(AutomationCanvas &area, const AutomationPage *page,
                                  const AutomationGeometry &geometry, const NodeLane &lane,
                                  const QRect &body, LaneHandle handle,
                                  const AutomationProjection &projection, const QPointF &position,
                                  const NodePoint &point, bool pencilMode);
    void clearHover(AutomationCanvas &area);
    void invalidateCaches();
    QFont valueLabelFont(const QFont &font) const;

    struct ClampedValueLabel {
        QRect bounds;
    };
    ClampedValueLabel clampedValueLabel(qreal x, int y, const QRect &plot, const QFont &font) const;
    void updateHoverValueLabel(const AutomationCanvas &area, const AutomationPage *page,
                               const AutomationGeometry &geometry, const NodeLane *lane,
                               const QRect &body, const AutomationProjection &projection,
                               bool pencilMode);
    void updatePreviewValueLabel(const AutomationCanvas &area, const AutomationPage *page,
                                 const AutomationGeometry &geometry, const NodeLane *lane,
                                 const QRect &body, LaneHandle handle, qreal x, int value);

  private:
    const std::vector<NodePoint> &cachedPoints(const NodeLane &lane, LaneHandle handle,
                                               uint64_t revision) const;
};
