## Implementation-ready target interfaces

This document is the sole full type and ownership contract for the
DecompProject and Project-I/O reorganization. The declarations are conceptual
target C++; spelling may follow repository conventions, but the fields, keys,
and invariants are fixed by the alignment contract. Callers do not learn
worker scheduling, `DecompProject` storage, or widget mechanics. The plan in
`projectio-dress-down-plan.md` cites these declarations; it does not restate
them.

The per-song view/editor sidecar transport once declared here is superseded by
`docs/view-sidecar-removal-plan.md`: there is no `SidecarStage`,
`SaveSidecarInput`, `SidecarWriteResult`, or `SongStage::Sidecar`, and no
sidecar field on `SongSaved`/`SaveSongInput`; a successful load publishes
`MidiStage`, then any keyed `LoadedBankView`, then terminal
`VoicegroupBound`; a semantic save ends after MIDI/flags with bare
`SongSaved`/`SongFailed`; missing or corrupt legacy view/editor JSON is not a
load stage and is never rewritten by view code; and no independent
close/switch/quit cosmetic view operation exists. The declarations below are
reconciled to that state.

### Stable identities

```cpp
class SongName {
public:
    static std::optional<SongName> create(QString value);
    const QString &value() const;
    friend bool operator==(const SongName &, const SongName &) = default;

private:
    explicit SongName(QString value);
    QString m_value;
};
size_t qHash(const SongName &name, size_t seed = 0);

class VoicegroupId {
public:
    static std::optional<VoicegroupId> create(QString sourceRelativePath,
                                              QString sectionLabel);
    const QString &sourceRelativePath() const;
    const QString &sectionLabel() const;
    friend bool operator==(const VoicegroupId &, const VoicegroupId &) = default;

private:
    VoicegroupId(QString normalizedSourceRelativePath, QString sectionLabel);
    QString m_sourceRelativePath;
    QString m_sectionLabel;
};
size_t qHash(const VoicegroupId &id, size_t seed = 0);
```

`SongName::create()` rejects an empty value, and no public constructor permits
an invalid name. `SongName` is the project-relative `SongInfo::label`;
`SongInfo::id` is snapshot-local. `VoicegroupId::create()` normalizes and
validates a non-empty project-relative source path, rejecting absolute or
escaping paths, then retains the optional `sectionLabel` (empty for a
per-file voicegroup). Loader names are aliases, not identity. Equality and
`qHash` remain value-based.

### Saved startup recipe

```cpp
struct SavedWorkspaceRecipe {
    QString projectPath;              // QSettings key: "lastProjectDir"
    QVector<SongName> orderedSongs;   // QSettings key: "lastOpenSongs"
    std::optional<SongName> selected; // QSettings key: "lastSongLabel"
};

SavedWorkspaceRecipe normalizeSavedRecipe(QString projectPath,
                                           QStringList labels,
                                           QString selectedLabel);
```

`normalizeSavedRecipe()` is one pure function used by both readers. It
discards empty labels, keeps the first duplicate, and preserves order. An
ordered list empty after discarding with a non-empty selected label restores
as `selected` alone (pre-tabs session generation, one tab). Selection falls
back to the first name when the selected label is empty, missing from the
ordered list, or discarded. No other section restates these rules.

### Voicegroup resource and bank ownership

`voicegroup_free()` only frees allocations owned by `LoadedVoiceGroup`; it has
no thread-affine state.

