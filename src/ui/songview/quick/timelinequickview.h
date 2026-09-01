#pragma once

#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickscene.h"

#include <QEvent>
#include <QFlags>
#include <QPointer>
#include <QQuickWidget>
#include <QRect>
#include <array>
#include <cstdint>
#include <limits>
#include <vector>

class AutomationPage;
class SongView;
class VelocityArea;
class VoiceChangeArea;

namespace songview {

class OtherStrip;
class PianoRoll;
enum class TimelineQuickHoverOwner : quint8 {
    None,
    Automation,
    VoiceChanges,
};

class TimeRuler;
enum class PianoRollQuickDirty : quint32 {
    None = 0,
    Grid = 1u << 0,
    NoteFills = 1u << 1,
    DrawPreviewFill = 1u << 2,
    NoteBordersAndSelection = 1u << 3,
    Overlay = 1u << 4,
    KeyboardKeys = 1u << 5,
    KeyboardHighlights = 1u << 6,
    NoteText = 1u << 7,
    LoadingText = 1u << 8,
    KeyboardText = 1u << 9,
    HoverChip = 1u << 10,
    All = (1u << 11) - 1,
};
Q_DECLARE_FLAGS(PianoRollQuickDirtySet, PianoRollQuickDirty)
Q_DECLARE_OPERATORS_FOR_FLAGS(PianoRollQuickDirtySet)

inline constexpr PianoRollQuickDirtySet cPlotDirty =
    PianoRollQuickDirty::Grid | PianoRollQuickDirty::NoteFills |
    PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::NoteBordersAndSelection |
    PianoRollQuickDirty::Overlay | PianoRollQuickDirty::NoteText;
inline constexpr PianoRollQuickDirtySet cPlotAndLoadingDirty =
    cPlotDirty | PianoRollQuickDirty::LoadingText;
inline constexpr PianoRollQuickDirtySet cNoteMutationDirty =
    PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteBordersAndSelection |
    PianoRollQuickDirty::NoteText;
inline constexpr PianoRollQuickDirtySet cVelocityMutationDirty =
    PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteText;
inline constexpr PianoRollQuickDirtySet cDrawCommitDirty =
    cNoteMutationDirty | PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::Overlay;

enum class TimelineQuickDirty : quint16 {
    None = 0,
    Ruler = 1u << 0,
    OtherEvents = 1u << 1,
    Velocity = 1u << 2,
    VoiceChanges = 1u << 3,
    VoiceChangesHover = 1u << 4,
    AutomationGrid = 1u << 5,
    AutomationCurves = 1u << 6,
    AutomationNodes = 1u << 7,
    AutomationSelection = 1u << 8,
    AutomationTransient = 1u << 9,
    AutomationHover = 1u << 10,
    AutomationText = 1u << 11,
    AutomationHoverText = 1u << 12,
    AutomationTransientText = 1u << 13,
    All = (1u << 14) - 1,
};
Q_DECLARE_FLAGS(TimelineQuickDirtySet, TimelineQuickDirty)
Q_DECLARE_OPERATORS_FOR_FLAGS(TimelineQuickDirtySet)

inline constexpr TimelineQuickDirtySet cAutomationMask =
    TimelineQuickDirty::AutomationGrid | TimelineQuickDirty::AutomationCurves |
    TimelineQuickDirty::AutomationNodes | TimelineQuickDirty::AutomationSelection |
    TimelineQuickDirty::AutomationTransient | TimelineQuickDirty::AutomationHover |
    TimelineQuickDirty::AutomationText | TimelineQuickDirty::AutomationHoverText |
    TimelineQuickDirty::AutomationTransientText;

static_assert(static_cast<quint32>(TimelineQuickDirty::All) <= std::numeric_limits<quint16>::max());

class TimelineQuickView final : public QQuickWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickView)

    Q_PROPERTY(qreal hoverRootContentX READ hoverRootContentX NOTIFY hoverChromeChanged FINAL)
    Q_PROPERTY(bool hoverVisible READ hoverVisible NOTIFY hoverChromeChanged FINAL)
    Q_PROPERTY(qreal editRootContentX READ editRootContentX NOTIFY editChromeChanged FINAL)
    Q_PROPERTY(bool editVisible READ editVisible NOTIFY editChromeChanged FINAL)
    Q_PROPERTY(
        qreal playheadRootContentX READ playheadRootContentX NOTIFY playheadChromeChanged FINAL)
    Q_PROPERTY(bool playheadVisible READ playheadVisible NOTIFY playheadChromeChanged FINAL)
    Q_PROPERTY(bool playheadPlaying READ playheadPlaying NOTIFY playheadChromeChanged FINAL)

  public:
    TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                      AutomationPage &automation, VelocityArea &velocity,
                      VoiceChangeArea &voiceChanges, SongView &songView);
    ~TimelineQuickView() override;

    qreal hoverRootContentX() const noexcept;
    bool hoverVisible() const noexcept;
    qreal editRootContentX() const noexcept;
    bool editVisible() const noexcept;
    qreal playheadRootContentX() const noexcept;
    bool playheadVisible() const noexcept;
    bool playheadPlaying() const noexcept;

    void synchronizeChrome(qreal rootOriginX, qreal editRootContentX, bool editVisible,
                           qreal playheadRootContentX, bool playheadVisible, bool playheadPlaying);
    void publishHover(TimelineQuickHoverOwner owner, uint64_t tick, qreal rootContentX);
    void clearHover(TimelineQuickHoverOwner owner);

    void syncAppearance();
    void requestUpdate(PianoRollQuickDirtySet dirty);
    void requestTimelineUpdate(TimelineQuickDirtySet dirty);

  signals:
    void hoverChromeChanged();
    void editChromeChanged();
    void playheadChromeChanged();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct PositionChrome {
        qreal rootContentX = 0.0;
        bool visible = false;
    };
    struct PlayheadChrome {
        qreal rootContentX = 0.0;
        bool visible = false;
        bool playing = false;
    };

    void setHoverChrome(qreal rootContentX, bool visible);
    void setEditChrome(qreal rootContentX, bool visible);
    void setPlayheadChrome(qreal rootContentX, bool visible, bool playing);

    void scheduleHostGeometryAndVisibilitySync();
    void synchronizeHostGeometryAndVisibility();
    void flushUpdate();
    void synchronize(PianoRollQuickDirtySet dirty);
    void synchronizeTimeline(TimelineQuickDirtySet dirty);

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

    QPointer<TimeRuler> m_ruler;
    QPointer<PianoRoll> m_roll;
    QPointer<OtherStrip> m_otherEvents;
    QPointer<AutomationPage> m_automation;
    QPointer<QWidget> m_automationScrollViewport;
    QPointer<VelocityArea> m_velocity;
    QPointer<VoiceChangeArea> m_voiceChanges;
    QPointer<SongView> m_songView;
    QRect m_rulerBandRect;
    QRect m_rollBandRect;
    QRect m_otherEventsBandRect;
    QRect m_automationBandRect;
    QRect m_velocityBandRect;
    QRect m_voiceChangesBandRect;
    TimelineQuickScene *m_scene = nullptr;
    std::array<TimelineQuickItem *, static_cast<std::size_t>(TimelineQuickLayer::Count)> m_items{};
    std::array<TimelineChromeItem *, 18> m_chromeItems{};
    PositionChrome m_hoverChrome;
    PositionChrome m_editChrome;
    PlayheadChrome m_playheadChrome;
    TimelineQuickHoverOwner m_hoverOwner = TimelineQuickHoverOwner::None;
    uint64_t m_hoverTick = 0;
    PianoRollQuickDirtySet m_pendingDirty = {PianoRollQuickDirty::None};
    TimelineQuickDirtySet m_pendingTimelineDirty = {TimelineQuickDirty::None};
    bool m_automationWasVisible = false;
    bool m_velocityWasVisible = false;
    bool m_voiceChangesWasVisible = false;
    bool m_hostSyncScheduled = false;
    bool m_flushScheduled = false;
    std::vector<TimelineQuickTextModel::Record> m_noteTextRecords;
    std::vector<TimelineQuickTextModel::Record> m_loadingTextRecords;
    std::vector<TimelineQuickTextModel::Record> m_keyboardTextRecords;
};

} // namespace songview
