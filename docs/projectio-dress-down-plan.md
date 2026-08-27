# DecompProject and Project-I/O Organization Plan

## Status

This document describes a target design. It is not a description of the current
implementation.

The complete type and ownership contract is declared once under **Implementation-ready
target interfaces**; the other sections cite that contract instead of
declaring competing types or policies.

Today, `DecompProject` provides read-only project discovery and catalog data,
while voicegroups load through separate paths. The target extends
`DecompProject` on the Project I/O worker with canonical `LoadedBankEntry`
records, one playable bank per `VoicegroupId`, and the related project-wide
catalog state.

The core runtime ownership boundaries, startup-restoration persistence, and
project-result routing are settled. `ProjectWorkspace` publishes the three
publication streams, with keyed events and song updates; `WorkspaceUi` matches
and applies them to passive `SongTab` objects.

## Goal

Turn Project I/O into a set of cohesive owners with one implementation-ready
contract:

- `MainWindow` remains the application composition root and owns
  `WorkspaceUi`, `AudioEngine`, and `ProjectWorkspace`.
- `MainWindow` makes the UI shell available immediately, wires high-level
  signals, and does not become the project-state module.
- `ProjectWorkspace` owns project-wide state and a private `ProjectIo`.
- `ProjectIo` hides the worker thread, queue, transport, and private command and
  result variants.
- Worker-side `DecompProject` contains the canonical `LoadedBankEntry` for each
  `VoicegroupId` and performs project file I/O.
- `WorkspaceUi` owns the widgets, reusable voice picker, and all `SongTab`
  instances. It holds the published `VoicegroupId → LoadedBankView` cache.
- Each `SongTab` owns its `SongDocument`, `MidiTimeline`, permanently paired
  `SongView`, and local document edit, dirty, readiness, and presentation state.
  It receives staged values and safe handles but never requests project I/O.
- `MainWindow` retains `AudioEngine` and applies audio state from the `SongTab`
  reported as selected by `WorkspaceUi`.

The worker record, immutable GUI view, keyed events, song failure payload,
undo boundary, saved-recipe helper, and audio values are declared only in
**Implementation-ready target interfaces**. This is an organization change and
must preserve existing behavior except where that contract requires an
explicit handoff.

## Target ownership
The alignment contract fixes these boundaries; this tree is only a summary,
while the complete declarations remain under **Implementation-ready target
interfaces**.

```text
MainWindow                              [application composition root]
├── WorkspaceUi                         [constructed first or available first]
│   ├── QSettings session view          [shared persisted source]
│   │   ├── reads ordered song labels and selected label
│   │   └── writes ordered song labels and selected label
│   ├── reusable voice picker
│   ├── VoicegroupId → LoadedBankView   [published immutable view cache]
│   └── SongTabs, including startup placeholders
│       └── SongTab
│           ├── SongDocument
│           ├── MidiTimeline
│           ├── permanently paired SongView
│           ├── VoicegroupId + VoicegroupLease
│           └── local document edit, dirty, readiness, and presentation state
├── AudioEngine
└── ProjectWorkspace                   [non-blocking construction and open]
    ├── QSettings startup view          [same persisted source]
    │   ├── reads project path and saved recipe
    │   └── writes project path only after successful open
    ├── copied/published project state
    │   ├── project identity and root
    │   ├── songs, players, and track budgets
    │   └── project-open state and error
    └── ProjectIo                       [private]
        └── worker thread
            ├── DecompProject           [worker-only]
            │   ├── project discovery and catalog data
            │   └── VoicegroupId → LoadedBankEntry [canonical record]
            └── project operation helpers [worker-only]
```

`MainWindow` constructs `WorkspaceUi` first, or otherwise makes the UI shell
available before project work completes. It then constructs the non-blocking
`ProjectWorkspace` and wires high-level publication. It reacts to
`WorkspaceUi` selection reports by applying audio state; it does not choose or
change the selected tab.

Composition ownership does not make `MainWindow` the project-state module. It
does not perform project file I/O, access `DecompProject`, inspect worker state,
or relay routine project data by hand.

`WorkspaceUi` owns tab selection and lifetime and reports its selected
`SongTab`. `MainWindow` reacts by applying that tab's timeline, settings, and
lease to `AudioEngine`. `WorkspaceUi` does not control the engine directly.
The GUI view cache is a published immutable copy; the worker record remains the
canonical source.

Neither `ProjectWorkspace` nor `DecompProject` owns `AudioEngine`.

## Design constraints
The alignment contract fixes these ownership and concurrency constraints;
constraints 15, 17, and 20 are summarized here and declared in full under
**Implementation-ready target interfaces**.

1. `MainWindow` is the composition root, not the project-state module.
2. `ProjectWorkspace` construction and project opening are non-blocking.
3. `ProjectIo` remains private to `ProjectWorkspace`.
4. GUI code does not include, construct, or call `ProjectIo`.
5. `ProjectIo` hides `QThread`, worker scheduling, request envelopes, and
   result transport.
6. `DecompProject` and all mutable project catalog state stay on the Project
   I/O worker thread.
7. No GUI caller receives a mutable `DecompProject` or a raw owning C pointer.
8. Project results published to the GUI contain copied presentation values or
   safe handles and leases with clear lifetime rules.
9. `ProjectWorkspace` contains no live-tab registry, `SongTab` or widget
   pointers, active GUI-tab state, tab liveness, or tab-close cancellation
   policy. It may read copied saved labels for automatic startup work.
10. `WorkspaceUi` owns `SongTab` selection and lifetime.
11. A `SongTab` and its `SongView` remain paired for the life of the tab.
12. `SongView` reads live document and timeline data directly from its parent
    `SongTab`.
13. Tabs using one `VoicegroupId` share one current playable bank; different
    identities remain isolated.
14. Replacing a loaded bank must not invalidate a bank still read by
    `AudioEngine` or a tab. `VoicegroupLease` supplies that lifetime.
15. Only one project open may be active. `ProjectWorkspace::openProject()`
    refuses only while `ProjectOpenState::Loading`, and `Loading` ends when
    open succeeds or fails. `WorkspaceUi` keeps Open Project disabled while a
    placeholder lacks a terminal song payload or any work it submitted is in
    flight. This disablement is `WorkspaceUi` policy, not `ProjectState`.
16. No new owner class is added merely to move existing project catalog work.
17. `QSettings` is the single persisted source for startup restoration.
    `WorkspaceUi` and `ProjectWorkspace` independently read the normalized
    saved recipe for the matching startup `projectPath` at application startup
    only, with split write ownership and no second store.
