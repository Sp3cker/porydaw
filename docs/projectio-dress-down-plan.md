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
- `ProjectWorkspace` owns project-wide state and a private `ProjectIo`. Its
  small semantic seam is `openProject(OpenProjectInput)` plus
  `submit(ProjectOperation)`.
- `ProjectIo` hides the worker thread, queue, transport, and private command and
  result variants.
- `SaveSongInput`, `SongSaved`, and `SongFailed` define the semantic song-save
  contract under **Implementation-ready target interfaces**; `ProjectIo` owns
  it and `WorkspaceUi` applies its public outcomes.
- Worker-side `DecompProject` contains the canonical `LoadedBankEntry` for each
  `VoicegroupId` and performs project file I/O.
- `WorkspaceUi` owns the widgets, reusable voice picker, all `SongTab`
  instances, and its private `VoicegroupViewCache`; transient `QSet<SongName>`
  tombstones remain direct `WorkspaceUi` state.
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
│   ├── VoicegroupViewCache              [private shared-bank coordinator]
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
`VoicegroupViewCache` owns the published immutable bank views and shared-bank
transition state; the worker record remains the canonical source.

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
21. `WorkspaceUi` disables conflicting actions while a submitted operation is in
    flight. A closed loading tab gets a transient `SongName` tombstone and the
    same name cannot be reopened until that semantic load reaches its terminal
    success or failure; this is UI policy, not `ProjectWorkspace` state. Do not
    add cancellation, request or incarnation IDs, speculative external-file
    race guards, retries, rollback, or a second history stack. Independent
    operations remain available, and shutdown may finish or discard its active
    worker result.

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

### Workspace operations are shallow

An operation-per-slot workspace surface makes callers learn worker mechanics.
The target gives `ProjectWorkspace` a small semantic seam: open is separate,
and `submit(ProjectOperation)` carries user intent. In particular,
`WorkspaceUi` submits `SaveSongInput` and applies the keyed `LoadedBankView`
and terminal `SongSaved`/`SongFailed` outcomes defined under
**Implementation-ready target interfaces**; it does not own save sequencing.

### Tab policy has leaked into project-wide state

Live-tab registries, active GUI-tab state, tab liveness, tab-close policy, and
voicegroup assignment by tab-specific identity do not belong to a project-wide
workspace.
`WorkspaceUi` owns those live collection concerns, while `SongTab` owns local
document, history, readiness, and presentation state. Command completion stays
private `ProjectIo`; tabs never own it. Copied stable labels used for project
work are semantic keys, not a registry of live tabs.

### Project catalog state is split

The current `DecompProject` describes the project, but loaded voicegroups and
their playable banks are managed elsewhere. The target puts the canonical
per-identity loaded-bank state beside the project catalog on the worker.

### Shared-bank undo crosses an asynchronous seam

`QUndoStack` normally advances synchronously, while a shared-bank request can
conflict after worker validation. The target keeps one `SongHistory` over that
stack: document requests cross immediately, but bank requests prepare the exact
worker draft while holding the index fixed through confirmation. Document dirty
state remains separate from `LoadedBankView.dirty`.

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

`ProjectWorkspace` is the project-wide module. It owns:

- the private `ProjectIo` instance;
- the selected project identity and `ProjectState`;
- its independent read of the shared `QSettings` project path and normalized
  saved recipe;
- write ownership of the last project path after successful project open;
- semantic project operations such as open, refresh, create, register, delete,
  voicegroup mutation, and sample/catalog work;
- semantic song operations through `SaveSongInput`, with `SongSaved` and
  `SongFailed` outcomes under the semantic-save contract declared in
  **Implementation-ready target interfaces**.

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

Callers submit `OpenProjectInput` through `openProject()` and all other
user-domain work through `submit(ProjectOperation)`. A save uses
`SaveSongInput`; its `SongSaved`/`SongFailed` outcome and any keyed
`LoadedBankView` publication follow the semantic-save contract under
**Implementation-ready target interfaces**. `SaveSidecarInput` remains an
independent fire-and-forget cosmetic operation for close or switch
persistence.

`ProjectWorkspace::openProject()` refuses only while `Loading`. The
Open Project action's longer disablement while placeholders or UI-submitted
work remain incomplete is enforced by `WorkspaceUi`.

### ProjectIo

`ProjectIo` is a private implementation detail of `ProjectWorkspace`. It:

- owns the worker thread and worker event loop;
- schedules typed worker commands;
- matches its one active FIFO command to typed results and one terminal result;
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
- the private `VoicegroupViewCache` shared-bank coordinator;
- transient `QSet<SongName>` load tombstones for closed in-flight tabs.

`VoicegroupViewCache` is the private shared-bank coordinator. It is not the
canonical worker record, a mutable `DecompProject`, or a project-wide tab
registry.

