#pragma once

#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/timelinebandlayout.h"

#include <QEvent>
#include <QFlags>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QResizeEvent>
#include <QTimer>
#include <QWidget>
#include <array>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

class AutomationPage;
class QQuickView;
class SongView;
class VelocityArea;
class VoiceChangeArea;

namespace songview {

class OtherStrip;
class PianoRoll;
class TimelineInputItem;
enum class TimelineQuickHoverOwner : quint8 {
    None,
    Automation,
    VoiceChanges,
};

class TimeRuler;

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

class TimelineQuickView final : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickView)

    Q_PROPERTY(qreal hoverRootContentX READ hoverRootContentX NOTIFY hoverChromeChanged FINAL)
    Q_PROPERTY(bool hoverVisible READ hoverVisible NOTIFY hoverChromeChanged FINAL)
    Q_PROPERTY(qreal editRootContentX READ editRootContentX NOTIFY editChromeChanged FINAL)
    Q_PROPERTY(bool editVisible READ editVisible NOTIFY editChromeChanged FINAL)

  public:
    TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                      AutomationPage &automation, VelocityArea &velocity,
                      VoiceChangeArea &voiceChanges, SongView &songView);
    ~TimelineQuickView() override;

    // Quick-root coordinates; guide publication arrives in SongView coordinates.
    qreal hoverRootContentX() const noexcept;
    bool hoverVisible() const noexcept;
    qreal editRootContentX() const noexcept;
    bool editVisible() const noexcept;
    void synchronizeGuides(qreal songViewTimelineOriginX,
                           std::optional<qreal> editSongViewContentX);
    void publishHover(TimelineQuickHoverOwner owner, uint64_t tick, qreal songViewContentX);
    void clearHover(TimelineQuickHoverOwner owner);
    QQuickItem *rootObject() const;
    QQuickWindow *quickWindow() const;
    void syncAppearance();
    void setBandLayout(TimelineBandLayout layout);
    // Republishes the stored band layout after native-window lifecycle events
    // (show, WinId, DPR); changes neither the canonical value nor dirty domains.
    void refreshBandLayout();
    // Live Quick-window device pixel ratio for camera and projection math;
    // 1.0 only before the Quick window exists. Not named devicePixelRatio()
    // — this QWidget already inherits that QPaintDevice method.
    qreal quickDevicePixelRatio() const;

    // Focus bridge over the converted bands' input items. focusBand() returns
    // false only when a band's input item does not exist yet; otherwise it
    // focuses the container, requests the item's focus, and returns true —
    // the active-focus FocusIn may still be pending asynchronously.
    // focusedBand() reads live QQuick active focus, never a cached flag.
    bool focusBand(TimelineBand band, Qt::FocusReason reason);
    std::optional<TimelineBand> focusedBand() const;
    // SongView calls this before destroying its non-QObject ruler module.
    void detachInputInteraction(TimelineBand band);

    void requestUpdate(PianoRollQuickDirtySet dirty);
    void requestTimelineUpdate(TimelineQuickDirtySet dirty);
    void requestAutomationUpdate(AutomationRefreshSet dirty);

  signals:
    void hoverChromeChanged();
    void editChromeChanged();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;

  private:
    qreal quickRootXForSongViewX(qreal songViewX) const noexcept;
    std::optional<qreal>
    guideSongViewContentXAtOrAfterStart(std::optional<qreal> songViewContentX) const noexcept;
    void setHoverChrome(std::optional<qreal> songViewContentX);
    void setEditChrome(std::optional<qreal> songViewContentX);

    void publishTimelineBandLayout();
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
    QPointer<PianoRoll> m_roll;
    QPointer<OtherStrip> m_otherEvents;
    QPointer<AutomationPage> m_automation;
    QPointer<VelocityArea> m_velocity;
    QPointer<VoiceChangeArea> m_voiceChanges;
    QPointer<SongView> m_songView;
    std::array<TimelineInputItem *, timelineBandIndex(TimelineBand::Count)> m_inputItems{};
    TimelineQuickScene *m_scene = nullptr;
    QQuickView *m_quickView = nullptr;
    QWidget *m_quickContainer = nullptr;
    std::array<TimelineQuickItem *, static_cast<std::size_t>(TimelineQuickLayer::Count)> m_items{};
    std::array<TimelineChromeItem *, 12> m_chromeItems{};
    std::array<QPointer<QWidget>, 6> m_nativeChrome;
    TimelineBandLayout m_bandLayout;
    std::optional<qreal> m_hoverSongViewContentX;
    std::optional<qreal> m_editSongViewContentX;
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
};

} // namespace songview