```cpp
// Poryaaaa compatibility seam: a small project-layer value wrapper backed by
// shared_ptr<LoadedVoiceGroup>. Its public API exposes only a const
// LoadedVoiceGroup borrow plus normal value and boolean semantics. AudioEngine
// is the sole private friend that may obtain the legacy mutable pointer
// required by unchanged poryaaaa calls; porydaw never mutates through it, and
// no code casts away constness or copies a bank.
class VoicegroupLease {
public:
    VoicegroupLease() = default;
    explicit operator bool() const;
    const LoadedVoiceGroup *get() const;

private:
    friend class AudioEngine; // sole legacy mutable borrow for poryaaaa calls
    LoadedVoiceGroup *legacyMutableBorrow() const;

    std::shared_ptr<LoadedVoiceGroup> bank;
};
using SampleSetLease = std::shared_ptr<const LoadedSampleSet>;

// One bank slot's presentation: the source line's exact kind plus the
// parsed voice when that line is editable. None alone is a blank slot the
// picker may materialize; ReadOnlyVoice and Broken publish no voice and
// render read-only from the loaded bank.
struct VoicegroupSlotView {
    VgLineKind kind = VgLineKind::None;
    std::optional<VgVoice> voice;
};

struct LoadedBankView {
    VoicegroupId id;
    VoicegroupLease bank;
    QString loadName;
    bool dirty = false;
    QVector<VoicegroupSlotView> slotViews;
};

struct SetVoicegroupSlot {
    int slot = -1;
    VgVoice value;
    std::optional<VgVoice> expected; // nullopt means the slot must still be blank
};
struct RevertBlankSlot {
    VoicegroupSource::BlankSlotMaterialization materialization;
};
using VoicegroupEditOperation =
    std::variant<SetVoicegroupSlot, RevertBlankSlot>;
struct VoicegroupEditInput {
    VoicegroupId id;
    VoicegroupEditOperation operation;
};

// Private ProjectIo outcomes; neither type is a public event. Expected
// mismatches and validation no-ops use VoicegroupEditConflictResult as the
// confirmed not-applied outcome.
struct VoicegroupEditAppliedResult {
    LoadedBankView view;
    std::optional<VoicegroupSource::BlankSlotMaterialization> materialization;
};
struct VoicegroupEditConflictResult {
    VoicegroupId voicegroup;
};
using VoicegroupEditResult =
    std::variant<VoicegroupEditAppliedResult, VoicegroupEditConflictResult>;

struct SaveVoicegroupInput {
    VoicegroupId voicegroup;
    QList<QPair<QString, VgSynthDesc>> synthDefinitions;
};
```

On the Project I/O worker, `DecompProject` owns `LoadedBankEntry` (source,
current lease, and file time). That is the only canonical bank. The entry is
never published:

```cpp
struct LoadedBankEntry {
    VoicegroupId id;
    QString loadName;
    std::unique_ptr<VoicegroupSource> source;
    VoicegroupLease current;
    QDateTime sourceFileTime;
};
```
`LoadedBankView` is the immutable publication copy
`{ id, bank, loadName, dirty, slotViews }`. Every slot publishes its exact
`VgLineKind` and a parsed voice only when the line is editable, because a
blank slot, a read-only cry line, and an unparseable line are three
different presentation states that an optional-voice-only vector collapses
into one indistinguishable "no voice" value. Kind `None` alone materializes
a blank voice; `Editable` edits; `ReadOnlyVoice` and `Broken` render
read-only from the immutable loaded bank and never yield a draft.
`VoicegroupViewCache` is the private `WorkspaceUi` owner for published
views and shared-bank transition state. Tabs hold the id and a
`VoicegroupLease` copy of the same bank pointer. The picker reads through
its stable owned presentation copy of the view; it does not mutate the
worker entry.

The worker wraps each successful owning `LoadedVoiceGroup *` exactly once.
The lease may release on the Project I/O or GUI thread, never on the audio
callback. `AudioEngine` is the sole private friend of `VoicegroupLease`
allowed to obtain the legacy mutable `LoadedVoiceGroup *` borrow that
unchanged poryaaaa requires; it never mutates the bank and does not own the
lease. `AudioEngine::loadSong`, `AudioEngine::updateVoicegroup`, and every
other borrowed-bank entry point take the lease; no public API exposes a
mutable raw pointer, no path casts away constness, and no bank is copied.
`MainWindow` retains the selected lease. Shutdown stops audio before
releasing that lease, destroys tabs and GUI leases, then stops `ProjectIo`,
discards or finishes the active result, destroys worker state, and joins.

`dirty` is the current `VoicegroupSource::dirty()` bit. Save calls
`didSave(savedBytes)` only for the bytes written; a newer edit remains dirty.
This uses existing source state, not a new token.

### Tab history and dirty state