During shell construction, `WorkspaceUi` reads the saved project path, labels,
and selection from the shared `QSettings` source and calls
`normalizeSavedRecipe(projectPath, labels, selectedLabel)`. It creates named
placeholder tabs and selects the normalized result before project work
completes. This small synchronous settings read is not project file I/O.

`WorkspaceUi` applies project state, keyed project events, and keyed song
updates directly. It writes tab-order and selection keys, prompts for local
document or shared-bank work, and disables conflicting actions. For a song
save it captures `SaveSongInput` and applies any keyed `LoadedBankView` event
plus the terminal `SongSaved` or `SongFailed` outcome under the semantic-save
contract in **Implementation-ready target interfaces**. It never sequences
filesystem stages or correlates stage callbacks. It owns transient load
tombstones for closed loading tabs and clears them when the accepted project
is replaced. It does not control `AudioEngine` directly.

### Project-to-UI publication handoff

The keyed event and lease rules here are fixed by the alignment contract; their
declarations appear once in **Implementation-ready target interfaces**.

The public boundary has exactly three streams:

1. standing `ProjectState` publication;
2. one-shot keyed `ProjectEvent` publication, never stored in
   `ProjectState`;
3. keyed `SongUpdate` publication.

`WorkspaceUi` receives those streams through its
`applyProjectState()`, `applyProjectEvent()`, and `applySongUpdate()` methods.
The stream names and apply-method signatures are declared only in the
implementation-ready contract.

`applyProjectState()` fills project-wide browser and catalog presentation.
It uses the published state as an input to the local Open Project policy; it
does not enable the action solely because `state != Loading`, and it does not
create placeholders or trigger startup song loads.

`applyProjectEvent()` visits `ProjectEvent` without storing it in
`ProjectState`. A `LoadedBankView` event is handed to `VoicegroupViewCache`;
tabs holding that identity refresh their lease through the helper. This
includes the independent keyed event prescribed by the semantic-save contract
in **Implementation-ready target interfaces**. For `VoicegroupEditApplied` and
`VoicegroupEditConflict`, `WorkspaceUi` asks the cache for its pending origin,
looks up that unique live tab by `SongName`, and passes its `SongHistory` to the
cache resolver; the cache's pending `Kind` selects the direction-specific
history method. `VoicegroupMutationFailed` goes to the hard-error resolver; no
pending transition fields are stored in `WorkspaceUi`. Other event
alternatives, including keyed mutation-failure alternatives, are delivered by
their declared domain key. `CatalogMutationFailed` and the successful
catalog-dialog events are the only unkeyed publications. A successful
register/delete/create-voicegroup operation updates standing `ProjectState`
rather than inventing another event.

`applySongUpdate()` finds the live tab by `SongName` and ignores an update when
no match exists. It dispatches the payload's staged value or its single
`SongFailed` value through the narrow `SongTab` apply methods declared below.
For a successful load, `MidiStage`, `SidecarStage`, and terminal
`VoicegroupBound` arrive in that order. Semantic-save handling follows the
`SaveSongInput`, `SongSaved`, and `SongFailed` contract under
**Implementation-ready target interfaces**; any bank event is already applied
through `VoicegroupViewCache`.

`VoicegroupBound` obtains the lease from `VoicegroupViewCache`, which was
already updated by the preceding `LoadedBankView` event. `MainWindow` connects
each of the three streams directly to the corresponding `WorkspaceUi` apply
method; there is no forwarding signal, controller, or payload relay in
`MainWindow`.
Closing a tab removes its live `SongName` recipient. If a closed loading tab
has in-flight work, `WorkspaceUi` records its transient tombstone, drops
remaining staged publications, refuses an immediate reopen of that name, and
erases the tombstone only at terminal success or `SongFailed`.

### SongTab

Each `SongTab` owns:

- one `SongDocument`;
- one `MidiTimeline`;
- one permanently paired `SongView`;
- one `SongHistory` interface over exactly its existing `QUndoStack`;
- its editor/view state;
- its `VoicegroupId` and `VoicegroupLease`;
- local document edit, dirty, readiness, and presentation-error state.

`SongView` consumes the tab's live document and timeline directly. Local
document dirty is distinct from shared-bank dirty, which is the `dirty` field
of the published `LoadedBankView`. Document dirty follows the tab's opaque
document-state identity and saved identity, not the undo stack clean index;
shared-bank transitions do not dirty the document.

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
   `submit(ProjectOperation)`. It supplies copied snapshots and never sends a
   worker stage tag.
3. `ProjectWorkspace` publishes keyed `SongUpdate` and `ProjectEvent` values.
   A semantic save follows the `SaveSongInput`, `SongSaved`, and `SongFailed`
   contract under **Implementation-ready target interfaces**; `WorkspaceUi`
   applies any independent keyed `LoadedBankView` and one terminal outcome,
   while the worker owns filesystem sequencing.

4. `WorkspaceUi` matches each result, applies a bank event independently of
   the terminal song update, creates or finds a tab when policy allows, and
   calls its passive apply method. Placement and focus remain UI policy.

