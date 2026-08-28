# Single Unified Project-I/O Thread Implementation Plan (Option A)

**Status:** Authoritative implementation and subagent execution plan.
**Living Decision Context:** [`PROJECT_THREAD_MINUTES.md`](../../PROJECT_THREAD_MINUTES.md)

---

## 1. Goal & Architecture (Option A)

### Primary Goal
Eliminate all project filesystem I/O, directory scans, file metadata probes, and disk-heavy parsing (including Porya `voicegroup_load` and MIDI SMF parsing) from Qt's GUI thread. All project disk interactions are executed serially on a single dedicated background worker thread owned by `ProjectIo`.

### Core User Constraints

1. **Immediate Song Presentation**: Opening or switching a song immediately creates and shows a `SongView` tab without waiting for MIDI parse or voicegroup load. The timeline/document bind when `loadSongFile` completes; the voicegroup binds when `loadVoicegroup` completes. Either completion may arrive first.
2. **Asynchronous Voicegroup Loading**: Voicegroup parsing and sample decoding (`voicegroup_load` and `VoicegroupSource` parsing) run on the background `ProjectIo` thread while the UI remains interactive.
3. **Zero Layout Shift**: The `VoicegroupBrowser` dock and `SongView` must never change dimensions, jump, jitter, or cause visual layout reflow when transitioning from the `"Loading..."` state to the loaded state.
4. **Thread Safety & C Ownership**: `LoadedVoiceGroup` and `LoadedSampleSet` pointers crossed across thread boundaries must have strict single-owner semantics with zero leaks, double-frees, or dangling engine borrowers.
5. **Smallest Safe Rewrite**: Keep production business logic (`SongRegistry`, `VoicegroupSource`, `SampleRegistrar`, `ViewSidecar`) intact behind the `ProjectIo` worker seam.

### Settled: Song-open sequence

empty roll first; MIDI and voicegroup both off the GUI thread.

1. GUI immediately `createSession()`, inserts the tab, and shows `SongView` with no SMF, no timeline, and no voicegroup (`setSong(nullptr, nullptr)`, `setDocument(nullptr)`). Do not call `SongDocument::load` or `voicegroup_load` on this thread.
2. GUI queues `ProjectIo::loadSongFile` and `ProjectIo::loadVoicegroup` for that session. Both run on the one serial worker. Completions are applied independently: MIDI may land before voicegroup or the reverse.
3. MIDI completion (GUI thread): adopt the parsed `SmfFile` into `SongDocument`, `buildTimeline`, then `setDocument` / `setSong(timeline, session.voicegroup)` (`voicegroup` may still be null).
4. Voicegroup completion (GUI thread): take ownership of `LoadedVoiceGroup*` + `VoicegroupSource`, store them on the session, bind `AudioEngine` if this session is active, `view->setVoicegroup(vg)`, `m_vgBrowser->setVoicegroup(vg)`.
5. The rest of the app stays interactive during both waits. Tab close cancels that session's in-flight requests.

Still open (later fills): injection reach; save payload; Wave 5 leftover I/O scope. Sidecar codec is settled: `ViewSidecar` (`src/ui/viewsidecar.{h,cpp}`) owns the JSON load/save; `Sidecar` (`src/project/sidecar.cpp`) owns only `.porydaw/` directory creation and the `.gitignore` entry.

### Settled: `ProjectIo` request queue

Rewrite the single `m_completion` / `m_generation` slot into a FIFO queue now, including `openProject`.

**Queue (lives on the `ProjectIo` facade thread, not the worker):**
- Each call enqueues one `Request { uint64_t id; kind; payload; completion; bool cancelled; }` and returns `id`.
- At most one request is in flight on the worker. When a result returns, dispose or deliver, then dispatch the next non-cancelled item.
- `cancel(id)` sets `cancelled` on that request. It does **not** abort a running `voicegroup_load` / `readFile`. The worker finishes; the facade drops the result.
- Dropping a `VoicegroupLoadResult` with a non-null `voicegroup` must `voicegroup_free` it on the facade thread before the result is destroyed.
- `openProject` keeps latest-wins **among opens only**: a new `openProject` `cancel`s every queued or in-flight `OpenProject` request, then enqueues. Existing `projectiocheck` superseded-open behavior stays. Loads never cancel each other or an open.

