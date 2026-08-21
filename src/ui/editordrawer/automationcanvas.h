#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QColor>
#include <QCursor>
#include <QFont>
#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QString>

#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationpaint.h"
#include "ui/editordrawer/automationpencilgesture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/editordrawer/voicechangelane.h"
#include "ui/editorviewstate.h"
#include "ui/songviewmodel.h"
#include "ui/timelinesurface.h"

class AutomationPage;
class QEvent;
class QKeyEvent;
class QPainter;
class QScrollArea;
class QWheelEvent;
class QMouseEvent;

struct LaneNodeIdentity {
    int engineTrack = -1;
    uint8_t controller = 0;
    DocLanePoint documentPoint;
};

struct LaneNodeDragState {
    NodeDragGesture gesture;
    std::vector<LaneNodeIdentity> identities;
};

// AutomationCanvas is the paint and input surface owned by AutomationPage.
// Temporary gesture state stays local to this canvas; song data and routing
// are obtained from the page's stable SongView owner.
class AutomationCanvas final : public songview::TimelineSurface
{
  public:
    explicit AutomationCanvas(AutomationPage *page, QScrollArea *scroll);
    using songview::TimelineSurface::invalidateContent;
    void invalidateContent();

    const std::vector<AutomationRow> &rows() const noexcept { return m_rowData.rows(); }
    void rebuildRows();
    void updateTempoLayout();
    void cancelInteraction();
    void setPencilMode(bool enabled);
    bool isPanning() const noexcept;
    bool bandPreviewContains(int rowIndex, uint64_t tick) const noexcept;
    bool bandPreviewContainsRow(int rowIndex) const noexcept;
    QRect labelGutter() const noexcept { return m_labelGutter; }
    int plotOrigin() const noexcept { return m_geometry.plotOrigin; }
    int contentTopInset() const noexcept
    {
        return m_tempoLane.totalHeight(m_geometry) + m_voiceLane.height();
    }

  protected:
    bool event(QEvent *event) override;
    void paintContent(QPainter &painter) override;
    void wheelEvent(QWheelEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void leaveEvent(QEvent *event) override;
    void contentGeometryChanged() override;

  private:
    friend class AutomationPage;
    friend class TempoLane;
    friend class VoiceChangeLane;

    void refreshGeometry();
    QFont captionLabelFont() const;

    // Pixel <-> tick <-> value mapping over the current geometry, rows, and
    // page timeline. Constructed fresh per event or paint pass.
    AutomationProjection projection() const;

    bool promptPointValue(const AutomationRow &row, uint8_t controller, int currentValue,
                          int *storedValue);
    bool showPointMenuNear(const AutomationRow &row, int rowIndex, const QPoint &position,
                           const QPoint &globalPosition);
    bool commitLaneEdit(int rowIndex, const NodeLaneEdit::Completion &completion);
    bool pencilPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                        DocLanePoint *point) const;
    bool pencilPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                        const AutomationProjection &proj, DocLanePoint *point) const;
    LaneNodeDragState collectSelectedNodeDrags(const AutomationProjection &projection) const;
    std::optional<LaneNodeDragState> nodeDragGestureAt(int rowIndex, const QPointF &position,
                                                       bool axisLockArmed,
                                                       const AutomationProjection &projection,
                                                       bool pencilMode) const;
    const QCursor &pencilCursor();
    void updateAxisLockCursor(AxisLock lock);
    ValuePoint mappedForRow(int row, QPointF pos, bool fine, bool snapValue,
                            const AutomationProjection &proj) const;
    void updateActiveGesture(const QPointF &position, Qt::KeyboardModifiers modifiers,
                             bool activateSweep);
    template <class T>
    static std::vector<NodeLaneEdit::Point> laneEditPoints(const std::vector<T> &points)
    {
        std::vector<NodeLaneEdit::Point> result;
        result.reserve(points.size());
        for (const auto &point : points)
            result.push_back({point.tick, point.value});
        return result;
    }
    void finishActiveGesture(bool fineMode);
    void showTimeSelectionMenu(const QPoint &globalPosition);
    void showAddLaneMenu(const QPoint &globalPosition);
    void showLaneMenu(const AutomationRow &row, const QPoint &globalPosition);
    void layoutLaneStack(int voiceTrack);
    void cancelNodeGestures();
    void rebuildNodeStack();
    LaneHandle laneAt(int y) const noexcept;
    bool resolveLane(LaneHandle handle, const NodeLane **lane, QRect *body) const noexcept;
    void syncHoverValueLabel();
    void syncPreviewValueLabel();
    void highlightHoveredPoint(LaneHandle handle, const QPointF &position, const ValuePoint &point);
    int ccRowIndexAt(int y) const noexcept;
    void setGestureActive(bool active);
    AutomationGeometry m_geometry;
    QRect m_labelGutter;
    AutomationPage *m_page = nullptr;
    QScrollArea *m_scroll = nullptr;
    CCLanes m_rowData;
    TempoLane m_tempoLane;
    VoiceChangeLane m_voiceLane;
    std::vector<CCLaneAdapter> m_ccAdapters;
    struct NodeLaneSlot {
        NodeLane *lane = nullptr;
        QRect body;
    };
    std::vector<NodeLaneSlot> m_nodeStack;
    struct ResizeState {
        int row = -1;
        int startHeight = 0;
        int startY = 0;
        int wheelRemainder = 0;
        bool active() const noexcept { return row >= 0; }
        void clear() noexcept { row = -1; }
    } m_resize;
    struct PanState {
        bool active = false;
        QPointF pos;
        double startHScroll = 0;
        int startVScroll = 0;
    } m_pan;
    BandGesture m_band;
    int m_bandRightRow = -1;
    int m_bandEndRow = -1;
    std::vector<ValuePoint> m_clipboard;
    bool m_pencilMode = false;
    qreal m_pencilCursorDpr = 0.0;
    QCursor m_pencilCursor;
    std::optional<ActiveGesture> m_activeGesture;
    std::vector<LaneNodeIdentity> m_activeNodeIdentities;
    NodeLaneHoverState m_hoverState;
    NodeDoubleClickGuard m_deletedNodeClick;
};
