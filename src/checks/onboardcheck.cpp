#include <QAction>
#include <QFile>
#include <QFileInfo>
#include <QListWidget>
#include <QProcess>
#include <QSettings>
#include <QString>
#include <QTemporaryDir>
#include <algorithm>
#include <cstdio>

#include "checks/onboardcheck/pipeline.h"
#include "mainwindow.h"
#include "project/voicegroupproject.h"
#include "ui/songlistpanel.h"

// --onboardcheck <projectRoot> [mid2agbPath]: M3 onboarding check. Exercises
// the New Song and Import backends headlessly against a scratch copy of a
// project — it writes into it. Creates a song, verifies its files and sidecar,
// registers it (porydaw writes song_table.inc / songs.h / ld_script.ld /
// charmap.txt / src/debug.c directly), verifies idempotency and stale-ID
// correction, and runs an external-MIDI import (analysis + division rescale),
// compiling both songs through the project's real mid2agb.
namespace OnboardCheck {

void CheckReporter::check(bool ok, const char *what)
{
    if (!ok) {
        std::fprintf(stderr, "onboardcheck: FAIL: %s\n", what);
        ++m_failures;
    }
}

void CheckReporter::check(bool ok, const QString &what)
{
    if (!ok) {
        std::fprintf(stderr, "onboardcheck: FAIL: %s\n", qUtf8Printable(what));
        ++m_failures;
    }
}

QByteArray readAllBytes(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

bool readMidiFixture(const QString &projectRoot, const QString &fileName, SmfFile *smf,
                     CheckReporter &reporter)
{
    const QString path = projectRoot + QStringLiteral("/test_midis/") + fileName;
    QString error;
    if (SmfFile::readFile(path, smf, &error))
        return true;

    if (error.isEmpty())
        error = QStringLiteral("could not open or parse the file");

    std::fprintf(stderr, "onboardcheck: MIDI fixture '%s': %s\n", qUtf8Printable(path),
                 qUtf8Printable(error));
    const QString failure = QStringLiteral("could not read MIDI fixture %1").arg(fileName);
    reporter.check(false, failure);
    return false;
}

bool compilesThroughMid2agb(const QString &mid2agb, const QString &midPath,
                            const QStringList &flags)
{
    QProcess proc;
    const QString outS = midPath.left(midPath.size() - 4) + ".s";
    proc.start(mid2agb, QStringList() << flags << midPath << outS);
    proc.waitForFinished(15000);
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        std::fprintf(stderr, "onboardcheck: mid2agb: %s\n",
                     qUtf8Printable(QString::fromLocal8Bit(proc.readAllStandardError())));
        return false;
    }
    return QFileInfo(outS).size() > 0;
}

QStringList snapshotVoicegroupArgs(const porydaw::VoicegroupProject::Snapshot &snapshot)
{
    QStringList args;
    for (const auto &entry : snapshot.catalog) {
        if (entry.kind == porydaw::VoicegroupProject::CatalogKind::VoiceGroup &&
            entry.symbol.startsWith(QLatin1String("voicegroup")))
            args.append(entry.symbol.mid(10));
    }
    args.removeDuplicates();
    std::sort(args.begin(), args.end());
    return args;
}

} // namespace OnboardCheck