```cpp
class DocumentStateIdentity {
public:
    DocumentStateIdentity() = default;
    DocumentStateIdentity(const DocumentStateIdentity &) = default;
    DocumentStateIdentity &operator=(const DocumentStateIdentity &) = default;
    friend bool operator==(const DocumentStateIdentity &,
                           const DocumentStateIdentity &) = default;

private:
    friend class SongHistory;
    friend class SongDocument;
    // Opaque strong value: callers may copy or compare, never inspect or order it.
    explicit DocumentStateIdentity(uint64_t value) : m_value(value) {}
    uint64_t m_value = 0;
};

// A detached MIDI/config image, document identity, and save-guard metadata.
struct SongSaveSnapshot {
    SmfFile smf;
    QString midPath;
    QString label;
    SongCfg cfg;
    bool flagsNeeded = false;
    uint64_t revision = 0;
    uint64_t saveStateToken = 0;
    DocumentStateIdentity documentState;
};

enum class HistoryKind { Document, SharedBank };

struct DocumentHistoryApplied {};
using HistoryRequest =
    std::variant<DocumentHistoryApplied, VoicegroupEditInput>;

class SongHistory {
public:
    bool canUndo() const;
    bool canRedo() const;
    DocumentStateIdentity currentDocumentIdentity() const;
    DocumentStateIdentity savedDocumentIdentity() const;
    void markDocumentSaved(DocumentStateIdentity identity);
    HistoryRequest requestUndo();
    HistoryRequest requestRedo();
    void pushConfirmedBank(
        VoicegroupEditInput draft,
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization);
    void crossConfirmedBankUndo(
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization);
    void crossConfirmedBankRedo(
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization);
    void resolveBankUndoConflict();
    void resolveBankRedoConflict();
};
```

`SongHistory` is the only tab history interface and wraps exactly that tab's
existing `QUndoStack`. Each entry is tagged `Document` or `SharedBank` and
carries document-state identities before and after the entry. A document entry
mints a new after identity; a bank entry preserves the current document
identity. `currentDocumentIdentity()`, `savedDocumentIdentity()`, and
`markDocumentSaved()` are the history operations used for dirty and save
adoption. The precondition for `requestUndo()` is `canUndo()`, and the
precondition for `requestRedo()` is `canRedo()`. Each request either crosses a
document entry synchronously and returns `DocumentHistoryApplied`, or prepares
the targeted shared-bank entry's exact `VoicegroupEditInput` for worker
submission and returns it without invoking its callback or moving the
`QUndoStack` index. `pushConfirmedBank()` builds an initial confirmed entry
whose first redo is inert, while `crossConfirmedBankUndo()` and
`crossConfirmedBankRedo()` cross an applied transition through the armed inert
callback. `resolveBankUndoConflict()` and `resolveBankRedoConflict()` handle
confirmed stale undo and redo transitions respectively; an initial conflict
does not call either method. These operations keep entry-transition mechanics
in this one history interface; pending asynchronous ownership remains solely in
`VoicegroupViewCache`.

`SongDocument` dirty compares its current identity with the saved identity.
`SongSaveSnapshot::documentState` stores the captured identity by value.
`SongDocument::didSave()` retains the existing `flagsNeeded`, `revision`, and
`saveStateToken` guards, and calls `markDocumentSaved(snapshot.documentState)`
only after those guards and the captured identity still match. Bank-only
transitions change neither the document identity nor `revision` or
`saveStateToken`, so they do not dirty the song or invalidate an in-flight
song snapshot. `SongHistory` treats shared-bank entries as non-document
transitions when it crosses the inert callback; that crossing emits no
document mutation and does not advance `revision` or `saveStateToken`.
Document dirty truth is never a whole-document hash or a monotonic revision
equality.
Document history merges preserve the oldest before identity and newest after
identity, cannot cross the saved document identity, and retain normal branch
and undo-to-saved behavior.

`VoicegroupViewCache` owns the one optional `PendingBankTransition` with the
GUI bank views. The transition stores its `VoicegroupId`, origin `SongName`,
`Kind::Initial`, `Kind::Undo`, or `Kind::Redo`, and the submitted
`VoicegroupEditInput` draft. It is the only normal user-reachable pending
transition: there is no per-identity pending map, request or incarnation ID,
tab pointer registry, worker state, or second history stack. For an initial
edit, `WorkspaceUi` supplies the draft directly; for an undo or redo, it uses
the bank alternative returned by `HistoryRequest` with the origin `SongName`
and matching `Kind` to construct this transition, calls
`VoicegroupViewCache::begin()` before submission, and retains no parallel
origin, kind, draft, or blank-token fields.

`WorkspaceUi` uses the cache's pending origin only to find the unique live
origin tab by `SongName`, then passes that tab's `SongHistory` to the resolver.
The global `bankActionsEnabled()` gate is false while any transition is pending
and gates picker edits, history mutation, undo, and redo. `closeEnabledFor()`
is the origin-aware close gate: it is false only for the pending origin, so
other tabs remain closable.