**Replace `void openProject` with `uint64_t openProject`.** `ProjectOpenResult` is unchanged. `Worker::prepareProject` / `commitProject` stay; pass `requestId` where they currently take `generation`. Commit only if that id is still the accepted (not cancelled) open.

**New methods and result types — copy these fields, do not invent others:**

```cpp
struct SongFileResult {
    uint64_t requestId = 0;
    SmfFile smf;
    QString error;
    bool succeeded() const { return error.isEmpty(); }
};

struct VoicegroupLoadResult {
    uint64_t requestId = 0;
    LoadedVoiceGroup *voicegroup = nullptr; // recipient owns; null on fail
    std::unique_ptr<VoicegroupSource> source;
    QString error;
    bool succeeded() const { return voicegroup != nullptr; }
};

uint64_t loadSongFile(SongInfo song, std::function<void(SongFileResult)>);
uint64_t loadVoicegroup(QString root, SongCfg cfg, std::function<void(VoicegroupLoadResult)>);
void cancel(uint64_t requestId);
```

- `loadSongFile` worker body: `SmfFile::readFile(song.midPath, &smf, &error)` only. No tempo normalize, no `SongDocument` mutation.
- `loadVoicegroup` worker body: `voicegroup_load` over `DecompProject::voicegroupCandidates(cfg)` (same loop as `MainWindow::loadVoicegroupFor`), then `VoicegroupSource::open(root, cfg.voicegroupArg, &error)`. If either step fails, `voicegroup_free` any allocated vg on the worker and return `{id, nullptr, {}, error}`. Success returns both pointers. This is one queued operation, not two.

**`SongDocument` adopt (GUI thread only):**

```cpp
bool adoptSmf(SmfFile smf, const SongInfo &song, QString *error);
```

Body is the current `load()` from `m_smf = std::move(smf)` onward (tempo normalize, strip tempo metas, undo clear, mint note ids, rebuild track map, `publishMutation`). `load()` becomes `readFile` + `adoptSmf` so remaining sync callers keep working until Wave 2 deletes them.

**`SongSession` fields to add in Wave 2 (not Wave 1):** `uint64_t pendingMidiRequest = 0; uint64_t pendingVgRequest = 0; bool midiBound = false; bool vgBound = false;`


### Settled: Load failure after the tab exists

Chosen 2026-08-24: tear the speculative tab down. Least new UI — reuse `destroySession` and the existing `QMessageBox` / restore-session status-bar warning.

- If `loadSongFile` or `loadVoicegroup` fails, show the same warning `loadSong` shows today, then `destroySession` the tab.
- Cancel the sibling in-flight request for that session.
- If the other result already bound, `~SongSession` frees it the way it does today (`setSong(nullptr, nullptr)` then `voicegroup_free`).
- A completion whose session is already destroyed is dropped. A `LoadedVoiceGroup*` inside a dropped result is `voicegroup_free`'d on the GUI thread. Never leak, never apply.


### Settled: Empty SongView contract

Chosen 2026-08-24: display-only until both MIDI and voicegroup have bound.

- Empty `SongView` is the widget `createSession()` already builds. No loading overlay widget. Do not hide or show the ruler, track-header column, piano roll, scrollbars, other strip, or editor drawer.
- Those widgets already sit in the constructor layout. MIDI/vg bind must not add or remove them or change the track-header column width (`layout::fontPx(17.5)`).
- `PianoRoll` paints `Loading...` centered while `m_timeline == nullptr`. No `QLabel`.
- Track header *rows* may appear inside the fixed-width header `QScrollArea` when the timeline binds. That is content, not a `SongView` size change.
- The first `setSong` may change camera/zoom (`rebuildAfterSongChange`). Allowed — same jump as today's synchronous load.
- `ViewSidecar::applyViewState` runs only after MIDI bind, still before the tab becomes interactive.
- Until **both** MIDI and voicegroup have bound: no note edit, track add, playback, save, or export. Tab close and tab switch stay enabled.

