#include "projectindex.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>

#include <algorithm>
#include <filesystem>
#include <string>
#include <vector>

#include "project/decompproject.h"

namespace ProjectIndex {

namespace {

constexpr int kStoreVersion = 1;

// Every input DecompProject::open derives index content from. Stat-digested:
// size + mtime per file, plus the midi directory's *.mid listing (names only
// — .mid contents never enter the index) and the .porydaw sidecar listing
// whose registration meta unregistered songs absorb at discovery time.
// Residual staleness window: a rewrite that lands in the same size and FAT
// mtime tick; porydaw's own writes touch mtime, so this needs an external
// same-size-in-place edit to go unnoticed.
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

// A null QString binds through QVariant as SQL NULL; index text columns
// always store plain empty strings instead.
inline QString nz(const QString &text)
{
    return text.isNull() ? QStringLiteral("") : text;
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

void feedListing(QCryptographicHash *hash, const QString &dirPath, const QString &suffix)
{
    // Names-only walk: QDir::entryList pays a per-entry metadata stat on
    // macOS (hidden/bundle resource flags), which dominates the whole warm
    // open on a 1500-entry FAT32 checkout. std::filesystem reads dirents
    // bare; dotfiles (FAT32 AppleDouble twins like ._mus_foo.mid) are
    // skipped exactly like QDir's hidden-file rule.
    std::vector<std::string> names;
    std::error_code error;
    for (std::filesystem::directory_iterator it(dirPath.toStdString(), error), end;
         !error && it != end; it.increment(error)) {
        const std::string name = it->path().filename().string();
        if (!name.empty() && name[0] != '.' && name.ends_with(suffix.toStdString()))
            names.push_back(name);
    }
    std::sort(names.begin(), names.end());
    hash->addData(QByteArray::number(qint64(names.size())));
    hash->addData(":");
    for (const std::string &name : names) {
        hash->addData(name.c_str(), qint64(name.size()));
        hash->addData(",");
    }
    hash->addData("\n");
}

QJsonObject songToJson(const SongInfo &song)
{
    QJsonObject o;
    o.insert(QStringLiteral("label"), song.label);
    o.insert(QStringLiteral("constant"), song.constant);
    o.insert(QStringLiteral("player"), song.player);
    o.insert(QStringLiteral("midPath"), song.midPath);
    o.insert(QStringLiteral("id"), song.id);
    o.insert(QStringLiteral("hasMid"), song.hasMid);
    o.insert(QStringLiteral("hasCfg"), song.hasCfg);
    o.insert(QStringLiteral("registered"), song.registered);
    o.insert(QStringLiteral("gaps"), QJsonArray::fromStringList(song.registrationGaps));
    o.insert(QStringLiteral("rawFlags"), QJsonArray::fromStringList(song.cfg.rawFlags));
    o.insert(QStringLiteral("vgArg"), song.cfg.voicegroupArg);
    o.insert(QStringLiteral("masterVolume"), song.cfg.masterVolume);
    o.insert(QStringLiteral("reverb"), song.cfg.reverb);
    o.insert(QStringLiteral("priority"), song.cfg.priority);
    o.insert(QStringLiteral("exactGate"), song.cfg.exactGate);
    o.insert(QStringLiteral("extendedClocks"), song.cfg.extendedClocks);
    o.insert(QStringLiteral("noCompression"), song.cfg.noCompression);
    return o;
}

SongInfo songFromJson(const QJsonObject &o)
{
    SongInfo song;
    song.label = o.value(QLatin1String("label")).toString();
    song.constant = o.value(QLatin1String("constant")).toString();
    song.player = o.value(QLatin1String("player")).toString();
    song.midPath = o.value(QLatin1String("midPath")).toString();
    song.id = o.value(QLatin1String("id")).toInt();
    song.hasMid = o.value(QLatin1String("hasMid")).toBool();
    song.hasCfg = o.value(QLatin1String("hasCfg")).toBool();
    song.registered = o.value(QLatin1String("registered")).toBool();
    for (const auto &gap : o.value(QLatin1String("gaps")).toArray())
        song.registrationGaps.append(gap.toString());
    for (const auto &flag : o.value(QLatin1String("rawFlags")).toArray())
        song.cfg.rawFlags.append(flag.toString());
    song.cfg.voicegroupArg = o.value(QLatin1String("vgArg")).toString();
    song.cfg.masterVolume = o.value(QLatin1String("masterVolume")).toInt();
    song.cfg.reverb = o.value(QLatin1String("reverb")).toInt();
    song.cfg.priority = o.value(QLatin1String("priority")).toInt();
    song.cfg.exactGate = o.value(QLatin1String("exactGate")).toBool();
    song.cfg.extendedClocks = o.value(QLatin1String("extendedClocks")).toBool();
    song.cfg.noCompression = o.value(QLatin1String("noCompression")).toBool();
    return song;
}

QJsonDocument jsonDocument(const QString &root, const QByteArray &finger,
                           const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players)
{
    QJsonObject top;
    top.insert(QStringLiteral("version"), kStoreVersion);
    top.insert(QStringLiteral("root"), root);
    top.insert(QStringLiteral("fingerprint"), QString::fromLatin1(finger));

    QJsonArray songArray;
    for (const SongInfo &song : songs)
        songArray.append(songToJson(song));
    top.insert(QStringLiteral("songs"), songArray);

    QJsonArray playerArray;
    for (const MusicPlayer &player : players) {
        QJsonObject p;
        p.insert(QStringLiteral("name"), player.name);
        p.insert(QStringLiteral("number"), player.number);
        p.insert(QStringLiteral("trackCount"), player.trackCount);
        playerArray.append(p);
    }
    top.insert(QStringLiteral("players"), playerArray);
    return QJsonDocument(top);
}

bool loadJson(const QString &path, const QString &root, const QByteArray &finger,
              QVector<SongInfo> *songs, QVector<MusicPlayer> *players)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QJsonObject top = QJsonDocument::fromJson(file.readAll()).object();
    if (top.isEmpty() || top.value(QLatin1String("version")).toInt() != kStoreVersion ||
        top.value(QLatin1String("root")).toString() != root ||
        top.value(QLatin1String("fingerprint")).toString() != QString::fromLatin1(finger))
        return false;

    songs->clear();
    for (const auto &value : top.value(QLatin1String("songs")).toArray())
        songs->append(songFromJson(value.toObject()));
    players->clear();
    for (const auto &value : top.value(QLatin1String("players")).toArray()) {
        const QJsonObject o = value.toObject();
        MusicPlayer player;
        player.name = o.value(QLatin1String("name")).toString();
        player.number = o.value(QLatin1String("number")).toInt();
        player.trackCount = o.value(QLatin1String("trackCount")).toInt(-1);
        players->append(player);
    }
    return !songs->isEmpty();
}

bool saveJson(const QString &path, const QString &root, const QByteArray &finger,
              const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(jsonDocument(root, finger, songs, players).toJson(QJsonDocument::Compact));
    return file.commit();
}

QString sqlConnectionName()
{
    static int counter = 0;
    return QStringLiteral("porydaw-project-index-%1").arg(++counter);
}

// True when the store's meta row matches expectation.
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
            QSqlQuery query(db);
            ok = query.exec(QStringLiteral("SELECT label, constant, player, mid_path, has_mid,"
                                           " has_cfg, registered, gaps, raw_flags, vg_arg,"
                                           " master_volume, reverb, priority, exact_gate,"
                                           " extended_clocks, no_compression FROM songs"
                                           " ORDER BY idx"));
            int idx = 0;
            while (ok && query.next()) {
                SongInfo song;
                song.id = idx++;
                song.label = query.value(0).toString();
                song.constant = query.value(1).toString();
                song.player = query.value(2).toString();
                song.midPath = query.value(3).toString();
                song.hasMid = query.value(4).toInt() != 0;
                song.hasCfg = query.value(5).toInt() != 0;
                song.registered = query.value(6).toInt() != 0;
                song.registrationGaps = query.value(7).toString().split(u',', Qt::SkipEmptyParts);
                song.cfg.rawFlags = query.value(8).toString().split(u',', Qt::SkipEmptyParts);
                song.cfg.voicegroupArg = query.value(9).toString();
                song.cfg.masterVolume = query.value(10).toInt();
                song.cfg.reverb = query.value(11).toInt();
                song.cfg.priority = query.value(12).toInt();
                song.cfg.exactGate = query.value(13).toInt() != 0;
                song.cfg.extendedClocks = query.value(14).toInt() != 0;
                song.cfg.noCompression = query.value(15).toInt() != 0;
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
        if (!ok)
            songs->clear();
        return ok;
    }
}

bool saveSqlite(const QString &path, const QString &root, const QByteArray &finger,
                const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players)
{
    // Write a scratch database, then swap it over destination atomically.
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

        QSqlQuery query(db);
        // journal_mode returns its new value as a row; drain it so the
        // statement cannot stay active across the writes below.
        query.exec(QStringLiteral("PRAGMA journal_mode=OFF"));
        query.next();

        const auto run = [&ok, &query](const QString &sql) {
            if (!query.exec(sql))
                ok = false;
        };
        run(QStringLiteral("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)"));
        run(QStringLiteral("CREATE TABLE songs(idx INTEGER PRIMARY KEY, label TEXT NOT NULL,"
                           " constant TEXT NOT NULL, player TEXT NOT NULL, mid_path TEXT NOT NULL,"
                           " has_mid INTEGER NOT NULL, has_cfg INTEGER NOT NULL,"
                           " registered INTEGER NOT NULL, gaps TEXT NOT NULL,"
                           " raw_flags TEXT NOT NULL, vg_arg TEXT NOT NULL,"
                           " master_volume INTEGER NOT NULL, reverb INTEGER NOT NULL,"
                           " priority INTEGER NOT NULL, exact_gate INTEGER NOT NULL,"
                           " extended_clocks INTEGER NOT NULL, no_compression INTEGER NOT NULL)"));
        run(QStringLiteral("CREATE TABLE players(idx INTEGER PRIMARY KEY,"
                           " name TEXT NOT NULL, number INTEGER NOT NULL,"
                           " track_count INTEGER NOT NULL)"));
        run(QStringLiteral("BEGIN"));
        if (!ok) {
            db = QSqlDatabase();
            QSqlDatabase::removeDatabase(connection);
            QFile::remove(tmp);
            return false;
        }

        query.prepare(QStringLiteral("INSERT INTO meta VALUES(:key, :value)"));
        const auto metaRow = [&](const QString &key, const QString &value) {
            query.bindValue(QStringLiteral(":key"), key);
            query.bindValue(QStringLiteral(":value"), value);
            ok = query.exec() && ok;
        };
        metaRow(QStringLiteral("version"), QString::number(kStoreVersion));
        metaRow(QStringLiteral("root"), root);
        metaRow(QStringLiteral("fingerprint"), QString::fromLatin1(finger));

        // 17 columns, 17 binds — an unbound placeholder becomes NULL and
        // trips NOT NULL, dropping every row silently.
        query.prepare(QStringLiteral("INSERT INTO songs VALUES("
                                     ":idx, :label, :constant, :player, :mid_path,"
                                     " :has_mid, :has_cfg, :registered, :gaps,"
                                     " :raw_flags, :vg_arg, :master_volume, :reverb,"
                                     " :priority, :exact_gate, :extended_clocks,"
                                     " :no_compression)"));
        for (int i = 0; i < songs.size(); ++i) {
            const SongInfo &song = songs[i];
            query.bindValue(QStringLiteral(":idx"), i);
            query.bindValue(QStringLiteral(":label"), nz(song.label));
            query.bindValue(QStringLiteral(":constant"), nz(song.constant));
            query.bindValue(QStringLiteral(":player"), nz(song.player));
            query.bindValue(QStringLiteral(":mid_path"), nz(song.midPath));
            query.bindValue(QStringLiteral(":has_mid"), int(song.hasMid));
            query.bindValue(QStringLiteral(":has_cfg"), int(song.hasCfg));
            query.bindValue(QStringLiteral(":registered"), int(song.registered));
            query.bindValue(QStringLiteral(":gaps"), nz(song.registrationGaps.join(u',')));
            query.bindValue(QStringLiteral(":raw_flags"), nz(song.cfg.rawFlags.join(u',')));
            query.bindValue(QStringLiteral(":vg_arg"), nz(song.cfg.voicegroupArg));
            query.bindValue(QStringLiteral(":master_volume"), song.cfg.masterVolume);
            query.bindValue(QStringLiteral(":reverb"), song.cfg.reverb);
            query.bindValue(QStringLiteral(":priority"), song.cfg.priority);
            query.bindValue(QStringLiteral(":exact_gate"), int(song.cfg.exactGate));
            query.bindValue(QStringLiteral(":extended_clocks"), int(song.cfg.extendedClocks));
            query.bindValue(QStringLiteral(":no_compression"), int(song.cfg.noCompression));
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
        run(ok ? QStringLiteral("COMMIT") : QStringLiteral("ROLLBACK"));

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

QByteArray fingerprint(const QString &projectRoot)
{
    QCryptographicHash hash(QCryptographicHash::Sha1);
    for (const char *relative : kIndexedFiles) {
        hash.addData(relative);
        hash.addData("\n");
        feedStat(&hash, projectRoot + QLatin1Char('/') + QLatin1String(relative));
    }
    feedListing(&hash, projectRoot + QStringLiteral("/sound/songs/midi"), QStringLiteral(".mid"));
    feedListing(&hash, projectRoot + QStringLiteral("/.porydaw"), QStringLiteral(".json"));
    return hash.result().toHex();
}

bool load(Backend backend, const QString &storeDir, const QString &projectRoot,
          const QByteArray &finger, QVector<SongInfo> *songs, QVector<MusicPlayer> *players)
{
    switch (backend) {
    case Backend::Sqlite:
        return loadSqlite(storePath(backend, storeDir), projectRoot, finger, songs, players);
    case Backend::Json:
        return loadJson(storePath(backend, storeDir), projectRoot, finger, songs, players);
    }
    return false;
}

bool save(Backend backend, const QString &storeDir, const QString &projectRoot,
          const QByteArray &finger, const QVector<SongInfo> &songs,
          const QVector<MusicPlayer> &players)
{
    switch (backend) {
    case Backend::Sqlite:
        return saveSqlite(storePath(backend, storeDir), projectRoot, finger, songs, players);
    case Backend::Json:
        return saveJson(storePath(backend, storeDir), projectRoot, finger, songs, players);
    }
    return false;
}

QString storePath(Backend backend, const QString &storeDir)
{
    switch (backend) {
    case Backend::Sqlite:
        return storeDir + QStringLiteral("/project-index.sqlite");
    case Backend::Json:
        return storeDir + QStringLiteral("/project-index.json");
    }
    return storeDir;
}

} // namespace ProjectIndex