`SaveSidecarInput` may be submitted independently for cosmetic close or switch
persistence. It is not a caller-managed step in the semantic song-save graph.
Shared-bank edit confirmation and history behavior follow the canonical
`SongHistory`/`VoicegroupViewCache` contract under **Implementation-ready target
interfaces**. Such edits publish keyed bank views and, when required, keyed
receipts or conflicts; they do not become per-tab song results, and
`ProjectWorkspace` never needs live-tab knowledge.

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

On open failure, `ProjectWorkspace` publishes `Failed` with a present
`ProjectState.error` and leaves the previous snapshot intact. `Loading` ends
at that success or failure; it does not cover startup song work. A missing or
unplayable saved label receives a keyed `SongFailed` at
`SongStage::Reconcile`. The product choice of retaining or removing that named
placeholder remains in **Remaining decisions**. Valid labels continue
independently.

`WorkspaceUi` keeps Open Project disabled while any placeholder lacks a
terminal song payload or any work it submitted is in flight. It re-enables the
action only when its policy says those conditions are clear, even though the
project state has already reached `Ready`. `openProject()` itself refuses only
while `Loading`.

For every semantic song load, successful publications are ordered as
`MidiStage`, then `SidecarStage`, then terminal `VoicegroupBound`; a failure
publishes one terminal `SongFailed` instead. If a loading placeholder closes
before that terminal publication, `WorkspaceUi` adds its `SongName` tombstone,
drops staged publications for that name, and refuses reopen until the terminal
payload arrives. It consumes the terminal only to erase the tombstone; it
does not recreate a tab. Accepted project replacement clears all such
tombstones. Other unmatched updates remain ignored; no cancellation or
incarnation counter is needed.

Later tab-order and selection changes write only the symbolic label keys.
Neither owner writes the other owner's keys.

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
choose another tab. A focused private `MainWindow` helper reads that selected
tab directly, stops the old transport, and either unloads before releasing the
old lease when the tab is null or not ready, or obtains the tab lease and
loads its timeline with the borrowed bank and copied settings before applying
mute and solo. The local tab lease stays alive through the engine call, then
becomes the retained selected lease.

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
tab, request, or bank allocation. `DecompProject` keeps the canonical
`VoicegroupId → LoadedBankEntry` records, including source metadata, current
lease, file freshness, and source dirty state. `WorkspaceUi` delegates
published bank views to its `VoicegroupViewCache`. A `LoadedBankEntry` never
crosses the worker seam; a `LoadedBankView` is an immutable GUI publication
copy.

### Sharing and replacement

`LoadedBankView` replacement is atomic at the publication seam: tabs with the
same `VoicegroupId` refresh from the new view and tabs with different
identities remain isolated. Existing `VoicegroupLease` values remain valid
until their last non-audio owner releases them. The last lease may release on
the Project I/O or GUI thread, never on the audio callback.

### Edit and save flow

1. The picker gathers a `SetVoicegroupSlot` or `RevertBlankSlot` operation for
   the selected tab's `VoicegroupId`.
2. `WorkspaceUi` starts the cache-owned initial transition and submits the
   copied `VoicegroupEditInput` as a `ProjectOperation`; undo/redo preparation
   and cache begin-before-submit ordering follow the canonical
   `SongHistory`/`VoicegroupViewCache` contract under **Implementation-ready
   target interfaces**.
3. The worker validates the identity and expected value, applies the set or
   blank materialization, or validates and reverts the supplied blank
   materialization token. It returns a typed applied outcome with a complete
   candidate and optional fresh token, or the typed confirmed-conflict/not-applied
   outcome for an expected mismatch or every validation no-op. A hard error is
   returned as absence plus an error message.

4. `ProjectWorkspace` publishes the keyed `LoadedBankView` and, when the
   pending history transition needs it, the keyed `VoicegroupEditApplied`,
   `VoicegroupEditConflict`, or `VoicegroupMutationFailed` outcome.
   `WorkspaceUi` routes those outcomes through the canonical
   `VoicegroupViewCache` contract below; if the identity is selected,
   `MainWindow` updates `AudioEngine`.
5. A semantic song save may carry `SaveVoicegroupInput`; its
   `SaveSongInput`, `SongSaved`, and `SongFailed` behavior, including any
   keyed `LoadedBankView`, follows the semantic-save contract under
   **Implementation-ready target interfaces**.

All async confirmation, branch, dirty, blank-slot, and merge behavior follows
the canonical `Tab history and dirty state` and `VoicegroupViewCache` contract
under **Implementation-ready target interfaces**. `WorkspaceUi` only starts
the owned transition and routes its keyed terminal outcome through the unique
live origin tab; it stores no pending origin, kind, draft, or blank token.

## Single project/startup load and result routing

The settled split is that `Loading` covers only open, while startup song work
uses ordinary keyed updates after `Ready`.