## 2. Ordering & Design Constraints (moved from PROJECT_THREAD_MINUTES.md)

These are the settled rules every wave must preserve. They are self-contained here so no other file is needed.

### Guiding constraint

**Smallest safe rewrite.** This is a performance change, not a broad architecture cleanup. Move disk work behind `ProjectIo` with the minimum safe seam; keep production business logic (`SongRegistry`, `VoicegroupSource`, `SampleRegistrar`, `ViewSidecar`) intact behind the worker. Do not refactor modules that are not broken.

### Ordering that must survive async migration

1. **Project switch order**: prompt/save old sessions and capture old view sidecars against the old root *before* the switch. A failed open must not destroy the current project/session state.
2. **Save order**: synth definitions → voicegroup source → voicegroup reload/mtime/sibling refresh → MIDI → cfg flags → GUI clean-state update. MIDI write first, flags rewrite second; mark the undo stack clean ONLY after both succeed. A flag failure leaves the new MIDI on disk and the session dirty for retry.
3. **Create order**: optional voicegroup → MIDI → flags → multi-file registration → pending metadata on registration failure → project refresh. Intentionally recoverable, not atomic.
4. **Delete order**: GUI detaches/destroys the song session and audio borrowers *first*; the worker then moves/removes/rewrites files; project state refresh follows all attempts.
5. **Preview order**: preview write → loader read → cleanup must serialize. A recursive cleanup cannot race a load that still needs the file.
6. **Shared sidecar JSON**: view state and pending registration metadata share `.porydaw/<song>.json`; worker operations must preserve unrelated keys. Sidecar failures are best-effort and must not interrupt the user.
7. **Plan staleness**: registration/removal plan probes (`makePlan`, `makeRemovalPlan`, `checkRegistration`, `deletableVoicegroup`) return a snapshot of disk state that can go stale between the probe and the confirming write. The write operation must re-derive/recheck its own plan — it may not trust a cached plan.

### Ownership & thread rules

1. `DecompProject` (root, retained `SongInfo`/player state) lives on the worker. GUI code never calls a project-thread-owned `DecompProject` or keeps references into its mutable containers; it receives detached values or immutable snapshots.
2. `LoadedVoiceGroup` and `LoadedSampleSet` cross the worker→GUI handoff as owned results. Every failure, cancellation, or stale completion must `voicegroup_free` them exactly once; GUI code detaches borrowers before replacement.
3. `SongDocument`, widgets, undo stacks, and audio binding mutate on the GUI thread only. Worker I/O/parsing returns detached values; adoption and signals stay on the GUI thread.
4. `ProjectIo` shutdown invalidates pending work, destroys its pending completion on its own thread, quits the worker event loop, and waits for the thread.

### Scope boundaries

1. **Project filesystem I/O only**: file reads/writes, directory scans, existence/metadata probes, renames, removals, sidecars, and hidden I/O inside the Porya voicegroup loader.
2. **Explicitly out of scope**: `QFileDialog` (modal GUI interaction, stays on the GUI thread), `QSettings` (app-local preferences), user-selected external import source reads, WAV export destination writes, theme cache writes.
3. **Adjacency note**: MIDI/sample import source reads and WAV export can also block, but they are not project-root I/O and are not silently included.

### Not settled (recorded, not blocking)

1. Injection reach: one injected `ProjectIo` at `MainWindow`/orchestrator, or lower project modules too?
2. Specialized workers: does the separate voicegroup worker remain for long Porya loads, or do all operations share the one serial project thread (head-of-line blocking risk)?
3. External import/export reads: same worker, different worker, or out of scope?
4. Cosmetic view-sidecar saves: wait for confirmation, queue as best-effort, or flush at teardown?
5. Immutable snapshot publication via `std::atomic<std::shared_ptr<T>>`: open option, not a decision. It makes pointer replacement safe but does not make a mutable object safe for concurrent access.
6. Mutation plan probes are read-only snapshots and can be stale before confirmation; every confirming worker write must re-derive and re-check its plan.

