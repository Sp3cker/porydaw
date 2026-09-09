#pragma once

#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/timelinebandlayout.h"

#include <QColor>
#include <QEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QTimer>
#include <array>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <vector>

class AutomationPage;
class DrawerChrome;
class QQmlContext;
class QQmlEngine;
class EventListController;
class SongView;
class VelocityArea;
class VoiceChangeArea;

namespace songview {

class OtherStrip;
class PianoRoll;
class TimeCamera;
class EventListInteraction;
class TimelineInputItem;
class QuickPopupSession;

class TimelineGestureScrollbar;
enum class TimelineQuickHoverOwner : quint8 {
    None,
    Automation,
    VoiceChanges,
};

class TimeRuler;
class TrackHeaderModel;

enum class TimelineQuickDirty : quint16 {
    None = 0,
    Ruler = 1u << 0,
    OtherEvents = 1u << 1,
    Velocity = 1u << 2,
    VoiceChanges = 1u << 3,
    VoiceChangesHover = 1u << 4,
    All = (1u << 5) - 1,
};
Q_DECLARE_FLAGS(TimelineQuickDirtySet, TimelineQuickDirty)
Q_DECLARE_OPERATORS_FOR_FLAGS(TimelineQuickDirtySet)

// Producers OR independent refresh levels; one flush repaints each requested
// level's layers. Levels are not supersets of one another:
//   Content   — grid, curves, nodes, selection, primary text
//   Transient — drag-preview layer + transient text
//   Hover     — hover layer + hover text
enum class AutomationRefresh : quint8 {
    None = 0,
    Content = 1u << 0,
    Transient = 1u << 1,
    Hover = 1u << 2,
    All = (1u << 3) - 1,
};
Q_DECLARE_FLAGS(AutomationRefreshSet, AutomationRefresh)
Q_DECLARE_OPERATORS_FOR_FLAGS(AutomationRefreshSet)

static_assert(static_cast<quint32>(TimelineQuickDirty::All) <= std::numeric_limits<quint16>::max());

// Windowless Quick coordinator over the canonical timeline viewport: it
// owns no window or engine. An external host (WorkspaceQuickHost or a fixture
// host) constructs its own QQuickView, calls registerQuickTypes() before
// that engine exists, then attaches the scene via attachScene(engine,
// viewport). The root canvas item is the canonical viewport with origin
// (0, 0); SongView and TimelineBandLayout stay authoritative for all band
// geometry, published here without translation. While detached the
// coordinator keeps every domain model and dirty domain alive; only the
// QML borrows go null.
class TimelineQuickView final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickView)

    Q_PROPERTY(qreal hoverRootContentX READ hoverRootContentX NOTIFY hoverChromeChanged FINAL)
    Q_PROPERTY(bool hoverVisible READ hoverVisible NOTIFY hoverChromeChanged FINAL)
    Q_PROPERTY(qreal editRootContentX READ editRootContentX NOTIFY editChromeChanged FINAL)
    Q_PROPERTY(bool editVisible READ editVisible NOTIFY editChromeChanged FINAL)
    // Canonical timeline split: ruler gutter controls end before this
    // coordinate, while ruler marks and the playhead column start at it.
    Q_PROPERTY(qreal rulerPlotOrigin READ rulerPlotOrigin NOTIFY rulerPlotOriginChanged FINAL)
    Q_PROPERTY(qreal playheadLocalX READ playheadLocalX NOTIFY playheadXChanged FINAL)
    Q_PROPERTY(bool playheadVisible READ playheadVisible NOTIFY playheadChanged FINAL)
    Q_PROPERTY(bool playheadPlaying READ playheadPlaying NOTIFY playheadChanged FINAL)
    Q_PROPERTY(QColor playheadColor READ playheadColor NOTIFY playheadChanged FINAL)
    Q_PROPERTY(
        bool playheadTrianglePointsUp READ playheadTrianglePointsUp NOTIFY playheadChanged FINAL)
    Q_PROPERTY(qreal playheadGlowLeft READ playheadGlowLeft NOTIFY playheadChanged FINAL)
    Q_PROPERTY(qreal playheadGlowRight READ playheadGlowRight NOTIFY playheadChanged FINAL)
    Q_PROPERTY(qreal playheadPeakAlpha READ playheadPeakAlpha NOTIFY playheadChanged FINAL)
    Q_PROPERTY(qreal playheadLineWidthPx READ playheadLineWidthPx NOTIFY playheadChanged FINAL)
    Q_PROPERTY(int playheadTriangleHalfWidthPx READ playheadTriangleHalfWidthPx NOTIFY
                   playheadChanged FINAL)
    Q_PROPERTY(
        int playheadTriangleHeightPx READ playheadTriangleHeightPx NOTIFY playheadChanged FINAL)
    Q_PROPERTY(QRectF horizontalScrollbarRect READ horizontalScrollbarRect NOTIFY
                   scrollbarRectsChanged FINAL)
    Q_PROPERTY(
        QRectF verticalScrollbarRect READ verticalScrollbarRect NOTIFY scrollbarRectsChanged FINAL)
    Q_PROPERTY(
        qreal horizontalScrollValue READ horizontalScrollValue NOTIFY scrollbarStateChanged FINAL)
    Q_PROPERTY(qreal horizontalScrollMinimum READ horizontalScrollMinimum NOTIFY
                   scrollbarStateChanged FINAL)
    Q_PROPERTY(qreal horizontalScrollMaximum READ horizontalScrollMaximum NOTIFY
                   scrollbarStateChanged FINAL)
    Q_PROPERTY(qreal horizontalScrollPageStep READ horizontalScrollPageStep NOTIFY
                   scrollbarStateChanged FINAL)
    Q_PROPERTY(
        qreal verticalScrollValue READ verticalScrollValue NOTIFY scrollbarStateChanged FINAL)
    Q_PROPERTY(
        qreal verticalScrollMaximum READ verticalScrollMaximum NOTIFY scrollbarStateChanged FINAL)
    Q_PROPERTY(
        qreal verticalScrollPageStep READ verticalScrollPageStep NOTIFY scrollbarStateChanged FINAL)

  public:
    TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                      AutomationPage &automation, VelocityArea &velocity,
                      VoiceChangeArea &voiceChanges, DrawerChrome &drawerChrome,
                      TrackHeaderModel &trackHeaders, EventListController &eventList,
                      SongView &songView);
    ~TimelineQuickView() override;

    // Canonical viewport x for the ruler guides; SongView-local content x
    // publishes directly in the Quick canvas item's coordinates.
    qreal hoverRootContentX() const noexcept;
    bool hoverVisible() const noexcept;
    qreal editRootContentX() const noexcept;
    bool editVisible() const noexcept;
    qreal rulerPlotOrigin() const noexcept;
    // Playhead state pushed by PlayheadOverlay's Quick forwarder (the
    // Windows/Linux playhead path). X is raw timeline-column-local
    // TimeCamera::contentX; visibility is already effective. Both default to
    // hidden/zero so the macOS native path never drives the Quick playhead.
    qreal playheadLocalX() const noexcept;
    bool playheadVisible() const noexcept;
    bool playheadPlaying() const noexcept;
    QColor playheadColor() const;
    bool playheadTrianglePointsUp() const noexcept;
    // Shared metrics from ui/playheadoverlay.h; glow extents and peak alpha
    // vary with the playing flag, the rest are static per theme.
    qreal playheadGlowLeft() const noexcept;
    qreal playheadGlowRight() const noexcept;
    qreal playheadPeakAlpha() const noexcept;
    qreal playheadLineWidthPx() const noexcept;
    int playheadTriangleHalfWidthPx() const noexcept;
    int playheadTriangleHeightPx() const noexcept;
    void setPlayhead(qreal localX, bool effectiveVisible, bool playing, bool trianglePointsUp);
    void setPlayheadColor(const QColor &color);
    void synchronizeGuides(qreal songViewSplitX, std::optional<qreal> editSongViewContentX);
    void publishHover(TimelineQuickHoverOwner owner, uint64_t tick, qreal songViewContentX);
    void clearHover(TimelineQuickHoverOwner owner);
    // Registers the timeline QML types into the "Porydaw.Ui" module;
    // idempotent. Hosts call this before constructing their QQuickView (the
    // view constructs its engine); attachScene() re-asserts it defensively
    // before creating the canvas component.
    static void registerQuickTypes();

    // Attaches the one coordinator scene to an external host: builds the
    // per-scene QQmlContext on top of the engine root context (parented to
    // this coordinator; no page data enters the engine root context), asks
    // DrawerChrome for its icon provider, creates the existing TimelineCanvas
    // QML in that context, parents it visually to the supplied viewport item
    // (which the canvas fills and observes for size and window association)
    // while keeping its QObject ownership here, and wires every interaction,
    // popup, scrollbar, and layer binding. The host keeps sole ownership of
    // the engine, window, and viewport — this coordinator only borrows them,
    // observes engine destruction, and destroys the owned canvas there if a
    // host drops its engine without detaching. One attached scene per
    // coordinator: attaching while a scene is attached is a contract
    // violation, and the viewport must already be associated with a
    // QQuickWindow. Emits viewportChanged() once the scene is fully attached
    // so SongView republishes its complete state into the real viewport.
    void attachScene(QQmlEngine &engine, QQuickItem &viewport);

    // Live QML borrows. rootObject() is the created canvas item whose
    // dimensions define the canonical viewport; all three return null while
    // detached or once an external host destroyed the borrowed window.
    QQuickItem *rootObject() const;
    QQuickWindow *quickWindow() const;
    // Shared canvas popup owner for typed menus and forms; null while
    // detached.
    QuickPopupSession *popupSession() const noexcept;

    // Page-scoped input eligibility: the conjunction of explicit host page
    // selection, projected readiness (SongTab projects its load facts and
    // starts unready; standalone domain views default ready), a live
    // attached scene, and the canvas's and window's effective visibility.
    // Losing eligibility disables this page's canvas subtree — never the
    // shared window or any sibling page — and cancels the page's outgoing
    // pointer/key transients, popup, and audition without focus
    // restoration; grab release stays bounded to this page's subtree.
    bool inputEligible() const noexcept;
    void setInputReady(bool ready);
    void setPageSelected(bool selected);

    // Idempotent teardown: stops the layout/flush timers, cancels the
    // popup and every live gesture, clears the key wiring, detaches all
    // interaction and session bindings, drops the window surveillance and
    // native association, and destroys the QML root, popup session, scene
    // context, and icon provider in dependency order — while every domain
    // model is still alive and without ever destroying the host window or
    // engine. Emits windowAboutToDetach() once per detach while the
    // borrowed window is still valid; re-entry during the emission is
    // inert. Afterwards quickWindow(), rootObject(), and popupSession()
    // return null and the update entry points become inert; a later
    // attachScene() rebuilds the whole scene.
    void detachScene();

    void syncAppearance();
    void setBandLayout(TimelineBandLayout layout);
    // Republishes the stored band layout after canvas resizes or Quick-window
    // lifecycle events (screen, DPR); changes neither the canonical value nor
    // dirty domains.
    void refreshBandLayout();
    // Canonical scrollbar lanes in viewport coordinates; empty means the
    // lane is absent (the roll bar hides in EventList mode). Published with
    // the band layout and re-notified whenever either rectangle changes.
    QRectF horizontalScrollbarRect() const noexcept;
    QRectF verticalScrollbarRect() const noexcept;
    // Fractional-DIP camera scroll state for the QML scrollbar controls;
    // read straight from SongView's camera, never cached here.
    qreal horizontalScrollValue() const;
    qreal horizontalScrollMinimum() const;
    qreal horizontalScrollMaximum() const;
    qreal horizontalScrollPageStep() const;
    qreal verticalScrollValue() const;
    qreal verticalScrollMaximum() const;
    qreal verticalScrollPageStep() const;
    // QML scrollbar input entry points: authoritative SongView camera
    // updates. Page-scoped input eligibility disables the whole canvas
    // subtree, so the scrollbar drag and wheel handlers that produce these
    // calls cannot fire while ineligible — no readiness flag lives here,
    // keeping C++ callers (drawer chrome, view-state restore) working as
    // legitimate programmatic updates; wheel deltas keep the platform's
    // natural-scroll sign (never re-inverted).
    Q_INVOKABLE void setHorizontalScroll(qreal value);
    Q_INVOKABLE void setVerticalScroll(qreal value);
    Q_INVOKABLE void scrollHorizontalByWheel(qreal pixelX, qreal pixelY, qreal angleX, qreal angleY,
                                             bool inverted);
    Q_INVOKABLE void scrollVerticalByWheel(qreal pixelX, qreal pixelY, qreal angleX, qreal angleY,
                                           bool inverted);
    // SongView camera tail: refreshes the scrollbar scalar bindings after
    // any camera/viewport/range mutation, even a no-op one.
    void notifyScrollbarsChanged();
    // Live Quick-window device pixel ratio for camera and projection math;
    // 1.0 only before the Quick window exists.
    qreal quickDevicePixelRatio() const;

    // Focus bridge over the converted Quick input items. focusBand() returns
    // false only when a band's input item does not exist yet; otherwise it
    // requests focus through the shared window's ordinary Quick focus chain.
    // focusedBand() reads live QQuick active focus, never a cached flag.
    bool focusBand(TimelineBand band, Qt::FocusReason reason);
    std::optional<TimelineBand> focusedBand() const;
    // EventList mode: focuses the event page's input item (the row-command
    // surface). Returns false only while the input item does not exist yet.
    bool focusEventListInput(Qt::FocusReason reason);
    // EventList mode companion to focusedBand(): true while the event page's
    // input item holds live active focus. The event surface is not a
    // TimelineBand, so focusedBand() deliberately reports nullopt for it —
    // this query is how a caller distinguishes that state from "nothing
    // focused".
    bool eventListSurfaceFocused() const;
    // SongView calls this before destroying a direct-owned band interaction.
    void detachInputInteraction(TimelineBand band);

    // Song key-policy bridge over the converted Quick inputs. Band, gutter
    // and drawer-chrome input items run their attached interaction first and
    // hand declined keys to SongView::handleEditKey through the guarded
    // callback installed here; forwardUnhandledKey(Release) is the matching
    // scene-root fallback for keys unclaimed by non-band QML chrome. A true
    // return means the shared policy consumed the key. gestureActive() and
    // cancelActiveGestures() let the shared policy protect command execution
    // from live pointer gestures across every attached interaction and QML
    // scrollbar thumb drag.
    bool gestureActive() const;
    void cancelActiveGestures();
    Q_INVOKABLE bool forwardUnhandledKey(int key, int modifiers, const QString &text,
                                         bool autoRepeat);
    Q_INVOKABLE bool forwardUnhandledKeyRelease(int key, int modifiers, const QString &text,
                                                bool autoRepeat);

    void requestUpdate(PianoRollQuickDirtySet dirty);
    void requestTimelineUpdate(TimelineQuickDirtySet dirty);
    void requestAutomationUpdate(AutomationRefreshSet dirty);

  signals:
    void hoverChromeChanged();
    void editChromeChanged();
    void rulerPlotOriginChanged();
    void playheadChanged();
    void scrollbarRectsChanged();
    void scrollbarStateChanged();
    void playheadXChanged();
    // Emitted once per detachScene() while the borrowed window is still
    // valid; native attachments clear here.
    void windowAboutToDetach();
    // The canvas item resized, or its Quick window resized, changed screens,
    // or changed DPR: SongView reruns its viewport layout choreography. The
    // scene's window mapping (canvas rect through every ancestor), effective
    // visibility, or effective ancestor clipping changing re-reports here
    // too, so native overlays retarget without a window resize.
    void viewportChanged();
    // Page-scoped input eligibility flipped; see inputEligible().
    void inputEligibleChanged();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    friend class QuickWindowInput;

    std::optional<qreal>
    guideSongViewContentXAtOrAfterStart(std::optional<qreal> songViewContentX) const noexcept;
    void setHoverChrome(std::optional<qreal> songViewContentX);
    void setEditChrome(std::optional<qreal> songViewContentX);

    void scheduleTimelineBandLayoutPublication();
    void publishTimelineBandLayout();
    void discoverGestureScrollbars(QObject &root);
    void trackViewportWindow(QQuickWindow *window);
    void retargetPopupSession(QQuickWindow *window);
    void setPopupSessionBindings(QuickPopupSession *session);
    void handleEngineDestroyed(const QQmlEngine &engine);
    // One hostless input-unbinding path shared by detachScene() and the
    // engine-loss observation: detaches every interaction, key policy, and
    // session binding while the domain models are alive, then clears the
    // raw QML borrows.
    void unbindSceneInputs();
    // Page input eligibility edges and the scene-mapping report behind
    // viewportChanged; both live with the window lifecycle code.
    void updateInputEligibility();
    bool sceneEffectivelyVisible() const;
    void watchSceneMapping();
    void disconnectSceneMappingWatch();
    bool isPageSubtreeItem(const QQuickItem &item) const;
    void registerGestureScrollbar(TimelineGestureScrollbar &scrollbar);
    void forgetGestureScrollbar(TimelineGestureScrollbar *scrollbar);
    void installKeyPolicyHandlers();
    void clearKeyPolicyHandlers();
    bool dispatchSongKey(const TimelineKeyInput &input);
    bool dispatchSongKeyRelease(const TimelineKeyInput &input);
    void flushUpdate();
    // One sync entry point per band; flushUpdate dispatches one call per
    // dirty band, and each sync owns that band's rebuild + layer updates.
    void syncPianoRoll(PianoRollQuickDirtySet dirty);
    void syncRuler();
    void syncOtherEvents();
    void syncVelocity();
    void syncVoiceChanges(TimelineQuickDirtySet dirty);
    void syncAutomation(AutomationRefreshSet refresh);
    void updateLayer(TimelineQuickLayer layer);

    void rebuildGrid();
    void rebuildNoteFills();
    void rebuildDrawPreviewFill();
    void rebuildNoteBordersAndSelection();
    void rebuildOverlay();
    void rebuildKeyboardKeys();
    void rebuildKeyboardHighlights();
    void synchronizeNoteText();
    void synchronizeLoadingText();
    void synchronizeKeyboardText();
    void synchronizeHoverChip();

    TimeRuler *m_ruler = nullptr;
    QPointer<TrackHeaderModel> m_trackHeaders;
    QPointer<PianoRoll> m_roll;
    QPointer<OtherStrip> m_otherEvents;
    QPointer<AutomationPage> m_automation;
    QPointer<VelocityArea> m_velocity;
    QPointer<VoiceChangeArea> m_voiceChanges;
    QPointer<DrawerChrome> m_drawerChrome;
    QPointer<SongView> m_songView;
    QPointer<EventListController> m_eventList;
    const TimeCamera &m_camera;
    // Primary plot inputs own focus and their interaction host; gutter inputs
    // only forward their physical-side event coordinates to that same interaction.
    std::array<QPointer<TimelineInputItem>, timelineBandIndex(TimelineBand::Count)> m_inputItems{};
    std::array<QPointer<TimelineInputItem>, timelineBandIndex(TimelineBand::Count)>
        m_gutterInputItems{};
    // EventList mode: the page's input item and its interaction; the
    // interaction joins the shared key-policy chain like every band input.
    QPointer<TimelineInputItem> m_eventListInput;
    std::unique_ptr<EventListInteraction> m_eventListInteraction;
    std::array<QPointer<TimelineInputItem>, 5> m_drawerChromeInputs{};
    // Typed QML scrollbar roots discovered once after scene construction.
    // QPointers survive teardown; destroyed connections erase identities as
    // soon as their QML object dies.
    std::vector<QPointer<TimelineGestureScrollbar>> m_gestureScrollbars;
    // Every remaining QML borrow is a QPointer as well: detachScene()
    // clears them, and an external host destroying the borrowed window or
    // viewport nulls them on their own while the coordinator-owned canvas
    // is destroyed by the engine-loss observation.
    TimelineQuickScene *m_scene = nullptr;
    // The borrowed host window, viewport, and engine; null while detached.
    // The window borrow follows the viewport's live window association —
    // reassociation retargets the window-bound collaborators — and nulls
    // out whenever the window dies.
    QPointer<QQuickWindow> m_view;
    QPointer<QQuickItem> m_viewport;
    QQmlEngine *m_engine = nullptr;
    QMetaObject::Connection m_engineDestroyed;
    // Per-scene QML context: parented to this coordinator, based on the
    // host engine's root context. Created by attachScene(), destroyed by
    // detachScene() after the canvas and popup session.
    QQmlContext *m_sceneContext = nullptr;
    // Detach-in-flight guard: a windowAboutToDetach listener may re-enter
    // while the borrows are still live; the nested call returns without
    // re-emitting or re-running. Cleared once teardown finishes so a later
    // attachScene() can run.
    bool m_detaching = false;
    // Coordinator-owned QML canvas root: QObject-parented to this
    // coordinator, visually parented to the host viewport. Deleted in
    // detachScene() and by the engine-loss observation when a host drops
    // its engine without detaching; never abandoned.
    QPointer<QQuickItem> m_root;
    QuickPopupSession *m_popupSession = nullptr;
    std::array<QPointer<TimelineQuickItem>, static_cast<std::size_t>(TimelineQuickLayer::Count)>
        m_items{};
    std::array<QPointer<TimelineChromeItem>, 12> m_chromeItems{};
    TimelineBandLayout m_bandLayout;
    // Published canonical timeline split (SongView::timelineSplitX()).
    qreal m_publishedRulerPlotOrigin = 0.0;
    QRectF m_publishedHorizontalScrollbarRect;
    QRectF m_publishedVerticalScrollbarRect;
    std::optional<qreal> m_hoverSongViewContentX;
    std::optional<qreal> m_editSongViewContentX;
    qreal m_playheadLocalX = 0.0;
    bool m_playheadEffectiveVisible = false;
    bool m_playheadPlaying = false;
    bool m_playheadTrianglePointsUp = false;
    QColor m_playheadColor;
    TimelineQuickHoverOwner m_hoverOwner = TimelineQuickHoverOwner::None;
    uint64_t m_hoverTick = 0;
    PianoRollQuickDirtySet m_pendingDirty = {PianoRollQuickDirty::None};
    TimelineQuickDirtySet m_pendingTimelineDirty = {TimelineQuickDirty::None};
    AutomationRefreshSet m_pendingAutomationRefresh = {AutomationRefresh::None};
    QTimer m_layoutTimer;
    QTimer m_flushTimer;
    std::vector<TimelineQuickTextModel::Record> m_noteTextRecords;
    std::vector<TimelineQuickTextModel::Record> m_loadingTextRecords;
    std::vector<TimelineQuickTextModel::Record> m_keyboardTextRecords;
    // Page input eligibility state. Standalone domain views default ready;
    // hosts select explicitly and SongTab projects its load-fact readiness.
    bool m_inputReady = true;
    bool m_pageSelected = false;
    bool m_inputEligible = false;
    // Last scene state reported through viewportChanged: the canvas rect in
    // window scene coordinates, its effective visibility through every
    // ancestor, whether any ancestor clips, and the canvas rect intersected
    // with every clipping ancestor (so a clipping-ancestor resize that leaves
    // the canvas rect and the clip flag unchanged still re-reports when the
    // visible intersection moves). Ancestor x/y/width/height/visible/clip
    // changes re-report through the watch installed by watchSceneMapping();
    // the canvas's own size keeps its single canvasResized publisher.
    QRectF m_reportedSceneRect;
    bool m_reportedSceneVisible = false;
    bool m_reportedSceneClipped = false;
    QRectF m_reportedClipRect;
    std::vector<QMetaObject::Connection> m_sceneMappingWatch;
};

} // namespace songview
