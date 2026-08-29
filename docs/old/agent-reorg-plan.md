# Agent-Driven Reorganization Plan — Porydaw

*Status: partially authoritative. The **EditorSelectionModel cutover (§5)** and the **SongView surface extraction (§6)** are implemented. `docs/selection-model-spec.md` remains the normative behavior contract. Later waves (§7, §8) remain **directional only** — each requires its own reviewed detailed plan before any implementation begins.*

*History: the planning worktree `songview-selection-spec` was created from `fork-main`@`6dfa10c` (`6dfa10cdbdda067833bbda9b3cc746cb7dcfbab4`). The implemented architecture now lives in the `fork-main` working tree.*

## 1. Authority and status

The selection-model cutover (§5) and SongView surface extraction (§6) are implemented in the working tree. `docs/selection-model-spec.md` remains the normative behavioral contract for `EditorSelectionModel`. If current code or checks conflict with that spec, implementation must stop and resolve the discrepancy explicitly rather than silently changing the specification or behavior.

Later waves — the pitch-bend folder move (§7), the shell split (§8), and the document split (§8) — remain directional in this file. They are not approved execution plans and must not be treated as such until each receives its own concrete reviewed plan.

## 2. Motivation — why this pays for agents

**Porydaw is an agent-heavy repo** (30+ in-binary `--*check` harnesses, 6000L+ UI files). Every feature lands via an AI agent that must `grep → read → edit → verify`. The current layout taxes that loop:

| pain | cost to agents | evidence |
|---|---|---|
| **God files** — `songview.cpp:6767`, `mainwindow.cpp:3351`, `songdocument.cpp:2308` | One `read` is 266KB; elided `…` forces re-reads. `grep` for `velocity` returns 395 hits mixed with harness. Token cost ~6× a 400L file. | `wc -l` p95 >1700 vs 400L target |
| **Flat `src/`** — 41 `*.cpp` at root before the checks move, 34 of them `*check.cpp` | `grep pattern="pencil" path="src"` hit 7 harness files, 0 prod (prod is `songview.cpp`). Agents learn to narrow *after* timeout. | Bake-off control: `hit_harness 6/6` old flat vs `0/6` new `src/checks/` |
| **No routing** — no `AGENTS.md` map, no `path` discipline | Every probe did `path="."` or `path="src"` first try. | Bake-off old: 2/6 `root_scan:true`, 2/6 `used_broad_src:true` even after docs added |
| **Harness co-location** — checks beside prod code | `src/checks/samplecheck.cpp` pollutes `grep dr_mp3 path="src"` (53 hits vs 24 in `src/audio`) | `git ls-files src/*.cpp` counted checks as prod |

**Result of the checks reorganization already landed:** `git mv 42 → src/checks/`, `AGENTS.md` + `.omp/rules/scope-searches` (`NEVER path="src"`) + `keep-files-small` (200–400L target, 600L ceiling). Control bake-off: `hit_harness 6/6 → 0/6`, `root_scan 2/6 → 0/6`, first-try hits 395→38.

**Pitch-bend proves the pattern:** new UI went to *new files* `pitchbendeditor.cpp:453` + `pitchbendgraph.cpp:623` instead of +1k to `songview`. `songview` only grew +121 for the seam. Check landed correctly in `src/checks/pitchbendcheck.cpp`. That is the vertical slice the SongView work wants — but `pitchbendgraph:623` is already over ceiling and flat in `src/ui/` wants a folder.

**Payoff of finishing:** an agent fixing `velocity` touches `src/ui/songview/` + `src/core`, not `grep` inside 6767L. `git diff` is reviewable. `lsp references` is cheap. `deno task checks` / `tools/run_checks.ts` stays green.

## 3. Current state (measured 2026-08-16)

```
src/                # top-level now 6 files after the checks move (was 41)
  main.cpp, mainwindow.{h,cpp}, porydaw_scale.{h,cpp}, songsession.h
src/checks/          # harness root — never add *check.cpp to src/
src/ui/
  songview.cpp:6767       # god #1
  mainwindow.cpp:3351     # god #2 (via src/mainwindow.cpp)
  pitchbendeditor.cpp:453 / .hpp:104  + pitchbendgraph.cpp:623 / .hpp:129  # flat, wants src/ui/pitchbend/
  editordrawer/            # MODEL — 200-400L per file, one gesture per file
  theme/, activity/, ...    # OK
src/core/songdocument.cpp:2308 (+19 bend)  # god #3
```