`ProjectWorkspace` publishes `Loading` before submitting project open and
publishes either `Ready` with the new snapshot or `Failed` with a present
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
remain available. Closing a loading tab records a transient `SongName`
tombstone, refuses an immediate reopen of that name, and drops staged
publications until its terminal `VoicegroupBound` or `SongFailed`. Accepted
project replacement clears tombstones; it does not require worker
cancellation.

`WorkspaceUi` routes `SongUpdate` by `SongName` and shared-bank events by
`VoicegroupId`. `ProjectWorkspace` does not store tab identity or internal
startup-name tracking. Immutable leases provide resource safety without
incarnation counters.

The only backend lifecycle exception is shutdown: stop accepting commands,
finish or discard the active result according to the private Project I/O
contract, release undelivered owning resources, destroy worker state, and join
the worker.

## Request and result model

Replace broad request bags with typed commands and typed results. The public
`ProjectWorkspace` seam is `openProject(OpenProjectInput)` plus
`submit(ProjectOperation)`; `ProjectOperation` contains user-domain inputs
only and never exports private worker stage tags. Private scheduling metadata
may contain tracing or timing data, but no project, song, tab, bank, or request
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
`{ id, bank, loadName, dirty, voices }`. `VoicegroupViewCache` is the private
`WorkspaceUi` owner for published views and shared-bank transition state.
Tabs hold the id and a `VoicegroupLease` copy of the same shared pointer. The
picker reads through the helper; it does not mutate the worker entry.

The worker wraps each successful owning `LoadedVoiceGroup *` exactly once.
The lease may release on the Project I/O or GUI thread, never on the audio
callback. `AudioEngine` borrows a `const LoadedVoiceGroup *`; `MainWindow`
retains the selected lease. Shutdown stops audio before releasing that lease,
destroys tabs and GUI leases, then stops `ProjectIo`, discards or finishes the
active result, destroys worker state, and joins.

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
    LoadedBankView loadBank(const SongInfo &song, QString *error);
    std::optional<VoicegroupEditResult> applyVoicegroupEdit(VoicegroupEditInput input, QString *error);
    LoadedBankView saveVoicegroup(SaveVoicegroupInput input, QString *error);
};
```

`loadBank()` reuses an unchanged entry when identity and source timestamp
permit. `applyVoicegroupEdit()` returns a
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

Every fan-out `ProjectEvent` alternative has its domain key except catalog
dialog publications. The exhaustive mutation-failure sum is:

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
    bool sidecarSaved = false;
    std::optional<QString> sidecarError;
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

Each worker stage wrapped as a `SongUpdate` carries its `SongName`;
`ProjectWorkspace` publishes that key directly and never reconstructs it from
a secondary collection. `SongUpdate::song` remains the public routing key.

`SongPayload` contains successful load stages and one `SongFailed` type. A
fatal load or save error publishes that type with its stage. Sidecar missing is
successful `SidecarStage{ loaded: false }`, not a failure. Project-open failure
remains only in the optional `ProjectState.error`.

For a successful song load, `ProjectWorkspace` publishes `MidiStage`, then
`SidecarStage`, then terminal `VoicegroupBound`; a failure publishes one
terminal `SongFailed` instead. Semantic-save behavior is specified by
`SaveSongInput`, `SongSaved`, and `SongFailed` below. Missing or unplayable
saved names use `SongFailed{ SongStage::Reconcile, ... }`; the remaining
presentation choice is the single product decision below.

### ProjectWorkspace semantic operations

```cpp
struct OpenSongInput { SongName song; };
struct ReloadSongInput { SongName song; };
struct OpenProjectInput { QString root; };
struct SaveSongInput {
    SongName song;
    SongSaveSnapshot snapshot;
    ViewSidecar::Snapshot sidecarSnapshot;
    std::optional<SaveVoicegroupInput> voicegroup;
};
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
    SaveSidecarInput, VoicegroupEditInput, CreateSongInput,
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

`WorkspaceUi` owns a transient `QSet<SongName>` for closed loading tabs.
It contains a name only while that name's semantic load remains in flight;
terminal `VoicegroupBound` or `SongFailed` erases it, and accepted project
replacement clears it. It is not project state or a tab registry.

A standalone `SaveSidecarInput` in `ProjectOperation` remains a fire-and-forget
cosmetic persistence operation for close or switch; it is not a
caller-managed song-save stage. Its private `SidecarWriteResult` records either
write success or an error, is consumed without a public event, and merely
advances the FIFO.

`SaveSongInput` is one copied recipe: the `SongName`, detached
`SongSaveSnapshot`, `ViewSidecar::Snapshot`, and optional `SaveVoicegroupInput`
cross the seam. `SaveVoicegroupInput` contains only the `VoicegroupId` and
minted synth definitions; the worker derives source bytes and source path from
the canonical `LoadedBankEntry` and its `VoicegroupSource`.

