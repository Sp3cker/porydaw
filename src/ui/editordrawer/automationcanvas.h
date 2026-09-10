#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <utility>
#include <variant>

#include <QCursor>
#include <QFont>
#include <QList>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QSize>
#include <QString>
#include <QStringList>
#include <QVariant>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/laneselection.h"
#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songviewmodel.h"

class AutomationPage;
class SongDocument;

namespace songview {
class QuickMenuHost;
class QuickMenuModel;
class QuickPopupSession;
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
    // Stable typed selectors for the shared Quick canvas menus. Ordinary
    // commands carry fixed ids; the lane menu's dynamic rows offset their
    // controller by AddLaneBase (add a new lane) or ShowLaneBase (reveal a
    // hidden lane). The value-range submenu's rows are the Range* ids proper
    // (Auto, 16, 32, 64, 127). Checks and production dispatch both read
    // these.
    enum class CanvasMenuAction : int {
        Copy = 1,
        Paste = 2,
        Clear = 3,
        RemoveLane = 4,
        HideLane = 5,
        ClearTimeSelection = 6,
        ValueRange = 7,
        RangeAuto = 8,
        Range16 = 9,
        Range32 = 10,
        Range64 = 11,
        Range127 = 12,
        AddLaneBase = 256,
        ShowLaneBase = 512,
    };
    // Typed row ids of the node point context menu. The node menu carries
    // its own QuickMenuModel over the shared popup session, so this id space
    // is disjoint from CanvasMenuAction's. Production dispatch and the checks
    // that click rendered rows both read these.
    enum class NodeMenuAction : int {
        SetValue = 1,
        DeleteNode = 2,
    };

    explicit AutomationCanvas(AutomationPage &page);
    ~AutomationCanvas() override = default;

    void requestFullQuickUpdate() const;
    const std::vector<AutomationRow> &rows() const noexcept { return m_rowData.rows(); }
    void rebuildRows();
    void updateTempoLayout();
    void cancelInteraction() override;
    // Shared inline value prompt behind the Set Value menu action and the
    // empty-plot double-click. Opening snapshots the document revision and
    // never writes; acceptance revalidates lane identity and revision before
    // taking the normal commit path, so a stale prompt edits nothing.
    struct PendingValuePrompt {
        LaneHandle lane;
        NodePoint anchor; // existing node (Set Value) or insertion tick/value
        uint64_t expectedRevision = 0;
        NodeValuePrompt prompt;
        bool forExistingNode = false;
    };

    bool openValuePromptForNode(LaneHandle handle, const NodePoint &point);
    // displayedValue is prompt-domain; tick and storedValue are lane-domain.
    bool openValuePromptForInsertion(LaneHandle handle, uint64_t tick, int storedValue);
    void acceptNodeValuePrompt(int displayedValue);
    void cancelNodeValuePrompt();
    bool valuePromptVisible() const noexcept { return m_pendingValuePrompt.has_value(); }
    NodeValuePrompt pendingValuePrompt() const
    {
        return m_pendingValuePrompt ? m_pendingValuePrompt->prompt : NodeValuePrompt{};
    }

    // QML bridge for CcDeleteConfirm.qml, the shared-session confirmation
    // behind the lane menu's Delete CC lane action on a lane that still
    // carries events. The prompt lives on this canvas — never a DrawerChrome
    // pass-through — and its guarded target is the snapshot below: document
    // identity plus revision reject any document change since the open, and
    // the lane handle plus exact row id reject a rebuild remap. No lane
    // pointer crosses the prompt; the displayed title and event count are
    // captured with it, because acceptance runs after the menu's close and
    // the getters run during QML component creation.
    struct PendingCcDeletePrompt {
        QPointer<SongDocument> document;
        uint64_t documentRevision = 0;
        LaneHandle lane;
        EditorAutomationRowId rowId = {};
        QString laneTitle;
        std::size_t eventCount = 0;
    };

