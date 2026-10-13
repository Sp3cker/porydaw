# Plan: Split Studio — drumkit and keysplit voice editing

Worktree: `.worktrees/swift-sample-library` (branch `feature/swift-sample-library`).
Binding product/architecture decisions: `local://split-studio-decisions.md`
(user-confirmed 2026-10-12). Controller rulings r1 (R1–R26, applied
throughout; R25's fact-check fixes — traceability rows, six open-choice
citations, range drift — are applied in place without per-site labels):
`local://split-studio-plan-rulings.md`. Agreed behavior, vocabulary and
every forward interface: `spec.md` in this directory. Briefs link to both
and carry deltas only.

## What lands

A modeless **Split Studio** window (Tools → Split Studio…) that edits drumkit
(`voice_keysplit_all`) and keysplit (`voice_keysplit` + table) voices: shared
sample library left, marker-based waveform slicing top-right, MIDI key-range
zone editor bottom-right. Slices are rendered sample assets with baked
declick; zones map keys to slices with pitch/pan/ADSR; the draft keeps both
mode views alive with a window-local undo stack; Save to Song is one song
undo step that registers slice samples (which survive undo and become
orphan-eligible) and applies parent slot + sub-group + table atomically.
Song-side sync (voicegroup-switch guard, close prompts, conflict bar, orphan
cleanup) and a manual page complete the surface.

New modules `PorydawSampleUI` (`src/swift/sampleui/`) and `PorydawKitStudio`
(`src/swift/kitstudio/`) are extracted/created along the way; Sample Studio's
waveform migrates onto the shared marker-list waveform. Lower modules gain
the kit capabilities first (Sample → Voicegroup/Project/Document).

## Task table

| # | Task | Route / seat | Justification (triage signals) |
|---|------|--------------|--------------------------------|
| 1 | PorydawSample: zero-crossing snap, slice render/declick, shared rate policy | SDD-track · `sdd-implementer` | New DSP with numerical invariants + one policy extraction consumed by 6/8; interface work |
| 2 | PorydawVoicegroup: keysplit table writer + store kit edit (+ public blank-line constant) | SDD-track · `sdd-implementer` | Multi-file with an interface between writer/store and three on-disk formats; judgment work |
| 3 | PorydawProject: kit-edit wrapper + usage scan + batch registrar + orphan delete | SDD-track · `sdd-implementer` | Four related store-level capabilities with failure/atomicity contracts; multi-file |
| 4 | PorydawDocument: `applyKitEdit` + one `ServiceKitEditAction` + service routing | SDD-track · `sdd-implementer` | History-action semantics (authoritative replay, identity rebase) across session/service/store; correctness-critical |
| 5 | Extract PorydawSampleUI (library model, arbiter, `PcmAuditionPlayer`); edit floor recorded | SDD-track · `sdd-implementer` | Module surgery with decoupling seams; behavior must be preserved |
| 6 | Marker-list waveform + Sample Studio migration onto it | SDD-track · `sdd-implementer` | Redesign of a live editor surface onto a new model; interaction contracts must survive |
| 7 | PorydawKitStudio: module + kit draft domain (pure API, codec pins) + audition tone in AppAudio | SDD-track · `sdd-implementer` | New domain model + audio publication shape; lossless round-trip pins; architectural |
| 8 | `KitSourceSession`: sources, markers, slices, minting, rates | SDD-track · `sdd-implementer` | Split from old task 8 at its interface seam (R17): independent state machine with its own check rows; multi-file judgment work |
| 9 | `KitStudioPresenter`: slot picker, zone views, conflict/retarget state, validation adapter | SDD-track · `sdd-implementer` | Large bridged surface with state-machine prompts (R17 split keeps one review unit); Swift-owned |
| 10 | App + QML: workflow, modeless window, editors, Tools action, routing gate, one shell lane, contrast registration | SDD-track · `sdd-implementer` | New modeless window + shell action + explicit routing mechanism; single behavior change over the file cap (named exception) |
| 11 | Voicegroup-switch sync: dropdown guard, slot follow, unguarded switch-back | SDD-track · `sdd-implementer` | R17 split of old task 10 at the session-lifecycle seam: one integration path (dropdown), prompt state machine |
| 12 | Close prompts + orphan cleanup (session registry, quit sequencing) | SDD-track · `sdd-implementer` | R17 split: close-path integration + destructive-delete guards across session close seams |
| 13 | Manual page `docsrc/manual/split-studio.md` | Direct | Single new doc file, content fully specified by spec.md; mechanical write, reversible |

