#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QScopeGuard>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

#include <atomic>
#include <cstdio>
#include <deque>
#include <utility>
#include <variant>

#include "project/decompproject.h"
#include "project/projectindex.h"
#include "project/projectworkspace.h"

// --projectworkspacecachecheck <projectRoot>: prove the actual workspace
// startup order for a stale, warmed SQLite index. The source tree is hidden
// until Workspace Ready, so Ready can only be a cache hydrate. The selected
// startup song then reaches VoicegroupBound before deferred catalog work and
// index validation rebuild the SQLite store.

namespace {

constexpr auto kLastProjectDirKey = "lastProjectDir";
constexpr auto kLastOpenSongsKey = "lastOpenSongs";
constexpr auto kLastSongLabelKey = "lastSongLabel";
constexpr auto kCacheDisableVariable = "PORYDAW_DISABLE_INDEX_CACHE";
std::atomic_int indexSourceAccesses{0};

using Entry = std::variant<ProjectState, SongUpdate>;

void recordIndexSourceAccess(const QString &)
{
    indexSourceAccesses.fetch_add(1, std::memory_order_relaxed);
}

class Check final
{
  public:
    explicit Check(int *failures) : m_failures(failures) {}

    bool that(bool condition, const char *what) const
    {
        if (!condition) {
            std::fprintf(stderr, "projectworkspacecachecheck: FAIL: %s\n", what);
            ++*m_failures;
        }
        return condition;
    }

  private:
    int *m_failures;
};

class CacheEnvironment final
{
  public:
    CacheEnvironment()
        : m_cacheWasDisabled(qEnvironmentVariableIsSet(kCacheDisableVariable))
        , m_cacheDisableValue(qgetenv(kCacheDisableVariable))
        , m_testModeWasEnabled(QStandardPaths::isTestModeEnabled())
    {
        QStandardPaths::setTestModeEnabled(true);
        qunsetenv(kCacheDisableVariable);
    }

    ~CacheEnvironment()
    {
        if (m_cacheWasDisabled)
            qputenv(kCacheDisableVariable, m_cacheDisableValue);
        else
            qunsetenv(kCacheDisableVariable);
        QStandardPaths::setTestModeEnabled(m_testModeWasEnabled);
    }

  private:
    bool m_cacheWasDisabled = false;
    QByteArray m_cacheDisableValue;
    bool m_testModeWasEnabled = false;
};

bool containsSong(const QVector<SongInfo> &songs, const QString &label)
{
    for (const SongInfo &song : songs)
        if (song.label == label)
            return true;
    return false;
}

void clearStartupSettings()
{
    QSettings settings;
    settings.remove(QLatin1String(kLastProjectDirKey));
    settings.remove(QLatin1String(kLastOpenSongsKey));
    settings.remove(QLatin1String(kLastSongLabelKey));
}

class WarmedCache final
{
  public:
    explicit WarmedCache(QString projectRoot)
        : m_projectRoot(std::move(projectRoot))
        , m_cacheDir(ProjectIndex::defaultStoreDir(m_projectRoot))
        , m_probeLabel(QStringLiteral("mus_workspace_cache_probe"))
        , m_probePath(QDir(m_projectRoot).filePath(QStringLiteral("sound/songs/midi/") +
                                                    m_probeLabel + QStringLiteral(".mid")))
    {}

    ~WarmedCache()
    {
        QFile::remove(m_probePath);
        QDir(m_cacheDir).removeRecursively();
    }

