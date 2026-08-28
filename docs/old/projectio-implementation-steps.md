# DecompProject / Project-I/O — Implementation Steps

Executable breakdown of `projectio-dress-down-plan.md`. The sole type and
ownership contract is
[`projectio-dress-down-contract.md`](projectio-dress-down-contract.md)
("the contract"). This file is the dispatch board; it declares no types,
fields, or rules of its own.

## Rules for every step

- **Contract-pinned.** Implement only what the contract declares. No design
  decisions at implementation time; transcribe the fixed contract.
- **Compile-gated.** C++20 + Qt6, exhaustive variant visitors. A step that
  adds an operation without handling it everywhere does not compile — that
  failure is the step boundary doing its job.
- **Acceptance-verified.** A step is done when its acceptance-matrix rows
  (plan §Verification strategy) observably pass, not when code exists.
- **Verification ownership.** Only the integration owner runs
  `deno task verify`. Slice agents skip project-wide validation, formatters,
  and linters; the integrator runs them once per integration point.

## Subagent roles

- `task` — general multi-step implementation and orchestration.
- `sonic` — fast, mechanical, low-reasoning edits and repetitive rewrites.
- `reviewer` — quality/security/architecture verification at review gates.
- `scout` — read-only reconnaissance when a target's surface is unknown.

## Execution graph

```
1.1 ─┐
     ├─► P3 (3.1 → 3.2 → 3.3) ─► P4/5 ─► P6a ─┐
2.1 ─┤                                        ├─► P7 ─► 8.1 → 8.2 → 8.3 → 8.4 → 8.5 ─► P9
2.2 ─┤                                  P6b ──┘            [R gate after 8.1]
2.3 ─┘                                  P6c ──┘                              [R gate after 8.5]

Review gates: after P2/P3, after 8.1, after 8.5.
```

Phases 1 and 2 run concurrently (disjoint files: `src/audio` vs `src/core` +
settings readers). Phases 4 and 5 co-deliver as a single step. Phase 8 is a
strict sequence; parallelism lives *inside* each workflow (see step 8.x
slices).

---

## Phase 1 — Audio const borrows  ·parallel with Phase 2·

### Step 1.1 [task]
- **Target:** `src/audio/audioengine.*` (`loadSong`, `updateVoicegroup`,
  every borrowed-bank entry point); worker bank production; session/tab bank
  destruction. Non-goal: engine DSP internals.
- **Contract:** `### Audio binding values`; lease/lifetime rules under
  `### Voicegroup resource and bank ownership`; ownership checklist row
  "Bank replacement retains old leases…".
- **Change:** use the small `VoicegroupLease` wrapper at every borrowed-bank
  API. Its public surface exposes only a const bank; `AudioEngine` alone uses
  its private legacy mutable borrow to call unchanged poryaaaa, without a cast
  or bank copy. Wrap each successful worker-owned bank exactly once; keep old
  and new leases alive around a cold engine swap, releasing only after audio
  unload or rebind returns. Remove raw GUI/session destruction of banks.
- **Acceptance:** acceptance rows *Direct audio seam*, *Canonical bank
  ownership*; no `const_cast`; engine builds and the audio path unchanged
  behaviorally. No project-wide verify.

---

## Phase 2 — Identities, saved-recipe normalization, dirty adoption  ·parallel with Phase 1·

### Step 2.1 [task]
- **Target:** new `SongName`, `VoicegroupId` validating types (`src/project`
  or `src/core` per convention). Non-goal: any call-site migration beyond
  compile necessity.
- **Contract:** `### Stable identities`.
- **Change:** validating factories (`create` returns `std::optional`;
  `SongName` rejects empty; `VoicegroupId` normalizes + validates a
  non-empty project-relative path, rejecting absolute/escaping, retaining
  `sectionLabel`); value equality and `qHash`; no public invalid-state
  constructor.
- **Acceptance:** acceptance row *Validating identities and error*
  (factory/equality/hash portion).

### Step 2.2 [task]
- **Target:** `normalizeSavedRecipe` pure function + both settings readers
  (WorkspaceUi shell-construction read; ProjectWorkspace startup read).
- **Contract:** `### Saved startup recipe`.
- **Change:** implement the pure function exactly as declared — discard
  empty labels, keep first duplicate, preserve order; empty ordered list +
  non-empty selected ⇒ `[selected]` (pre-tabs generation, one tab);
  selection falls back to the first name when selected is empty, absent from
  the ordered list, or discarded. Centralize both readers on it at
  application startup only.
- **Acceptance:** acceptance row *Loading and Open Project* (startup-restore
  substrate: named placeholders reflect the normalized recipe); old-format
  session restores as one tab (sessioncheck block 4); both readers use the
  one function.

