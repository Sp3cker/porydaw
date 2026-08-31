#pragma once

#include <QColor>
#include <QFont>
#include <QPoint>
#include <QRectF>
#include <QSet>
#include <QStringList>
#include <QWheelEvent>
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

#include "core/m4asemantics.h"
#include "ui/songview/grid.h"
extern "C" {
#include "voicegroup_loader.h"
}
class MidiTimeline;

namespace songview::detail {

// Resolved once per keyboard sync or hover; row formatting never queries a
// view. Construction is private — only keyboardRowSource produces one — so no
// caller can pair a drum classification with an unresolved bank/program. Drum
// classification holds even when the bank carries no names metadata; m_names
// is the optional O(1) per-slot table behind drumPadName/rowLabel.
class KeyboardRowSource
{
  public:
    bool isDrum() const { return m_isDrum; }
    // Trimmed pad name for `key`, or empty when the track is not a drumset,
    // the bank has no names table, or the slot is unnamed.
    QString drumPadName(int key) const;
    // Gutter/hover label: the pad name when one exists, else keyName(key).
    QString rowLabel(int key) const;

  private:
    KeyboardRowSource() = default;
    KeyboardRowSource(bool isDrum, const char (*names)[VG_VOICE_NAME_LEN])
        : m_isDrum(isDrum)
        , m_names(names)
    {}
    friend KeyboardRowSource keyboardRowSource(const LoadedVoiceGroup *bank,
                                               const MidiTimeline *timeline, int track);

    bool m_isDrum = false;
    const char (*m_names)[VG_VOICE_NAME_LEN] = nullptr;
};

KeyboardRowSource keyboardRowSource(const LoadedVoiceGroup *bank, const MidiTimeline *timeline,
                                    int track);

inline constexpr int kVoiceAuditionKey = 60; // middle C, matching the voicegroup browser
inline constexpr int kVoiceAuditionVel = 112;

struct VisibleRows {
    std::array<bool, VOICEGROUP_SIZE> rows{};
    int matchingCount = 0;
    int nextRow = -1;
};

VisibleRows visibleVoiceRows(const std::array<VoiceFamily, VOICEGROUP_SIZE> &families,
                             const QStringList &displayNames, const QSet<int> &usedSlots,
                             std::optional<VoiceFamily> family, bool usedOnly, bool namedOnly,
                             int currentRow);

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
// [range.begin, range.end) that is not a beat line, at the selection's
// drawn resolution (Grid::gridTicksAt, which bottoms out at the mid2agb
// clock grid; the snap grid runs one ladder step finer between these
// lines under Auto). Auto/Musical positions re-anchor at each
// time-signature segment; Clock positions stay on the absolute lattice
// across seams. No callbacks in segments whose grid is at (or coarser
// than) whole beats, or where Grid::drawsSubGridIn suppresses the
// sub-grid at the current zoom.
template <typename F>
void forEachSubGridLine(const Grid &grid, TickRange range, F &&fn)
{
    const bool triplet = grid.feel() == GridFeel::Triplet;
    Tick at = range.begin;
    while (at < range.end) {
        const Grid::Segment seg = grid.segmentAt(at);
        const Tick segEnd = std::min(seg.next, range.end);
        const uint64_t g = uint64_t(grid.gridTicksAt(at));
        if (g < seg.beatTicks && grid.drawsSubGridIn(seg)) {
            const uint64_t anchor = uint64_t(grid.subGridAnchorIn(seg));
            const uint64_t k = at > anchor ? (uint64_t(at) - anchor + g - 1) / g : 0;
            const uint64_t first = anchor + k * g;
            for (uint64_t tick = first; tick < segEnd; tick += g) {
                if ((tick - seg.start) % seg.beatTicks == 0)
                    continue; // beat/bar lines are drawn separately
                fn(Tick(tick), subGridLevel(Tick(tick - seg.start), seg.beatTicks, triplet));
            }
        }
        if (seg.next >= range.end)
            break;
        at = seg.next;
    }
}

QColor gridLineColor(int alpha = 255);

} // namespace songview::detail