---

## 3. Subagent Execution Plan

The execution is divided into discrete waves designed for parallel subagent execution with explicit agent roles.

```
Wave 0: Explorer (Reconnaissance & Geometry Pinning)
   │
   ├──► Wave 1: Task (ProjectIo Song & Voicegroup Operations)
   │       │
   │       ▼
   ├──► Wave 2: Task (UI Async Loading & Zero-Layout-Shift Integration)
   │       │
   │       ▼
   ├──► Wave 3: Task (Project Open & Session Restore Migration)
   │       │
   │       ▼
   ├──► Wave 4: Task (Project Writes, Sidecars & Mutations)
   │       │
   │       ▼
   ├──► Wave 5: Sonic (Mechanical UI Call Site Cutover & Cleanup)
   │       │
   │       ▼
   └──► Wave 6: Reviewer (Architecture, Thread-Affinity & Verification Review)
```

---

### Wave 0: Reconnaissance & Contract Pinning
* **Subagent Role**: skip
* **Status**: Contracts that Wave 0 was going to formalize are now pinned in §1 (`SongFileResult`, `VoicegroupLoadResult`, queue rules, empty-view, failure). Do not spawn an explorer to invent types.

---

### Wave 1: `ProjectIo` request queue + song/voicegroup loads
* **Subagent Role**: `task`
* **Target Files**:
  - `src/project/projectio.h`
  - `src/project/projectio.cpp`
  - `src/core/songdocument.h`
  - `src/core/songdocument.cpp`
  - `src/checks/projectiocheck.cpp`
* **Changes** (follow §1 "Settled: `ProjectIo` request queue" exactly):
  1. Replace `m_completion` / `m_generation` with the FIFO `Request` queue. `openProject` returns `uint64_t` and latest-wins among opens only.
  2. Add `cancel`, `loadSongFile`, `loadVoicegroup` with the structs copied from §1.
  3. Add `SongDocument::adoptSmf` as specified. Keep `load()` as `readFile` + `adoptSmf`.
  4. Extend `projectiocheck`:
     - Existing open / superseded-open / failed-open cases still pass.
     - `loadSongFile` on the first playable snapshot song completes off the caller thread; `smf.tracks` is non-empty.
     - `cancel` of that request: completion is not invoked.
     - `loadVoicegroup` on that song's `cfg` returns a non-null vg; the check `voicegroup_free`s it.
     - `cancel` of a vg request: completion is not invoked (no leak).
* **Success Criteria**:
  - `deno task verify --filter projectiocheck` compiles and passes.
  - Do not touch `MainWindow` in this wave.

---

### Wave 2: UI Async Loading & Zero-Layout-Shift Integration
* **Subagent Role**: `task`
* **Target Files**:
  - `src/mainwindow.h`
  - `src/mainwindow.cpp`
  - `src/songsession.h`
  - `src/ui/voicegroupbrowser.h`
  - `src/ui/voicegroupbrowser.cpp`
  - `src/ui/songview.cpp` (paint-only `Loading...` when `!m_timeline`)
