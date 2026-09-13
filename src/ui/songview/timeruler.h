#pragma once

#include "core/timedefaults.h"
#include "ui/songview/quick/timelineinput.h"

#include <QFont>
#include <QFontMetrics>
#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QString>
#include <QVariantMap>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

class SongDocument;

class SongView;

namespace songview {

class Grid;
class QuickMenuHost;
class QuickMenuModel;
class TimelineQuickScene;
class TimelineQuickView;
class TimeCamera;

// Typed ids for the ruler context menu rows. The model carries these raw
// values; owners and checks resolve rows by id (QuickMenuModel::rowForId),
// never by translated label.
enum class RulerMenuAction : int {
    SetLoopStart = 1,
    SetLoopEnd = 2,
    RemoveLoop = 3,
    LoopFromSelection = 4,
    InsertBlank = 5,
    Duplicate = 6,
    RemoveContents = 7,
    ClearSelection = 8,
    EditTimeSig = 9,
    RemoveTimeSig = 10,
    Paste = 11,
};

// Terminal focus completion shared by the action-backed context menus
// (ruler menu, note menu): the host has already closed the menu session
// when actionActivated() arrives, so a session still open is a follow-on
// form the command itself opened (the time-signature or velocity prompt)
// and keeps focus; otherwise `restore` returns focus to the invoking
// surface.
void restoreFocusUnlessFormOpen(SongView &owner, const std::function<void()> &restore);

class TimeRuler final : public QObject, public TimelineBandInteraction
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimeRuler)
    Q_PROPERTY(QString divisionText READ divisionText NOTIFY gridControlsChanged FINAL)
    Q_PROPERTY(QString feelText READ feelText NOTIFY gridControlsChanged FINAL)
    Q_PROPERTY(QString divisionToolTip READ divisionToolTip NOTIFY gridControlsChanged FINAL)
    Q_PROPERTY(QString feelToolTip READ feelToolTip NOTIFY gridControlsChanged FINAL)
    Q_PROPERTY(bool gridControlsEnabled READ gridControlsEnabled NOTIFY gridControlsChanged FINAL)
    Q_PROPERTY(QVariantMap gridControlAppearance READ gridControlAppearance NOTIFY
                   gridControlAppearanceChanged FINAL)
    Q_PROPERTY(int timeSigPromptInitialNumerator READ timeSigPromptInitialNumerator NOTIFY
                   timeSigPromptChanged FINAL)
    Q_PROPERTY(int timeSigPromptInitialDenominatorPow2 READ timeSigPromptInitialDenominatorPow2
                   NOTIFY timeSigPromptChanged FINAL)
    Q_PROPERTY(int timeSigPromptMinimumNumerator READ timeSigPromptMinimumNumerator CONSTANT FINAL)
    Q_PROPERTY(int timeSigPromptMaximumNumerator READ timeSigPromptMaximumNumerator CONSTANT FINAL)
    Q_PROPERTY(int timeSigPromptMinimumDenominatorPow2 READ timeSigPromptMinimumDenominatorPow2
                   CONSTANT FINAL)
    Q_PROPERTY(int timeSigPromptMaximumDenominatorPow2 READ timeSigPromptMaximumDenominatorPow2
                   CONSTANT FINAL)
    Q_PROPERTY(QString timeSigPromptTitle READ timeSigPromptTitle NOTIFY timeSigPromptChanged FINAL)
    Q_PROPERTY(QString timeSigPromptLabel READ timeSigPromptLabel NOTIFY timeSigPromptChanged FINAL)
    Q_PROPERTY(QVariantMap timeSigPromptAppearance READ timeSigPromptAppearance NOTIFY
                   timeSigPromptChanged FINAL)

  private:
    struct Geometry {
        int timelineDetailMinimumPixelsPerBeat;
        int timeRulerMinimumFontPixelSize;
        qreal timeRulerLetterSpacing;
        qreal timeRulerBeatLabelZoomFactor;

        static Geometry resolve();
    };

  public:
    explicit TimeRuler(SongView &owner);
    // Canonical ruler row height shared with SongView's spacer geometry.
    static int rowHeight();

    QString divisionText() const;
    QString feelText() const;
    QString divisionToolTip() const;
    QString feelToolTip() const;
    bool gridControlsEnabled() const noexcept;
    QVariantMap gridControlAppearance() const;
    void syncGridControls();
    void closePopups();
    Q_INVOKABLE void openDivisionMenu(QPointF position);
    Q_INVOKABLE void openFeelMenu(QPointF position);

    // Typed Quick-modal bridge for time-signature editing. The guarded target
    // remains with the ruler rather than a generic prompt result object.
    Q_INVOKABLE void acceptTimeSigPrompt(int numerator, int denominatorPow2);
    Q_INVOKABLE void cancelTimeSigPrompt();
    void cancelTimeSigPromptWithoutFocus();
    // Semantic entry for the shared Edit Time Signature action: opens the
    // guarded form at the current edit cursor — editing an explicit event
    // at that tick or inserting a new one seeded with the in-effect
    // signature. No menu snapshot is consulted.
    void editTimeSignatureAtCursor();
    int timeSigPromptInitialNumerator() const noexcept;
    int timeSigPromptInitialDenominatorPow2() const noexcept;
    static constexpr int timeSigPromptMinimumNumerator() noexcept { return 1; }
    static constexpr int timeSigPromptMaximumNumerator() noexcept { return 32; }
    static constexpr int timeSigPromptMinimumDenominatorPow2() noexcept { return 0; }
    static constexpr int timeSigPromptMaximumDenominatorPow2() noexcept { return 5; }
    QString timeSigPromptTitle() const;
    QString timeSigPromptLabel() const;
    QVariantMap timeSigPromptAppearance() const;
    bool gestureActive() const noexcept override;
    void cancelInteraction() override;

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerPress(const TimelinePointerInput &input) override;
    bool pointerDoubleClick(const TimelinePointerInput &input) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    bool pointerRelease(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const TimelineWheelInput &input) override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  signals:
    void gridControlsChanged();
    void gridControlAppearanceChanged();
    // Ordinary grid-menu choice completed (never dismissal): the in-scene
    // menu displaced the invoking control's focus, so QML returns it to the
    // matching control itself.
    void gridMenuActivated(bool division);
    void timeSigPromptChanged();

  private:
    friend class TimelineQuickView;
    void rebuildQuickScene(TimelineQuickScene &scene, bool horizontalPan);
    void requestQuickUpdate();
    static QFont resolveRulerFont(const Geometry &geometry);
    static int markerRowHeight(const QFontMetrics &metrics);
    void syncGridControlAppearance();
    void openGridMenu(QPointF position, bool division);
    // Emits gridMenuActivated() unless the setter opened a new popup.
    void notifyGridMenuChoice(bool division);
    QRect markerRow() const;
    QRect tickRow() const;
    int textBaseline(const QRect &row, const QFontMetrics &metrics) const;

    // Loop-marker and selection-edge grab zones live in the marker row —
    // where the bracket glyphs and edge handles are drawn — so the tick row
    // always scrubs the edit cursor even directly on a marker line.

    // 0 = start marker, 1 = end marker, -1 = neither near pos.
    int hitMarker(QPointF pos) const;

    // One time-signature chip as laid out in the marker row.
    struct SigChip {
        Tick tick;
        int numerator;
        int denomPow2;
        bool implicit; // no 0x58 meta behind it (editing one creates the event)
        qreal x;       // stem position (band-local coords)
        qreal labelX;  // label left edge, nudged right past a loop bracket
        qreal labelW;  // 0: label hidden behind the next chip (stem only)
    };

    // Chip layout shared by paint and hit-testing: shadowed same-tick
    // duplicates dropped, labels nudged past a loop bracket glyph sitting on
    // the same spot, and a label hidden (stem only) when it would run into
    // the next chip — zooming in separates them again.
    std::vector<SigChip> sigChips() const;

    // Chip hit-test in the ruler's top half, including the placeholder 4/4
    // at tick 0. Fills the chip's tick and values.
    bool hitTimeSigChip(QPointF pos, Tick *tick, int *numerator, int *denomPow2,
                        bool *implicit) const;

    // Values in effect at tick (4/4 before any 0x58 meta).
    void sigAtTick(Tick tick, int *numerator, int *denomPow2) const;

    // 0 = selection start edge, 1 = end edge, -1 = neither near pos.
    int hitSelEdge(QPointF pos) const;

    // Loop/selection/signature context menu over the shared canvas popup
    // session. scenePos is a Quick-window scene position (the release
    // point); the target comes from the consumed right-press gesture
    // state, never a pre-snapped argument.
    void showRulerMenu(const QPointF &scenePos);
    // Builds the menu host and row models once and wires their
    // activation/cancellation/invalidation connections together.
    void ensureMenuAdapters();
    // Drops the raw/exact right-press target without opening a menu.
    void clearRightPressTarget();

    struct PendingTimeSigPrompt {
        QPointer<SongDocument> document;
        uint64_t documentRevision = 0;
        Tick tick = 0;
        int initialNumerator = timeSigPromptMinimumNumerator();
        int initialDenominatorPow2 = timeSigPromptMinimumDenominatorPow2();
    };
    void openTimeSigPrompt(Tick tick, int numerator, int denominatorPow2);
    void clearTimeSigPrompt(bool restoreFocus);
    void restoreRulerFocus();

    QFont m_signatureFont;
    QFont m_rulerFont;
    QFont m_beatFont;
    QFont m_boldRulerFont;
    // Metrics of the fixed fonts above, built once in the constructor;
    // row heights, label widths, and baselines reuse them.
    QFontMetrics m_rulerMetrics{QFont{}};
    QFontMetrics m_beatMetrics{QFont{}};
    QFontMetrics m_boldRulerMetrics{QFont{}};
    QFontMetrics m_signatureMetrics{QFont{}};
    SongView &m_owner;
    const songview::TimeCamera &m_camera;
    const songview::Grid &m_grid;
    TimelineInputHost *m_inputHost = nullptr;
    Geometry m_geometry;
    QString m_divisionText;
    QString m_feelText;
    bool m_gridControlsEnabled = false;
    QVariantMap m_gridControlAppearance;
    // Typed menus over the shared canvas popup session; the host and all
    // row models (grid controls, ruler loop menu) are created on first
    // open — from either entry — and reused.
    QuickMenuHost *m_menuHost = nullptr;
    QuickMenuModel *m_divisionModel = nullptr;
    QuickMenuModel *m_feelModel = nullptr;
    QuickMenuModel *m_rulerMenuModel = nullptr;
    std::optional<PendingTimeSigPrompt> m_pendingTimeSigPrompt;
    QMetaObject::Connection m_timeSigPromptCancellation;
    int m_markerHeight = 0;
    int m_dragMarker = -1;
    Tick m_dragTick = 0;
    bool m_dragTimeSig = false;     // chip drag is live; commits moveTimeSig
    Tick m_dragTimeSigFrom = 0;     // the dragged signature's original tick
    bool m_leftPress = false;       // plain click vs. time-selection sweep undecided
    bool m_rightPress = false;      // right click held until the ruler menu opens
    bool m_selSweep = false;        // left-drag time-selection sweep is live
    bool m_multiTrackSweep = false; // modifier intent captured when the sweep is armed
    QPointF m_leftPressPos;
    // Right-press target state, captured raw/exact at press and consumed by
    // showRulerMenu before the menu opens — never the left-drag snapped
    // anchor. Cleared on release and cancellation.
    double m_rightPressTick = 0.0; // raw unsnapped press coordinate; meaningful only while
                                   // m_rightPress is set (tick 0 is a valid press point)
    bool m_rightPressChip = false; // press landed on a signature chip
    Tick m_rightPressChipTick = 0; // the chip's exact event tick
    Tick m_selAnchor = 0;          // snapped tick of the pending left press
    int m_dragSelEdge = -1;        // selection edge being left-dragged (0/1)
};

} // namespace songview
