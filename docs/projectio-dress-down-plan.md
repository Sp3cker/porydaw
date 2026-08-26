# ProjectIo Dress-Down Plan

## Status

Design direction only. This document is not yet detailed enough to hand implementation waves to medium-reasoning agents. The ownership model and refactoring sequence are settled enough to guide further planning, but the wrapper name, exact interface, tab identity model, command representation, and migration call sites still need to be pinned against the live code.

## Goal

Reduce `ProjectIo` to a boring private module for worker-thread scheduling, cooperative cancellation, shutdown, and result delivery.

Move project and tab I/O orchestration into a deep wrapper module that:

- owns semantic operation policy;
- owns the `LoadedVoiceGroup` resources for loaded tabs;
- owns per-tab request state and staleness checks;
- owns project-generation state;
- sequences multi-step project operations;
- exposes semantic operations instead of worker-thread mechanics.

`WorkspaceUi` separately owns and drives widgets. Neither `WorkspaceUi` nor `MainWindow` owns filesystem scheduling mechanics.

## Target Ownership Model

```text
MainWindow
  ├── WorkspaceUi
  │     └── owns and drives widgets
  │
  └── ProjectRuntime                 working name only
        ├── project generation/state
        ├── per-tab resources
        │     ├── LoadedVoiceGroup
        │     ├── VoicegroupSource
        │     └── pending operations
        ├── cancellation/staleness policy
        ├── multi-step operation sequencing
        └── ProjectIo                private implementation
              ├── worker thread
              ├── FIFO scheduling
              ├── cooperative cancellation
              ├── shutdown/result delivery
              └── filesystem operation implementations
```

`AudioEngine`, `WorkspaceUi`, and other GUI code receive non-owning borrows of loaded resources. The wrapper retains ownership and detaches borrowers before replacement or destruction.

## Design Constraints

1. The wrapper must be a deep module. It must not mirror all current `ProjectIo` methods as forwarding functions.
2. `ProjectIo` becomes private to the wrapper. GUI modules do not receive a `ProjectIo &`, raw request IDs, or worker-thread state.
3. `WorkspaceUi` owns widget creation, attachment, presentation, and interaction driving. The project wrapper must not manipulate widgets.
4. `SongDocument`, undo stacks, widget state, and audio binding remain GUI-thread state.
5. `DecompProject` and filesystem parsing remain worker-thread state.
6. `LoadedVoiceGroup` and `LoadedSampleSet` use explicit single-owner RAII types. Raw owning pointers do not cross the seam.
7. Preserve the existing project-I/O plan’s visible partial-failure and retry behavior unless a separate decision explicitly changes it. Dressing down the implementation does not silently introduce transactional semantics.
8. Do not split files solely to satisfy a line target. Split at real ownership seams: queue mechanism, song operations, voicegroup operations, and sample operations.
9. Keep `src/` top-level unchanged. New production files belong under a cohesive feature directory such as `src/project/runtime/` or another settled project-owned location.
10. Do not introduce a virtual interface or adapter seam unless a second real adapter is required.

## Problems to Remove

### Oversized public interface

`ProjectIo` currently exposes roughly 22 operation methods plus request IDs, completion shapes, cancellation rules, and manually owned result resources. Callers must understand too much worker-thread machinery.

### Untyped request storage

The current `Request` contains a `RequestKind`, storage for every operation payload, storage for every completion type, and a cancellation flag. Most fields are inactive for any particular request.

### Parallel registries

Adding an operation requires coordinated changes to the request enum, request fields, worker result variant, public enqueue method, dispatcher, result delivery, completion cleanup, and resource-discard handling.

### Scattered lifecycle policy

Latest-wins behavior, disposable reads, non-disposable mutations, tab-close cancellation, project-switch cancellation, and stale-result rejection are encoded across call sites instead of one policy owner.

### Raw C-resource ownership

`LoadedVoiceGroup *` and `LoadedSampleSet *` require operation-specific cleanup on cancellation, stale completion, shutdown, tab close, and replacement.

### Repeated project identity

Project-relative operations repeatedly carry and compare root strings. Project identity and filesystem path are conflated.

### Overgrown implementation file

Thread scheduling, Qt delivery, project state, song persistence, voicegroup loading, samples, sidecars, registration, and deletion all live in one implementation module despite independent reasons to change.

### Duplicated check machinery

Multiple harnesses independently implement asynchronous polling, timeout, session-readiness, project-open, and save-completion loops.

## Intended Wrapper Interface

The exact names and parameters remain open. The wrapper interface should be semantic and small, along the lines of:

```cpp
openProject(...);
openTab(TabId, SongInfo);
closeTab(TabId);
saveTab(TabId, SaveInput);
refreshVoicegroup(TabId);
```

