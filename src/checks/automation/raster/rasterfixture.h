#pragma once

#include <cstdint>
#include <memory>

#include <QImage>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QString>

#include "checks/support/songfixture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editorviewstate.h"

extern "C" {
#include "voicegroup_loader.h"
}

class AutomationCanvas;
class AutomationPage;
class MidiTimeline;
class SongView;

namespace songview {
class TimelineBandInteraction;
class TimelineInputItem;
class TimelineQuickScene;
} // namespace songview

class RasterAutomationInputHost;

class AutomationRasterFixture final
{
  public:
    struct Lane {
        EditorAutomationRowId row;
        int track = 0;
        uint8_t controller = 0;
    };

    static std::unique_ptr<AutomationRasterFixture> create(const QString &project,
                                                           const QString &song, QString &error);
    ~AutomationRasterFixture();

    AutomationRasterFixture(const AutomationRasterFixture &) = delete;
    AutomationRasterFixture &operator=(const AutomationRasterFixture &) = delete;

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    const SongView &view() const noexcept;
    void configurePainting();
    void configureInteraction();
    void shutdown();

    void setAutomationDpr(qreal dpr) noexcept;
    qreal nativeAutomationDpr() const noexcept;

    AutomationPage &page() noexcept;
    const AutomationPage &page() const noexcept;
    AutomationCanvas &canvas() noexcept;
    const AutomationCanvas &canvas() const noexcept;
    songview::TimelineInputItem &automationGutterInput() noexcept;
    songview::TimelineInputItem &voiceInput() noexcept;
    const songview::TimelineInputItem &voiceInput() const noexcept;
    const songview::TimelineQuickScene &quickScene() const noexcept;

    AutomationGeometry geometry() const;
    AutomationProjection projection() const;
    LaneHandle handleFor(const Lane &lane) const noexcept;
    QRect bodyFor(LaneHandle handle) const;
    qreal automationDpr() const noexcept;
    QPointF automationContentToViewport(const QPointF &position) const;

    bool expandTempo();
    QPointF tempoHeaderPoint() const;
    void setAutomationZoom(double zoom);
    void setAutomationScroll(double scroll);
    void setPersistentPencil(bool enabled);
    void documentChanged();

    void automationMouseMove(const QPointF &position);
    void automationPointerLeave();
    void voiceMousePress(const QPointF &position);
    void voiceMouseMove(const QPointF &position);
    void voiceMouseRelease(const QPointF &position);
    void pump();

    QImage renderAutomationViewport(QString *error = nullptr);
    QImage renderVoiceChanges(QString *error = nullptr);

    const Lane pan{{EditorAutomationRowKind::ControlChange, 0, 10}, 0, 10};
    static constexpr LaneHandle kTempoHandle{0};

  private:
    AutomationRasterFixture() = default;

    bool initialize(QString &error);
    void refreshPage();
    void waitForTimers(int milliseconds);

    DrawerPageLiveState m_live;
    std::unique_ptr<checks::LoadedSong> m_song;
    std::unique_ptr<LoadedVoiceGroup> m_voicegroup;
    std::unique_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
    AutomationPage *m_page = nullptr;
    std::unique_ptr<RasterAutomationInputHost> m_inputHost;
    songview::TimelineInputItem *m_automationPlotInput = nullptr;
    songview::TimelineBandInteraction *m_productionInteraction = nullptr;
    songview::TimelineInputItem *m_automationGutterInput = nullptr;
    songview::TimelineInputItem *m_voiceInput = nullptr;
    songview::TimelineQuickScene *m_quickScene = nullptr;
    bool m_shutdown = false;
};
