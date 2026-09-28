#pragma once

#include "drawer_content.h"
#include "roll_projection.h"

#include <vector>

namespace DrawerScene {

void append(const DrawerContent::Content &content, const RollProjection::Camera &camera,
            double width, double height, int layer, std::vector<RollProjection::Rect> &out);

}
