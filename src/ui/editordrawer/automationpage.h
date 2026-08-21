#pragma once

#include <chrono>
#include <cstdint>

#include <QWidget>

#include "ui/editordrawer/automationpaint.h"
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
class VoiceChangeLane;
struct AutomationHoverState;
class MidiTimeline;
class SongDocument;
class SongView;

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
    friend class VoiceChangeLane;
    friend class TempoLane;
    friend class AutomationHoverState;
    // Read-only access to the timeline mapping queries (tickAtContentX,
    // displayX, visible grid cells) and m_viewState row layout.
    friend class AutomationProjection;
    friend void automation::paint::paintRow(QPainter &, const automation::paint::RowPaintParams &,
                                            const QRect &, const QFont &, const QFont &,
                                            const QRect &, const QRect &, AutomationCanvas &,
                                            AutomationPage &, const AutomationGeometry &, CCLanes &,
                                            const AutomationHoverState &,
                                            const std::optional<ActiveGesture> &, bool);
    friend void automation::paint::paintPlainGridFallback(QPainter &, const QRect &,
                                                          AutomationPage &, qreal, qreal);
    friend void automation::paint::paintHover(QPainter &, const automation::paint::RowPaintParams &,
                                              AutomationPage &, const AutomationGeometry &,
                                              const CCLanes &, const AutomationHoverState &, bool);
    friend void automation::paint::paintNodeDragPreview(QPainter &,
                                                        const automation::paint::RowPaintParams &,
                                                        const NodeDragGesture &, AutomationCanvas &,
                                                        AutomationPage &,
                                                        const AutomationGeometry &,
                                                        const AutomationHoverState &);
    friend void automation::paint::paintPencilPreview(QPainter &,
                                                      const automation::paint::RowPaintParams &,
                                                      const PencilGesture &, AutomationPage &,
                                                      const AutomationGeometry &,
                                                      const AutomationHoverState &);
    friend void automation::paint::paintCurve(QPainter &, const automation::paint::RowPaintParams &,
                                              AutomationCanvas &, AutomationPage &,
                                              const AutomationGeometry &, const CCLanes &);
    friend void automation::paint::paintCurveNodes(QPainter &,
                                                   const automation::paint::RowPaintParams &,
                                                   AutomationCanvas &, AutomationPage &,
                                                   const AutomationGeometry &, const CCLanes &);

    struct Geometry {
        int rowDefaultHeight = 0;
        int addLaneStripHeight = 0;
        int defaultPixelsPerBeat = 0;

        static Geometry resolve();
    };

    void refreshGeometry();
    int scrollGutter() const noexcept;
    int laneHeightFor(const EditorAutomationRowId &row) const noexcept;
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
    void automationGestureStarted() noexcept;
    bool handlesPencilShortcut(const QKeyEvent *event) const noexcept;
    void finishPencilShortcut(bool forceMomentary);

    Geometry m_geometry;
    SongView &m_owner;
    QAction *m_pencilModeAction = nullptr;
    DrawerPageLiveState m_liveState;
    EditorViewState m_viewState;
    ScrollArea *m_scroll = nullptr;
    AutomationCanvas *m_canvas = nullptr;
    std::chrono::steady_clock::time_point m_pencilShortcutPressedAt{};
    int m_pencilShortcutKey = 0;
    bool m_pencilShortcutHeld = false;
    bool m_pencilShortcutPriorState = false;
    bool m_pencilShortcutGestureStarted = false;
};