* **Changes** (follow §1 song-open sequence, empty-view contract, and failure policy):
  1. **`VoicegroupBrowser`**:
     - Add `setLoading(bool loading)`.
     - `true`: 128 placeholder rows `000 Loading...` … `127 Loading...`, combo placeholder `"Loading..."`, combo/editor disabled. Do not hide widgets. If the tree already has 128 items, `setText` in place; otherwise create them once.
     - `setVoicegroup` must **not** `m_tree->clear()`. Update the existing 128 items via `setText` (see `updateRow`). Creating a new tree is a layout-shift bug.
     - `VoicegroupBrowser::updateRow(int slot)` reads from `m_source` (the editable `VoicegroupSource`), not from the `LoadedVoiceGroup`. On async load, call `browser.setVoicegroup(vg)` **and** `browser.setSource(std::move(source))` (or add a combined `setVoicegroup(vg, source)`), then update rows via `updateRow`. The ADSR column (2) is populated from the source model; confirm `updateRow` can render from a freshly-set source before the user edits anything.
     - Editor panel during load: **retain the existing fields in a disabled state** (do not add a loading notice widget). This keeps the form's geometry identical before/after load and is the zero-layout-shift choice.
  2. **`SongSession`**: add `pendingMidiRequest`, `pendingVgRequest`, `midiBound`, `vgBound` as specified in §1.
  3. **`MainWindow::loadSong`**:
     - `createSession()` + add tab immediately. `setSong(nullptr, nullptr)`, `setDocument(nullptr)`.
     - Active dock: `m_vgBrowser->setLoading(true)`.
     - `pendingMidiRequest = m_projectIo->loadSongFile(...)`.
     - `pendingVgRequest = m_projectIo->loadVoicegroup(root, song.cfg, ...)`.
     - MIDI completion: if `requestId != session.pendingMidiRequest` return; on failure follow §1 failure policy; on success `adoptSmf`, `buildTimeline`, `setDocument` / `setSong(timeline, session.voicegroup)`, apply sidecar, `midiBound = true`. If `vgBound` too, enable interaction and clear loading.
     - Vg completion: if `requestId != session.pendingVgRequest` return; on failure follow §1 failure policy (and `voicegroup_free` if destroying); on success take ownership, bind engine if active, `view->setVoicegroup`, `setVoicegroup` on the browser if active, `vgBound = true`. If `midiBound` too, enable interaction.
     - Tab close / destroySession: `cancel` both pending ids, then existing teardown.
  4. Inject `ProjectIo` as `MainWindow` member constructed in `MainWindow`'s ctor. Wave 3 switches `openProjectDir` onto it; Wave 2 only uses it for the two load methods.
* **Success Criteria**:
  - `deno task verify --filter projectiocheck` still passes.
  - Add a harness case (extend `tabcheck` or a new `sessioncheck`): open a song via `MainWindow` and assert the tab widget exists and `session->midiBound == false && session->vgBound == false` immediately after `loadSong` returns, before the event loop runs the completions.
  - `setVoicegroup` does not call `QTreeWidget::clear`.

---

### Wave 3: Project Open & Session Restore Migration
* **Subagent Role**: `task`
* **Target Files**:
  - `src/mainwindow.h`
  - `src/mainwindow.cpp`
  - `src/project/projectio.h`
  - `src/project/projectio.cpp`
* **Prerequisite**: Wave 1's `uint64_t openProject(QString, OpenCompletion)` must exist.
* **Changes**:
  1. **Injection**: add `ProjectIo *m_projectIo` to `MainWindow` (injected into the ctor, owned by `MainWindow`). `ProjectIo`'s destructor already quits and waits for its worker thread, so destruction order is safe.
  2. **Replace the open**: in `MainWindow::openProjectDir(const QString &dir, bool interactive)`, replace the synchronous `m_project.open(dir, &error)` call with `m_projectIo->openProject(dir, [&](ProjectOpenResult result){ ... })`.
     - On success: install the snapshot into `m_project` **on the GUI thread only**. Use the smallest-safe handoff: the worker returns `ProjectSnapshot { root, songs, trackBudgets }`; `MainWindow` tears down sessions, rebuilds `m_project` from that snapshot, repopulates the song list, and updates the window title inside the completion. (If `DecompProject` needs a builder, add `DecompProject::replaceWith(const ProjectSnapshot&)` rather than exposing retained containers across threads.)
     - On failure: keep the existing behavior (dialog when `interactive`, status bar when restoring) and do **not** touch the current project/sessions.
  3. **`restoreSession()` sequencing** (pin these invariants — do not improvise):
     - `restoreSession` calls the async `openProjectDir`. While the open is in flight, the old project (if any) remains intact; `restoreSession` returns immediately and the GUI shows no tabs until the open completes.
     - On open success, repopulate `m_songList` and the window title, then queue the tab loads: `for (const auto &label : labels) loadSongByLabel(label, /*newTab=*/true);` — exactly as today, but each `loadSong` now enqueues async MIDI+voicegroup loads instead of blocking.
     - `m_restoringSession = true` stays set from before the loop until after the last `loadSongByLabel` has been **queued** (not until loads finish). Its only job is to suppress per-tab activation side effects.
     - The single end-of-restore activation (`m_tabs->setCurrentWidget` + `activateSession` for `activeLabel`) fires **immediately after the loop**, unchanged from today. Do not defer activation behind the async loads — tabs are inserted empty and activate normally; their content binds as completions arrive.
     - `QSettings` writes (`lastProjectDir`, `kLastOpenSongsKey`, `kLastSongLabelKey`) happen on open success, before the tab loop, as today.
  4. **Window title / recent projects**: update inside the open completion. The recent-projects menu is populated from settings (already written before the loop); refresh it there only if it currently reads `m_project` directly.
  5. **`reloadProject()`**: keep synchronous for now — it's a same-project refresh, not a cross-project switch. Note it as a Wave-5 candidate, not in scope.