These examples are not implementation instructions. Further planning must determine:

- whether results arrive through callbacks, signals, or a combination;
- which operations need explicit completion at the caller;
- how `MainWindow` observes project/tab state changes;
- how `WorkspaceUi` receives presentation-ready state;
- which operations are wrapper-internal consequences of another operation.

The wrapper must absorb:

- request identity;
- tab liveness;
- cancellation;
- project-generation validation;
- operation classification;
- voicegroup ownership and replacement;
- stale-result disposal;
- save sequencing;
- catalog invalidation;
- sibling-tab refresh policy.

## ProjectIo End State

Conceptually, the dressed-down module should approach:

```cpp
class ProjectIo final {
  public:
    RequestHandle submit(Command command);
    void cancel(RequestHandle handle);
    void shutdown();
};
```

This is a target for conceptual size, not a committed C++ interface. `ProjectIo` should own only:

- worker construction and destruction;
- FIFO scheduling;
- one in-flight command;
- cooperative cancellation;
- worker dispatch;
- facade-thread result delivery;
- shutdown and draining.

Semantic policies belong to the wrapper. Filesystem behavior belongs to private operation implementations.

## Refactoring Work

### 1. Add RAII resource types

Define owned value types for Porya resources:

```cpp
struct VoicegroupDeleter {
    void operator()(LoadedVoiceGroup *) const;
};

using OwnedVoicegroup =
    std::unique_ptr<LoadedVoiceGroup, VoicegroupDeleter>;
```

Add the equivalent type for `LoadedSampleSet`.

Requirements:

- destruction occurs on the required facade/wrapper thread;
- cancellation and stale-result disposal use normal destruction;
- shutdown drains results on the correct thread;
- no completion handler calls `voicegroup_free` directly;
- the wrapper owns accepted tab resources;
- audio and UI borrowers are detached before replacement.

### 2. Add stable identity types

Introduce explicit internal types for:

- `TabId`;
- `ProjectGeneration`;
- `RequestHandle`.

A naked `uint64_t` must not represent all three concepts.

Per-tab asynchronous work moves into wrapper-owned state:

```cpp
struct TabOperations {
    RequestHandle songLoad;
    RequestHandle voicegroupLoad;
    RequestHandle voicegroupProbe;
    RequestHandle save;
    RequestHandle preview;
};
```

The exact fields must be derived from the final operation model rather than copied mechanically from `SongSession`.

### 3. Make ProjectIo private to the wrapper

Migrate all direct callers. After cutover:

- `MainWindow` has no `m_pending*Request` fields;
- `SongSession` has no worker request IDs;
- GUI code does not call `ProjectIo::cancel`;
- GUI code does not compare request IDs or project roots;
- GUI code does not free rejected worker resources.

Do not retain compatibility aliases or forwarding paths.

### 4. Centralize semantic policy

The wrapper owns operation classification, for example:

```cpp
enum class OperationClass {
    DisposableRead,
    TabLoad,
    ProjectMutation,
};
```

This is an internal model, not necessarily a public enum.

Centralize:

- whether an operation may start;
- which operations a project switch cancels;
- which operations tab close cancels;
- which mutations must remain FIFO;
- latest-wins project-open policy;
- stale-result acceptance.

`ProjectIo` itself only knows that a handle was cancelled.

### 5. Replace the request bag with typed commands

Use one active payload:

```cpp
using Command = std::variant<
    OpenProjectCommand,
    LoadSongCommand,
    LoadVoicegroupCommand,
    SaveDocumentCommand,
    ReadSidecarCommand
    // ...
>;

struct PendingCommand {
    RequestHandle handle;
    Command command;
    bool cancelled = false;
};
```

Each command owns only its own input and completion contract. Avoid a heap-allocated command hierarchy when a value variant provides the same seam without avoidable allocation.

### 6. Replace manual dispatch with visitation

Use one dispatch path and worker overloads. Remove the 22-arm invocation switch and repeated enqueue boilerplate.

Adding an operation should require only:

1. its command/result type;
2. its worker execution overload;
3. its wrapper-level use.

It must not require edits to multiple parallel cleanup and dispatch registries.

### 7. Move request identity into one result envelope

Remove `requestId` from every domain result. Use transport metadata once:

```cpp
struct CompletedCommand {
    RequestHandle handle;
    Result result;
};
```

Song, sidecar, voicegroup, and sample results then contain only domain information.

### 8. Centralize result acceptance

The wrapper has one acceptance path based on:

- stable tab identity;
- request handle;
- project generation;
- operation-specific revision when necessary.

No raw `SongSession *` crosses an asynchronous gap. No completion performs an `O(n)` scan to rediscover whether a captured pointer is alive.

The flow becomes:

