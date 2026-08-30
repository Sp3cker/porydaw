#include "project/projectworkspace.h"

#include "project/projectio.h"

#include <QSettings>

#include <utility>
#include <variant>

// ProjectWorkspace is the project-wide module behind the public seam in
// projectworkspace.h. It owns the private ProjectIo transport, holds the
// published ProjectState, maps every private staged and terminal result
// exhaustively onto the three public streams (keyed project events, keyed
// song updates, and state publications), and owns the startup QSettings
// recipe: an independent read through normalizeSavedRecipe plus write
// ownership of the last project path after a successful open.

namespace {

// QSettings keys this module reads or owns. The song keys belong to
// WorkspaceUi; they are read here for the matching startup projectPath only.
constexpr auto kLastProjectDirKey = "lastProjectDir";
constexpr auto kLastOpenSongsKey = "lastOpenSongs";
constexpr auto kLastSongLabelKey = "lastSongLabel";

template <typename... Ts>
struct OutcomeVisitor : Ts... {
    using Ts::operator()...;
};
template <typename... Ts>
OutcomeVisitor(Ts...) -> OutcomeVisitor<Ts...>;

SavedWorkspaceRecipe readStartupRecipe()
{
    const QSettings settings;
    return normalizeSavedRecipe(settings.value(QLatin1String(kLastProjectDirKey)).toString(),
                                settings.value(QLatin1String(kLastOpenSongsKey)).toStringList(),
                                settings.value(QLatin1String(kLastSongLabelKey)).toString());
}

bool isTerminalSongLoad(const ProjectCommand &command)
{
    return std::holds_alternative<OpenSongInput>(command) ||
           std::holds_alternative<ReloadSongInput>(command) ||
           std::holds_alternative<LoadSongCommand>(command) ||
           std::holds_alternative<LoadVoicegroupCommand>(command);
}

} // namespace

// ---- mapping machinery --------------------------------------------------------

class ProjectWorkspace::Private
{
  public:
    explicit Private(ProjectWorkspace *published)
        : owner(published)
        , io([this](ProjectResult result, std::optional<ProjectCommand> command) {
            handleResult(std::move(result), std::move(command));
        })
        , startup(readStartupRecipe())
    {
        // Startup restoration queues one asynchronous open for a later
        // event-loop turn: neither construction nor the owner's signal
        // wiring observes a publication, and construction never waits for
        // project work. The saved song names enqueue only after that open
        // has published Ready.
        startupPending = !startup.projectPath.isEmpty();
        if (startupPending) {
            QMetaObject::invokeMethod(
                owner,
                [this] {
                    if (!startupPending)
                        return;
                    if (state.state != ProjectOpenState::Closed) {
                        startupPending = false; // a user-driven open superseded the recipe
                        return;
                    }
                    openProject(OpenProjectInput{startup.projectPath});
                },
                Qt::QueuedConnection);
        }
    }

    void openProject(OpenProjectInput input)
    {
        // Refuse only while one open is active; a call in any other state
        // queues a new open.
        if (state.state == ProjectOpenState::Loading)
            return;
        postSongStartupWorkPending = false;
        auto loading = state; // the prior snapshot may stay visible during Loading
        loading.state = ProjectOpenState::Loading;
        loading.error.reset();
        loading.catalog = {};
        publishState(std::move(loading));
        io.submit(ProjectCommand{OpenProjectInput{std::move(input.root)}});
    }

    void submit(ProjectOperation operation)
    {
        std::visit([this](auto &&input) { io.submit(ProjectCommand{std::move(input)}); },
                   std::move(operation));
    }

    ProjectWorkspace *owner;
    ProjectIo io;
    ProjectState state;
    SavedWorkspaceRecipe startup;
    // One-shot: the saved recipe belongs to the startup open only; a later
    // user-driven open never enqueues saved songs.
    bool startupPending = false;
    // Initial catalog work and cache validation stay behind the first song's
    // terminal result, or Ready when no startup song was restored, so remote
    // scans never delay cache-backed playability or remain pending forever.
    bool postSongStartupWorkPending = false;

