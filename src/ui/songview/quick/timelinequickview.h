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

// Map an item-local rectangle and intersect it with item/ancestor clips.
QRectF clippedSceneRect(const QQuickItem &item, const QRectF &localRect);

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

// Windowless coordinator: a host attaches its persistent page exactly once.
// Detach and engine loss are terminal; host windows and engines are borrowed.
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
    // Effective Quick playhead state for non-native platforms.
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
    // Registers timeline QML types before a host constructs its engine.
    static void registerQuickTypes();

    // Attaches the completed, window-associated QML page exactly once.
    Q_INVOKABLE void attachToPage(QQuickItem *viewport);

    // Attaches the canvas to one borrowed engine, window, and page viewport.
    // Reattachment is a contract violation; viewportChanged publishes completion.
    void attachScene(QQmlEngine &engine, QQuickItem &viewport);

    // Live QML borrows; null before attachment and after terminal teardown.
    QQuickItem *rootObject() const;
    QQuickWindow *quickWindow() const;
    // Shared typed popup owner; null outside the attached lifetime.
    QuickPopupSession *popupSession() const noexcept;

    // Input requires a selected, ready, visible page with a live scene.
    // Losing eligibility cancels only this page's transient interaction state.
    bool inputEligible() const noexcept;
    void setInputReady(bool ready);
    void setPageSelected(bool selected);

    // Terminal teardown releases every scene binding without destroying the host.
    // Re-entry is inert and later attachment is forbidden.
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

    // ShortcutOverride arbitration only: a claim never executes pencil
    // mode. Execution stays in SongView's shared edit-key policy.
    Q_INVOKABLE bool claimsPencilShortcut(int key, int modifiers) const;

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
    void observeWindow(QQuickWindow &window);
    // Attach-time popup-session creation for the bound window; detachScene()
    // and the engine-loss unbind destroy the session again.
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
    // Typed scrollbar roots discovered once after scene construction.
    std::vector<QPointer<TimelineGestureScrollbar>> m_gestureScrollbars;
    // Remaining QML borrows use QPointer and are cleared on teardown.
    TimelineQuickScene *m_scene = nullptr;
    // Borrowed host objects; the window is bound once and never retargeted.
    QPointer<QQuickWindow> m_view;
    QPointer<QQuickItem> m_viewport;
    QQmlEngine *m_engine = nullptr;
    QMetaObject::Connection m_engineDestroyed;
    // Per-scene QML context owned by this coordinator.
    QQmlContext *m_sceneContext = nullptr;
    // Prevents detach re-entry; the separate tombstone forbids later attachment.
    bool m_detaching = false;
    // Set on first attachment and never cleared.
    bool m_hasAttached = false;
    // Coordinator-owned canvas, visually parented to the borrowed viewport.
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
    // Last canvas mapping and clipping state published through viewportChanged.
    QRectF m_reportedSceneRect;
    bool m_reportedSceneVisible = false;
    bool m_reportedSceneClipped = false;
    QRectF m_reportedClipRect;
    std::vector<QMetaObject::Connection> m_sceneMappingWatch;
};

} // namespace songview