This snapshot is historical context for the directional waves. The authoritative selection wave below is scoped to selection state only and does not reorganize folders or move files.

## 4. Target architecture — feature slices > layers (directional)

Keep layers, split the monsters vertically. One file = one concept. This is the long-run destination, not an instruction to restructure anything during the selection wave.

```
src/
  app/                 # main.cpp + applicationstartup.*
  core/
    document/          # SongDocument: document.{h,cpp} (~300L facade), notes.*, lanes.*, time.*, commands/
    timeline/          # miditimeline.*, timelineplayer.*, midiimport.*
    smf/               # smf.*, mid2agbtables.*
    scale/             # porydaw_scale.*
  project/             # keep — DecompProject, SongRegistry, VoicegroupSource, SampleReg
  audio/
    engine/            # audioengine.*
    dsp/               # resonance_suppressor.*, sampledsp.*
    import/            # sampleimport.*, sf2reader.*, samplewav.*
  ui/
    shell/             # mainwindow 3351 → mainwindow.{h,cpp} (frame) + tabs.*, project_ops.*, voicegroup_ops.*, playback_ops.*, catalog.*
    songview/          # 6767 → per-surface folders/modules (pianoroll/, trackheaders/, timeruler/, …); split a surface only when it exceeds 200–400L
    pitchbend/         # pitchbendeditor.* + pitchbendgraph.* → pitchbend/{editor.*, graph.*, popup.*}
    editordrawer/      # keep as template
    theme/, shared/, activity/  # keep
  checks/              # DONE — single harness root, never add *check.cpp to src/
CMakeLists.txt         # → per-folder CMakeLists or GLOB once splits stabilize
```

Rules (already in `.omp/rules/`):
* `scope-searches`: `NEVER grep without path`, `NEVER path="src" or path="."`, smallest owning folder (`src/core`, `src/audio`, `src/ui/songview.cpp`, `src/checks`)
* `keep-files-small`: 200–400L target, 600L ceiling, `editordrawer/` as model, don't create 80L fragments

## 5. Authoritative wave — EditorSelectionModel cutover

### Scope and normative source

The complete cutover extracts the canonical editor selection state into one concrete module. All behavioral detail — ownership, the four canonical fields, transition semantics, coverage projections, the notification contract, and the acceptance matrix — lives in `docs/selection-model-spec.md`. Do not restate or redesign that contract here; this section is the execution checklist, not the specification.

Runtime ownership stays `SongSession → SongView`, with `SongView` owning one `EditorSelectionModel`. `SongDocument` keeps musical data, commands, revision, and undo. The four canonical fields move together to avoid two sources of truth:

| Canonical field | Current `SongView` storage (`src/ui/songview.h`) |
|---|---|
| Primary Track | `int m_selectedTrack` |
| Track Scope | `uint32_t m_trackSelMask` |
| Note Selection | `std::vector<NoteId> m_selection` |
| Time Selection | `SongView::TimeSelection m_timeSel` |

`SongView::TimeSelection` itself — the nested `struct` (`Scope {Tracks,Lanes}`, `startTick`, `endTick`, `lanes`, `active()`) — migrates to the model's public surface.

The cutover leaves exactly three selection interfaces (spec §"Coordination seam: three interfaces"): the model's direct state interface, deep `SongView` coordination commands, and the private `SongView` notification coordinator. Thin pass-throughs are prohibited.

**Direct pass-throughs — replace with the `EditorSelectionModel` interface and remove from `SongView`**:

- `selectedTrack()` → `primaryTrack()`.
- `trackSelectionMask()` → allocation-free `storedTrackScope()` and `resolvedTrackScope(uint32_t usedMask)`.
- `selection()` → `noteSelection()`; `setSelection(...)` / `clearSelection()` → model mutations; `isSelected(const ViewNote&)` → `isNoteSelected(NoteId)`. `ViewNote` track/projection checks stay in the surface; the model depends only on opaque note identity.
- `timeSelection()` / `setTimeSelection(...)` / `clearTimeSelection()` → model queries and mutations; coverage becomes `timeSelectionCoversTrack(int, uint32_t usedMask)` and `timeSelectionCoversLane(int, uint8_t, uint32_t usedMask)`.

Migrated model methods never read `MidiTimeline` internally. Callers supply the allocation-free `uint32_t` used-track mask required by resolved scope and coverage queries.

**Retained deep coordination commands — stay on `SongView`, delegate only the canonical mutation to the model.** Each performs required non-selection orchestration (interaction/popup cancellation before the model mutation, then post-mutation notification coordination), so it is not a forwarding shim:

- `selectTrack(int)` and `trackHeaderClicked(int, Qt::KeyboardModifiers)` — application-facing track and scope commands. `trackHeaderClicked` translates Qt modifiers into the model-owned `TrackScopeAction { Plain, Toggle, Range }`; `EditorSelectionModel` does not accept Qt event or modifier types.
- `transitionSelectedTrack(int)` / `transitionSelectedTrack(int, bool)` — the private real Primary Track transition coordination.
- `revealNote(int, uint8_t, uint64_t)` — application-facing note reveal.
- Lifecycle entry points `setSong`, `updateSong`, `setDocument`, and `onTracksRemapped` — also deep coordination commands. They keep SongView-owned lifecycle work, delegate canonical selection mutations to the model, and obey the same pre-mutation cleanup and post-mutation notification rules.

A retained method that degenerates into a bare model call is removed, not kept.

### Build surfaces

Implemented files and wiring:

- **Model** — a concrete source/header pair at `src/ui/songview/editorselectionmodel.{h,cpp}` (200–400L target, 600L ceiling). It may use `NoteId` (`src/core/noteid.h`) and `TrackRemap` but must not retain a `SongDocument`, `MidiTimeline`, `SongViewModel`, or widget pointer (spec §"Ownership and seam").
- **Focused check** — `src/checks/selectioncheck.cpp`, testing the model through its public interface (never private fields or source text).
- **Check harness and CLI dispatch** — wired via `porydaw_checks`: forward-declared in `src/checks/fwd.hpp`, registered with its handler and `--selectioncheck` flag in `src/checks/checkregistry.cpp`, and executed through `src/checks/checks_main.cpp`.
- **Build** — `CMakeLists.txt`: `src/ui/songview/editorselectionmodel.{h,cpp}` is added to the `porydaw_app` library target, and `src/checks/selectioncheck.cpp` is built into the `porydaw_checks` executable target (which links `porydaw_app`).
- **Every production caller** — SongView's extracted surfaces under `src/ui/songview/` (PianoRoll, TimeRuler, TrackHeaders), `EventListView` (`src/ui/eventlistview.cpp`), `AutomationPage`/`AutomationRows`/`AutomationArea`/`AutomationPaint`/`AutomationHover` and `VelocityArea` (`src/ui/editordrawer/`), and application-facing callers (`src/mainwindow.cpp` self-test).
- **Every direct check caller** — `hostcheck`, `eventviewcheck`, `rollcheck`, `rollcheckautomation`, `rollcheckdrawer`, `rollcheckpsgvelocity`, `pitchbendcheck`, `viewcheck`, `mainwindowroutingcheck`, `tabcheck`, `vgsavecheck`, and `automationgesturecheck` under `src/checks/`. These caller lists are baseline routing aids, not exhaustive proof: run `lsp references` on each migrated symbol plus scoped `src/ui` and `src/checks` searches as the actual completeness gate.

`src/ui/editordrawer/` and `EventListView` are already separate modules: migrate only their selection access, do not reorganize them as part of this wave.

### Migration rule — clean cutover

- Before modifying any exported symbol, run `lsp references` on it. Missed callsites are bugs.
- No parallel `SongView` selection state: do not leave a second source of truth beside the model.
- No compatibility shims or obsolete forwarding methods. Temporary `SongView` forwarding is allowed only during the atomic caller migration and is removed before the wave is complete.
- The private `SongView` notification coordinator is allowed: it maps one consolidated post-invariant model notification to widget refresh, focus, and application signals. It is not a selection forwarding interface — `SongView` stores no canonical selection and exposes no selection pass-through getters or mutators after cutover (spec §"Notification contract").
- Preserve ordering inside every retained coordination command: interaction/popup cancellation happens before the model mutation; the post-invariant notification is too late for pre-mutation cleanup (spec §"Transition semantics").
- Preserve the spec's `TrackRemap` ordering and seam rules (spec §"Track remap", §"Ownership and seam"): compute every remapped value into locals; commit SongView-owned remapped state (clipboard, mute/solo, cosmetic `EditorViewState`) without refresh or signals; then invoke the model's notifying remap so the private coordinator sees the complete batch and publishes selection-driven refreshes and `selectedTrackChanged`; finally publish the remaining non-selection signals (`muteMaskChanged`, `soloMaskChanged`, `editorDrawerStateChanged`). An emitting helper such as `setEditorViewState` must not run before the batch is committed. Used-track context crosses the seam only as an allocation-free `uint32_t` mask.
- No stale check callers: after migration, the old symbols must have zero references.
- Keep interaction preview state outside the canonical model; keep selection predicate queries allocation-free in paint and pointer-move paths (spec §"Canonical selection versus interaction state", §"Notification contract").

