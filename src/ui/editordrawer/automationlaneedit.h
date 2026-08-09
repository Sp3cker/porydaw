#pragma once

#include <cstdint>
#include <vector>

#include "core/songdocument.h"

class AutomationLaneEdit
{
  public:
    using Point = SongDocument::LanePointValue;

    struct Target {
        int engineTrack = -1;
        uint8_t controller = 0;
        uint64_t expectedRevision = 0;
    };

    struct Completion {
        Target target;
        uint64_t tickBegin = 0;
        uint64_t tickEnd = 0;
        std::vector<Point> points;
        bool unchanged = false;
    };

    AutomationLaneEdit(Target target, std::vector<Point> originalPoints);

    Completion replacePointRange(uint64_t tickBegin, uint64_t tickEnd,
                                 std::vector<Point> points) const;
    Completion replaceHeldSpan(uint64_t tickBegin, uint64_t tickEnd, uint64_t songEndTick,
                               int minimumValue, int maximumValue, std::vector<Point> points) const;

  private:
    Target m_target;
    std::vector<Point> m_originalPoints;
    std::vector<Point> m_heldOriginalPoints;
};