18. `WorkspaceUi` writes ordered open-song labels and selected label.
    `ProjectWorkspace` writes the last project path only after successful
    project open. Neither writes the other owner's keys, and `DecompProject`
    owns no UI history.
19. `SongTab` is passive with respect to project operations. It never calls
    `ProjectWorkspace` or `ProjectIo`, starts a load/save/reload, or owns a
    project-operation identity.
20. `ProjectWorkspace` publishes song results by stable `SongName`.
    `WorkspaceUi` matches them to live tabs and calls narrow receive/apply
    methods; an absent match is ignored. Identity-scoped bank replacement is a
    keyed `LoadedBankView` project event, not a per-tab song result.
21. Before adding a race guard, disable the conflicting user action while the
    current operation runs when that matches normal product behavior. Retain
    backend overlap handling only for user actions that must remain available
    together or unavoidable lifecycle work such as shutdown. Do not add
    counters, cancellation paths, identities, or tests for GUI-impossible
    sequences.

## Current problems to remove

### Project I/O is one broad implementation surface

Thread startup, request scheduling, project discovery, MIDI work, voicegroup
work, sidecars, samples, previews, file mutation, and result transport are too
close together. This makes ownership and dependencies hard to review.

### Project policy and worker mechanics are mixed

Project selection, the single active load state, and published project state
belong to `ProjectWorkspace`. Queue mechanics and worker dispatch belong to
private Project I/O machinery. Filesystem work belongs to worker-side project
operations and `DecompProject`.

### Tab policy has leaked into project-wide state

Live-tab registries, active GUI-tab state, tab liveness, tab-close policy, and
voicegroup assignment by tab-specific identity do not belong to a project-wide
workspace.
`WorkspaceUi` owns those live collection concerns, while `SongTab` owns only
local edit and readiness state. Command completion stays inside the one-active
private `ProjectIo`; tabs never own it. Copied stable labels used for project
work are semantic keys, not a registry of live tabs.

### Project catalog state is split

The current `DecompProject` describes the project, but loaded voicegroups and
their playable banks are managed elsewhere. The target puts the canonical
per-identity loaded-bank state beside the project catalog on the worker.

### Voicegroup bank ownership is unclear

Tabs that use the same voicegroup must observe the same edits. Tabs that use
different voicegroups must not. The target needs one shared bank per stable
voicegroup identity, plus safe replacement so readers can finish with an old
bank.

### Raw resource lifetimes cross boundaries

Owning C pointers and mutable project objects must not cross to GUI or audio
callers. Worker-owned RAII types and immutable handles or leases must make
ownership explicit.

### Project roots and derived state travel with requests

After a project opens, worker operations use the worker-owned `DecompProject`
rather than accepting repeated root paths from GUI callers.

### MainWindow risks becoming a relay

As the composition root, `MainWindow` should connect high-level owners. It
must not forward routine project results field by field, mirror worker state,
or implement project loading policy. Direct publication from
`ProjectWorkspace` to `WorkspaceUi` keeps that boundary clear.

### Checks can depend on implementation machinery

Checks should enter through public project behavior, `SongTab` behavior, or a
narrow worker seam. They should not need the private queue representation.

## Target responsibilities

The responsibilities below cite the sole contract under
**Implementation-ready target interfaces**.

### MainWindow

`MainWindow` is the application composition root. It owns:

- `WorkspaceUi`;
- `AudioEngine`;
- `ProjectWorkspace`;
- high-level wiring among those owners.

It constructs `WorkspaceUi` first, or uses an equivalent sequence that makes
the UI shell available immediately. `ProjectWorkspace` construction must not
wait for project discovery, voicegroup loading, sample work, or other file I/O.
Opening a project queues work and returns.

`MainWindow` connects the three `ProjectWorkspace` publication streams directly
to `WorkspaceUi` and reacts to `WorkspaceUi`'s selected-`SongTab` report by
applying audio state. It does not perform project file I/O, access
`DecompProject`, inspect the worker queue, relay routine project fields, read or
write startup-restoration `QSettings`, or own tab-specific load/save policy.

### ProjectWorkspace

`ProjectWorkspace` is the project-wide application service. It owns:

- the private `ProjectIo` instance;
- the selected project identity and `ProjectState`;
- its independent read of the shared `QSettings` project path and normalized
  saved recipe;
- write ownership of the last project path after successful project open;
- semantic project operations such as open, refresh, create, register, delete,
  voicegroup mutation, and sample/catalog work.

`ProjectWorkspace` does not own:

- `SongTab` instances or a live open-tab map;
- any `SongView`, widget pointer, active GUI tab, or tab lifetime;
- a `SongDocument`, `MidiTimeline`, or `AudioEngine`;
- mutable worker-side `DecompProject` state;
- a second startup recipe store.

Its GUI-facing state consists of copied project values, `ProjectState`,
keyed `SongUpdate`s, keyed `ProjectEvent`s, and safe resource handles. It may
know copied saved labels for automatic startup work, but it never receives a
tab pointer or widget identity. A successful project open publishes `Ready`
with the new snapshot; startup song loads are ordinary keyed `SongUpdate`s
after that publication. `ProjectWorkspace` has no operation field or busy
flag.

`ProjectWorkspace::openProject()` refuses only while `Loading`. The
Open Project action's longer disablement while placeholders or UI-submitted
work remain incomplete is enforced by `WorkspaceUi`.

### ProjectIo

`ProjectIo` is a private implementation detail of `ProjectWorkspace`. It:

- owns the worker thread and worker event loop;
- schedules typed worker commands;
- matches its one active FIFO command to one typed result;
- dispatches commands to cohesive operation helpers;
- transports typed results back to `ProjectWorkspace`;
- shuts down deterministically.

It does not define product policy, own tabs, or publish worker objects to GUI
callers. Only `ProjectWorkspace` constructs and directly drives it.

### DecompProject

`DecompProject` remains the existing project catalog concept and is
worker-only. It retains project identity, root, songs, players, track budgets,
voicegroup sources, and sample/catalog data needed by worker operations. It
resolves `VoicegroupId`, updates the canonical worker records, builds complete
replacement banks, and publishes only copied values or safe leases through
`ProjectWorkspace`.

The worker record and GUI view are different types. `LoadedBankEntry` is never
published; `LoadedBankView` is the immutable publication consumed by the GUI.
The worker swaps a complete candidate into the record only after a successful
edit or reload, so a failed operation leaves the previous record intact.

