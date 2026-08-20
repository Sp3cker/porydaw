#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationprojection.h"
class AutomationArea;
class AutomationPage;
class QFont;
class QMouseEvent;
class QPainter;

// Song-wide Tempo lives above the track-owned automation rows. It shares their
// canvas but deliberately has no controller or track identity.
class TempoLane final
{
  public:
    explicit TempoLane(AutomationPage *page) noexcept;

    void updateLayout(int width, const AutomationGeometry &geometry);
    int totalHeight(const AutomationGeometry &geometry) const;
    bool interactionActive() const noexcept;
    bool hasTimeSelection() const;
    bool selectionContains(const AutomationProjection &projection, qreal x,
                           qreal devicePixelRatio) const;
    void cancel();
    void clearHover();

    bool mousePress(AutomationArea &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseMove(AutomationArea &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseRelease(AutomationArea &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseDoubleClick(AutomationArea &area, QMouseEvent *event,
                          const AutomationGeometry &geometry);

    void paint(QPainter &painter, const AutomationGeometry &geometry, const QRect &labelGutter,
               const QFont &titleFont, const QFont &captionFont);

  private:
    struct DragState {
        TempoPoint original;
        TempoPoint current;
        QPointF pressPosition;
        Slop dragSlop;
        AxisLock axisLock = AxisLock::None;
    };
    struct DrawState {
        TempoPoint previous;
        std::vector<TempoPoint> points;
        bool moved = false;
    };

    int headerHeight(const AutomationGeometry &geometry) const;
    int bodyHeight(const AutomationGeometry &geometry) const;
    bool contains(const QPoint &position) const;
    bool containsBody(const QPointF &position) const;
    std::optional<std::size_t> hitPoint(const QPointF &position,
                                        const AutomationProjection &projection,
                                        const AutomationGeometry &geometry,
                                        qreal devicePixelRatio) const;
    bool promptBpm(AutomationArea &area, int currentBpm, int *bpm) const;
    void appendDrawPoint(DrawState &draw, TempoPoint point);
    void appendDrawSegment(DrawState &draw, TempoPoint next, bool fine);
    void applyEdit(const TempoEdit &edit) const;
    void showTempoMenu(AutomationArea &area, const QPoint &globalPosition);
    void showPointMenu(AutomationArea &area, std::size_t pointIndex, const QPoint &globalPosition);
    void showTimeSelectionMenu(const QPoint &globalPosition) const;
    void publishTimeSelection(uint64_t first, uint64_t last) const;
    QString bpmText(uint32_t microsecondsPerQuarterNote) const;

    AutomationPage *m_page = nullptr;
    QRect m_header;
    QRect m_body;
    bool m_expanded = false;
    std::optional<std::size_t> m_hoveredPoint;
    std::optional<DragState> m_drag;
    std::optional<DrawState> m_draw;
    BandGesture m_band;
    std::vector<TempoPoint> m_clipboard;
};
