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

// One publication in arrival order across the three public streams.
using Entry = std::variant<ProjectState, ProjectEvent, SongUpdate>;

// Count the published states in the arrival log.
int stateCount(const std::deque<Entry> &log)
{
    auto count = 0;
    for (const auto &entry : log)
        if (std::holds_alternative<ProjectState>(entry))
            ++count;
    return count;
}

// The most recent published state, or null before the first one arrives.
const ProjectState *lastState(const std::deque<Entry> &log)
{
    for (auto it = log.rbegin(); it != log.rend(); ++it)
        if (const auto *state = std::get_if<ProjectState>(&*it))
            return state;
    return nullptr;
}

// Whether the latest published state sits in the given open state.
bool lastStateIs(const std::deque<Entry> &log, ProjectOpenState openState)
{
    const auto *state = lastState(log);
    return state && state->state == openState;
}

// Log position of the first arrival matching, or -1.
template <typename Match>
int indexOf(const std::deque<Entry> &log, Match &&match)
{
    for (std::size_t i = 0; i < log.size(); ++i)
        if (match(log[i]))
            return int(i);
    return -1;
}

// Log position of the first state published in a given open state.
int stateIndexOf(const std::deque<Entry> &log, ProjectOpenState openState)
{
    return indexOf(log, [openState](const Entry &entry) {
        const auto *state = std::get_if<ProjectState>(&entry);
        return state && state->state == openState;
    });
}

// A song update that settles its load: bound or failed.
bool isTerminal(const SongUpdate &update)
{
    return std::holds_alternative<VoicegroupBound>(update.payload) ||
           std::holds_alternative<SongFailed>(update.payload);
}

// How many terminal updates one song reached in the log.
int terminalCount(const std::deque<Entry> &log, const SongName &song)
{
    auto count = 0;
    for (const auto &entry : log) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        if (update && update->song == song && isTerminal(*update))
            ++count;
    }
    return count;
}

// Log position of a song's first terminal update.
int terminalIndexOf(const std::deque<Entry> &log, const SongName &song)
{
    return indexOf(log, [&song](const Entry &entry) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        return update && update->song == song && isTerminal(*update);
    });
}

// Whether an arrival is a state carrying a published, non-empty catalog.
bool hasPublishedCatalog(const Entry &entry)
{
    const auto *state = std::get_if<ProjectState>(&entry);
    return state && !state->catalog.groupArgs.isEmpty();
}

// The keyed failure payload a ProjectEvent settles with, or null.
template <typename Failure>
const Failure *mutationFailure(const Entry &entry)
{
    const auto *event = std::get_if<ProjectEvent>(&entry);
    const auto *failure = event ? std::get_if<ProjectMutationFailure>(&*event) : nullptr;
    return failure ? std::get_if<Failure>(&*failure) : nullptr;
}

// The bank view published at the given log slot, or null.
const LoadedBankView *publishedBankView(const std::deque<Entry> &log, std::size_t index)
{
    if (index >= log.size())
        return nullptr;
    const auto *viewEntry = std::get_if<ProjectEvent>(&log[index]);
    return viewEntry ? std::get_if<LoadedBankView>(&*viewEntry) : nullptr;
}

// First slot index carrying a voice, or -1 when the bank is all blank.
int firstFilledSlot(const LoadedBankView &view)
{
    for (int i = 0; i < view.slotViews.size(); ++i)
        if (view.slotViews[i].voice.has_value())
            return i;
    return -1;
}

// The three QSettings keys the workspace owns across runs.
void clearSavedProjectSettings()
{
    QSettings settings;
    settings.remove(QStringLiteral("lastProjectDir"));
    settings.remove(QStringLiteral("lastOpenSongs"));
    settings.remove(QStringLiteral("lastSongLabel"));
}

// Seed the saved startup the workspace restores: the project, three songs
// in saved order, and the selected song that must load first.
void writeStartupSavedSettings(const QString &projectRoot)
{
    QSettings settings;
    settings.setValue(QLatin1String("lastProjectDir"), projectRoot);
    settings.setValue(QLatin1String("lastOpenSongs"),
                      QStringList{QStringLiteral("mus_petalburg"), QStringLiteral("mus_route101"),
                                  QStringLiteral("porydaw_missing_song")});
    settings.setValue(QLatin1String("lastSongLabel"), QStringLiteral("mus_route101"));
}

