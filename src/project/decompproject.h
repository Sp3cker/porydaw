#pragma once

#include <QDateTime>
#include <QDir>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVector>

#include <memory>
#include <optional>
#include <unordered_map>

#include "project/projectindex.h"
#include "projectidentity.h"
#include "voicegroupsource.h"

// Per-song mid2agb options from the song's line in sound/songs/midi/midi.cfg
// (or, in projects predating midi.cfg, its songs.mk rule).
struct SongCfg {
    // Vanilla songs.mk passes -R$(STD_REVERB) = 50 to every song, so a song
    // whose flags lack -R effectively plays at 50 in-game; treat that as the
    // default wherever the flag is absent.
    static constexpr int kDefaultReverb = 50;

    QStringList rawFlags;        // the flags as written ($(VAR) refs pre-expanded)
    QString voicegroupArg;       // -G value, e.g. "_abandoned_ship" (mid2agb default: "_dummy")
    int masterVolume = 127;      // -V (0-127)
    int reverb = -1;             // -R, -1 = flag absent (defaults to kDefaultReverb)
    int priority = 0;            // -P
    bool exactGate = false;      // -E
    bool extendedClocks = false; // -X (48 clocks/beat)
    bool noCompression = false;  // -N
    static SongCfg fromFlags(const QStringList &flags);
};

struct MusicPlayer {
    QString name;   // e.g. "MUSIC_PLAYER_BGM"
    int number = 0; // the .equiv value; also the song macro's third argument
    // Tracks this player allocates (music_player_table.inc), clamped to the
    // engine's 16 the way MPlayOpen clamps. MPlayStart never starts a song
    // track at or beyond this index, so it bounds what sounds in-game.
    // -1 when the table couldn't be parsed (no limit assumed).
    int trackCount = -1;
};

struct SongInfo {
    int id = -1;      // index in the project's song vector; equals the
                      // numeric song ID only when registered
    QString label;    // e.g. "mus_abandoned_ship"
    QString constant; // e.g. "MUS_ABANDONED_SHIP" (from songs.h, if matched)
    QString player;   // e.g. "MUSIC_PLAYER_BGM"
    QString midPath;  // absolute path to the .mid source, if it exists
    bool hasMid = false;
    bool hasCfg = false;
    // false: the .mid exists in sound/songs/midi/ but song_table.inc has no
    // entry yet — registerSong hasn't run (or failed) for it.
    bool registered = true;
    // Registration files still missing (or mis-stating) this song's entry,
    // e.g. "charmap.txt" for a song registered before porydaw wrote charmap
    // entries. Empty when the registration is complete. Stamped at open from
    // SongRegistry::checkRegistrations; drives the browser badge and the
    // Register Song enablement.
    QStringList registrationGaps;
    SongCfg cfg;

    bool isPlayable() const { return hasMid; }
};

class ProjectSnapshot
{
  public:
    ProjectSnapshot() = default;
    ProjectSnapshot(QString root, QVector<SongInfo> songs, QVector<MusicPlayer> players,
                    QHash<QString, int> trackBudgets);

    bool isOpen() const;
    const QString &root() const;
    const QVector<SongInfo> &songs() const;
    const QVector<MusicPlayer> &players() const;
    int trackBudgetFor(const SongInfo &song) const;

  private:
    QString m_root;
    QVector<SongInfo> m_songs;
    QVector<MusicPlayer> m_players;
    QHash<QString, int> m_trackBudgets;
};

// Read-only view of a Gen 3 decomp project's music data: the song list
// assembled from sound/song_table.inc, include/constants/songs.h, and
// sound/songs/midi/midi.cfg (falling back to songs.mk rules when midi.cfg
// does not exist). Voicegroups/samples are loaded separately via poryaaaa's
// voicegroup_loader.
class DecompProject
{
  public:
    bool open(const QString &rootDir, QString *error);
    // Installs detached project state on the GUI thread without disk I/O.
    void replaceWith(const ProjectSnapshot &snapshot);
    void close();

    bool isOpen() const { return !m_root.isEmpty(); }
    const QString &root() const { return m_root; }
    const QVector<SongInfo> &songs() const { return m_songs; }

