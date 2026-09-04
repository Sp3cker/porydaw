#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QByteArray>
#include <QCursor>
#include <QEvent>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QSize>
#include <QString>

#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editorviewstate.h"
#include "ui/songview/quick/timelineinput.h"

namespace songview {
class TimelineBandInteraction;
class TimelineInputItem;
class TimelineQuickScene;
} // namespace songview

extern "C" {
#include "voicegroup_loader.h"
}

class QAction;
class AutomationCanvas;
class AutomationPage;
class QImage;
class MidiTimeline;
class QObject;
class SongView;

// In-memory TimelineInputHost driving the converted AutomationCanvas: it
// mirrors the plot-local primary input bounds, font, palette, DPR, and global
// mapping, and records focus, cursor, pointer-grab, and accessibility calls so
// checks assert host state instead of QWidget surface state. Bounds stay live
// on AutomationPage; this host never caches viewport size, content height, or
// scroll.
class AutomationInputHost final : public songview::TimelineInputHost
{
  public:
    AutomationInputHost(const AutomationPage &page, const songview::TimelineInputItem &gutterInput);
    ~AutomationInputHost() override = default;

    AutomationInputHost(const AutomationInputHost &) = delete;
    AutomationInputHost &operator=(const AutomationInputHost &) = delete;

    // Recorded-state queries for assertions.
    QCursor cursor() const noexcept; // ArrowCursor once clearCursor() runs
    bool cursorSet() const noexcept;
    int cursorAssignments() const noexcept;
    int cursorClears() const noexcept;
    int focusRequests() const noexcept;
    Qt::FocusReason lastFocusReason() const noexcept;
    int grabReleases() const noexcept;
    int globalMappings() const noexcept; // mapFromGlobal + mapToGlobal calls
    const QString &accessibilityDescription() const noexcept;
    const QPointF &globalOffset() const noexcept;

    // Fixture controls for appearance and mapping assertions.
    void setDevicePixelRatio(qreal dpr) noexcept;
    void setGlobalOffset(QPointF offset) noexcept;

    // TimelineInputHost
    QRectF bounds() const override;
    qreal devicePixelRatio() const override;
    QFont font() const override;
    QPalette palette() const override;
    QPointF mapFromGlobal(QPointF position) const override;
    QPointF mapToGlobal(QPointF position) const override;
    void requestFocus(Qt::FocusReason reason) override;
    void setCursor(const QCursor &cursor) override;
    void clearCursor() override;
    void releasePointerGrab() override;
    void setAccessibilityDescription(const QString &description) override;

  private:
    const AutomationPage &m_page;
    const songview::TimelineInputItem &m_gutterInput;
    qreal m_dpr = 1.0;
    QPointF m_globalOffset;
    QCursor m_cursor{Qt::ArrowCursor};
    bool m_cursorSet = false;
    int m_cursorAssignments = 0;
    int m_cursorClears = 0;
    int m_focusRequests = 0;
    Qt::FocusReason m_lastFocusReason = Qt::ActiveWindowFocusReason;
    int m_grabReleases = 0;
    mutable int m_globalMappings = 0;
    QString m_accessibilityDescription;
};

class AutomationGestureCheckRig final
{
  public:
    struct Lane {
        EditorAutomationRowId row;
        int track = 0;
        uint8_t controller = 0;
    };

    struct InputPoint {
        QPointF position;
        AutomationProjection::PointerMapping mapped;
    };

    struct Snapshot {
        QByteArray smf;
        uint64_t revision = 0;
        int undoIndex = 0;
        std::vector<DocLanePoint> lanePoints;
    };

    struct ValueRange {
        int min = 0;
        int max = 0;
    };

    static std::unique_ptr<AutomationGestureCheckRig> create(const QString &project,
                                                             const QString &song, QString &error);
    ~AutomationGestureCheckRig();

    AutomationGestureCheckRig(const AutomationGestureCheckRig &) = delete;
    AutomationGestureCheckRig &operator=(const AutomationGestureCheckRig &) = delete;

    SongDocument &document() noexcept;
    const SongDocument &document() const noexcept;
    SongView &view() noexcept;
    const SongView &view() const noexcept;
    AutomationPage &page() noexcept;
    const AutomationPage &page() const noexcept;
    AutomationCanvas &canvas() noexcept;
    const AutomationCanvas &canvas() const noexcept;
    AutomationInputHost &automationHost() noexcept;
    const AutomationInputHost &automationHost() const noexcept;
    songview::TimelineInputItem &automationGutterInput() noexcept;
    const songview::TimelineInputItem &automationGutterInput() const noexcept;
    songview::TimelineInputItem &voiceInput() noexcept;
    const songview::TimelineInputItem &voiceInput() const noexcept;
    QAction *pencilModeAction() const noexcept;

    // Host-recorded canvas surface state; checks assert these instead of
    // QWidget cursor and DPR reads.
    QCursor automationCursor() const noexcept;
    bool automationCursorSet() const noexcept;
    qreal automationDpr() const noexcept;
    int automationContentHeight() const noexcept;
    QSize automationViewportSize() const noexcept;
    // Resizes the automation viewport through the production path, so the
    // canvas rebuilds its geometry stack mid-gesture.
    void resizeAutomationViewport(const QSize &size);
    void canvasHostAppearanceChanged();