Direct task 13 inline: **Target** — create `docsrc/manual/split-studio.md`.
**Change** — user-facing page covering entry (Tools → Split Studio…),
layout/modes/zones/slicing/audition semantics per spec §1–§18, Save to Song
as one undo step with files surviving undo (spec §20), voicegroup-switch/close
prompts (§22–§23), shared-kit copy default (§24), orphan cleanup (§25);
follow `docsrc/manual/sample-studio.md`'s heading style. **Acceptance** —
file exists, no other file touched; controller reviews content against
spec.md (no check run; documentation only).

## Decision → task traceability

| Decision (decisions file) | Task(s) |
|---|---|
| Name + Tools-menu entry only (Product §1) | 10 |
| Modeless, one window, song-bound, retarget prompt, title with • | 9, 10, 11 |
| Layout, draggable splitters, persisted geometry | 10 |
| Slot picker + New kit in empty slot N + `<vg>_kit<N>.inc` + table on Keysplit save | 2, 3, 9 (picker), 10 (creation + copy execution in save pipeline) |
| Mode toggle changes bottom editor only | 7, 9 |
| Both views kept alive; unstorables disabled; active view decides save | 7 |
| Keyboard 0–127, zoom/scroll, no overlaps | 7 (invariants), 10 (QML) |
| Drop → zone (1 key drumkit / extend keysplit); edge/body drags | 7, 10 |
| Map all slices from key + white-keys-only | 8 (session), 9 (command) |
| Zone strip: sample/root/Pitched/pan/ADSR | 9, 10 |
| Pitched semantics both modes (drumkit rising `key`) | 7 |
| Load-time collapse of identical slots; locked zones; table-run zones | 7 |
| Multiple sources, tabs, per-source persistence, closable | 8, 10 |
| Marker add/move/remove; Slice selection; no grid/transients | 6 (model), 8 (session) |
| Zero-crossing snap default ON, bounded | 1, 8 |
| Baked declick: fade-out ≤4 ms default, fade-in off, per-slice overrides | 1, 8 |
| Slice names `<source>_NN`, renamable, collision rules; per-source rate | 8 (minting via 1's policy + 3's validation adapter, wired in 10) |
| Slice click plays; key click plays draft from memory with pitch/pan/ADSR; no live MIDI | 5 (player), 7 (tone), 9 (playSlice/playKey), 10 (wiring) |
| Window undo stack; focus-gated routing; dies with window | 7 (stack), 10 (explicit gate + shortcuts) |
| Save to Song = ONE undo step; registrations at that moment (sibling `.wav` first); files survive undo | 3, 4, 10 |
| Song-side kit change: silent reload / Changed-in-the-song bar (own-save suppressed) | 9 (bar state), 10 (observer + suppression tag) |
| Voicegroup switch: dropdown `hasUnsavedChanges(song:)` prompt; follow slot; switch-back bar | 11 |
| Close prompts (window/tab/project/quit); clean closes silently; quit waits | 10 (window close), 12 (tab/project/quit) |
| Shared kits "used by N"; edit-everywhere vs copy (copy default) | 3 (scan), 9 (prompt), 10 (copy executes in save) |
| Orphan cleanup: session-created + unreferenced; checklist; delete wav+registration | 3 (delete), 12 (registry is session-owned per R6, offering, checklist) |
| Architecture module table | 1–10 (per task; deps per spec) |
| Edit-floor before/after in `docs/BUILDING.md` | 5, 7 (controller-measured, controller-recorded) |
| Sample Studio waveform may be redesigned onto marker list | 6 |
| Verification budget ≤ 3 s; fast Swift + one shell QML check; rest smoke | all briefs + Verification gates |

## Global Constraints (read once; briefs carry deltas only)

- **Scope**: all edits inside this worktree only. No commits by implementers
  (the execution loop owns staging/checkpoints). No source changes outside a
  brief's Exact write set. Main checkout stays untouched; `external/` is
  never edited.
- **Gates**: implementers run **no** build/test/lint/format/baseline
  commands. The controller owns every command recorded in this plan.
  Read-only inspection (reads, greps, `git show`) is always allowed.
- **Verification reuse**: implementers reuse the commands recorded in each
  brief's Acceptance predicate / Controller verification without
  re-discovering them. The runtime budget below is fixed now (R7); if a
  change alters scope or a command proves stale, report the concrete
  mismatch and the revised verification — coverage is never silently
  narrowed.
- **Language/framework**: Swift 6 strict concurrency per `rule://swift-standards`
  (`private` by default, `final`, `guard let`, domain errors, no test
  sleeps, `@MainActor` at the type). QML per repo conventions: versionless
  imports, `required property` delegates, `Connections` function syntax,
  `model.X` only in `QListModel`-backed delegates. No new C/C++.
