#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <variant>
#include <vector>

#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/nodelane.h"

namespace songview {
class EditorSelectionModel;
}

class AutomationCanvas;
class AutomationPage;
class QFont;
class QMouseEvent;
class QPainter;

// Song-wide Tempo lives above Voice Change and the CC lanes. It shares their
// canvas but deliberately has no controller or track identity.
class TempoLane final : public NodeLane
{
  public:
    explicit TempoLane(AutomationPage *page) noexcept;
    TempoLane(SongDocument &document, const songview::EditorSelectionModel &selection,
              uint32_t usedTrackMask) noexcept;

    QString title() const override;
    std::vector<NodePoint> points() const override;
    int minimumValue() const override;
    int maximumValue() const override;
    QString valueText(int value) const override;
    bool pointSelected(uint64_t tick) const override;
    void deletePoints(const std::vector<uint64_t> &ticks) override;
    void movePoints(const std::vector<NodePointMove> &moves) override;
    void replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points) override;
    void updateLayout(int width, const AutomationGeometry &geometry);
    int totalHeight(const AutomationGeometry &geometry) const;
    QRect bodyRect() const noexcept { return m_body; }
    bool interactionActive() const noexcept;
    bool hasTimeSelection() const;
    bool selectionContains(const AutomationProjection &projection, qreal x,
                           qreal devicePixelRatio) const;
    void cancel();
    void clearHover();
    bool deleteTimeSelection();

    bool mousePress(AutomationCanvas &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseMove(AutomationCanvas &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseRelease(AutomationCanvas &area, QMouseEvent *event,
                      const AutomationGeometry &geometry);
    bool mouseDoubleClick(AutomationCanvas &area, QMouseEvent *event,
                          const AutomationGeometry &geometry);

    void paint(QPainter &painter, const AutomationGeometry &geometry, const QRect &labelGutter,
               const QFont &titleFont, const QFont &captionFont);

  private:
    using ActiveGesture = std::variant<NodeDragGesture, SweepGesture>;
    struct NodeDragState {
        NodeDragGesture gesture;
        std::vector<TempoPoint> identities;
    };

    int collapsedHeight(const AutomationGeometry &geometry) const;
    int bodyHeight(const AutomationGeometry &geometry) const;
    bool contains(const QPoint &position) const;
    bool containsBody(const QPointF &position) const;
    std::optional<std::size_t> hitPoint(const QPointF &position,
                                        const AutomationProjection &projection,
                                        const AutomationGeometry &geometry,
                                        qreal devicePixelRatio) const;
    int bpmAt(qreal y, const AutomationGeometry &geometry) const;
    ValuePoint mappedPoint(const QPointF &position, const AutomationProjection &projection,
                           const AutomationGeometry &geometry, bool fine) const;
    std::optional<NodeDragState> nodeDragGestureAt(const QPointF &position, bool axisLockArmed,
                                                   const AutomationProjection &projection,
                                                   const AutomationGeometry &geometry,
                                                   qreal devicePixelRatio) const;
    void updateActiveGesture(AutomationCanvas &area, const QPointF &position,
                             Qt::KeyboardModifiers modifiers, const AutomationGeometry &geometry,
                             bool activateSweep);
    void finishActiveGesture(bool fine, const AutomationGeometry &geometry);
    bool pointInTimeSelection(uint64_t tick) const;
    bool promptBpm(AutomationCanvas &area, int currentBpm, int *bpm) const;
    void applyEdit(const TempoEdit &edit) const;
    void showTempoMenu(AutomationCanvas &area, const QPoint &globalPosition);
    void showPointMenu(AutomationCanvas &area, std::size_t pointIndex,
                       const QPoint &globalPosition);
    void showTimeSelectionMenu(const QPoint &globalPosition) const;
    void publishTimeSelection(uint64_t first, uint64_t last) const;
    QString bpmText(uint32_t microsecondsPerQuarterNote) const;
    SongDocument *boundDocument() const noexcept;
    const songview::EditorSelectionModel *boundSelection() const noexcept;
    uint32_t boundUsedTrackMask() const noexcept;

    AutomationPage *m_page = nullptr;
    SongDocument *m_document = nullptr;
    const songview::EditorSelectionModel *m_selection = nullptr;
    uint32_t m_usedTrackMask = 0;
    QRect m_header;
    QRect m_body;
    std::vector<TempoPoint> m_activeNodeIdentities;
    bool m_expanded = false;
    std::optional<std::size_t> m_hoveredPoint;
    std::optional<ActiveGesture> m_activeGesture;
    BandGesture m_band;
    std::vector<TempoPoint> m_clipboard;
    NodeDoubleClickGuard m_deletedNodeClick;
};
