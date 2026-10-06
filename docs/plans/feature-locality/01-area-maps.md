# Plan 01 — Area maps (lever: cause g; fixes discovery in 9 of 12 traced questions)

Route: **Direct** for every task (doc writes, mechanical, reversible; no build surface).
Model: `src/swift/app/drawer/README.md` (the repo's existing anatomy map). Evidence: Q5
(map-covered) read 2 files / 629 opened vs Q2 (same shape, unmapped) 12 / 4,013 (wc-verified).

## Verdict

Maps are the cheapest measured lever: they do not shrink files, they collapse *discovery* —
wrong-fragment opens (`SongTabsController+Close` 291 ln for 0 needed), negative-finding sprawl
(Q4 opened TimeAxis+GridGeometry ~480 ln to prove tempo does not feed the grid), registry reads
(Q12: 643-line CMake for 20 needed lines), and entry-route hops an agent opens only to learn they
forward. Draw the map once, name the decisive file, state the negative facts.

## Tasks (all Direct; controller verifies)

| # | Task | Write set | Route |
|---|---|---|---|
| 1 | Roll anatomy map | `src/swift/app/roll/README.md` (new) | Direct |
| 2 | Timeline + tempo facts map | `src/swift/document/view/timeline/README.md` (new) | Direct |
| 3 | App shell/session anatomy + flows map | `src/swift/app/README.md` (new) | Direct |
| 4 | Checks map | `src/checks/README.md` (new) | Direct |
| 5 | Drawer README commit-row fix | `src/swift/app/drawer/README.md:86` | Direct |

### Task 1 — Roll anatomy map

Write `src/swift/app/roll/README.md`, drawer-README shape: file table (one row per file, types +
ownership), "Where to change X" table, negative facts. Required rows (from Q1/Q6/Q10 traces):
- `PianoGrid.swift` — bridged surface (`@QtBridgeable` body: tracked props incl. `drawThreshold`
  :47-51, gesture state), wrapper slots.
- `PianoGrid+Gestures.swift` — pointer orchestration + `GridGesture` state machine (folded by
  swift-token-cost plan 02); draw-to-`addNote` pitch construction :407-420 (the scale-snap feature
  seam, with `MusicalScale.isPitch`/`pitch` at `src/swift/core/MusicalScale.swift:35-69`).
- `PianoGrid+SceneSync.swift` — scene sink: `sceneInput()`/`refreshNotes()` seam; NOT gesture policy.
- `GridScene+Notes.swift` / `GridScene+Rebuild.swift` — scene rebuild tiers.
- `RollRulerBuilder.swift` — ruler tick/label policy (zoom thresholds, collisions) :46-224.
- `RollPlotBuilder.swift`, keyboard/plot builders — adjacent, one row each.
- Adjacent-area pointers: `RulerMenuPresenter` (app/timeline), `EditorRulerBand.qml`
  (ui/songview/quick/swiftroll) — forwards only.
- "Where to change X": drag threshold → `PianoGrid.drawThreshold` + `PianoGrid+Gestures`
  :102-120/:629-635; note insert overlap rule → `core/NoteEditing.addNotes` +
  `core/NoteCollision` (covered/trim/untouched); ruler beats → see timeline map (Task 2).
- Negative fact: activation/decision never lives in SceneSync/Rebuild (forwards).

### Task 2 — Timeline + tempo facts map

Write `src/swift/document/view/timeline/README.md`. Required content (from Q1/Q4):
- Rows: `TimeAxis.swift` (bar/beat enumeration, signature segments — pinned port of
  `src/ui/songview/timeaxis.h/.cpp`; do not restate its arithmetic), `GridGeometry.swift`
  (subdivision resolution/feel, beat-line weight), `DocumentProjectionCache.swift` (revision→
  `TimeMap`/`TimeAxis` projection), `EditorCamera.swift`, and pointers to core meter/tempo owners.
- **Negative facts (the Q4 win):** tempo (`SongState.tempo`, µs/quarter) affects playback timing
  only (`core/PlaybackTimeline` conversion, consumed by `playback/Sequencer`); it does NOT move
  bars/grid — spacing derives from `ticksPerBeat` + `timeSignatures` via `TimeAxis`. BPM display
  rounding lives at the two projections (automation lane, event list).
- Meter pointer: signature-beat math is `signatureBeatTicks` — `core/PlaybackTimeline.swift:146`
  today, `core/Meter.swift` after plan 02 lands (cite Meter.swift once it exists).
- "Where to change X": ruler beat labels → `RollRulerBuilder` + `TimeAxis.forEachGridLine`;
  grid density → `GridGeometry`; time-sig edit → `ApplicationSession+Ruler` prompt +
  `document.setTimeSignature`.

### Task 3 — App shell/session anatomy + flows map

Write `src/swift/app/README.md`. Required content (from Q3/Q8/Q9/Q11):
- `ApplicationSession.swift` + each `+Aspect` file in one table row apiece, naming what the aspect
  owns: `+Commands` (save/undo/redo requests, conflict prompt), `+Tabs` (open/replace/new-tab
  policy `openSongFromDock` :132-144 with `startOpen` at :150, workspace creation),
  `+ProjectOpening` (project switch/startup restore — NOT ordinary song open), `+Close`, `+Audio`,
  `+Ruler` (time-sig prompt impls), `+Catalog`, `+Samples`. State the QtBridge fact: bridged
  members/forwarders live in the class body; impls in extensions (cause d — where to read vs
  where it decides).
- Entry routing row: `ShellPresenter.activate(id:)` — dispatch switch `shell/ShellPresenter.swift:155-206`
  — is THE dispatch; `KeybindingRegistry.swift:21-150` is the binding catalogue; QML `Shortcut`
  repeater `ui/shell/ShellContent.qml:68-76`. Mixed routes noted: `transport.play` →
  `transportBarPresenter().play()`, `transport.play_pause` → `session.playPause()`.
- Flows ("Where to change X" shape):
  - Save: `+Commands.requestSaveImpl` :101-124 → `DocumentSession.save` :252-269 (gates:
    `document.isDirty || bankDirty`; in-flight bank ops reject; MIDI conflict unless forced) →
    `ProjectService+Bank.swift:175-201` (bank stage → MIDI write → flags iff `flagsNeeded`) →
    `MidiCfg.writeSongFlags` :78-90 (midi.cfg vs songs.mk fallback via `SongsMk`). Negative
    facts: normal save never writes `.asm`/registration (`SongRegistration+Writes` is the
    register-song flow); mute/solo never dirties (session-only state).
  - Open: `SongsPanel.qml:157-168` (click=select, dblclick=activate) → `SongDockController`
    :103-108 → `ApplicationSession+Tabs.openSongFromDock` (:132-144 policy: existing song→existing
    tab, plain activation replaces the selected tab's document via `requestReplacement` :140,
    new-tab appends; serialized by `startOpen` :150) → `DocumentSession.open` :232-246 →
    `ProjectService.openSong` → `ProjectStore+Open` :48-103.
    Negative fact: nothing closes; replacement swaps the selected tab's document.
- `NativeAudio.swift` row: thin facade over `device.renderer` (AppAudio); open it only for facade
  membership, never for policy.

### Task 4 — Checks map

Write `src/checks/README.md`. Required content (from Q12 + catalog facts):
- Directory → feature coverage table (velocity → `velocity/`, `drawerpresentation/`, `keyboard/`,
  `rollcheck/` [INFERENCE on editorqml velocity presence — verify when writing]; automation →
  `automation/` + `drawerpresentation/`; etc. — enumerate by globbing `src/checks/`).
- The two registries: Swift check sources list `src/checks/CMakeLists.txt` (`swift_core_check`
  SOURCES ~:103-322) and suite/catalog rows `src/checks/checkcatalog.cpp` (38 entries;
  `swiftSuite("swiftcore-…", suite)` :117-135). Rule: adding a slot to an existing suite edits
  Swift sources + CMake list only; a new command also edits `checkcatalog.cpp`;
  `checkregistry.cpp` serializes, never edit for this.
- Lanes: `deno task checks --filter swiftcore` (native harness suites), `checks:shell` /
  `checks:qml` / `checks:qml-roll` (QML lanes), `checks:bridge`.
- Manifest: generated at run time by `tools/run_checks.ts` from `--manifest`; no checked-in JSON.

### Task 5 — Drawer README commit-row fix

`src/swift/app/drawer/README.md:86` — the velocity commit row says `VelocityPage.commitVelocities`;
the function is `VelocityInteraction.commitVelocities` (private, `velocity/VelocityInteraction.swift:421-424`)
→ `session.document.setVelocities`, reached from gesture release (:409-413) and prompt acceptance
(:292-293). Replace the row with that chain (the qualified name, not just the file, was wrong).

## Acceptance predicate (controller-run; no automated check covers doc accuracy — named gap)

1. Every path and `file:line` cited in the four new maps resolves (spot `glob`/`read` of ≥10
   citations per map, scoped `grep` with `path`).
2. Re-trace Q11 with only the app map: the tab-policy answer must be reachable in ≤3 files
   (SongsPanel.qml, SongDockController, ApplicationSession+Tabs) without opening
   `SongTabsController+Close` or `+ProjectOpening`.
3. Re-trace Q4's negative fact from the timeline map alone: no `GridGeometry` open needed.
4. **Keep-honest step (review checklist, not CI):** any change that touches a file a map covers
   re-resolves that map's citations for the touched rows (same scoped grep/read as above) as part
   of review — maps rot silently otherwise; creation-day checks do not keep them true.
5. `deno task format --check` — no-op for `.md` (name it; swift-format touches Swift only).
No `deno task build:*` required: no compile unit changes (build-neutral by construction).

## Task-specific constraints

- Maps state ownership and negative facts; they do not prescribe code changes.
- Every map row cites `file` (+ line ranges for decisive seams); no unverified symbols —
  re-grep at write time; if a cited line has drifted, fix the citation, not the code.
- Keep each map ≤ ~120 lines; link sibling maps instead of duplicating rows.