### Step 2.3 [task]
- **Target:** `DocumentStateIdentity`, `SongSaveSnapshot`,
  `SongDocument::didSave()`/dirty logic (`src/core`). Non-goal: bank
  transitions.
- **Contract:** `### Tab history and dirty state` (identity, snapshot,
  didSave, dirty-compare paragraphs).
- **Change:** introduce the opaque identity; `SongSaveSnapshot` carries the
  detached image + save-guard metadata; dirty compares current vs saved
  identity — never `QUndoStack` clean index, monotonic revision equality, or
  whole-document hash; `didSave()` retains `flagsNeeded`/`revision`/
  `saveStateToken` guards and calls `markDocumentSaved()` only while guards
  and captured identity match.
- **Acceptance:** acceptance row *Validating identities and error* (dirty
  portion); bank-only transitions do not dirty the document.

**Review gate [reviewer]** after P2 + P3: contract substrate correct before
dependents build on it.

---

## Phase 3 — Extend DecompProject on the worker  ·single thread·

### Step 3.1 [task]
- **Target:** worker-side `DecompProject` (`src/project/decompproject.*`);
  `LoadedBankEntry` records.
- **Contract:** `### Voicegroup resource and bank ownership`
  (`LoadedBankEntry`, publication rules); §DecompProject responsibilities.
- **Change:** place the canonical `VoicegroupId → LoadedBankEntry` map beside
  the project catalog; `loadBank` reuses an unchanged entry when identity and
  source timestamp permit; build complete candidates, replace the current
  lease only on success; publish `LoadedBankView` copies — the entry never
  crosses the seam.
- **Acceptance:** acceptance row *Canonical bank ownership*.

### Step 3.2 [task]
- **Target:** `DecompProject::applyVoicegroupEdit`.
- **Contract:** `applyVoicegroupEdit` semantics under `### Voicegroup
  resource and bank ownership` (applied / confirmed-conflict / hard-error =
  nullopt; blank-slot materialize/revert tokens; worker is the only
  validator).
- **Change:** return `std::optional<VoicegroupEditResult>`; a present value is
  applied (complete candidate replaces `current`) or confirmed-conflict
  (typed not-applied for expected mismatch / every validation no-op, leaves
  `current` untouched); hard error returns `nullopt` + message, old entry
  untouched; blank set/materialize uses `materializeBlankSlot`, revert uses
  the supplied token with `revertBlankSlotMaterialization`; structural vs
  scalar derived from the source, no GUI mode flag.
- **Acceptance:** acceptance rows *Private command/result totality*,
  *Shared-bank confirmation and blank slots* (worker half).

### Step 3.3 [task]
- **Target:** `DecompProject::saveVoicegroup` + semantic-save worker
  sequencing.
- **Contract:** semantic-save worker ordering under `SaveSongInput` in
  `### ProjectWorkspace semantic operations` (bank first, then MIDI/flags,
  cosmetic sidecar last; no transaction/rollback/retry/race guard); keyed
  `LoadedBankView` delivery while the command stays active.
- **Change:** optional voicegroup source + synth writes and required bank
  refresh first; then MIDI and flags; final cosmetic sidecar nonfatal;
  deliver the resulting `LoadedBankView` as soon as voicegroup save + refresh
  land.
- **Acceptance:** acceptance row *Semantic save* (worker ordering,
  partial-write, no-rollback outcomes).

---

## Phases 4+5 — ProjectWorkspace seam  ·co-delivered, single step·

### Step 4/5.1 [task]
- **Target:** new `src/project/projectworkspace.h/.cpp`; wiring in
  `src/mainwindow.*`. Non-goal: any workflow behavior (phase 8).
- **Contract:** `### ProjectWorkspace semantic operations` (the
  `openProject`/`submit` seam, the three publication signals); relocated
  `ProjectState` + refusal/disablement rule under `### Project publications`;
  §ProjectWorkspace responsibilities.
- **Change:** construct the non-blocking owner; expose only
  `openProject(OpenProjectInput)` and `submit(ProjectOperation)`; publish
  `projectStatePublished` / `projectEventPublished` / `songUpdatePublished`;
  `ProjectState` is exactly `{ state, snapshot, catalog, error }` with the
  `Failed`-only error invariant; `openProject()` refuses only while
  `Loading`; a successful startup open writes the path and publishes `Ready`,
  then queues normalized selected-first-then-rest as ordinary keyed updates.
  MainWindow wires the three streams directly to WorkspaceUi — no relay.
- **Acceptance:** acceptance rows *Loading and Open Project*, *Event keys and
  failure sum* (publication shape). Shell + placeholders render before
  project work completes.

