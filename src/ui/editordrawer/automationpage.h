#pragma once

#include <cstdint>

#include <QWidget>

#include "ui/editordrawer/drawerpage.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songviewmodel.h"

class QEvent;
class QAction;
class QObject;
class QKeyEvent;
class QWheelEvent;
class QPainter;
class QRect;
class AutomationCanvas;
class TempoLane;
class CCLanes;
struct NodeLaneHoverState;
class MidiTimeline;
class SongDocument;
class SongView;
struct AutomationGeometry;

// The concrete automation page owns its scroll surface and keeps a stable
// SongView owner for shared song data and editor routing.
class AutomationPage final : public QWidget
{
  public:
    explicit AutomationPage(SongView &owner, QWidget *parent = nullptr);
    ~AutomationPage() override;

    AutomationCanvas *canvas() noexcept { return m_canvas; }
    const AutomationCanvas *canvas() const noexcept { return m_canvas; }
    bool event(QEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;
    const EditorViewState &automationViewState() const noexcept { return m_viewState; }
    const SongViewModel &model() const noexcept;

    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void addEmptyLane(int track, uint8_t controller);
    void removeEmptyLane(int track, uint8_t controller);
    void setLaneRange(const EditorAutomationRowId &row, uint8_t range);

  private:
    friend class AutomationCanvas;
    friend class CCLanes;
    friend class TempoLane;
    friend struct NodeLaneHoverState;
    // Read-only access to the timeline mapping queries (tickAtContentX,
    // displayX, visible grid cells) and m_viewState row layout.
    friend class AutomationProjection;

    struct Geometry {
        int rowDefaultHeight = 0;
        int addLaneStripHeight = 0;
        int defaultPixelsPerBeat = 0;

        static Geometry resolve();
    };

    void refreshGeometry();
    int scrollGutter() const noexcept;
    int laneHeightFor(const EditorAutomationRowId &row) const noexcept;
    bool scaleSharedHeight(int wheelSteps, const AutomationGeometry &geometry);
    class ScrollArea;
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
    void requestTimeZoom(const QWheelEvent *event, qreal anchorContentX) const;
    void setFollowScrollPaused(bool paused) const;
    void publishViewState();
    void rebuildModel();
    void publishTimeSelection(uint64_t startTick, uint64_t endTick,
                              const std::vector<std::pair<int, uint8_t>> &lanes,
                              bool tempo = false) const;
    DrawerPageVoiceContext voiceContext(uint64_t tick) const;
    void showTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request) const;
    bool pickVoice(const QString &title, int initialVoice, int *outVoice) const;
    void requestRefresh() const;
    void commitEditCursor(uint64_t tick) const;
    void announce(const QString &message) const;
    bool paintGrid(QPainter &painter, const QRect &bounds, qreal origin) const;

    bool matchesPencilShortcut(const QKeyEvent *event) const noexcept;

    Geometry m_geometry;
    SongView &m_owner;
    QAction *m_pencilModeAction = nullptr;
    DrawerPageLiveState m_liveState;
    EditorViewState m_viewState;
    ScrollArea *m_scroll = nullptr;
    AutomationCanvas *m_canvas = nullptr;
};
