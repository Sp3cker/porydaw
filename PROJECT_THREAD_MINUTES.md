# Project File-I/O Thread Design Minutes

Status: living design record. This file records settled decisions, verified facts, and unresolved questions. Implementation plan is defined in [`docs/project-io-thread-plan.md`](docs/project-io-thread-plan.md).

## Goal

**Settled goal: no project file reads or writes should run on the GUI thread. They go through the dedicated project `QThread` so the GUI stays responsive.**

Make that performance change with the smallest safe rewrite. This is not a request for a broad module cleanup.

The performance boundary is project work that can block on disk: file reads and writes, directory scans, existence and metadata probes, renames and removals, sidecar work, and hidden I/O inside the Porya voicegroup loader. GUI file-dialog interaction and app-local settings are adjacent concerns, not project filesystem I/O.

Success means the GUI queues project file operations, stays able to paint and respond while they run, and applies returned values in the right order without changing current save, reload, ownership, or partial-failure behavior.

This boundary is intentionally about project filesystem work. Moving only a `QFile` read or write does not prevent a later GUI stall if the GUI thread still does costly parsing, decoding, regular-expression work, timeline construction, or other processing. Each flow below therefore distinguishes disk work from processing so later measurements can show which part moved.

## Decisions

### Settled

- The design centers on one dedicated `QThread` for project file I/O.
- A worker `QObject` with affinity to that thread performs the filesystem work.
- A GUI-facing object queues complete operations to the worker and delivers completion values back to the GUI thread.
- Callers receive that GUI-facing object through dependency injection. They do not construct it ad hoc and do not reach it through a global.
- Callers do not receive the raw `QThread` or live `QFile` objects.
- The new module is not merely a `QFileSystemWatcher` wrapper. It is the handle/interface through which callers submit project file-I/O work.
- The work is a performance change, not a broad architecture cleanup. Existing production modules can remain the implementation behind the new dispatch seam where that is safe.
- `DecompProject` itself should live on and be accessed from the dedicated project thread. Its discovery, parsing, retained lookup state, reloads, and mutations form a main part of the worker-owned project state.
- GUI code must not directly call a project-thread-owned `DecompProject` or retain references into its mutable containers. It queues operations and receives copied/value results such as an open-project snapshot, song lists, and resolved `SongInfo` values.
- `MainWindow` project-I/O orchestration will be substantially rewritten. Its 14 direct project-I/O initiation sites are requirements for the replacement orchestration path, not 14 call sites that the design should preserve or inject one by one.
- All 19 current UI-owned project-filesystem initiation sites must be absorbed behind the one injected GUI-facing project-I/O object. No `MainWindow`, wizard page, or `ViewSidecar` path should keep initiating project filesystem work directly.
- `DecompProject` lives on or inside the worker-side implementation. The GUI-facing object may own the `QThread` and route queued operations to `DecompProject` and existing internal project modules on that thread. This does not require view-sidecar JSON, preview files, or every other operation to become a public `DecompProject` method.
- All later decisions and every unresolved question from this design discussion must remain in this file.
- Song open shows an empty `SongView` immediately. MIDI SMF parse and voicegroup load both run on `ProjectIo`. The document/timeline bind when `loadSongFile` completes; the voicegroup binds when `loadVoicegroup` completes. Either result may arrive first. Tab close cancels that session's in-flight requests.
- Empty `SongView` is a normal `createSession()` widget: full chrome stays in the constructor layout; `PianoRoll` paints `Loading...` only while the timeline is null; no overlay widget and no hide/show. The tab is display-only until both MIDI and voicegroup have bound. Tab close and tab switch stay enabled. Camera/zoom jump on first `setSong` is allowed. Sidecar view state applies only after MIDI bind.
- Load failure after the empty tab exists tears the tab down (`destroySession` + existing warning). The sibling in-flight request is cancelled. A late `LoadedVoiceGroup*` is `voicegroup_free`'d on the GUI thread and not applied.
- `ProjectIo` uses a FIFO request queue on the facade thread. Each call returns a `uint64_t` id. `cancel(id)` is cooperative (running work finishes; result is dropped; a dropped `LoadedVoiceGroup*` is `voicegroup_free`'d on the facade thread). `openProject` latest-wins among opens only. `loadSongFile` / `loadVoicegroup` never cancel each other. `loadSongFile` is `SmfFile::readFile` only; GUI adopts via `SongDocument::adoptSmf`. `loadVoicegroup` is one op: `voicegroup_load` then `VoicegroupSource::open`, both-or-neither.





### Not settled

- The production owner or owners that receive the injected dependency are not settled. The main choice is one injected dependency at `MainWindow` or another orchestrator versus injection into lower project modules as well.
- The five non-`MainWindow` direct sites under `src/ui/` still need a caller-routing decision: their current owners can call the injected object, or route requests through the replacement `MainWindow` orchestration. Either route must end at the same injected project-I/O boundary.
- Whether specialized workers remain alongside the project thread is not settled. One serial project thread is simpler and consistent, but a long voicegroup load could delay unrelated project commands.
- Publishing an immutable project snapshot with `std::atomic<std::shared_ptr<T>>` is an open option, not a decision.

## Verified Current Architecture

### Production ownership and thread boundary

- `CMakeLists.txt` defines `porydaw_app` and includes `src/mainwindow.cpp`, `src/core/songdocument.cpp`, `src/core/smf.cpp`, the modules under `src/project/`, the sample/audio import and export modules, `src/ui/newsongwizard.cpp`, and `src/ui/viewsidecar.cpp`.
- Current local `fork-main` has no production `QThread` or `moveToThread` use. Project operations are called synchronously from `MainWindow` actions, tab activation, project restore, and wizard code. Therefore the GUI-thread labels below are verified from the direct production call path unless marked as an inference.
- `MainWindow` is the current orchestration owner. `DecompProject` stores the open project's song/player snapshot. Each `SongSession` owns a `SongDocument`, editable `VoicegroupSource`, timeline, and `LoadedVoiceGroup`; `AudioEngine` borrows active playback state.
- There is no production `QFileSystemWatcher`. Voicegroup staleness is polled with `QFileInfo::lastModified()` when a tab becomes active.

### Qt execution semantics

- Ordinary `QFile`/`QSaveFile` reads and writes, `QFileInfo` metadata queries, `QDir`/`QDirIterator` scans, renames, removals, and recursive cleanup execute synchronously on the calling thread. Qt does not move these calls to a worker on its own. `QSaveFile::commit()` also performs the final replacement/rename step. See the Qt documentation for [`QFile`](https://doc.qt.io/qt-6/qfile.html), [`QSaveFile`](https://doc.qt.io/qt-6/qsavefile.html), [`QFileInfo`](https://doc.qt.io/qt-6/qfileinfo.html), and [`QDirIterator`](https://doc.qt.io/qt-6/qdiriterator.html).
- A native `QFileDialog` is GUI interaction and stays on the GUI thread. The project read or write that follows the selected path is a separate operation.
- `QFileSystemWatcher` can receive changes through operating-system facilities, but its signals and receiver slots still follow Qt object thread affinity. Any metadata probe or file read performed by a GUI-thread receiver is synchronous there. See [Qt threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html) and [`QFileSystemWatcher`](https://doc.qt.io/qt-6/qfilesystemwatcher.html).

### `DecompProject` state beyond file I/O

`src/project/decompproject.{h,cpp}` is not only a thin file wrapper. In addition to discovery and parsing, it retains the project root, a mutable `QVector<SongInfo>`, and cached `QVector<MusicPlayer>` data. It also provides non-I/O state/query behavior:

- `isOpen()`, `root()`, and `songs()` expose retained state; `root()` and `songs()` currently return const references.
- `trackBudgetFor()` resolves a song's player against the cached music-player table.
- `voicegroupCandidates()` maps a `SongInfo` or `SongCfg` to loader-compatible lookup names without disk I/O.
- `setSongCfg()` mutates the cached configuration after a successful flags write.
- `close()` clears the retained state; `reload()` replaces it by reopening the root.

`DecompProject` is currently a plain C++ object, not a `QObject`, so it does not acquire Qt affinity by itself. The settled direction means the worker owns it and only project-thread operations access it. GUI code cannot keep using its current reference-returning API across threads. The handoff must use detached values or immutable snapshots.

### Current timing boundaries

- `MainWindow::openProjectDir()` uses one `QElapsedTimer`, but the interval also includes pre-switch save prompts, old view-sidecar saves, preview cleanup, project parsing, and GUI state changes. It is not a project-I/O-only measure.
- `MainWindow::loadSong()` uses one `QElapsedTimer` around voicegroup loading, MIDI read/parse, timeline build, editable voicegroup parsing, view-sidecar load, and GUI/session binding. It does not rank the blocking calls.
- Current local `fork-main` has no per-operation filesystem timing inside `DecompProject`, `SongRegistry`, `VoicegroupSource`, `SampleRegistrar`, `ViewSidecar`, or the external voicegroup loader.
- The first implementation work should preserve clear timing boundaries so the project can prove which queued calls removed GUI stalls. The exact instrumentation is not settled.

### Disk time versus processing time

- Project open combines file opens/scans with text parsing, regular expressions, registration analysis, sorting, and construction of retained `SongInfo`/player state. Moving the whole `DecompProject` operation to the project thread moves both parts off the GUI path.
- Song load combines the MIDI file read with SMF parsing, tempo normalization, track remapping, and later timeline construction. A byte read on the worker followed by all parsing on the GUI can still stall.
- The Porya loader combines discovery and file reads with voice/sample parsing, decoding, allocation, keysplit expansion, and included-subgroup traversal.
- `VoicegroupSource` and the voicegroup catalog combine directory scans/file reads with regular-expression parsing, source-model construction, deduplication, and sorting.
- Registry and deletion flows combine reads with plan construction, reference searches, byte-conservative rewrites, and error aggregation.
- Sample flows combine source/project reads and writes with decode, resample, crop, loop, waveform rendering, and preview reload work.

The first performance measurements should time complete queued operations and, where useful, separate their disk and processing phases. The design does not assume that moving a file handle alone removes the full pause.

### Separate asynchronous voicegroup work

- The separate `integrate/async-voicegroup-loading` branch adds `src/project/voicegrouploader.{h,cpp}` on that branch. It runs per-song `voicegroup_load()` calls on one worker `QThread` and can also construct/open the editable `VoicegroupSource` there, then returns owned results to the GUI thread.
- That branch covers initial, switch, refresh, and preview playable-voicegroup loads plus the paired editable source parse. It does not move broad project open/reload, registry scans and writes, catalog scans, sidecars, sample registration, song creation/deletion, or other project file work.
- The broader project-thread design therefore cannot treat that branch as complete project-I/O coverage. Whether its specialized worker should stay separate remains open.

## File-I/O Inventory

The inventory starts from the production owners in `CMakeLists.txt` and excludes `src/checks/` harnesses. “GUI now” means the production call is synchronous on the GUI path. Candidate destinations name complete worker operations, not final method or class names.

### Count and method

A **direct initiation site** is one unique production source location that begins a synchronous filesystem action: open, existence/metadata probe, directory scan, create, rename, remove, or recursive cleanup. A later `readAll()`, `write()`, or `commit()` on the same opened file belongs to that initiation site, and a loop does not create a new source site per iteration. Read/write-capable counts can overlap when one source location conditionally does both; grouped flows describe user-visible operations and do not add up to the raw source-site count.

| Production owner | Direct sites | Read/probe/scan-capable | Write/mutation-capable | Plain scope |
| --- | ---: | ---: | ---: | --- |
| `src/mainwindow.cpp` | 14 | 9 | 5 | Voicegroup mtimes; restored-root, sample, MIDI/trash-name, and voicegroup-directory probes; project sample read; song rename/generated-file removal; preview directory/file create, write, and cleanup. |
| `src/ui/newsongwizard.cpp` | 2 | 2 | 0 | Proposed MIDI existence and per-file voicegroup-layout existence. |
| `src/ui/viewsidecar.cpp` | 3 | 2 | 1 | Existing-root read for a key-preserving rewrite, sidecar load, and atomic sidecar save. |
| `src/project/decompproject.cpp` | 6 | 6 | 0 | Project root/table/config scans and reads. |
| `src/project/songregistry.cpp` | 20 | 13 | 7 | Registration/player/reference reads and multi-file registration/metadata writes. |
| `src/project/songsmk.cpp` | 5 | 3 | 2 | Legacy flags read, rule rewrite, and rule removal. |
| `src/project/samplereg.cpp` | 12 | 6 | 6 | Sample-format/provenance probes and reads; sample/include/sidecar writes and removals. |
| `src/project/sidecar.cpp` | 4 | 2 | 2 | `.porydaw`/`.gitignore` probes, directory create, and atomic `.gitignore` update. |
| `src/project/voicegroupsource.cpp` | 20 | 14 | 7 | Voicegroup/catalog/synth scans and reads; source/include/hub writes and removal. One conditional existence/removal location is in both columns. |
| `src/core/smf.cpp` | 2 | 1 | 1 | MIDI read and MIDI write. |
| **Porydaw production total** | **88** | **58** | **31** | One overlapping read/write-capable source location makes `58 + 31` one larger than 88 unique sites. |
| Linked Porya loader, `external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.c` | 18 | 18 | 0 | Two metadata probes, four directory scans, and twelve file-open locations used by project voicegroup/sample discovery and loading. |
| **Current code plus linked loader** | **106** | **76** | **31** | Hidden loader I/O included. |

The tables below group these locations into **12 read/scan flows and 9 write/mutation flows: 21 owning flows total**. The raw count measures source breadth; the grouped count measures useful worker operations.

### UI-owned direct sites

There are **19 direct project-filesystem initiation sites under UI ownership**: 13 read/probe sites and 6 write/mutation sites. These 19 are already included in the 88-site Porydaw total.

| Production file | GUI owner | Count | Direct project operations | Widget? |
| --- | --- | ---: | --- | --- |
| `src/mainwindow.cpp` | `MainWindow` | 14 | Three voicegroup mtimes; restored project-root existence; project sample-WAV existence and read; song MIDI existence, trash-name existence loop, MIDI rename, generated `.s` removal; preview directory creation, preview-file write, recursive preview cleanup; voicegroup-directory existence. | Yes. `MainWindow` is both a `QMainWindow` and the current project orchestrator. Its orchestration will be replaced, so these are coverage requirements rather than injection points to preserve. |
| `src/ui/newsongwizard.cpp` | `IdentityPage` and `SoundPage`, owned by `NewSongWizard` | 2 | Proposed project MIDI existence; per-file voicegroup-directory existence. | Yes. These are `QWizardPage` widgets. |
| `src/ui/viewsidecar.cpp` | `ViewSidecar` namespace codec | 3 | Read the existing JSON root before a key-preserving rewrite; load the song view JSON; atomically save it. | No. This is a UI-state helper module, not a widget. Its `Sidecar::ensureDir()` call is an additional indirect project-I/O entry. |

All 19 sites must move behind the single injected project-I/O object. The 14 `MainWindow` sites feed the replacement orchestration path. The remaining five still need a caller-routing choice: inject the GUI-facing object into the wizard/helper owners, or have them request operations through the new `MainWindow`/orchestrator path. In addition, UI-owned production code has 47 indirect entry sites into file-owning project/core modules; those are call-path evidence, not 47 extra raw filesystem sites.

### Project reads, scans, and metadata probes

| Area and owner | Operation and files | Current caller/path | GUI now | Data or state | Ordering and lifetime constraints | Candidate destination |
| --- | --- | --- | --- | --- | --- | --- |
| Project open/reload — `src/project/decompproject.{h,cpp}` | Checks the root directory; reads `sound/song_table.inc`, `include/constants/songs.h`, `sound/songs/midi/midi.cfg` or root `songs.mk`, `sound/music_player_table.inc`; lists `sound/songs/midi/*.mid`. It also calls the registry audit below. | `MainWindow::openProjectDir()` and `MainWindow::reloadProject()` in `src/mainwindow.cpp`; startup path is `restoreSession()` → `openProjectDir()` → later tab loads. | Yes, direct. | Replaces worker-owned `DecompProject` root, songs, flags, registration gaps, and player track budgets; returns a detached snapshot/value result to the GUI. | Old sessions are prompted/saved and old view state is written before the project changes. Failed open keeps the existing GUI sessions and published snapshot. | Complete “open/reload project snapshot” operation on the project worker. |
| Registration audit nested under open — `src/project/songregistry.{h,cpp}` | `checkRegistrations()` rereads `song_table.inc`, `songs.h`, `ld_script.ld`, `charmap.txt`, and `src/debug.c` once for all songs. `musicPlayers()` rereads both song/player tables. | Called inside `DecompProject::open()`. | Yes, inferred from the direct open call. | Registration gaps and music-player budgets in the project snapshot. | Must correspond to the same on-disk generation as the song table and constants used for the snapshot. | Part of the same project-open worker operation, not a later GUI-thread audit. |
| Song identity validation and import wizard — `src/ui/newsongwizard.cpp` | Repeated `QFileInfo::exists()` for the proposed `.mid`; checks `sound/voicegroups/`; import construction calls `SongRegistry::musicPlayers()` and reads the project tables again. | `MainWindow::newSong()` and `MainWindow::importMidi()`. | Yes, direct wizard/UI path. | Wizard completeness, allowed voicegroup-creation mode, player choices, import analysis. | Validation must not accept a name that became occupied before commit. A cached/preloaded answer can improve typing, but the final worker commit still needs an on-disk recheck. | Project snapshot data where possible; otherwise a queued validation/read operation. Exact split is open. |
| MIDI song load — `src/core/songdocument.cpp`, `src/core/smf.{h,cpp}` | `SongDocument::load()` → `SmfFile::readFile()` reads and parses the song `.mid`. | `MainWindow::loadSong()`. | Yes, direct. | Mutates the live `SongDocument`, undo stack, normalized tempo state, and track map. | `SongDocument` is a `QObject` tied to GUI-owned session state. Worker I/O/parsing must return detached values; live document adoption and signals stay on the GUI thread. | Song-load worker operation returning parsed song data for GUI adoption. |
| Playable voicegroup load — `src/mainwindow.cpp`; hidden implementation in `external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.c` at the current Porya gitlink | `voicegroup_load()` recursively discovers project sound layout; performs directory walks and `stat`/existence probes; reads sound-data, programmable-wave, keysplit, voicegroup, WAV/AIF/BIN, and included sub-voicegroup files. Preview loading also reads `.porydaw/vgpreview/*.inc`. | `MainWindow::loadVoicegroupFor()` during song load, document `-G` changes, cross-tab refresh, and save verification; direct call in `reloadVoicegroupPreview()`. | Yes, direct; hidden loader I/O is inside the same call. | Allocates a `LoadedVoiceGroup` with decoded samples, waves, keysplits, and names. A `SongSession` owns it; views/audio borrow it until detached. | On replacement, the view/browser/audio must release the old object before it is freed. Failed or stale results must keep or free ownership safely. | Complete playable-voicegroup load operation; may remain a specialized worker if that decision is made. |
| Editable voicegroup source — `src/project/voicegroupsource.{h,cpp}` | `open()` probes likely files, may recursively scan `sound/voicegroups/`, reads declarations, then `reload()` rereads/parses the chosen file. | `MainWindow::openVoicegroupSource()` during song load, `-G` changes, save refresh, and cross-tab refresh. | Yes, direct. | Produces the byte-preserving editable source model and its disk baseline. | The editable source must match the playable voicegroup result and project generation. Unsaved per-tab edits must remain isolated. The separate async branch already pairs this parse with playable loading. | Same complete song/voicegroup load operation, returning owned editable source data. |
| Per-song view sidecar — `src/ui/viewsidecar.{h,cpp}`, `src/project/sidecar.{h,cpp}` | Reads `.porydaw/<song>.json`. | `MainWindow::loadSong()`. | Yes, direct. | Camera, grid, selection, edit cursor, lane heights/ranges, and hidden/empty lanes. | Cosmetic and best-effort. Apply only to the matching song/session. | Queued sidecar read, or part of a song-load result if that preserves locality without delaying first content. Choice open. |
| Voicegroup browser catalog — `src/project/voicegroupsource.{h,cpp}` | `catalogScan()` lists and reads monolithic/per-file voicegroups; `directSoundCatalog()` reads direct-sound/synth data and scans `asm/macros/*.inc`; `progWaveSymbols()` reads programmable-wave data. | Lazy `MainWindow::vgCatalog()` from browser updates, new/import song, sample operations, synth editing, and new voicegroup. | Yes, direct and cached only after the first full scan per invalidation. | `MainWindow::VgCatalog` value cache; invalidation also drops loaded sample sets. | A completion must not repopulate a cache after a project switch or later invalidation. | Queued “refresh voicegroup catalog” operation returning value data. |
| Lazy sample/keysplit batch — `src/mainwindow.cpp`; hidden Porya loader path above | `voicegroup_load_samples()` repeats project discovery and sound-data parsing, then reads every requested sample, programmable wave, and keysplit/subgroup needed by the browser. | `MainWindow::ensureSampleSet()` from sample-info and audition callbacks. | Yes, direct on first demand after each catalog invalidation. | `LoadedSampleSet`, then maps of borrowed wave/keysplit pointers used for browser metadata and audition. | The set owns all returned pointers. Invalidation/free must not race a late load or active audition copy. | Queued batch load with explicit ownership transfer; specialized-worker choice remains open. |
| Voicegroup staleness probe — `src/mainwindow.cpp` | `QFileInfo::lastModified()` on the editable voicegroup file, followed by full playable/editable reload if changed. | `activateSession()` → `maybeRefreshVoicegroup()`; save records a fresh mtime. | Yes, direct. | `SongSession::vgFileTime` and possibly both voicegroup models. | Dirty tabs must not auto-reload. Clean sibling tabs reload after another tab saves. Last-save-wins semantics must remain. | Cheap queued metadata probe or fold into serialized save/activation commands. No watcher exists today. |
| Registration/removal planning — `src/project/songregistry.{h,cpp}` | `makePlan()`, `makeRemovalPlan()`, and `checkRegistration(s)` read the five registration files, song/player tables, and related constants. `deletableVoicegroup()` also scans all voicegroups and recursively reads project `src/**/*.c`, `src/**/*.h`, and `include/**/*.c`, `include/**/*.h` for symbol references. | Register and delete actions in `src/mainwindow.cpp`; audit also occurs during open. | Yes, direct. The deletable-voicegroup scan can be wide. | Confirmation plans, proposed IDs, applicability flags, and whether a voicegroup can be deleted. | The plan can go stale between confirmation and commit; the write operation already recomputes/rechecks parts of it and must continue to do so. | Queued planning operation plus a separate complete commit operation that revalidates on disk. |
| Sample project probe and provenance — `src/project/samplereg.{h,cpp}` | `probeSampleFormat()` lists root `*.mk` files and reads makefiles to find the sample build rule; validation probes `.wav/.bin/.aif`; edit reads `.porydaw/samples/<name>.json` and the committed project `.wav` when the external original cannot be used. | `MainWindow::importSampleForSlot()` and `editSampleForSlot()`. | Yes, direct. | Format capability, name availability, provenance, and imported sample bytes. | Final registration must recheck symbols/files after any earlier UI validation. Provenance is auxiliary; the committed project WAV remains canonical. | Queue project probe/read work and complete sample commit work. External source reads are classified separately below. |

### Project writes, renames, removals, and cleanup

| Area and owner | Operation and files | Current caller/path | GUI now | Data or state | Ordering and lifetime constraints | Candidate destination |
| --- | --- | --- | --- | --- | --- | --- |
| Save song and flags — `src/core/songdocument.cpp`, `src/core/smf.cpp`, `src/project/songregistry.cpp`, `src/project/songsmk.cpp` | Writes the `.mid`; then, when needed, rewrites `midi.cfg` or root `songs.mk`. | `MainWindow::saveSession()`. | Yes, direct. | Persistent MIDI and `SongCfg`; only after both succeed does the document mark its undo stack clean. | Preserve current order: MIDI first, flags second. A flag failure can leave the new MIDI on disk while the session remains dirty for retry. Capture an immutable save snapshot; do not let the worker touch the live undo stack. | Complete “save song snapshot” worker operation; GUI marks clean and updates cached cfg only on success. |
| Save voicegroup and synth definitions — `src/project/voicegroupsource.cpp` | Scans synth definitions/macros; atomically appends `sound/direct_sound_synth_data.inc`; may edit an assembly include anchor; then rewrites the editable voicegroup file. The caller reloads via Porya and probes mtime. | First part of `MainWindow::saveSession()`. | Yes, direct. | Pending synth definitions, editable source bytes, catalog cache, playable voicegroup, sibling sessions, mtime. | Preserve: synth definitions before the voicegroup that references them; voicegroup before document save; invalidate catalog after definitions; verify by reload; record mtime only after a real write; refresh clean siblings without overwriting dirty ones. | One ordered save operation or an explicitly serialized sequence on the project worker, with value results for GUI cache/session updates. |
| Voicegroup preview — `src/mainwindow.cpp` plus the Porya loader | Creates `.porydaw/vgpreview`, writes a shadow `.inc`, then calls `voicegroup_load()` against it; cleanup uses recursive directory removal on song/project switches and after save. | Structural voice edits and preview cleanup. | Yes, direct. | Temporary project-local preview source and a replacement `LoadedVoiceGroup`. | The file must be fully written before load; cleanup must not race a queued load; stale preview results must be freed. | Complete “materialize and load preview” worker operation, serialized with preview cleanup. |
| View and registration/sample sidecars — `src/ui/viewsidecar.cpp`, `src/project/songregistry.cpp`, `src/project/samplereg.cpp`, `src/project/sidecar.cpp` | Reads/rewrites `.porydaw/*.json`; creates `.porydaw[/subdir]`; may append `.porydaw/` to root `.gitignore`; removes sidecars. | Tab close, project switch, app close, song load/create/delete, and sample import/edit. | Yes, direct. | Cosmetic view state, pending registration metadata, sample provenance. | Old-project view state must be captured and written against the old root before the switch. Sidecar failures are often intentionally best-effort. Multiple codecs share one per-song JSON root and must preserve each other's keys. | Queued sidecar operations with explicit best-effort result policy and ordering by project/song key. |
| Create/import song and register — `src/mainwindow.cpp`, `src/core/smf.cpp`, `src/project/songregistry.cpp`, `src/project/songsmk.cpp`, `src/project/voicegroupsource.cpp` | Optionally creates a voicegroup and hub include; writes the new `.mid`; writes flags; then rewrites up to `song_table.inc`, `songs.h`, `ld_script.ld`, `charmap.txt`, and `src/debug.c`; on registration failure writes pending metadata and reloads the project. | `MainWindow::finishCreateSong()` after the new/import wizard. | Yes, direct. | New project files plus refreshed project/song list and optional new tab. | Preserve existing partial-commit contract: new voicegroup first; MIDI/flags next; registration last. Failed registration intentionally leaves a playable unregistered MIDI and metadata for retry. Do not claim transactionality. | One complete create/import worker operation returning a detailed outcome, followed by GUI snapshot adoption/tab load. |
| Register existing song — `src/project/songregistry.cpp` | Re-reads a registration plan and sequentially rewrites the registration files; clears pending sidecar metadata; reloads project state. | `MainWindow::registerSongById()`. | Yes, direct. | Song ID/registration state and project snapshot. | Multi-file writes are sequential, not atomic as a group. Preserve byte-conservative edits and current retry behavior. | Complete register operation, then queued/project snapshot refresh or a result containing refreshed registration data. |
| Delete song — `src/mainwindow.cpp`, `src/project/songregistry.cpp`, `src/project/voicegroupsource.cpp`, `src/project/sidecar.cpp` | Closes the tab; creates `.porydaw/trash`; finds a free trash name; renames `.mid`; removes generated `.s`; rewrites flags and registration files; removes sidecar; optionally removes voicegroup hub line and file; reloads project. | `MainWindow::performSongDeletion()`. | Yes, direct. | Filesystem plus sessions, audio binding, catalog, and project list. | GUI must detach/destroy the song session and audio borrowers before files disappear. Preserve recoverable MIDI rename, stable song IDs, best-effort problem collection, and reload after all attempts. | GUI pre-step to detach, then one serialized delete operation, then GUI applies refreshed project result. |
| Import/update sample — `src/project/samplereg.cpp`, `src/mainwindow.cpp` | Creates/atomically writes project `.wav`; then atomically appends `direct_sound_data.inc`; writes provenance sidecar. Update rewrites `.wav`, adjusts/removes sidecar, invalidates catalogs, and reloads the preview voicegroup. | `MainWindow::importSampleForSlot()` and `editSampleForSlot()`. | Yes, direct. | Registered sample, symbol catalog, optional voice assignment, provenance, loaded audio. | Preserve `.wav` before registration block so failure leaves a harmless orphan rather than a build-breaking symbol. Sidecar remains best-effort. Voice assignment is separately undoable and must occur only after file commit. | Complete sample register/update worker operation; GUI then updates caches, undo state, and queues any preview reload. |
| Create/delete voicegroup — `src/project/voicegroupsource.cpp` | Lists siblings to copy style; may read a source file/section; writes `sound/voicegroups/<name>.inc`; rewrites `sound/voice_groups.inc`. Delete removes hub include before removing the file. | New-song flow, `MainWindow::newVoicegroup()`, and optional song deletion. | Yes, direct. | Project voicegroup files, browser catalog, optional current song cfg. | Preserve file-before-include creation order and include-before-file deletion order. Catalog invalidation and song assignment happen on GUI completion. | Complete create/delete voicegroup worker operation. |

### Exhaustive project-write owners

The 31 write/mutation-capable source locations above belong to these production implementations. This list is the write-coverage checklist for the future boundary:

- `src/core/smf.cpp`: `SmfFile::writeFile()` writes song MIDI.
- `src/project/songregistry.cpp`: registration/unregistration rewrites; `midi.cfg` update/removal; pending-registration sidecar write/removal.
- `src/project/songsmk.cpp`: legacy `songs.mk` rule write/removal.
- `src/project/samplereg.cpp`: project sample WAV and registration-include writes; sample provenance sidecar write/removal; needed directory creation.
- `src/project/sidecar.cpp`: `.porydaw` directory creation and atomic root `.gitignore` update.
- `src/project/voicegroupsource.cpp`: synth include/data writes; editable voicegroup save; voicegroup file/hub creation and rewrite; voicegroup file removal.
- `src/ui/viewsidecar.cpp`: atomic per-song view-sidecar write.
- `src/mainwindow.cpp`: preview directory/file write and cleanup; deleted-song MIDI rename and generated `.s` removal.

`src/core/songdocument.cpp` starts MIDI and song-flag saves indirectly through `SmfFile`, `SongRegistry`, and `SongsMk`; it has no additional direct file primitive. `DecompProject` reads and retains project state but has no direct write site today.

### Adjacent I/O kept distinct from project filesystem I/O

- `QFileDialog` calls in `src/mainwindow.cpp` are modal GUI interaction and must remain on the GUI thread. They choose paths; they are not the worker's filesystem implementation.
- `QSettings` in `src/mainwindow.cpp` and theme/keymap modules stores app-local preferences and session labels. It is not project filesystem I/O and is outside this project's stated scope unless the scope changes.
- MIDI and sample import first read a user-selected external source file. Sample edit may reread the external provenance path. These reads can also block the GUI, but they are not project-root I/O; whether the same worker owns them is open.
- `src/audio/wavexport.{h,cpp}` writes a user-selected destination and performs synchronous rendering. The destination may be outside the project and the main cost may be rendering rather than filesystem I/O. It is not silently included in the project-I/O worker scope.
- `src/audio/sampleimport.cpp` and `src/audio/sf2reader.cpp` expose direct file helpers, but the current `MainWindow` path reads source bytes itself and uses byte-based decoding. These helpers are not current project-root I/O owners.
- `src/audio/audioengine.cpp` reads `/proc/sys/kernel/osrelease` on Linux/WSL. `src/ui/theme/themeruntime.cpp` creates a cache under the system temporary directory and can write glyph PNG files there. Neither is project I/O.
- The linked Porya loader contains an optional append-mode diagnostic log write, but current Porydaw does not call `voicegroup_loader_set_log_path()`. It is not an active project write in this inventory.

### Test-only fixtures

- `src/checks/` and check-only files are excluded from the production inventory. They call the production modules against staged scratch fixtures and remain useful for preserving operation order and failure behavior when implementation starts.
- The inventory does not propose moving fixture staging or the Deno check runner onto the project thread.

## Candidate Seam

Keep the seam small and performance-focused:

1. One GUI-facing, dependency-injected module accepts complete project operations expressed as owned/value requests. All 19 current UI-owned initiation sites move behind it.
2. It may own the dedicated project `QThread`; it queues each operation to one worker `QObject` on that thread.
3. The worker owns or contains `DecompProject`, calls existing file-oriented implementations such as `SongRegistry`, `VoicegroupSource`, `SampleRegistrar`, and sidecar codecs where safe, and returns owned/value results and errors. The public surface does not have to turn every operation into a `DecompProject` method.
4. The GUI-facing object delivers completions on the GUI thread. GUI owners then mutate `MainWindow`, `SongSession`, `SongDocument`, widgets, undo stacks, audio bindings, and caches.

This interface should hide thread mechanics and file handles while providing leverage across the blocking call sites and locality for queue order, cancellation/staleness checks, result delivery, and shutdown. It should not force a broad rewrite of `DecompProject`, `SongRegistry`, `VoicegroupSource`, `SampleRegistrar`, or `ViewSidecar` before I/O can move.

Dependency injection is settled; its reach is not. Injecting one dispatcher into the orchestrator keeps thread coordination local, while injecting an asynchronous dispatcher into lower modules could spread request lifetimes and completion handling across the codebase. The design must choose that owner deliberately.

### Optional immutable snapshot publication

The user raised C++20 `std::atomic<std::shared_ptr<T>>` as an option for publishing an immutable project snapshot from the project thread so the GUI can make cheap reads. This is not settled.

- Atomic `shared_ptr` operations make publication/replacement of the pointer safe. They do not make the pointed-to object safe for concurrent mutation; a published snapshot must remain immutable.
- `std::atomic<std::shared_ptr<T>>` is not guaranteed to be lock-free; `is_always_lock_free` is implementation-defined.
- A snapshot can help with current-state queries, but it does not replace queued commands and completions for ordered mutations, errors, cancellation, or partial outcomes.

See the C++20 atomic smart-pointer specification in the [C++ working draft](https://eel.is/c++draft/util.smartptr.atomic.shared).

## Risks/Ordering Constraints

- **Head-of-line blocking:** one serial project thread gives simple, consistent ordering, but a long Porya voicegroup load or broad reference scan can stall quick sidecar saves or metadata probes behind it. Whether heavy work keeps a specialized worker is open.
- **Stale completions:** a project switch, tab close, catalog invalidation, or newer request can make an old result unsafe. Results need project/session identity and an explicit stale-result disposal rule; the exact mechanism is open.
- **Thread-owned state:** `MainWindow`, widgets, `SongDocument`, undo stacks, and audio binding changes stay on the GUI thread. `DecompProject` and its mutable containers stay worker-owned. Operations cross the seam only through detached inputs/outputs or an immutable published snapshot.
- **C ownership:** `LoadedVoiceGroup` and `LoadedSampleSet` cross the worker/GUI handoff as owned results. Every failure, cancellation, or stale completion must free them exactly once, and GUI code must detach borrowers before replacement.
- **Project switch order:** prompt/save old sessions, capture and save old sidecars against the old root, then perform the switch. A failed open must not destroy the current project/session state.
- **Save order:** synth definitions → voicegroup source → voicegroup reload/mtime/sibling refresh → MIDI → cfg flags → GUI clean-state update. Existing partial failures and retry behavior must remain visible.
- **Create order:** optional voicegroup → MIDI → flags → multi-file registration → metadata on registration failure → project refresh. This is intentionally recoverable, not atomic.
- **Delete order:** GUI detaches the session/audio first; worker then moves/removes/rewrites files; project state refresh follows all attempts.
- **Preview order:** preview write, loader read, and cleanup must serialize. A recursive cleanup cannot race a load that still needs the file.
- **Shared sidecar JSON:** view state and pending registration metadata share `.porydaw/<song>.json`; worker operations must preserve unrelated keys and serialize per-song rewrites.
- **Shutdown:** `ProjectIo` invalidates pending work, destroys its pending completion on its own thread, quits the worker event loop, and waits for the thread. The later production wiring still needs to place this shutdown before GUI-owned result consumers are destroyed.
- **Measurement:** current end-to-end timers do not attribute filesystem stalls. Without operation timings, moving work cannot prove which GUI pauses were removed.

## Open Questions

1. Which production owner receives `ProjectIo`: only `MainWindow`/a project orchestrator, or lower project modules too?
2. Does the separate voicegroup worker remain for long Porya loads, or do all project operations share the one project thread despite head-of-line blocking?
3. After the implemented `openProject` operation, which complete flow moves next: reload, song load, catalog/sample loading, save, registration/delete, sidecars, or another path?
4. What request identity and cancellation/staleness rules do operations other than project open need across project switches, tab closes, reloads, and repeated catalog/preview requests?
5. Should user-selected external import source reads and WAV export destination writes use the same worker, a different worker, or stay outside this project-I/O scope?
6. Should cosmetic view-sidecar saves wait for confirmation, queue as best-effort work, or flush during project/app teardown?
7. How should the GUI present partial multi-file failures after work becomes asynchronous without changing current recovery behavior?
8. What timing points and workloads will prove that GUI blocking moved off-thread, including cold or slow-disk cases?
9. Should the project thread publish an immutable project snapshot through `std::atomic<std::shared_ptr<T>>`, or should all reads use queued requests/completions? If a snapshot is used, what exact value type is immutable and when is it replaced?

## Change Log

### 2026-08-24

- Created this durable minutes file.
- Recorded the performance goal and the requirement to retain all later decisions and open questions.
- Recorded the settled dedicated-`QThread`, worker-`QObject`, GUI-facing injected object design.
- Recorded that the object is not merely a file watcher; its name and injection receivers remain open.
- Recorded the settled goal that no project reads or writes remain on the GUI thread, while keeping disk and CPU processing time distinct.
- Recorded the direction to keep `DecompProject` worker-owned, its non-I/O retained/query behavior, and the value/snapshot handoff requirement.
- Recorded that all 19 UI-owned direct sites move behind the one injected object and that `MainWindow` orchestration will be replaced rather than preserved site by site.
- Recorded the open immutable-snapshot option and the limits of `std::atomic<std::shared_ptr<T>>`.
- Verified the current local `fork-main` production call paths and inventoried project reads, writes, scans, probes, sidecars, imports, creation/deletion, previews, and hidden Porya loader I/O.
- Recorded the separate async voicegroup branch's narrower scope.
- Recorded the one-thread head-of-line warning and left specialized-worker retention unsettled.
- Chose `ProjectIo` as the initial GUI-facing module name and implemented the first project-open slice on `feature/project-io-thread`.
- Added `src/project/projectio.{h,cpp}`. `ProjectIo` owns one `QThread`; its private worker owns the live `DecompProject`, opens projects serially, and returns a copied `ProjectSnapshot` on the caller object's thread.
- Made project-open requests latest-wins through a generation number, so a superseded open cannot install stale state. Shutdown invalidates pending results, quits the worker event loop, and waits for the thread.
- Kept this slice out of `MainWindow`: startup injection, loading-state UI, and migration of the other project-I/O flows remain future work.
- Did not merge `integrate/async-voicegroup-loading`. Reused only its proven thread lifecycle, queued handoff, stale-result, and completion-delivery patterns.
- Added `projectiocheck`, first observed failing compilation without the new public header, then verified queued completion, caller-thread delivery, copied snapshot lifetime, track-budget data, failure reporting, and stale-result suppression.
- Review fixes keep callbacks on the facade thread, stage a candidate `DecompProject` until the current request is accepted, preserve the prior live project after failed or stale opens, and key track budgets by song label rather than a reload-sensitive vector index.
- Settled song-open sequence: empty `SongView` tab first; MIDI parse and voicegroup load both on `ProjectIo`; independent GUI binds; tab close cancels that session's requests.
- Settled empty `SongView` contract: display-only until both binds; paint-only `Loading...`; no overlay widget; sidecar after MIDI.
- Settled load-failure policy: tear the speculative tab down; cancel the sibling request; free late `LoadedVoiceGroup*` on the GUI thread.



