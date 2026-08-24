#include <cstddef>

#include <cstdio>

#include "checks/editcheck/support.h"

namespace editcheck {

bool tracksSorted(const SmfFile &smf)
{
    for (const SmfTrack &track : smf.tracks) {
        for (size_t i = 1; i < track.events.size(); i++) {
            if (track.events[i].tick < track.events[i - 1].tick)
                return false;
        }
    }
    return true;
}

TempoPoint tempoPoint(uint64_t tick, uint32_t bpm)
{
    return {tick, 60'000'000U / bpm};
}

bool containsTempoPoint(const SongDocument &doc, const TempoPoint &point)
{
    for (const TempoPoint &candidate : doc.tempoPoints()) {
        if (candidate == point)
            return true;
    }
    return false;
}

void SongEditScenario::fail(const char *what) const
{
    std::fprintf(stderr, "editcheck: FAIL %s: %s\n", qUtf8Printable(songLabel), what);
    failures++;
}

bool SongEditScenario::checkSorted(const char *what) const
{
    if (tracksSorted(doc.smf()))
        return true;
    fail(what);
    return false;
}

} // namespace editcheck
