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

inline constexpr int kScrollUnitsPerDip = 16;
inline constexpr int kVoiceAuditionKey = 60; // middle C, matching the voicegroup browser
inline constexpr int kVoiceAuditionVel = 112;

qreal logicalPhysicalPixel(qreal dpr);
int scrollUnits(double dip);
double scrollDips(int units);
QPoint wheelDelta(const QWheelEvent *event);
double wheelAngleUnits(const QWheelEvent *event);
double cursorAnchoredScroll(double anchor, double oldScale, double oldScroll, double newScale);
uint32_t usedTrackMask(const MidiTimeline *timeline) noexcept;
qreal edgeGripInnerReach(const QRectF &noteRect, qreal minimumMoveWidth, qreal edgeGripReach);
bool isBlackKey(int key);
QString keyName(int key);
// "Label\tCtrl+C" for a context-menu entry: the registry's current binding
// of the command (native text) when bound, the bare label otherwise. Shared
// by the note and time-selection menus so a rebinding updates both.
QString contextActionText(const QString &text, const QString &commandId);
QString timeSigLabel(int numerator, int denomPow2);
bool askTimeSignature(QWidget *parent, int *numerator, int *denomPow2);
QColor loopEdge();
QColor pianoRollAccidentalLaneColor();
QColor pianoRollScaleHighlightColor();
QColor trackHeaderAlsoSelectedColor();
QColor mixTowardOklabImpl(const QColor &color, const QColor &backdrop, double t);
std::size_t trackIdentityIndex(int track);
QColor contrastingTextColor(const QColor &backdrop);
QColor ghostNoteColor(int track, bool accidentalRow);
int subGridLevel(uint64_t relTick, uint64_t beatTicks, bool triplet);

// Calls fn(tick, level) for every sub-beat visible-grid position in [t0, t1)
// that is not a beat line, at the current zoom's drawn resolution
// (SongView::gridTicksAt, which bottoms out at the mid2agb clock grid; the
// snap grid runs one ladder step finer between these lines).
// Walks time-signature segments so the positions stay snappable and match
// the beat lines. No callbacks in segments whose grid is at (or coarser
// than) whole beats.
template <typename F>
void forEachSubGridLine(const SongView *sv, double t0, double t1,
                        int timelineDetailMinimumPixelsPerBeat, F &&fn)
{
    const bool triplet = sv->gridFeel() == SongView::GridFeel::Triplet;
    uint64_t at = uint64_t(std::max(0.0, t0));
    const uint64_t end = t1 <= 0.0 ? 0 : uint64_t(t1);
    while (at < end) {
        const SongView::GridSeg seg = sv->gridSegAt(at);
        const uint64_t segEnd = std::min(seg.next, end);
        const uint64_t g = sv->gridTicksAt(at);
        if (g > 0 && g < seg.beatTicks &&
            sv->pxPerTick() * double(seg.beatTicks) >= timelineDetailMinimumPixelsPerBeat) {
            const uint64_t k = at > seg.start ? (at - seg.start + g - 1) / g : 0;
            for (uint64_t tick = seg.start + k * g; tick < segEnd; tick += g) {
                if ((tick - seg.start) % seg.beatTicks == 0)
                    continue; // beat/bar lines are drawn separately
                fn(tick, subGridLevel(tick - seg.start, seg.beatTicks, triplet));
            }
        }
        if (seg.next >= end)
            break;
        at = seg.next;
    }
}

QColor gridLineColor(int alpha = 255);

} // namespace songview::detail
