#pragma once

// Selection-keyboard routing, gesture tier, as a genuine Qt Test: five
// independently selectable scenarios over standalone SongView rigs prove
// that a live pointer gesture owns its surface — overlap hit priority in the
// velocity plot, selected/unselected velocity transitions, roll note drags,
// automation pans — and that shared edit commands (Delete resolved through
// the live keymap) are consumed no-ops while a gesture is live, with the
// first Escape cancelling only the gesture and the second clearing the
// leftover selection. The discovered typed scrollbar thumbs (the root roll
// bar and nested drawer automation bar) get the same guard proof end to end
// as data rows: the live native MouseArea grab blocks Delete, Escape
// ungrabs it, held-button movement stays inert, and a physically released
// then newly pressed drag works normally.
//
// Every scenario stages a fresh world (song fixture + rig + Quick window), so
// one scenario's failure can never skip or poison another's. Programmatic
// staging is limited to selection, camera reveals, and section sizing; every
// interaction delivery is real QTest input into the shown QQuickWindow. The
// per-case cleanup releases any held button and drops any residual Quick
// grab, so an assertion failure mid-gesture cannot leak input into the next
// case. Scenario implementations live in gesturevelocity.cpp,
// gesturecommands.cpp, and gesturethumbs.cpp; the entry point and lifecycle
// live in gesture.cpp.

#include "checks/selectionkey/primitives.h"

#include "core/noteid.h"
#include "core/songdocument.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QQuickWindow>
#include <QString>

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

class SelectionKeyGestureTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SelectionKeyGestureTest)

  public:
    // Constructors store fixture strings only: listing -functions must stay
    // side-effect-free.
    SelectionKeyGestureTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();

    // The visible following node owns the velocity overlap: it paints above
    // the selected earlier stem in idle, hover, selected, and zoomed
    // presentations; a press-drag and a click target it; and equal
    // node-versus-node hits keep their model-order and selected tie-breaks.
    void overlapNodeTargetsVisibleNode();

    // A selected duration-stem drag retains the whole selection and blocks
    // edit keys; an unselected stem is a real replacement selection
    // transition.
    void velocityStemDragGuardsEdits();

    // A roll note drag is a live surface owner — the shared Delete is a
    // consumed no-op mid-drag, the first Escape cancels only the drag and
    // restores the captured selection, and the idle Escape then clears it.
    void rollNoteDragGuardsSharedCommands();

    // The automation band's middle-button pan is a live surface owner with
    // the same guard contract, preserving the staged time selection across
    // the cancelling Escape.
    void automationPanGuardsSharedCommands();

    // A registered scrollbar thumb (root roll bar, nested drawer automation
    // bar) is a live gesture surface exactly like the bands — the shared
    // Delete is a consumed no-op mid-drag, Escape releases the native
    // MouseArea grab, the still-held button cannot move or page the model,
    // and a physical release permits a fresh drag before the same binding
    // deletes. Each row is one thumb, independently selectable.
    void scrollbarThumbGuardsSharedCommands_data();
    void scrollbarThumbGuardsSharedCommands();

  private:
    // The three delivery points in velocity-input coordinates; a nullopt
    // return keeps callers from pressing outside the shown surface.
    struct VelocityStemPoints {
        QPointF earlierStem;
        QPointF followingNode;
        QPointF followingStem;
    };

    // Which live model value a thumb row reads back as its scroll evidence.
    enum class ThumbScrollRole : int {
        CameraScrollY,
        AutomationVerticalScroll,
    };

    // Reserved gesture fixture ticks: the routing notes at 24/60/96 carry
    // durations 48/24/24 (spans 24..72 / 60..84 / 96..120), so at the
    // canonical timeZoom 96 the earlier stem, the following node, and the
    // unselected stem sit ~36 px apart — every press has a dedicated target
    // clear of the velocity hit radius. The CC 10 lane point reuses
    // kFollowingTick.
    static constexpr int kTrack = 0;
    static constexpr uint64_t kEarlierTick = 24;
    static constexpr uint64_t kFollowingTick = 60;
    static constexpr uint64_t kLaterTick = 96;
    static constexpr uint32_t kEarlierDuration = 48;
    static constexpr uint32_t kFollowingDuration = 24;
    static constexpr uint32_t kLaterDuration = 24;
    static constexpr uint8_t kEarlierKey = 106;
    static constexpr uint8_t kFollowingKey = 105;
    static constexpr uint8_t kLaterKey = 104;
    static constexpr uint8_t kTiedKey = 103;
    static constexpr uint8_t kVelocity = 70;
    static constexpr uint8_t kAutomationController = 10;
    // Canonical gesture drawer heights: the velocity plot needs its full
    // 320 px stem range; 250 shows the automation lane; 180 forces the
    // automation page to overflow so its nested scrollbar becomes scrollable
    // (the proven scrollbar-check drag height).
    static constexpr int kVelocitySectionHeight = 320;
    static constexpr int kAutomationSectionHeight = 250;
    static constexpr int kScrollbarAutomationSectionHeight = 180;

    static std::vector<SongDocument::NewNote> gestureNoteSpecs();
    static void prepareGestureDocument(SongDocument &document);
    static songview::EditorSelectionModel::TimeSelection automationSelection();

    // Fresh-rig staging. On failure these record the assertion themselves
    // and return false, so callers must early-return without touching the
    // world.
    bool stageWorld(const char *worldLabel, EditorDrawerPage activePage, int sectionHeight);
    bool stageVelocitySurface();
    std::optional<VelocityStemPoints> velocityStemPoints();
    bool focusPointerSurface(songview::TimelineInputItem *input, songview::TimelineBand band);
    bool verifyNodePaintsAboveSelectedStem(const VelocityStemPoints &overlapPoints,
                                           const char *message);

    SongView &view();
    SongDocument &document();
    QQuickWindow *window();

    QPoint windowPoint(const songview::TimelineInputItem &input, QPointF itemPoint) const;
    bool noteSelectionIs(const std::vector<NoteId> &expected);

    // QTest delivery into the shown Quick window that records the held-input
    // state the failure-safe cleanup relies on; Escape cancels the
    // interaction but never this record.
    void mousePress(Qt::MouseButton button, const QPoint &windowPos);
    void mouseMove(const QPoint &windowPos);
    void mouseRelease(Qt::MouseButton button, const QPoint &windowPos);

    QString mProjectRoot;
    QString mSongLabel;
    std::unique_ptr<selectionkey::RigWorld> mWorld;
    QPointer<QQuickWindow> mQuickWindow;
    QPointer<songview::TimelineInputItem> mVelocityInput;
    QPointer<VelocityArea> mVelocityArea;
    QPointer<songview::TimelineInputItem> mRollInput;
    QPointer<songview::TimelineInputItem> mAutomationInput;
    Qt::MouseButton mHeldButton = Qt::NoButton;
    QPoint mLastWindowPos;
};
