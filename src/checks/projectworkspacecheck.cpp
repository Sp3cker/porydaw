#include <QDir>
#include <QEventLoop>
#include <QSettings>
#include <QTimer>

#include <cstdio>
#include <deque>
#include <optional>
#include <utility>
#include <variant>

#include "project/projectidentity.h"
#include "project/projectworkspace.h"
#include "project/songregistry.h"
#include "project/voicegroupsource.h"
#include "ui/viewsidecar.h"

// --projectworkspacecheck <projectRoot>: drives the public ProjectWorkspace
// seam end to end against the fixture project with redirected QSettings.
// Covered contracts: the Loading-only open refusal, the state/error
// invariant with a failed open retaining the prior snapshot, write
// ownership of the last project path on success only, the startup open
// queued to a later event-loop turn so its Loading publication leads every
// wired publication and Ready precedes the selected-first startup song
// submissions, the missing saved-name Reconcile failure, keyed semantic
// event and failure mapping (catalog replacement and its one-publication
// failure settlement, registration/deletion plans, ordered song-load
// stages, voicegroup edit view/receipt/conflict/hard error), and the
// silent completions that advance the FIFO without a public publication.

namespace {

// Report and count each failure.
auto contractCheck(int &failures)
{
    return [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "projectworkspacecheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
}

// One publication in arrival order across the three public streams.
using Entry = std::variant<ProjectState, ProjectEvent, SongUpdate>;

int checkWorkspaceFlows(const QString &projectRoot, int &failures)
{
    const auto check = contractCheck(failures);
    auto loop = QEventLoop{};

    const auto waitFor = [&](const auto &ready, const char *what) {
        auto timedOut = false;
        auto timer = QTimer{};
        timer.setSingleShot(true);
        timer.setInterval(30000);
        QObject::connect(&timer, &QTimer::timeout, &loop, [&] {
            timedOut = true;
            loop.quit();
        });
        while (!timedOut && !ready()) {
            timer.start();
            loop.exec();
        }
        timer.stop();
        return check(ready(), what);
    };

    const auto stateCount = [](const std::deque<Entry> &log) {
        auto count = 0;
        for (const auto &entry : log)
            if (std::holds_alternative<ProjectState>(entry))
                ++count;
        return count;
    };
    const auto lastState = [](const std::deque<Entry> &log) -> const ProjectState * {
        for (auto it = log.rbegin(); it != log.rend(); ++it)
            if (const auto *state = std::get_if<ProjectState>(&*it))
                return state;
        return nullptr;
    };
    const auto indexOf = [](const std::deque<Entry> &log, auto &&match) -> int {
        for (std::size_t i = 0; i < log.size(); ++i)
            if (match(log[i]))
                return int(i);
        return -1;
    };
    const auto checkInvariants = [&](const std::deque<Entry> &log) {
        for (const auto &entry : log) {
            const auto *state = std::get_if<ProjectState>(&entry);
            if (!state)
                continue;
            check(state->error.has_value() == (state->state == ProjectOpenState::Failed),
                  "a published state broke the error invariant");
        }
    };
    const auto wire = [&](ProjectWorkspace &workspace, std::deque<Entry> &log) {
        const auto record = [&log, &loop](auto value) {
            log.push_back(Entry{std::move(value)});
            loop.quit();
        };
        QObject::connect(&workspace, &ProjectWorkspace::projectStatePublished, &workspace,
                         [record](ProjectState state) { record(std::move(state)); });
        QObject::connect(&workspace, &ProjectWorkspace::projectEventPublished, &workspace,
                         [record](ProjectEvent event) { record(std::move(event)); });
        QObject::connect(&workspace, &ProjectWorkspace::songUpdatePublished, &workspace,
                         [record](SongUpdate update) { record(std::move(update)); });
    };

    const auto absRoot = QDir(projectRoot).absolutePath();
    const auto goneRoot = projectRoot + QStringLiteral("/gone");
    const auto route101 = SongName::create(QStringLiteral("mus_route101"));
    const auto petalburg = SongName::create(QStringLiteral("mus_petalburg"));
    const auto missing = SongName::create(QStringLiteral("porydaw_missing_song"));
    check(route101 && petalburg && missing, "fixture song labels were rejected as identities");
    if (!(route101 && petalburg && missing))
        return failures;

    // ---- user-driven open: refusal, invariants, write ownership ------------------

    {
        QSettings settings;
        settings.remove(QStringLiteral("lastProjectDir"));
        settings.remove(QStringLiteral("lastOpenSongs"));
        settings.remove(QStringLiteral("lastSongLabel"));
    }
    auto openLog = std::deque<Entry>{};
    auto opener = ProjectWorkspace{};
    wire(opener, openLog);

    opener.openProject(OpenProjectInput{goneRoot});
    check(stateCount(openLog) == 1, "the open did not publish exactly one Loading state");
    opener.openProject(OpenProjectInput{projectRoot});
    check(stateCount(openLog) == 1, "openProject was not refused while Loading");
    waitFor(
        [&] {
            const auto *state = lastState(openLog);
            return state && state->state == ProjectOpenState::Failed;
        },
        "the failed open did not publish Failed");
    if (const auto *failed = lastState(openLog)) {
        check(failed->error.has_value() && !failed->error->isEmpty(),
              "a failed open did not carry its present error");
    }
    {
        const QSettings settings;
        check(!settings.contains(QLatin1String("lastProjectDir")),
              "a failed open recorded the last project path");
    }
    // Any other state queues a new open.
    opener.openProject(OpenProjectInput{projectRoot});
    waitFor(
        [&] {
            const auto *state = lastState(openLog);
            return state && state->state == ProjectOpenState::Ready;
        },
        "the re-open did not publish Ready");
    {
        const QSettings settings;
        check(settings.value(QLatin1String("lastProjectDir")).toString() == absRoot,
              "a successful open did not record the last project path");
    }

    // ---- startup restoration: Ready first, selected first, Reconcile -------------

    {
        QSettings settings;
        settings.setValue(QLatin1String("lastProjectDir"), projectRoot);
        settings.setValue(QLatin1String("lastOpenSongs"),
                          QStringList{QStringLiteral("mus_petalburg"),
                                      QStringLiteral("mus_route101"),
                                      QStringLiteral("porydaw_missing_song")});
        settings.setValue(QLatin1String("lastSongLabel"), QStringLiteral("mus_route101"));
    }
    auto startupLog = std::deque<Entry>{};
    auto restorer = ProjectWorkspace{};
    wire(restorer, startupLog);
    // The wiring lands in this same turn; the constructor only queues the
    // saved open, so every startup publication arrives through these
    // connections on a later event-loop turn.

    const auto terminalFor = [](const SongUpdate &update) {
        return std::holds_alternative<VoicegroupBound>(update.payload) ||
               std::holds_alternative<SongFailed>(update.payload);
    };
    const auto terminalsFor = [&](const SongName &song) {
        auto count = 0;
        for (const auto &entry : startupLog) {
            const auto *update = std::get_if<SongUpdate>(&entry);
            if (update && update->song == song && terminalFor(*update))
                ++count;
        }
        return count;
    };
    waitFor(
        [&] {
            return terminalsFor(*route101) >= 1 && terminalsFor(*petalburg) >= 1 &&
                   terminalsFor(*missing) >= 1;
        },
        "startup song loads did not all reach a terminal update");

    const auto readyIndex = indexOf(startupLog, [](const Entry &entry) {
        const auto *state = std::get_if<ProjectState>(&entry);
        return state && state->state == ProjectOpenState::Ready;
    });
    const auto loadingIndex = indexOf(startupLog, [](const Entry &entry) {
        const auto *state = std::get_if<ProjectState>(&entry);
        return state && state->state == ProjectOpenState::Loading;
    });
    const auto selectedFirst = indexOf(startupLog, [&](const Entry &entry) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        return update && update->song == *route101 && terminalFor(*update);
    });
    const auto restIndex = indexOf(startupLog, [&](const Entry &entry) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        return update && update->song == *petalburg && terminalFor(*update);
    });
    const auto missingIndex = indexOf(startupLog, [&](const Entry &entry) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        return update && update->song == *missing && terminalFor(*update);
    });
    check(readyIndex >= 0, "the startup open did not publish Ready");
    check(loadingIndex == 0, "the wired publications did not lead with startup Loading");
    check(readyIndex > loadingIndex, "the startup Ready was published before its Loading");
    check(selectedFirst > readyIndex && restIndex > readyIndex && missingIndex > readyIndex,
          "a startup song update was published before Ready");
    check(selectedFirst < restIndex && restIndex < missingIndex,
          "startup loads did not run selected first, then the rest in saved order");

    for (const auto &entry : startupLog) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        if (!update || update->song != *missing)
            continue;
        const auto *failure = std::get_if<SongFailed>(&update->payload);
        check(failure && failure->stage == SongStage::Reconcile && !failure->message.isEmpty(),
              "the missing saved name did not report the keyed Reconcile failure");
    }

    // ---- failed re-open retains the prior snapshot --------------------------------

    restorer.openProject(OpenProjectInput{goneRoot});
    waitFor(
        [&] {
            const auto *state = lastState(startupLog);
            return state && state->state == ProjectOpenState::Failed;
        },
        "the failed re-open did not publish Failed");
    if (const auto *failed = lastState(startupLog)) {
        check(failed->snapshot.root() == absRoot && failed->snapshot.isOpen(),
              "a failed open did not retain the prior snapshot");
    }
    restorer.openProject(OpenProjectInput{projectRoot});
    waitFor(
        [&] {
            const auto *state = lastState(startupLog);
            return state && state->state == ProjectOpenState::Ready;
        },
        "the restored re-open did not publish Ready");
    if (const auto *restored = lastState(startupLog)) {
        check(restored->catalog.groupArgs.isEmpty(),
              "the restored re-open scanned its catalog before a song became playable");
    }
    // A re-open has no restored songs, so its low-priority fallback must run
    // after Ready. Let it settle before the per-command catalog assertions
    // below, whose marks intentionally describe only user submissions.
    waitFor(
        [&] {
            const auto *state = lastState(startupLog);
            return state && state->state == ProjectOpenState::Ready &&
                   !state->catalog.groupArgs.isEmpty();
        },
        "the restored re-open did not run its deferred catalog fallback");

    // ---- semantic event mapping ------------------------------------------------------

    const auto routeConstant = SongRegistry::constantForLabel(QStringLiteral("mus_route101"));

    // A successful catalog mutation replaces the published state's catalog.
    auto mark = startupLog.size();
    restorer.submit(ProjectOperation{RefreshCatalogInput{}});
    waitFor(
        [&] {
            for (auto i = mark; i < startupLog.size(); ++i)
                if (const auto *state = std::get_if<ProjectState>(&startupLog[i]);
                    state && !state->catalog.groupArgs.isEmpty())
                    return true;
            return false;
        },
        "a successful catalog mutation did not publish a state replacement");
    check(startupLog.size() == mark + 1,
          "the catalog mutation published extra results beside its state");

    // A failed catalog mutation settles as the one unkeyed failure, not a
    // silent completion: exactly one publication after the submission.
    mark = startupLog.size();
    const auto duplicateName = lastState(startupLog)->catalog.groupArgs.first().mid(1);
    restorer.submit(ProjectOperation{CreateVoicegroupInput{duplicateName, QString(), QString()}});
    waitFor(
        [&] {
            return indexOf(startupLog, [](const Entry &entry) {
                       const auto *event = std::get_if<ProjectEvent>(&entry);
                       const auto *failure =
                           event ? std::get_if<ProjectMutationFailure>(&*event) : nullptr;
                       return failure && std::get_if<CatalogMutationFailed>(&*failure);
                   }) >= int(mark);
        },
        "the failed voicegroup creation did not publish the catalog failure");
    check(startupLog.size() == mark + 1, "the failed voicegroup creation published extra results");

    // Keyed plan events forward unchanged.
    mark = startupLog.size();
    restorer.submit(ProjectOperation{RegistrationPlanInput{
        QStringLiteral("mus_route101"), routeConstant, QStringLiteral("MUSIC_PLAYER_BGM")}});
    waitFor(
        [&] {
            return indexOf(startupLog, [](const Entry &entry) {
                       const auto *event = std::get_if<ProjectEvent>(&entry);
                       return event && std::holds_alternative<RegistrationPlanResult>(*event);
                   }) >= int(mark);
        },
        "the registration plan did not arrive as a keyed event");
    restorer.submit(ProjectOperation{DeletionPlanInput{*route101, routeConstant}});
    waitFor(
        [&] {
            return indexOf(startupLog, [](const Entry &entry) {
                       const auto *event = std::get_if<ProjectEvent>(&entry);
                       return event && std::holds_alternative<DeletionPlanResult>(*event);
                   }) >= int(mark);
        },
        "the deletion plan did not arrive as a keyed event");
    if (const auto index =
            indexOf(startupLog,
                    [](const Entry &entry) {
                        const auto *event = std::get_if<ProjectEvent>(&entry);
                        return event && std::holds_alternative<RegistrationPlanResult>(*event);
                    });
        index >= 0) {
        const auto &plan =
            std::get<RegistrationPlanResult>(std::get<ProjectEvent>(startupLog[index]));
        check(plan.song == *route101, "the registration plan lost its song key");
    }

    // ---- silent completions advance the FIFO without a publication -------------------

    mark = startupLog.size();
    restorer.submit(ProjectOperation{CleanupPreviewInput{}});
    restorer.submit(ProjectOperation{SaveSidecarInput{*route101, ViewSidecar::Snapshot{}}});
    restorer.submit(ProjectOperation{ProbeSamplesInput{}});
    waitFor([&] { return startupLog.size() > mark; },
            "the silent completions did not advance the FIFO to the next probe");
    check(startupLog.size() == mark + 1, "a silent completion published a public result");
    if (startupLog.size() == mark + 1) {
        const auto *event = std::get_if<ProjectEvent>(&startupLog[mark]);
        check(event && std::holds_alternative<SamplesProbed>(*event),
              "the FIFO did not advance straight to the probe publication");
    }

    // ---- ordered song load: stages, keyed bank view, terminal bound --------------------

    mark = startupLog.size();
    restorer.submit(ProjectOperation{OpenSongInput{*route101}});
    waitFor([&] { return startupLog.size() >= mark + 4; },
            "the song reload did not deliver its four ordered publications");
    check(startupLog.size() == mark + 4, "the song reload delivered extra publications");
    if (startupLog.size() == mark + 4) {
        const auto *midi = std::get_if<SongUpdate>(&startupLog[mark]);
        const auto *sidecar = std::get_if<SongUpdate>(&startupLog[mark + 1]);
        const auto *viewEntry = std::get_if<ProjectEvent>(&startupLog[mark + 2]);
        const auto *bound = std::get_if<SongUpdate>(&startupLog[mark + 3]);
        check(midi && std::holds_alternative<MidiStage>(midi->payload) && midi->song == *route101,
              "the reload did not publish the keyed MIDI stage first");
        check(sidecar && std::holds_alternative<SidecarStage>(sidecar->payload) &&
                  sidecar->song == *route101,
              "the reload did not publish the keyed sidecar stage second");
        check(viewEntry && std::holds_alternative<LoadedBankView>(*viewEntry),
              "the reload did not publish the keyed bank view before its bound update");
        check(bound && std::holds_alternative<VoicegroupBound>(bound->payload) &&
                  bound->song == *route101,
              "the reload did not publish the terminal bound update last");
    }

    // ---- voicegroup edits: conflict, applied view + receipt, hard failure -------------

    const auto *viewEntry = std::get_if<ProjectEvent>(&startupLog[mark + 2]);
    const auto *view = viewEntry ? std::get_if<LoadedBankView>(&*viewEntry) : nullptr;
    check(view && static_cast<bool>(view->bank) && !view->slotViews.isEmpty(),
          "the reload's bank view carried no usable lease");
    if (view && !view->slotViews.isEmpty()) {
        auto filled = -1;
        for (int i = 0; i < view->slotViews.size(); ++i) {
            if (view->slotViews[i].voice.has_value()) {
                filled = i;
                break;
            }
        }
        check(filled >= 0, "the loaded bank view had no filled slots");
        if (filled >= 0) {
            // A filled slot re-submitted as expecting-blank confirms keyed.
            mark = startupLog.size();
            restorer.submit(ProjectOperation{VoicegroupEditInput{
                view->id,
                SetVoicegroupSlot{filled, *view->slotViews[filled].voice, std::nullopt}}});
            waitFor(
                [&] {
                    return indexOf(startupLog, [&](const Entry &entry) {
                               const auto *event = std::get_if<ProjectEvent>(&entry);
                               return event &&
                                      std::holds_alternative<VoicegroupEditConflict>(*event);
                           }) >= int(mark);
                },
                "the expected-state mismatch did not publish a keyed conflict");

            // A scalar edit with the expected voice applies: the canonical
            // bank replacement event arrives with the keyed receipt.
            auto edited = *view->slotViews[filled].voice;
            edited.key += 1;
            mark = startupLog.size();
            restorer.submit(ProjectOperation{VoicegroupEditInput{
                view->id, SetVoicegroupSlot{filled, edited, *view->slotViews[filled].voice}}});
            waitFor([&] { return startupLog.size() >= mark + 2; },
                    "the applied edit did not publish its view and receipt");
            check(startupLog.size() == mark + 2,
                  "the applied edit published an unexpected publication count");
            if (startupLog.size() == mark + 2) {
                const auto *appliedView = std::get_if<ProjectEvent>(&startupLog[mark]);
                const auto *receipt = std::get_if<ProjectEvent>(&startupLog[mark + 1]);
                check(appliedView && std::holds_alternative<LoadedBankView>(*appliedView),
                      "the applied edit did not publish the canonical bank view first");
                if (receipt) {
                    const auto *applied = std::get_if<VoicegroupEditApplied>(&*receipt);
                    check(applied && applied->voicegroup == view->id,
                          "the applied edit did not publish the keyed receipt second");
                }
            }

            // A hard worker error maps to the keyed mutation failure.
            const auto ghost = VoicegroupId::create(
                QStringLiteral("sound/voicegroups/porydaw_ghost.inc"), QString());
            check(ghost.has_value(), "the fabricated voicegroup identity was rejected");
            if (ghost) {
                mark = startupLog.size();
                restorer.submit(ProjectOperation{VoicegroupEditInput{
                    *ghost, SetVoicegroupSlot{0, *view->slotViews[filled].voice, std::nullopt}}});
                waitFor(
                    [&] {
                        return indexOf(startupLog, [&](const Entry &entry) {
                                   const auto *event = std::get_if<ProjectEvent>(&entry);
                                   const auto *failure =
                                       event ? std::get_if<ProjectMutationFailure>(&*event)
                                             : nullptr;
                                   const auto *vg =
                                       failure ? std::get_if<VoicegroupMutationFailed>(&*failure)
                                               : nullptr;
                                   return vg && vg->voicegroup == *ghost && !vg->message.isEmpty();
                               }) >= int(mark);
                    },
                    "the hard edit error did not publish the keyed voicegroup failure");
            }
        }
    }

    checkInvariants(openLog);
    checkInvariants(startupLog);

    {
        QSettings settings;
        settings.remove(QStringLiteral("lastProjectDir"));
        settings.remove(QStringLiteral("lastOpenSongs"));
        settings.remove(QStringLiteral("lastSongLabel"));
    }
    return failures;
}

} // namespace

int runProjectWorkspaceCheck(const QString &projectRoot)
{
    auto failures = 0;
    checkWorkspaceFlows(projectRoot, failures);
    if (failures == 0)
        std::printf("projectworkspacecheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
