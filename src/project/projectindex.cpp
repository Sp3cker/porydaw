#include "projectindex.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QThread>

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <optional>
#include <string>
#include <system_error>

#include "project/decompproject.h"

namespace ProjectIndex {

namespace {

constexpr int kStoreVersion = 3;
constexpr auto kManifestPrefix = "porydaw-project-index-generation:\n";
std::atomic<SourceAccessObserverForTesting> s_sourceAccessObserver{nullptr};

// Files and listings digested by fingerprint().
constexpr const char *kIndexedFiles[] = {
    "sound/song_table.inc",
    "include/constants/songs.h",
    "sound/songs/midi/midi.cfg",
    "sound/music_player_table.inc",
    "charmap.txt",
    "ld_script.ld",
    "src/debug.c",
    "songs.mk",
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
    return QDir(root).absoluteFilePath(QStringLiteral("sound/songs/midi/") + label +
                                       QStringLiteral(".mid"));
}

inline QString encodeList(const QStringList &list)
{
    return QString::fromUtf8(
        QJsonDocument(QJsonArray::fromStringList(list)).toJson(QJsonDocument::Compact));
}

inline bool decodeList(const QString &jsonText, QStringList *result)
{
    const QJsonDocument document = QJsonDocument::fromJson(jsonText.toUtf8());
    if (document.isNull() || !document.isArray())
        return false;
    const QJsonArray array = document.array();
    result->clear();
    result->reserve(array.size());
    for (const auto &val : array) {
        if (!val.isString())
            return false;
        result->append(val.toString());
    }
    return true;
}

bool isMissingDirectory(const std::error_code &error)
{
    return error == std::errc::no_such_file_or_directory;
}

bool feedFile(QCryptographicHash *hash, const QString &path)
{
    std::error_code statusError;
#if defined(_WIN32)
    const std::filesystem::file_status status =
        std::filesystem::status(std::filesystem::path(path.toStdWString()), statusError);
#else
    const std::filesystem::file_status status =
        std::filesystem::status(std::filesystem::path(path.toStdString()), statusError);
#endif
    if (statusError && !isMissingDirectory(statusError))
        return false;
    if (statusError || !std::filesystem::exists(status)) {
        hash->addData("absent\n");
        return true;
    }
    if (!std::filesystem::is_regular_file(status))
        return false;

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QCryptographicHash contents(QCryptographicHash::Sha1);
    if (!contents.addData(&file))
        return false;
    hash->addData(contents.result());
    hash->addData("\n");
    return true;
}

void feedListingNames(QCryptographicHash *hash, const QStringList &names)
{
    hash->addData(QByteArray::number(qsizetype(names.size())));
    hash->addData(":");
    hash->addData(names.join(u'\0').toUtf8());
    hash->addData("\n");
}

QString sqlConnectionName()
{
    static std::atomic<int> counter{0};
    return QStringLiteral("porydaw-project-index-%1").arg(++counter);
}

QString manifestPath(const QString &storeDir)
{
    return QDir(storeDir).filePath(QStringLiteral("project-index.current"));
}

QString legacyStorePath(const QString &storeDir)
{
    return QDir(storeDir).filePath(QStringLiteral("project-index.sqlite"));
}

void reportSourceAccess(const QString &path)
{
    const auto observer = s_sourceAccessObserver.load(std::memory_order_acquire);
    if (observer)
        observer(path);
}

std::optional<QString> generationPath(const QString &storeDir)
{
    // nullopt: no manifest, so a legacy store remains readable. An empty
    // QString: a manifest exists but is invalid, so never trust that legacy
    // store as a fallback.
    QFile manifest(manifestPath(storeDir));
    if (!manifest.exists())
        return std::nullopt;
    if (!manifest.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString{};
    const QByteArray contents = manifest.readAll();
    const QByteArray prefix(kManifestPrefix);
    if (!contents.startsWith(prefix))
        return QString{};
    const QString name = QString::fromUtf8(contents.mid(prefix.size()).trimmed());
    if (name.isEmpty() || QFileInfo(name).fileName() != name || name.contains(u'/') ||
        name.contains(u'\\'))
        return QString{};
    return QDir(storeDir).filePath(name);
}

QString resolvedStorePath(const QString &storeDir)
{
    const auto generated = generationPath(storeDir);
    if (!generated)
        return legacyStorePath(storeDir);
    return *generated;
}

bool writeGenerationManifest(const QString &storeDir, const QString &generationName,
                             QString *error)
{
    QSaveFile manifest(manifestPath(storeDir));
    if (!manifest.open(QIODevice::WriteOnly)) {
        if (error)
            *error = manifest.errorString();
        return false;
    }
    const QByteArray contents = QByteArray(kManifestPrefix) + generationName.toUtf8() + '\n';
    if (manifest.write(contents) != contents.size()) {
        manifest.cancelWriting();
        if (error)
            *error = manifest.errorString();
        return false;
    }
    if (manifest.commit())
        return true;
    if (error)
        *error = manifest.errorString();
    return false;
}

bool publishGeneration(const QString &storeDir, const QString &generationName, QString *error)
{
    // Readers only hold the small manifest while resolving a generation, but
    // Windows may still reject a replacement during that narrow close race.
    // Retrying leaves the previous manifest/database valid on every failure.
    auto publishError = QString{};
    for (int attempt = 0; attempt < 3; ++attempt) {
        if (writeGenerationManifest(storeDir, generationName, &publishError))
            return true;
        if (attempt < 2)
            QThread::msleep(20u << attempt);
    }
    if (error)
        *error = publishError;
    return false;
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

bool loadSqlite(const QString &path, const QString &storedRoot, const QString &projectRoot,
                const QByteArray *finger, QVector<SongInfo> *songs, QVector<MusicPlayer> *players)
{
    if (!QFileInfo::exists(path))
        return false;
    const QString connection = sqlConnectionName();
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
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
                 metaMatches(&query, QStringLiteral("root"), storedRoot) &&
                 (!finger || metaMatches(&query, QStringLiteral("fingerprint"),
                                         QString::fromLatin1(*finger)));
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
                QStringList gaps;
                QStringList rawFlags;
                if (!decodeList(query.value(6).toString(), &gaps) ||
                    !decodeList(query.value(7).toString(), &rawFlags)) {
                    ok = false;
                    break;
                }
                SongInfo song;
                song.id = idx++;
                song.label = query.value(0).toString();
                song.constant = query.value(1).toString();
                song.player = query.value(2).toString();
                song.hasMid = query.value(3).toInt() != 0;
                song.midPath = deriveMidPath(projectRoot, song.label, song.hasMid);
                song.hasCfg = query.value(4).toInt() != 0;
                song.registered = query.value(5).toInt() != 0;
                song.registrationGaps = gaps;
                song.cfg = SongCfg::fromFlags(rawFlags);
                songs->append(song);
            }
            if (query.lastError().isValid())
                ok = false;
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

void discardSqliteScratch(const QString &path)
{
    QFile::remove(path);
    QFile::remove(path + QStringLiteral("-journal"));
    QFile::remove(path + QStringLiteral("-wal"));
    QFile::remove(path + QStringLiteral("-shm"));
}

bool saveSqlite(const QString &storeDir, const QString &root, const QByteArray &finger,
                const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players, QString *error)
{
    // Generations are immutable after publishing. Keeping old generations
    // avoids replacing a database an SQLite reader still holds open on Windows;
    // the small manifest is the only atomically replaced file. Do not prune
    // here: another process can have resolved an old manifest just before a
    // write and still need that generation to open successfully.
    QTemporaryFile scratch(
        QDir(storeDir).filePath(QStringLiteral("project-index-XXXXXX.sqlite")));
    if (!scratch.open()) {
        if (error)
            *error = scratch.errorString();
        return false;
    }
    const QString tmp = scratch.fileName();
    scratch.setAutoRemove(false);
    scratch.close();
    bool ok = true;

    const QString connection = sqlConnectionName();
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
        db.setDatabaseName(tmp);
        if (!db.open()) {
            if (error)
                *error = db.lastError().text();
            db = QSqlDatabase();
            QSqlDatabase::removeDatabase(connection);
            discardSqliteScratch(tmp);
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

    QFile::remove(tmp + QStringLiteral("-journal"));
    QFile::remove(tmp + QStringLiteral("-wal"));
    QFile::remove(tmp + QStringLiteral("-shm"));
    if (!ok) {
        if (error)
            *error = QStringLiteral("SQLite could not write the project index.");
        discardSqliteScratch(tmp);
        return false;
    }
    if (publishGeneration(storeDir, QFileInfo(tmp).fileName(), error))
        return true;
    discardSqliteScratch(tmp);
    return false;
}

bool matchesSqlite(const QString &path, const QString &storedRoot, const QByteArray &finger)
{
    if (!QFileInfo::exists(path))
        return false;
    const QString connection = sqlConnectionName();
    QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connection);
    db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
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
             metaMatches(&query, QStringLiteral("root"), storedRoot) &&
             metaMatches(&query, QStringLiteral("fingerprint"), QString::fromLatin1(finger));
    }
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(connection);
    return ok;
}

} // namespace

void setSourceAccessObserverForTesting(SourceAccessObserverForTesting observer)
{
    s_sourceAccessObserver.store(observer, std::memory_order_release);
}

bool listFileNames(const QString &dirPath, const QString &suffix, QStringList *names)
{
    Q_ASSERT(names);
    reportSourceAccess(dirPath);
    // Bare dirent walk skipping dotfiles and filtering by suffix. A missing
    // optional directory is a valid empty listing; any other failure is kept
    // distinct so a transient SMB error cannot be cached as "no files".
    names->clear();
    std::error_code error;
#if defined(_WIN32)
    const std::filesystem::path rootPath(dirPath.toStdWString());
#else
    const std::filesystem::path rootPath(dirPath.toStdString());
#endif
    std::filesystem::directory_iterator it(rootPath, error);
    if (error)
        return isMissingDirectory(error);
    const std::filesystem::directory_iterator end;
    while (it != end) {
#if defined(_WIN32)
        const QString fileName = QString::fromStdWString(it->path().filename().wstring());
#else
        const QString fileName = QString::fromStdString(it->path().filename().string());
#endif
        if (!fileName.isEmpty() && !fileName.startsWith(u'.') && fileName.endsWith(suffix)) {
            std::error_code statusError;
            const bool regular = it->is_regular_file(statusError);
            if (statusError)
                return false;
            if (regular)
                names->append(fileName);
        }
        it.increment(error);
        if (error) {
            names->clear();
            return false;
        }
    }
    std::sort(names->begin(), names->end());
    return true;
}

QStringList listFileNames(const QString &dirPath, const QString &suffix)
{
    QStringList names;
    listFileNames(dirPath, suffix, &names);
    return names;
}

bool fingerprint(const QString &projectRoot, const QStringList &midiSongNames,
                 const QStringList &sidecarJsonNames, QByteArray *result)
{
    Q_ASSERT(result);
    reportSourceAccess(projectRoot);
    QCryptographicHash hash(QCryptographicHash::Sha1);
    for (const char *relative : kIndexedFiles) {
        hash.addData(relative);
        hash.addData("\n");
        if (!feedFile(&hash, projectRoot + QLatin1Char('/') + QLatin1String(relative)))
            return false;
    }
    feedListingNames(&hash, midiSongNames);
    feedListingNames(&hash, sidecarJsonNames);
    for (const QString &sidecar : sidecarJsonNames) {
        hash.addData(".porydaw/");
        hash.addData(sidecar.toUtf8());
        hash.addData("\n");
        if (!feedFile(&hash, projectRoot + QStringLiteral("/.porydaw/") + sidecar))
            return false;
    }
    *result = hash.result().toHex();
    return true;
}

QByteArray fingerprint(const QString &projectRoot, const QStringList &midiSongNames,
                       const QStringList &sidecarJsonNames)
{
    QByteArray result;
    fingerprint(projectRoot, midiSongNames, sidecarJsonNames, &result);
    return result;
}

static QString lexicalRoot(const QString &projectRoot)
{
    return QDir::cleanPath(QDir(projectRoot).absolutePath());
}

bool collectInputs(const QString &projectRoot, Inputs *inputs, QString *error)
{
    Q_ASSERT(inputs);
    reportSourceAccess(projectRoot);
    auto collected = Inputs{};
    const QString midiDir = QDir(projectRoot).filePath(QStringLiteral("sound/songs/midi"));
    if (!QDir(midiDir).exists() ||
        !listFileNames(midiDir, QStringLiteral(".mid"), &collected.midiSongNames)) {
        if (error)
            *error = QStringLiteral("Cannot list project MIDI files: %1").arg(midiDir);
        return false;
    }

    const QString sidecarDir = QDir(projectRoot).filePath(QStringLiteral(".porydaw"));
    if (!listFileNames(sidecarDir, QStringLiteral(".json"), &collected.sidecarJsonNames) ||
        !fingerprint(projectRoot, collected.midiSongNames, collected.sidecarJsonNames,
                     &collected.fingerprint)) {
        if (error)
            *error = QStringLiteral("Cannot read project index inputs: %1").arg(projectRoot);
        return false;
    }
    *inputs = std::move(collected);
    return true;
}

bool loadCached(const QString &storeDir, const QString &projectRoot, QVector<SongInfo> *songs,
                QVector<MusicPlayer> *players)
{
    if (storeDir.isEmpty())
        return false;
    const QString path = resolvedStorePath(storeDir);
    return !path.isEmpty() && loadSqlite(path, lexicalRoot(projectRoot), projectRoot, nullptr, songs,
                                         players);
}

bool matches(const QString &storeDir, const QString &projectRoot, const QByteArray &finger)
{
    if (storeDir.isEmpty())
        return false;
    const QString path = resolvedStorePath(storeDir);
    return !path.isEmpty() && matchesSqlite(path, lexicalRoot(projectRoot), finger);
}

bool load(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          QVector<SongInfo> *songs, QVector<MusicPlayer> *players)
{
    if (storeDir.isEmpty())
        return false;
    const QString path = resolvedStorePath(storeDir);
    return !path.isEmpty() && loadSqlite(path, lexicalRoot(projectRoot), projectRoot, &finger, songs,
                                         players);
}

bool save(const QString &storeDir, const QString &projectRoot, const QByteArray &finger,
          const QVector<SongInfo> &songs, const QVector<MusicPlayer> &players, QString *error)
{
    if (storeDir.isEmpty()) {
        if (error)
            *error = QStringLiteral("No local project-index directory is configured.");
        return false;
    }
    // Ensure destination directory exists.
    if (!QDir().mkpath(storeDir)) {
        if (error)
            *error = QStringLiteral("Cannot create local project-index directory: %1").arg(storeDir);
        return false;
    }
    const QString path = storePath(storeDir);
    QLockFile lock(path + QStringLiteral(".lock"));
    if (!lock.tryLock()) {
        if (error)
            *error = QStringLiteral("The local project index is busy: %1").arg(path);
        return false;
    }
    auto saveError = QString{};
    if (saveSqlite(storeDir, lexicalRoot(projectRoot), finger, songs, players, &saveError))
        return true;
    if (error)
        *error = QStringLiteral("Cannot publish the local project index: %1 (%2)")
                     .arg(path, saveError);
    return false;
}

QString storePath(const QString &storeDir)
{
    return manifestPath(storeDir);
}

QString defaultStoreDir(const QString &projectRoot)
{
    if (!qEnvironmentVariableIsEmpty("PORYDAW_DISABLE_INDEX_CACHE"))
        return {};
    const QString effective = lexicalRoot(projectRoot);
    if (effective.isEmpty())
        return {};
    const QString key = QString::fromLatin1(
        QCryptographicHash::hash(effective.toUtf8(), QCryptographicHash::Sha1).toHex());
    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (appData.isEmpty())
        return {};
    return QDir(appData).filePath(QStringLiteral("index-cache/") + key);
}

} // namespace ProjectIndex