---

## Phase 6 — Tab policy to WorkspaceUi / SongTab  ·three slices + integration owner·

Slices 6a and 6b create disjoint new files (`songtab.*`, `workspaceui.*`) and
run in parallel; 6c touches `WorkspaceUi` and `MainWindow`, so it lands after
6a/6b merge. The **integration owner** merges 6a/6b, then applies 6c,
serializing `workspaceui.*` and the `MainWindow` unload hook, and runs
`deno task verify`. Slice agents skip project-wide validation.

### Step 6a [task]
- **Target:** new `src/ui/songtab.h/.cpp`; document/timeline/view ownership.
- **Contract:** §SongTab responsibilities; `### Tab history and dirty state`
  (`SongHistory` interface).
- **Change:** `SongTab` owns its `SongDocument`, `MidiTimeline`, permanently
  paired `SongView`, and one `SongHistory` over exactly its existing
  `QUndoStack`; passive toward project operations (never calls
  `ProjectWorkspace`/`ProjectIo`, starts no load/save, owns no operation
  identity); emits local intent only.
- **Acceptance:** acceptance row *Pending bank transition ownership*
  (`SongHistory` honors `canUndo`/`canRedo` preconditions and returns the
  `HistoryRequest` contract values); `SongTab` holds no project-service
  dependency.

### Step 6b [task]
- **Target:** new `src/ui/workspaceui.h/.cpp`;
  `VoicegroupViewCache`; transient tombstones.
- **Contract:** `### WorkspaceUi shared-bank view coordinator`
  (`PendingBankTransition`, the resolve methods, both gates); §WorkspaceUi
  responsibilities; tombstone rules.
- **Change:** `WorkspaceUi` owns tab selection/lifetime, the private
  `VoicegroupViewCache`, and transient `QSet<SongName>` tombstones; the cache
  holds one optional pending transition (never a per-identity map);
  `begin()` before submission; `applyView()` before `resolveApplied()`;
  `bankActionsEnabled()` and origin-aware `closeEnabledFor()`.
- **Acceptance:** acceptance rows *Pending bank transition ownership*,
  *Close/reopen tombstone*.

### Step 6c [sonic]
- **Target:** interactive project-switch sequence in `WorkspaceUi` +
  MainWindow unload hook.
- **Contract:** the exact 5-step switch sequence under plan phase 6.
- **Change:** implement the fixed sequence verbatim (dirty prompts →
  `openProject` → prior state stays during `Loading` → failure preserves /
  `Ready` tears down, null-unloads, clears cache + settings, clean default,
  no previous-project placeholder recreation).
- **Acceptance:** acceptance row *Interactive switching*.

---

## Phase 7 — Typed operations  ·single thread·

### Step 7.1 [task]
- **Target:** `src/project/projectio.h/.cpp` (private thread, queue,
  transport, command/result variants); visitor dispatch.
- **Contract:** `### Private ProjectIo command/result interface`
  (variants, one-active-FIFO, totality, `CommandFailure` mapping incl. the
  keyless-operation rule); §Request and result model.
- **Change:** `ProjectOperation` (public inputs only) / `ProjectCommand` /
  `ProjectResult` variants; exhaustive visitor, one active FIFO command, one
  private result callback; hard worker errors → private `CommandFailure` →
  keyed `SongFailed` / keyed `ProjectMutationFailure` / `ProjectState.error`
  for open; keyless operations (`OpenProjectInput`, `RefreshProjectInput`,
  `CleanupPreviewInput`, `SaveSidecarInput`) consume failures per their fixed
  per-operation mapping; remove cancellation/overlap machinery.
- **Acceptance:** acceptance rows *Private command/result totality*, *Event
  keys and failure sum*, *Independent sidecar*.

---

## Phase 8 — Cut GUI callers over  ·strict sequence 8.1 → 8.5·

Each workflow runs as **4 parallel slices + one integration owner**:
`[task]` worker helper · `[task]` ProjectWorkspace wiring · `[task]`
WorkspaceUi/SongTab apply path · `[sonic]` harness-body rewire for that
workflow's checks. The integrator alone serializes `workspaceui.h/.cpp` and
the old-entry deletion in `mainwindow.cpp`, then runs `deno task verify`.
The typed contract is fixed before the phase begins; the exhaustive visitor
turns cross-slice drift into a compile error.

Per the plan, this is a hard dependency chain — each workflow establishes
substrate the next consumes. Do not start 8.(n+1) before 8.n integrates.

### Step 8.1 — open / startup placeholders  ·gates the rest·
- **Target:** project open, snapshot publication, startup song updates,
  placeholder lifecycle.
