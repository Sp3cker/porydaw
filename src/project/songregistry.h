#pragma once

#include <QHash>
#include <QString>
#include <QStringList>
#include <QVector>

#include "project/decompproject.h"

struct SmfFile;

// The onboarding backend (SPEC.md §6.3): everything the New Song / Import
// wizards need to create a song and register it. porydaw writes the .mid,
// the midi.cfg line, and the registration files (song_table.inc, songs.h,
// ld_script.ld, charmap.txt) directly — inserting or correcting only the
// song's own lines, byte-conservative for everything else.

struct RegistrationPlan {
    QString label;    // e.g. "mus_foo"
    QString constant; // e.g. "MUS_FOO"
    QString player;   // e.g. "MUSIC_PLAYER_BGM"
    int songId = -1;  // proposed ID = current count of song-table entries

    QString songTableLine;    // "\tsong mus_foo, MUSIC_PLAYER_BGM, 0"
    QString songsHLine;       // "#define MUS_FOO 610"
    QString ldLine;           // "        sound/songs/midi/mus_foo.o(.rodata);"
    QString charmapLine;      // "MUS_FOO = 62 02" — the ID, little-endian bytes
    bool ldApplicable = true; // false when ld_script.ld has no per-song lines
    bool charmapApplicable = true; // false when charmap.txt has no song entries
};

struct RegistrationStatus {
    bool inSongTable = false;
    bool inSongsH = false;
    bool inLdScript = false;
    bool inCharmap = false;
    bool ldApplicable = true;
    bool charmapApplicable = true;

    bool complete() const
    {
        return inSongTable && inSongsH && (inLdScript || !ldApplicable)
               && (inCharmap || !charmapApplicable);
    }
};

namespace SongRegistry {

// -G arguments for every voicegroup label findable in the project: the
// "voice_group <name>" macro (modern pokeemerald) and raw "voicegroup*::"
// labels (pokefirered et al.), scanned from sound/voice_groups.inc,
// sound/voicegroups.inc, and sound/voicegroups/ recursively. Sorted.
QStringList voicegroupArgs(const QString &projectRoot);

// Display form of a -G arg: the leading underscore folds into the fixed
// "voicegroup_" prefix the UI shows, so "_abandoned_ship" reads as
// "abandoned_ship". Underscore-less args (vanilla "128"-style symbols)
// pass through unchanged.
QString voicegroupDisplayName(const QString &arg);

// The inverse: a name typed under the "voicegroup_" prefix back to a -G
// arg. A leading underscore means a raw arg was pasted; a verbatim match
// against knownArgs keeps legacy underscore-less args addressable;
// everything else assumes the underscore.
QString voicegroupArgFromDisplay(const QString &text, const QStringList &knownArgs);

// Music players from song_table.inc's ".equiv MUSIC_PLAYER_*,n" lines.
QVector<MusicPlayer> musicPlayers(const QString &projectRoot);

// Default constant for a label: "mus_foo" -> "MUS_FOO".
QString constantForLabel(const QString &label);

// Computes the registration lines against the files as they are on disk
// right now, matching each file's existing indentation/alignment.
RegistrationPlan makePlan(const QString &projectRoot, const QString &label,
                          const QString &constant, const QString &player);

// Writes the song into all registration files: appends the song_table.inc
// entry, the songs.h #define, and the ld_script.ld object line, and inserts
// the charmap.txt ID mapping in the sound section's ID order (the last two
// when applicable). Idempotent —
// entries that already exist are left byte-identical, except a songs.h
// define or charmap.txt entry whose ID no longer matches the song's table
// index, which is corrected in place. Only the song's own lines change.
// On success *songId carries the song's table index.
bool registerSong(const QString &projectRoot, const QString &label,
                  const QString &constant, const QString &player, QString *error,
                  int *songId = nullptr);

// Re-parses the registration files from disk. The songs.h and charmap.txt
// items additionally require their value to match the label's actual
// song-table index once the table entry exists (a mismatched ID is a
// mis-registration).
RegistrationStatus checkRegistration(const QString &projectRoot, const QString &label,
                                     const QString &constant);

// checkRegistration for every song at once, keyed by label: one read of
// each registration file for the whole project (the song browser audits
// hundreds of songs at open). A song with no parsed constant is checked
// under its label-derived default, like the Register Song action.
QHash<QString, RegistrationStatus> checkRegistrations(const QString &projectRoot,
                                                      const QVector<SongInfo> &songs);

// Rebuilds a song's midi.cfg flag list from its properties, keeping unknown
// flags (e.g. -L) and the original flag order intact.
QStringList mergeCfgFlags(const SongCfg &cfg);

// Updates or appends the song's line in <midiDir>/midi.cfg, byte-conservative
// for every other line (vanilla midi.cfg is CRLF; per-line \r is preserved).
bool writeMidiCfgLine(const QString &midiDir, const QString &label,
                      const QStringList &flags, QString *error);

// Persists a song's flags wherever the project stores them: its midi.cfg
// line when <midiDir>/midi.cfg exists, its songs.mk rule for projects
// predating midi.cfg, and a fresh midi.cfg when the project has neither.
bool writeSongFlags(const QString &midiDir, const QString &label,
                    const QStringList &flags, QString *error);

// A minimal editable song: format 1, division 24 (vanilla), a seq track with
// tempo 120 + 4/4 time signature, and one instrument track (voice 0, VOL 100)
// spanning one bar.
SmfFile blankSong();

// Pending-registration metadata in the sidecar (.porydaw/<label>.json), so
// an unregistered song's chosen constant/player survive a project reopen
// when registerSong could not complete (SPEC §6.3).
bool saveRegistrationMeta(const QString &projectRoot, const QString &label,
                          const QString &constant, const QString &player);
bool loadRegistrationMeta(const QString &projectRoot, const QString &label,
                          QString *constant, QString *player);
void clearRegistrationMeta(const QString &projectRoot, const QString &label);

} // namespace SongRegistry
