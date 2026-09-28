#include "roll_scene.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace RollScene {

namespace {

void emitClipped(std::vector<Rect> &out, const Rect &r, double width, double height)
{
    const double x0 = std::max(r.x, 0.0);
    const double y0 = std::max(r.y, 0.0);
    const double x1 = std::min(r.x + r.w, width);
    const double y1 = std::min(r.y + r.h, height);
    if (x1 <= x0 || y1 <= y0)
        return;
    out.push_back(Rect{x0, y0, x1 - x0, y1 - y0, r.argb});
}

double gridHeight(const Frame &f)
{
    return f.camera.totalHeight(int(f.content.rows.size()));
}

double gridStroke(const Frame &f)
{
    return f.content.metrics.gridLineStrokeBase * f.camera.pixel();
}

void addFrame(const Frame &f, std::vector<Rect> &out, const Rect &box, uint32_t argb,
              int thicknessPixels, int insetPixels)
{
    const double pixel = f.camera.pixel();
    const double inset = double(insetPixels) * pixel;
    const double t = double(thicknessPixels) * pixel;
    const double fx = box.x + inset;
    const double fy = box.y + inset;
    const double fw = box.w - 2 * inset;
    const double fh = box.h - 2 * inset;
    if (!(fw > 0 && fh > 0))
        return;
    const double side = std::max(0.0, fh - 2 * t);
    out.push_back(Rect{fx, fy, fw, t, argb});
    out.push_back(Rect{fx, fy + fh - t, fw, t, argb});
    out.push_back(Rect{fx, fy + t, t, side, argb});
    out.push_back(Rect{fx + fw - t, fy + t, t, side, argb});
}

void addNoteBorder(const Frame &f, std::vector<Rect> &out, const Rect &box, int insetPixels)
{
    const RollProjection::Camera &cam = f.camera;
    const int fitted = RollProjection::fittedFrameThickness(box.w, box.h, cam.dpr,
                                                            cam.noteBorderPixels(), insetPixels);
    uint32_t argb = f.content.color(RollPaletteSlot::NoteBorder);
    if (fitted == 0) {
        const double alpha =
            std::min(0.85, std::max(0.25, std::min(box.w, box.h) / (3.0 * cam.pixel())));
        argb = uint32_t(std::round(alpha * 255)) << 24;
    }
    addFrame(f, out, box, argb, std::max(1, fitted), insetPixels);
}

void addSelectionRing(const Frame &f, std::vector<Rect> &out, const Rect &box)
{
    const RollProjection::Camera &cam = f.camera;
    const int ring = RollProjection::fittedFrameThickness(
        box.w, box.h, cam.dpr, cam.selectionRingPixels(f.content.metrics.selectionRingDip), 0);
    const uint32_t argb = f.content.color(RollPaletteSlot::SelectionRing);
    if (ring > 0) {
        addFrame(f, out, box, argb, ring, 0);
        addNoteBorder(f, out, box, ring);
    } else {
        out.push_back(Rect{box.x, box.y, box.w, box.h, argb});
    }
}

void addDashedFrame(const Frame &f, std::vector<Rect> &out, const Rect &box, const Rect &clip,
                    uint32_t argb)
{
    const double width = f.camera.pixel();
    const double dash = f.content.metrics.dashLen;
    const double period = dash + dash;
    auto addClipped = [&](double x, double y, double w, double h) {
        const double x0 = std::max(x, clip.x);
        const double y0 = std::max(y, clip.y);
        const double x1 = std::min(x + w, clip.x + clip.w);
        const double y1 = std::min(y + h, clip.y + clip.h);
        if (x1 > x0 && y1 > y0)
            out.push_back(Rect{x0, y0, x1 - x0, y1 - y0, argb});
    };
    auto horizontal = [&](double x0, double x1, double y) {
        if (!(y + width / 2 > clip.y && y - width / 2 < clip.y + clip.h))
            return;
        double x = x0 + std::max(0.0, std::floor((clip.x - x0) / period)) * period;
        const double end = std::min(x1, clip.x + clip.w);
        for (; x < end; x += period)
            addClipped(x, y - width / 2, std::min(x + dash, x1) - x, width);
    };
    auto vertical = [&](double x, double y0, double y1) {
        if (!(x + width / 2 > clip.x && x - width / 2 < clip.x + clip.w))
            return;
        double y = y0 + std::max(0.0, std::floor((clip.y - y0) / period)) * period;
        const double end = std::min(y1, clip.y + clip.h);
        for (; y < end; y += period)
            addClipped(x - width / 2, y, width, std::min(y + dash, y1) - y);
    };
    horizontal(box.x, box.x + box.w, box.y);
    horizontal(box.x, box.x + box.w, box.y + box.h);
    vertical(box.x, box.y, box.y + box.h);
    vertical(box.x + box.w, box.y, box.y + box.h);
}

Rect plotClip(const Frame &f)
{
    const double top = std::max(0.0, -f.camera.scrollOriginY());
    const double bottom = std::min(f.height, gridHeight(f) - f.camera.scrollOriginY());
    return Rect{0, top, f.width, std::max(0.0, bottom - top)};
}

} // namespace

