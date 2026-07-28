#pragma once

#include <QString>
#include <QStringList>
#include <cstdint>
#include <vector>

#include "core/smf.h"

// External-MIDI import analysis (SPEC.md §6.2): everything the import wizard
// shows about an arbitrary .mid before it becomes a project song. The file's
// bytes are kept as-is on import — mid2agb rescales the division and ignores
// CCs outside its vocabulary — so the pass is a lens plus one optional
// transform: a division rescale onto the m4a clock grid.

struct ImportTrackInfo {
    int smfTrack = -1;      // chunk index
    QString name;           // track-name meta, if present
    int noteCount = 0;
    // Programs in order of first use; empty means every note plays voice 0
    // (mid2agb's initial program) — worth flagging against the voicegroup.
    std::vector<uint8_t> programs;
    std::vector<uint8_t> channels;   // used MIDI channels, in source order
    bool notesBeforeProgram = false; // notes sound before the first VOICE
};

struct ImportCcUsage {
    uint8_t cc = 0;
    int count = 0;
    QString label; // m4a meaning ("VOL — Volume") or "CC n (ignored by mid2agb)"
    bool audible = false; // rendered by the engine (vs. kept-but-inert)
};

struct ImportAnalysis {
    uint16_t division = 24;
    int smfTrackCount = 0;
    int mappedTracks = 0;  // engine tracks (first 16 channel-bearing chunks)
    int droppedTracks = 0; // channel-bearing chunks beyond the m4a limit
    int silentTracks = 0;  // mapped tracks beyond the player's track budget
    int peakConcurrentNotes = 0;
    std::vector<ImportTrackInfo> tracks; // one per mapped engine track
    std::vector<ImportCcUsage> ccs;      // by CC number, ascending
    QStringList warnings;                // human-readable mapping-pass flags
};

// Importable note-bearing chunks, in source order. Unlike analyzeForImport,
// this scan is not capped at the m4a 16-track engine limit.
std::vector<ImportTrackInfo> noteBearingImportTracks(const SmfFile &smf);

// Build a format-1 file containing the selected musical chunks plus the
// source-global events needed by a standalone song.
SmfFile selectedMidiForNewSong(const SmfFile &smf,
                               const std::vector<int> &selectedTracks);

// Build the selected musical chunks for appending to an existing song,
// omitting events that are global to the destination song.
SmfFile selectedMidiForAppend(const SmfFile &smf,
                              const std::vector<int> &selectedTracks);

// Earliest real note-on tick, or UINT64_MAX when the file has no note-ons.
uint64_t earliestNoteTick(const SmfFile &smf);

// trackBudget/playerName describe the music player the song will run on
// (MusicPlayer::trackCount): mapped tracks at or beyond the budget never
// start in-game, which is worth a warning of its own below the hard 16
// ceiling. Budget 16 (or a negative unknown) disables that warning.
ImportAnalysis analyzeForImport(const SmfFile &smf, int trackBudget = 16,
                                const QString &playerName = QString());

// Rescale every event tick (and each track's end-of-track tick) onto a new
// division, using the same floor arithmetic as mid2agb's event conversion
// (`24 * clocksPerBeat * time / division`, tools/mid2agb/midi.cpp). With
// newDivision equal to the song's clocks per beat (24, or 48 under -X), every
// onset lands on the exact tick mid2agb would have played it at, and the
// editor grid becomes exact. Note durations may still differ from an as-is
// import by one clock, because mid2agb floors onset and duration
// independently while a tick rescale floors onset and note-off.
void rescaleDivision(SmfFile *smf, uint16_t newDivision);
