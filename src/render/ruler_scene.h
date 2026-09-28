#pragma once

#include "roll_labels.h"

#include <array>
#include <vector>

struct SGFontMetrics;

namespace RulerScene {

struct Frame {
    const RollContent::Content &content;
    const RollProjection::Camera &camera;
    double width;
    double height;
    std::array<SGFontMetrics *, 4> fonts;
};

struct Markers {
    std::array<RollProjection::Rect, 2> lines{};
    std::array<bool, 2> visible{};
};

void append(const Frame &frame, std::vector<RollProjection::Rect> &rects,
            std::vector<RollRender::Label> &labels, Markers &markers);

}