  private:
    void handleResult(ProjectResult result, std::optional<ProjectCommand> command)
    {
        std::visit(
            OutcomeVisitor{
                // ---- ordered song publications; the payload carries its key ----
                [this](MidiStage &stage) { publishSongUpdate(std::move(stage)); },
                [this](SidecarStage &stage) { publishSongUpdate(std::move(stage)); },
                [this](LoadedBankView &view) {
                    emit owner->projectEventPublished(std::move(view));
                },
                [this, &command](VoicegroupBound &bound) {
                    publishSongUpdate(std::move(bound));
                    schedulePostSongStartupWork(command);
                },
                [this](SongSaved &saved) { publishSongUpdate(std::move(saved)); },

                // ---- voicegroup edit outcomes -----------------------------------
                [this](VoicegroupEditResult &edit) {
                    std::visit(OutcomeVisitor{
                                   [this](VoicegroupEditAppliedResult &applied) {
                                       auto id = applied.view.id;
                                       auto materialization = std::move(applied.materialization);
                                       // The view remains the canonical bank replacement
                                       // event; the keyed receipt only carries the fresh
                                       // blank-slot token for a pending history transition.
                                       emit owner->projectEventPublished(std::move(applied.view));
                                       emit owner->projectEventPublished(
                                           ProjectEvent{VoicegroupEditApplied{
                                               std::move(id), std::move(materialization)}});
                                   },
                                   [this](VoicegroupEditConflictResult &conflict) {
                                       emit owner->projectEventPublished(ProjectEvent{
                                           VoicegroupEditConflict{std::move(conflict.voicegroup)}});
                                   },
                               },
                               edit);
                },

                // ---- project and catalog state ------------------------------------
                [this, &command](ProjectSnapshot &snapshot) {
                    // A deferred validation can finish after a user has
                    // started switching projects. Its refreshed old snapshot
                    // must not replace the new Loading/Ready state.
                    if (command && std::holds_alternative<ValidateProjectIndexCommand>(*command) &&
                        (state.state != ProjectOpenState::Ready ||
                         state.snapshot.root() != snapshot.root()))
                        return;
                    acceptSnapshot(std::move(snapshot), *command);
                },
                [this](VoicegroupCatalog &catalog) {
                    // A catalog scan may have started just before a project
                    // switch. Do not publish that old root into the new
                    // loading or ready state.
                    if (state.state != ProjectOpenState::Ready ||
                        state.snapshot.root() != catalog.root)
                        return;
                    // Catalog replacement keeps the current state, snapshot, and
                    // error invariant intact.
                    auto next = state;
                    next.catalog = std::move(catalog);
                    publishState(std::move(next));
                },

                // ---- keyed events forwarded unchanged -------------------------------
                [this](RegistrationPlanResult &event) {
                    emit owner->projectEventPublished(std::move(event));
                },
                [this](DeletionPlanResult &event) {
                    emit owner->projectEventPublished(std::move(event));
                },
                [this](PreviewPlan &event) { emit owner->projectEventPublished(std::move(event)); },
                [this](PreviewReady &event) {
                    emit owner->projectEventPublished(std::move(event));
                },
                [this](SampleSetReady &event) {
                    emit owner->projectEventPublished(std::move(event));
                },
                [this](SamplesProbed &event) {
                    emit owner->projectEventPublished(std::move(event));
                },
                [this](SampleRead &event) { emit owner->projectEventPublished(std::move(event)); },
                [this](SampleCommitted &event) {
                    emit owner->projectEventPublished(std::move(event));
                },
                [this](SongCreated &event) { emit owner->projectEventPublished(std::move(event)); },
                [](IndexValidated &) {},

                // ---- silent completions ------------------------------------------------
                // A standalone sidecar write and a preview cleanup advance the
                // FIFO without a public event; so do their hard errors below.
                [](SidecarWriteResult &) {},
                [](PreviewCleanupCompleted &) {},

                // ---- private failures ------------------------------------------------------
                [this, &command](SongCommandFailure &failure) {
                    emit owner->songUpdatePublished(SongUpdate{
                        std::move(failure.song),
                        SongPayload{SongFailed{failure.stage, std::move(failure.message)}}});
                    schedulePostSongStartupWork(command);
                },
                [this, &command](CommandFailure &failure) {
                    publishFailure(*command, std::move(failure));
                },
            },
            result);
    }