    bool prepare(const Check &check)
    {
        if (!check.that(!m_cacheDir.isEmpty(), "could not determine the test cache directory"))
            return false;
        QDir(m_cacheDir).removeRecursively();
        if (QFileInfo::exists(m_probePath) &&
            !check.that(QFile::remove(m_probePath), "could not remove a stale cache probe MIDI"))
            return false;

        auto error = QString{};
        if (!check.that(ProjectIndex::collectInputs(m_projectRoot, &m_before, &error),
                        "could not collect the initial project index inputs"))
            return false;
        auto primer = DecompProject{};
        primer.setIndexCache(m_cacheDir);
        if (!check.that(primer.openFresh(m_projectRoot, &error), "could not warm the SQLite cache") ||
            !check.that(ProjectIndex::matches(m_cacheDir, m_projectRoot, m_before.fingerprint),
                        "warming did not produce a matching SQLite cache"))
            return false;

        const QString source = QDir(m_projectRoot).filePath(
            QStringLiteral("sound/songs/midi/mus_petalburg.mid"));
        if (!check.that(QFile::copy(source, m_probePath), "could not add the stale-cache probe MIDI") ||
            !check.that(ProjectIndex::collectInputs(m_projectRoot, &m_after, &error),
                        "could not collect the changed project index inputs") ||
            !check.that(m_before.fingerprint != m_after.fingerprint,
                        "adding the probe MIDI did not make the cache stale") ||
            !check.that(!ProjectIndex::matches(m_cacheDir, m_projectRoot, m_after.fingerprint),
                        "the warmed cache matched the changed project before startup"))
            return false;
        return true;
    }

    const QString &cacheDir() const { return m_cacheDir; }
    const QString &probeLabel() const { return m_probeLabel; }
    const QByteArray &changedFingerprint() const { return m_after.fingerprint; }

  private:
    QString m_projectRoot;
    QString m_cacheDir;
    QString m_probeLabel;
    QString m_probePath;
    ProjectIndex::Inputs m_before;
    ProjectIndex::Inputs m_after;
};

class HiddenSource final
{
  public:
    explicit HiddenSource(const QString &projectRoot)
        : m_soundDir(QDir(projectRoot).filePath(QStringLiteral("sound")))
        , m_offlineDir(QDir(projectRoot).filePath(QStringLiteral("sound.cache-check-offline")))
    {}

    ~HiddenSource() { restore(); }

    bool hide(const Check &check)
    {
        const QFileInfo offlineInfo(m_offlineDir);
        if (offlineInfo.exists()) {
            const bool removed = offlineInfo.isDir() ? QDir(m_offlineDir).removeRecursively()
                                                      : QFile::remove(m_offlineDir);
            if (!check.that(removed, "could not remove a stale hidden-source directory"))
                return false;
        }
        if (!check.that(QDir().rename(m_soundDir, m_offlineDir),
                        "could not hide the source tree before workspace startup"))
            return false;
        m_hidden = true;
        return true;
    }

    bool restore()
    {
        if (!m_hidden)
            return true;
        if (!QDir().rename(m_offlineDir, m_soundDir))
            return false;
        m_hidden = false;
        return true;
    }

    bool isHidden() const { return m_hidden; }

  private:
    QString m_soundDir;
    QString m_offlineDir;
    bool m_hidden = false;
};

class WorkspaceLog final
{
  public:
    void wire(ProjectWorkspace &workspace)
    {
        QObject::connect(&workspace, &ProjectWorkspace::projectStatePublished, &workspace,
                         [this](ProjectState state) { record(Entry{std::move(state)}); });
        QObject::connect(&workspace, &ProjectWorkspace::songUpdatePublished, &workspace,
                         [this](SongUpdate update) { record(Entry{std::move(update)}); });
    }

    const ProjectState *lastState() const
    {
        for (auto it = m_entries.rbegin(); it != m_entries.rend(); ++it)
            if (const auto *state = std::get_if<ProjectState>(&*it))
                return state;
        return nullptr;
    }

    template <typename Predicate>
    int indexOf(Predicate predicate) const
    {
        for (std::size_t i = 0; i < m_entries.size(); ++i)
            if (predicate(m_entries[i]))
                return int(i);
        return -1;
    }