void appendRows(const Frame &f, std::vector<Rect> &out)
{
    const RollContent::Content &c = f.content;
    const RollProjection::Camera &cam = f.camera;
    const double W = f.width;
    const double H = f.height;
    const double stroke = gridStroke(f);
    const int rowCount = int(c.rows.size());
    for (int row = 0; row < rowCount; ++row) {
        const RollContent::Row &r = c.rows[size_t(row)];
        const double top = cam.viewRowTop(row);
        const double bottom = cam.viewRowBottom(row);
        if (r.flags & RollContent::rowAccidentalLane)
            emitClipped(out,
                        Rect{0, top, W, bottom - top, c.color(RollPaletteSlot::AccidentalLane)},
                        W, H);
        if (r.flags & RollContent::rowScaleHighlight)
            emitClipped(out,
                        Rect{0, top, W, bottom - top, c.color(RollPaletteSlot::ScaleHighlight)},
                        W, H);
        emitClipped(out,
                    Rect{0, bottom - stroke / 2, W, stroke,
                         c.color(r.pitch % 12 == 0 ? RollPaletteSlot::KeyboardSeparator
                                                   : RollPaletteSlot::RowLine)},
                    W, H);
    }
}

void appendPreRollMask(const Frame &f, std::vector<Rect> &out)
{
    const double soY = f.camera.scrollOriginY();
    emitClipped(out,
                Rect{0, -soY, -f.camera.scrollOriginX(), gridHeight(f),
                     f.content.color(RollPaletteSlot::PreRollMask)},
                f.width, f.height);
}

void appendTimeGrid(const Frame &f, std::vector<Rect> &out)
{
    const RollContent::Content &c = f.content;
    const RollProjection::Camera &cam = f.camera;
    if (!c.hasTimeAxis || !(cam.pixelsPerTick > 0))
        return;
    const RollContent::Metrics &m = c.metrics;
    const RollContent::TimeAxis &axis = c.timeAxis;
    const double W = f.width;
    const double H = f.height;
    const double soX = cam.scrollOriginX();
    const double soY = cam.scrollOriginY();
    const double stroke = gridStroke(f);
    const double gridH = gridHeight(f);
    const double ppt = cam.pixelsPerTick;
    const double margin = stroke + cam.pixel();
    const double limit = double(RollContent::noTick);
    const uint64_t begin =
        uint64_t(std::min(limit, std::floor(std::max(0.0, soX - margin) / ppt)));
    const uint64_t end =
        uint64_t(std::min(limit, std::max(0.0, std::ceil((soX + W + margin) / ppt) + 1)));
    RollProjection::forEachSubdivision(
        axis, begin, end, ppt, m, stroke, [&](uint64_t tick, int level) {
            const RollPaletteSlot slot = level == 1   ? RollPaletteSlot::GridSub1
                                         : level == 2 ? RollPaletteSlot::GridSub2
                                                      : RollPaletteSlot::GridSub3;
            emitClipped(out,
                        Rect{cam.viewX(double(tick)) - stroke / 2, -soY, stroke, gridH,
                             c.color(slot)},
                        W, H);
        });
    const RollContent::GridSegment *lineSegment = nullptr;
    bool finest = false;
    RollProjection::forEachGridLine(
        axis, begin, end, [&](const RollContent::GridSegment &segment, uint64_t tick, bool isBar) {
            if (&segment != lineSegment) {
                lineSegment = &segment;
                finest = RollProjection::gridTicksAt(axis, segment, ppt, m) == 1;
            }
            const RollPaletteSlot slot = isBar    ? RollPaletteSlot::GridBar
                                         : finest ? RollPaletteSlot::GridBeatFine
                                                  : RollPaletteSlot::GridBeat;
            emitClipped(out,
                        Rect{cam.viewX(double(tick)) - stroke / 2, -soY, stroke, gridH,
                             c.color(slot)},
                        W, H);
        });
}