    Q_PROPERTY(
        QString ccDeletePromptTitle READ ccDeletePromptTitle NOTIFY ccDeletePromptChanged FINAL)
    Q_PROPERTY(
        QString ccDeletePromptMessage READ ccDeletePromptMessage NOTIFY ccDeletePromptChanged FINAL)
    Q_PROPERTY(QVariantMap ccDeletePromptAppearance READ ccDeletePromptAppearance NOTIFY
                   ccDeletePromptChanged FINAL)
    Q_INVOKABLE void acceptCcDeletePrompt();
    Q_INVOKABLE void cancelCcDeletePrompt();
    QString ccDeletePromptTitle() const;
    QString ccDeletePromptMessage() const;
    QVariantMap ccDeletePromptAppearance() const;

    void setPencilMode(bool enabled);
    bool pencilMode() const noexcept { return m_pencilMode; }
    bool isPanning() const noexcept;
    bool bandPreviewContainsLane(LaneHandle handle) const noexcept;
    QRect laneBody(LaneHandle handle) const;
    QRect pinnedTempoRect() const noexcept;
    int minimumContentHeight() const noexcept;
    // The view-local parameter selector for the shared gutter: nine clickable
    // identities — the eight supported CCs plus song-global Tempo, all
    // available without written events. `index` is a catalog position
    // (parameterRow), never a LaneHandle; a null m_activeController selects
    // Tempo. The active parameter is view-local (default Volume), retained by
    // the owning SongTab, never persisted; switching it is a view-only change.
    Q_PROPERTY(
        QStringList parameterLabels READ parameterLabels NOTIFY parameterPresentationChanged FINAL)
    Q_PROPERTY(int activeParameter READ activeParameter NOTIFY activeParameterChanged FINAL)
    Q_PROPERTY(QList<int> selectedParameters READ selectedParameters NOTIFY
                   parameterSelectionChanged FINAL)
    Q_PROPERTY(QVariantMap parameterAppearance READ parameterAppearance NOTIFY
                   parameterPresentationChanged FINAL)
    Q_PROPERTY(
        bool parametersEnabled READ parametersEnabled NOTIFY parameterPresentationChanged FINAL)
    QStringList parameterLabels() const;
    int activeParameter() const noexcept;
    QList<int> selectedParameters() const;
    QVariantMap parameterAppearance() const;
    bool parametersEnabled() const noexcept;
    // Qt Binding target for the selector grid's QML-measured implicitHeight
    // (published rounded up from QML); the only cross-boundary size value.
    // READ reuses the existing minimumContentHeight() declaration above.
    Q_PROPERTY(int minimumContentHeight READ minimumContentHeight WRITE setMinimumContentHeight
                   NOTIFY minimumContentHeightChanged FINAL)
    void setMinimumContentHeight(int height);
    std::optional<EditorAutomationRowId> parameterRow(int index) const;
    int parameterIndex(const EditorAutomationRowId &row) const noexcept;
    Q_INVOKABLE void activateParameter(int index);
    Q_INVOKABLE void openParameterMenu(int index, qreal sceneX, qreal sceneY);
    // Binds the shared canvas popup session once TimelineQuickView exists;
    // the automation menus are typed QuickMenuHost adapters over it.
    void setPopupSession(songview::QuickPopupSession *session);

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerDoubleClick(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const songview::TimelineWheelInput &input) override;
    bool keyPress(const songview::TimelineKeyInput &input) override;
    bool gestureActive() const override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  signals:
    void valuePromptChanged();
    void ccDeletePromptChanged();
    void activeParameterChanged();
    void parameterSelectionChanged();
    void parameterPresentationChanged();
    void minimumContentHeightChanged();

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
    // The guarded open-time target for one automation canvas menu. Document
    // identity plus revision reject any document change since the open; the
    // lane menu additionally re-resolves the handle and requires the same
    // row id, so a rebuild landing after the open cannot retarget a
    // different lane. No lane pointer and no point vector crosses the popup:
    // commands re-read live state at dispatch. `track` carries the captured
    // add-menu track, `laneTitle` the presentation string for post-rebuild
    // announcements.
    struct PendingMenu {
        QPointer<SongDocument> document;
        uint64_t documentRevision = 0;
        LaneHandle lane;
        EditorAutomationRowId rowId = {};
        int track = -1;
        QString laneTitle;
    };
    // The guarded open-time target for the node point menu. Document identity
    // plus revision reject any document change since the open; the lane
    // handle plus exact row id reject a rebuild remap, and the full NodePoint
    // (tick and value) is the occurrence identity — lanes can carry several
    // points at one tick, so dispatch re-finds this exact point before any
    // mutation. No lane pointer crosses the popup.
    struct PendingNodeMenu {
        QPointer<SongDocument> document;
        uint64_t documentRevision = 0;
        LaneHandle lane;
        EditorAutomationRowId rowId = {};
        NodePoint point = {};
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

