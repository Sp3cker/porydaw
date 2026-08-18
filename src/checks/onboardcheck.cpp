#include <QAction>
#include <QFile>
#include <QFileInfo>
#include <QListWidget>
#include <QProcess>
#include <QSettings>
#include <QString>
#include <QTemporaryDir>
#include <cstdio>

#include "checks/onboardcheck/context.h"
#include "mainwindow.h"
#include "ui/songlistpanel.h"

// --onboardcheck <projectRoot> [mid2agbPath]: M3 onboarding check. Exercises
// the New Song and Import backends headlessly against a scratch copy of a
// project — it writes into it. Creates a song, verifies its files and sidecar,
// registers it (porydaw writes song_table.inc / songs.h / ld_script.ld /
// charmap.txt / src/debug.c directly), verifies idempotency and stale-ID
// correction, and runs an external-MIDI import (analysis + division rescale),
// compiling both songs through the project's real mid2agb.

namespace OnboardCheck {

namespace {
int g_failures = 0;
} // namespace

void check(bool ok, const char *what)
{
    if (!ok) {
        std::fprintf(stderr, "onboardcheck: FAIL: %s\n", what);
        g_failures++;
    }
}

int failureCount()
{
    return g_failures;
}

QByteArray readAllBytes(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

bool readMidiFixture(const QString &projectRoot, const QString &fileName, SmfFile *smf)
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
    check(false, qUtf8Printable(failure));
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

} // namespace OnboardCheck

int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath)
{
    OnboardCheck::Context context;
    context.projectRoot = projectRoot;

    QString error;
    if (!context.project.open(projectRoot, &error)) {
        std::fprintf(stderr, "onboardcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    const bool externalLoaded = OnboardCheck::readMidiFixture(
        projectRoot, QStringLiteral("external_import.mid"), &context.externalImport);
    const bool duplicateSettersLoaded = OnboardCheck::readMidiFixture(
        projectRoot, QStringLiteral("duplicate_setters.mid"), &context.duplicateSetters);
    if (!externalLoaded || !duplicateSettersLoaded)
        return 1;
    // Only song_table entries count toward the proposed ID; the project may
    // already contain stray unregistered .mid files.
    for (const SongInfo &s : context.project.songs())
        context.registeredCount += s.registered ? 1 : 0;
    context.midiDir = projectRoot + QStringLiteral("/sound/songs/midi");

    context.mid2agb = mid2agbPath;
    if (context.mid2agb.isEmpty())
        context.mid2agb = projectRoot + QStringLiteral("/tools/mid2agb/mid2agb");
    context.haveMid2agb = QFileInfo::exists(context.mid2agb);
    if (!context.haveMid2agb)
        std::printf("onboardcheck: note: mid2agb not found, compile checks skipped\n");

    // ---- Project enumeration ------------------------------------------------
    context.voicegroupArgs = SongRegistry::voicegroupArgs(projectRoot);
    OnboardCheck::check(!context.voicegroupArgs.isEmpty(), "no voicegroups enumerated");
    std::printf("onboardcheck: %d voicegroups, e.g. %s\n", int(context.voicegroupArgs.size()),
                context.voicegroupArgs.isEmpty() ? "-"
                                                 : qUtf8Printable(context.voicegroupArgs.first()));
    const QVector<MusicPlayer> players = SongRegistry::musicPlayers(projectRoot);
    OnboardCheck::check(!players.isEmpty(), "no music players parsed from song_table.inc");

    // ---- Music-player track budgets -----------------------------------------
    // Deterministic fixture regardless of the checkout: swap in a known
    // music_player_table.inc, assert parsing + budget resolution, restore.
    {
        const QString tablePath = projectRoot + QStringLiteral("/sound/music_player_table.inc");
        const QByteArray original = OnboardCheck::readAllBytes(tablePath);
        QFile table(tablePath);
        OnboardCheck::check(table.open(QIODevice::WriteOnly | QIODevice::Truncate),
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
        OnboardCheck::check(countFor(QStringLiteral("MUSIC_PLAYER_BGM")) == 12,
                            "BGM budget follows the project's NUM_TRACKS override");
        OnboardCheck::check(countFor(QStringLiteral("MUSIC_PLAYER_SE1")) == 3,
                            "literal track count parsed");
        OnboardCheck::check(countFor(QStringLiteral("MUSIC_PLAYER_SE2")) == 16,
                            "budget clamped to the engine's 16 like MPlayOpen");
        OnboardCheck::check(countFor(QStringLiteral("MUSIC_PLAYER_SE3")) == -1,
                            "unresolvable count stays unknown");

        DecompProject budgetProject;
        OnboardCheck::check(budgetProject.open(projectRoot, &error), "reopen for budgets");
        SongInfo bgmSong;
        bgmSong.player = QStringLiteral("MUSIC_PLAYER_BGM");
        OnboardCheck::check(budgetProject.trackBudgetFor(bgmSong) == 12,
                            "trackBudgetFor resolves the song's player");
        bgmSong.player = QStringLiteral("MUSIC_PLAYER_SE3");
        OnboardCheck::check(budgetProject.trackBudgetFor(bgmSong) == 16,
                            "unknown budget falls back to the engine ceiling");

        if (original.isEmpty()) {
            QFile::remove(tablePath);
        } else {
            OnboardCheck::check(table.open(QIODevice::WriteOnly | QIODevice::Truncate),
                                "restore music_player_table.inc");
            table.write(original);
            table.close();
        }
    }

    context.cfg.exactGate = true;
    context.cfg.reverb = 50;
    context.cfg.masterVolume = 100;
    context.cfg.voicegroupArg = context.voicegroupArgs.isEmpty() ? QStringLiteral("_dummy")
                                                                 : context.voicegroupArgs.first();
    context.cfg.rawFlags = SongRegistry::mergeCfgFlags(context.cfg);

    const OnboardCheck::RegisteredSongFixture fixture =
        OnboardCheck::runRegistrationChecks(context);
    OnboardCheck::runDebugLayoutChecks(context, fixture);
    OnboardCheck::runRegionedLayoutChecks(context);
    OnboardCheck::runRegisterActionChecks(context, fixture);
    OnboardCheck::runImportChecks(context);
    OnboardCheck::runDeletionChecks(context);

    std::printf("onboardcheck: %s (%d failures)\n", OnboardCheck::failureCount() ? "FAIL" : "PASS",
                OnboardCheck::failureCount());
    return OnboardCheck::failureCount() ? 1 : 0;
}

bool MainWindow::runRegisterActionCheck(const QString &projectRoot, const QString &label)
{
    m_persistSession = false;
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
    OnboardCheck::check(m_registerAction->isEnabled(),
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
    OnboardCheck::check(info && info->registered,
                        "partially registered song no longer counts as table-registered");
    OnboardCheck::check(info &&
                            info->registrationGaps == QStringList{QStringLiteral("charmap.txt")},
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
    OnboardCheck::check(item && item->text().contains(QStringLiteral("not fully registered")),
                        "song list shows no badge for a partial registration");

    // The context menu's Register Song path heals the registration.
    if (info)
        registerSongById(info->id);
    OnboardCheck::check(!m_registerAction->isEnabled(),
                        "Register Song still enabled after backfill");
    info = findSong(label);
    OnboardCheck::check(info && info->registrationGaps.isEmpty(),
                        "registration gaps not cleared by the backfill");
    item = info ? itemFor(info->id) : nullptr;
    OnboardCheck::check(item && item->text() == label, "badge not cleared after the backfill");
    // A fresh activation recomputes the enable state from the reloaded songs.
    activateSession(m_active, /*force=*/true);
    OnboardCheck::check(!m_registerAction->isEnabled(),
                        "re-activation re-enabled Register Song for a complete registration");
    return true;
}

bool MainWindow::runDeleteActionCheck(const QString &projectRoot, const QString &label)
{
    m_persistSession = false;
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
    OnboardCheck::check(performSongDeletion(song, QString(), &error), "performSongDeletion failed");
    if (!error.isEmpty())
        std::fprintf(stderr, "onboardcheck: delete: %s\n", qUtf8Printable(error));
    OnboardCheck::check(!sessionForLabel(label), "deleted song's tab still open");
    bool inModel = false;
    for (const SongInfo &s : m_project.songs())
        inModel = inModel || s.label == label;
    OnboardCheck::check(!inModel, "deleted song still in the project model");
    auto *list = m_songList->findChild<QListWidget *>();
    bool listed = false;
    for (int i = 0; list && i < list->count(); i++)
        listed = listed || list->item(i)->text().startsWith(label);
    OnboardCheck::check(!listed, "deleted song still listed in the browser");
    OnboardCheck::check(
        !QFile::exists(projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(label)),
        "deleted song's .mid still in sound/songs/midi");
    OnboardCheck::check(
        QFile::exists(projectRoot + QStringLiteral("/.porydaw/trash/%1.mid").arg(label)),
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
        OnboardCheck::check(!performSongDeletion(*fallback, QString(), &refuse) &&
                                !refuse.isEmpty(),
                            "performSongDeletion deleted the fallback song");
        OnboardCheck::check(
            OnboardCheck::readAllBytes(projectRoot + QStringLiteral("/sound/song_table.inc")) ==
                tableBefore,
            "refused fallback delete still edited song_table.inc");
        OnboardCheck::check(QFile::exists(fallbackMid) == hadMid,
                            "refused fallback delete still moved the .mid");
    }
    return true;
}