void appendNoteFills(const Frame &f, std::vector<uint32_t> &visible, std::vector<Rect> &out,
                     std::vector<PaintedNote> &painted)
{
    const RollContent::Content &c = f.content;
    const RollProjection::Camera &cam = f.camera;
    const double W = f.width;
    const double H = f.height;
    auto paint = [&](const RollContent::Note &note) {
        const int row = c.rowForPitch(note.pitch);
        if (row < 0)
            return;
        Rect box = RollProjection::noteBox(cam, row, double(note.tick),
                                           double(note.tick) + double(note.duration), c.metrics);
        if (!(box.w > 0 && box.h > 0) || box.x >= W || box.x + box.w <= 0 || box.y >= H
            || box.y + box.h <= 0)
            return;
        box.argb = note.fillArgb;
        out.push_back(box);
        painted.push_back(PaintedNote{box, note.id, note.pitch, note.velocity, note.flags});
    };
    const double ppt = cam.pixelsPerTick;
    if (!(ppt > 0)) {
        for (const RollContent::Note &note : c.notes)
            paint(note);
        return;
    }
    const double slack = 2 * cam.pixel();
    const double soX = cam.scrollOriginX();
    const double lo = (soX - c.metrics.noteMinWidth - slack) / ppt;
    const double hi = (soX + W + slack) / ppt;
    const auto first = c.notesByTick.begin();
    const auto last = c.notesByTick.end();
    const double from = lo - double(c.maxNoteDuration);
    auto it = std::partition_point(
        first, last, [&](uint32_t index) { return double(c.notes[index].tick) < from; });
    visible.clear();
    for (; it != last && double(c.notes[*it].tick) < hi; ++it) {
        const RollContent::Note &note = c.notes[*it];
        if (double(note.tick) + double(note.duration) >= lo)
            visible.push_back(*it);
    }
    std::sort(visible.begin(), visible.end());
    for (uint32_t index : visible)
        paint(c.notes[index]);
}

bool drawPreviewBox(const Frame &f, Rect &box)
{
    const RollContent::Content &c = f.content;
    if (!c.drawPreview.active)
        return false;
    const int row = c.rowForPitch(c.drawPreview.pitch);
    if (row < 0)
        return false;
    box = RollProjection::noteBox(f.camera, row, double(c.drawPreview.tick),
                                  double(c.drawPreview.tick) + double(c.drawPreview.duration),
                                  c.metrics);
    box.argb = c.color(RollPaletteSlot::DrawPreviewFill);
    return true;
}

void appendNoteFrames(const Frame &f, const std::vector<PaintedNote> &painted,
                      const Rect *preview, const BandSelection &band, std::vector<Rect> &out)
{
    const Rect &b = band.rect;
    for (const PaintedNote &note : painted) {
        const bool covered = note.flags & RollContent::noteTimeCovered;
        if (note.flags & RollContent::noteGhost) {
            if (covered)
                addSelectionRing(f, out, note.box);
            continue;
        }
        const bool swept = band.active && note.box.x < b.x + b.w && note.box.x + note.box.w > b.x
            && note.box.y < b.y + b.h && note.box.y + note.box.h > b.y;
        if ((note.flags & RollContent::noteSelected) || swept || covered)
            addSelectionRing(f, out, note.box);
        else
            addNoteBorder(f, out, note.box, 0);
    }
    if (preview)
        addNoteBorder(f, out, *preview, 0);
}