### Worker operation helpers

Small worker-only helpers perform cohesive file work, for example:

- project open and refresh;
- MIDI load and save;
- voicegroup source load, edit preparation, and save;
- sidecar load and save;
- song create, register, and delete;
- previews and catalog scans;
- sample probe, import, export, and registration.

Helpers use worker `DecompProject` state but do not own the project, thread,
queue, or GUI publication policy. Split helpers only where a behavior has its
own inputs, outputs, and dedicated check surface.

### WorkspaceUi

`WorkspaceUi` owns:

- the visible workspace widgets;
- all `SongTab` instances;
- tab selection and tab lifetime;
- the reusable voice picker;
- the `VoicegroupId → LoadedBankView` published view cache.

The picker reads the view cache. The cache is not the canonical worker record
and is not a mutable `DecompProject`.

During shell construction, `WorkspaceUi` reads the saved project path, labels,
and selection from the shared `QSettings` source and calls
`normalizeSavedRecipe(projectPath, labels, selectedLabel)`. It creates named
placeholder tabs and selects the normalized result before project work
completes. This small synchronous settings read is not project file I/O.

`WorkspaceUi` applies project state, keyed project events, and keyed song
updates directly. It writes tab-order and selection keys, prompts for local
document or shared-bank work, and disables conflicting actions. It does not
control `AudioEngine` directly.

### Project-to-UI publication handoff
The keyed event and lease rules here are fixed by the alignment contract; their
declarations appear once in **Implementation-ready target interfaces**.

The public boundary has exactly three streams:

1. standing `ProjectState` publication;
2. one-shot keyed `ProjectEvent` publication, never stored in
   `ProjectState`;
3. keyed `SongUpdate` publication.

```cpp
signals:
    void ProjectWorkspace::projectStatePublished(ProjectState state);
    void ProjectWorkspace::projectEventPublished(ProjectEvent event);
    void ProjectWorkspace::songUpdatePublished(SongUpdate update);

public slots:
    void WorkspaceUi::applyProjectState(ProjectState state);
    void WorkspaceUi::applyProjectEvent(ProjectEvent event);
    void WorkspaceUi::applySongUpdate(SongUpdate update);
```

`applyProjectState()` fills project-wide browser and catalog presentation.
It uses the published state as an input to the local Open Project policy; it
does not enable the action solely because `state != Loading`, and it does not
create placeholders or trigger startup song loads.

`applyProjectEvent()` visits `ProjectEvent` without storing it in
`ProjectState`. A `LoadedBankView` event replaces the
`VoicegroupId → LoadedBankView` entry; tabs holding that identity refresh their
lease from the view cache. Other event alternatives are delivered by their
declared domain key. Catalog events are the unkeyed catalog-dialog cases. A
successful register/delete/create-voicegroup operation updates
standing `ProjectState` rather than inventing another event.

`applySongUpdate()` finds the live tab by `SongName` and ignores an update when
no match exists. It dispatches the payload's staged value or its single
`SongFailed` value:

```cpp
void SongTab::applyMidi(MidiStage value);
void SongTab::applySidecar(SidecarStage value);
void SongTab::applyVoicegroup(VoicegroupId id, VoicegroupLease lease);
void SongTab::applySongSaved(SongSaved value);
void SongTab::applyFailed(SongFailed value);
```

`VoicegroupBound` obtains the lease from the view cache, which was already
replaced by the preceding `LoadedBankView` event. The direct connections are:

```cpp
connect(projectWorkspace, &ProjectWorkspace::projectStatePublished,
        workspaceUi, &WorkspaceUi::applyProjectState);
connect(projectWorkspace, &ProjectWorkspace::projectEventPublished,
        workspaceUi, &WorkspaceUi::applyProjectEvent);
connect(projectWorkspace, &ProjectWorkspace::songUpdatePublished,
        workspaceUi, &WorkspaceUi::applySongUpdate);
```

No forwarding signal, controller, or payload relay in `MainWindow` is part of
the target. Closing a tab removes its `SongName` match; a later publication
has no recipient and is ignored.

### SongTab

Each `SongTab` owns:

- one `SongDocument`;
- one `MidiTimeline`;
- one permanently paired `SongView`;
- its editor/view state;
- its `VoicegroupId` and `VoicegroupLease`;
- local document edit, dirty, readiness, and presentation-error state.

`SongView` consumes the tab's live document and timeline directly. Local
document dirty is distinct from shared-bank dirty, which is the `dirty` field
of the published `LoadedBankView`.

`SongTab` never calls `ProjectWorkspace` or `ProjectIo`, starts a project
load/save/reload, awaits a project future, or stores a project-operation
identity. It receives copied staged values or safe handles through narrow
apply methods and may emit local edit or save intent to `WorkspaceUi`.

### Interactive project operations

Startup restoration is autonomous, but later user actions use the same keyed
result boundary:

1. A song-browser open, reload, save, or voicegroup edit originates in
   `WorkspaceUi`. A `SongTab` may emit local intent to its owner.
2. `WorkspaceUi` sends one semantic operation to `ProjectWorkspace` through
   the high-level connection established by `MainWindow`.
3. `ProjectWorkspace` publishes a keyed `SongUpdate` or `ProjectEvent`.
4. `WorkspaceUi` matches the result, creates or finds a tab when policy allows,
   and calls its passive apply method. Placement and focus remain UI policy.

Shared-bank edits publish a new `LoadedBankView` event. They do not become
per-tab song results, and `ProjectWorkspace` never needs live-tab knowledge.

### Startup session restoration

`QSettings` is the single persisted source for the saved project path, ordered
symbolic song labels, and selected symbolic label. `WorkspaceUi` and
`ProjectWorkspace` read their relevant keys independently and both call
`normalizeSavedRecipe(projectPath, labels, selectedLabel)` for the matching
startup project path at application startup only; the helper's rules are
declared once in the implementation-ready section.

`WorkspaceUi` creates named placeholders and shows the shell immediately.
`ProjectWorkspace` independently queues one asynchronous project open. It
publishes `Loading` while that open is active. The placeholders remain visible
and no placeholder triggers a load request.

On successful open, `ProjectWorkspace` writes the project path, publishes
`Ready` with the accepted snapshot, and then queues startup songs. The startup
recipe for the matching project path is used only during application startup.
The saved selected label is enqueued first, followed by the other normalized
labels in persisted order. Each result is an ordinary `SongUpdate` keyed by
`SongName`; there is no internal startup-name tracking collection.

