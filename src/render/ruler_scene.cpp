#include "ruler_scene.h"

#include "roll_projection.h"
#include "ui/songview/quick/swiftroll/native/font_metrics.h"

#include <algorithm>
#include <cmath>

namespace RulerScene {

namespace {

using RollProjection::Rect;

void appendVisible(std::vector<Rect> &rects, const Frame &frame, Rect rect)
{
    const double x0 = std::max(0.0, rect.x);
    const double y0 = std::max(0.0, rect.y);
    const double x1 = std::min(frame.width, rect.x + rect.w);
    const double y1 = std::min(frame.height, rect.y + rect.h);
    if (x1 > x0 && y1 > y0)
        rects.push_back(Rect{x0, y0, x1 - x0, y1 - y0, rect.argb});
}

uint64_t visibleTick(double x, double pixelsPerTick, bool upper)
{
    const double tick = std::max(0.0, upper ? std::ceil(x / pixelsPerTick) + 1
                                                 : std::floor(x / pixelsPerTick));
    return uint64_t(std::min(double(RollContent::noTick), tick));
}

QString number(uint64_t value)
{
    return QString::number(qulonglong(value));
}

}

void append(const Frame &f, std::vector<Rect> &rects, std::vector<RollRender::Label> &labels,
            Markers &markers)
{
    const auto &c = f.content;
    const auto &m = c.metrics;
    const auto &cam = f.camera;
    const double soX = cam.scrollOriginX();
    appendVisible(rects, f, Rect{0, 0, f.width, f.height,
                                 c.color(RollPaletteSlot::ChromeBackground)});
    appendVisible(rects, f, Rect{0, f.height - 0.5, f.width, 1,
                                 c.color(RollPaletteSlot::Separator)});
    if (!(c.modes & RollContent::modeTypographyAvailable) || !c.hasTimeAxis
        || !(cam.pixelsPerTick > 0) || !f.fonts[0] || !f.fonts[1] || !f.fonts[2]
        || !f.fonts[3])
        return;

    const auto &axis = c.timeAxis;
    const double rulerAscent = sgf_extents(f.fonts[0]).ascent;
    const double rulerHeight = sgf_extents(f.fonts[0]).height;
    const double beatAscent = sgf_extents(f.fonts[1]).ascent;
    const double beatHeight = sgf_extents(f.fonts[1]).height;
    const double boldHeight = sgf_extents(f.fonts[2]).height;
    const double markerHeight = boldHeight + 1;
    const double tickBottom = f.height - 1;
    const double tickCenter = (markerHeight + tickBottom) / 2;
    const double barCap = m.spaceHalf;
    const double labelGap = 1;
    const uint32_t ink = c.color(RollPaletteSlot::RulerTick);
    const uint64_t visibleEnd = visibleTick(soX + f.width, cam.pixelsPerTick, true);
    const uint64_t lastTick = std::min(visibleEnd, RollContent::maxTick);
    const auto &endSegment = RollProjection::segmentAt(axis, lastTick);
    const uint64_t alignedEnd = endSegment.start
        + (lastTick - endSegment.start) / endSegment.beatTicks * endSegment.beatTicks;
    uint64_t maxBar = 1;
    RollProjection::forEachNumberedGridLine(
        axis, alignedEnd, lastTick + 1,
        [&](const auto &, uint64_t, bool, uint64_t bar, uint64_t) { maxBar = bar; });
    ++maxBar;

    const QString maxBeat = number(maxBar) + QLatin1Char('.') + number(255);
    const double maxBeatWidth = sgf_advance(f.fonts[1], maxBeat.toUtf8().constData());
    const double maxSignatureWidth = sgf_advance(f.fonts[3], "255/64");
    const double margin = std::max(maxBeatWidth, maxSignatureWidth)
        + 2 * m.spaceHalf + m.spaceTwo;
    const uint64_t begin = visibleTick(soX - margin, cam.pixelsPerTick, false);
    const uint64_t end = visibleEnd;
    appendVisible(rects, f, Rect{0, 0, std::max(0.0, -soX), f.height,
                                 c.color(RollPaletteSlot::RulerPreRollMask)});
    RollProjection::forEachSubdivision(
        axis, begin, end, cam.pixelsPerTick, m, m.gridLineStrokeBase * cam.pixel(),
        [&](uint64_t tick, int level) {
            const double h = level == 1 ? m.spaceHalf : 1.0;
            const double x = cam.viewX(double(tick));
            appendVisible(rects, f, Rect{x - 0.5, tickBottom - h + 1, 1, h, ink});
        });

    const RollContent::GridSegment *current = nullptr;
    bool drawBeatTicks = false;
    bool showBeatLabels = false;
    double lastLabelRight = cam.contentTickX(double(begin)) - soX - labelGap;
    RollProjection::forEachNumberedGridLine(
        axis, begin, end,
        [&](const RollContent::GridSegment &segment, uint64_t tick, bool isBar,
            uint64_t bar, uint64_t beat) {
            if (&segment != current) {
                current = &segment;
                const double beatWidth = double(segment.beatTicks) * cam.pixelsPerTick;
                const QString reserve = number(maxBar) + QLatin1Char('.')
                    + number(segment.beatsPerBar);
                const double beatAdvance = sgf_advance(f.fonts[1], reserve.toUtf8().constData());
                drawBeatTicks = beatWidth >= m.detailMinPxPerBeat;
                showBeatLabels = beatWidth >= m.rulerBeatLabelZoomFactor
                    * (barCap + 2 * labelGap + m.spaceTwo + beatAdvance);
            }
            const double x = cam.viewX(double(tick));
            const double beatTop = tickCenter - m.spaceHalf;
            if (!isBar && !showBeatLabels) {
                if (drawBeatTicks)
                    appendVisible(rects, f, Rect{x - 0.5, beatTop, 1,
                                                 tickBottom - beatTop, ink});
                return;
            }
            const double labelX = x + barCap;
            if (labelX < lastLabelRight + labelGap) {
                if (!isBar && drawBeatTicks)
                    appendVisible(rects, f, Rect{x - 0.5, beatTop, 1,
                                                 tickBottom - beatTop, ink});
                return;
            }
            const QString text = isBar ? number(bar) : number(bar) + QLatin1Char('.') + number(beat);
            const SGFontMetrics *font = f.fonts[isBar ? 0 : 1];
            const double labelWidth = sgf_advance(font, text.toUtf8().constData());
            if (isBar) {
                const double top = markerHeight - m.spaceHalf;
                appendVisible(rects, f, Rect{x - 0.5, top, 1, tickBottom - top, ink});
                appendVisible(rects, f, Rect{x, top - 0.5, barCap, 1, ink});
            } else {
                appendVisible(rects, f, Rect{x - 0.5, beatTop, 1,
                                             tickBottom - beatTop, ink});
            }
            RollRender::appendLabel(c, labels,
                                    Rect{labelX, markerHeight + rulerAscent
                                         - (isBar ? rulerAscent : beatAscent),
                                         labelWidth, isBar ? rulerHeight : beatHeight},
                                    text, isBar ? RollContent::fontRuler : RollContent::fontBeat,
                                    0, Qt::AlignLeft,
                                    c.color(isBar ? RollPaletteSlot::PrimaryText
                                                  : RollPaletteSlot::RulerDetailText));
            lastLabelRight = labelX + labelWidth;
        });

    const auto marker = [&](uint64_t tick, int index, QLatin1StringView glyph) {
        if (tick == RollContent::noTick || tick < begin || tick >= end)
            return;
        const double x = cam.viewX(double(tick));
        const Rect line{x - 0.5, 0, 1, markerHeight - 1,
                        c.color(RollPaletteSlot::PrimaryText)};
        if (line.x < f.width && line.x + line.w > 0) {
            markers.lines[size_t(index)] = line;
            markers.visible[size_t(index)] = true;
        }
        appendVisible(rects, f, line);
        const QString text(glyph);
        RollRender::appendLabel(c, labels,
                                Rect{x + m.spaceHalf, 0,
                                     sgf_advance(f.fonts[2], text.toUtf8().constData()), markerHeight},
                                text, RollContent::fontBold, 0, Qt::AlignLeft,
                                c.color(RollPaletteSlot::PrimaryText));
    };
    marker(axis.loopStartTick, 0, QLatin1StringView("["));
    marker(axis.loopEndTick, 1, QLatin1StringView("]"));

    for (const auto &segment : axis.segments) {
        if (segment.start >= end)
            break;
        if (segment.start < begin)
            continue;
        const double x = cam.viewX(double(segment.start));
        const uint32_t color = c.color(segment.flags & 1 ? RollPaletteSlot::ImplicitSignature
                                                        : RollPaletteSlot::PrimaryText);
        appendVisible(rects, f, Rect{x - 0.5, 0, 1, markerHeight - 1, color});
        const QString text = number(segment.numerator) + QLatin1Char('/')
            + number(uint64_t(1) << std::min<unsigned>(segment.denomPow2, 6));
        const double labelWidth = sgf_advance(f.fonts[3], text.toUtf8().constData());
        if (segment.next != RollContent::noTick
            && cam.contentTickX(double(segment.start)) + 2 * m.spaceHalf + labelWidth
                > cam.contentTickX(double(segment.next)))
            continue;
        RollRender::appendLabel(c, labels,
                                Rect{x + m.spaceHalf, (markerHeight - boldHeight) / 2,
                                     labelWidth, boldHeight},
                                text, RollContent::fontBold, 0, Qt::AlignLeft, color);
    }
}

}
