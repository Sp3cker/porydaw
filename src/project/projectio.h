#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QHash>
#include <QList>
#include <QObject>
#include <QString>
#include <QVector>

#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <variant>

#include "core/smf.h"
#include "core/songdocument.h"
#include "decompproject.h"
#include "samplereg.h"
#include "sidecar.h"
#include "songregistry.h"
#include "ui/viewsidecar.h"
#include "voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

class QThread;

struct ProjectOpenResult {
    ProjectSnapshot snapshot;
    QString error;

    bool succeeded() const { return snapshot.isOpen(); }
};

struct SongFileResult {
    uint64_t requestId = 0;
    SmfFile smf;
    QString error;

    bool succeeded() const { return error.isEmpty(); }
};

struct VoicegroupLoadResult {
    uint64_t requestId = 0;
    LoadedVoiceGroup *voicegroup = nullptr;
    std::unique_ptr<VoicegroupSource> source;
    QString filePath;
    QDateTime fileTime;
    QString error;

    bool succeeded() const { return voicegroup != nullptr; }
};

struct VoicegroupProbeResult {
    uint64_t requestId = 0;
    QString filePath;
    QDateTime fileTime;
    QString error;

    bool succeeded() const { return !filePath.isEmpty(); }
};

struct VoicegroupSaveRequest {
    QString projectRoot;
    QString filePath;
    QByteArray sourceBytes;
    QList<QPair<QString, VgSynthDesc>> synthDefinitions;
};

struct VoicegroupSaveResult {
    uint64_t requestId = 0;
    bool synthOk = false;
    bool sourceOk = false;
    QDateTime fileTime;
    QString error;

    bool succeeded() const { return synthOk && sourceOk; }
};

// flagsWritten is true only when the optional flags stage completed
// successfully; flagsOk is true without it when no rewrite was needed.
struct SaveSongResult {
    uint64_t requestId = 0;
    bool midiOk = false;
    bool flagsOk = false;
    bool flagsWritten = false;
    QString error;

    bool succeeded() const { return midiOk && flagsOk; }
};

using SaveCompletion = std::function<void(SaveSongResult)>;

struct SidecarLoadRequest {
    QString projectRoot;
    QString songLabel;
};

struct SidecarSaveRequest {
    QString projectRoot;
    QString songLabel;
    ViewSidecar::Snapshot snapshot;
};

struct SidecarLoadResult {
    uint64_t requestId = 0;
    bool loaded = false;
    ViewSidecar::Snapshot snapshot;
    QString error;

    bool succeeded() const { return loaded; }
};

struct SidecarSaveResult {
    uint64_t requestId = 0;
    bool saved = false;
    QString error;

    bool succeeded() const { return saved; }
};
using SidecarLoadCompletion = std::function<void(SidecarLoadResult)>;
using SidecarSaveCompletion = std::function<void(SidecarSaveResult)>;

// Plan probes are detached read-only snapshots. A confirming write always
// re-derives its plan on the worker because these values may be stale.
struct RegistrationPlanRequest {
    QString projectRoot;
    QString label;
    QString constant;
    QString player;
};

struct RegistrationPlanResult {
    uint64_t requestId = 0;
    RegistrationPlan plan;
    RegistrationStatus status;
    QString error;

    bool succeeded() const { return error.isEmpty(); }
};

struct RegisterSongRequest {
    QString projectRoot;
    QString label;
    QString constant;
    QString player;
};

struct RegisterSongResult {
    uint64_t requestId = 0;
    bool registered = false;
    int songId = -1;
    QString error;

    bool succeeded() const { return registered; }
};

struct DeletionPlanRequest {
    QString projectRoot;
    QString label;
    QString constant;
    QVector<SongInfo> songs;
};

struct DeletionPlanResult {
    uint64_t requestId = 0;
    RemovalPlan plan;
    QString deletableVoicegroupName;
    QString error;

    bool succeeded() const { return error.isEmpty(); }
};

struct DeleteSongRequest {
    QString projectRoot;
    QString label;
    QString constant;
    QString deleteVoicegroupName;
};

struct DeleteSongResult {
    uint64_t requestId = 0;
    QString error;

    bool succeeded() const { return error.isEmpty(); }
};

struct PreviewRequest {
    QString projectRoot;
    QString loadName;
    QByteArray sourceBytes;
};

struct PreviewPlanRequest {
    QString projectRoot;
    QString loadName;
};

struct PreviewPlanResult {
    uint64_t requestId = 0;
    QString shadowSourcePath;
    QString targetIncPath;
    QString error;

    bool succeeded() const { return error.isEmpty(); }
};
struct PreviewResult {
    uint64_t requestId = 0;
    LoadedVoiceGroup *voicegroup = nullptr;
    QString error;

    bool succeeded() const { return voicegroup != nullptr; }
};