    // Engine tracks the song's music player allocates (its MusicPlayer::
    // trackCount, cached at open). Tracks at or beyond this never start
    // in-game (MPlayStart), so playback and the UI treat them as silent.
    // 16 when the player is unknown or the table couldn't be parsed — the
    // engine ceiling, i.e. no porydaw-invented limit.
    int trackBudgetFor(const SongInfo &song) const;
    const QVector<MusicPlayer> &players() const { return m_players; }

    // Loader-compatible voicegroup names to try, in order, for a song.
    // mid2agb emits "voicegroup" + <-G arg> as the symbol; poryaaaa's loader
    // wants the file-basename form with any "voicegroup_" prefix stripped.
    static QStringList voicegroupCandidates(const SongInfo &song);
    static QStringList voicegroupCandidates(const SongCfg &cfg);

    // Refreshes a song's cached cfg after porydaw writes its flags back.
    void setSongCfg(int id, const SongCfg &cfg);

    // Re-reads the project's music data (after the wizard creates and
    // registers a song). Song ids are reassigned.
    bool reload(QString *error);

    // Persistent-index hook: open() uses storeDir when provided, otherwise
    // ProjectIndex::defaultStoreDir(root). A matching store replaces the scan;
    // a missing or stale store is rebuilt. PORYDAW_DISABLE_INDEX_CACHE makes
    // the default directory empty and disables automatic persistence.
    void setIndexCache(const QString &storeDir = QString());

    // ---- Worker-side voicegroup bank ownership (Project I/O worker) ----
    // The worker keeps the one canonical bank per VoicegroupId. Every
    // publication is an immutable LoadedBankView copy; a LoadedBankEntry
    // never crosses a thread or layer seam, and every hard error leaves the
    // previous record (source, lease, and file time) untouched.

    // The playable song carrying the given project-relative label, if any.
    std::optional<SongInfo> playableSong(SongName name) const;

    // Publishes the song's voicegroup bank, reusing the unchanged canonical
    // record when identity and source timestamp permit and otherwise loading
    // a complete candidate from disk before the record changes. A hard error
    // returns nullopt and writes its message through error, leaving the
    // previous record (source, lease, and file time) untouched; no invalid
    // empty-identity view is ever manufactured.
    std::optional<LoadedBankView> loadBank(const SongInfo &song, QString *error);

    // Applies one typed slot edit and returns the applied outcome (the
    // complete candidate replaces the current lease) or the confirmed
    // not-applied outcome for an expected mismatch or validation no-op,
    // which leaves the record untouched. A hard error returns nullopt with
    // a message; the old source and lease survive.
    std::optional<VoicegroupEditResult> applyVoicegroupEdit(VoicegroupEditInput input,
                                                            QString *error);

    // Writes the record's source (plus any synth definitions) to disk,
    // refreshes the canonical bank from the saved bytes, and publishes the
    // clean view. A failed stage leaves the earlier writes in place and
    // returns nullopt with a message, like loadBank.
    std::optional<LoadedBankView> saveVoicegroup(SaveVoicegroupInput input, QString *error);

  private:
    bool parseSongTable(const QDir &midiDir, const QSet<QString> &midiFiles, QString *error);
    void parseSongConstants();
    bool parseMidiCfg(); // false if midi.cfg does not exist (or can't open)
    void parseSongsMk();
    void discoverUnregisteredSongs(const QDir &midiDir, const QStringList &midiFiles);

    // The canonical, worker-owned bank record. Never published.
    struct LoadedBankEntry {
        VoicegroupId id;
        QString loadName;
        std::unique_ptr<VoicegroupSource> source;
        VoicegroupLease current;
        QDateTime sourceFileTime;
    };

    // One immutable publication copy of the record: the shared lease and the
    // 128 slot voices extracted from the source model.
    LoadedBankView publishView(const LoadedBankEntry &entry) const;

    QString m_root;
    QVector<SongInfo> m_songs;
    QVector<MusicPlayer> m_players; // cached at open (one file read)
    QHash<QString, int> m_playerTrackBudgets;
    QString m_cacheStoreDir; // empty: use ProjectIndex::defaultStoreDir()
    std::unordered_map<VoicegroupId, LoadedBankEntry, VoicegroupIdHash> m_banks;
};
