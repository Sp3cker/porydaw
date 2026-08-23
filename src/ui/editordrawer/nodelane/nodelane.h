#pragma once

#include <cstdint>
#include <optional>
#include <vector>

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

class QWidget;
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
    // Implicit pre-roll value at song start; nullopt means none. Tempo draws
    // a 120-BPM lead-in when its first point starts after tick 0.
    virtual std::optional<NodePoint> leadIn() const { return std::nullopt; }

    virtual void replaceSpan(uint64_t first, uint64_t last,
                             const std::vector<NodePoint> &points) = 0;
};

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
