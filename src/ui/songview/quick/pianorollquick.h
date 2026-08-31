#pragma once

#include "ui/songview/quick/timelinequickscene.h"

#include <QEvent>
#include <QFlags>
#include <QPointer>
#include <QQuickWidget>
#include <QRect>
#include <array>
#include <vector>

class SongView;

namespace songview {

class OtherStrip;
class PianoRoll;
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

enum class TimelineQuickDirty : quint8 {
    None = 0,
    Ruler = 1u << 0,
    OtherEvents = 1u << 1,
    All = (1u << 2) - 1,
};
Q_DECLARE_FLAGS(TimelineQuickDirtySet, TimelineQuickDirty)
Q_DECLARE_OPERATORS_FOR_FLAGS(TimelineQuickDirtySet)

class TimelineQuickView final : public QQuickWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickView)

  public:
    TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                      SongView &songView);
    ~TimelineQuickView() override;

    void syncAppearance();
    void requestUpdate(PianoRollQuickDirtySet dirty);
    void requestTimelineUpdate(TimelineQuickDirtySet dirty);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
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
    QPointer<SongView> m_songView;
    QRect m_rulerBandRect;
    QRect m_rollBandRect;
    QRect m_otherEventsBandRect;
    TimelineQuickScene *m_scene = nullptr;
    std::array<TimelineQuickItem *, static_cast<std::size_t>(TimelineQuickLayer::Count)> m_items{};
    PianoRollQuickDirtySet m_pendingDirty = {PianoRollQuickDirty::None};
    TimelineQuickDirtySet m_pendingTimelineDirty = {TimelineQuickDirty::None};
    bool m_flushScheduled = false;
    std::vector<TimelineQuickTextModel::Record> m_noteTextRecords;
    std::vector<TimelineQuickTextModel::Record> m_loadingTextRecords;
    std::vector<TimelineQuickTextModel::Record> m_keyboardTextRecords;
};

} // namespace songview