Initial bank edits submit without pushing. When a typed applied outcome arrives,
the cache installs the `LoadedBankView` before resolving the origin history and
selects from its owned `Kind`: `pushConfirmedBank(m_pending->draft, ...)` for
`Initial`, `crossConfirmedBankUndo(...)` for `Undo`, or
`crossConfirmedBankRedo(...)` for `Redo`. The returned bank draft is therefore
the same input that was submitted to the worker. `SongHistory` receives the
fresh blank materialization through the selected operation before the cache
clears the pending transition.

`resolveConflict()` also switches on the owned `Kind`. `Initial` clears the
pending transition and leaves history unchanged without a history call; `Undo`
invokes `resolveBankUndoConflict()` and `Redo` invokes
`resolveBankRedoConflict()`. A confirmed conflict leaves the current view
unchanged. Only a typed applied or confirmed-conflict outcome may obsolete or
cross a stale bank entry. Raw `QUndoStack` actions cannot bypass this gate, and
other tabs sharing the identity never gain history. A hard worker error maps to
`VoicegroupMutationFailed`, clears the pending transition without crossing it,
and leaves the history index fixed. `applyView()` precedes applied resolution,
and `resolveConflict()` leaves the current view unchanged.

`VoicegroupEditApplied` carries the `VoicegroupId` and an optional fresh
blank-slot materialization. Scalar applications carry no token. A blank
initial set/materialize operation and every blank redo return a fresh
`VoicegroupSource::BlankSlotMaterialization` in the applied outcome and
receipt; blank undo sends that token in `RevertBlankSlot` to
`revertBlankSlotMaterialization`. The history command stores the returned
token, replaces it with each fresh blank-redo token, and clears it after a
confirmed blank undo. It never uses `setVoice`. The worker is the only
validator. Structural blank edits do not merge, while confirmed scalar bank
entries may merge only with the existing scalar merge rules.

```cpp
class DecompProject {
public:
    ProjectSnapshot openProject(QString root, QString *error);
    std::optional<SongInfo> playableSong(SongName name) const;
    std::optional<LoadedBankView> loadBank(const SongInfo &song, QString *error);
    std::optional<VoicegroupEditResult> applyVoicegroupEdit(VoicegroupEditInput input, QString *error);
    std::optional<LoadedBankView> saveVoicegroup(SaveVoicegroupInput input, QString *error);
};
```

`loadBank()` reuses an unchanged entry when identity and source timestamp
permit. Like every hard worker error on the bank methods, a `loadBank()` or
`saveVoicegroup()` failure returns `std::nullopt`, writes its message through
`error`, and leaves the previous record (source, lease, and file time)
untouched; no invalid empty-identity view is ever manufactured.
`applyVoicegroupEdit()` returns a
`std::optional<VoicegroupEditResult>`. A present value is either an applied
result, whose complete candidate replaces `current`, or a confirmed conflict,
the typed not-applied outcome for an expected mismatch or every validation
no-op, which leaves `current` untouched. A hard error returns `std::nullopt`,
writes its message through `error`, and leaves the old entry untouched;
`ProjectIo` maps that absence to private `CommandFailure`, and
`ProjectWorkspace` maps it to keyed `VoicegroupMutationFailed`. A
`SetVoicegroupSlot` with blank expected state uses `materializeBlankSlot`, and
a `RevertBlankSlot` uses its supplied token with
`revertBlankSlotMaterialization`. The worker derives structural versus scalar
behavior from the source; the GUI does not send a mode flag.

### Project publications

```cpp
enum class ProjectOpenState { Closed, Loading, Ready, Failed };

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

struct ProjectState {
    ProjectOpenState state = ProjectOpenState::Closed;
    ProjectSnapshot snapshot;
    VoicegroupCatalog catalog;
    std::optional<QString> error;
};
```

`ProjectState` has exactly `{ state, snapshot, catalog, error }`. During
`Loading`, the prior snapshot may remain. A failed open sets `state` and a
present `error` without replacing that snapshot; every other state has an
absent error. There is no operation field or busy flag. Startup song work
begins after successful open has published `Ready`.

`ProjectWorkspace::openProject()` refuses only while `ProjectOpenState` is
`Loading`; a call at any other time queues a new open. The Open Project
action's longer disablement while any placeholder lacks a terminal song
payload or any `WorkspaceUi`-submitted work remains in flight is
`WorkspaceUi` policy; it is not part of `ProjectState` or of the
`openProject()` refusal rule.

