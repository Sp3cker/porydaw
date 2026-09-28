#pragma once

#include "roll_content.h"

#include <cmath>
#include <vector>

namespace DrawerContent {

struct Rect {
    uint32_t tickStart = 0;
    uint32_t tickEnd = 0;
    float y = 0;
    float h = 0;
    uint32_t argb = 0;
    uint8_t flags = 0;
};

struct Anchored {
    uint32_t tick = 0;
    float dx = 0;
    float width = 0;
    float y = 0;
    float h = 0;
    uint32_t argb = 0;
    uint8_t flags = 0;
};

struct Section {
    uint16_t kind = 0;
    std::vector<Rect> rects;
    std::vector<Anchored> anchored;
};

struct Content {
    RollContent::Content common;
    std::vector<Section> sections;
    double dashDevicePx = 0;
    double gapDevicePx = 0;
    bool hasDashPattern = false;
};

inline bool decode(const QByteArray &blob, Content &out)
{
    out = Content{};
    if (blob.isEmpty())
        return true;
    RollContent::Reader r(blob.constData(), size_t(blob.size()));
    if (r.u32() != RollContent::blobMagic || r.u16() != RollContent::blobVersion)
        return false;
    const uint16_t count = r.u16();
    bool hasDashedFrame = false;
    for (uint16_t i = 0; i < count; ++i) {
        const uint16_t kind = r.u16();
        const uint32_t length = r.u32();
        RollContent::Reader s = r.section(length);
        if (r.fail())
            return false;
        if (kind == 11 || kind == 12 || kind == 13) {
            if (kind == 13) {
                if (length != 0)
                    return false;
                Section separator;
                separator.kind = 13;
                out.sections.push_back(std::move(separator));
                continue;
            }
            Section section;
            section.kind = kind;
            const uint32_t records = s.u32();
            const size_t stride = kind == 11 ? 21 : 25;
            if (s.fail() || records > s.remaining() / stride)
                return false;
            if (kind == 11) {
                section.rects.reserve(records);
                for (uint32_t j = 0; j < records; ++j) {
                    Rect rect;
                    rect.tickStart = s.u32();
                    rect.tickEnd = s.u32();
                    rect.y = s.f32();
                    rect.h = s.f32();
                    rect.argb = s.u32();
                    rect.flags = s.u8();
                    if (!std::isfinite(rect.y) || !std::isfinite(rect.h))
                        return false;
                    hasDashedFrame |= (rect.flags & 4) != 0;
                    section.rects.push_back(rect);
                }
            } else {
                section.anchored.reserve(records);
                for (uint32_t j = 0; j < records; ++j) {
                    Anchored rect;
                    rect.tick = s.u32();
                    rect.dx = s.f32();
                    rect.width = s.f32();
                    rect.y = s.f32();
                    rect.h = s.f32();
                    rect.argb = s.u32();
                    rect.flags = s.u8();
                    if (!std::isfinite(rect.dx) || !std::isfinite(rect.width)
                        || !std::isfinite(rect.y) || !std::isfinite(rect.h))
                        return false;
                    section.anchored.push_back(rect);
                }
            }
            out.sections.push_back(std::move(section));
        } else if (kind == 14) {
            if (length != 16 || out.hasDashPattern)
                return false;
            out.dashDevicePx = s.f64();
            out.gapDevicePx = s.f64();
            if (!std::isfinite(out.dashDevicePx) || !std::isfinite(out.gapDevicePx)
                || out.dashDevicePx <= 0 || out.gapDevicePx < 0)
                return false;
            out.hasDashPattern = true;
        } else if (!RollContent::decodeSection(kind, s, out.common)) {
            return false;
        }
        if (s.fail() || ((kind == 11 || kind == 12 || kind == 14
                          || kind <= RollContent::sectionModes) && s.remaining() != 0))
            return false;
    }
    return !r.fail() && r.remaining() == 0 && (!hasDashedFrame || out.hasDashPattern)
        && (!out.common.hasMetrics || out.common.palette.size() >= rollPaletteSlotCount);
}

}