* **Not in scope**: song loads, sidecars, catalog scans, register/delete — those stay synchronous until their own waves.
* **Success Criteria**:
  - `deno task verify --filter projectiocheck` still passes.
  - Opening a project inserts no tabs until the open completes, then the song list and window title reflect the new project before any tab content binds.
  - `restoreSession()` on a multi-song project queues all tab loads and activates exactly one tab; no project state is read from `m_project` on the worker thread.

---

### Wave 4A: Save Song (serialized, single operation)
* **Subagent Role**: `task`
* **Target Files**:
  - `src/project/projectio.h`
  - `src/project/projectio.cpp`
  - `src/checks/projectiocheck.cpp`
* **Changes**:
  1. Add ONE queued operation to `ProjectIo` (after `openProject`): `saveSong(const SongInfo&, const QString &midiPath, const QString &flagsPath, SaveCompletion);`
  2. Worker body: call existing `SmfFile::writeFile()` and `SongRegistry::mergeCfgFlags`/`writeSongFlags` on the worker. Preserve the settled order: **MIDI write first, flags rewrite second**; return a copied `SaveResult { bool midiOk; bool flagsOk; QString error; }`. The worker must replicate the current "write flags only when changed" decision — pass `SongCfg cfg`, `SongCfg savedCfg`, and `bool hadCfgLine` as inputs and apply the same rule `SongDocument::save` uses. Capture an immutable save snapshot; the worker must not touch the live undo stack.
  3. Completion on the GUI thread (same queued-delivery pattern as `openProject`): mark the undo stack clean ONLY after both succeed; otherwise leave the session dirty for retry.
* **Not included**: `saveVoicegroup`, `registerSong`, `deleteSong`, `preview`, `sidecar` — intentionally excluded per the smallest-safe-rewrite constraint.
* **Success Criteria**:
  - `deno task verify --filter projectiocheck` passes with the new harness case.
  - Saving one dirty session does not freeze the Qt event loop (timed assertion).

---

### Wave 4B: Sidecar Read / Write (independent, parallel-capable design)
* **Subagent Role**: `task`
* **Target Files**:
  - `src/project/projectio.h`
  - `src/project/projectio.cpp`
  - `src/ui/viewsidecar.h`
  - `src/ui/viewsidecar.cpp`
* **Contract** (independent of 4A): `ProjectIo::readSidecar` / `writeSidecar` for `.porydaw/<song>.json` only.
* **Changes**:
  1. Define `SidecarLoadRequest` / `SidecarSaveRequest` structs in `projectio.h` (detached value contracts, no live `ViewSidecar` reference).
  2. Implement queued methods that delegate to the existing JSON codec (`ViewSidecar::load`/`ViewSidecar::save`, `src/ui/viewsidecar.cpp`) for `.porydaw/<song>.json` on the worker, with `Sidecar::ensureDir` (`src/project/sidecar.cpp`) for directory creation; return a copied `ViewSidecar::Snapshot` value (or an error string) — never a live `ViewSidecar` reference.
  3. `ViewSidecar` migrates only its `.json` load/save paths off the GUI thread; cosmetic view-state mutations stay on GUI. Sidecar failures are best-effort and must preserve unrelated keys.