Every fan-out `ProjectEvent` alternative has its domain key except catalog
dialog publications. The exhaustive mutation-failure sum is fixed to exactly
the four alternatives declared below; adding another mutation-failure kind
must produce exhaustive-visitor compile errors at every required handling
point:

```cpp
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
using ProjectMutationFailure = std::variant<
    SongMutationFailed, VoicegroupMutationFailed, SampleMutationFailed,
    CatalogMutationFailed>;
```

The remaining keyed event contract is:

```cpp
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
struct SampleSetReady { SampleSetLease sampleSet; }; // one catalog dialog
struct SamplesProbed { SampleFormatProbe probe; };   // one catalog dialog
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
struct VoicegroupEditApplied {
    VoicegroupId voicegroup;
    std::optional<VoicegroupSource::BlankSlotMaterialization> materialization;
};
struct VoicegroupEditConflict {
    VoicegroupId voicegroup;
};

using ProjectEvent = std::variant<
    LoadedBankView, RegistrationPlanResult, DeletionPlanResult,
    PreviewPlan, PreviewReady, SampleSetReady, SamplesProbed, SampleRead,
    SampleCommitted, SongCreated, VoicegroupEditApplied,
    VoicegroupEditConflict, ProjectMutationFailure>;
```

### WorkspaceUi shared-bank view coordinator

`VoicegroupViewCache` is a private deep module owned by `WorkspaceUi`. It is
not part of `ProjectWorkspace`, a project-wide tab registry, or a second
history stack. Its view map is keyed by `VoicegroupId`; its pending state is
one optional transition, never a per-identity pending map.

```cpp
struct PendingBankTransition {
    enum class Kind { Initial, Undo, Redo };
    VoicegroupId voicegroup;
    SongName origin;
    Kind kind = Kind::Initial;
    VoicegroupEditInput draft; // copied submitted input; draft.id == voicegroup
};

class VoicegroupViewCache {
public:
    const LoadedBankView *find(VoicegroupId voicegroup) const;
    bool begin(PendingBankTransition transition);
    std::optional<SongName> pendingOrigin() const;
    void applyView(LoadedBankView view);
    void resolveApplied(VoicegroupEditApplied outcome, SongHistory &originHistory);
    void resolveConflict(VoicegroupEditConflict outcome, SongHistory &originHistory);
    void resolveHardError(VoicegroupMutationFailed failure);
    void clear();
    bool bankActionsEnabled() const;
    bool closeEnabledFor(SongName origin) const;

private:
    QHash<VoicegroupId, LoadedBankView> m_views;
    std::optional<PendingBankTransition> m_pending;
};
```

`begin()` starts the one FIFO transition and refuses another while one is
active; a history request must not be submitted unless `begin()` succeeds.
`pendingOrigin()` exposes only the stored origin key so `WorkspaceUi` can find
the unique live tab and pass its `SongHistory`; it does not expose a tab pointer
or parallel pending fields. `applyView()` must precede `resolveApplied()`; the
history-taking resolver selects the canonical initial/undo/redo confirmation
operation from the owned `Kind` and ends the pending transition.
`resolveConflict()` selects the direction-specific stale-transition method
from `Kind`, while an initial conflict calls no history method.
`resolveHardError()` ends it without crossing history. `clear()` resets both
owned stores on accepted project replacement. `bankActionsEnabled()` is the
single global picker/history/undo/redo gate, while `closeEnabledFor()` is the
origin-aware close gate. The helper does not own the transient
`QSet<SongName>` tombstones.

`ProjectMutationFailure` is exhaustive: song failures key by `SongName`,
voicegroup failures by `VoicegroupId`, sample failures by `name`, and only
catalog-dialog failures are unkeyed. `SampleSetReady` and `SamplesProbed`
remain intentionally unkeyed because there is one catalog dialog.
`LoadedBankView` is keyed by its `id`, previews by `voicegroup`, sample events
by `name`, and song events by `song`. A bank load publishes the view before the
song's `VoicegroupBound` update. An applied edit maps its private
`VoicegroupEditAppliedResult` to a keyed `LoadedBankView` event and, when the
pending history transition needs the token, a keyed `VoicegroupEditApplied`
receipt. A confirmed worker conflict maps to keyed
`VoicegroupEditConflict`; a hard worker error maps to the keyed
`VoicegroupMutationFailed` alternative. The view remains the canonical bank
replacement event.

