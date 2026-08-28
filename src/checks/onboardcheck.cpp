#include <QAbstractButton>
#include <QAction>
#include <QApplication>
#include <QFile>
#include <QFileInfo>
#include <QMessageBox>
#include <QProcess>
#include <QString>
#include <cstdio>

#include "checks/onboardcheck/pipeline.h"
#include "checks/support/asyncwait.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/workspaceui.h"

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

} // namespace OnboardCheck

namespace {

// A headless harness cannot answer an unexpected blocking warning: dismiss
// WorkspaceUi's failure dialogs so a broken run fails its keyed assertions
// on timeout instead of hanging inside a nested modal loop.
void dismissBlockingFailureDialog()
{
    auto *box = qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
    if (!box)
        return;
    const QString title = box->windowTitle();
    if (title == MainWindow::tr("Project Change") || title == MainWindow::tr("Load Song") ||
        title == MainWindow::tr("Save Song"))
        box->accept();
}

} // namespace

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
    const QStringList voicegroupArgs = SongRegistry::voicegroupArgs(projectRoot);
    check(!voicegroupArgs.isEmpty(), "no voicegroups enumerated");
    std::printf("onboardcheck: %d voicegroups, e.g. %s\n", int(voicegroupArgs.size()),
                voicegroupArgs.isEmpty() ? "-" : qUtf8Printable(voicegroupArgs.first()));
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
    cfg.voicegroupArg =
        voicegroupArgs.isEmpty() ? QStringLiteral("_dummy") : voicegroupArgs.first();
    cfg.rawFlags = SongRegistry::mergeCfgFlags(cfg);

    const OnboardCheck::RegisteredSongFixture fixture = OnboardCheck::runRegistrationChecks(
        projectRoot, midiDir, registeredCount, project, cfg, reporter);
    OnboardCheck::runDebugLayoutChecks(projectRoot, project, fixture, reporter);
    OnboardCheck::runRegionedLayoutChecks(projectRoot, reporter);
    OnboardCheck::runRegisterActionChecks(projectRoot, midiDir, mid2agb, haveMid2agb, cfg, fixture,
                                          reporter);
    OnboardCheck::runImportChecks(projectRoot, midiDir, mid2agb, haveMid2agb, voicegroupArgs,
                                  project, cfg, externalImport, duplicateSetters, reporter);
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
    // before asserting on the fixture's playable-song presentation.
    m_workspace->restoreSongFilters({});

    const std::optional<SongName> name = SongName::create(label);
    if (!name) {
        std::fprintf(stderr, "onboardcheck: '%s' is not a valid song name\n",
                     qUtf8Printable(label));
        return false;
    }
    m_workspace->requestProjectOpenAt(projectRoot);
    const auto openWait = checks::async_wait::waitUntil(
        [] { return true; },
        [this] {
            const ProjectOpenState state = m_workspace->projectState().state;
            return state == ProjectOpenState::Ready || state == ProjectOpenState::Failed;
        });
    if (openWait != checks::async_wait::Result::Ready ||
        m_workspace->projectState().state != ProjectOpenState::Ready) {
        std::fprintf(stderr, "onboardcheck: project failed to open in MainWindow\n");
        return false;
    }
    m_workspace->requestSongOpen(*name);
    const auto loadWait = checks::async_wait::waitUntil(
        [this] { return m_workspace->projectState().state == ProjectOpenState::Ready; },
        [this, &name] {
            SongTab *const tab = m_workspace->songTabFor(*name);
            return tab && tab->isReady() && m_workspace->selectedSongTab() == tab;
        });
    if (loadWait != checks::async_wait::Result::Ready) {
        const char *reason = loadWait == checks::async_wait::Result::Destroyed
                                 ? "tab destroyed before its async load completed"
                                 : "timed out waiting for the SongTab's Midi, Sidecar, and "
                                   "VoicegroupBound stages";
        std::fprintf(stderr, "onboardcheck: %s for '%s'\n", reason, qUtf8Printable(label));
        return false;
    }
    SongTab *const tab = m_workspace->songTabFor(*name);
    if (!tab || tab->document().label() != label) {
        std::fprintf(stderr, "onboardcheck: '%s' did not load in MainWindow\n",
                     qUtf8Printable(label));
        return false;
    }
    check(m_registerAction->isEnabled(),
          "Register Song disabled for a song missing its charmap entry");

    // The model carries the gap while the workspace continues to present the
    // playable song through its semantic list boundary.
    const auto findSong = [this](const QString &wanted) -> const SongInfo * {
        for (const SongInfo &s : m_workspace->projectState().snapshot.songs()) {
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
    check(info && m_workspace->isSongListed(label),
          "partially registered song is absent from the browser");

    // The Register Song action heals the registration. The plan and commit
    // both run asynchronously, and the plan presents the same confirmation
    // dialog as the interactive path, so drive that dialog and wait for the
    // subsequent project snapshot refresh before asserting.
    if (!info) {
        check(false, "registration fixture song missing from the project model");
        return pass;
    }
    const QString constant =
        info->constant.isEmpty() ? SongRegistry::constantForLabel(label) : info->constant;
    // The song's open tab is the selection: the Register Song action targets
    // it through the production seam.
    m_workspace->registerSelectedSong();
    const auto dialogWait = checks::async_wait::waitUntil(
        [] { return true; },
        [this, &label, &constant, &check] {
            dismissBlockingFailureDialog();
            auto *box = qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
            if (!box || box->parent() != this)
                return false;
            const QString expectedText = tr("Register %1 as %2?").arg(label, constant);
            check(box->text() == expectedText,
                  "Register Song confirmation text does not match the requested song");
            bool foundAcceptRole = false;
            QAbstractButton *registerButton = nullptr;
            for (auto *button : box->buttons()) {
                if (box->buttonRole(button) != QMessageBox::AcceptRole)
                    continue;
                foundAcceptRole = true;
                auto buttonText = button->text();
                buttonText.remove(u'&');
                if (buttonText == tr("Register"))
                    registerButton = button;
            }
            check(foundAcceptRole, "Register Song confirmation has no AcceptRole button");
            check(registerButton, "Register Song confirmation has no Register button");
            if (!registerButton)
                return false;
            registerButton->click();
            return true;
        });
    check(dialogWait == checks::async_wait::Result::Ready,
          "Register Song confirmation dialog did not appear");
    if (dialogWait != checks::async_wait::Result::Ready)
        return pass;

    // The post-registration republication is the settlement signal: the model
    // only reports a healed registration after the worker's snapshot refresh.
    const auto refreshWait = checks::async_wait::waitUntil(
        [this] { return m_workspace->projectState().state == ProjectOpenState::Ready; },
        [this, &findSong, &label, &check] {
            dismissBlockingFailureDialog();
            const SongInfo *current = findSong(label);
            if (!current || !current->registered || !current->registrationGaps.isEmpty())
                return false;
            return m_workspace->isSongListed(label) && !m_registerAction->isEnabled();
        });
    check(refreshWait == checks::async_wait::Result::Ready,
          "registration snapshot refresh did not complete");
    if (refreshWait != checks::async_wait::Result::Ready)
        return pass;

    check(!m_registerAction->isEnabled(), "Register Song still enabled after backfill");
    info = findSong(label);
    check(info && info->registrationGaps.isEmpty(),
          "registration gaps not cleared by the backfill");
    check(info && m_workspace->isSongListed(label), "registered song disappeared from the browser");
    // A fresh activation recomputes the enable state from the reloaded songs:
    // re-opening the live tab is the production in-place reload, and the
    // open-project gate is down exactly while its load is in flight.
    m_workspace->requestSongOpen(*name);
    const auto reloadWait =
        checks::async_wait::waitUntil([] { return true; },
                                      [this] {
                                          dismissBlockingFailureDialog();
                                          return m_workspace->openProjectEnabled();
                                      });
    check(reloadWait == checks::async_wait::Result::Ready, "re-activation reload did not complete");
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

    m_workspace->restoreSongFilters({});
    const std::optional<SongName> name = SongName::create(label);
    if (!name) {
        std::fprintf(stderr, "onboardcheck: '%s' is not a valid song name\n",
                     qUtf8Printable(label));
        return false;
    }
    m_workspace->requestProjectOpenAt(projectRoot);
    const auto openWait = checks::async_wait::waitUntil(
        [] { return true; },
        [this] {
            const ProjectOpenState state = m_workspace->projectState().state;
            return state == ProjectOpenState::Ready || state == ProjectOpenState::Failed;
        });
    if (openWait != checks::async_wait::Result::Ready ||
        m_workspace->projectState().state != ProjectOpenState::Ready) {
        std::fprintf(stderr, "onboardcheck: project failed to open in MainWindow\n");
        return false;
    }
    m_workspace->requestSongOpen(*name);
    const auto loadWait = checks::async_wait::waitUntil(
        [this] { return m_workspace->projectState().state == ProjectOpenState::Ready; },
        [this, &name] {
            SongTab *const tab = m_workspace->songTabFor(*name);
            return tab && tab->isReady() && m_workspace->selectedSongTab() == tab;
        });
    if (loadWait != checks::async_wait::Result::Ready) {
        const char *reason = loadWait == checks::async_wait::Result::Destroyed
                                 ? "tab destroyed before its async load completed"
                                 : "timed out waiting for the SongTab's Midi, Sidecar, and "
                                   "VoicegroupBound stages";
        std::fprintf(stderr, "onboardcheck: %s for '%s'\n", reason, qUtf8Printable(label));
        return false;
    }
    SongTab *const tab = m_workspace->songTabFor(*name);
    if (!tab || tab->document().label() != label) {
        std::fprintf(stderr, "onboardcheck: '%s' did not load in MainWindow\n",
                     qUtf8Printable(label));
        return false;
    }
    const SongInfo *info = nullptr;
    for (const SongInfo &s : m_workspace->projectState().snapshot.songs()) {
        if (s.label == label)
            info = &s;
    }
    if (!info) {
        std::fprintf(stderr, "onboardcheck: '%s' not in the project model\n",
                     qUtf8Printable(label));
        return false;
    }
    const qsizetype listedSongCount = m_workspace->listedSongCount();
    check(m_workspace->isSongListed(label), "song is absent from the browser before deletion");

    // The Delete Song action runs its plan and confirmation dialog before any
    // file edit. Drive the dialog and wait for the post-delete snapshot
    // republication, which closes the deleted song's tab.
    m_workspace->deleteSelectedSong();
    const auto dialogWait = checks::async_wait::waitUntil(
        [] { return true; },
        [this, &label, &check] {
            dismissBlockingFailureDialog();
            auto *box = qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
            if (!box || box->parent() != this)
                return false;
            check(box->text() == tr("Delete %1?").arg(label),
                  "Delete Song confirmation text does not match the requested song");
            QAbstractButton *deleteButton = nullptr;
            for (auto *button : box->buttons()) {
                auto buttonText = button->text();
                buttonText.remove(u'&');
                if (box->buttonRole(button) == QMessageBox::DestructiveRole &&
                    buttonText == tr("Delete"))
                    deleteButton = button;
            }
            check(deleteButton, "Delete Song confirmation has no Delete button");
            if (!deleteButton)
                return false;
            deleteButton->click();
            return true;
        });
    check(dialogWait == checks::async_wait::Result::Ready,
          "Delete Song confirmation dialog did not appear");
    if (dialogWait != checks::async_wait::Result::Ready)
        return pass;

    const auto settleWait = checks::async_wait::waitUntil(
        [this] { return m_workspace->projectState().state == ProjectOpenState::Ready; },
        [this, &name] {
            dismissBlockingFailureDialog();
            return m_workspace->songTabFor(*name) == nullptr;
        });
    check(settleWait == checks::async_wait::Result::Ready, "deleted song's tab did not close");
    check(!m_workspace->songTabFor(*name), "deleted song's tab still open");
    bool inModel = false;
    for (const SongInfo &s : m_workspace->projectState().snapshot.songs())
        inModel = inModel || s.label == label;
    check(!inModel, "deleted song still in the project model");
    check(!m_workspace->isSongListed(label), "deleted song still listed in the browser");
    check(m_workspace->listedSongCount() == listedSongCount - 1,
          "deleting the song did not update the browser count");
    check(!QFile::exists(projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(label)),
          "deleted song's .mid still in sound/songs/midi");
    check(QFile::exists(projectRoot + QStringLiteral("/.porydaw/trash/%1.mid").arg(label)),
          "deleted song's .mid not moved to .porydaw/trash");

    // The fallback song refuses deletion end to end, before any file edit.
    const SongInfo *fallback = nullptr;
    for (const SongInfo &s : m_workspace->projectState().snapshot.songs()) {
        if (s.registered && s.id == 0)
            fallback = &s;
    }
    if (fallback) {
        const QString fallbackLabel = fallback->label;
        const std::optional<SongName> fallbackName = SongName::create(fallbackLabel);
        if (!fallbackName) {
            check(false, "fallback song label is not a valid SongName");
            return pass;
        }
        // The production delete action targets the selected tab, so open the
        // fallback song first.
        m_workspace->requestSongOpen(*fallbackName);
        const auto fallbackLoadWait = checks::async_wait::waitUntil(
            [this] { return m_workspace->projectState().state == ProjectOpenState::Ready; },
            [this, &fallbackName] {
                SongTab *const fallbackTab = m_workspace->songTabFor(*fallbackName);
                return fallbackTab && fallbackTab->isReady() &&
                       m_workspace->selectedSongTab() == fallbackTab;
            });
        if (fallbackLoadWait != checks::async_wait::Result::Ready) {
            check(false, "fallback song did not open for the delete-action refusal check");
            return pass;
        }
        const QByteArray tableBefore =
            OnboardCheck::readAllBytes(projectRoot + QStringLiteral("/sound/song_table.inc"));
        const QString fallbackMid =
            projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(fallbackLabel);
        const bool hadMid = QFile::exists(fallbackMid);
        m_workspace->deleteSelectedSong();
        const auto refusalWait = checks::async_wait::waitUntil(
            [] { return true; },
            [this, &fallbackLabel, &check] {
                auto *box = qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
                if (!box || box->parent() != this)
                    return false;
                const QString expected =
                    tr("%1 is the first usable table entry (song ID 0); the engine's "
                       "fallback. It cannot be deleted.")
                        .arg(fallbackLabel);
                check(box->text() == expected,
                      "fallback delete refusal does not name the engine fallback");
                box->accept();
                return true;
            });
        check(refusalWait == checks::async_wait::Result::Ready,
              "fallback delete refusal dialog did not appear");
        check(m_workspace->songTabFor(*fallbackName), "refused fallback delete closed its tab");
        check(OnboardCheck::readAllBytes(projectRoot + QStringLiteral("/sound/song_table.inc")) ==
                  tableBefore,
              "refused fallback delete still edited song_table.inc");
        check(QFile::exists(fallbackMid) == hadMid, "refused fallback delete still moved the .mid");
    }
    return pass;
}