On open failure, `ProjectWorkspace` publishes `Failed` with `ProjectState.error`
and leaves the previous snapshot intact. `Loading` ends at that success or
failure; it does not cover startup song work. A missing or unplayable saved
label receives a keyed `SongFailed` at `SongStage::Reconcile`. The product
choice of retaining or removing that named placeholder remains in
**Remaining decisions**. Valid labels continue independently.

`WorkspaceUi` keeps Open Project disabled while any placeholder lacks a
terminal song payload or any work it submitted is in flight. It re-enables the
action only when its policy says those conditions are clear, even though the
project state has already reached `Ready`. `openProject()` itself refuses only
while `Loading`.

If a placeholder closes before its update arrives, `WorkspaceUi` has no
matching label and ignores the publication. Later tab-order and selection
changes write only the symbolic label keys. Neither owner writes the other
owner's keys.

Transport is unrelated to restoration and remains on the settled route:
`TransportBar` belongs to `WorkspaceUi`, actions travel up through
`WorkspaceUi` to `MainWindow`, and copied transport state travels back down
through `WorkspaceUi`.
### AudioEngine wiring

`MainWindow` owns `AudioEngine` and all application-level engine wiring.
`ProjectWorkspace`, `WorkspaceUi`, and `DecompProject` do not own the engine.
The audio values and ownership rules are declared once under
**Audio binding values** in the implementation-ready section.

#### Lifetime and selected-tab binding

The UI shell is built first, then `MainWindow` initializes its engine and
publishes copied device status. Shutdown stops timers and audio before
releasing the selected `VoicegroupLease` or destroying tabs. Project I/O never
participates in device lifetime.

`WorkspaceUi` reports its selected `SongTab`; it does not call the engine or
choose another tab. One focused private `MainWindow` helper applies the
reported tab:

```cpp
void MainWindow::applySelectedAudio(const SongTab *tab)
{
    m_audio.stop();
    if (!tab || !tab->isAudioReady()) {
        m_audio.unloadSong();
        m_selectedBankLease.reset();
        return;
    }

    VoicegroupLease next = tab->voicegroupLease();
    m_audio.loadSong(tab->timeline(), next.get(), tab->songSettings());
    m_audio.setMuteMask(tab->muteMask());
    m_audio.setSoloMask(tab->soloMask());
    m_selectedBankLease = std::move(next);
}
```

`AudioEngine::loadSong`, `AudioEngine::updateVoicegroup`, and every other
borrowed-bank entry point accept `const LoadedVoiceGroup *`. The engine borrows
the bank and never copies it. The selected lease remains alive through each
cold load, unload, or replacement call; a null or not-ready selection unloads
before releasing it.

#### Timeline, transport, and settings

`SongTab` rebuilds its timeline from its document and the copied audio sample
rate, then updates its paired `SongView`. Only the selected tab's shared
timeline reaches `AudioEngine::updateTimeline()`. Tick conversion for seeking
uses that tab's timeline rather than an engine-owned editor model.

Transport actions, mute/solo, song settings, global engine settings,
diagnostics, playhead, and activity polling remain focused private helpers on
`MainWindow`. They operate on the selected tab reported by `WorkspaceUi`;
inactive tab changes do not touch the engine. Copied
`AudioPresentationState` travels back to `WorkspaceUi` for its transport bar
and selected tab.

#### Audition, export, and shutdown

Note, voice, sample, and wave audition stay application-level and separate
from selected-song binding. `MainWindow` private helpers call the engine with
the meaningful audition values declared below. Sample and wave bytes are
copied into engine-owned audition slots, so they do not depend on a tab lease.
The sample editor may retain its bounded engine borrow or emit copied
audition values; it never owns the engine or project state.

Offline export captures the selected tab's document, timeline metadata,
settings, and a bank lease once and retains them for the render. It does not
use an engine-borrowed timeline or raw tab-owned bank as an alternate source.

The selection sequence is fixed: report the tab, stop the old transport,
unload or load with the selected timeline and bank borrow, reapply mute/solo,
then retain the new lease. A replacement for an inactive tab updates only its
tab lease. Shutdown stops timers and audio, releases the selected lease,
destroys tabs and GUI leases, then stops `ProjectIo`, finishes or discards its
active result, destroys worker state, and joins.
## Voicegroup identity and shared banks

This section cites the identity and ownership contract declared under
**Implementation-ready target interfaces**.

A stable `VoicegroupId` identifies the project voicegroup independently of a
tab, request, or bank allocation. Worker state is conceptually:

```text
VoicegroupId -> LoadedBankEntry
                 source metadata
                 current VoicegroupLease
                 source-file freshness
                 existing VoicegroupSource dirty/pristine state
```

`WorkspaceUi` holds the published:

```text
VoicegroupId -> LoadedBankView
```

Each view is an immutable publication copy. The map is a GUI view cache, not a
second mutable project or the canonical worker record. The picker reads it.

### Sharing and replacement

- Tabs with the same `VoicegroupId` obtain the same current lease and dirty
  publication.
- Tabs with different identities remain isolated.
- The worker builds a complete replacement before publishing a
  `LoadedBankView`.
- A replacement swaps the view-map entry and lets existing leases finish.
- The last lease may release on the Project I/O or GUI thread, never on the
  audio callback.

### Edit and save flow

1. The picker gathers an edit for the selected tab's `VoicegroupId`.
2. `WorkspaceUi` sends `VoicegroupEditInput` to `ProjectWorkspace`; the tab
   contributes copied values only.
3. The worker validates the identity, applies the source edit, builds a
   complete candidate, and publishes a new `LoadedBankView` on success.
4. `WorkspaceUi::applyProjectEvent()` replaces the view-map entry. Every live
   tab bound to that identity refreshes its lease from the map. If the
   identity is selected, `MainWindow` updates `AudioEngine`.
5. Save writes the canonical source bytes, adopts them through
   `VoicegroupSource::didSave(savedBytes)`, and publishes the post-save
   `LoadedBankView`. A later edit makes the view dirty again.

The editing tab's document stack owns voicegroup undo. Prompting for a dirty
shared bank is once per `VoicegroupId`; other tabs do not grow undo stacks.
The precise inverse command and its worker validation are fixed in the
implementation-ready contract.

## Single project/startup load and result routing
The settled split is that `Loading` covers only open, while startup song work
uses ordinary keyed updates after `Ready`.

