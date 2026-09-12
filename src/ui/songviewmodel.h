#pragma once

#include <QString>
#include <cstdint>
#include <vector>

#include "core/m4asemantics.h"
#include "core/miditimeline.h"
#include "core/noteid.h"
#include "core/timedefaults.h"

// Presentation model derived from a MidiTimeline: notes paired from on/off
// events, automation lane curves per (track, parameter), voice changes, and a
// strip of everything else. Every timeline event lands in exactly one of
// these buckets — the M1 guarantee that no event is silently invisible.

struct ViewNote {
    NoteId noteId; // source document identity; unassigned for ordinary timeline notes
    Tick startTick;
    uint32_t duration; // 0 = unpaired note-on or same-tick pair
    uint8_t key;
    uint8_t velocity;
    uint8_t track;

    uint64_t endTick() const { return uint64_t(startTick) + duration; }
};

struct LanePoint {
    Tick tick;
    int value;
};

constexpr uint8_t LANE_CC_BEND = CoreTimeDefaults::kLaneCcBend;

struct CcLane {
    uint8_t track;
    uint8_t cc; // MIDI CC number or registered pseudo-lane controller
    M4aLane lane;
    QString name;
    std::vector<LanePoint> points; // sorted by tick
};

struct VoiceChange {
    Tick tick;
    uint8_t track;
    uint8_t program;
};

struct StripItem {
    Tick tick;
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

    size_t unpairedNoteOns = 0;
    size_t orphanNoteOffs = 0; // shown in the strip

    const CcLane *findLane(int track, uint8_t cc) const
    {
        for (const CcLane &l : lanes)
            if (l.track == track && l.cc == cc)
                return &l;
        return nullptr;
    }
};

SongViewModel buildSongViewModel(const MidiTimeline &tl);
