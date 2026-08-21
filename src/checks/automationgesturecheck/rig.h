#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QByteArray>
#include <QEvent>
#include <QPointF>
#include <QRect>

#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editorviewstate.h"

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
    QAction *pencilModeAction() const noexcept;

    AutomationGeometry geometry() const;
    AutomationProjection projection() const;
    int rowIndex(const Lane &lane) const noexcept;
    InputPoint pointAt(const Lane &lane, double tick, int value) const;
    QRect voiceBounds() const;
    QPointF tempoHeaderPoint() const;
    QPointF tempoBodyPoint(double tick, int bpm) const;
    QImage renderArea();
    Snapshot snapshot(int track, uint8_t controller) const;

    void documentChanged();
    void setAutomationZoom(double zoom);
    void setAutomationScroll(double scroll);
    void setPersistentPencil(bool enabled);
    void keyToArea(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                   bool autoRepeat = false);
    void keyToView(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                   bool autoRepeat = false);
    void keyToWindow(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                     bool autoRepeat = false);
    void mousePress(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                    Qt::MouseButton button = Qt::LeftButton);
    void mouseMove(const QPointF &position, Qt::MouseButtons buttons = Qt::LeftButton,
                   Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseRelease(const QPointF &position, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                      Qt::MouseButton button = Qt::LeftButton);
    void mouseDoubleClick(const QPointF &position,
                          Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void pump();
    void waitForTimers(int milliseconds);

    const Lane pan{{EditorAutomationRowKind::ControlChange, 0, 10}, 0, 10};
    const Lane lfo{{EditorAutomationRowKind::ControlChange, 0, 21}, 0, 21};
    const Lane volume{{EditorAutomationRowKind::ControlChange, 0, 7}, 0, 7};

  private:
    AutomationGestureCheckRig() = default;
    bool initialize(const SongInfo &song, QString &error);
    void refreshPage();

    static void sendKey(QObject *target, QEvent::Type type, int key,
                        Qt::KeyboardModifiers modifiers, bool autoRepeat);
    void sendMouse(QEvent::Type type, const QPointF &position, Qt::MouseButton button,
                   Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers);

    DrawerPageLiveState m_live;
    std::unique_ptr<SongDocument> m_document;
    std::unique_ptr<LoadedVoiceGroup> m_voicegroup;
    std::unique_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
    AutomationPage *m_page = nullptr;
};