* **Parallel note**: Design/spec work is independent of 4A (different target files, no shared mutable state); runtime execution remains serial on the single `QThread`, but agent assignment is independent.
* **Not included**: `registerSong`, `deleteSong`, `saveVoicegroup`, `preview`.
* **Success Criteria**:
  - `.porydaw/*.json` load/write completes off the GUI thread; unrelated keys preserved.

---

### Wave 4C: Mutation Planning — Register, Delete, Preview Contracts (DESIGN ONLY)
* **Subagent Role**: `task`
* **Target Files**: `src/project/projectio.h`, `src/project/projectio.cpp` (contract definitions only). `src/mainwindow.cpp` is read-only in this wave except for the design note below.
* **Decision**: this wave defines the queued *plan* request/response value types and their worker bodies. It does **not** wire `MainWindow::registerSongById`, `deleteSongById`, or `performSongDeletion` to them, and it does not move the actual multi-file writes. Those wires are a later wave (or stay synchronous).
* **Changes**:
  1. Add three value-result types and their queued methods to `ProjectIo`:
     - `registrationPlan(...)` → returns a `RegistrationPlanResult` value (proposed song ID/constant/player, registration gaps, proposed file edits) as plain copied data.
     - `deletionPlan(...)` → returns a `DeletionPlanResult` value (trash name, affected files, free-slot flag, deletable-voicegroup answer).
     - `previewPlan(...)` → returns a `PreviewPlanResult` value (shadow source path, target `.inc` path).
     Each runs its read-only analysis on the worker (using the worker-owned `DecompProject` and `SongRegistry`), returns a detached value, and delivers on the GUI thread.
  2. **Probe clarification**: `MainWindow::maybeRefreshVoicegroup` (line ~1053) and `MainWindow::loadVoicegroupFor` (line ~1314) are **voicegroup-load** probes, not register/delete plan probes. They belong to the voicegroup-loading flow (Wave 1's `loadVoicegroup` already covers playable loading; the editable `VoicegroupSource::open` is the remaining piece). Do not route them through `registrationPlan`/`deletionPlan`. If a queued "refresh voicegroup catalog" operation is needed, define it separately as `refreshVgCatalog()` returning copied catalog data — but only if Wave 2's browser needs it; otherwise leave these two functions alone.
  3. Add a short note under the plan's own "Not settled" section recording: plan probes are read-only and may return stale data between the probe and the confirming write; the write operation must re-derive/recheck its own plan (as today's `performSongDeletion` re-checks `makeRemovalPlan`).
* **Not executed in this wave**: actual `registerSong` / `deleteSong` multi-file writes; `preview` load/cleanup sequence (preview write → loader read → cleanup must serialize).
* **Success Criteria**:
  - The three plan result types and methods compile; each has a worker body that runs off the GUI thread and returns a detached value.
  - `MainWindow` is unchanged except for the design note — no raw `SongRegistry::makeRemovalPlan`/`checkRegistration` calls are moved in this wave.

### Wave 5: Mechanical Project-I/O Call Site Cutover & Cleanup
* **Subagent Role**: `sonic`
* **Target Files**:
  - `src/ui/newsongwizard.cpp`
  - `src/ui/samplepicker.cpp`
  - `src/ui/sampleeditordialog.cpp`
  - `src/mainwindow.cpp`
