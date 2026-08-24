#include "projectindex.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <string>
#include <vector>

#include "project/decompproject.h"

namespace ProjectIndex {

namespace {

constexpr int kStoreVersion = 3;

// Files and listings digested by fingerprint().
constexpr const char *kIndexedFiles[] = {
    "sound/song_table.inc",
    "include/constants/songs.h",
    "sound/songs/midi/midi.cfg",
    "sound/music_player_table.inc",
    "charmap.txt",
    "ld_script.ld",
    "src/debug.c",
    "sound/songs/midi/songs.mk",
};

// Coerce null QString to empty string so SQL NOT NULL is satisfied.
inline QString nz(const QString &text)
{
    return text.isNull() ? QStringLiteral("") : text;
}

inline QString deriveMidPath(const QString &root, const QString &label, bool hasMid)
{
    if (!hasMid)
        return {};
    return root + QStringLiteral("/sound/songs/midi/") + label + QStringLiteral(".mid");
}

inline QString encodeList(const QStringList &list)
{
    return QString::fromUtf8(
        QJsonDocument(QJsonArray::fromStringList(list)).toJson(QJsonDocument::Compact));
}

inline QStringList decodeList(const QString &jsonText)
{
    if (jsonText.isEmpty())
        return {};
    QStringList result;
    const QJsonArray array = QJsonDocument::fromJson(jsonText.toUtf8()).array();
    result.reserve(array.size());
    for (const auto &val : array)
        result.append(val.toString());
    return result;
}

void feedStat(QCryptographicHash *hash, const QString &path)
{
    QFileInfo info(path);
    if (!info.isFile()) {
        const char absent[] = "absent\n";
        hash->addData(absent, sizeof(absent) - 1);
        return;
    }
    hash->addData(QFile::encodeName(info.fileName()));
    hash->addData("|");
    hash->addData(QByteArray::number(info.size()));
    hash->addData("|");
    hash->addData(QByteArray::number(info.lastModified().toMSecsSinceEpoch()));
    hash->addData("\n");
}

void feedListingNames(QCryptographicHash *hash, const QStringList &names)
{
    hash->addData(QByteArray::number(qsizetype(names.size())));
    hash->addData(":");
    hash->addData(names.join(u',').toUtf8());
    hash->addData("\n");
}

QString sqlConnectionName()
{
    static std::atomic<int> counter{0};
    return QStringLiteral("porydaw-project-index-%1").arg(++counter);
}

// True when the meta table holds the expected key/value pair.
bool metaMatches(QSqlQuery *query, const QString &key, const QString &expected)
{
    query->prepare(QStringLiteral("SELECT value FROM meta WHERE key = :key"));
    query->bindValue(QStringLiteral(":key"), key);
    if (!query->exec() || !query->next())
        return false;
    return query->value(0).toString() == expected;
}

bool loadSqlite(const QString &path, const QString &root, const QByteArray &finger,
                QVector<SongInfo> *songs, QVector<MusicPlayer> *players)
{
    if (!QFileInfo::exists(path))
        return false;
    const QString connection = sqlConnectionName();
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
        db.setDatabaseName(path);
        if (!db.open()) {
            db = QSqlDatabase();
            QSqlDatabase::removeDatabase(connection);
            return false;
        }

        bool ok = false;
        {
            QSqlQuery query(db);
            ok = metaMatches(&query, QStringLiteral("version"), QString::number(kStoreVersion)) &&
                 metaMatches(&query, QStringLiteral("root"), root) &&
                 metaMatches(&query, QStringLiteral("fingerprint"), QString::fromLatin1(finger));
        }
        if (ok) {
            // Replace caller-owned output vectors.
            songs->clear();
            players->clear();
            QSqlQuery query(db);
            ok = query.exec(QStringLiteral("SELECT label, constant, player, has_mid,"
                                           " has_cfg, registered, gaps, raw_flags FROM songs"
                                           " ORDER BY idx"));
            int idx = 0;
            while (ok && query.next()) {
                SongInfo song;
                song.id = idx++;
                song.label = query.value(0).toString();
                song.constant = query.value(1).toString();
                song.player = query.value(2).toString();
                song.hasMid = query.value(3).toInt() != 0;
                song.midPath = deriveMidPath(root, song.label, song.hasMid);
                song.hasCfg = query.value(4).toInt() != 0;
                song.registered = query.value(5).toInt() != 0;
                song.registrationGaps = decodeList(query.value(6).toString());
                song.cfg = SongCfg::fromFlags(decodeList(query.value(7).toString()));
                songs->append(song);
            }
            ok = ok && query.exec(QStringLiteral("SELECT name, number, track_count FROM players"
                                                 " ORDER BY idx"));
            while (ok && query.next()) {
                MusicPlayer player;
                player.name = query.value(0).toString();
                player.number = query.value(1).toInt();
                player.trackCount = query.value(2).toInt();
                players->append(player);
            }
            if (!query.isActive() || query.lastError().isValid())
                ok = false;
        }
        ok = ok && !songs->isEmpty();

        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(connection);
        if (!ok) {
            songs->clear();
            players->clear();
        }
        return ok;
    }
}

bool saveSqlite(const QString &path, const QString &root, const QByteArray &finger,
                const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players)
{
    // Write scratch database, then atomically swap over destination.
    const QString tmp = path + QStringLiteral(".tmp");
    bool ok = true;
    QFile::remove(tmp);
    QFile::remove(tmp + QStringLiteral("-journal"));

    const QString connection = sqlConnectionName();
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
        db.setDatabaseName(tmp);
        if (!db.open()) {
            db = QSqlDatabase();
            QSqlDatabase::removeDatabase(connection);
            return false;
        }

        {
            // Scope queries so handles are closed before connection removal.
            QSqlQuery query(db);
            // Drain journal_mode statement before subsequent writes.
            query.exec(QStringLiteral("PRAGMA journal_mode=OFF"));
            query.next();

            const auto run = [&ok, &query](const QString &sql) {
                if (!query.exec(sql))
                    ok = false;
            };
            run(QStringLiteral("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)"));
            run(QStringLiteral("CREATE TABLE songs(idx INTEGER PRIMARY KEY, label TEXT NOT NULL,"
                               " constant TEXT NOT NULL, player TEXT NOT NULL,"
                               " has_mid INTEGER NOT NULL, has_cfg INTEGER NOT NULL,"
                               " registered INTEGER NOT NULL, gaps TEXT NOT NULL,"
                               " raw_flags TEXT NOT NULL)"));
            run(QStringLiteral("CREATE TABLE players(idx INTEGER PRIMARY KEY,"
                               " name TEXT NOT NULL, number INTEGER NOT NULL,"
                               " track_count INTEGER NOT NULL)"));
            run(QStringLiteral("BEGIN"));
            if (ok) {
                query.prepare(QStringLiteral("INSERT INTO meta VALUES(:key, :value)"));
                const auto metaRow = [&](const QString &key, const QString &value) {
                    query.bindValue(QStringLiteral(":key"), key);
                    query.bindValue(QStringLiteral(":value"), value);
                    ok = query.exec() && ok;
                };
                metaRow(QStringLiteral("version"), QString::number(kStoreVersion));
                metaRow(QStringLiteral("root"), root);
                metaRow(QStringLiteral("fingerprint"), QString::fromLatin1(finger));

                // Bind all 9 columns for each song.
                query.prepare(QStringLiteral("INSERT INTO songs VALUES("
                                             ":idx, :label, :constant, :player,"
                                             " :has_mid, :has_cfg, :registered, :gaps,"
                                             " :raw_flags)"));
                for (int i = 0; i < songs.size(); ++i) {
                    const SongInfo &song = songs[i];
                    query.bindValue(QStringLiteral(":idx"), i);
                    query.bindValue(QStringLiteral(":label"), nz(song.label));
                    query.bindValue(QStringLiteral(":constant"), nz(song.constant));
                    query.bindValue(QStringLiteral(":player"), nz(song.player));
                    query.bindValue(QStringLiteral(":has_mid"), int(song.hasMid));
                    query.bindValue(QStringLiteral(":has_cfg"), int(song.hasCfg));
                    query.bindValue(QStringLiteral(":registered"), int(song.registered));
                    query.bindValue(QStringLiteral(":gaps"), encodeList(song.registrationGaps));
                    query.bindValue(QStringLiteral(":raw_flags"), encodeList(song.cfg.rawFlags));
                    ok = query.exec() && ok;
                }

                query.prepare(QStringLiteral("INSERT INTO players VALUES("
                                             ":idx, :name, :number, :track_count)"));
                for (int i = 0; i < players.size(); ++i) {
                    query.bindValue(QStringLiteral(":idx"), i);
                    query.bindValue(QStringLiteral(":name"), nz(players[i].name));
                    query.bindValue(QStringLiteral(":number"), players[i].number);
                    query.bindValue(QStringLiteral(":track_count"), players[i].trackCount);
                    ok = query.exec() && ok;
                }
            }
            run(ok ? QStringLiteral("COMMIT") : QStringLiteral("ROLLBACK"));
        }

        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(connection);
    }

