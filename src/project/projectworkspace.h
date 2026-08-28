#pragma once

#include <QByteArray>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>

#include <memory>
#include <optional>
#include <variant>

#include "core/smf.h"
#include "core/songdocument.h"
#include "decompproject.h"
#include "projectidentity.h"
#include "samplereg.h"
#include "songregistry.h"
#include "ui/viewsidecar.h"
#include "voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

// The public ProjectWorkspace seam: everything the GUI may see and submit,
// and nothing about worker scheduling or DecompProject storage. ProjectIo
// consumes the same declarations for its private command/result layer; the
// only private stage tags (load/read commands and worker outcomes) live
// behind ProjectIo and never appear here.

// ---- Project open state ----------------------------------------------------

enum class ProjectOpenState { Closed, Loading, Ready, Failed };

// One published catalog of the project's voicegroup resources.
struct VoicegroupCatalog {
    bool perFileVoicegroups = false;
    QStringList groupArgs;
    QStringList directSound;
    QStringList progWave;
    QList<QPair<QString, QString>> keysplits;
    QStringList drumkits;
    VgSynthCatalog synths;
    VgAdsrDefaults typicalAdsr;
};

// Exactly the four published open fields: no operation field, no busy flag.
// During Loading the prior snapshot may remain; a failed open keeps that
// snapshot and carries the only present error. Every other state has an
// absent error.
struct ProjectState {
    ProjectOpenState state = ProjectOpenState::Closed;
    ProjectSnapshot snapshot;
    VoicegroupCatalog catalog;
    std::optional<QString> error;
};

// ---- Keyed mutation failures (exhaustive) ----------------------------------

struct SongMutationFailed {
    SongName song;
    QString message;
};
struct VoicegroupMutationFailed {
    VoicegroupId voicegroup;
    QString message;
};
struct SampleMutationFailed {
    QString name;
    QString message;
};
struct CatalogMutationFailed {
    QString message; // the only unkeyed mutation failure
};

// Fixed to exactly these four alternatives: adding another must break every
// exhaustive visitor.
using ProjectMutationFailure = std::variant<SongMutationFailed, VoicegroupMutationFailed,
                                            SampleMutationFailed, CatalogMutationFailed>;

// ---- Keyed event results ----------------------------------------------------

struct RegistrationPlanResult {
    SongName song;
    RegistrationPlan plan;
    RegistrationStatus status;
};
struct DeletionPlanResult {
    SongName song;
    RemovalPlan plan;
    QString deletableVoicegroupName;
};
struct PreviewPlan {
    VoicegroupId voicegroup;
    QString shadowSourcePath;
    QString targetIncPath;
};
struct PreviewReady {
    VoicegroupId voicegroup;
    VoicegroupLease bank;
};

// Shared-ownership sample set handed to the one catalog dialog.
using SampleSetLease = std::shared_ptr<const LoadedSampleSet>;

struct SampleSetReady {
    SampleSetLease sampleSet;
}; // one catalog dialog
struct SamplesProbed {
    SampleFormatProbe probe;
}; // one catalog dialog
struct SampleRead {
    QString name;
    SampleFormatProbe probe;
    bool sidecarLoaded = false;
    SampleSidecar sidecar;
    QByteArray wavBytes;
    QString wavPath;
};
struct SampleCommitted {
    QString name;
    bool committed = false;
    bool sidecarSaved = false;
    QString sidecarError;
};
struct SongCreated {
    SongName song;
    bool voicegroupOk = true;
    bool midiOk = false;
    bool flagsOk = false;
    bool registered = false;
    int songId = -1;
};

// Receipt derived from the typed worker outcome only when the pending history
// transition needs the fresh blank-slot token; not a second worker result.
struct VoicegroupEditApplied {
    VoicegroupId voicegroup;
    std::optional<VoicegroupSource::BlankSlotMaterialization> materialization;
};
struct VoicegroupEditConflict {
    VoicegroupId voicegroup;
};

// Exhaustive fan-out stream. LoadedBankView (from voicegroupsource.h) is the
// canonical bank replacement event, keyed by its id.
using ProjectEvent = std::variant<LoadedBankView, RegistrationPlanResult, DeletionPlanResult,
                                  PreviewPlan, PreviewReady, SampleSetReady, SamplesProbed,
                                  SampleRead, SampleCommitted, SongCreated, VoicegroupEditApplied,
                                  VoicegroupEditConflict, ProjectMutationFailure>;

// ---- Song publications -------------------------------------------------------

