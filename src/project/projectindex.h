#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>
#include <QVector>

struct MusicPlayer;
struct SongInfo;

// Persistent index of DecompProject::open state. A cache hydrate reads only
// this local SQLite store; remote-input validation is a separate later step.
namespace ProjectIndex {

struct Inputs {
    QStringList midiSongNames;
    QStringList sidecarJsonNames;
    QByteArray fingerprint;
};

// Test-only diagnostic seam. The observer is invoked for source-index
// discovery (listing/fingerprinting), never for local SQLite cache reads.
using SourceAccessObserverForTesting = void (*)(const QString &path);
void setSourceAccessObserverForTesting(SourceAccessObserverForTesting observer);

// Collects every source input used by the cache key. A missing .porydaw
// directory is valid and empty, but an inaccessible directory or indexed file
// returns false instead of manufacturing a partial fingerprint.
bool collectInputs(const QString &projectRoot, Inputs *inputs, QString *error);

// Fingerprint of every path-dependent input of DecompProject::open.
// The checked overload reports unreadable source files. The value-returning
// overload is for best-effort check helpers only.
bool fingerprint(const QString &projectRoot, const QStringList &midiSongNames,
                 const QStringList &sidecarJsonNames, QByteArray *result);
QByteArray fingerprint(const QString &projectRoot, const QStringList &midiSongNames,
                       const QStringList &sidecarJsonNames);

// Fills songs/players from a local store when its schema and lexical project
// root match. This does not inspect the project directory.
bool loadCached(const QString &storeDir, const QString &projectRoot, QVector<SongInfo> *songs,
                QVector<MusicPlayer> *players);

// Returns whether the local store still matches a fingerprint computed after
// a cache-backed project has become usable.
bool matches(const QString &storeDir, const QString &projectRoot, const QByteArray &finger);

// Strict load used by checks and callers that have already computed a
// fingerprint. Prefer loadCached() on the interactive startup path.
bool load(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          QVector<SongInfo> *songs, QVector<MusicPlayer> *players);

// Publishes a complete SQLite generation through the local current manifest.
bool save(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players,
          QString *error = nullptr);

// Current-generation manifest path under storeDir. A legacy SQLite store is
// read only when the manifest is absent.
QString storePath(const QString &storeDir);

// Default app-cache directory for a project root, keyed by lexical absolute
// path so determining it never probes a remote filesystem.
QString defaultStoreDir(const QString &projectRoot);

// Fills names with sorted bare regular-file names ending with suffix, skipping
// dotfiles. Missing directories are an empty successful listing; other
// filesystem errors return false so callers never mistake an incomplete remote
// listing for an empty one.
bool listFileNames(const QString &dirPath, const QString &suffix, QStringList *names);

// Compatibility convenience for callers that only need best-effort discovery.
// Project loading and cache validation must use the checked overload above.
QStringList listFileNames(const QString &dirPath, const QString &suffix);

} // namespace ProjectIndex