int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath)
{
    OnboardCheck::CheckReporter reporter;
    const auto check = [&](bool ok, const char *what) { reporter.check(ok, what); };

    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "onboardcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    SmfFile externalImport;
    SmfFile duplicateSetters;
    const bool externalLoaded = OnboardCheck::readMidiFixture(
        projectRoot, QStringLiteral("external_import.mid"), &externalImport, reporter);
    const bool duplicateSettersLoaded = OnboardCheck::readMidiFixture(
        projectRoot, QStringLiteral("duplicate_setters.mid"), &duplicateSetters, reporter);
    if (!externalLoaded || !duplicateSettersLoaded)
        return 1;
    // Only song_table entries count toward the proposed ID; the project may
    // already contain stray unregistered .mid files.
    int registeredCount = 0;
    for (const SongInfo &s : project.songs())
        registeredCount += s.registered ? 1 : 0;
    const QString midiDir = projectRoot + QStringLiteral("/sound/songs/midi");

    QString mid2agb = mid2agbPath;
    if (mid2agb.isEmpty())
        mid2agb = projectRoot + QStringLiteral("/tools/mid2agb/mid2agb");
    const bool haveMid2agb = QFileInfo::exists(mid2agb);
    if (!haveMid2agb)
        std::printf("onboardcheck: note: mid2agb not found, compile checks skipped\n");

    // ---- Project enumeration ------------------------------------------------
    auto vgProject = porydaw::VoicegroupProject{};
    const auto vgSnapshot = vgProject.open(projectRoot);
    const QStringList groupArgs = OnboardCheck::snapshotVoicegroupArgs(vgSnapshot);
    check(vgSnapshot.succeeded && !groupArgs.isEmpty(), "no voicegroups enumerated");
    std::printf("onboardcheck: %d voicegroups, e.g. %s\n", int(groupArgs.size()),
                groupArgs.isEmpty() ? "-" : qUtf8Printable(groupArgs.first()));
    const QVector<MusicPlayer> players = SongRegistry::musicPlayers(projectRoot);
    check(!players.isEmpty(), "no music players parsed from song_table.inc");

    // ---- Music-player track budgets -----------------------------------------
    // Deterministic fixture regardless of the checkout: swap in a known
    // music_player_table.inc, assert parsing + budget resolution, restore.
    {
        const QString tablePath = projectRoot + QStringLiteral("/sound/music_player_table.inc");
        const QByteArray original = OnboardCheck::readAllBytes(tablePath);
        QFile table(tablePath);
        check(table.open(QIODevice::WriteOnly | QIODevice::Truncate),
              "rewrite music_player_table.inc fixture");
        // BGM overridden to 12 via equiv, SE1 literal, SE2 clamped from a
        // NUM_TRACKS beyond the engine's 16, SE3 via an unknown symbol.
        table.write("\t.equiv NUM_TRACKS_BGM, 12\n"
                    "\t.equiv NUM_TRACKS_SE2, 20\n\n"
                    "gMPlayTable::\n"
                    "\tmusic_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0\n"
                    "\tmusic_player gMPlayInfo_SE1, gMPlayTrack_SE1, 3, 1\n"
                    "\tmusic_player gMPlayInfo_SE2, gMPlayTrack_SE2, NUM_TRACKS_SE2, 1\n"
                    "\tmusic_player gMPlayInfo_SE3, gMPlayTrack_SE3, NUM_TRACKS_WHO, 0\n");
        table.close();

        const QVector<MusicPlayer> budgeted = SongRegistry::musicPlayers(projectRoot);
        auto countFor = [&budgeted](const QString &name) {
            for (const MusicPlayer &p : budgeted) {
                if (p.name == name)
                    return p.trackCount;
            }
            return -2;
        };
        check(countFor(QStringLiteral("MUSIC_PLAYER_BGM")) == 12,
              "BGM budget follows the project's NUM_TRACKS override");
        check(countFor(QStringLiteral("MUSIC_PLAYER_SE1")) == 3, "literal track count parsed");
        check(countFor(QStringLiteral("MUSIC_PLAYER_SE2")) == 16,
              "budget clamped to the engine's 16 like MPlayOpen");
        check(countFor(QStringLiteral("MUSIC_PLAYER_SE3")) == -1,
              "unresolvable count stays unknown");

        DecompProject budgetProject;
        check(budgetProject.open(projectRoot, &error), "reopen for budgets");
        SongInfo bgmSong;
        bgmSong.player = QStringLiteral("MUSIC_PLAYER_BGM");
        check(budgetProject.trackBudgetFor(bgmSong) == 12,
              "trackBudgetFor resolves the song's player");
        bgmSong.player = QStringLiteral("MUSIC_PLAYER_SE3");
        check(budgetProject.trackBudgetFor(bgmSong) == 16,
              "unknown budget falls back to the engine ceiling");

        if (original.isEmpty()) {
            QFile::remove(tablePath);
        } else {
            check(table.open(QIODevice::WriteOnly | QIODevice::Truncate),
                  "restore music_player_table.inc");
            table.write(original);
            table.close();
        }
    }

    SongCfg cfg;
    cfg.exactGate = true;
    cfg.reverb = 50;
    cfg.masterVolume = 100;
    cfg.voicegroupArg = groupArgs.isEmpty() ? QStringLiteral("_dummy") : groupArgs.first();
    cfg.rawFlags = SongRegistry::mergeCfgFlags(cfg);

    const OnboardCheck::RegisteredSongFixture fixture = OnboardCheck::runRegistrationChecks(
        projectRoot, midiDir, registeredCount, project, cfg, reporter);
    OnboardCheck::runDebugLayoutChecks(projectRoot, project, fixture, reporter);
    OnboardCheck::runRegionedLayoutChecks(projectRoot, reporter);
    OnboardCheck::runRegisterActionChecks(projectRoot, midiDir, mid2agb, haveMid2agb, cfg, fixture,
                                          reporter);
    OnboardCheck::runImportChecks(projectRoot, midiDir, mid2agb, haveMid2agb, groupArgs, project,
                                  cfg, externalImport, duplicateSetters, reporter);
    OnboardCheck::runDeletionChecks(projectRoot, midiDir, project, cfg,
                                    fixture.plan.charmapApplicable, reporter);

    std::printf("onboardcheck: %s (%d failures)\n", reporter.hasFailures() ? "FAIL" : "PASS",
                reporter.failureCount());
    return reporter.hasFailures() ? 1 : 0;
}