    template <typename Payload>
    void publishSongUpdate(Payload payload)
    {
        auto key = payload.song;
        emit owner->songUpdatePublished(
            SongUpdate{std::move(key), SongPayload{std::move(payload)}});
    }

    void publishState(ProjectState next)
    {
        state = next;
        emit owner->projectStatePublished(std::move(next));
    }

    void acceptSnapshot(ProjectSnapshot snapshot, const ProjectCommand &command)
    {
        const auto isOpen = std::holds_alternative<OpenProjectInput>(command);
        const bool refreshCatalog = isOpen ||
                                    std::holds_alternative<RefreshProjectInput>(command) ||
                                    std::holds_alternative<DeleteSongInput>(command);
        if (isOpen) {
            // Write ownership of the last project path: only a successful
            // open records it.
            QSettings settings;
            settings.setValue(QLatin1String(kLastProjectDirKey), snapshot.root());
        }
        auto next = std::move(state);
        next.state = ProjectOpenState::Ready;
        next.snapshot = std::move(snapshot);
        next.error.reset();
        publishState(std::move(next));
        // Ready is published before the first startup OpenSong submission.
        if (isOpen) {
            postSongStartupWorkPending = true;
            auto queuedStartupSong = false;
            if (startupPending) {
                startupPending = false;
                queuedStartupSong = submitStartupSongs();
            }
            if (!queuedStartupSong)
                schedulePostSongStartupWork();
        } else if (refreshCatalog) {
            io.submit(ProjectCommand{RefreshCatalogInput{}});
        }
    }

    void schedulePostSongStartupWork(const std::optional<ProjectCommand> &command = std::nullopt)
    {
        if (!postSongStartupWorkPending)
            return;
        if (command && !isTerminalSongLoad(*command))
            return;
        postSongStartupWorkPending = false;
        io.submitDeferred(ProjectCommand{RefreshCatalogInput{}});
        io.submitDeferred(ProjectCommand{ValidateProjectIndexCommand{}});
    }

    bool submitStartupSongs()
    {
        // Selected first, then the other normalized names in persisted
        // order; each result is an ordinary keyed SongUpdate. There is no
        // startup-name tracking collection: the recipe is consumed once here.
        auto queued = false;
        if (startup.selected) {
            io.submit(ProjectCommand{OpenSongInput{*startup.selected}});
            queued = true;
        }
        for (const auto &song : startup.orderedSongs) {
            if (!startup.selected || !(song == *startup.selected)) {
                io.submit(ProjectCommand{OpenSongInput{song}});
                queued = true;
            }
        }
        startup.orderedSongs.clear();
        startup.selected.reset();
        return queued;
    }

    void publishLabelFailure(const QString &label, QString message)
    {
        auto song = SongName::create(label);
        if (song)
            emit owner->projectEventPublished(
                ProjectEvent{SongMutationFailed{std::move(*song), std::move(message)}});
        else
            emit owner->projectEventPublished(
                ProjectEvent{CatalogMutationFailed{std::move(message)}});
    }

