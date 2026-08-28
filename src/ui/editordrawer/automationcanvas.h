#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <utility>
#include <variant>

#include <QColor>
#include <QCursor>
#include <QFont>
#include <QPointF>
#include <QRect>
#include <QRectF>
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
#include "ui/songviewmodel.h"
#include "ui/timelinesurface.h"

class AutomationPage;
class QEvent;
class QKeyEvent;
class QPainter;
class QScrollArea;
class QWheelEvent;
class QMouseEvent;

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
    bool bandPreviewContainsLane(LaneHandle handle) const noexcept;
    QRect labelGutter() const noexcept { return m_labelGutter; }
    int plotOrigin() const noexcept { return m_geometry.plotOrigin; }
    QRect laneBody(LaneHandle handle) const;
    QRect pinnedTempoRect() const noexcept;

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
    struct TickRange {
        uint64_t firstTick = 0;
        uint64_t lastTick = 0;
        [[nodiscard]] static std::optional<TickRange> orderedNonEmpty(uint64_t firstTick,
                                                                      uint64_t secondTick) noexcept;
    };
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
        // Single dispatch point for the tempo/CC kind split. The node stack
        // only ever holds these two kinds, so the visit is total.
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
    struct PaintFrame;
    struct LanePaintItem;
    using LanePointSnapshots = std::vector<std::vector<NodePoint>>;
    static void paintPlainGridFallback(QPainter &painter, const QRect &plot, AutomationPage &page,
                                       qreal plotOriginX, qreal dpr);
    static void paintEditCursor(QPainter &painter, const QRect &plot, qreal cursorX);
    static void paintSelectionReticle(QPainter &painter, const TickRange &range,
                                      const AutomationProjection &projection, const QRect &bounds,
                                      qreal devicePixelRatio);
    LanePointSnapshots snapshotLanePoints() const;
    PaintFrame preparePaintFrame(qreal devicePixelRatio,
                                 std::span<const std::vector<NodePoint>> pointsBySlot) const;
    void paintLaneStack(QPainter &painter, const PaintFrame &frame,
                        const LanePointSnapshots &pointsBySlot);
    void paintTempoSlot(QPainter &painter, const PaintFrame &frame, const LanePaintItem &item);
    void paintCcSlot(QPainter &painter, const PaintFrame &frame, const LanePaintItem &item);
    void paintLaneBody(QPainter &painter, const PaintFrame &frame, const LanePaintItem &item,
                       const QColor &color, bool preparedPreviewCurve);
    const QString &refreshCcSummaryText(CCLanes::RowTextCache &cache,
                                        std::span<const NodePoint> points, const NodeLane &lane);

    void refreshGeometry();
    void rebuildFontCache();

    // Pixel <-> tick mapping over the current geometry and page timeline.
    AutomationProjection projection() const;
    NodeLaneHoverTarget hoverTarget() const;
    bool showPointMenuNear(LaneHandle handle, const QPoint &position, const QPoint &globalPosition);

    bool commitLaneEdit(const NodeLaneEdit::Completion &completion);
    // Point-level actions treat an origin phantom as its covered source node.
    // Drag construction distinguishes concrete nodes from value-only phantoms.
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
    void clearTimeSelectionIfOutsidePress(const QMouseEvent &event,
                                          const AutomationProjection &projection, LaneHandle lane,
                                          const NodeLaneSlot *slot);
    void beginPencilPress(const QMouseEvent &event, LaneHandle handle, const NodeLane &lane,
                          const QRect &body, const AutomationProjection &projection);
    void beginDragOrSweep(const QMouseEvent &event, LaneHandle handle,
                          const AutomationProjection &projection);
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
    QRegion syncPinnedTempoLayout();
    void cancelNodeGestures();
    void rebuildNodeStack();
    LaneHandle laneAt(int y) const noexcept;
    PointerLaneHit pointerLaneAt(const QPoint &position) const noexcept;
    const NodeLaneSlot *resolveSlot(LaneHandle handle) const noexcept;
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
    AutomationPage *m_page = nullptr;
    QScrollArea *m_scroll = nullptr;
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
    std::vector<NodePoint> m_clipboard;
    bool m_pencilMode = false;
    qreal m_pencilCursorDpr = 0.0;
    QCursor m_pencilCursor;
    std::optional<ActiveGesture> m_activeGesture;
    NodeLaneHoverState m_hoverState;
    NodeDoubleClickGuard m_deletedNodeClick;
};
