#pragma once

#include <QByteArray>
#include <QStringList>
#include <QVector>

struct MusicPlayer;
struct SongInfo;

// Persistent copy of the index DecompProject::open assembles. A stored index
// is keyed by ProjectIndex::fingerprint — a digest over every input the scan
// reads (registration/config files, the midi directory listing, and the
// .porydaw sidecar listing) — so a stale store is detected by stat alone and
// self-heals: load() refuses anything whose fingerprint does not match, and
// the caller falls back to a full scan followed by save().
//
// Storage lives outside the indexed project (app cache / benchmark scratch),
// never beside the sources: projects on FAT32 sticks have neither the space
// nor the metadata fidelity for derived state.
namespace ProjectIndex {

enum class Backend {
    Sqlite, // one table per entity in a single SQLite database (Qt6::Sql)
    Json,   // one QJsonDocument object tree in a single file (QSaveFile)
};

// Every path-dependent input of DecompProject::open, stat-digested.
QByteArray fingerprint(const QString &projectRoot);

// Fills songs/players from the store when it holds this exact root and
// fingerprint. False on any absence, mismatch, or parse failure — callers
// rescan. Best-effort, like all sidecar IO.
bool load(Backend backend, const QString &storeDir, const QString &projectRoot,
          const QByteArray &finger, QVector<SongInfo> *songs, QVector<MusicPlayer> *players);

// Replaces the stored index atomically (temp file + rename).
bool save(Backend backend, const QString &storeDir, const QString &projectRoot,
          const QByteArray &finger, const QVector<SongInfo> &songs,
          const QVector<MusicPlayer> &players);

// Where a backend keeps its bytes under storeDir (for size metrics/tests).
QString storePath(Backend backend, const QString &storeDir);

// Bare file names in dirPath whose name ends with suffix — dotfiles
// (FAT32 AppleDouble twins) excluded, sorted. A bare dirent walk: no
// per-entry stat, unlike QDir::entryList on macOS.
QStringList listFileNames(const QString &dirPath, const QString &suffix);

} // namespace ProjectIndex