bool MainWindow::runRegisterActionCheck(const QString &projectRoot, const QString &label)
{
    m_persistSession = false;
    bool pass = true;
    const auto check = [&pass](bool condition, const char *what) {
        if (!condition) {
            std::fprintf(stderr, "onboardcheck: FAIL: %s\n", what);
            pass = false;
        }
    };

    // Native-format QSettings use the registry on Windows, so setPath() in
    // the harness cannot isolate a persisted song filter. Clear it explicitly
    // before asserting on the fixture's list item.
    m_songList->restoreFilters(QString(), 0, QString());
    if (!openProjectDir(projectRoot, /*interactive=*/false)) {
        std::fprintf(stderr, "onboardcheck: project failed to open in MainWindow\n");
        return false;
    }
    loadSongByLabel(label);
    if (!m_active || m_active->doc.label() != label) {
        std::fprintf(stderr, "onboardcheck: '%s' did not load in MainWindow\n",
                     qUtf8Printable(label));
        return false;
    }
    check(m_registerAction->isEnabled(),
          "Register Song disabled for a song missing its charmap entry");

    // The model carries the gap and the song browser badges it.
    const auto findSong = [this](const QString &wanted) -> const SongInfo * {
        for (const SongInfo &s : m_project.songs()) {
            if (s.label == wanted)
                return &s;
        }
        return nullptr;
    };
    const SongInfo *info = findSong(label);
    check(info && info->registered,
          "partially registered song no longer counts as table-registered");
    check(info && info->registrationGaps == QStringList{QStringLiteral("charmap.txt")},
          "registrationGaps does not name the stripped charmap entry");
    auto *list = m_songList->findChild<QListWidget *>();
    const auto itemFor = [list](int id) -> QListWidgetItem * {
        for (int i = 0; list && i < list->count(); i++) {
            if (list->item(i)->data(Qt::UserRole).toInt() == id)
                return list->item(i);
        }
        return nullptr;
    };
    QListWidgetItem *item = info ? itemFor(info->id) : nullptr;
    check(item && item->text().contains(QStringLiteral("not fully registered")),
          "song list shows no badge for a partial registration");

    // The context menu's Register Song path heals the registration.
    if (info)
        registerSongById(info->id);
    check(!m_registerAction->isEnabled(), "Register Song still enabled after backfill");
    info = findSong(label);
    check(info && info->registrationGaps.isEmpty(),
          "registration gaps not cleared by the backfill");
    item = info ? itemFor(info->id) : nullptr;
    check(item && item->text() == label, "badge not cleared after the backfill");
    // A fresh activation recomputes the enable state from the reloaded songs.
    activateSession(m_active, /*force=*/true);
    check(!m_registerAction->isEnabled(),
          "re-activation re-enabled Register Song for a complete registration");
    return pass;
}