`ProjectWorkspace` publishes `Loading` before submitting project open and
publishes either `Ready` with the new snapshot or `Failed` with
`ProjectState.error` when that open completes. The prior snapshot may remain
visible while `Loading`; a failed open does not replace it. Startup song loads
are ordinary keyed `SongUpdate`s after `Ready`.

`WorkspaceUi` owns the Open Project disablement policy. It keeps the action
disabled for the open interval and for any placeholder without a terminal
song payload or any work it submitted that remains in flight. This does not
add a busy field to `ProjectState`. `ProjectWorkspace::openProject()` refuses
only while `Loading`.

The same prevention rule applies to other real conflicts: focus an already
open `SongName` instead of opening it twice, and disable one song's
reload/save trigger until its keyed terminal result. Independent operations
remain available. Closing a tab removes its keyed recipient; it does not
require worker cancellation.

`WorkspaceUi` routes `SongUpdate` by `SongName` and shared-bank events by
`VoicegroupId`. `ProjectWorkspace` does not store tab identity or internal
startup-name tracking. Immutable leases provide resource safety without
incarnation counters.

The only backend lifecycle exception is shutdown: stop accepting commands,
finish or discard the active result according to the private Project I/O
contract, release undelivered owning resources, destroy worker state, and join
the worker.

## Request and result model

Replace broad request bags with typed commands and typed results. A command
contains only data valid for that operation. Private scheduling metadata may
contain tracing or timing data, but no project, song, tab, bank, or request
incarnation counter.

Do not add tab identity to project-wide workspace state. GUI-facing song
results use `SongName`; `WorkspaceUi` performs the live match without creating
a workspace tab registry. Shared-bank views use `VoicegroupId`.

Use an exhaustive variant visitor or equivalent typed dispatch so adding an
operation produces compile errors at every required handling point. Results
must not expose mutable `DecompProject`, mutable worker entries, raw owning C
pointers, references into worker containers, or queue/thread details.

## Implementation-ready target interfaces

This is the sole full type and ownership contract. The declarations are
conceptual target C++; spelling may follow repository conventions, but the
fields, keys, and invariants are fixed by the alignment contract.
Callers do not learn worker scheduling, `DecompProject` storage, or widget
mechanics.

### Stable identities

```cpp
struct SongName {
    QString value;
    friend bool operator==(const SongName &, const SongName &) = default;
};
size_t qHash(const SongName &name, size_t seed = 0);

struct VoicegroupId {
    QString sourceRelativePath;
    QString sectionLabel; // empty for a per-file voicegroup
    friend bool operator==(const VoicegroupId &, const VoicegroupId &) = default;
};
size_t qHash(const VoicegroupId &id, size_t seed = 0);
```
`SongName` is the project-relative `SongInfo::label` and is constructed only
when non-empty; `SongInfo::id` is snapshot-local. `VoicegroupId` is the
project-relative normalized source relative path plus `sectionLabel`; loader
names are aliases, not identity.

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

`normalizeSavedRecipe()` is one pure function used by both readers. It
discards empty labels, keeps the first duplicate, preserves order, and falls
back to the first name. No other section restates these rules.

### Voicegroup resource and bank ownership

`voicegroup_free()` only frees allocations owned by `LoadedVoiceGroup`; it has
no thread-affine state.

```cpp
using VoicegroupLease = std::shared_ptr<const LoadedVoiceGroup>;
using SampleSetLease = std::shared_ptr<const LoadedSampleSet>;

struct LoadedBankView {
    VoicegroupId id;
    VoicegroupLease bank;
    QString loadName;
    bool dirty = false;
    QVector<std::optional<VgVoice>> voices;
};

struct VoicegroupEditInput {
    VoicegroupId id;
    int slot = -1;
    VgVoice value;
    std::optional<VgVoice> expected; // current voice for scalar/existing-voice undo
};

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
`{ id, bank, loadName, dirty, voices }`. `WorkspaceUi` holds a
`VoicegroupId → LoadedBankView` map. Tabs hold the id and a `VoicegroupLease`
copy of the same shared pointer. The picker reads the map; it does not mutate
the worker entry.

The worker wraps each successful owning `LoadedVoiceGroup *` exactly once.
The lease may release on the Project I/O or GUI thread, never on the audio
callback. `AudioEngine` borrows a `const LoadedVoiceGroup *`; `MainWindow`
retains the selected lease. Shutdown stops audio before releasing that lease,
destroys tabs and GUI leases, then stops `ProjectIo`, discards or finishes the
active result, destroys worker state, and joins.

`dirty` is the current `VoicegroupSource::dirty()` bit. Save calls
`didSave(savedBytes)` only for the bytes written; a newer edit remains dirty.
This uses existing source state, not a new token.

Voicegroup undo lives on the editing tab's document stack. For scalar or
existing-voice undo, the inverse `VoicegroupEditInput` carries `expected`; the
worker no-ops when the current voice does not match and the command becomes
obsolete. For blank-slot undo, the stack stores
`VoicegroupSource::BlankSlotMaterialization` and the worker calls
`revertBlankSlotMaterialization`. Undo never uses a second identity stack, and
other tabs on the identity do not grow stacks. The worker is the only
validator.

Sample-set results use `SampleSetLease` with the matching C deleter. No raw
owning sample-set pointer enters UI state.

```cpp
class DecompProject {
public:
    ProjectSnapshot openProject(QString root, QString *error);
    std::optional<SongInfo> playableSong(SongName name) const;
    LoadedBankView loadBank(const SongInfo &song, QString *error);
    LoadedBankView applyVoicegroupEdit(VoicegroupEditInput input, QString *error);
    LoadedBankView saveVoicegroup(SaveVoicegroupInput input, QString *error);
};
```

`loadBank()` reuses an unchanged entry when identity and source timestamp
permit. Edit and reload build a complete candidate, then replace `current`;
an error leaves the old entry. The worker derives structural versus scalar
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
    QString error;
};
```

`ProjectState` has exactly `{ state, snapshot, catalog, error }`. During
`Loading`, the prior snapshot may remain. A failed open sets `state` and
`error` without replacing that snapshot. There is no operation field or busy
flag. Startup song work begins after successful open has published `Ready`.

Every fan-out `ProjectEvent` alternative has its domain key except the catalog
dialog publications. The key contract is:

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
struct ProjectMutationFailed {
    std::optional<SongName> song;
    std::optional<VoicegroupId> voicegroup;
    QString message;
};

