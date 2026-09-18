#pragma once

// Parity seam for the Swift Wave-1 view-math ports (spec §4): C ABI over the
// production C++ types, imported by Swift through the NativeGridSmoke module.
// Swift drives, C++ answers — no @_cdecl, no C++→Swift calls.
//
// Declared incrementally: Task 1 declares only the tick pair. Tasks 2–3
// append the time-axis and pitch groups below; the fixture structs are
// declared here up front so those appends touch declarations only.

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGSigPoint { // fixture mirror of TimeSigPoint
    uint32_t tick;
    uint8_t numerator;
    uint8_t denomPow2;
} SGSigPoint;

typedef struct SGTimeMapFixture { // fixture mirror of TimeMap
    uint32_t ticksPerBeat;
    uint32_t lengthTicks;
    uint32_t loopStartTick;
    uint32_t loopEndTick;
    const SGSigPoint *timeSigs; // tick-sorted; may be NULL when count == 0
    size_t timeSigCount;
} SGTimeMapFixture;

typedef struct SGTimeAxisAnswer { // every scalar query in one struct
    uint32_t ticksPerBeat, lengthTicks, loopStartTick, loopEndTick;
    uint32_t segStart, segNext, segBeatTicks, segBeatsPerBar; // segmentAt(tick)
    int32_t sigNumerator, sigDenomPow2, sigImplicit;          // signatureAt(tick); implicit 0/1
} SGTimeAxisAnswer;

typedef struct SGGridLine {
    uint32_t tick;
    uint8_t isBar;
    int32_t bar;
    int32_t beat;
} SGGridLine;

/* Task 1 */ uint32_t sgm_shift_tick_clamped(uint32_t tick, int64_t delta);
/* Task 1 */ uint32_t sgm_tick_from_double(double tick);
/* Task 2 */ void sgm_timeaxis_answer(const SGTimeMapFixture *map, uint32_t tick,
                                      SGTimeAxisAnswer *out);
/* Task 2 */ size_t sgm_timeaxis_grid_lines(const SGTimeMapFixture *map, uint32_t begin,
                                            uint32_t end, SGGridLine *out, size_t capacity);
/* Task 3 */ int32_t sgm_pitch_row_for_pitch(const uint8_t *pitches, size_t count, int32_t pitch);
/* Task 3 */ int32_t sgm_pitch_nearest_visible(const uint8_t *pitches, size_t count, int32_t pitch);
/* Task 3 */ double sgm_pitch_row_top(const uint8_t *pitches, size_t count, int32_t row,
                                      double keyHeight, double scrollY, double dpr);
/* Task 3 */ int32_t sgm_pitch_y_to_pitch(const uint8_t *pitches, size_t count, double y,
                                          double keyHeight, double scrollY, double dpr);

#ifdef __cplusplus
} // extern "C"
#endif
