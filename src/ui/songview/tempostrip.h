#pragma once

#include <cstdint>
#include <optional>
#include <vector>

#include <QPointF>
#include <QRect>

#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/timelinesurface.h"

class QContextMenuEvent;
class QEvent;
class QKeyEvent;
class QMouseEvent;
class QPainter;
class SongView;

namespace songview {

// Song-wide tempo automation is a fixed-height, timeline-aligned surface. It
// deliberately reads SongView live state directly: mounting and refresh
// orchestration belong to SongView's Wave 3 cutover.
class TempoStrip final : public TimelineSurface
{
  public:
    explicit TempoStrip(SongView &view);
    ~TempoStrip() override;

    int plotOrigin() const noexcept;
    void cancelInteraction();
    bool gestureActive() const noexcept;

  protected:
    bool event(QEvent *event) override;
    void paintContent(QPainter &painter) override;
    void contentGeometryChanged() override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void leaveEvent(QEvent *event) override;
    void contextMenuEvent(QContextMenuEvent *event) override;

  private:
    class TempoLane final : public NodeLane
    {
      public:
        explicit TempoLane(TempoStrip &strip) noexcept;

        QString title() const override;
        std::vector<NodePoint> points() const override;
        int minimumValue() const override;
        int maximumValue() const override;
        QString valueText(int value) const override;
        bool pointSelected(uint64_t tick) const override;
        void deletePoints(const std::vector<uint64_t> &ticks) override;
        void movePoints(const std::vector<NodePointMove> &moves) override;
        void replaceSpan(uint64_t first, uint64_t last,
                         const std::vector<NodePoint> &points) override;

      private:
        TempoStrip &m_strip;
    };

    AutomationProjection projection() const;
    NodeLaneHoverTarget hoverTarget() const;
    bool ready() const noexcept;
    uint32_t usedTrackMask() const noexcept;
    NodePoint mappedPoint(QPointF position, Qt::KeyboardModifiers modifiers) const;
    bool nodePointHit(QPointF position, NodePoint *point) const;
    void beginNodeDrag(const NodePoint &hit, QPointF position, Qt::KeyboardModifiers modifiers);
    void updateNodeDrag(QPointF position, Qt::KeyboardModifiers modifiers);
    void finishNodeDrag();
    void updateHover(QPointF position);
    void publishBandSelection(uint64_t first, uint64_t last);
    void applyTempoEdit(const TempoEdit &edit);
    bool promptBpm(int currentBpm, int *bpm) const;
    void showTempoMenu(const QPoint &globalPosition);
    void updateAxisLockCursor(AxisLock lock);

    SongView &m_view;
    AutomationGeometry m_geometry;
    QRect m_body;
    TempoLane m_lane;
    std::vector<TempoPoint> m_clipboard;
    std::optional<NodeDragGesture> m_drag;
    BandGesture m_band;
    NodeLaneHoverState m_hover;
    NodeDoubleClickGuard m_deletedNodeClick;
};

} // namespace songview
