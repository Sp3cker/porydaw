#pragma once

#include <cstdint>

#include <QObject>
#include <QPointer>
#include <QSize>

#include "ui/editordrawer/drawerpage.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songviewmodel.h"

class QAction;
class QEvent;
class AutomationCanvas;
class TempoLane;
class CCLanes;
struct NodeLaneHoverState;
class MidiTimeline;
class SongDocument;
class SongView;
class QQuickItem;
class QQuickWindow;
class QWindow;
struct AutomationGeometry;

namespace songview {
class Grid;
struct TimelineWheelInput;
} // namespace songview

// The concrete automation page owns its scroll state and keeps a stable
// SongView owner for shared song data and editor routing.
class AutomationPage final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationPage)

  public:
    explicit AutomationPage(SongView &owner, QObject *parent);
    ~AutomationPage() override;

    AutomationCanvas *canvas() noexcept { return m_canvas; }
    const AutomationCanvas *canvas() const noexcept { return m_canvas; }
    // Pencil-mode toggle; the shortcut dispatch lives in this page's
    // application event filter, which triggers the action on the configured
    // key. Exposed for settings-driven discovery.
    QAction *pencilModeAction() const noexcept { return m_pencilModeAction; }
    QSize automationViewportSize() const noexcept;
    int automationContentHeight() const noexcept;
    int verticalScroll() const noexcept;
    void setVerticalScroll(int value);
    bool scrollVertically(const songview::TimelineWheelInput &input);
    void synchronizeAutomationViewport(QSize viewportSize);
    bool eventFilter(QObject *watched, QEvent *event) override;
    // The Quick page item that delivers this page's timeline input; the
    // pencil shortcut guard identifies its targets through the page's
    // effective enabled/visible state and the window's focused-item
    // ancestry, never through window identity alone. Injected by the Quick
    // coordinator after the canvas exists and cleared before it is
    // destroyed.
    void setInputPage(QQuickItem *page) noexcept;
    const EditorViewState &automationViewState() const noexcept { return m_viewState; }
    const SongViewModel &model() const noexcept;

    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void addEmptyLane(int track, uint8_t controller);
    void removeEmptyLane(int track, uint8_t controller);
    void setLaneRange(const EditorAutomationRowId &row, uint8_t range);

  signals:
    void scrollStateChanged();

  private:
    friend class AutomationCanvas;
    friend class CCLanes;
    friend class TempoLane;
    friend struct NodeLaneHoverState;
    friend class songview::TimelineQuickView;
    // Read-only access to the timeline mapping queries (tickAtContentX,
    // displayX, visible grid cells) and m_viewState row layout.
    friend class AutomationProjection;
    struct Geometry {
        int rowDefaultHeight = 0;
        int addLaneStripHeight = 0;
        int defaultPixelsPerBeat = 0;

        static Geometry resolve();
    };

    int laneHeightFor(const EditorAutomationRowId &row) const noexcept;
    bool scaleSharedHeight(int wheelSteps, const AutomationGeometry &geometry);
    bool ready() const noexcept;
    const DrawerPageLiveState &liveState() const noexcept { return m_liveState; }
    const MidiTimeline *timeline() const noexcept;
    uint32_t usedTrackMask() const noexcept;
    SongDocument *document() const noexcept;
    const LoadedVoiceGroup *voicegroup() const noexcept;
    uint64_t snapTick(double tick, bool fineMode) const noexcept;
    uint64_t snapTickDown(double tick, bool fineMode) const noexcept;
    DrawerPageGridState gridState(uint64_t tick, bool fineMode) const noexcept;
    uint64_t nextGridTick(uint64_t tick, bool fineMode, uint64_t limit) const noexcept;
    double tickAtContentX(double x) const noexcept;
    qreal displayX(double tick, qreal origin, qreal dpr) const noexcept;
    double pxPerBeat() const noexcept;
    void requestHorizontalScroll(double value) const;
    void requestTimeZoom(const songview::TimelineWheelInput &input, qreal anchorContentX) const;
    void setFollowScrollPaused(bool paused) const;
    void publishViewState();
    void rebuildModel();
    void publishTimeSelection(uint64_t startTick, uint64_t endTick,
                              const std::vector<std::pair<int, uint8_t>> &lanes,
                              bool tempo = false) const;
    DrawerPageVoiceContext voiceContext(uint64_t tick) const;
    void showTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request) const;
    void requestRefresh() const;
    void requestQuickUpdate(songview::AutomationRefreshSet dirty) const;
    void commitEditCursor(uint64_t tick) const;
    void announce(const QString &message) const;

    bool matchesPencilShortcut(int key, Qt::KeyboardModifiers modifiers) const noexcept;
    // Window identity only: does this event's delivery chain (a child window
    // inherits through its QWindow parent) belong to the injected page's
    // window?
    bool deliveredThroughWindow(const QWindow &window) const noexcept;
    // Keyboard ownership: the target must be this page's window while the
    // page is effectively enabled and visible, and the window's focused item
    // must live in the page subtree. A matching QWindow alone is not
    // ownership: sibling pages share one window, and a hidden, disabled, or
    // unfocused page never claims the pencil shortcut.
    bool ownsKeyboardTarget(const QQuickWindow &window) const noexcept;

    Geometry m_geometry;
    SongView &m_owner;
    const songview::Grid &m_grid;
    QAction *m_pencilModeAction = nullptr;
    DrawerPageLiveState m_liveState;
    EditorViewState m_viewState;
    AutomationCanvas *m_canvas = nullptr;
    int m_scrollY = 0;
    int m_contentHeight = 0;
    QSize m_viewportSize;
    qreal m_verticalWheelRemainder = 0.0;
    QPointer<QQuickItem> m_inputPage;
};