The worker performs optional voicegroup source and synth writes plus the
required bank refresh first when a voicegroup recipe is present, then writes
MIDI and flags, and finally performs the cosmetic sidecar write. As soon as
the optional voicegroup save and bank refresh land, `ProjectIo` delivers the
resulting `LoadedBankView` while the semantic command remains active, and
`ProjectWorkspace` publishes it as a normal keyed `ProjectEvent` before later
MIDI or flags work. A fatal voicegroup, refresh, MIDI, or flags failure stops
later stages while earlier writes remain; there is no transaction, rollback,
retry, or external-file race guard. The final cosmetic sidecar write is
nonfatal; its status and error are carried by `SongSaved`.

The semantic save publishes exactly one terminal public song outcome:
`SongSaved` on completion or `SongFailed` for a fatal voicegroup, refresh,
MIDI, or flags failure. `SongSaved` carries the copied snapshot,
`flagsWritten`, sidecar success, and an optional sidecar error, but no bank
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
struct ReadSidecarCommand { SongName song; };

struct SidecarWriteResult {
    bool success = false;
    std::optional<QString> error; // present iff success is false
}; // private SaveSidecarInput completion
struct PreviewCleanupCompleted {}; // private CleanupPreviewInput success

using ProjectCommand = std::variant<
    OpenProjectInput, RefreshProjectInput, OpenSongInput, ReloadSongInput,
    LoadSongCommand, LoadVoicegroupCommand, ReadSidecarCommand,
    SaveSongInput, SaveSidecarInput, VoicegroupEditInput,
    CreateSongInput, CreateVoicegroupInput, RegistrationPlanInput,
    RegisterSongInput, DeletionPlanInput, DeleteSongInput, PreviewPlanInput,
    PreviewInput, CleanupPreviewInput, RefreshCatalogInput,
    LoadSampleSetInput, ProbeSamplesInput, ReadSampleInput, CommitSampleInput>;

struct CommandFailure { QString message; }; // private and unkeyed

using ProjectResult = std::variant<
    ProjectSnapshot, MidiStage, LoadedBankView, VoicegroupBound,
    SidecarStage, VoicegroupEditResult, SidecarWriteResult,
    PreviewCleanupCompleted, SongSaved,
    RegistrationPlanResult, DeletionPlanResult, PreviewPlan, PreviewReady,
    SampleSetReady, SamplesProbed, SampleRead, SampleCommitted, SongCreated,
    VoicegroupCatalog, CommandFailure>;