bool MainWindow::runDeleteActionCheck(const QString &projectRoot, const QString &label)
{
    m_persistSession = false;
    bool pass = true;
    const auto check = [&pass](bool condition, const char *what) {
        if (!condition) {
            std::fprintf(stderr, "onboardcheck: FAIL: %s\n", what);
            pass = false;
        }
    };

    if (!openProjectDir(projectRoot, /*interactive=*/false)) {
        std::fprintf(stderr, "onboardcheck: project failed to open in MainWindow\n");
        return false;
    }
    loadSongByLabel(label);
    if (!m_active || m_active->doc.label() != label) {
        std::fprintf(stderr, "onboardcheck: '%s' did not load in MainWindow\n",
                     qUtf8Printable(label));
        return false;
    }
    const SongInfo *info = nullptr;
    for (const SongInfo &s : m_project.songs()) {
        if (s.label == label)
            info = &s;
    }
    if (!info) {
        std::fprintf(stderr, "onboardcheck: '%s' not in the project model\n",
                     qUtf8Printable(label));
        return false;
    }
    const SongInfo song = *info; // survives the reload inside the deletion

    QString error;
    check(performSongDeletion(song, QString(), &error), "performSongDeletion failed");
    if (!error.isEmpty())
        std::fprintf(stderr, "onboardcheck: delete: %s\n", qUtf8Printable(error));
    check(!sessionForLabel(label), "deleted song's tab still open");
    bool inModel = false;
    for (const SongInfo &s : m_project.songs())
        inModel = inModel || s.label == label;
    check(!inModel, "deleted song still in the project model");
    auto *list = m_songList->findChild<QListWidget *>();
    bool listed = false;
    for (int i = 0; list && i < list->count(); i++)
        listed = listed || list->item(i)->text().startsWith(label);
    check(!listed, "deleted song still listed in the browser");
    check(!QFile::exists(projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(label)),
          "deleted song's .mid still in sound/songs/midi");
    check(QFile::exists(projectRoot + QStringLiteral("/.porydaw/trash/%1.mid").arg(label)),
          "deleted song's .mid not moved to .porydaw/trash");

    // The fallback song refuses deletion end to end, before any file edit.
    const SongInfo *fallback = nullptr;
    for (const SongInfo &s : m_project.songs()) {
        if (s.registered && s.id == 0)
            fallback = &s;
    }
    if (fallback) {
        const QByteArray tableBefore =
            OnboardCheck::readAllBytes(projectRoot + QStringLiteral("/sound/song_table.inc"));
        const QString fallbackMid =
            projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(fallback->label);
        const bool hadMid = QFile::exists(fallbackMid);
        QString refuse;
        check(!performSongDeletion(*fallback, QString(), &refuse) && !refuse.isEmpty(),
              "performSongDeletion deleted the fallback song");
        check(OnboardCheck::readAllBytes(projectRoot + QStringLiteral("/sound/song_table.inc")) ==
                  tableBefore,
              "refused fallback delete still edited song_table.inc");
        check(QFile::exists(fallbackMid) == hadMid, "refused fallback delete still moved the .mid");
    }
    return pass;
}