void appendBandSelection(const Frame &f, const BandSelection &band, std::vector<Rect> &out)
{
    if (!band.active)
        return;
    const double soY = f.camera.scrollOriginY();
    const Rect &b = band.rect;
    const double top = std::max(b.y, -soY);
    const double bottom = std::min(b.y + b.h, gridHeight(f) - soY);
    if (!(b.w > 0 && bottom > top))
        return;
    const Rect frame{b.x, top, b.w, bottom - top};
    const Rect clip = plotClip(f);
    const double x0 = std::max(frame.x, clip.x);
    const double y0 = std::max(frame.y, clip.y);
    const double x1 = std::min(frame.x + frame.w, clip.x + clip.w);
    const double y1 = std::min(frame.y + frame.h, clip.y + clip.h);
    if (!(x1 > x0 && y1 > y0))
        return;
    const RollContent::Content &c = f.content;
    out.push_back(Rect{x0, y0, x1 - x0, y1 - y0, c.color(RollPaletteSlot::SelectionFill)});
    addDashedFrame(f, out, frame, clip, c.color(RollPaletteSlot::SelectionFrame));
}

void appendTimeSelection(const Frame &f, std::vector<Rect> &out)
{
    const RollContent::Content &c = f.content;
    const RollContent::Overlay &o = c.overlay;
    if (!(o.active && o.selectedTrack < o.usedTrackCount && o.selectedTrack < o.scopeTracks.size()
          && o.scopeTracks[o.selectedTrack] != 0))
        return;
    const RollProjection::Camera &cam = f.camera;
    const double pixel = cam.pixel();
    const double soY = cam.scrollOriginY();
    const double gridH = gridHeight(f);
    const double x0 = cam.viewX(double(o.startTick));
    const double x1 = cam.viewX(double(o.endTick));
    const uint32_t edge = c.color(RollPaletteSlot::SelectionFrame);
    emitClipped(out, Rect{x0, -soY, x1 - x0, gridH, c.color(RollPaletteSlot::TimeSelectionFill)},
                f.width, f.height);
    emitClipped(out, Rect{x0 - pixel / 2, -soY, pixel, gridH, edge}, f.width, f.height);
    emitClipped(out, Rect{x1 - pixel / 2, -soY, pixel, gridH, edge}, f.width, f.height);
}

