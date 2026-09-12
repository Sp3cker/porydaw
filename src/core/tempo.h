#pragma once
#include "timedefaults.h"
#include <cstdint>

// A global MIDI tempo change. The value is the exact SMF FF 51 payload rather
// than a derived BPM, so the document can preserve MIDI tempo precision.
struct TempoPoint {
    Tick tick = 0;
    uint32_t microsecondsPerQuarterNote = 0;
};
static_assert(sizeof(TempoPoint) == 8);

inline bool operator==(const TempoPoint &a, const TempoPoint &b)
{
    return a.tick == b.tick && a.microsecondsPerQuarterNote == b.microsecondsPerQuarterNote;
}