```text
ProjectIo result
    → wrapper validates handle/generation/revision
        → wrapper updates owned project/tab resources
            → wrapper emits a semantic state change
```

### 9. Make project generation implicit

Opening a project installs a worker-side project generation. Project-relative commands target that generation rather than carrying and repeatedly comparing project-root strings.

Explicit external import paths remain paths. Project identity is not represented by a path string.

### 10. Consolidate multi-stage filesystem workflows

Move ordering into coarse worker commands where the stages form one user operation. Candidates include:

- session save;
- sample commit plus sidecar update/removal;
- song creation plus optional voicegroup and registration;
- deletion plus plan re-derivation;
- preview creation, load, and cleanup.

A coarse save command can preserve visible partial failures:

```cpp
struct SaveDocumentResult {
    SaveStage completedThrough;
    bool voicegroupWritten;
    bool midiWritten;
    bool flagsWritten;
    QString error;
};
```

Do not claim atomicity unless the product contract is explicitly changed. The immediate objective is to keep ordering and partial-failure publication out of GUI callbacks.

### 11. Split private operation implementations by ownership

Candidate structure:

```text
src/project/runtime/
  projectruntime.{h,cpp}        wrapper and external seam
  projectio.{h,cpp}             private queue/thread mechanism
  projectoperations.cpp        open/refresh state
  songoperations.cpp           load/save/create/delete
  voicegroupoperations.cpp     load/save/preview/catalog
  sampleoperations.cpp         probe/read/commit
```

The final directory and file names remain open. The ownership boundaries are the important part.

These operation implementations remain private. Do not create four new public modules.

### 12. Assert thread affinity once

Assert worker-thread affinity at the worker dispatch gateway. Assert facade-thread result delivery and resource disposal at the corresponding gateway.

Remove repeated per-operation “did not run on project thread” branches once the gateway makes the invariant structural.

### 13. Reduce header coupling

The scheduling header must stop exposing its implementation vocabulary.

Move operation-specific command/result types to private headers or their owning implementation modules. Remove worker-only dependencies such as the Porya loader C header from the external seam. Forward-declare where appropriate.

### 14. Simplify completion and disposal

Converge worker return onto one owned-result path:

```text
worker executes command
    → posts one owned result envelope to facade
        → facade completes or drops it
```

RAII handles dropped resource results. Eliminate operation-specific completion clearing and resource-discard switches.

Do not replace the existing result queue merely for aesthetics. Preserve it if Qt metatype or shutdown constraints require it; simplify its ownership and completion model instead.

### 15. Separate mechanism tests from wrapper contract tests

`projectiocheck` should eventually cover only the scheduling module’s interface:

- worker-thread execution;
- facade-thread completion;
- FIFO ordering;
- cooperative cancellation;
- one-time disposal of cancelled owned results;
- shutdown draining;
- stale generation suppression.

Wrapper checks cover:

- tab-close cancellation;
- project-switch rejection of old results;
- tab voicegroup lifetime;
- audio borrower detachment before replacement;
- preview replacement;
- save sequencing and partial failures;
- catalog and sibling-tab refresh consequences.

Create one shared asynchronous check helper under `src/checks/support/` rather than duplicating event-loop polling in each harness.

### 16. Remove DecompProject’s duplicate track-budget source

Choose one canonical owner for track budgets. Do not retain both `m_players` and `m_trackBudgets` as path-dependent sources of truth.

This is adjacent to, but independently implementable from, the queue simplification.

## Implementation Waves

The waves below describe dependency order and appropriate agent types. They are not yet one-shot assignments; each must be expanded with exact symbols, call sites, and check contracts before dispatch.

### Wave 0 — Pin the external seam

**Subagent type:** Spawn `explorer` subagents for code mapping, then use a `task` subagent for slice-local design. Use a dedicated `reviewer` subagent to challenge the resulting interface.

Decide and document:

- wrapper name and directory;
- stable tab identity owner;
- wrapper interface and result-notification mechanism;
- relationship to `SongSession`;
- relationship to `WorkspaceUi`;
- relationship to `AudioEngine`;
- project-generation lifecycle;
- save partial-failure contract;
- resource destruction thread.

**Exit criterion:** every external method, result, owner, and call site is pinned. No implementation begins before this exit criterion.

### Wave 1 — RAII and identity foundation

**Subagent type:** Dispatch independent C++ implementation slices to parallel `task` subagents. Use `qt-cpp-reviewer` for the Qt thread-affinity and ownership review.

Implement:

- owned voicegroup/sample-set types;
- typed request handle;
- stable tab identity;
- project generation;
- focused ownership checks.

**Exit criterion:** no newly migrated path exposes a raw owning C pointer or naked cross-layer request ID.