- **QtBridge**: `rule://qtbridge-surface` and `docs/old/qtbridge-surface/spec.md`.
  Bridged declarations in class bodies (not extensions); QML-facing state
  public; unsupported stored types need `@QtTracked` (including the stored
  `Optional<MarkerWaveformModel>`); Swift-only stored members are
  `@QtIgnored` (never on `private`/`static`); no `@QtTracked` on supported
  Int/Bool/String members (R22); slot returns `Optional<T>` for nilable
  bridged objects. `checks:bridge` and any baseline rewrite are
  controller-run. Types moved into `PorydawSampleUI`/`PorydawKitStudio` keep
  their QML URI via `qmlModuleAliases` (no QML edits merely for a move).
- **Module direction** (R2): the dependency graph must stay acyclic and
  point downward; every module dep is listed in spec.md with the symbol it
  provides. No dependency is ever added to reach code — the shared part
  moves down (`KitAuditionTone` lives in PorydawAppAudio per R1).
- **Audio**: no audio-thread changes; the existing generation/acknowledgement
  retirement protocol in `AudioSampleAudition` is the only ownership path for
  in-memory audition storage. Nothing decodes, renders or publishes from an
  audio callback. `publishKitTone` allocates only on the caller's context.
- **UI**: geometry derives from `applicationSession.baseFontPx` (`window.unit`)
  and `layoutSpaces`; no hard-coded pixel constants. Text colors come only
  from `GridPalette` (`colors`) pairs per `rule://text-contrast`; no literal
  text colors, no opacity dimming. The new window and the orphan dialog are
  registered in the shell text-contrast audit (R19). Window/splitter sizes
  persist only through the two named preference keys (spec §3).
- **Files/modules**: one concept per file inside the feature directories
  `src/swift/sampleui/` and `src/swift/kitstudio/` (the `src/swift/app/drawer/`
  model); `internal` by default, `public` only cross-module or QML-facing.
  Each new module's one-file edit floor is measured before/after and
  recorded in `docs/BUILDING.md` (controller-owned; tasks 5 and 7).
- **Registration is controller-owned** (R26): `CMakeLists.txt` edits (module
  targets, source lists, links, module-map includes), `PorydawQmlTypes`
  list appends and module aliases, `PdcSuite` enum + `CoreCheckDispatch`
  case + `checkcatalog.cpp` lane entry + check-runner calls,
  `ShellQmlEntries` lane and text-contrast entries, and baseline files.
  Briefs name only their Swift/QML/doc write sets.
- **Preserved flows**: Sample Studio behavior (import/edit/commit/reopen,
  lanes and objectNames), scalar voice editing and its merge policy,
  voicegroup save/reload, and the Tools → Import Sample route keep passing.
  Migrations are cut overs: the moved/generalized declarations replace the
  old ones; no shims, no parallel paths.
- **Docs**: the user-facing surface change adds `docsrc/manual/split-studio.md`
  (task 13) and `docs/BUILDING.md` module-floor rows (tasks 5/7,
  controller-recorded).
- **Proof ledgers**: none exist; this plan touches no `proof.*.txt`.

## Concurrency and checkpoints

Serial spine: 7 → 8 → 9 → 10 → 11 → 12 → 13 (each consumes the previous
interface; 11 and 12 share task 10's workflow/window files, so they are
serial too). Parallelizable waves given frozen interfaces: {1, 2, 5}, then
{3, 6}, then {4, 7}. Interfaces are frozen in `spec.md`; consumers cite
producer contracts, never implementations. Task 7 depends on task 2's
`kitBlankChildLine` (R3), which wave 1 provides.

Cross-task file reuses and their named checkpoints (R18):

- Task 8 consumes task 7's module/`KitDraft` interfaces — no shared files
  (task 8 writes only `KitSourceSession`).
- Task 9 consumes tasks 7–8 interfaces — no shared files.
- **M4 checkpoints task 10's accepted write set before tasks 11–12 re-edit
  `KitStudioWorkflow.swift` and `SplitStudioWindow.qml`.**
- Between tasks 11 and 12 (both re-edit the workflow/window), task 11's
  accepted state checkpoints with other ready work before 12 starts.

Checkpoint milestones:

- **M1** — after tasks 1–4 are accepted: lower modules complete, kit save
  path (Sample → Voicegroup → Project → Document) exercisable headless.
- **M2** — after tasks 5–6 are accepted: `PorydawSampleUI` live, Sample
  Studio migrated, full studio regression green (behavior-preserving gate).
- **M3** — after tasks 7–9 are accepted: KitStudio domain, source session
  and presenter; edit floor recorded; checkpoint the accepted union.
- **M4** — after task 10 is accepted: window live, lane + contrast entries
  green; checkpoint before tasks 11–12 reuse its files.
- **M5** — final handoff after tasks 11–13, final review, justified baseline
  changes and native smoke; checkpoints any remaining accepted work.

No per-task commit requirements; task completion, review and Git persistence
stay independent.

## Added-check runtime budget (R7; fixed now, sums ≤ 3 s)

