#pragma once

#include <QByteArray>
#include <QStringList>
#include <QVector>

struct MusicPlayer;
struct SongInfo;

// Persistent index of DecompProject::open state, keyed by file stat fingerprint.
namespace ProjectIndex {

// Fingerprint of every path-dependent input of DecompProject::open.
QByteArray fingerprint(const QString &projectRoot, const QStringList &midiSongNames,
                       const QStringList &sidecarJsonNames);

// Fills songs/players from the SQLite store when fingerprint and root match.
bool load(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          QVector<SongInfo> *songs, QVector<MusicPlayer> *players);

// Replaces the stored SQLite index atomically.
bool save(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players);

// SQLite database path under storeDir.
QString storePath(const QString &storeDir);

// Default app-cache directory for a project root, keyed by canonical path.
QString defaultStoreDir(const QString &projectRoot);

// Sorted bare file names ending with suffix, skipping dotfiles (no per-entry stat).
QStringList listFileNames(const QString &dirPath, const QString &suffix);

} // namespace ProjectIndex