    AutomationProjection projection() const;
    NodeLaneHoverTarget hoverTarget() const;
    // True consumes the node hit even when the open aborts (teardown,
    // refused publish, a newer popup on the session, stale snapshot); false
    // is only a genuine miss, which keeps the caller's fallback available.
    bool showNodeMenuNear(LaneHandle handle, const QPointF &position,
                          const QPointF &globalPosition);

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
    void showTimeSelectionMenuFor(LaneHandle contextLane, const QPointF &scenePosition);
    void showLaneMenuFor(LaneHandle handle, const QPointF &scenePosition);
    // Handle for the currently resolved active-parameter row, searched in
    // m_nodeStack per call: rebuilds remap handles, so no index is cached.
    LaneHandle activeLane() const noexcept;
    void showAddLaneMenu(const QPointF &scenePosition);
    QPointF menuScenePosition(const QPointF &globalPosition) const;
    // Consumes the guarded open-time target; clears it before any command.
    void handleMenuAction(int actionId);
    // Ends only a session this canvas still owns, without stealing focus.
    void cancelLaneMenuWithoutFocus();
    // Consumes the guarded node-menu target; clears it before any command.
    void handleNodeMenuAction(int actionId);
    // Outside-right sink from the node menu host: retargets to the point
    // under the press and reopens, or stays dismissed on a miss.
    void retargetNodeMenu(const QPointF &scenePosition);
    // Ends only the node menu's session ownership, without stealing focus.
    void cancelNodeMenuWithoutFocus();
    // Shared-session Quick confirmation behind Delete CC lane on a nonempty
    // lane; implemented in automationcanvas_deleteprompt.cpp. clear drops the
    // pending target, optionally returning focus to the band; the
    // without-focus variant serves the shared invalidation policy (document
    // change, rebuild, hidden, detach, session replacement) and only ends a
    // session this canvas still owns.
    // writtenEventCount is resolved once at show time by the caller's
    // document-written query; revision equality revalidated across the open's
    // cancellation keeps that captured count truthful.
    bool openCcDeletePrompt(LaneHandle handle, std::size_t writtenEventCount);
    void clearCcDeletePrompt(bool restoreFocus);
    void cancelCcDeletePromptWithoutFocus();
    void ensureMenuAdapters();
    void ensureNodeMenuAdapters();
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
    AutomationPage &m_page;
    songview::TimelineInputHost *m_inputHost = nullptr;
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
    std::optional<PendingValuePrompt> m_pendingValuePrompt;
    songview::QuickMenuHost *m_menuHost = nullptr;
    songview::QuickMenuModel *m_menuModel = nullptr;
    QPointer<songview::QuickPopupSession> m_menuSession;
    std::optional<PendingMenu> m_pendingMenu;
    // Typed node point menu adapter over the shared canvas popup session.
    songview::QuickMenuHost *m_nodeMenuHost = nullptr;
    songview::QuickMenuModel *m_nodeMenuModel = nullptr;
    std::optional<PendingNodeMenu> m_pendingNodeMenu;
    std::optional<PendingCcDeletePrompt> m_pendingCcDeletePrompt;
    QMetaObject::Connection m_ccDeletePromptCancellation;
    NodeLaneHoverState m_hoverState;
    NodeDoubleClickGuard m_deletedNodeClick;
    // View-local selector state: the QML-published grid minimum and the
    // active parameter identity (null controller selects song-global Tempo;
    // the default is Volume).
    int m_minimumContentHeight = 0;
    std::optional<uint8_t> m_activeController = CoreTimeDefaults::kCcVolume;
};