    // Exhaustive per-command mapping of the private non-song failure; song
    // commands never pair with CommandFailure, and CatalogMutationFailed is
    // the only public unkeyed mutation failure.
    void publishFailure(const ProjectCommand &command, CommandFailure &&failure)
    {
        std::visit(
            OutcomeVisitor{
                // Open failure is the only present-error state and keeps the
                // prior snapshot intact.
                [this, &failure](const OpenProjectInput &) {
                    auto failed = state;
                    failed.state = ProjectOpenState::Failed;
                    failed.error = std::move(failure.message);
                    startupPending = false; // the saved recipe belongs to that open only
                    publishState(std::move(failed));
                },

                [this, &failure](const RefreshProjectInput &) {
                    emitCatalogFailure(std::move(failure.message));
                },
                [this, &failure](const CreateVoicegroupInput &) {
                    emitCatalogFailure(std::move(failure.message));
                },
                [this, &failure](const RefreshCatalogInput &) {
                    emitCatalogFailure(std::move(failure.message));
                },
                [this, &failure](const LoadSampleSetInput &) {
                    emitCatalogFailure(std::move(failure.message));
                },
                [this, &failure](const ProbeSamplesInput &) {
                    emitCatalogFailure(std::move(failure.message));
                },

                // Only the explicitly cosmetic completions stay silent.
                [](const CleanupPreviewInput &) {},
                [](const SaveSidecarInput &) {},
                [](const ValidateProjectIndexCommand &) {},

                [this, &failure](const VoicegroupEditInput &input) {
                    emit owner->projectEventPublished(ProjectEvent{
                        VoicegroupMutationFailed{input.id, std::move(failure.message)}});
                },
                [this, &failure](const PreviewPlanInput &input) {
                    emit owner->projectEventPublished(ProjectEvent{
                        VoicegroupMutationFailed{input.voicegroup, std::move(failure.message)}});
                },
                [this, &failure](const PreviewInput &input) {
                    emit owner->projectEventPublished(ProjectEvent{
                        VoicegroupMutationFailed{input.voicegroup, std::move(failure.message)}});
                },

                [this, &failure](const CreateSongInput &input) {
                    publishLabelFailure(input.label, std::move(failure.message));
                },
                [this, &failure](const RegistrationPlanInput &input) {
                    publishLabelFailure(input.label, std::move(failure.message));
                },
                [this, &failure](const RegisterSongInput &input) {
                    publishLabelFailure(input.label, std::move(failure.message));
                },
                [this, &failure](const DeletionPlanInput &input) {
                    emit owner->projectEventPublished(
                        ProjectEvent{SongMutationFailed{input.song, std::move(failure.message)}});
                },
                [this, &failure](const DeleteSongInput &input) {
                    emit owner->projectEventPublished(
                        ProjectEvent{SongMutationFailed{input.song, std::move(failure.message)}});
                },

                [this, &failure](const ReadSampleInput &input) {
                    emit owner->projectEventPublished(
                        ProjectEvent{SampleMutationFailed{input.name, std::move(failure.message)}});
                },
                [this, &failure](const CommitSampleInput &input) {
                    emit owner->projectEventPublished(
                        ProjectEvent{SampleMutationFailed{input.name, std::move(failure.message)}});
                },

                [](const OpenSongInput &) { Q_ASSERT(false); },
                [](const ReloadSongInput &) { Q_ASSERT(false); },
                [](const LoadSongCommand &) { Q_ASSERT(false); },
                [](const ReadSidecarCommand &) { Q_ASSERT(false); },
                [](const LoadVoicegroupCommand &) { Q_ASSERT(false); },
                [](const SaveSongInput &) { Q_ASSERT(false); },
            },
            command);
    }

    void emitCatalogFailure(QString message)
    {
        // A catalog command can finish just after a project switch has made
        // the previous snapshot unavailable. Its failure is no longer useful
        // to the newly loading project.
        if (state.state != ProjectOpenState::Ready)
            return;
        emit owner->projectEventPublished(ProjectEvent{CatalogMutationFailed{std::move(message)}});
    }
};

// ---- public surface ------------------------------------------------------------

ProjectWorkspace::ProjectWorkspace(QObject *parent) : QObject(parent), d(new Private(this)) {}

ProjectWorkspace::~ProjectWorkspace()
{
    delete d; // joins the worker and releases undelivered owning resources
}

void ProjectWorkspace::openProject(OpenProjectInput input)
{
    d->openProject(std::move(input));
}

void ProjectWorkspace::submit(ProjectOperation operation)
{
    d->submit(std::move(operation));
}
