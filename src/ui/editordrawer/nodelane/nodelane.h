#pragma once

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <vector>

#include <QRect>
#include <QRectF>
#include <QString>

struct NodePoint {
    uint64_t tick = 0;
    int value = 0;
};

struct NodePointMove {
    uint64_t fromTick = 0; // identifies the point (one per tick per lane)
    NodePoint to;          // destination tick + value
};

struct LaneHandle {
    int index = -1;
    constexpr bool valid() const noexcept { return index >= 0; }
    constexpr bool operator==(const LaneHandle &) const noexcept = default;
};

// The automation node nearest the plot origin while still covered by the lane
// labels. The point keeps its source tick; callers present it at the origin.
struct OriginPhantom {
    LaneHandle lane;
    NodePoint point;
    int minimumValue = 0;
    int maximumValue = 127;
};

// Returns the rightmost node strictly left of `plotOriginX` in display space.
template <class DisplayX>
std::optional<OriginPhantom> originPhantomAt(std::span<const NodePoint> points, LaneHandle handle,
                                             int minimumValue, int maximumValue, double plotOriginX,
                                             DisplayX &&displayX)
{
    const auto firstVisible = std::lower_bound(
        points.begin(), points.end(), plotOriginX,
        [&displayX](const NodePoint &point, double x) { return displayX(point.tick) < x; });
    if (firstVisible == points.begin())
        return std::nullopt;
    return OriginPhantom{handle, *std::prev(firstVisible), minimumValue, maximumValue};
}

class QWidget;
struct AutomationGeometry;
class NodeLane
{
  public:
    virtual ~NodeLane();

    virtual QString title() const = 0;
    virtual std::vector<NodePoint> points() const = 0;
    virtual int minimumValue() const = 0;
    virtual int maximumValue() const = 0;
    virtual QString valueText(int value) const = 0;
    virtual bool promptValue(QWidget *parent, int currentValue, int *storedValue) const = 0;
    virtual int neutralValue() const { return -1; }
    // Implicit held tick-zero value outside points(); nullopt means no such
    // value. Tempo retains its 120-BPM default until an explicit tick-zero
    // point supersedes it.
    virtual std::optional<NodePoint> leadIn() const { return std::nullopt; }

    virtual void replaceSpan(uint64_t first, uint64_t last,
                             const std::vector<NodePoint> &points) = 0;
};

namespace nodelane {

qreal valueY(const NodeLane &lane, const QRect &body, const AutomationGeometry &geometry,
             int value);
QRectF nodeOverflowClip(const QRect &plot, const AutomationGeometry &geometry);

} // namespace nodelane

class NodeLaneEdit
{
  public:
    using Point = NodePoint;

    struct Target {
        LaneHandle lane;
        uint64_t expectedRevision = 0;
    };

    struct Completion {
        Target target;
        uint64_t tickBegin = 0;
        uint64_t tickEnd = 0;
        std::vector<Point> points;
        bool unchanged = false;
    };

    NodeLaneEdit(Target target, std::vector<Point> originalPoints);

    Completion replacePointRange(uint64_t tickBegin, uint64_t tickEnd,
                                 std::vector<Point> points) const;
    Completion replaceHeldSpan(uint64_t tickBegin, uint64_t tickEnd, uint64_t songEndTick,
                               int minimumValue, int maximumValue, std::vector<Point> points) const;

  private:
    Target m_target;
    std::vector<Point> m_originalPoints;
    std::vector<Point> m_heldOriginalPoints;
};