### Verification gates

Run in order; a failure stops the wave.

1. **Baseline capture** — before edits, run the existing checks named by the spec's acceptance matrix and record pass/fail, so the cutover can be proven behavior-preserving.
2. **Build** — `cmake --build build --target porydaw porydaw_checks` succeeds.
3. **Selection check** — run `QT_QPA_PLATFORM=offscreen ./build/porydaw_checks --selectioncheck`.
4. **Acceptance matrix** — run every check family named by `docs/selection-model-spec.md` §"Acceptance matrix" using the spec's explicit dispatch map (for example `rollcheckautomation` → `--check-automation`, `rollcheckpsgvelocity` → `--check-velocity-page`, `hostcheck` → `--check-host-adapter`/`--check-host-seams`, `mainwindowroutingcheck` → `--check-mainwindow-routing`/`--check-host-integration`).
5. **Formatting** — `deno task format:check` passes.
6. **Obsolete references gone** — `lsp references`/`grep` on the migrated `SongView` selection symbols returns no remaining callers.

`tools/run_checks.ts` (`deno task checks`) provides necessary broad regression evidence across the test suite but does not run every specialized acceptance harness; it cannot substitute for the explicit `--check-*` runs in gate 4.

Any discrepancy between current code/checks and the normative spec stops the wave for explicit resolution — never silently change the spec or the observed behavior.

### Ownership and parallelism

One implementation owner controls `src/ui/songview.h`, `src/ui/songview.cpp`, and the model seam. No one else edits those files during the cutover. Parallel work starts only after the model interface is fixed, and only on independent callers or checks (e.g. a second agent migrating `EventListView` or a focused check once the header is stable).

## 6. Implemented SongView surface extraction

The SongView surface extraction has been fully implemented under `src/ui/songview/` and `src/ui/songview.{h,cpp}`. `SongView` is reduced from a 6767L god file to a ~580L coordinating facade handling widget composition, lifecycle/view-state coordination, and application-facing signals.

### Implemented layout and files under `src/ui/songview/`

The extraction splits SongView into per-surface modules, shared data/geometry helpers, and dedicated coordination files:

1. **Per-surface modules**:
   - **PianoRoll surface** (`pianoroll.h`, `pianoroll.cpp`, `pianoroll_geometry.cpp`, `pianoroll_paint.cpp`, `pianoroll_interaction.cpp`, `pianoroll_commands.cpp`): Split vertically into layout/geometry, note rendering, gesture interaction, and note command execution because PianoRoll is complex and each aspect warrants its own focused 200–500L file.
   - **TimeRuler surface** (`timeruler.h`, `timeruler.cpp`, `timeruler_paint.cpp`, `timeruler_interaction.cpp`): Split into the ruler widget shell, timeline ruler painting (markers, loop region, time signatures), and scrubber/loop interaction.
   - **TrackHeaders surface** (`trackheaderpanel.h`, `trackheaderpanel.cpp`, `trackheaderrow.h`, `trackheaderrow.cpp`): Split into the panel container and individual track row widgets (track selection, mute/solo, activity meter, layout, and interaction).
   - **OtherStrip surface** (`otherstrip.h`, `otherstrip.cpp`): Dedicated strip widget for bottom timeline lane and automation items.
   - **VoicePicker surface** (`voicepicker.h`, `voicepicker.cpp`): Dedicated popup/dropdown widget for track voice selection.

   *Cohesion rationale:* `OtherStrip`, `VoicePicker`, and `TrackHeaders` rows/panel stay cohesive in their respective files rather than splitting further into separate geometry/paint/interaction files because finer splits would produce tiny fragments under 100–200 lines, violating the 200–400L file size principle.

2. **Data, geometry, timeline state, and editing helpers**:
   - `camera.cpp`: Viewport coordinate transforms, zoom scaling, scrolling, and cursor anchoring.
   - `grid.cpp`: Beat-grid calculations, subdivision intervals, painting support, and tick snapping.
   - `viewstate.cpp`: Scale projection, editor view state, lane display state, and velocity-gesture coordination.
   - `detail.h`, `detail.cpp`: Shared layout and metric helpers (pixel scaling, wheel deltas, hit-padding, used-track masks, scale-folding logic, and key names).
   - `rangeedit.cpp`: Multi-track range edit operations (cut, copy, paste, delete, transpose, and time insertion).
   - `editorselectionmodel.h`, `editorselectionmodel.cpp`: Canonical selection model (track scope, note selection, time selection, and primary track).

