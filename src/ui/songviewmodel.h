#pragma once

#include <QString>
#include <cstdint>
#include <vector>

#include "core/miditimeline.h"
#include "core/noteid.h"
#include "core/timedefaults.h"
#include "ui/m4asemantics.h"

// Presentation model derived from a MidiTimeline: notes paired from on/off
// events, automation lane curves per (track, parameter), voice changes, and a
// strip of everything else. Every timeline event lands in exactly one of
// these buckets — the M1 guarantee that no event is silently invisible.

struct ViewNote {
    NoteId noteId; // source document identity; unassigned for ordinary timeline notes
    uint32_t startTick;
    uint32_t endTick;
    uint8_t key;
    uint8_t velocity;
    uint8_t track;
    bool unterminated; // note-on with no matching note-off; drawn to song end
};

struct LanePoint {
    uint32_t tick;
    int value;
};

constexpr uint8_t LANE_CC_BEND = CoreTimeDefaults::kLaneCcBend;

struct CcLane {
    uint8_t track;
    uint8_t cc; // MIDI CC number, or LANE_CC_BEND
    M4aLane lane;
    QString name;
    std::vector<LanePoint> points; // sorted by tick
};

struct VoiceChange {
    uint32_t tick;
    uint8_t track;
    uint8_t program;
};

struct StripItem {
    uint64_t tick;
    int track; // -1 = file-level
    QString label;
};

struct SongViewModel {
    std::vector<ViewNote> notes;     // sorted by startTick
    std::vector<CcLane> lanes;       // grouped by track, lane order per §4.2
    std::vector<VoiceChange> voices; // sorted by tick
    std::vector<StripItem> strip;    // sorted by tick; advanced CCs + parser leftovers
    int minNoteKey = 127;
    int maxNoteKey = 0;

    // Coverage stats for --viewcheck.
    size_t unpairedNoteOns = 0; // rendered anyway (unterminated), but reported
    size_t orphanNoteOffs = 0;  // shown in the strip

    const CcLane *findLane(int track, uint8_t cc) const
    {
        for (const CcLane &l : lanes)
            if (l.track == track && l.cc == cc)
                return &l;
        return nullptr;
    }
};

SongViewModel buildSongViewModel(const MidiTimeline &tl);
