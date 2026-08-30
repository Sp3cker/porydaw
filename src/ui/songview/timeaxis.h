#pragma once

#include <cstdint>
#include <functional>
#include <span>

#include "core/miditimeline.h"

namespace songview {

// The musical coordinate system of the song view's time axis: the timebase,
// the time-signature map, the known content length, and the loop markers.
// It has two states. Unbound — a fresh tab, or after setSong(nullptr) — it is
// the fallback axis: 24 ticks per beat, an implicit opening 4/4, zero known
// content length, and no loop markers. Bound, it borrows the immutable
// MidiTimeline whose lease SongTab keeps alive; nothing is copied, and the
// borrow must be repointed before the owning timeline is released. Camera,
// grid, and ruler code consume one always-valid interface and never branch
// on "no song yet".
//
// The implicit 4/4 is synthesized only here (hasImplicitOpeningSignature()
// and signatureAt()); painters must not re-derive fallback from an empty
// signature span. Zoom- and editor-dependent subdivision stays in SongView;
// this module only knows the signature-segmented musical grid itself.
class TimeAxis
{
  public:
    // Time-signature segment governing a tick. The grid — beats, snap
    // positions, sub-beat lines — restarts at every signature change and
    // scales the beat by the signature's denominator; a signature placed
    // mid-measure must still leave the drawn lines snappable.
    struct GridSegment {
        uint64_t start = 0;         // governing signature's tick (0 = song start)
        uint64_t next = UINT64_MAX; // next signature's tick; the grid restarts there
        uint64_t beatTicks = 24;    // denominator-scaled beat length in ticks
        uint64_t beatsPerBar = 4;   // numerator, matching forEachGridLine()
    };

    // The signature governing a tick, normalized: a blank numerator reads
    // as 4, and `implicit` marks the synthesized opening 4/4 of a song (or
    // of the fallback axis) whose tick 0 carries no actual signature event.
    struct ResolvedTimeSignature {
        uint64_t tick = 0;
        int numerator = 4;
        int denomPow2 = 2;
        bool implicit = true;
    };

    using GridLineVisitor =
        std::function<void(uint64_t tick, bool isBar, int barNumber, int beatNumber)>;

    TimeAxis() noexcept;

    // Borrow the timeline's musical time; nullptr returns to the fallback
    // axis. The borrowed timeline must outlive the axis or every later
    // rebinding.
    void bind(const MidiTimeline *timeline) noexcept;
    bool isBound() const noexcept;

    uint32_t ticksPerBeat() const noexcept;
    uint64_t lengthTicks() const noexcept;
    uint64_t loopStartTick() const noexcept; // UINT64_MAX when absent
    uint64_t loopEndTick() const noexcept;   // UINT64_MAX when absent

    // Actual 0x58 events only. Fallback returns an empty span; storage
    // remains borrowed from the bound immutable timeline.
    std::span<const TimeSigPoint> explicitTimeSignatures() const noexcept;
    // True in fallback and whenever no actual signature governs tick zero.
    bool hasImplicitOpeningSignature() const noexcept;
    ResolvedTimeSignature signatureAt(uint64_t tick) const noexcept;

    GridSegment segmentAt(uint64_t tick) const noexcept;
    // Bar/beat grid over [tickBegin, tickEnd): visitor(tick, isBarStart,
    // barNumber, beatNumber) for every beat — 1-based numbering, bars
    // counted across signature changes. Walks the borrowed signatures in
    // place; no segment list is copied.
    void forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                         const GridLineVisitor &visitor) const;

  private:
    const MidiTimeline *m_timeline = nullptr;
};

} // namespace songview
