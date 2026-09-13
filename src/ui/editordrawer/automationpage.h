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
class AutomationCanvas;
class TempoLane;
class CCLanes;
struct NodeLaneHoverState;
class MidiTimeline;
class SongDocument;
class SongView;
class QWindow;

namespace songview {
class Grid;
struct TimelineWheelInput;
} // namespace songview

// The concrete automation page owns one plot viewport and keeps a stable
// SongView owner for shared song data and editor routing.
class AutomationPage final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationPage)

  public:
    explicit AutomationPage(SongView &owner, QObject *parent);

    AutomationCanvas *canvas() noexcept { return m_canvas; }
    const AutomationCanvas *canvas() const noexcept { return m_canvas; }
    // Borrow the canonical Pencil action while the owning view is bound.
    QPointer<QAction> pencilModeAction() const noexcept;
    QSize automationViewportSize() const noexcept;
    void synchronizeAutomationViewport(QSize viewportSize);
    // The Quick window that delivers this page's timeline input. Injected by
    // SongView after the shared Quick host is constructed.
    void setInputWindow(QWindow *window) noexcept;
    const EditorViewState &automationViewState() const noexcept { return m_viewState; }
    const SongViewModel &model() const noexcept;

    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void setLaneRange(const EditorAutomationRowId &row, uint8_t range);

  private:
    friend class AutomationCanvas;
    friend class CCLanes;
    friend class TempoLane;
    friend struct NodeLaneHoverState;
    friend class songview::TimelineQuickView;
    // Read-only access to the timeline mapping queries (tickAtContentX,
    // displayX, visible grid cells).
    friend class AutomationProjection;
    struct Geometry {
        int defaultPixelsPerBeat = 0;

        static Geometry resolve();
    };

    bool ready() const noexcept;
    const DrawerPageLiveState &liveState() const noexcept { return m_liveState; }
    const MidiTimeline *timeline() const noexcept;
    uint32_t usedTrackMask() const noexcept;
    SongDocument *document() const noexcept;
    const LoadedVoiceGroup *voicegroup() const noexcept;
    Tick snapTick(double tick, bool fineMode) const noexcept;
    Tick snapTickDown(double tick, bool fineMode) const noexcept;
    DrawerPageGridState gridState(Tick tick, bool fineMode) const noexcept;
    Tick nextGridTick(Tick tick, bool fineMode, Tick limit) const noexcept;
    double tickAtContentX(double x) const noexcept;
    qreal displayX(double tick, qreal origin, qreal dpr) const noexcept;
    double pxPerBeat() const noexcept;
    void requestHorizontalScroll(double value) const;
    void requestTimeZoom(const songview::TimelineWheelInput &input, qreal anchorContentX) const;
    void setFollowScrollPaused(bool paused) const;
    void publishViewState();
    void rebuildModel();
    void publishTimeSelection(Tick startTick, Tick endTick,
                              const std::vector<std::pair<int, uint8_t>> &lanes,
                              bool tempo = false) const;
    DrawerPageVoiceContext voiceContext(Tick tick) const;
    void showTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request) const;
    void requestRefresh() const;
    void requestQuickUpdate(songview::AutomationRefreshSet dirty) const;
    void commitEditCursor(Tick tick) const;
    void announce(const QString &message) const;

    QMetaObject::Connection m_inputWindowDeactivationConnection;

    Geometry m_geometry;
    SongView &m_owner;
    const songview::Grid &m_grid;
    DrawerPageLiveState m_liveState;
    EditorViewState m_viewState;
    AutomationCanvas *m_canvas = nullptr;
    QSize m_viewportSize;
    QPointer<QWindow> m_inputWindow;
};
