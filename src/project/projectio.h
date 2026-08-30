#pragma once

#include <QObject>

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <variant>

#include "projectworkspace.h"

class QThread;

// ---- Private worker commands and results ------------------------------------
//
// ProjectIo is the private transport behind ProjectWorkspace: one semantic
// command at a time on a worker thread, results delivered back to the owner
// in order. Staged results reach the sink alone; the terminal result is
// delivered together with the original moved command so the owner can key
// its publications without any request ID or envelope. The variants hold the
// public input types from projectworkspace.h directly whenever no worker
// enrichment is added; the only private command alternatives beyond those
// inputs are the load stage tags below. They never cross the
// ProjectWorkspace seam and carry no cached catalog rows.

// The real private stage tags for the ordered song-load flow.
struct LoadSongCommand {
    SongName song;
};
struct LoadVoicegroupCommand {
    SongName song;
    VoicegroupId voicegroup;
};
// Private terminal result for a preempted catalog scan. It never reaches the
// ProjectWorkspace sink: ProjectIo appends one replacement refresh instead.
struct CatalogScanCancelled {};
// Private CleanupPreviewInput success; consumed without a public event.
struct PreviewCleanupCompleted {};

// Every alternative has a terminal private result in ProjectResult; every
// hard worker error becomes SongCommandFailure for a song command or
// CommandFailure for every other command.
using ProjectCommand =
    std::variant<OpenProjectInput, RefreshProjectInput, OpenSongInput, ReloadSongInput,
                 LoadSongCommand, LoadVoicegroupCommand, SaveSongInput, VoicegroupEditInput,
                 CreateSongInput, CreateVoicegroupInput, RegistrationPlanInput, RegisterSongInput,
                 DeletionPlanInput, DeleteSongInput, PreviewPlanInput, PreviewInput,
                 CleanupPreviewInput, RefreshCatalogInput, LoadSampleSetInput, ProbeSamplesInput,
                 ReadSampleInput, CommitSampleInput>;

struct SongCommandFailure {
    SongName song;
    SongStage stage;
    QString message;
};
struct CommandFailure {
    QString message;
};

// Total over ProjectCommand. Load commands may emit staged values before
// terminal VoicegroupBound; a semantic SaveSongInput delivers its independent
// LoadedBankView early and ends with one terminal SongSaved or
// SongCommandFailure.
using ProjectResult =
    std::variant<ProjectSnapshot, MidiStage, LoadedBankView, VoicegroupBound, VoicegroupEditResult,
                 CatalogScanCancelled, PreviewCleanupCompleted, SongSaved, RegistrationPlanResult,
                 DeletionPlanResult, PreviewPlan, PreviewReady, SampleSetReady, SamplesProbed,
                 SampleRead, SampleCommitted, SongCreated, VoicegroupCatalog, SongCommandFailure,
                 CommandFailure>;

// One queued delivery: a staged or terminal result, and — on the terminal
// result only — the original moved command, so the owner can key its
// publications without a request ID or envelope. No large command is ever
// copied for this pairing.
struct Delivery {
    ProjectResult result;
    std::optional<ProjectCommand> command;
};

// Owner of the project worker thread: one active FIFO command, one private
// result callback. Catalog work cooperatively yields to a submitted song and
// requeues one refresh at the FIFO tail. No request IDs, envelopes, cached
// catalog rows, or GUI types cross this seam. There is no per-command
// cancellation or old-result filter; a closed loading tab is WorkspaceUi
// tombstone policy. Shutdown stops accepting commands, finishes or discards
// the active result, releases undelivered owning resources, and joins the
// worker.
class ProjectIo final : public QObject
{
  public:
    using ResultSink = std::function<void(ProjectResult, std::optional<ProjectCommand>)>;

    explicit ProjectIo(ResultSink sink, QObject *parent = nullptr);
    ~ProjectIo() override;

    ProjectIo(const ProjectIo &) = delete;
    ProjectIo &operator=(const ProjectIo &) = delete;
    ProjectIo(ProjectIo &&) = delete;
    ProjectIo &operator=(ProjectIo &&) = delete;

    void submit(ProjectCommand command);

  private:
    class Worker;

    void dispatchNext();
    void postResult(ProjectResult result, std::optional<ProjectCommand> command);
    void completeCommand();
    void drainResults();
    void finishResult(Delivery &&delivery);

    QThread *m_thread = nullptr;
    Worker *m_worker = nullptr;
    ResultSink m_sink;
    std::deque<ProjectCommand> m_queue;
    bool m_active = false;
    bool m_activeCatalog = false;
    std::deque<Delivery> m_results;
    std::atomic_bool m_shuttingDown = false;
    std::atomic_bool m_cancelCatalog = false;
    std::mutex m_resultMutex;
};
