#pragma once

#if defined(PORYDAW_SIGNPOSTS)
#include <os/signpost.h>

namespace profiling {

inline os_log_t midiNoteDeleteLog()
{
    static os_log_t log =
        os_log_create("com.huderlem.porydaw", "MidiNoteDelete");
    return log;
}

} // namespace profiling
#endif