    template <typename Predicate>
    bool waitFor(Predicate predicate, const Check &check, const char *what)
    {
        auto elapsed = QElapsedTimer{};
        elapsed.start();
        auto timer = QTimer{};
        timer.setInterval(20);
        QObject::connect(&timer, &QTimer::timeout, &m_loop, &QEventLoop::quit);
        timer.start();
        while (!predicate() && elapsed.elapsed() < 30000)
            m_loop.exec();
        timer.stop();
        return check.that(predicate(), what);
    }

  private:
    void record(Entry entry)
    {
        m_entries.push_back(std::move(entry));
        m_loop.quit();
    }

    QEventLoop m_loop;
    std::deque<Entry> m_entries;
};

bool isReady(const ProjectState *state)
{
    return state && state->state == ProjectOpenState::Ready;
}

} // namespace

int runProjectWorkspaceCacheCheck(const QString &projectRoot)
{
    auto failures = 0;
    const Check check(&failures);
    const CacheEnvironment cacheEnvironment;
    clearStartupSettings();
    const auto clearSettings = qScopeGuard([] { clearStartupSettings(); });

    const auto route101 = SongName::create(QStringLiteral("mus_route101"));
    if (!check.that(route101.has_value(), "fixture song label was rejected as an identity"))
        return 1;

    auto cache = WarmedCache(projectRoot);
    if (!cache.prepare(check))
        return 1;
    {
        QSettings settings;
        settings.setValue(QLatin1String(kLastProjectDirKey), projectRoot);
        settings.setValue(QLatin1String(kLastOpenSongsKey), QStringList{route101->value()});
        settings.setValue(QLatin1String(kLastSongLabelKey), route101->value());
        settings.sync();
    }

    auto source = HiddenSource(projectRoot);
    if (!source.hide(check))
        return 1;
    indexSourceAccesses.store(0, std::memory_order_relaxed);
    ProjectIndex::setSourceAccessObserverForTesting(&recordIndexSourceAccess);
    const auto clearSourceAccessObserver =
        qScopeGuard([] { ProjectIndex::setSourceAccessObserverForTesting(nullptr); });

    auto log = WorkspaceLog{};
    auto readyWhileSourceOffline = false;
    auto readyUsedCachedSnapshot = false;
    auto readyCatalogWasEmpty = false;
    auto cacheStillStaleAtBound = false;
    {
        auto workspace = ProjectWorkspace{};
        log.wire(workspace);
        QObject::connect(
            &workspace, &ProjectWorkspace::projectStatePublished, &workspace,
            [&](const ProjectState &state) {
                if (!source.isHidden() ||
                    (state.state != ProjectOpenState::Ready && state.state != ProjectOpenState::Failed))
                    return;
                if (state.state == ProjectOpenState::Ready) {
                    readyWhileSourceOffline = true;
                    readyUsedCachedSnapshot = !containsSong(state.snapshot.songs(), cache.probeLabel());
                    readyCatalogWasEmpty = state.catalog.groupArgs.isEmpty();
                }
                check.that(source.restore(), "could not restore the source tree from the Ready callback");
            });
        QObject::connect(&workspace, &ProjectWorkspace::songUpdatePublished, &workspace,
                         [&](const SongUpdate &update) {
                             if (update.song == *route101 &&
                                 std::holds_alternative<VoicegroupBound>(update.payload)) {
                                 cacheStillStaleAtBound = !ProjectIndex::matches(
                                     cache.cacheDir(), projectRoot, cache.changedFingerprint());
                             }
                         });

        if (!log.waitFor(
                [&] {
                    const ProjectState *state = log.lastState();
                    return state && (state->state == ProjectOpenState::Ready ||
                                     state->state == ProjectOpenState::Failed);
                },
                check, "cache-backed workspace startup did not settle"))
            return 1;
        const ProjectState *initial = log.lastState();
        if (!check.that(isReady(initial), "workspace did not reach Ready while the source was unavailable") ||
            !check.that(readyWhileSourceOffline,
                        "Workspace Ready was not published while the source was hidden") ||
            !check.that(readyUsedCachedSnapshot,
                        "Workspace Ready did not receive the stale cached song snapshot") ||
            !check.that(readyCatalogWasEmpty,
                        "Workspace ran the catalog scan before a startup song was playable") ||
            !check.that(indexSourceAccesses.load(std::memory_order_relaxed) == 0,
                        "project-index source discovery ran before Workspace Ready"))
            return 1;

        const auto reachedBound = [&] {
            return log.indexOf([&](const Entry &entry) {
                       const auto *update = std::get_if<SongUpdate>(&entry);
                       return update && update->song == *route101 &&
                              std::holds_alternative<VoicegroupBound>(update->payload);
                   }) >= 0;
        };
        if (!log.waitFor(reachedBound, check, "cached startup song did not reach VoicegroupBound"))
            return 1;

        const int readyIndex = log.indexOf([](const Entry &entry) {
            const auto *state = std::get_if<ProjectState>(&entry);
            return state && state->state == ProjectOpenState::Ready;
        });
        const int boundIndex = log.indexOf([&](const Entry &entry) {
            const auto *update = std::get_if<SongUpdate>(&entry);
            return update && update->song == *route101 &&
                   std::holds_alternative<VoicegroupBound>(update->payload);
        });
        const int catalogIndex = log.indexOf([](const Entry &entry) {
            const auto *state = std::get_if<ProjectState>(&entry);
            return state && !state->catalog.groupArgs.isEmpty();
        });
        check.that(readyIndex >= 0 && readyIndex < boundIndex,
                   "the startup song became ready before Workspace Ready");
        check.that(catalogIndex < 0 || catalogIndex > boundIndex,
                   "catalog work published before the startup song became playable");
        check.that(cacheStillStaleAtBound,
                   "SQLite re-indexing ran before the startup song reached VoicegroupBound");
        check.that(indexSourceAccesses.load(std::memory_order_relaxed) == 0,
                   "project-index source discovery ran before the startup song reached VoicegroupBound");

        const auto cacheReindexed = [&] {
            auto songs = QVector<SongInfo>{};
            auto players = QVector<MusicPlayer>{};
            return ProjectIndex::load(cache.cacheDir(), projectRoot, cache.changedFingerprint(), &songs,
                                      &players) &&
                   containsSong(songs, cache.probeLabel());
        };
        const auto freshSnapshotPublished = [&] {
            const ProjectState *state = log.lastState();
            return isReady(state) && containsSong(state->snapshot.songs(), cache.probeLabel());
        };
        if (!log.waitFor(cacheReindexed, check,
                         "deferred SQLite re-indexing did not refresh the changed project") ||
            !log.waitFor(freshSnapshotPublished, check,
                         "deferred re-indexing did not publish the fresh project snapshot"))
            return 1;
        const int catalogAfterReindex = log.indexOf([](const Entry &entry) {
            const auto *state = std::get_if<ProjectState>(&entry);
            return state && !state->catalog.groupArgs.isEmpty();
        });
        check.that(catalogAfterReindex > boundIndex,
                   "deferred catalog publication did not follow the playable startup song");
    }
    if (!check.that(!source.isHidden(), "the source tree was not restored after workspace startup"))
        return 1;

    // A user-driven project open has no restored song command. Its deferred
    // maintenance must still run after Ready instead of remaining pending.
    clearStartupSettings();
    {
        auto noStartup = ProjectWorkspace{};
        auto noStartupLog = WorkspaceLog{};
        noStartupLog.wire(noStartup);
        noStartup.openProject(OpenProjectInput{projectRoot});
        if (!noStartupLog.waitFor([&] { return isReady(noStartupLog.lastState()); }, check,
                                  "user-driven cache-backed open did not reach Ready") ||
            !noStartupLog.waitFor(
                [&] {
                    const ProjectState *state = noStartupLog.lastState();
                    return isReady(state) && !state->catalog.groupArgs.isEmpty();
                },
                check, "an open with no startup song did not run deferred catalog work"))
            return 1;
    }

    if (failures == 0)
        std::printf("projectworkspacecachecheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
