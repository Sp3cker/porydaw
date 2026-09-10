#pragma once

#include <QPoint>
#include <QPointer>
#include <QString>

#include <cstdint>
#include <optional>
#include <span>

class AutomationCanvas;
class AutomationPage;
class SongView;
namespace songview {
class TimelineInputItem;
}

namespace selectionkey {

struct AutomationProbePoint {
    uint64_t tick = 0;
    int value = 0;
};

// Locates a logical CC lane and maps its full-height plot coordinates without
// changing the active parameter or selection. Pointer-delivery staging must
// explicitly activate the parameter before using those coordinates.
class AutomationProbe final
{
  public:
    static std::optional<AutomationProbe> locate(SongView &view, songview::TimelineInputItem *input,
                                                 int track, uint8_t controller,
                                                 QString *diagnostics = nullptr);

    bool activateParameter(QString *diagnostics = nullptr) const;

    bool project(std::span<const AutomationProbePoint> points, std::span<QPoint> projected,
                 QString *diagnostics = nullptr) const;
    bool emptyNodePoint(int value, QPoint &point, QString *diagnostics = nullptr) const;

  private:
    AutomationProbe(SongView &view, AutomationPage &page, AutomationCanvas &canvas,
                    songview::TimelineInputItem &input, int track, uint8_t controller) noexcept;

    QPointer<SongView> m_view;
    QPointer<AutomationPage> m_page;
    QPointer<AutomationCanvas> m_canvas;
    QPointer<songview::TimelineInputItem> m_input;
    int m_track;
    uint8_t m_controller;
};

} // namespace selectionkey