Semantic-save publication is specified once by `SaveSongInput` below.
`VoicegroupEditApplied` is a public receipt derived from its typed worker
outcome only when the pending history transition needs it; it is not a
second worker result.
`SongMutationFailed` is only the keyed failure alternative for project
mutations; song load and save failures use the single `SongFailed` payload.

### Song publications

```cpp
struct MidiStage {
    SongName song;
    SongInfo info;
    SmfFile smf;
    int trackBudget = 16;
};
struct VoicegroupBound {
    SongName song;
    VoicegroupId id;
};
struct SongSaved {
    SongName song;
    SongSaveSnapshot savedSnapshot;
    bool flagsWritten = false;
};

enum class SongStage { Midi, Voicegroup, Reconcile, Save };
struct SongFailed {
    SongStage stage;
    QString message;
};

using SongPayload = std::variant<MidiStage, VoicegroupBound,
                                 SongSaved, SongFailed>;

struct SongUpdate {
    SongName song;
    SongPayload payload;
};
```

Each worker stage wrapped as a `SongUpdate` carries its `SongName`;
`ProjectWorkspace` publishes that key directly and never reconstructs it from
a secondary collection. `SongUpdate::song` remains the public routing key.

`SongPayload` contains successful load stages and one `SongFailed` type. A
fatal load or save error publishes that type with its stage. Per
`docs/view-sidecar-removal-plan.md`, legacy per-song view/editor JSON is not a
load stage: missing or corrupt legacy view/editor data is ignored by the view
path and never rewritten by it, and no sidecar stage or rewrite exists.
Project-open failure remains only in the optional `ProjectState.error`.

For a successful song load, `ProjectWorkspace` publishes `MidiStage`, any
keyed `LoadedBankView`, then terminal `VoicegroupBound`; a failure publishes one
terminal `SongFailed` instead. Semantic-save behavior is specified by
`SaveSongInput`, `SongSaved`, and `SongFailed` below. Missing or unplayable
saved names use `SongFailed{ SongStage::Reconcile, ... }`; `WorkspaceUi` closes
that placeholder tab and preserves nothing.

### ProjectWorkspace semantic operations

```cpp
struct OpenSongInput { SongName song; };
struct ReloadSongInput {
    SongName song;
    std::optional<QString> voicegroupArg;
};
struct OpenProjectInput { QString root; };
struct SaveSongInput {
    SongName song;
    SongSaveSnapshot snapshot;
    std::optional<SaveVoicegroupInput> voicegroup;
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
struct RegistrationPlanInput { QString label; QString constant; QString player; };
struct RegisterSongInput { QString label; QString constant; QString player; };
struct DeletionPlanInput { SongName song; QString constant; };
struct DeleteSongInput {
    SongName song;
    QString constant;
    QString deleteVoicegroupName;
};
struct PreviewPlanInput { VoicegroupId voicegroup; };
struct PreviewInput { VoicegroupId voicegroup; QByteArray sourceBytes; };
struct LoadSampleSetInput {
    QStringList samples;
    QStringList waves;
    QList<QPair<QString, QString>> keysplits;
};
struct ReadSampleInput { QString name; };
struct CommitSampleInput {
    QString name;
    QByteArray wavBytes;
    std::optional<SampleSidecar> sidecar;
    bool removeSidecar = false;
    bool update = false;
};

using ProjectOperation = std::variant<
    RefreshProjectInput, OpenSongInput, ReloadSongInput, SaveSongInput,
    VoicegroupEditInput, CreateSongInput,
    CreateVoicegroupInput, RegistrationPlanInput, RegisterSongInput,
    DeletionPlanInput, DeleteSongInput, PreviewPlanInput, PreviewInput,
    CleanupPreviewInput, RefreshCatalogInput, LoadSampleSetInput,
    ProbeSamplesInput, ReadSampleInput, CommitSampleInput>;

class ProjectWorkspace {
public slots:
    void openProject(OpenProjectInput input);
    void submit(ProjectOperation operation);

signals:
    void projectStatePublished(ProjectState state);
    void projectEventPublished(ProjectEvent event);
    void songUpdatePublished(SongUpdate update);
};
```

`ProjectOperation` contains user-domain inputs only; private worker stage tags
are not exported through this seam. `WorkspaceUi` is the caller. It enforces
one live tab per `SongName`, captures copied snapshots, and submits one
semantic song-save operation. Worker filesystem ordering remains behind the
semantic seam. Placement (focus, replace, or new tab) stays in `WorkspaceUi`;
it is not a project input. `MainWindow` owns only the three direct publication
connections.

