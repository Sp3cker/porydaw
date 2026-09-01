#include "ui/editordrawer/nodelane/nodelane.h"

#include <algorithm>
#include <limits>
#include <optional>
#include <utility>

NodeLane::~NodeLane() = default;

namespace {

using Point = NodeLaneEdit::Point;
void canonicalize(std::vector<Point> &points, uint64_t tickBegin, uint64_t tickEnd,
                  int minimumValue, int maximumValue,
                  NodeLaneEdit::LeadingPointPolicy leadingPointPolicy,
                  std::optional<int> priorValue = std::nullopt)
{
    std::stable_sort(points.begin(), points.end(),
                     [](const Point &left, const Point &right) { return left.tick < right.tick; });
    auto kept = std::size_t{0};
    for (auto index = std::size_t{0}; index < points.size();) {
        auto point = points[index++];
        while (index < points.size() && points[index].tick == point.tick)
            point = points[index++];
        if (point.tick < tickBegin || point.tick > tickEnd)
            continue;
        point.value = std::clamp(point.value, minimumValue, maximumValue);
        if (priorValue && *priorValue == point.value &&
            (leadingPointPolicy != NodeLaneEdit::LeadingPointPolicy::Preserve ||
             point.tick != tickBegin))
            continue;
        points[kept++] = point;
        priorValue = point.value;
    }
    points.resize(kept);
}

std::optional<int> heldValue(const std::vector<Point> &points, uint64_t tick, bool inclusive)
{
    auto position =
        std::lower_bound(points.cbegin(), points.cend(), tick,
                         [](const Point &point, uint64_t value) { return point.tick < value; });
    if (inclusive && position != points.cend() && position->tick == tick)
        ++position;
    return position == points.cbegin() ? std::nullopt : std::optional<int>((position - 1)->value);
}

bool rangeMatches(const std::vector<Point> &original, uint64_t tickBegin, uint64_t tickEnd,
                  const std::vector<Point> &replacement)
{
    const auto first =
        std::lower_bound(original.cbegin(), original.cend(), tickBegin,
                         [](const Point &point, uint64_t tick) { return point.tick < tick; });
    const auto last =
        std::upper_bound(first, original.cend(), tickEnd,
                         [](uint64_t tick, const Point &point) { return tick < point.tick; });
    return std::equal(first, last, replacement.cbegin(), replacement.cend(),
                      [](const Point &left, const Point &right) {
                          return left.tick == right.tick && left.value == right.value;
                      });
}

} // namespace

NodeLaneEdit::NodeLaneEdit(Target target, std::vector<Point> originalPoints)
    : m_target(target)
    , m_heldOriginalPoints(std::move(originalPoints))
{
    canonicalize(m_heldOriginalPoints, 0, std::numeric_limits<uint64_t>::max(),
                 std::numeric_limits<int>::min(), std::numeric_limits<int>::max(),
                 LeadingPointPolicy::Reduce);
}

NodeLaneEdit::Completion NodeLaneEdit::replaceHeldSpan(uint64_t tickBegin, uint64_t tickEnd,
                                                       uint64_t songEndTick, int minimumValue,
                                                       int maximumValue, std::vector<Point> points,
                                                       LeadingPointPolicy leadingPointPolicy) const
{
    if (tickEnd < songEndTick)
        if (const auto endpointValue = heldValue(m_heldOriginalPoints, tickEnd, true))
            points.push_back({tickEnd, *endpointValue});
    canonicalize(points, tickBegin, tickEnd, minimumValue, maximumValue, leadingPointPolicy,
                 heldValue(m_heldOriginalPoints, tickBegin, false));
    const bool unchanged = rangeMatches(m_heldOriginalPoints, tickBegin, tickEnd, points);
    return {m_target, tickBegin, tickEnd, std::move(points), unchanged};
}
