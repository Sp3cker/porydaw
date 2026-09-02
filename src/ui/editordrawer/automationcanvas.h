#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <utility>
#include <variant>

#include <QCursor>
#include <QFont>
#include <QObject>
#include <QPalette>
#include <QPointF>
#include <QRect>
#include <QSize>
#include <QString>

#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/laneselection.h"
#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songviewmodel.h"

class AutomationPage;

namespace songview {
class TimelineQuickScene;
class TimelineQuickView;
} // namespace songview

// AutomationCanvas owns automation interaction and content geometry. AutomationPage owns the
// viewport and scroll range; the attached TimelineInputHost provides input-surface services.
class AutomationCanvas final : public QObject, public songview::TimelineBandInteraction
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationCanvas)

  public:
    explicit AutomationCanvas(AutomationPage &page);
    ~AutomationCanvas() override = default;

    void requestFullQuickUpdate() const;
    const std::vector<AutomationRow> &rows() const noexcept { return m_rowData.rows(); }
    void rebuildRows();
    void updateTempoLayout();
    void cancelInteraction();
    void setPencilMode(bool enabled);
    bool isPanning() const noexcept;
    bool bandPreviewContainsLane(LaneHandle handle) const noexcept;
    QRect labelGutter() const noexcept { return m_labelGutter; }
    int plotOrigin() const noexcept { return m_geometry.plotOrigin; }
    QRect laneBody(LaneHandle handle) const;
    QRect pinnedTempoRect() const noexcept;
    int minimumContentHeight() const noexcept;

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerDoubleClick(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const songview::TimelineWheelInput &input) override;
    bool keyPress(const songview::TimelineKeyInput &input) override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    friend class AutomationPage;
    friend class songview::TimelineQuickView;

    void rebuildQuickScene(songview::TimelineQuickScene &scene,
                           songview::AutomationRefreshSet refresh);
    void requestQuickUpdate(songview::AutomationRefreshSet dirty) const;
    void syncTimelineQuickHover() const;
    void requestViewportQuickUpdate() const;
    void requestSelectionQuickUpdate() const;
    void requestHoverQuickUpdate() const;
    void requestGestureBeginQuickUpdate(bool band) const;
    void requestGestureMoveQuickUpdate() const;
    void requestGestureEndQuickUpdate() const;
    void invalidateSelectedNodeMultiplicity() const noexcept;
    bool hasMultipleSelectedNodes(
        const std::optional<std::pair<uint64_t, uint64_t>> &selectedTickRange) const;
    struct PointerLaneHit {
        LaneHandle lane;
        bool tempoHeader = false;
    };
    struct NodeLaneSlot {
        EditorAutomationRowId id;
        NodeLane *lane = nullptr;
        QRect body;
        CCLanes::RowTextCache *text = nullptr;

        [[nodiscard]] bool isTempo() const noexcept
        {
            return id.kind == EditorAutomationRowKind::Tempo;
        }
        template <class TempoFn, class CcFn>
        decltype(auto) visit(TempoFn &&tempoFn, CcFn &&ccFn) const
        {
            if (isTempo())
                return std::forward<TempoFn>(tempoFn)();
            return std::forward<CcFn>(ccFn)();
        }
    };
    struct NodeLaneChange {
        const NodeLaneSlot *slot = nullptr;
        std::vector<NodePointMove> moves;
        std::vector<uint64_t> deleteTicks;
    };
    void viewportResized();
    void scrollStateChanged();
    void relayoutContent();
    void contentGeometryChanged();
    QPointF contentPosition(QPointF viewportPosition) const noexcept;
    QPointF viewportPosition(QPointF contentPosition) const noexcept;
    QPointF contentPositionFromGlobal(QPointF globalPosition) const;
    QRect viewportRect(QRect contentRect) const noexcept;
    QRect contentBounds() const noexcept;
    void refreshGeometry();
    void rebuildFontCache();
    const QString &refreshCcSummaryText(CCLanes::RowTextCache &cache,
                                        std::span<const NodePoint> points, const NodeLane &lane);

    AutomationProjection projection() const;
    NodeLaneHoverTarget hoverTarget() const;
    bool showPointMenuNear(LaneHandle handle, const QPoint &position, const QPoint &globalPosition);

    bool commitLaneEdit(const NodeLaneEdit::Completion &completion);
    bool nodePointHit(LaneHandle handle, const QPointF &position, NodePoint *point) const;
    bool nodePointHit(LaneHandle handle, const QPointF &position, const AutomationProjection &proj,
                      NodePoint *point) const;
    std::optional<OriginPhantom> originPhantomAt(LaneHandle handle, const QPointF &position,
                                                 const AutomationProjection &projection) const;
    std::optional<OriginPhantom> originPhantom(LaneHandle handle,
                                               const AutomationProjection &projection,
                                               std::span<const NodePoint> points) const;
    std::optional<PhantomGesture> phantomDragGestureAt(LaneHandle handle,
                                                       const QPointF &position) const;
    NodeDragGesture collectSelectedNodeDrags() const;
    std::optional<NodeDragGesture> nodeDragGestureAt(LaneHandle handle, const QPointF &position,
                                                     bool axisLockArmed,
                                                     const AutomationProjection &projection,
                                                     bool pencilMode) const;
    const QCursor &pencilCursor();
    bool isEditablePencilHit(const QPointF &position) const noexcept;
    void updatePencilCursor();
    void updateAxisLockCursor(AxisLock lock);
    void clearTimeSelectionIfOutsidePress(QPointF contentPosition,
                                          const AutomationProjection &projection, LaneHandle lane,
                                          const NodeLaneSlot *slot);
    bool beginPencilPress(QPointF contentPosition, Qt::KeyboardModifiers modifiers,
                          LaneHandle handle, const NodeLane &lane, const QRect &body,
                          const AutomationProjection &projection);
    bool beginDragOrSweep(QPointF contentPosition, Qt::KeyboardModifiers modifiers,
                          LaneHandle handle, const AutomationProjection &projection);
    NodePoint mappedForLane(LaneHandle handle, QPointF pos, bool fine, bool snapValue,
                            const AutomationProjection &proj) const;
    void updateActiveGesture(const QPointF &position, Qt::KeyboardModifiers modifiers,
                             bool activateSweep);
    void finishActiveGesture(bool fineMode);
    bool commitNodePointMoves(uint64_t expectedRevision, const std::vector<NodeDrag> &points);
    bool commitNodePointDeletes(std::optional<uint64_t> expectedRevision,
                                const std::vector<NodeDrag> &points);
    bool commitResolvedNodeLaneChanges(std::optional<uint64_t> expectedRevision,
                                       const std::vector<NodeLaneChange> &changes,
                                       const QString &undoLabel);
    void showTimeSelectionMenuFor(LaneHandle contextLane, const QPoint &globalPosition);
    void showLaneMenuFor(LaneHandle handle, const QPoint &globalPosition);
    void showAddLaneMenu(const QPoint &globalPosition);
    void layoutLaneStack();
    int tempoTop() const;
    void syncPinnedTempoLayout();
    void cancelNodeGestures();
    void rebuildNodeStack();
    LaneHandle laneAt(int y) const noexcept;
    PointerLaneHit pointerLaneAt(const QPoint &position) const noexcept;
    const NodeLaneSlot *resolveSlot(LaneHandle handle) const noexcept;
    void refreshHoverAt(const QPointF &position);
    bool resolveLane(LaneHandle handle, const NodeLane **lane, QRect *body) const noexcept;
    NodeLane *mutableLane(LaneHandle handle) noexcept;
    void syncHoverValueLabel();
    void syncPreviewValueLabel();
    void highlightHoveredPoint(LaneHandle handle, const QPointF &position, const NodePoint &point);
    int ccRowIndexAt(int y) const noexcept;
    int ccLaneHeight(const AutomationRow &row) const;
    int ccRowBoundaryAt(int y) const;
    int addLaneStripTop() const;
    void publishBandSelection(uint64_t first, uint64_t last, LaneHandle start,
                              LaneHandle end) const;
    void setGestureActive(bool active);

    AutomationGeometry m_geometry;
    QFont m_laneTitleFont;
    QFont m_laneCaptionFont;
    std::optional<layout::TwoLineTextLayout> m_laneTextLayout;
    QRect m_labelGutter;
    AutomationPage &m_page;
    songview::TimelineInputHost *m_inputHost = nullptr;
    QFont m_hostFont;
    QPalette m_hostPalette;
    qreal m_hostDpr = 0.0;
    CCLanes m_rowData;
    TempoLane m_tempoLane;
    std::vector<CCLaneAdapter> m_ccAdapters;
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
    LaneSelection m_laneSelection;
    struct SelectedNodeMultiplicityCache {
        uint64_t documentRevision = 0;
        bool valid = false;
        bool multiple = false;
    };
    mutable SelectedNodeMultiplicityCache m_selectedNodeMultiplicity;
    std::vector<NodePoint> m_clipboard;
    bool m_pencilMode = false;
    qreal m_pencilCursorDpr = 0.0;
    QCursor m_pencilCursor;
    std::optional<ActiveGesture> m_activeGesture;
    NodeLaneHoverState m_hoverState;
    NodeDoubleClickGuard m_deletedNodeClick;
};