When `ReloadSongInput::voicegroupArg` is present, the reload is a live
voicegroup rebind: the worker resolves that user-domain argument against its
project and publishes only the keyed bank view and terminal binding. An absent
override reloads the complete song from the worker-owned catalog.

`WorkspaceUi` owns a transient `QSet<SongName>` for closed loading tabs.
It contains a name only while that name's semantic load remains in flight;
terminal `VoicegroupBound` or `SongFailed` erases it, and accepted project
replacement clears it. It is not project state or a tab registry.

Per `docs/view-sidecar-removal-plan.md`, no independent close, switch, or quit
cosmetic view operation exists, and `ProjectOperation` contains no
`SaveSidecarInput`: those boundaries perform zero view/editor project I/O.

`SaveSongInput` is one copied recipe: the `SongName`, detached
`SongSaveSnapshot`, and optional `SaveVoicegroupInput`
cross the seam. `SaveVoicegroupInput` contains only the `VoicegroupId` and
minted synth definitions; the worker derives source bytes and source path from
the canonical `LoadedBankEntry` and its `VoicegroupSource`.

The worker performs optional voicegroup source and synth writes plus the
required bank refresh first when a voicegroup recipe is present, then writes
MIDI and flags; the save ends there. As soon as
the optional voicegroup save and bank refresh land, `ProjectIo` delivers the
resulting `LoadedBankView` while the semantic command remains active, and
`ProjectWorkspace` publishes it as a normal keyed `ProjectEvent` before later
MIDI or flags work. A fatal voicegroup, refresh, MIDI, or flags failure stops
later stages while earlier writes remain; there is no transaction, rollback,
retry, or external-file race guard.

The semantic save publishes exactly one terminal public song outcome:
`SongSaved` on completion or `SongFailed` for a fatal voicegroup, refresh,
MIDI, or flags failure. The bare `SongSaved` carries the copied snapshot and
`flagsWritten`, but no bank
field. If a later fatal stage publishes `SongFailed`, `WorkspaceUi` has
already applied the independent bank event and does not leave its cache or
lease stale. This event publication is not filesystem-stage correlation in
`WorkspaceUi`.

### Private ProjectIo command/result interface

```cpp
// These are the real private stage tags for the ordered song-load flow.
struct LoadSongCommand { SongName song; };
struct LoadVoicegroupCommand {
    SongName song;
    VoicegroupId voicegroup;
};
struct PreviewCleanupCompleted {}; // private CleanupPreviewInput success

using ProjectCommand = std::variant<
    OpenProjectInput, RefreshProjectInput, OpenSongInput, ReloadSongInput,
    LoadSongCommand, LoadVoicegroupCommand,
    SaveSongInput, VoicegroupEditInput,
    CreateSongInput, CreateVoicegroupInput, RegistrationPlanInput,
    RegisterSongInput, DeletionPlanInput, DeleteSongInput, PreviewPlanInput,
    PreviewInput, CleanupPreviewInput, RefreshCatalogInput,
    LoadSampleSetInput, ProbeSamplesInput, ReadSampleInput, CommitSampleInput>;

struct SongCommandFailure {
    SongName song;
    SongStage stage;
    QString message;
};
struct CommandFailure {
    QString message;
}; // private and unkeyed

using ProjectResult = std::variant<
    ProjectSnapshot, MidiStage, LoadedBankView, VoicegroupBound,
    VoicegroupEditResult,
    PreviewCleanupCompleted, SongSaved,
    RegistrationPlanResult, DeletionPlanResult, PreviewPlan, PreviewReady,
    SampleSetReady, SamplesProbed, SampleRead, SampleCommitted, SongCreated,
    VoicegroupCatalog, SongCommandFailure, CommandFailure>;
```

The private variant holds public input types directly whenever no worker
enrichment is added. The only private command alternatives beyond those inputs
are the listed load stage tags; they do not cross the
`ProjectWorkspace` seam and carry no cached catalog rows.

