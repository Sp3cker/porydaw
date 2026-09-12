#pragma once

#include <QColor>
#include <QFont>
#include <QPoint>
#include <QRectF>
#include <QWheelEvent>
#include <algorithm>
#include <cstddef>
#include <cstdint>

#include "ui/songview.h"

namespace songview::detail {

inline constexpr int kVoiceAuditionKey = 60; // middle C, matching the voicegroup browser
inline constexpr int kVoiceAuditionVel = 112;

qreal logicalPhysicalPixel(qreal dpr);
QPoint wheelDelta(const QWheelEvent *event);
double wheelAngleUnits(const QWheelEvent *event);
double cursorAnchoredScroll(double anchor, double oldScale, double oldScroll, double newScale);
uint32_t usedTrackMask(const MidiTimeline *timeline) noexcept;
qreal edgeGripInnerReach(const QRectF &noteRect, qreal minimumMoveWidth, qreal edgeGripReach);
bool isBlackKey(int key);
QString keyName(int key);
// The registry's current binding of a menu command (native text), empty
// when unbound. Typed menus render the label and this shortcut in separate
// columns; the note and time-selection menus share it so a rebinding
// updates both.
QString contextShortcutText(const QString &commandId);
QString timeSigLabel(int numerator, int denomPow2);
QColor loopEdge();
QColor pianoRollAccidentalLaneColor();
QColor pianoRollScaleHighlightColor();
QColor trackHeaderAlsoSelectedColor();
QColor mixTowardOklabImpl(const QColor &color, const QColor &backdrop, double t);
std::size_t trackIdentityIndex(int track);
QColor contrastingTextColor(const QColor &backdrop);
QColor ghostNoteColor(int track, bool accidentalRow);
int subGridLevel(Tick relTick, uint32_t beatTicks, bool triplet);

// Half-open tick bounds for grid iteration, resolved from the fractional
// tick interval a viewport covers. empty() unless the interval is finite,
// non-empty once a negative begin clips to the song start, and strictly
// below kNoTick, where double -> tick conversion stays defined.
struct TickRange {
    Tick begin = 0;
    Tick end = 0;

    bool empty() const noexcept { return begin == end; }
};

TickRange tickRange(double begin, double end) noexcept;

// Calls fn(tick, level) for every sub-beat visible-grid position in
// [range.begin, range.end) that is not a beat line, at the current zoom's
// drawn resolution (Grid::gridTicksAt, which bottoms out at the mid2agb
// clock grid; the snap grid runs one ladder step finer between these
// lines). Walks time-signature segments so the positions stay snappable
// and match the beat lines. No callbacks in segments whose grid is at (or
// coarser than) whole beats.
template <typename F>
void forEachSubGridLine(const Grid &grid, const TimeCamera &camera, TickRange range,
                        int timelineDetailMinimumPixelsPerBeat, F &&fn)
{
    const bool triplet = grid.feel() == GridFeel::Triplet;
    Tick at = range.begin;
    while (at < range.end) {
        const Grid::Segment seg = grid.segmentAt(at);
        const Tick segEnd = std::min(seg.next, range.end);
        const Tick g = grid.gridTicksAt(at);
        if (g > 0 && g < seg.beatTicks &&
            camera.pxPerTick() * double(seg.beatTicks) >= timelineDetailMinimumPixelsPerBeat) {
            const uint64_t k = at > seg.start ? (uint64_t(at) - seg.start + g - 1) / g : 0;
            for (Tick tick = seg.start + Tick(k * g); tick < segEnd; tick += g) {
                if ((tick - seg.start) % seg.beatTicks == 0)
                    continue; // beat/bar lines are drawn separately
                fn(tick, subGridLevel(Tick(tick - seg.start), seg.beatTicks, triplet));
            }
        }
        if (seg.next >= range.end)
            break;
        at = seg.next;
    }
}

QColor gridLineColor(int alpha = 255);

} // namespace songview::detail