struct CatalogResult {
    uint64_t requestId = 0;
    VgCatalogScan catalog;
    VgDirectSoundScan directSound;
    QStringList progWave;
    bool perFileVoicegroups = false;
    QString error;

    bool succeeded() const { return error.isEmpty(); }
};

struct SampleSetRequest {
    QString projectRoot;
    QStringList samples;
    QStringList waves;
    QList<QPair<QString, QString>> keysplits;
};

struct SampleSetResult {
    uint64_t requestId = 0;
    LoadedSampleSet *sampleSet = nullptr;
    QString error;

    bool succeeded() const { return sampleSet != nullptr; }
};

struct SampleProbeResult {
    uint64_t requestId = 0;
    SampleFormatProbe probe;
    QString error;

    bool succeeded() const { return probe.ok(); }
};

struct SampleProjectResult {
    uint64_t requestId = 0;
    SampleFormatProbe probe;
    bool sidecarLoaded = false;
    SampleSidecar sidecar;
    QByteArray wavBytes;
    QString wavPath;
    QString error;

    bool succeeded() const { return probe.ok() && !wavBytes.isEmpty(); }
};

struct SampleCommitRequest {
    QString projectRoot;
    QString name;
    QByteArray wavBytes;
    std::optional<SampleSidecar> sidecar;
    bool removeSidecar = false;
    bool update = false;
};

struct SampleCommitResult {
    uint64_t requestId = 0;
    bool committed = false;
    bool sidecarSaved = false;
    QString sidecarError;
    QString error;

    bool succeeded() const { return committed; }
};

struct CreateSongRequest {
    QString projectRoot;
    QString label;
    QString constant;
    QString player;
    SongCfg cfg;
    QString newVoicegroup;
    SmfFile smf;
};

struct CreateSongResult {
    uint64_t requestId = 0;
    bool voicegroupOk = true;
    bool midiOk = false;
    bool flagsOk = false;
    bool registered = false;
    int songId = -1;
    QString error;

    bool succeeded() const { return midiOk && flagsOk && registered; }
};

struct CreateVoicegroupRequest {
    QString projectRoot;
    QString name;
    QString copyFromFile;
    QString copySectionLabel;
};

struct CreateVoicegroupResult {
    uint64_t requestId = 0;
    bool created = false;
    QString error;

    bool succeeded() const { return created; }
};

struct PreviewCleanupResult {
    uint64_t requestId = 0;
    bool cleaned = false;
    QString error;
};

// GUI-facing owner of the project worker thread. Requests are accepted and
// ordered on this object's thread; one request at a time executes on the
// worker and its detached result is delivered back here.
class ProjectIo final : public QObject
{
  public:
    using OpenCompletion = std::function<void(ProjectOpenResult)>;

    explicit ProjectIo(QObject *parent = nullptr);
    ~ProjectIo() override;

    uint64_t openProject(QString root, OpenCompletion completion);
    uint64_t loadSongFile(SongInfo song, std::function<void(SongFileResult)> completion);
    uint64_t loadVoicegroup(QString root, SongCfg cfg,
                            std::function<void(VoicegroupLoadResult)> completion);
    uint64_t probeVoicegroup(QString root, SongCfg cfg,
                             std::function<void(VoicegroupProbeResult)> completion);
    void cancel(uint64_t requestId);

    uint64_t saveSong(SongSaveSnapshot snapshot, SaveCompletion completion);
    uint64_t saveVoicegroup(VoicegroupSaveRequest request,
                            std::function<void(VoicegroupSaveResult)> completion);
    uint64_t previewPlan(PreviewPlanRequest request,
                         std::function<void(PreviewPlanResult)> completion);
    uint64_t readSidecar(SidecarLoadRequest request, SidecarLoadCompletion completion);
    uint64_t writeSidecar(SidecarSaveRequest request, SidecarSaveCompletion completion);
    uint64_t registrationPlan(RegistrationPlanRequest request,
                              std::function<void(RegistrationPlanResult)> completion);
    uint64_t registerSong(RegisterSongRequest request,
                          std::function<void(RegisterSongResult)> completion);
    uint64_t deletionPlan(DeletionPlanRequest request,
                          std::function<void(DeletionPlanResult)> completion);
    uint64_t deleteSong(DeleteSongRequest request,
                        std::function<void(DeleteSongResult)> completion);
    uint64_t preview(PreviewRequest request, std::function<void(PreviewResult)> completion);
    uint64_t cleanupPreview(QString projectRoot,
                            std::function<void(PreviewCleanupResult)> completion = {});
    uint64_t refreshVgCatalog(QString projectRoot, std::function<void(CatalogResult)> completion);
    uint64_t loadSampleSet(SampleSetRequest request,
                           std::function<void(SampleSetResult)> completion);
    uint64_t probeSamples(QString projectRoot, std::function<void(SampleProbeResult)> completion);
    uint64_t readProjectSample(QString projectRoot, QString name,
                               std::function<void(SampleProjectResult)> completion);
    uint64_t commitSample(SampleCommitRequest request,
                          std::function<void(SampleCommitResult)> completion);
    uint64_t createSong(CreateSongRequest request,
                        std::function<void(CreateSongResult)> completion);
    uint64_t createVoicegroup(CreateVoicegroupRequest request,
                              std::function<void(CreateVoicegroupResult)> completion);