### Wave 2 — Introduce wrapper ownership

**Subagent type:** Use a `task` subagent for the wrapper and a separate `task` subagent for per-tab resource migration. Use `qt-cpp-reviewer` after integration.

Move:

- per-tab loaded voicegroups;
- per-tab sources;
- per-tab request state;
- acceptance and staleness policy;
- project-operation policy.

Keep behavior unchanged. `WorkspaceUi` continues to own widget driving.

**Exit criterion:** `MainWindow` and `SongSession` no longer own worker request IDs or loaded voicegroups.

### Wave 3 — Cut callers over to the deep interface

**Subagent type:** Dispatch independent caller groups to parallel `task` subagents; use `sonic` only for strictly mechanical include/call-site updates after interfaces are fixed. Use a dedicated `reviewer` for clean-cutover verification.

Migrate all direct `ProjectIo` callers and delete obsolete paths. Do not leave aliases, forwarding compatibility methods, or dual ownership.

**Exit criterion:** only the wrapper can construct or call `ProjectIo`.

### Wave 4 — Replace the queue type model

**Subagent type:** Use a C++ `task` subagent with the typed command/result contract pinned in its assignment. Use `cpp-smell-reviewer` and `qt-cpp-reviewer` after implementation.

Replace:

- `RequestKind` plus bag fields;
- completion bag;
- manual dispatch switch;
- per-kind clear/discard logic;
- repeated thread checks.

**Exit criterion:** one generic dispatch path and one generic completion/disposal path remain.

### Wave 5 — Deepen filesystem operations

**Subagent type:** Dispatch song, voicegroup, and sample operation ownership to parallel C++ `task` subagents after the shared command contract is fixed. Assign one integration-owner `task` subagent for shared queue mutations. Use `reviewer` for architecture verification.

Consolidate multi-stage commands and move private operation implementations into cohesive files.

**Exit criterion:** GUI callbacks do not sequence filesystem stages, and `projectio.cpp` contains scheduling rather than every filesystem concern.

### Wave 6 — Check consolidation and cleanup

**Subagent type:** Use `sonic` for mechanical wait-helper migrations after one `task` subagent implements the canonical helper. Use `reviewer` for contract coverage and `thermo-nuclear-reviewer` for final maintainability review.

Implement shared asynchronous check helpers, migrate harnesses, delete obsolete scaffolding, and verify no old interface remains.

**Exit criterion:** mechanism checks and wrapper-contract checks are clearly separated, and the thermo-nuclear review no longer identifies `MainWindow` or `ProjectIo` as god modules.

## Verification Expectations

Each implementation wave must define focused checks before execution. At final integration, verification must include:

- `deno task build:checks`;
- project-I/O mechanism checks;
- tab open/close and project-switch checks;
- voicegroup save and replacement checks;
- sample probe/read/commit checks;
- shutdown with queued and in-flight owned results;
- main-window routing checks;
- formatter verification for touched files;
- strict Qt/C++ ownership review;
- thermo-nuclear maintainability review.

## Open Decisions Before Implementation Planning

1. What is the wrapper’s domain name: `ProjectRuntime`, `ProjectWorkspace`, `ProjectSessions`, or another established term?
2. Does the wrapper own `SongSession`, or does it own only the asynchronous resources associated with a stable `TabId`?
3. Does `WorkspaceUi` map `TabId` to `SongView`, or does another owner maintain that association?
4. How does the wrapper publish state changes without becoming coupled to widgets?
5. Does `AudioEngine` borrow directly from the wrapper, or does `MainWindow` remain the binding coordinator?
6. Must `voicegroup_free` and sample-set destruction run on the GUI thread, the wrapper facade thread, or merely the same thread as audio detachment?
7. Which current `ProjectIo` operations combine into coarse commands, and which remain independent because their results must arrive separately?
8. Does a session save preserve the current visible partial-write contract exactly, or is transactional behavior a separate desired change?
9. Is a single FIFO worker retained despite long `voicegroup_load` head-of-line blocking, or will measurement justify a separate execution lane?
10. Can the existing mutex-protected result queue be reduced safely with Qt queued invocations while preserving shutdown guarantees?
11. Which `DecompProject` representation becomes the canonical track-budget source?
12. Which existing checks defend ownership and cancellation behavior, and what observable contracts are still uncovered?

## Design Test

Imagine deleting the wrapper.

If request identity, tab liveness, project-generation validation, cancellation, loaded-resource ownership, save sequencing, and stale-result disposal would reappear across `MainWindow`, `SongSession`, widgets, and checks, the wrapper is earning its keep as a deep module.

If deleting it would merely replace calls with the equivalent `ProjectIo` calls, the wrapper is shallow and must be redesigned before implementation.