`ProjectResult` is total over `ProjectCommand`: every command alternative has a
terminal private result in this variant, and every hard worker error is typed
by the command it fails. A load, reload, private load-stage, semantic-save, or
closed-project song failure becomes a `SongCommandFailure` carrying the
original `SongName` and the exact fatal stage recorded at the worker failure
site; every other command's failure becomes a message-only `CommandFailure`.
Load commands may emit staged values before terminal `VoicegroupBound`. A
semantic `SaveSongInput` follows the semantic-save contract under
**Implementation-ready target interfaces** and has one private terminal
`SongSaved` or `SongCommandFailure`, with the public mapping handled by
`ProjectWorkspace`.

The visitor dispatches `VoicegroupEditInput` directly to
`DecompProject::applyVoicegroupEdit`, whose `std::optional<VoicegroupEditResult>`
is present for an applied or confirmed-not-applied outcome. A hard edit error
is the helper's `std::nullopt` plus error, which `ProjectIo` turns into
`CommandFailure`; `ProjectWorkspace` maps it to `VoicegroupMutationFailed`.
The applied value maps to the bank view and, when needed, keyed
`VoicegroupEditApplied`; the confirmed conflict maps to keyed
`VoicegroupEditConflict`. Successful
`CleanupPreviewInput` delivers `PreviewCleanupCompleted`; `ProjectWorkspace`
consumes it without a public event and advances the FIFO, while its hard error
is `CommandFailure`.

Startup names are resolved against the accepted snapshot and enqueued after
successful open. `ProjectWorkspace` publishes a `SongCommandFailure` directly
as the keyed
`SongFailed` song update for its carried song and stage without inspecting the
paired command, and maps a `CommandFailure` — always paired with a non-song
command — onto the appropriate keyed `ProjectMutationFailure` alternative, or
onto `ProjectState.error` for project open. Neither private failure crosses as
a public unkeyed event.

A keyless operation carries no `SongName`, `VoicegroupId`, sample `name`, or
catalog-dialog destination: `OpenProjectInput`, `RefreshProjectInput`, and
`CleanupPreviewInput`. For these, `CommandFailure`
consumption is fixed per operation rather than by a key. `OpenProjectInput`
failure maps to the present `ProjectState.error` of a `Failed` open.
`RefreshProjectInput` and `CleanupPreviewInput` failures are consumed without
a public event and advance the FIFO.

`ProjectIo` has one private `submit(ProjectCommand)` seam, one active FIFO
command, and one private result callback. Semantic-save delivery follows the
contract under **Implementation-ready target interfaces**; no
filesystem-stage callback is exposed for `WorkspaceUi` to correlate. There is
no per-command cancellation or old-result filter. A closed loading tab is
handled by the `WorkspaceUi` tombstone policy rather than by a worker identity.
Shutdown stops accepting commands, finishes or discards the active result,
releases undelivered owning resources, and joins the worker.

### Audio binding values

```cpp
struct NoteAuditionIntent {
    uint8_t track = 0;
    uint8_t key = 0;
    uint8_t velocity = 0;
    std::optional<uint32_t> durationSamples;
};
struct VoiceAuditionIntent {
    uint8_t voice = 0;
    uint8_t key = 0;
    uint8_t velocity = 0;
};
struct SampleBytesAudition {
    QByteArray s8;
    uint32_t frequency = 0;
    uint32_t loopStart = 0;
    bool looped = false;
    uint8_t key = 60;
    AuditionSlots::Adsr adsr;
    uint8_t toneKey = 60;
};
struct WaveAudition {
    QByteArray wave16;
    uint8_t key = 60;
    AuditionSlots::Adsr adsr;
};
struct AuditionStop {};
using SampleAuditionIntent = std::variant<SampleBytesAudition, WaveAudition,
                                          AuditionStop>;
struct AudioPresentationState {
    std::optional<SongName> selectedSong;
    Transport transport = Transport::Stopped;
    uint64_t playheadSamples = 0;
    TrackActivityLevels activity;
    int activePcmChannels = 0;
    int activeCgbChannels = 0;
};
```

`MainWindow` reads the selected `SongTab` directly when applying audio; no
selected-audio aggregate crosses the seam. It owns all `AudioEngine` calls. A
null or not-ready selection unloads before releasing the old lease.
`AudioEngine` load/rebind entry points take the selected lease and offline
export captures and retains a `VoicegroupLease` for the render, as declared
under **Voicegroup resource and bank ownership**; the engine never owns the
lease and never mutates the bank. Audition
payloads are copied values or safe leases. Transport and global settings use
direct focused helpers rather than thin value-intent types. Whether the
declared values travel as one signal or a few focused signals is an
implementation freedom; ownership and ordering are fixed.