    AutomationGeometry geometry() const;
    AutomationProjection projection() const;
    int rowIndex(const Lane &lane) const noexcept;
    LaneHandle handleFor(const Lane &lane) const noexcept;
    QRect bodyFor(LaneHandle handle) const;
    QRect bodyFor(const Lane &lane) const;
    const songview::TimelineQuickScene &quickScene() const noexcept;

    InputPoint pointAt(LaneHandle handle, double tick, int value) const;
    AutomationProjection::PointerMapping mappingAt(LaneHandle handle,
                                                   const QPointF &position) const;
    QPointF tempoHeaderPoint() const;
    QPointF tempoBodyPoint(double tick, int bpm) const;
    Snapshot snapshot(int track, uint8_t controller) const;
    bool expandTempo();
    InputPoint pointAt(const Lane &lane, double tick, int value) const;
    QPointF automationContentToViewport(const QPointF &position) const;

    QPoint automationContentToViewport(const QPoint &position) const;
    QRect automationContentToViewport(const QRect &rect) const;
    QRect automationViewportInContent() const;
    QImage renderAutomationViewport(QString *error = nullptr);
    QImage renderAutomationContent(const QRect &contentRect, QString *error = nullptr);
    QImage renderVoiceChanges(QString *error = nullptr);

    void documentChanged();
    void setAutomationZoom(double zoom);
    void setAutomationScroll(double scroll);
    void setPersistentPencil(bool enabled);

    // True when no canvas pan or view gesture is in flight. Callers pump first;
    // the retained Quick scene and gesture state are per-view.
    bool isIdle() const noexcept;
    // Zoom/scroll a fixture view back to the canonical pencil-test framing.
    void resetView(double zoom = 96.0, double scroll = 0.0);
    // Runs the rig's event loop for `milliseconds` (0 = one pass).
    void commitTimers(int milliseconds = 0);
    // Value slab for a handle; tempo lane and unknown handles get the tempo range.
    ValueRange valueRange(LaneHandle handle) const;
    void keyToArea(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                   bool autoRepeat = false);
    void keyToView(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                   bool autoRepeat = false);
    void keyToWindow(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                     bool autoRepeat = false);
    // Plot pointer positions are plot-local automation content coordinates;
    // the rig only removes vertical scroll before constructing normalized
    // TimelinePointerInput values.
    void mousePress(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                    Qt::MouseButton button = Qt::LeftButton);
    [[nodiscard]] bool dispatchMousePress(const QPointF &position,
                                          Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                                          Qt::MouseButton button = Qt::LeftButton);
    void mouseMove(const QPointF &position, Qt::MouseButtons buttons = Qt::LeftButton,
                   Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseRelease(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                      Qt::MouseButton button = Qt::LeftButton);
    void mouseDoubleClick(const QPointF &position,
                          Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void gutterMousePress(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                          Qt::MouseButton button = Qt::LeftButton);
    [[nodiscard]] bool dispatchGutterMousePress(const QPointF &position,
                                                Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                                                Qt::MouseButton button = Qt::LeftButton);
    void gutterMouseMove(const QPointF &position, Qt::MouseButtons buttons = Qt::NoButton,
                         Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void gutterMouseRelease(const QPointF &position,
                            Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                            Qt::MouseButton button = Qt::LeftButton);
    void voiceMousePress(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    [[nodiscard]] bool dispatchVoiceMousePress(const QPointF &position,
                                               Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void voiceMouseMove(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void voiceMouseRelease(const QPointF &position,
                           Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void keyToVoiceArea(QEvent::Type type, int key,
                        Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void pump();

    const Lane pan{{EditorAutomationRowKind::ControlChange, 0, 10}, 0, 10};
    const Lane lfo{{EditorAutomationRowKind::ControlChange, 0, 21}, 0, 21};
    const Lane volume{{EditorAutomationRowKind::ControlChange, 0, 7}, 0, 7};
    static constexpr LaneHandle kTempoHandle{0};

  private:
    AutomationGestureCheckRig() = default;
    bool initialize(QString &error);
    void refreshPage();

    // Event-loop spin used by commitTimers(); not part of the public seam.
    void waitForTimers(int milliseconds);

    DrawerPageLiveState m_live;
    std::unique_ptr<checks::LoadedSong> m_song;
    std::unique_ptr<LoadedVoiceGroup> m_voicegroup;
    std::unique_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
    AutomationPage *m_page = nullptr;
    std::unique_ptr<AutomationInputHost> m_inputHost;
    // Production plot wiring stolen for the in-memory check host and restored
    // at teardown. The physical gutter remains wired and handles gutter input.
    songview::TimelineInputItem *m_automationPlotInput = nullptr;
    songview::TimelineBandInteraction *m_productionInteraction = nullptr;
    songview::TimelineInputItem *m_automationGutterInput = nullptr;
    songview::TimelineInputItem *m_voiceInput = nullptr;
    songview::TimelineQuickScene *m_quickScene = nullptr;
};