- **Contract:** §Startup session restoration; `### Project publications`;
  `SongUpdate` load staging under `### Song publications`.
- **Slices:** worker open+snapshot helper ∥ `openProject`/Ready wiring ∥
  WorkspaceUi placeholder create/select/apply ∥ sessioncheck/tabcheck
  startup-body rewire.
- **Acceptance:** *Loading and Open Project*; shell + placeholders render
  before work completes; old-format restore = one tab.

**Review gate [reviewer]** after 8.1: the seam is proven end-to-end. If it is
wrong here, stop — everything downstream reuses it.

### Step 8.2 — song load / reload / independent sidecar
- **Target:** `OpenSongInput`, `ReloadSongInput`, `SaveSidecarInput`; live
  voicegroup rebind through `ReloadSongInput::voicegroupArg`; ordered keyed
  application.
- **Contract:** `### Song publications` (MidiStage → SidecarStage →
  VoicegroupBound); independent-sidecar rules.
- **Slices:** load/reload/sidecar worker helpers ∥ command/result wiring ∥
  SongTab staged apply methods ∥ tabcheck/sessioncheck load-body rewire.
- **Acceptance:** *Song failures*, *Independent sidecar*; corrupt sidecar ⇒
  `loaded: false`, not a failure.

### Step 8.3 — semantic song save
- **Target:** `SaveSongInput` end-to-end; terminal `SongSaved`/`SongFailed`.
- **Contract:** semantic-save contract under `### ProjectWorkspace semantic
  operations` + `### Song publications`.
- **Slices:** save worker sequencing ∥ wiring ∥ WorkspaceUi capture +
  independent bank-event + terminal apply ∥ vgsavecheck body rewire.
- **Acceptance:** *Semantic save*; *Loading and Open Project* (save-in-flight
  close refusal).

### Step 8.4 — voicegroup load / edit / confirmed undo-redo / shared-view replacement
- **Target:** `VoicegroupEditInput`, keyed `LoadedBankView`,
  `VoicegroupEditApplied`/`Conflict`/`MutationFailed`.
- **Contract:** `### Tab history and dirty state` + `### WorkspaceUi
  shared-bank view coordinator` + edit/save flow.
- **Slices:** edit worker path ∥ keyed wiring ∥ cache transition + origin
  `SongHistory` routing ∥ tabcheck 10b rewire (now asserts shared-bank
  identity invariant, not clean-only-follow).
- **Acceptance:** *Pending bank transition ownership*, *Shared-bank
  confirmation and blank slots*.

### Step 8.5 — create / register / delete / previews / catalog / samples
- **Target:** the remaining `ProjectOperation` alternatives; largest surface.
  May sub-split by operation once 8.1–8.4 conventions exist.
- **Contract:** the operation structs and event alternatives under `###
  ProjectWorkspace semantic operations` / `### Project publications`.
- **Slices:** per-operation worker helpers ∥ wiring ∥ WorkspaceUi apply +
  catalog dialog ∥ onboardcheck (register/delete) + catalog harness rewires.
- **Acceptance:** *Event keys and failure sum*; remaining matrix rows.

**Review gate [reviewer]** after 8.5: full acceptance-matrix audit + the
*Forbidden scans* structural checks (no selected-audio aggregate, no
availability result, no cached catalog rows in load commands, no broad slot
surface, no one-to-one wrappers, no optional-key failure bag, no duplicate
saved-bank field, no GUI filesystem-stage sequence, no request/incarnation
identity, no mutation-failure alternatives outside the four declared, no
const-removal cast, no worker-owned undo stack).

---

## Phase 9 — Audio handoff and shutdown order

### Step 9.1 [task]
- **Target:** selected-tab lease handoff in `MainWindow`; shutdown ordering;
  inactive-tab isolation.
- **Contract:** `### Audio binding values` + §AudioEngine wiring (lifetime,
  selected-tab binding, timeline/transport/settings, audition/export,
  shutdown); plan phase 9.
- **Change:** the selected `SongTab` takes its `VoicegroupLease` from
  `VoicegroupViewCache`; `MainWindow` reads the selected tab directly, stops
  the old transport, unloads/loads with the borrowed bank, reapplies
  mute/solo, retains the lease; inactive-tab updates never touch
  `AudioEngine`; shutdown stops timers/audio → releases selected lease →
  destroys tabs/GUI leases → stops `ProjectIo` → finishes/discards the active
  result → destroys worker state → joins.
- **Acceptance:** acceptance row *Direct audio seam*; replacement,
  selected-tab switching, inactive-tab editing, audition, export, and
  shutdown all use the declared lease and publication boundaries.