// One full drive's shared sequential state: the single event loop, the
// failure counter, fixture paths and song identities, and the arrival log
// of the open-refusal workspace. Scenario helpers receive this by
// reference and run in program order.
struct FlowFixture {
    FlowFixture(const QString &root, int &failureCount)
        : failures(failureCount)
        , projectRoot(root)
        , absRoot(QDir(root).absolutePath())
        , goneRoot(root + QStringLiteral("/gone"))
        , route101(SongName::create(QStringLiteral("mus_route101")))
        , petalburg(SongName::create(QStringLiteral("mus_petalburg")))
        , missing(SongName::create(QStringLiteral("porydaw_missing_song")))
    {}

    // Report and count each failure.
    bool check(bool ok, const char *what)
    {
        if (!ok) {
            std::fprintf(stderr, "projectworkspacecheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    }

    // Run the event loop until the predicate holds or the run times out.
    template <typename Ready>
    bool waitFor(const Ready &ready, const char *what)
    {
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
    }

    // Append every publication of the workspace to the log, in order.
    void wire(ProjectWorkspace &workspace, std::deque<Entry> &log)
    {
        const auto record = [this, &log](auto value) {
            log.push_back(Entry{std::move(value)});
            loop.quit();
        };
        QObject::connect(&workspace, &ProjectWorkspace::projectStatePublished, &workspace,
                         [record](ProjectState state) { record(std::move(state)); });
        QObject::connect(&workspace, &ProjectWorkspace::projectEventPublished, &workspace,
                         [record](ProjectEvent event) { record(std::move(event)); });
        QObject::connect(&workspace, &ProjectWorkspace::songUpdatePublished, &workspace,
                         [record](SongUpdate update) { record(std::move(update)); });
    }

    // Every published state carries an error exactly when it failed.
    void checkInvariants(const std::deque<Entry> &log)
    {
        for (const auto &entry : log) {
            const auto *state = std::get_if<ProjectState>(&entry);
            if (!state)
                continue;
            check(state->error.has_value() == (state->state == ProjectOpenState::Failed),
                  "a published state broke the error invariant");
        }
    }

    QEventLoop loop;
    int &failures;
    const QString projectRoot;
    const QString absRoot;
    const QString goneRoot;
    const std::optional<SongName> route101;
    const std::optional<SongName> petalburg;
    const std::optional<SongName> missing;
    std::deque<Entry> openLog;
};

// Publication positions the startup contract is judged against; the
// automatic-catalog scenario compares its own index against these.
struct StartupOrder {
    int ready = -1;
    int selected = -1;
    int rest = -1;
    int missing = -1;
};

// The restored startup drive every scenario after the open refusal shares:
// the arrival log wired to a workspace constructed only after the saved
// startup settings exist.
struct StartupSession {
    std::deque<Entry> log;
    ProjectWorkspace restorer;
};

// ---- user-driven open: refusal, invariants, write ownership --------------
//
// The Loading-only open refusal, the failed open's present error, and the
// last-project-path written on success only.
void checkOpenRefusalAndOwnership(FlowFixture &fx)
{
    clearSavedProjectSettings();
    auto opener = ProjectWorkspace{};
    fx.wire(opener, fx.openLog);

    opener.openProject(OpenProjectInput{fx.goneRoot});
    fx.check(stateCount(fx.openLog) == 1, "the open did not publish exactly one Loading state");
    opener.openProject(OpenProjectInput{fx.projectRoot});
    fx.check(stateCount(fx.openLog) == 1, "openProject was not refused while Loading");
    fx.waitFor([&] { return lastStateIs(fx.openLog, ProjectOpenState::Failed); },
               "the failed open did not publish Failed");
    if (const auto *failed = lastState(fx.openLog)) {
        fx.check(failed->error.has_value() && !failed->error->isEmpty(),
                 "a failed open did not carry its present error");
    }
    {
        const QSettings settings;
        fx.check(!settings.contains(QLatin1String("lastProjectDir")),
                 "a failed open recorded the last project path");
    }
    // Any other state queues a new open.
    opener.openProject(OpenProjectInput{fx.projectRoot});
    fx.waitFor([&] { return lastStateIs(fx.openLog, ProjectOpenState::Ready); },
               "the re-open did not publish Ready");
    {
        const QSettings settings;
        fx.check(settings.value(QLatin1String("lastProjectDir")).toString() == fx.absRoot,
                 "a successful open did not record the last project path");
    }
}

// ---- startup restoration: Ready first, selected first ----------------------
//
// The queued saved open publishes Loading ahead of every wired
// publication, Ready precedes the song submissions, and the selected song
// loads first with the rest following in saved order.
StartupOrder checkStartupRestoration(FlowFixture &fx, StartupSession &startup)
{
    fx.waitFor(
        [&] {
            return terminalCount(startup.log, *fx.route101) >= 1 &&
                   terminalCount(startup.log, *fx.petalburg) >= 1 &&
                   terminalCount(startup.log, *fx.missing) >= 1;
        },
        "startup song loads did not all reach a terminal update");

    const auto readyIndex = stateIndexOf(startup.log, ProjectOpenState::Ready);
    const auto loadingIndex = stateIndexOf(startup.log, ProjectOpenState::Loading);
    const auto selectedFirst = terminalIndexOf(startup.log, *fx.route101);
    const auto restIndex = terminalIndexOf(startup.log, *fx.petalburg);
    const auto missingIndex = terminalIndexOf(startup.log, *fx.missing);
    fx.check(readyIndex >= 0, "the startup open did not publish Ready");
    fx.check(loadingIndex == 0, "the wired publications did not lead with startup Loading");
    fx.check(readyIndex > loadingIndex, "the startup Ready was published before its Loading");
    fx.check(selectedFirst > readyIndex && restIndex > readyIndex && missingIndex > readyIndex,
             "a startup song update was published before Ready");
    fx.check(selectedFirst < restIndex && restIndex < missingIndex,
             "startup loads did not run selected first, then the rest in saved order");
    return {readyIndex, selectedFirst, restIndex, missingIndex};
}

// The missing saved name reports the keyed Reconcile failure.
void checkStartupReconcileFailure(FlowFixture &fx, const StartupSession &startup)
{
    for (const auto &entry : startup.log) {
        const auto *update = std::get_if<SongUpdate>(&entry);
        if (!update || update->song != *fx.missing)
            continue;
        const auto *failure = std::get_if<SongFailed>(&update->payload);
        fx.check(failure && failure->stage == SongStage::Reconcile && !failure->message.isEmpty(),
                 "the missing saved name did not report the keyed Reconcile failure");
    }
}

// ---- automatic startup catalog: exactly once, after every saved song -------
//
// acceptSnapshot enqueues the saved songs before the automatic refresh,
// so the catalog publication may only arrive once every saved startup
// song reached its terminal update, and exactly once: a lost or
// duplicated refresh, or a catalog failure, breaks the startup contract.
void checkAutomaticStartupCatalog(FlowFixture &fx, const StartupSession &startup,
                                  const StartupOrder &order)
{
    fx.waitFor([&] { return indexOf(startup.log, hasPublishedCatalog) >= 0; },
               "the automatic startup catalog did not publish");
    const auto autoCatalogIndex = indexOf(startup.log, hasPublishedCatalog);
    fx.check(autoCatalogIndex > order.ready, "the automatic catalog published before Ready");
    fx.check(autoCatalogIndex > order.selected && autoCatalogIndex > order.rest &&
                 autoCatalogIndex > order.missing,
             "the automatic catalog published before a saved startup song reached terminal state");
    auto automaticCatalogs = 0;
    for (const auto &entry : startup.log)
        if (hasPublishedCatalog(entry))
            ++automaticCatalogs;
    fx.check(automaticCatalogs == 1, "the automatic startup catalog did not publish exactly once");
    fx.check(indexOf(startup.log,
                     [](const Entry &entry) {
                         return mutationFailure<CatalogMutationFailed>(entry) != nullptr;
                     }) < 0,
             "the automatic startup catalog published a failure");
}

// ---- failed re-open retains the prior snapshot -------------------------------
void checkFailedReopenRetention(FlowFixture &fx, StartupSession &startup)
{
    startup.restorer.openProject(OpenProjectInput{fx.goneRoot});
    fx.waitFor([&] { return lastStateIs(startup.log, ProjectOpenState::Failed); },
               "the failed re-open did not publish Failed");
    if (const auto *failed = lastState(startup.log)) {
        fx.check(failed->snapshot.root() == fx.absRoot && failed->snapshot.isOpen(),
                 "a failed open did not retain the prior snapshot");
    }
    startup.restorer.openProject(OpenProjectInput{fx.projectRoot});
    fx.waitFor(
        [&] {
            const auto *state = lastState(startup.log);
            return state && state->state == ProjectOpenState::Ready &&
                   !state->catalog.groupArgs.isEmpty();
        },
        "the restored re-open did not publish its Ready catalog");
}

// ---- semantic event mapping --------------------------------------------------
//
// A successful catalog mutation replaces the published state's catalog, a
// failed one settles as the one unkeyed failure, and keyed plan events
// forward unchanged.
void checkCatalogAndPlanEvents(FlowFixture &fx, StartupSession &startup)
{
    const auto routeConstant = SongRegistry::constantForLabel(QStringLiteral("mus_route101"));

    auto mark = startup.log.size();
    startup.restorer.submit(ProjectOperation{RefreshCatalogInput{}});
    fx.waitFor(
        [&] {
            for (auto i = mark; i < startup.log.size(); ++i)
                if (hasPublishedCatalog(startup.log[i]))
                    return true;
            return false;
        },
        "a successful catalog mutation did not publish a state replacement");
    fx.check(startup.log.size() == mark + 1,
             "the catalog mutation published extra results beside its state");

    // A failed catalog mutation settles as the one unkeyed failure, not a
    // silent completion: exactly one publication after the submission.
    mark = startup.log.size();
    const auto duplicateName = lastState(startup.log)->catalog.groupArgs.first().mid(1);
    startup.restorer.submit(
        ProjectOperation{CreateVoicegroupInput{duplicateName, QString(), QString()}});
    fx.waitFor(
        [&] {
            return indexOf(startup.log, [](const Entry &entry) {
                       return mutationFailure<CatalogMutationFailed>(entry) != nullptr;
                   }) >= int(mark);
        },
        "the failed voicegroup creation did not publish the catalog failure");
    fx.check(startup.log.size() == mark + 1,
             "the failed voicegroup creation published extra results");

    // Keyed plan events forward unchanged.
    mark = startup.log.size();
    startup.restorer.submit(ProjectOperation{RegistrationPlanInput{
        QStringLiteral("mus_route101"), routeConstant, QStringLiteral("MUSIC_PLAYER_BGM")}});
    fx.waitFor(
        [&] {
            return indexOf(startup.log, [](const Entry &entry) {
                       const auto *event = std::get_if<ProjectEvent>(&entry);
                       return event && std::holds_alternative<RegistrationPlanResult>(*event);
                   }) >= int(mark);
        },
        "the registration plan did not arrive as a keyed event");
    startup.restorer.submit(ProjectOperation{DeletionPlanInput{*fx.route101, routeConstant}});
    fx.waitFor(
        [&] {
            return indexOf(startup.log, [](const Entry &entry) {
                       const auto *event = std::get_if<ProjectEvent>(&entry);
                       return event && std::holds_alternative<DeletionPlanResult>(*event);
                   }) >= int(mark);
        },
        "the deletion plan did not arrive as a keyed event");
    if (const auto index =
            indexOf(startup.log,
                    [](const Entry &entry) {
                        const auto *event = std::get_if<ProjectEvent>(&entry);
                        return event && std::holds_alternative<RegistrationPlanResult>(*event);
                    });
        index >= 0) {
        const auto &plan =
            std::get<RegistrationPlanResult>(std::get<ProjectEvent>(startup.log[index]));
        fx.check(plan.song == *fx.route101, "the registration plan lost its song key");
    }
}

// ---- silent completions advance the FIFO without a publication -------------
void checkSilentCompletions(FlowFixture &fx, StartupSession &startup)
{
    auto mark = startup.log.size();
    // Two keyless silent completions queue one behind the other and advance
    // the FIFO to the probe without any public publication.
    startup.restorer.submit(ProjectOperation{CleanupPreviewInput{}});
    startup.restorer.submit(ProjectOperation{CleanupPreviewInput{}});
    startup.restorer.submit(ProjectOperation{ProbeSamplesInput{}});
    fx.waitFor([&] { return startup.log.size() > mark; },
               "the silent completions did not advance the FIFO to the next probe");
    fx.check(startup.log.size() == mark + 1, "a silent completion published a public result");
    if (startup.log.size() == mark + 1) {
        const auto *event = std::get_if<ProjectEvent>(&startup.log[mark]);
        fx.check(event && std::holds_alternative<SamplesProbed>(*event),
                 "the FIFO did not advance straight to the probe publication");
    }
}

// ---- ordered song load: stages, keyed bank view, terminal bound ------------
//
// Returns the reloaded bank view the edit scenarios work against; the
// pointer stays valid because the log only ever appends.
const LoadedBankView *checkOrderedSongReload(FlowFixture &fx, StartupSession &startup)
{
    auto mark = startup.log.size();
    startup.restorer.submit(ProjectOperation{OpenSongInput{*fx.route101}});
    fx.waitFor([&] { return startup.log.size() >= mark + 3; },
               "the song reload did not deliver its three ordered publications");
    fx.check(startup.log.size() == mark + 3, "the song reload delivered extra publications");
    if (startup.log.size() == mark + 3) {
        const auto *midi = std::get_if<SongUpdate>(&startup.log[mark]);
        const auto *viewEntry = std::get_if<ProjectEvent>(&startup.log[mark + 1]);
        const auto *bound = std::get_if<SongUpdate>(&startup.log[mark + 2]);
        fx.check(midi && std::holds_alternative<MidiStage>(midi->payload) &&
                     midi->song == *fx.route101,
                 "the reload did not publish the keyed MIDI stage first");
        fx.check(viewEntry && std::holds_alternative<LoadedBankView>(*viewEntry),
                 "the reload did not publish the keyed bank view before its bound update");
        fx.check(bound && std::holds_alternative<VoicegroupBound>(bound->payload) &&
                     bound->song == *fx.route101,
                 "the reload did not publish the terminal bound update last");
    }
    return publishedBankView(startup.log, mark + 1);
}

// ---- voicegroup edits: conflict, applied view + receipt, hard failure ------

// A filled slot re-submitted as expecting-blank confirms the keyed conflict.
void checkEditConflict(FlowFixture &fx, StartupSession &startup, const LoadedBankView &view,
                       int filled)
{
    const auto mark = startup.log.size();
    startup.restorer.submit(ProjectOperation{VoicegroupEditInput{
        view.id, SetVoicegroupSlot{filled, *view.slotViews[filled].voice, std::nullopt}}});
    fx.waitFor(
        [&] {
            return indexOf(startup.log, [](const Entry &entry) {
                       const auto *event = std::get_if<ProjectEvent>(&entry);
                       return event && std::holds_alternative<VoicegroupEditConflict>(*event);
                   }) >= int(mark);
        },
        "the expected-state mismatch did not publish a keyed conflict");
}

// A scalar edit with the expected voice applies: the canonical bank
// replacement event arrives with the keyed receipt.
void checkEditApplied(FlowFixture &fx, StartupSession &startup, const LoadedBankView &view,
                      int filled)
{
    auto edited = *view.slotViews[filled].voice;
    edited.key += 1;
    const auto mark = startup.log.size();
    startup.restorer.submit(ProjectOperation{VoicegroupEditInput{
        view.id, SetVoicegroupSlot{filled, edited, *view.slotViews[filled].voice}}});
    fx.waitFor([&] { return startup.log.size() >= mark + 2; },
               "the applied edit did not publish its view and receipt");
    fx.check(startup.log.size() == mark + 2,
             "the applied edit published an unexpected publication count");
    if (startup.log.size() == mark + 2) {
        const auto *appliedView = std::get_if<ProjectEvent>(&startup.log[mark]);
        const auto *receipt = std::get_if<ProjectEvent>(&startup.log[mark + 1]);
        fx.check(appliedView && std::holds_alternative<LoadedBankView>(*appliedView),
                 "the applied edit did not publish the canonical bank view first");
        if (receipt) {
            const auto *applied = std::get_if<VoicegroupEditApplied>(&*receipt);
            fx.check(applied && applied->voicegroup == view.id,
                     "the applied edit did not publish the keyed receipt second");
        }
    }
}

// A hard worker error maps to the keyed mutation failure.
void checkEditHardFailure(FlowFixture &fx, StartupSession &startup, const LoadedBankView &view,
                          int filled)
{
    const auto ghost =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/porydaw_ghost.inc"), QString());
    fx.check(ghost.has_value(), "the fabricated voicegroup identity was rejected");
    if (!ghost)
        return;
    const auto mark = startup.log.size();
    startup.restorer.submit(ProjectOperation{VoicegroupEditInput{
        *ghost, SetVoicegroupSlot{0, *view.slotViews[filled].voice, std::nullopt}}});
    fx.waitFor(
        [&] {
            return indexOf(startup.log, [&](const Entry &entry) {
                       const auto *failure = mutationFailure<VoicegroupMutationFailed>(entry);
                       return failure && failure->voicegroup == *ghost &&
                              !failure->message.isEmpty();
                   }) >= int(mark);
        },
        "the hard edit error did not publish the keyed voicegroup failure");
}

// The reloaded bank view is exercised through a filled slot: the
// expecting-blank conflict, the applied view and receipt, and the hard
// error keyed to a fabricated voicegroup.
void checkVoicegroupEdits(FlowFixture &fx, StartupSession &startup, const LoadedBankView *view)
{
    fx.check(view && static_cast<bool>(view->bank) && !view->slotViews.isEmpty(),
             "the reload's bank view carried no usable lease");
    if (!view || view->slotViews.isEmpty())
        return;
    const auto filled = firstFilledSlot(*view);
    fx.check(filled >= 0, "the loaded bank view had no filled slots");
    if (filled < 0)
        return;
    checkEditConflict(fx, startup, *view, filled);
    checkEditApplied(fx, startup, *view, filled);
    checkEditHardFailure(fx, startup, *view, filled);
}

// Drives every workspace scenario in one sequential pass against the
// fixture project: the helper order below mirrors a single user flow, and
// later scenarios keep reading the restored startup session's log.
int checkWorkspaceFlows(const QString &projectRoot, int &failures)
{
    FlowFixture fx{projectRoot, failures};
    fx.check(fx.route101 && fx.petalburg && fx.missing,
             "fixture song labels were rejected as identities");
    if (!(fx.route101 && fx.petalburg && fx.missing))
        return failures;

    checkOpenRefusalAndOwnership(fx);

    writeStartupSavedSettings(projectRoot);
    // The wiring lands in this same turn; the constructor only queues the
    // saved open, so every startup publication arrives through these
    // connections on a later event-loop turn.
    StartupSession startup;
    fx.wire(startup.restorer, startup.log);

    const auto order = checkStartupRestoration(fx, startup);
    checkStartupReconcileFailure(fx, startup);
    checkAutomaticStartupCatalog(fx, startup, order);
    checkFailedReopenRetention(fx, startup);
    checkCatalogAndPlanEvents(fx, startup);
    checkSilentCompletions(fx, startup);
    const auto *bankView = checkOrderedSongReload(fx, startup);
    checkVoicegroupEdits(fx, startup, bankView);

    fx.checkInvariants(fx.openLog);
    fx.checkInvariants(startup.log);

    clearSavedProjectSettings();
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