using ProjectEvent = std::variant<
    LoadedBankView, RegistrationPlanResult, DeletionPlanResult,
    PreviewPlan, PreviewReady, SampleSetReady, SamplesProbed, SampleRead,
    SampleCommitted, SongCreated, ProjectMutationFailed>;
```

`ProjectMutationFailed` carries at least one applicable `SongName` and/or
`VoicegroupId` key. `SampleSetReady` and `SamplesProbed` are intentionally
unkeyed because there is one catalog dialog. `LoadedBankView` is keyed by its
`id`, previews by `voicegroup`, sample events by `name`, and song events by
`song`. A bank load publishes the view before the song's `VoicegroupBound`
update. Edit and save of an already-bound identity publish the view event only.

### Song publications

```cpp
struct MidiStage {
    SongName song;
    SongInfo info;
    SmfFile smf;
    int trackBudget = 16;
};
struct SidecarStage {
    SongName song;
    bool loaded = false;
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
};

enum class SongStage { Midi, Voicegroup, Sidecar, Reconcile, Save };
struct SongFailed {
    SongStage stage;
    QString message;
};

using SongPayload = std::variant<MidiStage, SidecarStage, VoicegroupBound,
                                 SongSaved, SongFailed>;

struct SongUpdate {
    SongName song;
    SongPayload payload;
};
```

Each worker stage that is wrapped as a `SongUpdate` carries its `SongName`.
`ProjectWorkspace` uses that field to publish directly; it does not retain a
remainder set to reconstruct the key. `SongUpdate::song` remains the public
routing key.

`SongPayload` contains successful stages and one `SongFailed` type. A MIDI,
voicegroup, sidecar, reconcile, or save error publishes that type with its
stage. Sidecar missing is successful `SidecarStage{ loaded: false }`, not a
failure. Project-open failure remains only `ProjectState.error`.

`ProjectWorkspace` publishes `MidiStage` before later sidecar or voicegroup
stages for a song. `SongSaved` lets the tab adopt a matching document save
snapshot without owning the operation. Missing or unplayable saved names use
`SongFailed{ SongStage::Reconcile, ... }`; the remaining presentation choice
is the single product decision below.

### ProjectWorkspace semantic operations

```cpp
struct OpenSongInput { SongName song; };
struct ReloadSongInput { SongName song; };
struct OpenProjectInput { QString root; };
struct SaveSongInput {
    SongName song;
    SongSaveSnapshot snapshot;
};
struct SaveSidecarInput {
    SongName song;
    ViewSidecar::Snapshot snapshot;
};
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
using RegisterSongInput = RegistrationPlanInput;
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

class ProjectWorkspace {
public slots:
    void openProject(OpenProjectInput input);
    void refreshProject();
    void openSong(OpenSongInput input);
    void reloadSong(ReloadSongInput input);
    void saveSong(SaveSongInput input);
    void saveVoicegroup(SaveVoicegroupInput input);
    void saveSidecar(SaveSidecarInput input);
    void applyVoicegroupEdit(VoicegroupEditInput input);
    void createSong(CreateSongInput input);
    void createVoicegroup(CreateVoicegroupInput input);
    void planRegistration(RegistrationPlanInput input);
    void registerSong(RegisterSongInput input);
    void planDeletion(DeletionPlanInput input);
    void deleteSong(DeleteSongInput input);
    void planPreview(PreviewPlanInput input);
    void preview(PreviewInput input);
    void cleanupPreview();
    void refreshCatalog();
    void loadSampleSet(LoadSampleSetInput input);
    void probeSamples();
    void readSample(ReadSampleInput input);
    void commitSample(CommitSampleInput input);

signals:
    void projectStatePublished(ProjectState state);
    void projectEventPublished(ProjectEvent event);
    void songUpdatePublished(SongUpdate update);
};
```

`WorkspaceUi` is the caller. It enforces one live tab per `SongName`, supplies
copied save snapshots, and sequences voicegroup, MIDI, and sidecar save where
current user-visible behavior requires it. Placement (focus, replace, or new
tab) stays in `WorkspaceUi`; it is not a project input. `MainWindow` owns only
the three direct publication connections.

### Private ProjectIo command/result interface

```cpp
struct OpenProjectCommand { QString root; };
struct LoadSongCommand {
    SongName song;
    SongInfo resolvedSong;
};
struct LoadVoicegroupCommand {
    SongName song;
    SongCfg cfg;
};
struct SaveSongCommand { SaveSongInput input; };
struct SaveVoicegroupCommand { SaveVoicegroupInput input; };
struct ApplyVoicegroupEditCommand { VoicegroupEditInput input; };
struct ReadSidecarCommand { SongName song; };
struct WriteSidecarCommand { SaveSidecarInput input; };
struct CreateSongCommand { CreateSongInput input; };
struct CreateVoicegroupCommand { CreateVoicegroupInput input; };
struct RegistrationPlanCommand { RegistrationPlanInput input; };
struct RegisterSongCommand { RegisterSongInput input; };
struct DeletionPlanCommand { DeletionPlanInput input; };
struct DeleteSongCommand { DeleteSongInput input; };
struct PreviewPlanCommand { PreviewPlanInput input; };
struct PreviewCommand { PreviewInput input; };
struct CleanupPreviewCommand {};
struct RefreshCatalogCommand {};
struct LoadSampleSetCommand { LoadSampleSetInput input; };
struct ProbeSamplesCommand {};
struct ReadSampleCommand { ReadSampleInput input; };
struct CommitSampleCommand { CommitSampleInput input; };

using ProjectCommand = std::variant<
    OpenProjectCommand, LoadSongCommand, LoadVoicegroupCommand,
    SaveSongCommand, SaveVoicegroupCommand, ApplyVoicegroupEditCommand,
    ReadSidecarCommand, WriteSidecarCommand, CreateSongCommand,
    CreateVoicegroupCommand, RegistrationPlanCommand, RegisterSongCommand,
    DeletionPlanCommand, DeleteSongCommand, PreviewPlanCommand, PreviewCommand,
    CleanupPreviewCommand, RefreshCatalogCommand, LoadSampleSetCommand,
    ProbeSamplesCommand, ReadSampleCommand, CommitSampleCommand>;

struct CommandFailure { QString message; }; // private and unkeyed

using ProjectResult = std::variant<
    ProjectSnapshot, MidiStage, LoadedBankView, VoicegroupBound,
    SidecarStage, SongSaved, RegistrationPlanResult, DeletionPlanResult,
    PreviewPlan, PreviewReady, SampleSetReady, SamplesProbed, SampleRead,
    SampleCommitted, SongCreated, VoicegroupCatalog, CommandFailure>;