  private:
    enum class RequestKind {
        OpenProject,
        LoadSongFile,
        LoadVoicegroup,
        ProbeVoicegroup,
        SaveSong,
        SaveVoicegroup,
        ReadSidecar,
        WriteSidecar,
        RegistrationPlan,
        RegisterSong,
        DeletionPlan,
        DeleteSong,
        PreviewPlan,
        Preview,
        CleanupPreview,
        RefreshVgCatalog,
        LoadSampleSet,
        ProbeSamples,
        ReadProjectSample,
        CommitSample,
        CreateSong,
        CreateVoicegroup,
    };

    struct Request {
        uint64_t id = 0;
        RequestKind kind = RequestKind::OpenProject;
        QString root;
        QString songLabel;
        SongInfo song;
        SongCfg cfg;
        SongSaveSnapshot saveSnapshot;
        VoicegroupSaveRequest voicegroupSave;
        SidecarLoadRequest sidecarLoad;
        SidecarSaveRequest sidecarSave;
        RegistrationPlanRequest registrationPlan;
        RegisterSongRequest registerSong;
        DeletionPlanRequest deletionPlan;
        DeleteSongRequest deleteSong;
        PreviewPlanRequest previewPlan;
        PreviewRequest preview;
        SampleSetRequest sampleSet;
        SampleCommitRequest sampleCommit;
        CreateSongRequest createSong;
        CreateVoicegroupRequest createVoicegroup;
        OpenCompletion openCompletion;
        std::function<void(SongFileResult)> songCompletion;
        std::function<void(VoicegroupLoadResult)> voicegroupCompletion;
        std::function<void(VoicegroupProbeResult)> voicegroupProbeCompletion;
        SaveCompletion saveCompletion;
        std::function<void(VoicegroupSaveResult)> voicegroupSaveCompletion;
        SidecarLoadCompletion sidecarLoadCompletion;
        SidecarSaveCompletion sidecarSaveCompletion;
        std::function<void(RegistrationPlanResult)> registrationPlanCompletion;
        std::function<void(RegisterSongResult)> registerSongCompletion;
        std::function<void(PreviewPlanResult)> previewPlanCompletion;
        std::function<void(DeletionPlanResult)> deletionPlanCompletion;
        std::function<void(DeleteSongResult)> deleteSongCompletion;
        std::function<void(PreviewResult)> previewCompletion;
        std::function<void(PreviewCleanupResult)> previewCleanupCompletion;
        std::function<void(CatalogResult)> catalogCompletion;
        std::function<void(SampleSetResult)> sampleSetCompletion;
        std::function<void(SampleProbeResult)> sampleProbeCompletion;
        std::function<void(SampleProjectResult)> sampleProjectCompletion;
        std::function<void(SampleCommitResult)> sampleCommitCompletion;
        std::function<void(CreateSongResult)> createSongCompletion;
        std::function<void(CreateVoicegroupResult)> createVoicegroupCompletion;
        bool cancelled = false;
    };

    struct WorkerResult {
        uint64_t requestId = 0;
        RequestKind kind = RequestKind::OpenProject;
        std::variant<ProjectOpenResult, SongFileResult, VoicegroupLoadResult, VoicegroupProbeResult,
                     SaveSongResult, VoicegroupSaveResult, SidecarLoadResult, SidecarSaveResult,
                     RegistrationPlanResult, RegisterSongResult, DeletionPlanResult,
                     DeleteSongResult, PreviewPlanResult, PreviewResult, PreviewCleanupResult,
                     CatalogResult, SampleSetResult, SampleProbeResult, SampleProjectResult,
                     SampleCommitResult, CreateSongResult, CreateVoicegroupResult>
            payload;
    };

    class Worker;

    void dispatchNext();
    void postResult(WorkerResult result);
    void drainResults();
    void finishResult(WorkerResult result);
    void discardResult(WorkerResult &result);
    static void clearCompletion(Request &request);
    void cancelOpenRequests();

    QThread *m_thread = nullptr;
    Worker *m_worker = nullptr;
    std::deque<Request> m_requests;
    std::optional<Request> m_active;
    uint64_t m_nextRequestId = 0;
    std::atomic_bool m_shuttingDown = false;
    std::mutex m_resultMutex;
    std::deque<WorkerResult> m_results;
};
