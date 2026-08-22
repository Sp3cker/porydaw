#include <cstdio>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <QStringList>
#include <QVector>

#include "project/decompproject.h"
#include "project/projectindex.h"
#include "project/songregistry.h"

// End-to-end tests for persistent SQLite project indexing.
int runProjectIndexCheck(const QString &scratchProject, const QString &scratchDir)
{
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "projectindexcheck: FAIL: %s\n", what);
        failures++;
    };
    if (!QDir(scratchProject).exists()) {
        std::fprintf(stderr, "projectindexcheck: scratch project not found: %s\n",
                     qUtf8Printable(scratchProject));
        return 1;
    }

    const auto writeBytes = [](const QString &path, const QByteArray &bytes) {
        QFile file(path);
        return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
    };
    const auto projectFingerprint = [](const QString &projectRoot) {
        const QStringList midiSongs = ProjectIndex::listFileNames(
            projectRoot + QStringLiteral("/sound/songs/midi"), QStringLiteral(".mid"));
        const QStringList sidecars = ProjectIndex::listFileNames(
            projectRoot + QStringLiteral("/.porydaw"), QStringLiteral(".json"));
        return ProjectIndex::fingerprint(projectRoot, midiSongs, sidecars);
    };
    const auto findSong = [](const QVector<SongInfo> &songs, const QString &label) {
        for (const SongInfo &song : songs)
            if (song.label == label)
                return &song;
        return static_cast<const SongInfo *>(nullptr);
    };
    const auto songEquals = [](const SongInfo &a, const SongInfo &b) {
        return a.id == b.id && a.label == b.label && a.constant == b.constant &&
               a.player == b.player && a.midPath == b.midPath && a.hasMid == b.hasMid &&
               a.hasCfg == b.hasCfg && a.registered == b.registered &&
               a.registrationGaps == b.registrationGaps && a.cfg.rawFlags == b.cfg.rawFlags &&
               a.cfg.voicegroupArg == b.cfg.voicegroupArg &&
               a.cfg.masterVolume == b.cfg.masterVolume && a.cfg.reverb == b.cfg.reverb &&
               a.cfg.priority == b.cfg.priority && a.cfg.exactGate == b.cfg.exactGate &&
               a.cfg.extendedClocks == b.cfg.extendedClocks &&
               a.cfg.noCompression == b.cfg.noCompression;
    };

    // Baseline un-cached scan.
    auto error = QString{};
    DecompProject baseline;
    if (!baseline.open(scratchProject, &error)) {
        std::fprintf(stderr, "projectindexcheck: baseline open: %s\n", qUtf8Printable(error));
        return 1;
    }
    const int baselineSongCount = baseline.songs().size();
    const SongInfo *baselineRoute101 = findSong(baseline.songs(), QStringLiteral("mus_route101"));
    const auto baselineBudget = [&](const char *label, int *budget) {
        const SongInfo *song = findSong(baseline.songs(), QString::fromLatin1(label));
        if (!song)
            return false;
        *budget = baseline.trackBudgetFor(*song);
        return true;
    };
    int bgmBudget = 0;
    if (!baselineRoute101 || !baselineBudget("mus_route101", &bgmBudget) || bgmBudget != 16) {
        fail("baseline BGM player budget is not 16");
        return failures;
    }
    int fanfareBudget = 0;
    if (!findSong(baseline.songs(), QStringLiteral("se_fanfare_1trk")) ||
        !baselineBudget("se_fanfare_1trk", &fanfareBudget) || fanfareBudget != 1) {
        fail("baseline SE_1TRK player budget is not 1");
        return failures;
    }

    // Tests 1 and 2: cold scan -> SQLite store -> fresh instance reload.
    const QString cacheDir = scratchDir + QStringLiteral("/cache-sqlite");
    const QString storePath = ProjectIndex::storePath(cacheDir);
    DecompProject project;
    project.setIndexCache(cacheDir);
    QString openError;
    if (!project.open(scratchProject, &openError)) {
        std::fprintf(stderr, "projectindexcheck: first open: %s\n", qUtf8Printable(openError));
        fail("first cached open failed");
        return failures;
    }
    if (project.songs().size() != baselineSongCount) {
        fail("cold-scan song count differs from baseline");
        return failures;
    }
    const SongInfo *route101 = findSong(project.songs(), QStringLiteral("mus_route101"));
    if (!route101) {
        fail("mus_route101 missing from cold scan");
        return failures;
    }
    if (!route101->hasMid || !route101->hasCfg)
        fail("mus_route101 lost mid/cfg flags");
    if (route101->constant != QStringLiteral("MUS_ROUTE101"))
        fail("mus_route101 constant not resolved from songs.h");
    if (route101->player != QStringLiteral("MUSIC_PLAYER_BGM"))
        fail("mus_route101 player mismatch");
    if (route101->cfg.voicegroupArg != QStringLiteral("_fixture_rich") ||
        route101->cfg.masterVolume != 100 || route101->cfg.reverb != 50 || !route101->cfg.exactGate)
        fail("mus_route101 cfg flags not preserved");
    if (project.trackBudgetFor(*route101) != 16)
        fail("cached BGM player budget is not 16");
    if (!QFileInfo::exists(storePath)) {
        fail("store file was not written");
        return failures;
    }

    DecompProject reloaded;
    reloaded.setIndexCache(cacheDir);
    if (!reloaded.open(scratchProject, &openError)) {
        fail("reloaded cached open failed");
        return failures;
    }
    if (reloaded.songs().size() != baseline.songs().size()) {
        fail("reload song count differs from cold scan");
        return failures;
    }
    for (int i = 0; i < baseline.songs().size(); ++i) {
        if (!songEquals(baseline.songs()[i], reloaded.songs()[i])) {
            fail("reloaded song properties differ from cold scan");
            return failures;
        }
        if (reloaded.trackBudgetFor(reloaded.songs()[i]) !=
            baseline.trackBudgetFor(baseline.songs()[i])) {
            fail("reloaded player budget differs from cold scan");
            return failures;
        }
    }

    // Test 3: fingerprint invalidation when a new .mid is added.
    const QByteArray fingerBefore = projectFingerprint(scratchProject);
    QFile dummyMid(scratchProject + QStringLiteral("/sound/songs/midi/mus_dummy.mid"));
    if (dummyMid.open(QIODevice::ReadOnly) &&
        !writeBytes(scratchProject + QStringLiteral("/sound/songs/midi/mus_probe_projectindex.mid"),
                    dummyMid.readAll())) {
        fail("cannot drop in the probe .mid file");
    }
    dummyMid.close();
    const QByteArray fingerAfter = projectFingerprint(scratchProject);
    if (fingerBefore == fingerAfter) {
        fail("fingerprint did not change after adding a .mid file");
    } else {
        QVector<SongInfo> staleSongs;
        QVector<MusicPlayer> stalePlayers;
        if (ProjectIndex::load(cacheDir, scratchProject, fingerAfter, &staleSongs, &stalePlayers))
            fail("load accepted a store whose fingerprint predates the change");

        DecompProject rescan;
        rescan.setIndexCache(cacheDir);
        if (!rescan.open(scratchProject, &error)) {
            fail("rescan after fingerprint change failed");
        } else {
            if (rescan.songs().size() != baselineSongCount + 1)
                fail("rescan did not pick up the new .mid file");
            const SongInfo *probe =
                findSong(rescan.songs(), QStringLiteral("mus_probe_projectindex"));
            if (!probe || probe->registered || !probe->hasMid || probe->hasCfg) {
                fail("dropped-in .mid was not discovered as an unregistered song");
            } else {
                staleSongs.clear();
                stalePlayers.clear();
                if (!ProjectIndex::load(cacheDir, scratchProject, fingerAfter, &staleSongs,
                                        &stalePlayers))
                    fail("store was not rewritten after the rescan");
                else if (staleSongs.size() != baselineSongCount + 1)
                    fail("rewritten store lost the unregistered song");
            }
        }
    }

    // Test 4: corrupt cache resilience and fallback scan recovery.
    DecompProject warmup;
    warmup.setIndexCache(cacheDir);
    if (!warmup.open(scratchProject, &error)) {
        fail("cache warmup open failed");
    } else if (!writeBytes(storePath, QByteArrayLiteral("not a sqlite store\n"))) {
        fail("cannot corrupt cache store");
    } else {
        QVector<SongInfo> songs;
        QVector<MusicPlayer> players;
        if (ProjectIndex::load(cacheDir, scratchProject, fingerAfter, &songs, &players))
            fail("load accepted corrupted store");

        DecompProject recovered;
        recovered.setIndexCache(cacheDir);
        if (!recovered.open(scratchProject, &error)) {
            fail("open did not fall back to a full scan on corrupted store");
        } else {
            if (recovered.songs().size() != baselineSongCount + 1)
                fail("fallback scan lost songs");
            const SongInfo *probe =
                findSong(recovered.songs(), QStringLiteral("mus_probe_projectindex"));
            if (!probe)
                fail("fallback scan lost the dropped-in song");
            songs.clear();
            players.clear();
            if (!ProjectIndex::load(cacheDir, scratchProject, projectFingerprint(scratchProject),
                                    &songs, &players))
                fail("corrupted store was not rewritten as valid cache");
            else if (songs.size() != baselineSongCount + 1)
                fail("rewritten cache lost the dropped-in song");
        }
    }

    // Additional coverage: listFileNames dotfile filtering and sorting.
    const QString listingDir = scratchDir + QStringLiteral("/listing");
    QDir().mkpath(listingDir);
    writeBytes(listingDir + QStringLiteral("/b.mid"), QByteArrayLiteral("x"));
    writeBytes(listingDir + QStringLiteral("/a.mid"), QByteArrayLiteral("x"));
    writeBytes(listingDir + QStringLiteral("/.hidden.mid"), QByteArrayLiteral("x"));
    writeBytes(listingDir + QStringLiteral("/._appledouble.mid"), QByteArrayLiteral("x"));
    writeBytes(listingDir + QStringLiteral("/note.txt"), QByteArrayLiteral("x"));
    writeBytes(listingDir + QStringLiteral("/shouted.MID"), QByteArrayLiteral("x"));
    writeBytes(listingDir + QStringLiteral("/space name.mid"), QByteArrayLiteral("x"));
    const QStringList listed = ProjectIndex::listFileNames(listingDir, QStringLiteral(".mid"));
    const QStringList expected{QStringLiteral("a.mid"), QStringLiteral("b.mid"),
                               QStringLiteral("space name.mid")};
    if (listed != expected) {
        std::fprintf(stderr, "projectindexcheck: expected listing %s, got %s\n",
                     qUtf8Printable(expected.join(u',')), qUtf8Printable(listed.join(u',')));
        fail("listFileNames did not filter dotfiles/suffix");
    }
    const QString emptyDir = listingDir + QStringLiteral("/empty");
    QDir().mkpath(emptyDir);
    if (!ProjectIndex::listFileNames(emptyDir, QStringLiteral(".mid")).isEmpty())
        fail("listFileNames listed files from an empty dir");
    if (!ProjectIndex::listFileNames(listingDir + QStringLiteral("/missing"),
                                     QStringLiteral(".mid"))
             .isEmpty())
        fail("listFileNames listed files from a missing dir");

    // Test 5: Comma-bearing flag roundtrip and dynamic midPath derivation.
    const QString commaCacheDir = scratchDir + QStringLiteral("/cache-comma");
    SongInfo commaSong;
    commaSong.id = 0;
    commaSong.label = QStringLiteral("mus_comma");
    commaSong.constant = QStringLiteral("MUS_COMMA");
    commaSong.player = QStringLiteral("MUSIC_PLAYER_BGM");
    commaSong.hasMid = true;
    commaSong.registered = true;
    commaSong.cfg.rawFlags = QStringList{QStringLiteral("-G_custom,rich"), QStringLiteral("-V100")};
    commaSong.registrationGaps = QStringList{QStringLiteral("gap,1"), QStringLiteral("gap,2")};
    QVector<SongInfo> commaSongs{commaSong};
    QVector<MusicPlayer> commaPlayers;
    const QByteArray commaFinger = "commafingerprint12345";
    if (!ProjectIndex::save(commaCacheDir, scratchProject, commaFinger, commaSongs, commaPlayers)) {
        fail("failed to save comma-bearing flags to sqlite");
    } else {
        QVector<SongInfo> loadedCommaSongs;
        QVector<MusicPlayer> loadedCommaPlayers;
        if (!ProjectIndex::load(commaCacheDir, scratchProject, commaFinger, &loadedCommaSongs,
                                &loadedCommaPlayers) ||
            loadedCommaSongs.isEmpty()) {
            fail("failed to load comma-bearing flags from sqlite");
        } else if (loadedCommaSongs[0].cfg.rawFlags != commaSong.cfg.rawFlags) {
            fail("raw_flags with commas were split/corrupted in sqlite roundtrip");
        } else if (loadedCommaSongs[0].registrationGaps != commaSong.registrationGaps) {
            fail("registrationGaps with commas were split/corrupted in sqlite roundtrip");
        } else if (loadedCommaSongs[0].cfg.voicegroupArg != QStringLiteral("_custom,rich") ||
                   loadedCommaSongs[0].cfg.masterVolume != 100) {
            fail("SongCfg properties were not correctly derived from raw_flags on load");
        } else {
            const QString canonicalProject = QFileInfo(scratchProject).canonicalFilePath();
            const QString expectedMid =
                (canonicalProject.isEmpty() ? scratchProject : canonicalProject) +
                QStringLiteral("/sound/songs/midi/mus_comma.mid");
            if (loadedCommaSongs[0].midPath != expectedMid)
                fail("derived midPath does not match expected path");
        }
    }
    // Test 6: Unregistered song sidecar metadata refresh on cache hit.
    const QString sidecarCacheDir = scratchDir + QStringLiteral("/cache-sidecar");
    DecompProject sidecarWarmup;
    sidecarWarmup.setIndexCache(sidecarCacheDir);
    if (!sidecarWarmup.open(scratchProject, &error)) {
        fail("sidecar warmup open failed");
    } else {
        SongRegistry::saveRegistrationMeta(scratchProject, QStringLiteral("mus_probe_projectindex"),
                                           QStringLiteral("MUS_CUSTOM_CONSTANT"),
                                           QStringLiteral("MUSIC_PLAYER_CUSTOM"));
        DecompProject sidecarCached;
        sidecarCached.setIndexCache(sidecarCacheDir);
        if (!sidecarCached.open(scratchProject, &error)) {
            fail("sidecar cached open failed");
        } else {
            const SongInfo *probe =
                findSong(sidecarCached.songs(), QStringLiteral("mus_probe_projectindex"));
            if (!probe)
                fail("probe song missing on cached reopen");
            else if (probe->constant != QStringLiteral("MUS_CUSTOM_CONSTANT") ||
                     probe->player != QStringLiteral("MUSIC_PLAYER_CUSTOM"))
                fail("unregistered song sidecar metadata was not refreshed on cache hit");
        }
    }

    return failures == 0 ? 0 : 1;
}