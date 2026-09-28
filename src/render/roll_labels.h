#pragma once

#include "roll_content.h"
#include "roll_projection.h"

#include <QtCore/qstring.h>

#include <utility>
#include <vector>

namespace RollRender {

struct Label {
    RollProjection::Rect rect;
    RollProjection::Rect background;
    bool hasBackground = false;
    QString text;
    QString family;
    int pixelSize = 0;
    int weight = 0;
    double letterSpacing = 0;
    int horizontalAlignment = 0;
    uint32_t color = 0;
};

inline Label *appendLabel(const RollContent::Content &content, std::vector<Label> &labels,
                          const RollProjection::Rect &rect, QString text, uint8_t fontId,
                          int pixelSize, int horizontalAlignment, uint32_t argb)
{
    const RollContent::FontSpec *spec = content.font(fontId);
    if (!spec)
        return nullptr;
    Label &label = labels.emplace_back();
    label.rect = rect;
    label.text = std::move(text);
    label.family = spec->family;
    label.pixelSize = pixelSize > 0 ? pixelSize : spec->pixelSize;
    label.weight = spec->weight;
    label.letterSpacing = spec->letterSpacing;
    label.horizontalAlignment = horizontalAlignment;
    label.color = argb;
    return &label;
}

}
