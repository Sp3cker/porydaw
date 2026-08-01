#pragma once

#include <cstdint>

#include <QWidget>

#include "ui/editorpage.h"
#include "ui/editorviewstate.h"
#include "ui/songviewmodel.h"

class QEvent;
class QPainter;
class QScrollArea;
class QRect;
class AutomationArea;
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

    AutomationArea *area() noexcept { return m_area; }
    const AutomationArea *area() const noexcept { return m_area; }
    bool event(QEvent *event) override;
    const EditorViewState &automationViewState() const noexcept { return m_viewState; }
    const SongViewModel &model() const noexcept;

    void songChanged();
    void refreshLiveState(const EditorPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();

  private:
    friend class AutomationArea;

    bool ready() const noexcept;
    const EditorPageLiveState &liveState() const noexcept { return m_liveState; }
    const MidiTimeline *timeline() const noexcept;
    SongDocument *document() const noexcept;
    const LoadedVoiceGroup *voicegroup() const noexcept;
    int selectedTrack() const noexcept;
    uint64_t snapTick(double tick, bool fineMode) const noexcept;
    EditorPageGridState gridState(uint64_t tick, bool fineMode) const noexcept;
    uint64_t nextGridTick(uint64_t tick, bool fineMode, uint64_t limit) const noexcept;
    double tickAtContentX(double x) const noexcept;
    qreal displayX(double tick, qreal origin, qreal dpr) const noexcept;
    double pxPerBeat() const noexcept;
    void requestHorizontalScroll(double value) const;
    void requestTimeZoom(double value) const;
    void setFollowScrollPaused(bool paused) const;
    void publishViewState();
    void rebuildModel();
    void addEmptyLane(int track, uint8_t controller);
    void removeEmptyLane(int track, uint8_t controller);
    void setLaneRange(const EditorAutomationRowId &row, uint8_t range);
    void publishTimeSelection(uint64_t startTick, uint64_t endTick,
                              const std::vector<std::pair<int, uint8_t>> &lanes) const;
    EditorPageVoiceContext voiceContext(uint64_t tick) const;
    void showTimeSelectionMenu(const EditorPageTimeSelectionMenuRequest &request) const;
    bool pickVoice(const QString &title, int initialVoice, int *outVoice) const;
    void requestRefresh() const;
    void announce(const QString &message) const;
    bool paintGrid(QPainter &painter, const QRect &bounds, qreal origin) const;

    SongView &m_owner;
    EditorPageLiveState m_liveState;
    EditorViewState m_viewState;
    int m_rowsTrack = -2;
    QScrollArea *m_scroll = nullptr;
    AutomationArea *m_area = nullptr;
};
