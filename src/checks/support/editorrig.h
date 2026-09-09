#pragma once

#include <QPointer>
#include <cstdint>
#include <memory>
#include <vector>

#include <QSize>
#include <QString>

#include "ui/editordrawer/editordrawer.h"

extern "C" {
#include "voicegroup_loader.h"
}

class MidiTimeline;
class QQmlEngine;
class QQuickItem;
class QQuickView;
class QQuickWindow;
class SongDocument;
class SongView;

namespace songview {
class TimelineInputItem;
class TimelineQuickScene;
} // namespace songview

namespace checks {

// EditorRig is the one canonical document-driven assembly for checks: it
// builds the timeline, hosts the real Quick window through QuickSceneHost
// so SongView's windowless canvas renders into it, wires the SongView in
// production order (SongTab does setDocument then setSong), applies the
// drawer/zoom/cursor setup that each check used to hand-roll, and resolves
// the Quick scene, root, and input items once so checks never fish the
// object tree. The document and voicegroup are borrowed and must outlive
// the rig; members destroy the host and the view before the borrowed state.
struct EditorRigSection {
    EditorDrawerPage page;
    int height = 0;
};

struct EditorRigConfig {
    QSize viewSize = QSize(1000, 640); // Quick window (canonical viewport) size
    double sampleRate = 48000.0;
    LoadedVoiceGroup *voicegroup = nullptr;
    int track = -1; // -1 keeps the view's default track selection
    EditorDrawerPage activePage = EditorDrawerPage::Automations;
    std::vector<EditorRigSection> sections;
    double timeZoom = 0.0; // 0 keeps the view's default zoom
    bool applyEditCursor = false;
    uint64_t editCursorTick = 0;
    bool show = true;        // exposes the Quick window
    bool attachScene = true; // false leaves the canvas unattached for a custom viewport
};

// Hosts one real Quick window plus a child page viewport, matching production.
// The canvas detaches before its borrowed view, engine, or window dies.
class QuickSceneHost final
{
  public:
    QuickSceneHost(SongView &view, const QSize &size, bool attachScene = true);
    ~QuickSceneHost();

    QuickSceneHost(const QuickSceneHost &) = delete;
    QuickSceneHost &operator=(const QuickSceneHost &) = delete;

    QQuickWindow &window() noexcept;
    QQmlEngine &engine() noexcept;
    QQuickItem &viewport() noexcept;

  private:
    QPointer<SongView> m_view;
    std::unique_ptr<QQuickView> m_window;
    QQuickItem *m_viewport = nullptr;
};

class EditorRig final
{
  public:
    static std::unique_ptr<EditorRig> create(SongDocument &document, const EditorRigConfig &config,
                                             QString &error);
    ~EditorRig();

    EditorRig(const EditorRig &) = delete;
    EditorRig &operator=(const EditorRig &) = delete;

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    QuickSceneHost &host() noexcept;
    const QuickSceneHost &host() const noexcept;
    const MidiTimeline &timeline() const noexcept;
    LoadedVoiceGroup *voicegroup() const noexcept;
    // The Quick voice-changes input item, resolved once during create().
    // Unavailable when created with attachScene=false until the caller
    // attaches (no input items exist before then); do not call before that.
    songview::TimelineInputItem &voiceInput() noexcept;
    // The Quick scene backing the timeline canvas, resolved once during create().
    songview::TimelineQuickScene *quickScene() noexcept;
    // The QML root of the timeline canvas, resolved once during create().
    // Null when created with attachScene=false until the caller attaches.
    QQuickItem *quickRoot() noexcept;

  private:
    explicit EditorRig(SongDocument &document);
    songview::TimelineInputItem *inputItem(const QString &objectName) const;

    SongDocument &m_document;
    LoadedVoiceGroup *m_voicegroup = nullptr;
    std::unique_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
    std::unique_ptr<QuickSceneHost> m_host;
    QQuickItem *m_quickRoot = nullptr;
    songview::TimelineQuickScene *m_quickScene = nullptr;
    songview::TimelineInputItem *m_voiceInput = nullptr;
};

} // namespace checks
