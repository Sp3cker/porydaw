#include "drawer_scene.h"

#include <algorithm>
#include <cmath>

namespace DrawerScene {
namespace {
using RollProjection::Rect;

double displayX(const RollProjection::Camera &cam, double tick)
{
    return std::round((tick * cam.pixelsPerTick - cam.scrollX) * cam.dpr) / cam.dpr;
}

void clipped(std::vector<Rect> &out, double x, double y, double w, double h, uint32_t argb,
             const RollProjection::Camera &cam, double width, double height)
{
    if (!(w > 0 && h > 0))
        return;
    const double left = std::floor(x * cam.dpr + 0.5) / cam.dpr;
    const double right = std::max(left + cam.pixel(),
                                  std::floor((x + w) * cam.dpr + 0.5) / cam.dpr);
    const double x0 = std::max(0.0, left);
    const double y0 = std::max(0.0, y);
    const double x1 = std::min(width, right);
    const double y1 = std::min(height, y + h);
    if (x1 > x0 && y1 > y0 && (argb >> 24))
        out.push_back(Rect{x0, y0, x1 - x0, y1 - y0, argb});
}

void grid(const RollContent::Content &c, const RollProjection::Camera &cam, double width,
          double height, std::vector<Rect> &out)
{
    if (!c.hasTimeAxis || !(cam.pixelsPerTick > 0))
        return;
    const double stroke = c.metrics.gridLineStrokeBase * cam.pixel();
    const double origin = cam.scrollOriginX();
    const double margin = stroke + cam.pixel();
    const double limit = double(RollContent::noTick);
    const uint64_t begin = uint64_t(std::min(limit,
        std::floor(std::max(0.0, origin - margin) / cam.pixelsPerTick)));
    const uint64_t end = uint64_t(std::min(limit,
        std::max(0.0, std::ceil((origin + width + margin) / cam.pixelsPerTick) + 1)));
    auto line = [&](uint64_t tick, RollPaletteSlot slot) {
        clipped(out, displayX(cam, double(tick)) - stroke / 2, 0, stroke, height,
                c.color(slot), cam, width, height);
    };
    RollProjection::forEachSubdivision(c.timeAxis, begin, end, cam.pixelsPerTick,
        c.metrics, stroke, [&](uint64_t tick, int level) {
            line(tick, level == 1 ? RollPaletteSlot::GridSub1
                       : level == 2 ? RollPaletteSlot::GridSub2 : RollPaletteSlot::GridSub3);
        });
    const RollContent::GridSegment *segmentPrevious = nullptr;
    bool finest = false;
    RollProjection::forEachGridLine(c.timeAxis, begin, end,
        [&](const RollContent::GridSegment &segment, uint64_t tick, bool bar) {
            if (&segment != segmentPrevious) {
                segmentPrevious = &segment;
                finest = RollProjection::gridTicksAt(c.timeAxis, segment, cam.pixelsPerTick,
                                                       c.metrics) == 1;
            }
            line(tick, bar ? RollPaletteSlot::GridBar
                          : finest ? RollPaletteSlot::GridBeatFine : RollPaletteSlot::GridBeat);
        });
}

void dashed(std::vector<Rect> &out, const Rect &box, const DrawerContent::Content &content,
            const RollProjection::Camera &cam, double width, double height)
{
    const double stroke = cam.pixel();
    const double dash = content.dashDevicePx * stroke;
    const double period = (content.dashDevicePx + content.gapDevicePx) * stroke;
    if (!(period > 0 && dash > 0))
        return;
    auto horizontal = [&](double y) {
        if (y + stroke <= 0 || y >= height)
            return;
        double x = box.x + std::max(0.0, std::floor(-box.x / period)) * period;
        const double end = std::min(width, box.x + box.w);
        for (; x < end; x += period)
            clipped(out, x, y, std::min(dash, box.x + box.w - x), stroke, box.argb,
                    cam, width, height);
    };
    auto vertical = [&](double x) {
        if (x + stroke <= 0 || x >= width)
            return;
        double y = box.y + std::max(0.0, std::floor(-box.y / period)) * period;
        const double end = std::min(height, box.y + box.h);
        for (; y < end; y += period)
            clipped(out, x, y, stroke, std::min(dash, box.y + box.h - y), box.argb,
                    cam, width, height);
    };
    horizontal(box.y);
    horizontal(box.y + box.h - stroke);
    vertical(box.x);
    vertical(box.x + box.w - stroke);
}
}

void append(const DrawerContent::Content &content, const RollProjection::Camera &cam,
            double width, double height, int layer, std::vector<Rect> &out)
{
    const auto &c = content.common;
    if (layer == 0)
        grid(c, cam, width, height, out);
    int currentLayer = 0;
    for (const auto &section : content.sections) {
        if (section.kind == 13) {
            ++currentLayer;
            continue;
        }
        if (currentLayer != layer)
            continue;
        if (section.kind == 11) {
            for (const auto &r : section.rects) {
                const bool pxSpace = r.flags & 1;
                const double origin = r.flags & 2 ? 0 : cam.scrollOriginX();
                const double x0 = pxSpace ? double(r.tickStart) - origin : displayX(cam, r.tickStart);
                const double x1 = pxSpace ? double(r.tickEnd) - origin : displayX(cam, r.tickEnd);
                const Rect box{x0, r.y, x1 - x0, r.h, r.argb};
                if (!(box.w > 0 && box.h > 0) || box.x >= width || box.x + box.w <= 0
                    || box.y >= height || box.y + box.h <= 0)
                    continue;
                if (r.flags & 4)
                    dashed(out, box, content, cam, width, height);
                else
                    clipped(out, box.x, box.y, box.w, box.h, box.argb, cam, width, height);
            }
        } else {
            for (const auto &r : section.anchored) {
                double x = cam.viewX(r.tick) + r.dx;
                if (r.flags & 1)
                    x = std::round(x * cam.dpr) / cam.dpr;
                clipped(out, x, r.y, r.width, r.h, r.argb, cam, width, height);
            }
        }
    }
}
}