```

Commands use the public inputs or empty tags. Only `OpenProjectCommand` has a
root. Startup names are resolved against the accepted snapshot and enqueued
after successful open. Do not wrap the old broad request bag.

The FIFO adapter matches the one active command to its result. Worker
exceptions become private `CommandFailure`; `ProjectWorkspace` maps that
failure onto the appropriate keyed `SongFailed` or keyed
`ProjectMutationFailed`, or onto `ProjectState.error` for project open.
`CommandFailure` never crosses as a public unkeyed event.

`ProjectIo` has one private `submit(ProjectCommand)` seam, one active FIFO
command, and one private result callback. There is no per-command
cancellation or old-result filter. A closed tab has no keyed recipient.
Shutdown stops accepting commands, finishes or discards the active result,
releases undelivered owning resources, and joins the worker.

### Audio binding values

```cpp
struct SelectedAudioState {
    SongName song;
    std::shared_ptr<const MidiTimeline> timeline;
    VoicegroupId voicegroupId;
    VoicegroupLease voicegroup;
    SongSettings settings;
    uint32_t muteMask = 0;
    uint32_t soloMask = 0;
    bool ready = false;
};

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

Only the `SongTab` reported as selected by `WorkspaceUi` produces selected
audio values. `MainWindow` private helpers call `AudioEngine` and own all
engine calls. A null or not-ready selection unloads before releasing the old
lease. Audition payloads are copied values or safe leases. Transport and
global settings use direct focused helpers rather than thin value-intent
types. Whether the declared values travel as one signal or a few focused
signals is an implementation freedom; ownership and ordering are fixed.

## Refactoring sequence

Each phase is a behavior-preserving cutover to the contract above. Keep the
implementation seams cohesive and delete an obsolete path once its callers
have moved; do not retain forwarding wrappers.

### 1. Cut AudioEngine over to const voicegroup borrows

Change `AudioEngine::loadSong`, `AudioEngine::updateVoicegroup`, and every
other borrowed-bank API to accept `const LoadedVoiceGroup *`. The engine
continues to borrow only, while `VoicegroupLease` supplies lifetime. No path
may cast away constness.

At the same boundary, wrap each successful worker-owned bank exactly once and
remove raw GUI/session destruction. Keep old/new leases alive around a cold
engine swap and release only after audio unload or rebind returns.

### 2. Add stable identities, saved-recipe normalization, and existing dirty adoption

Introduce only `SongName` and `VoicegroupId`, with equality and `qHash`.
At application startup, centralize both settings readers on
`normalizeSavedRecipe(projectPath, labels, selectedLabel)`. Keep existing
`SongSaveSnapshot::{revision,saveStateToken}` and
`VoicegroupSource::{sourceBytes,didSave,dirty}` adoption. Do not add
project-wide tab identities, transport revisions, or incarnation counters.

### 3. Extend DecompProject on the worker

Keep current discovery behavior, then place the canonical
`VoicegroupId → LoadedBankEntry` records beside the project catalog. Build
complete candidates, replace the current lease only on success, and publish
`LoadedBankView` copies. Remove GUI discovery state and per-tab bank loading
once the worker path covers load, edit, save, reload, and replacement.

### 4. Keep MainWindow as a thin composition root

Construct `WorkspaceUi` first or expose its shell immediately. Construct the
non-blocking `ProjectWorkspace`, retain `AudioEngine`, and wire the three
direct publication connections. Remove project-state and routine data relay
from `MainWindow`; retain only composition, selection-to-audio helpers, and
shutdown ordering.

### 5. Make ProjectWorkspace project-wide only

Move project selection, copied project state, and project-open state into
`ProjectWorkspace`. At application startup it independently reads
`SavedWorkspaceRecipe`; it publishes `Loading`, submits exactly one open, and
on success writes the path and publishes `Ready` with the accepted snapshot.
After that successful startup open, it queues the normalized selected song
first, then the other saved labels in persisted order as ordinary keyed
`SongUpdate`s. There is no internal startup-name tracking collection.

`WorkspaceUi` owns the Open Project disablement policy: it remains disabled
while placeholders lack terminal song payloads or UI-submitted work is in
flight. `ProjectWorkspace::openProject()` refuses only while `Loading`.
Project-open failure publishes `Failed` and leaves the prior snapshot intact.
Loading ends at open success or failure, before startup song updates complete.

### 6. Move tab policy to WorkspaceUi and SongTab

Make `WorkspaceUi` own tab selection and lifetime. Make `SongTab` own its
document, timeline, paired view, local document dirty state, readiness, and
presentation state. Keep keyed result matching, picker policy, placement, and
shared-bank view-cache updates in `WorkspaceUi`. `SongTab` emits local intent
only and has no project-service or project-operation identity dependency.

For an interactive project switch, use this exact sequence:

1. `WorkspaceUi` prompts dirty songs and prompts once per dirty
   `VoicegroupId`.
2. After confirmation it calls `openProject`; Open Project becomes disabled.
3. While `Loading`, the prior snapshot may remain and the existing tabs and
   `VoicegroupId → LoadedBankView` map stay in place.
4. On failure, publish `Failed` and its error; snapshot, tabs, view map, and
   persisted project and song settings in `QSettings` are unchanged.
5. On `Ready`, `MainWindow` performs null-selection unload, then
   `WorkspaceUi` destroys the tabs, clears the view map, and clears the old
   `lastOpenSongs` and `lastSongLabel` settings (or otherwise starts with zero
   tabs / a clean default). It does not call `normalizeSavedRecipe()` or
   recreate placeholders from the previous project's recipe; it reconciles the
   new snapshot directly.

For application startup only, normalized saved songs then arrive as ordinary
keyed updates. No switch step uses a worker tab registry or a second undo
stack.

### 7. Replace generic worker requests with typed operations

Replace the broad request bag and kind switches with the private
`ProjectCommand` and `ProjectResult` variants. An exhaustive visitor dispatches
one operation at a time through `ProjectIo`; `ProjectWorkspace` maps private
failures to the keyed public streams. Remove cancellation and overlap machinery
for actions disabled by `WorkspaceUi`.

### 8. Cut GUI callers over by behavior

Move complete workflows in this order:

1. saved placeholders, project open, snapshot publication, and startup song
   updates;