struct MidiStage {
    SongName song;
    SongInfo info;
    SmfFile smf;
    int trackBudget = 16;
};
struct SidecarStage {
    SongName song;
    bool loaded = false; // missing or corrupt sidecar: success, entry rewritten
    ViewSidecar::Snapshot snapshot;
};
struct VoicegroupBound {
    SongName song;
    VoicegroupId id;
};
struct SongSaved {
    SongName song;
    SongSaveSnapshot savedSnapshot;
    bool flagsWritten = false;
    bool sidecarSaved = false;
    std::optional<QString> sidecarError; // nonfatal cosmetic write result
};

enum class SongStage { Midi, Voicegroup, Sidecar, Reconcile, Save };
// The single song load/save failure payload: fatal stages only.
struct SongFailed {
    SongStage stage;
    QString message;
};

using SongPayload = std::variant<MidiStage, SidecarStage, VoicegroupBound, SongSaved, SongFailed>;

// song is the public routing key; ProjectWorkspace never reconstructs it.
struct SongUpdate {
    SongName song;
    SongPayload payload;
};

// ---- Semantic operations (user-domain inputs only) ---------------------------

struct OpenSongInput {
    SongName song;
};
struct ReloadSongInput {
    SongName song;
    std::optional<QString> voicegroupArg;
};
struct OpenProjectInput {
    QString root;
};
struct SaveSongInput {
    SongName song;
    SongSaveSnapshot snapshot;
    ViewSidecar::Snapshot sidecarSnapshot;
    std::optional<SaveVoicegroupInput> voicegroup;
};
// Fire-and-forget cosmetic persistence for close or switch; its private
// SidecarWriteResult never becomes a public event.
struct SaveSidecarInput {
    SongName song;
    ViewSidecar::Snapshot snapshot;
};
struct RefreshProjectInput {};
struct CleanupPreviewInput {};
struct RefreshCatalogInput {};
struct ProbeSamplesInput {};
struct CreateSongInput {
    QString label;
    QString constant;
    QString player;
    SongCfg cfg;
    QString newVoicegroup;
    SmfFile smf;
};
struct CreateVoicegroupInput {
    QString name;
    QString copyFromFile;
    QString copySectionLabel;
};
struct RegistrationPlanInput {
    QString label;
    QString constant;
    QString player;
};
struct RegisterSongInput {
    QString label;
    QString constant;
    QString player;
};
struct DeletionPlanInput {
    SongName song;
    QString constant;
};
struct DeleteSongInput {
    SongName song;
    QString constant;
    QString deleteVoicegroupName;
};
struct PreviewPlanInput {
    VoicegroupId voicegroup;
};
struct PreviewInput {
    VoicegroupId voicegroup;
    QByteArray sourceBytes;
};
struct LoadSampleSetInput {
    QStringList samples;
    QStringList waves;
    QList<QPair<QString, QString>> keysplits;
};
struct ReadSampleInput {
    QString name;
};
struct CommitSampleInput {
    QString name;
    QByteArray wavBytes;
    std::optional<SampleSidecar> sidecar;
    bool removeSidecar = false;
    bool update = false;
};

// User-domain inputs only; private worker stage tags stay behind ProjectIo.
using ProjectOperation =
    std::variant<RefreshProjectInput, OpenSongInput, ReloadSongInput, SaveSongInput,
                 SaveSidecarInput, VoicegroupEditInput, CreateSongInput, CreateVoicegroupInput,
                 RegistrationPlanInput, RegisterSongInput, DeletionPlanInput, DeleteSongInput,
                 PreviewPlanInput, PreviewInput, CleanupPreviewInput, RefreshCatalogInput,
                 LoadSampleSetInput, ProbeSamplesInput, ReadSampleInput, CommitSampleInput>;

// ---- ProjectWorkspace ---------------------------------------------------------

// GUI-facing owner of the project worker. Accepts one semantic open plus a
// single-command FIFO of operations, maps private worker outcomes onto the
// keyed publications below, and refuses a second open only while Loading.
class ProjectWorkspace final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectWorkspace)

  public:
    explicit ProjectWorkspace(QObject *parent = nullptr);
    ~ProjectWorkspace() override;

  public slots:
    void openProject(OpenProjectInput input);
    void submit(ProjectOperation operation);

  signals:
    void projectStatePublished(ProjectState state);
    void projectEventPublished(ProjectEvent event);
    void songUpdatePublished(SongUpdate update);

  private:
    // All private machinery (ProjectIo, the ProjectCommand/ProjectResult
    // mapping, and startup recipe state) lives behind this nested class in
    // projectworkspace.cpp, so GUI code including this header never sees the
    // private worker seam.
    class Private;
    Private *d = nullptr;
};