```

The private variant holds public input types directly whenever no worker
enrichment is added. The only private command alternatives beyond those inputs
are the listed load/read stage tags; they do not cross the
`ProjectWorkspace` seam and carry no cached catalog rows.

`ProjectResult` is total over `ProjectCommand`: every command alternative has a
terminal private result in this variant, and every hard worker error becomes
`CommandFailure`. Load commands may emit staged values before terminal
`VoicegroupBound`. A semantic `SaveSongInput` follows the semantic-save
contract under **Implementation-ready target interfaces** and has one private
terminal `SongSaved` or `CommandFailure`, with the public mapping handled by
`ProjectWorkspace`.

The visitor dispatches `VoicegroupEditInput` directly to
`DecompProject::applyVoicegroupEdit`, whose `std::optional<VoicegroupEditResult>`
is present for an applied or confirmed-not-applied outcome. A hard edit error
is the helper's `std::nullopt` plus error, which `ProjectIo` turns into
`CommandFailure`; `ProjectWorkspace` maps it to `VoicegroupMutationFailed`.
The applied value maps to the bank view and, when needed, keyed
`VoicegroupEditApplied`; the confirmed conflict maps to keyed
`VoicegroupEditConflict`. `SidecarWriteResult` completes standalone cosmetic
sidecar writes without becoming a public event. Successful
`CleanupPreviewInput` delivers `PreviewCleanupCompleted`; `ProjectWorkspace`
consumes it without a public event and advances the FIFO, while its hard error
is `CommandFailure`.

Startup names are resolved against the accepted snapshot and enqueued after
successful open. Other worker exceptions become private `CommandFailure`;
`ProjectWorkspace` maps those onto the appropriate keyed `SongFailed` or keyed
`ProjectMutationFailure` alternative, or onto `ProjectState.error` for project
open. `CommandFailure` never crosses as a public unkeyed event.

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
null or not-ready selection unloads before releasing the old lease. Audition
payloads are copied values or safe leases. Transport and global settings use
direct focused helpers rather than thin value-intent types. Whether the
declared values travel as one signal or a few focused signals is an
implementation freedom; ownership and ordering are fixed.

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

### 2. Add validating identities, saved-recipe normalization, and dirty adoption

Introduce `SongName` and `VoicegroupId` through their validating factories,
with equality and `qHash`. At application startup, centralize both settings
readers on `normalizeSavedRecipe(projectPath, labels, selectedLabel)`.
Keep the detached document image and save metadata in `SongSaveSnapshot`;
`SongDocument::didSave()` retains its flags and asynchronous guards before
calling `SongHistory::markDocumentSaved()` for a matching
`DocumentStateIdentity`. `SongDocument` dirty compares current and saved
identities rather than a `QUndoStack` clean index, a monotonic revision
equality, or a whole-document hash. Bank-only transitions preserve the
identity and save guards. Do not add project-wide tab identities, transport
revisions, incarnation counters, a worker history stack, or a second identity
stack.

### 3. Extend DecompProject on the worker

Keep current discovery behavior, then place the canonical
`VoicegroupId → LoadedBankEntry` records beside the project catalog. Build
complete candidates, replace the current lease only on success, and publish
`LoadedBankView` copies. Route semantic song saves through the
`SaveSongInput`, `SongSaved`, and `SongFailed` contract under
**Implementation-ready target interfaces**. Remove GUI discovery state and
per-tab bank loading once the worker path covers load, edit, save, reload, and
replacement.

### 4. Keep MainWindow as a thin composition root

Construct `WorkspaceUi` first or expose its shell immediately. Construct the
non-blocking `ProjectWorkspace`, retain `AudioEngine`, and wire the three
direct publication connections. Remove project-state and routine data relay
from `MainWindow`; retain only composition, selection-to-audio helpers, and
shutdown ordering.

### 5. Make ProjectWorkspace project-wide only

Move project selection, copied project state, and project-open state into
`ProjectWorkspace`. Expose only `openProject(OpenProjectInput)` and
`submit(ProjectOperation)`; keep worker stage tags and filesystem sequencing
behind that semantic seam. At application startup it independently reads
`SavedWorkspaceRecipe`; it publishes `Loading`, submits exactly one open, and
on success writes the path and publishes `Ready` with the accepted snapshot.
After that successful startup open, it queues the normalized selected song
first, then the other saved labels in persisted order as ordinary keyed
`SongUpdate`s. There is no internal startup-name tracking collection.

`WorkspaceUi` owns the Open Project disablement policy: it remains disabled
while placeholders lack terminal song payloads or UI-submitted work is in
flight. `ProjectWorkspace::openProject()` refuses only while `Loading`.
Project-open failure publishes `Failed` with a present `ProjectState.error` and
leaves the prior snapshot intact. Loading ends at open success or failure,
before startup song updates complete.

### 6. Move tab policy to WorkspaceUi and SongTab
Make `WorkspaceUi` own tab selection and lifetime, its private
`VoicegroupViewCache`, and transient load tombstones. Make `SongTab` own its
document, timeline, paired view, local document dirty state, readiness,
presentation state, and its one `SongHistory` interface over the existing
`QUndoStack`. Keep keyed result matching, picker policy, placement, and
`VoicegroupViewCache` updates in `WorkspaceUi`. `SongTab` emits local intent
only and has no project-service or project-operation identity dependency.
Route bank history through `VoicegroupViewCache`; its pending transition,
origin lookup, global action gate, origin-close gate, confirmation, dirty,
branch, blank-slot, merge, and inert-crossing behavior is defined once by the
`Tab history and dirty state` and `WorkspaceUi shared-bank view coordinator`
contract under **Implementation-ready target interfaces**. Do not add a
worker-owned or per-identity history stack.

For an interactive project switch, use this exact sequence:

1. `WorkspaceUi` prompts dirty songs and prompts once per dirty
   `VoicegroupId`.
2. After confirmation it calls `openProject(OpenProjectInput)`; Open Project
   becomes disabled.
3. While `Loading`, the prior snapshot may remain and the existing tabs and
   `VoicegroupViewCache` state stay in place.
4. On failure, publish `Failed` and its present error; snapshot, tabs,
   `VoicegroupViewCache` state, and persisted project and song settings in
   `QSettings` are unchanged.
5. On `Ready`, `MainWindow` performs null-selection unload, then
   `WorkspaceUi` destroys the tabs, clears `VoicegroupViewCache`, and clears the
   old `lastOpenSongs` and `lastSongLabel` settings (or otherwise starts with
   zero tabs / a clean default). It clears transient load tombstones. It does
   not call `normalizeSavedRecipe()` or recreate placeholders from the previous
   project's recipe; it reconciles the new snapshot directly.

For application startup only, normalized saved songs then arrive as ordinary
keyed updates. No switch step uses a worker tab registry or a second undo or
identity stack.

If any loading tab closes outside an accepted project replacement,
`WorkspaceUi` records a transient tombstone for its `SongName`, refuses an
immediate reopen of that name, and drops staged publications until terminal
`VoicegroupBound` or `SongFailed`; the terminal publication erases the
tombstone. No request or incarnation counter is introduced.

### 7. Replace generic worker requests with typed operations

Replace the broad request bag and kind switches with the public
`ProjectOperation` variant and the private `ProjectCommand` and
`ProjectResult` variants. Keep public input types directly in
`ProjectCommand` whenever no worker enrichment is needed; retain only the
real load/read stage tags. An exhaustive visitor dispatches one command
at a time through `ProjectIo`, resolves catalog rows on the worker, and maps
private failures to keyed `SongFailed` or `ProjectMutationFailure` results.
`VoicegroupEditResult` provides total typed applied or confirmed-not-applied
edit completion (expected mismatches and validation no-ops use the latter);
`SidecarWriteResult` completes standalone cosmetic writes without a public
event, and `PreviewCleanupCompleted` completes successful preview cleanup the
same way. `SaveSongInput`, `SongSaved`, and `SongFailed` follow the
semantic-save contract under **Implementation-ready target interfaces**.
Remove cancellation and overlap machinery for actions disabled by
`WorkspaceUi`.

### 8. Cut GUI callers over by behavior

Move complete workflows in this order:

1. saved placeholders, project open, snapshot publication, and startup song
   updates;
2. song load/reload, ordered keyed application, and independent cosmetic
   sidecar persistence;
3. semantic song save through `SaveSongInput`, `SongSaved`, and `SongFailed`
   under the semantic-save contract in **Implementation-ready target
   interfaces**;
4. voicegroup load, edit, confirmed undo/redo, and shared-view replacement;
5. create, register, delete, previews, catalog, and samples.

For each workflow, migrate input, result, failure, and placement behavior
together. `WorkspaceUi` captures `SaveSongInput`, applies any independent
keyed `LoadedBankView`, and applies terminal `SongSaved` or `SongFailed` under
the semantic-save contract in **Implementation-ready target interfaces**; it
does not sequence filesystem stages or correlate stage callbacks. Delete old
`MainWindow` entry points when their behavior has moved; do not preserve
forwarding aliases.

### 9. Finish audio handoff and shutdown order

The selected `SongTab` takes its `VoicegroupLease` from
`VoicegroupViewCache`. `MainWindow` reads that selected tab directly, stops and
unloads or loads the engine as required,
applies mute/solo, and retains the lease in the declared order. Inactive tab
timeline and bank updates do not touch `AudioEngine`.

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
- Worker `DecompProject` contains canonical `LoadedBankEntry` records;
  `WorkspaceUi`'s private `VoicegroupViewCache` contains the published views.
- `ProjectWorkspace` exposes only `openProject(OpenProjectInput)` and
  `submit(ProjectOperation)`, owns `ProjectState` as declared under
  **Implementation-ready target interfaces** and its error invariant, and has
  no live-tab state, operation field, busy flag, or internal startup-name
  tracking collection.
- `WorkspaceUi` owns tabs, selection, placement, picker, its private
  `VoicegroupViewCache`, transient load tombstones, and Open Project
  disablement policy. The cache owns one optional pending transition and its
  origin-aware gates; `SongTab` owns local document state and one
  `SongHistory`; it remains passive toward project operations.
- `SongName` and `VoicegroupId` use validating factories, remain value-keyed,
  and are the only semantic identities. Every fan-out event uses its declared
  domain key, with only catalog-dialog events intentionally unkeyed.
- Worker execution resolves catalog rows from `DecompProject`; callers do not
  send cached `SongInfo` or `SongCfg` for load stages.
- `SaveSongInput`, `SongSaved`, and `SongFailed` follow the semantic-save
  contract under **Implementation-ready target interfaces**; `WorkspaceUi`
  applies its independent keyed `LoadedBankView` and terminal outcome.
- Bank replacement retains old leases through cold audio swaps, and worker
  mutable state never crosses the GUI boundary.

### Acceptance matrix

| Contract item | Observable acceptance |
| --- | --- |
| Canonical bank ownership | The worker record is `LoadedBankEntry`; `WorkspaceUi`'s private `VoicegroupViewCache` owns the published `LoadedBankView` views, and no other object is the canonical bank. |
| Pending bank transition ownership | `SongHistory::requestUndo()`/`requestRedo()` return `HistoryRequest` under their `canUndo()`/`canRedo()` preconditions (document requests return `DocumentHistoryApplied` after crossing; bank requests return the exact `VoicegroupEditInput` with the stack index fixed); `WorkspaceUi` requires `VoicegroupViewCache::begin()` to succeed before submission, and its `Kind` selects applied handling or `resolveBankUndoConflict()`/`resolveBankRedoConflict()` for conflicts, with initial conflicts and hard errors leaving history fixed and no parallel pending state. |
| Semantic save | `SaveSongInput` produces any independent keyed `LoadedBankView` and exactly one terminal `SongSaved` or `SongFailed` under the semantic-save contract in **Implementation-ready target interfaces**; verify its ordering, partial-write, sidecar, and no-rollback/retry outcomes there. |
| Independent sidecar | A standalone `SaveSidecarInput` persists cosmetic state on close/switch without becoming a caller-managed song-save stage; private `SidecarWriteResult` records success or error, produces no public event, and advances FIFO, while successful `CleanupPreviewInput` returns private `PreviewCleanupCompleted`, is consumed without public publication, and advances FIFO; semantic-save sidecar handling follows the contract above. |
| Private command/result totality | Every `ProjectCommand` alternative has a terminal private `ProjectResult`; `VoicegroupEditInput` dispatches directly to `DecompProject::applyVoicegroupEdit`, returning `std::optional<VoicegroupEditResult>`, expected mismatches and every validation no-op use `VoicegroupEditConflictResult`, and an edit hard error maps through private `CommandFailure` to keyed `VoicegroupMutationFailed`. |
| Loading and Open Project | Open state reaches `Ready` at snapshot publication, startup loads use keyed updates, and UI policy alone keeps Open Project disabled while placeholders or submitted work remain. |
| Event keys and failure sum | `LoadedBankView`, preview, sample, song-created, `VoicegroupEditApplied`, `VoicegroupEditConflict`, and each `ProjectMutationFailure` alternative route by domain key; only catalog-dialog events and `CatalogMutationFailed` are unkeyed. |
| Song failures | `SongPayload` has one simple `SongFailed` with `SongStage`; sidecar absence is a nonfailure stage and project-open errors stay in optional `ProjectState.error`. |
| Shared-bank confirmation and blank slots | `VoicegroupViewCache` routes initial, undo, and redo through the unique origin `SongHistory`; applied/conflict/hard-error and blank-token behavior is verified against the canonical contract in **Implementation-ready target interfaces**, with hard errors leaving history fixed. |
| Worker catalog resolution | Load stage commands carry only `SongName`/`VoicegroupId` and user inputs; worker execution resolves `SongInfo`, `SongCfg`, constants, players, and track budget from `DecompProject`. |
| Close/reopen tombstone | `WorkspaceUi` keeps a transient `QSet<SongName>` only for a closed loading tab with in-flight work, refuses reopen of the same name, drops staged publications, erases the tombstone only at terminal `VoicegroupBound` or `SongFailed`, and accepted project replacement clears tombstones. |
| Direct audio seam | `MainWindow` reads the selected `SongTab` directly, retains the lease across borrowed-bank calls, and `AudioPresentationState` plus audition payloads remain without a selected-audio aggregate. |
| Validating identities and error | `SongName` rejects empty construction; `VoicegroupId` normalizes and validates project-relative paths; equality and `qHash` remain value-based; `ProjectState.error` is absent except in `Failed`. |
| Interactive switching | Dirty prompts, failure preservation, Ready teardown, null-selection unload, `VoicegroupViewCache` clearing, settings clearing, and clean-default start without previous-project placeholder recreation follow Phase 6. |
| Sole declaration site | Full types occur only in **Implementation-ready target interfaces**; other sections refer to them by name and do not redeclare fields or rules, including `DocumentStateIdentity` and `SongSaveSnapshot`. |
| Forbidden scans | Structural scans confirm the removed selected-audio aggregate, availability result, cached catalog rows in load commands, broad slot surface, one-to-one command wrappers, optional-key failure bag, duplicate saved-bank field, GUI filesystem-stage sequence, request/incarnation identity, documentation split, mutable const-removal cast, and worker-owned undo stack do not appear. |

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
- `VoicegroupViewCache` may choose private implementation details, and the
  declared audio values may travel in one or several focused signals.
  Ownership, fields, selection routing, and call order are fixed.
- `SampleEditorDialog` may keep a bounded application-level engine borrow or
  emit copied audition values. It must not own the engine or project state.

The plan must not answer these by adding a tab registry to
`ProjectWorkspace`, exposing `DecompProject`, transferring `AudioEngine`
ownership, or making `MainWindow` a project-data relay.

## Design test

- worker scheduling can change behind private `ProjectIo`;
- project discovery and canonical bank coordination can change inside worker
  `DecompProject`;
- startup placeholder persistence can change inside `WorkspaceUi`, while
  project open and keyed publication can change inside `ProjectWorkspace`;
- tab layout and lifetime can change inside `WorkspaceUi` and `SongTab`;
- audio binding can change inside `MainWindow` and `AudioEngine` wiring;
- GUI callers continue to use semantic operations, copied state, and safe
  handles.
- `SaveSongInput`, `SongSaved`, and `SongFailed` behavior can change inside
  `ProjectIo` under the semantic-save contract in **Implementation-ready target
  interfaces**, while `WorkspaceUi` continues to apply the independent keyed
  bank-view event and one terminal outcome;
- history confirmation can change inside `SongHistory` and its view-cache
  helper without adding a worker or per-identity stack.

If a change requires GUI code to know the worker queue, the worker to know a
tab, the workspace to own audio, or audio to hold a raw owning pointer, the
boundary is wrong.