    if (!ok) {
        QFile::remove(tmp);
        return false;
    }
    QFile::remove(path);
    return QFile::rename(tmp, path);
}

} // namespace

QStringList listFileNames(const QString &dirPath, const QString &suffix)
{
    // Bare dirent walk skipping dotfiles and filtering by suffix.
    QStringList names;
    std::error_code error;
#if defined(_WIN32)
    const std::filesystem::path rootPath(dirPath.toStdWString());
#else
    const std::filesystem::path rootPath(dirPath.toStdString());
#endif
    for (std::filesystem::directory_iterator it(rootPath, error), end; !error && it != end;
         it.increment(error)) {
#if defined(_WIN32)
        const QString fileName = QString::fromStdWString(it->path().filename().wstring());
#else
        const QString fileName = QString::fromStdString(it->path().filename().string());
#endif
        if (!fileName.isEmpty() && !fileName.startsWith(u'.') && fileName.endsWith(suffix))
            names.append(fileName);
    }
    std::sort(names.begin(), names.end());
    return names;
}

QByteArray fingerprint(const QString &projectRoot, const QStringList &midiSongNames,
                       const QStringList &sidecarJsonNames)
{
    QCryptographicHash hash(QCryptographicHash::Sha1);
    for (const char *relative : kIndexedFiles) {
        hash.addData(relative);
        hash.addData("\n");
        feedStat(&hash, projectRoot + QLatin1Char('/') + QLatin1String(relative));
    }
    feedListingNames(&hash, midiSongNames);
    feedListingNames(&hash, sidecarJsonNames);
    return hash.result().toHex();
}
static QString canonicalRoot(const QString &projectRoot)
{
    const QString canonical = QFileInfo(projectRoot).canonicalFilePath();
    return canonical.isEmpty() ? QDir(projectRoot).absolutePath() : canonical;
}

bool load(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          QVector<SongInfo> *songs, QVector<MusicPlayer> *players)
{
    return loadSqlite(storePath(storeDir), canonicalRoot(projectRoot), finger, songs, players);
}

bool save(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players)
{
    if (storeDir.isEmpty())
        return false;
    // Ensure destination directory exists.
    if (!QDir().mkpath(storeDir))
        return false;
    return saveSqlite(storePath(storeDir), canonicalRoot(projectRoot), finger, songs, players);
}

QString storePath(const QString &storeDir)
{
    return storeDir + QStringLiteral("/project-index.sqlite");
}

QString defaultStoreDir(const QString &projectRoot)
{
    if (!qEnvironmentVariableIsEmpty("PORYDAW_DISABLE_INDEX_CACHE"))
        return {};
    const QString effective = canonicalRoot(projectRoot);
    if (effective.isEmpty())
        return {};
    const QString key = QString::fromLatin1(
        QCryptographicHash::hash(effective.toUtf8(), QCryptographicHash::Sha1).toHex());
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) +
           QStringLiteral("/index-cache/") + key;
}

} // namespace ProjectIndex
