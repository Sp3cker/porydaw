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
struct NodeLaneHoverState;
class MidiTimeline;
class SongDocument;
class SongView;
class QWindow;

namespace songview {
class Grid;
class TimeCamera;
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
    void refresh(DrawerScopes scopes);
    void cancelInteraction();
    void documentChanged();
    void setLaneRange(const EditorAutomationRowId &row, uint8_t range);

  private:
    friend struct NodeLaneHoverState;
    friend class songview::TimelineQuickView;
    // Read-only access to the timeline mapping queries (tickAtContentX,
    // displayX, visible grid cells).
    friend class AutomationProjection;

    bool ready() const noexcept;
    // x-mapping reads the camera live; row/model decisions follow the refresh scopes.
    const MidiTimeline *timeline() const noexcept;
    SongDocument &document() const noexcept;
    const LoadedVoiceGroup *voicegroup() const noexcept;
    Tick snapTick(double tick, bool fineMode) const noexcept;
    Tick snapTickDown(double tick, bool fineMode) const noexcept;
    Tick nextGridTick(Tick tick, bool fineMode, Tick limit) const noexcept;
    double tickAtContentX(double x) const noexcept;
    qreal displayX(double tick, qreal origin, qreal dpr) const noexcept;
    double pxPerBeat() const noexcept;
    double scrollX() const noexcept;
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

    void commitEditCursor(Tick tick) const;

    QMetaObject::Connection m_inputWindowDeactivationConnection;

    SongView &m_owner;
    const songview::Grid &m_grid;
    const songview::TimeCamera &m_camera;
    EditorViewState m_viewState;
    QSize m_viewportSize;
    QPointer<QWindow> m_inputWindow;
};
