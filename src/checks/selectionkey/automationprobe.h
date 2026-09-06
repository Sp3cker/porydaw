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

// Maps only real, visible CC-lane coordinates. Locating the lane, applying a
// final camera state for an entire delivery set, and finding a node-free point
// belong together because each is a precondition for genuine pointer input.
class AutomationProbe final
{
  public:
    static std::optional<AutomationProbe> locate(SongView &view, songview::TimelineInputItem *input,
                                                 int track, uint8_t controller,
                                                 QString *diagnostics = nullptr);

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