3. **SongView responsibility files**:
   - `src/ui/songview.h`, `src/ui/songview.cpp`: Coordinating shell handling widget composition, lifecycle updates, event routing, playhead state, and application-facing Qt signals.
   - `trackvoiceops.cpp`: Track selection and remapping, mute/solo state, voice operations, and audition routing.
   - `drawercoordination.cpp`: Coordination between SongView and the velocity and automation editor-drawer pages.

### Structural rules maintained

- **No global replacement god files:** Global `songview_painting.cpp` / `songview_interaction.cpp` files remain strictly prohibited — a replacement god file is not a modular split.
- **File size discipline:** Each file targets 200–400 lines (with a 600L ceiling), keeping concepts cleanly separated and agent-navigable without gratuitous fragmentation.

## 7. Deferred waves — pitch-bend folder and docs cleanup

The pitch-bend folder move (`src/ui/pitchbendeditor.*`, `src/ui/pitchbendgraph.*` → `src/ui/pitchbend/`) and unrelated `AGENTS.md`/rule-count documentation cleanup are deferred. They are **not** prerequisites for, and must **not** be combined with, the authoritative selection wave. Each remains a separate small commit when it is later approved.

## 8. Shell and document splits (directional)

- **Shell split:** `mainwindow.cpp:3351` → `src/ui/shell/{mainwindow.* (frame), tabs.*, project_ops.*, voicegroup_ops.*, playback_ops.*, catalog.*}`.
- **Document split:** `songdocument.cpp:2308` → `src/core/document/{document.*, notes.*, lanes.*, time.*, commands/}`.

Both are directional; neither is approved for execution here.

## 9. AGENTS.md strategy (directional) — router + on-demand

* **Root `AGENTS.md` (auto-loaded, keep ~80L)** — project map + routing table, not full docs.
* **Sub-files on demand** — `src/ui/songview/AGENTS.md`, `src/core/document/AGENTS.md`, `src/audio/AGENTS.md` — ~20L each, read only when task matches. Enforced by `.omp/rules/read-feature-guide` (Before editing `src/ui/songview/*`, read that `AGENTS.md`).

Root routing to add (a future docs commit, not part of the selection wave):
```
- Piano roll / notes / velocity / songview → read src/ui/songview/AGENTS.md
- SongDocument / time / undo             → read src/core/document/AGENTS.md
- Voicegroup / samples                   → read src/project/AGENTS.md
- Playback / engine / DSP                → read src/audio/AGENTS.md
- Pitch bend                             → read src/ui/pitchbend/AGENTS.md
- Theme / layout                         → read src/ui/theme/AGENTS.md
- Harnesses                              → read src/checks/AGENTS.md
```

## 10. Why this organization suits agents

* **Token cost:** 400L ≈ one `read` without elision; 6767L costs 6× and forces re-reads. Smaller files = cheaper, faster `lsp`.
* **Discoverability:** `glob src/ui/songview/` lists 6 candidates, not `grep pencil` across 41 files with 35 harness hits. Routing table makes `grep path="src/ui/theme"` the first try.
* **Conflict isolation:** feature folder = task boundary. Two agents can own `src/ui/songview/` and `src/audio/` without touching the same file. `git mv` renames are `100%` (no content change) until split.
* **Proven:** `src/checks/` move + bake-off is the evidence. Pitch-bend's `src/checks/pitchbendcheck.cpp` landing correctly is the first field proof.

## 11. Risks & non-goals

* Don't create 80L fragments — 40 tiny files in one feature is also undiscoverable. Keep 200–400L.
* Don't add speculative abstractions — minimum code that solves the problem (`~/.claude/CLAUDE.md` Simplicity First).
* Not general DAW features — m4a-native constraints only (SPEC.md §1 non-goals).
* The selection wave is a behavior-preserving cutover only: no new gestures, shortcuts, colors, undo changes, camera/grid/painting refactors, or `src/ui/editordrawer/` reorganization.

---
*Next implementer: §5 (EditorSelectionModel cutover) and §6 (SongView surface extraction) are implemented. Remaining waves (§7 pitch-bend folder, §8 shell/document splits, §9 AGENTS.md routing) remain directional until individually planned and reviewed.*