| Task | Added check rows | Lane | Estimate (s) |
|---|---|---|---:|
| 1 | zero-crossing + slice-render + `SampleRatePolicy` rows | `samplecheck-render` | 0.05 |
| 2 | writer round-trip/replace/append rows | `projectstore-keysplits` | 0.10 |
| 2 | store kit-edit rows | `projectstore-editing` | 0.10 |
| 3 | batch/delete rows | `samplecheck-storage` | 0.10 |
| 3 | usage-scan rows | `projectstore-keysplits` | 0.05 |
| 4 | kit history rows | `swiftcore-bankhistory` | 0.10 |
| 7 | new lane `kitstudio-draft` (suite spawn + draft/codec rows) | `kitstudio-draft` | 0.45 |
| 7 | kit publication rows | `swiftcore-playback-audition` | 0.05 |
| 8 | source-session rows (same lane) | `kitstudio-draft` | 0.10 |
| 9 | presenter rows (same lane) | `kitstudio-draft` | 0.05 |
| 10 | new lane `shell-split-studio` (one undo step, files survive) | `shell-split-studio` | 0.85 |
| 10 | text-contrast audit: `split-studio` state × 2 modes (`vanilla`, `dark-neutral-high`) | `shell-text-contrast-split-studio-*` | 0.70 |
| **Total** | 0.05+0.10+0.10+0.10+0.05+0.10+0.45+0.05+0.10+0.05+0.85+0.70 | | **2.70** |


Coverage gaps created by the cuts (named, not silent):

1. **Cmd/Ctrl+Z + Cmd/Ctrl+S routing lane row** (R8 fallback): no permanent
   lane row fits the budget; routing is verified by native Cocoa smoke
   (task 10 Controller verification) over the explicit `active` +
   `activeFocusItem` gate.
2. **Presenter-row depth**: task 9's rows are trimmed to the state-machine
   essentials; exhaustive per-slot permutations stay smoke-only.
3. **Contrast breadth (F1)**: the audit registers the `split-studio` state
   for `vanilla` and `dark-neutral-high` only — the `immaterial` entry is
   cut to fit the ≤ 3 s budget (2.70 s as budgeted); the window's label/
   palette pairs under `immaterial` are smoke-verified in task 10's native
   pass. The orphan dialog is reached only via the `split-studio` audit
   state opening it — its separate opening path is smoke-verified in
   task 12.

Everything else sync-related (dropdown guard prompts, close flows, orphan
checklist UX, geometry persistence, audible output) stays temporary
controller smoke per the decisions' verification section; tasks 10–12 name
the scripts.

## Verification gates (exact; controller-run)

- Per-task NAMED CHECKS live in each brief's Acceptance predicate
  (`uv run --no-sync dev …` only). The one shell QML lane covers exactly:
  Tools menu → open Split Studio → add marker/slice → Save to Song → exactly
  one song undo step, with the slice `.wav` + registration surviving undo
  and the orphan query listing them (R4).
- Gates before M5: `uv run --no-sync dev checks:bridge`,
  `uv run --no-sync dev checks:qml-aot`, `uv run --no-sync dev format --check`
  on the changed lines, plus the full covering lanes named in briefs.
- Native smoke is controller-run against the real app (window focus and
  Cmd/Ctrl+Z/S routing, prompts, live audio, screenshots) — mandatory, not
  optional; honest blockers are reported.

## Open blockers

1. **Stale citation — `AudioAuditionVoices.resolvedVoice`.** The decisions
   file cites `AudioAuditionVoices.swift:83-92` as the draft-key audition
   mechanism. That file does not exist in this worktree (branch base
   `834642b5`): it lives on `origin/fork-main` only, at
   `src/swift/playback/audition/AudioAuditionVoices.swift:82-92` (verified
   via `git show origin/fork-main:…`), where `resolvedVoice` is a private
   helper of the accepted-chord-audition work. No user decision changes: the
   agreed *behavior* is implemented through the worktree's existing
   publication path — `AudioSampleAudition.publish`
   (`src/swift/app/audio/AudioSampleAudition.swift:63-90`) builds in-memory
   `ToneData`/`WaveData`, and `apply` (`:119-138`) plays it as the preview
   track's `currentVoice`, so a keysplit-all/keysplit wrapper tone
   (`publishKitTone`, task 7, R1) yields the engine's own rhythm-pan and
   fixed-key semantics (`m4a_track.c:413-422`). If this worktree rebases onto
   `fork-main` before task 7 starts, the implementer must re-check overlap
   with `AudioAuditionVoices` and reuse its accepted-audition allocation
   policy where it has become the owner — report instead of duplicating.

No other decision in `local://split-studio-decisions.md` was found
unimplementable; every other cited path/symbol was re-verified in this
worktree (see spec.md "Engine facts" and each brief's Context).
