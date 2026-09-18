// Parity-seam oracles for the Swift Wave-1 tick helpers (spec §4, Task 1):
// thin forwarding over the production CoreTimeDefaults — no logic of its own.
// Tasks 2–3 append the time-axis and pitch groups to this file.

#include "math_smoke.h"

#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "ui/pitchprojection.h"
#include "ui/songview/timeaxis.h"

uint32_t sgm_shift_tick_clamped(uint32_t tick, int64_t delta)
{
    return CoreTimeDefaults::shiftTickClamped(static_cast<Tick>(tick), delta);
}

uint32_t sgm_tick_from_double(double tick)
{
    return CoreTimeDefaults::tickFromDouble(tick);
}

// Parity-seam oracles for the Swift Wave-1 TimeAxis port (spec §4, Task 2):
// thin forwarding over the production songview::TimeAxis bound to a
// stack-constructed MidiTimeline whose viewer fields are filled from the
// SGTimeMapFixture — no logic of its own. Swift never sees MidiTimeline.

namespace {

void fillTimelineFromFixture(const SGTimeMapFixture *map, MidiTimeline &timeline)
{
    timeline.ticksPerBeat = map->ticksPerBeat;
    timeline.lengthTicks = static_cast<Tick>(map->lengthTicks);
    timeline.loopStartTick = static_cast<Tick>(map->loopStartTick);
    timeline.loopEndTick = static_cast<Tick>(map->loopEndTick);
    timeline.timeSigs.clear();
    for (size_t i = 0; i < map->timeSigCount; ++i) {
        TimeSigPoint point;
        point.tick = static_cast<Tick>(map->timeSigs[i].tick);
        point.numerator = map->timeSigs[i].numerator;
        point.denomPow2 = map->timeSigs[i].denomPow2;
        timeline.timeSigs.push_back(point);
    }
}

} // namespace

void sgm_timeaxis_answer(const SGTimeMapFixture *map, uint32_t tick, SGTimeAxisAnswer *out)
{
    MidiTimeline timeline;
    fillTimelineFromFixture(map, timeline);
    songview::TimeAxis axis;
    axis.bind(&timeline);
    const songview::TimeAxis::GridSegment seg = axis.segmentAt(static_cast<Tick>(tick));
    const songview::TimeAxis::ResolvedTimeSignature sig = axis.signatureAt(static_cast<Tick>(tick));
    out->ticksPerBeat = axis.ticksPerBeat();
    out->lengthTicks = static_cast<uint32_t>(axis.lengthTicks());
    out->loopStartTick = static_cast<uint32_t>(axis.loopStartTick());
    out->loopEndTick = static_cast<uint32_t>(axis.loopEndTick());
    out->segStart = static_cast<uint32_t>(seg.start);
    out->segNext = static_cast<uint32_t>(seg.next);
    out->segBeatTicks = seg.beatTicks;
    out->segBeatsPerBar = seg.beatsPerBar;
    out->sigNumerator = static_cast<int32_t>(sig.numerator);
    out->sigDenomPow2 = static_cast<int32_t>(sig.denomPow2);
    out->sigImplicit = sig.implicit ? 1 : 0;
}

size_t sgm_timeaxis_grid_lines(const SGTimeMapFixture *map, uint32_t begin, uint32_t end,
                               SGGridLine *out, size_t capacity)
{
    MidiTimeline timeline;
    fillTimelineFromFixture(map, timeline);
    songview::TimeAxis axis;
    axis.bind(&timeline);
    size_t needed = 0;
    axis.forEachGridLine(static_cast<Tick>(begin), static_cast<Tick>(end),
                         [&](Tick tick, bool isBar, int barNumber, int beatNumber) {
                             if (needed < capacity && out != nullptr) {
                                 out[needed].tick = static_cast<uint32_t>(tick);
                                 out[needed].isBar = static_cast<uint8_t>(isBar ? 1 : 0);
                                 out[needed].bar = static_cast<int32_t>(barNumber);
                                 out[needed].beat = static_cast<int32_t>(beatNumber);
                             }
                             ++needed;
                         });
    return needed;
}

// Parity-seam oracles for the Swift Wave-1 PitchProjection port (spec §4,
// Task 3): thin forwarding over the production songview::PitchProjection —
// no logic of its own. pitches == NULL (count 0) selects the chromatic
// build; otherwise buildFromPitches over the ascending list.

namespace {

songview::PitchProjection makePitchProjection(const uint8_t *pitches, size_t count)
{
    songview::PitchProjection projection;
    if (pitches == nullptr || count == 0) {
        projection.buildChromatic();
    } else {
        projection.buildFromPitches(std::span<const uint8_t>(pitches, count));
    }
    return projection;
}

} // namespace

int32_t sgm_pitch_row_for_pitch(const uint8_t *pitches, size_t count, int32_t pitch)
{
    return static_cast<int32_t>(makePitchProjection(pitches, count).rowForPitch(pitch));
}

int32_t sgm_pitch_nearest_visible(const uint8_t *pitches, size_t count, int32_t pitch)
{
    return static_cast<int32_t>(makePitchProjection(pitches, count).nearestVisiblePitch(pitch));
}

double sgm_pitch_row_top(const uint8_t *pitches, size_t count, int32_t row, double keyHeight,
                         double scrollY, double dpr)
{
    return static_cast<double>(
        makePitchProjection(pitches, count).rowTop(row, keyHeight, scrollY, dpr));
}

int32_t sgm_pitch_y_to_pitch(const uint8_t *pitches, size_t count, double y, double keyHeight,
                             double scrollY, double dpr)
{
    return static_cast<int32_t>(
        makePitchProjection(pitches, count).yToPitch(y, keyHeight, scrollY, dpr));
}