* **Decision**: this wave moves only **project-root filesystem reads/writes** behind `ProjectIo` or the project snapshot. It does not touch GUI file dialogs, app settings, export destinations, or non-project source reads.
* **Changes**:
  1. **Wizard existence probes** (`newsongwizard.cpp`): `QFileInfo::exists(m_project->root() + "/sound/songs/midi/<name>.mid")` and `QDir(project->root() + "/sound/voicegroups").exists()` → serve from the project snapshot (`ProjectSnapshot::songs()` / a cached voicegroup list) where possible; where an on-disk recheck is still required (final commit validation), queue a `ProjectIo` existence probe. Keep the wizard's live-typing feedback instant by using the cached answer for hints and the queued probe only for the final "can create" gate.
  2. **Sample picker/editor** (`samplepicker.cpp`, `sampleeditordialog.cpp`): remove any `QFileInfo`/`QDir` probes of the *project* root; route through the snapshot or a queued probe. (Verify first — the current picker may already be fed by `MainWindow`; if it touches no project paths, this step is a no-op.)
  3. **`MainWindow` leftovers** (read-only probes only — writes stay in their own waves):
     - `maybeRefreshVoicegroup`: `QFileInfo(session.vgSource->filePath()).lastModified()` → use the cached value already in `SongSession::vgFileTime` or a cheap queued metadata probe; do not block the GUI thread.
     - `deleteSongById` / `performSongDeletion`: `makeRemovalPlan` / `deletableVoicegroup` reads → queued `deletionPlan` request (uses Wave 4C's `DeletionPlanResult` shape).
     - `registerSongById`: `checkRegistration` / `registerSong` reads → queued plan/commit request.
     - `vgCatalog()` / `ensureSampleSet()`: catalog scan and `voicegroup_load_samples` → queued catalog/sample-batch requests (specialized-worker decision remains open; if unresolved, use the single project thread).
  4. Run `deno task format`.
* **Explicitly out of scope (do not touch)**: `QFileDialog` (GUI interaction, stays on the GUI thread), `QSettings`, WAV export destination paths, sample *source* reads from outside the project, theme cache writes, and any `QFileInfo` used purely for window-title/path display.
* **Success Criteria**:
  - `deno task verify` passes (all 41 `*check.cpp` harnesses).
  - After this wave, no **project-root** `QFile`/`QSaveFile`/`QFileInfo`/`QDir` read/write remains in `src/ui/` except the explicitly excluded cases above; `src/mainwindow.cpp` retains only dialog/settings/export filesystem use.

---

### Wave 6: Architecture, Thread-Affinity & Verification Review
* **Subagent Role**: `reviewer` (and `thermo-nuclear-reviewer` / `qt-cpp-reviewer`)
* **Target Files**:
  - Full codebase diff across `src/` and `src/checks/`
* **Checks & Verification**:
  1. **Thread Affinity Review**:
     - Verify no `QObject` with GUI thread affinity is manipulated on the `ProjectIo` worker thread.
     - Confirm all completions use `Qt::QueuedConnection` / direct GUI callback dispatch.
  2. **Memory & C Ownership**:
     - Audit all `LoadedVoiceGroup` and `LoadedSampleSet` handoffs to confirm `voicegroup_free` is called on all teardown, cancellation, and error paths.
  3. **Automated Verification**:
     - Run `deno task verify` to execute all 41 `*check.cpp` harnesses.
     - Ensure no test regressions across `rollcheck`, `songdoccheck`, `projectiocheck`, etc.
* **Success Criteria**:
  - All test suites green; zero memory leaks or thread warnings.


```
Wave 0: Explorer (Reconnaissance & Geometry Pinning)
   │
   ├──► Wave 1: Task (ProjectIo Song & Voicegroup Operations)
   │       │
   │       ▼
   ├──► Wave 2: Task (UI Async Loading & Zero-Layout-Shift Integration)
   │       │
   │       ▼
   ├──► Wave 3: Task (Project Open & Session Restore Migration)
   │       │
   │       ▼
   ├──► Wave 4: Task (Project Writes, Sidecars & Mutations)
   │       │
   │       ▼
   ├──► Wave 5: Sonic (Mechanical UI Call Site Cutover & Cleanup)
   │       │
   │       ▼
   └──► Wave 6: Reviewer (Architecture, Thread-Affinity & Verification Review)
```

---