void appendLoop(const Frame &f, std::vector<Rect> &out)
{
    const RollContent::Content &c = f.content;
    const RollProjection::Camera &cam = f.camera;
    const double gridH = gridHeight(f);
    if (!c.hasTimeAxis || !(gridH > 0))
        return;
    const RollContent::TimeAxis &axis = c.timeAxis;
    const bool hasStart = axis.loopStartTick != RollContent::noTick;
    const bool hasEnd = axis.loopEndTick != RollContent::noTick;
    if (!hasStart && !hasEnd)
        return;
    const double W = f.width;
    const double soY = cam.scrollOriginY();
    const double pixel = cam.pixel();
    const double x0 = hasStart ? cam.viewX(double(axis.loopStartTick))
                               : -std::numeric_limits<double>::max();
    const double x1 = hasEnd ? cam.viewX(double(axis.loopEndTick))
                             : std::numeric_limits<double>::max();
    if (!(x1 > 0 && x0 < W))
        return;
    const double glowWidth = std::min(2 * c.metrics.baseFontPx, x1 - x0);
    const uint32_t ink = c.color(RollPaletteSlot::LoopGlow) & 0x00FFFFFFu;
    const double bandWidth = std::max(1.0, c.metrics.spaceHalf);
    auto appendGlow = [&](double left, bool fadesRight) {
        if (!(glowWidth > 0))
            return;
        const double right = std::min(left + glowWidth, W);
        for (int band = std::max(0, int(std::floor((0 - left) / bandWidth)));
             left + double(band) * bandWidth < right; ++band) {
            const double bandLeft = left + double(band) * bandWidth;
            const double bandRight = std::min(left + double(band + 1) * bandWidth, left + glowWidth);
            const double midpoint = (bandLeft + bandRight) / 2;
            const double fraction = fadesRight ? (midpoint - left) / glowWidth
                                               : (left + glowWidth - midpoint) / glowWidth;
            const double alpha = fraction <= 0.2 ? 150 + (18 - 150) * fraction / 0.2
                                                 : 18 * (1 - fraction) / 0.8;
            const double visibleLeft = std::max(0.0, bandLeft);
            const double visibleRight = std::min(W, bandRight);
            if (visibleRight > visibleLeft)
                emitClipped(out,
                            Rect{visibleLeft, -soY, visibleRight - visibleLeft, gridH,
                                 uint32_t(std::round(alpha)) << 24 | ink},
                            W, f.height);
        }
    };
    if (hasStart)
        appendGlow(x0, true);
    if (hasEnd)
        appendGlow(x1 - glowWidth, false);
    const uint32_t edge = c.color(RollPaletteSlot::LoopEdge);
    auto appendEdge = [&](double x) {
        emitClipped(out, Rect{x - pixel / 2, -soY, pixel, gridH, edge}, W, f.height);
    };
    if (hasStart)
        appendEdge(x0);
    if (hasEnd)
        appendEdge(x1);
}

void appendKeys(const Frame &f, int hoverPitch, std::vector<Rect> &under,
                std::vector<Rect> &over)
{
    const RollContent::Content &c = f.content;
    const RollProjection::Camera &cam = f.camera;
    const double W = f.width;
    const double H = f.height;
    const double soY = cam.scrollOriginY();
    const double pixel = cam.pixel();
    const double keyboardWidth = c.metrics.keyboardWidth;
    const int rowCount = int(c.rows.size());
    const double gridH = gridHeight(f);

    emitClipped(under,
                Rect{0, -soY, keyboardWidth, gridH, c.color(RollPaletteSlot::KeyboardWhite)}, W,
                H);
    for (int row = 0; row < rowCount; ++row) {
        const RollContent::Row &r = c.rows[size_t(row)];
        const double top = cam.viewRowTop(row);
        const double bottom = cam.viewRowBottom(row);
        if (r.flags & RollContent::rowAccidentalLane)
            emitClipped(under,
                        Rect{0, top, keyboardWidth, bottom - top,
                             c.color(RollPaletteSlot::KeyboardBlack)},
                        W, H);
        else if (r.pitch % 12 == 0 || r.pitch % 12 == 5)
            emitClipped(under,
                        Rect{0, bottom - pixel / 2, keyboardWidth, pixel,
                             c.color(RollPaletteSlot::KeyboardSeparator)},
                        W, H);
    }

    const bool typography = c.modes & RollContent::modeTypographyAvailable;
    const int hoverRow = typography ? c.rowForPitch(hoverPitch) : -1;
    if (hoverRow >= 0) {
        const double top = cam.viewRowTop(hoverRow);
        const double bottom = cam.viewRowBottom(hoverRow);
        emitClipped(over,
                    Rect{0, top, keyboardWidth, bottom - top,
                         c.color(RollPaletteSlot::KeyboardHighlight)},
                    W, H);
        if (!RollProjection::isBlackKey(hoverPitch) && (hoverPitch % 12 == 0 || hoverPitch % 12 == 5))
            emitClipped(over,
                        Rect{0, bottom - pixel / 2, keyboardWidth, pixel,
                             c.color(RollPaletteSlot::KeyboardSeparator)},
                        W, H);
    }
    emitClipped(over, Rect{-pixel / 2, -soY, pixel, gridH, c.color(RollPaletteSlot::Separator)},
                W, H);
}

} // namespace RollScene