2. song load/reload, keyed application, and sidecars;
3. voicegroup load, edit, save, undo, and shared-view replacement;
4. create, register, delete, previews, catalog, and samples.

For each workflow, migrate input, result, failure, and placement behavior
together. Delete old `MainWindow` entry points when their behavior has moved;
do not preserve forwarding aliases.

### 9. Finish audio handoff and shutdown order

The selected `SongTab` takes its `VoicegroupLease` from the
`WorkspaceUi` `VoicegroupId → LoadedBankView` map. `MainWindow` applies
`SelectedAudioState` with stop, unload/load or update, mute/solo, and lease
ordering. Inactive tab timeline and bank updates do not touch `AudioEngine`.

Move timeline rebuild and paired-view updates into `SongTab`; keep transport,
audition, telemetry, diagnostics, and export in focused `MainWindow` private
helpers. `AudioEngine` receives only the selected tab's shared timeline and
`const LoadedVoiceGroup *` borrow. Shutdown stops audio and timers before
releasing leases, destroying tabs, or stopping worker state.

The phase is complete when replacement, selected-tab switching, inactive-tab
editing, audition, export, and shutdown all use the declared lease and
publication boundaries.

## Suggested file layout

`src/project/projectio.h/.cpp` holds the private thread, queue, transport, and
command/result variants until a split has a distinct dependency boundary and a
dedicated check:

```text
src/project/
├── decompproject.h/.cpp          existing catalog, extended on worker
├── projectworkspace.h/.cpp       project-wide service, startup, and state
└── projectio.h/.cpp              private thread, queue, transport, and
                                  command/result variants

src/ui/
├── workspaceui.h/.cpp             widgets, picker, and SongTabs
└── songtab.h/.cpp                 document, timeline, view, and local state
```

Do not prescribe a directory of operation fragments.
UI headers depend on semantic workspace state and safe resource handles, not
thread or queue types.

## Verification strategy

### Ownership checklist

- `MainWindow` owns the three composition objects and all `AudioEngine` calls.
- The shell and named placeholders render before project work completes.
- Worker `DecompProject` contains canonical `LoadedBankEntry` records; the GUI
  contains only the published `LoadedBankView` map.
- `ProjectWorkspace` has `ProjectState` exactly `{ state, snapshot, catalog,
  error }`, no live-tab state, operation field, busy flag, or internal
  startup-name tracking collection.
- `WorkspaceUi` owns tabs, selection, placement, picker, the view cache, and
  Open Project disablement policy. `SongTab` owns local document state and
  remains passive toward project operations.
- `SongName` and `VoicegroupId` are the only semantic identities; every
  fan-out event uses its declared domain key, with only catalog-dialog events
  intentionally unkeyed.
- Bank replacement retains old leases through cold audio swaps, and worker
  mutable state never crosses the GUI boundary.

### Acceptance matrix

| Contract item | Observable acceptance |
| --- | --- |
| Canonical bank ownership | The worker record is `LoadedBankEntry`; the GUI map is `LoadedBankView` and no other object is the canonical bank. |
| Loading and Open Project | Open state reaches `Ready` at snapshot publication, startup loads use keyed updates, and UI policy alone keeps Open Project disabled while placeholders or submitted work remain. |
| Event keys | Keyed `LoadedBankView`, preview, sample, song-created, and mutation-failure publications route to their domain; catalog-dialog publications are the only unkeyed public events. |
| Song failures | `SongPayload` has one `SongFailed` with `SongStage`; sidecar absence is a nonfailure stage and project-open errors stay in `ProjectState.error`. |
| Voicegroup undo | Existing-voice inverses use `expected`; blank-slot inverses store `BlankSlotMaterialization` and call its revert operation; validation remains worker-side. |
| Interactive switching | Dirty prompts, failure preservation, Ready teardown, null-selection unload, view-cache clearing, and clean-default start without previous-project placeholder recreation follow Phase 6. |
| Audio and file layout | Only the meaningful audio values remain, and `src/project/projectio.h/.cpp` retains private machinery until a justified split. |
| Single declaration site | Full types occur only in **Implementation-ready target interfaces**; other sections refer to them by name and do not redeclare fields or rules. |
| Forbidden alternatives | No availability enum, documentation split, mutable const-removal cast, request identity, or worker-owned undo stack is introduced. |

## Remaining decisions and allowed implementation freedom

### Resolved alignment decisions

NC4 (interactive project switch) and NC5 (Loading versus startup song work)
are resolved by this plan and are not implementation decisions. They follow the
Phase 6 sequence and the `ProjectState`/`WorkspaceUi` boundaries above.

### Product decision still open

There is one product decision: when a saved song label is missing or
unplayable, should its named skeleton remain with a simple failure
presentation, or should it be removed? `SongFailed` at
`SongStage::Reconcile` identifies the label either way. Do not choose this
presentation policy during implementation.

### Safe implementation freedom

- `ProjectIo` may choose its private FIFO container. It runs one command at a
  time, publishes MIDI before later stages for a song, and releases owning
  resources deterministically.
- `VoicegroupLease` may remain a shared-pointer alias or become a small value
  wrapper. It must expose only a const borrow, free exactly once, and obey the
  shutdown order.
- `DecompProject` may choose its private bank-map container and helper split.
  Identity, replacement atomicity, existing source dirty state, and copied
  publication are fixed.
- Private helper names and whether the declared audio values travel in one or
  several focused signals may vary. Ownership, fields, selection routing, and
  call order are fixed.
- `SampleEditorDialog` may keep a bounded application-level engine borrow or
  emit copied audition values. It must not own the engine or project state.

The plan must not answer these by adding a tab registry to
`ProjectWorkspace`, exposing `DecompProject`, transferring `AudioEngine`
ownership, or making `MainWindow` a project-data relay.

## Design test

The target is sound if each owner can change without forcing unrelated owners
to change:

- worker scheduling can change behind private `ProjectIo`;
- project discovery and canonical bank coordination can change inside worker
  `DecompProject`;
- startup placeholder persistence can change inside `WorkspaceUi`, while
  project open and keyed publication can change inside `ProjectWorkspace`;
- tab layout and lifetime can change inside `WorkspaceUi` and `SongTab`;
- audio binding can change inside `MainWindow` and `AudioEngine` wiring;
- GUI callers continue to use semantic operations, copied state, and safe
  handles.

If a change requires GUI code to know the worker queue, the worker to know a
tab, the workspace to own audio, or audio to hold a raw owning pointer, the
boundary is wrong.

