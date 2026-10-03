# File → New Song blank-mode wizard — execution plan

Status: authorized 2026-09-30. This plan adopts the fork's blank-mode
`NewSongWizard` for File → New Song, closes visual dialogs A017–A021 and the
PJ03 creation transaction, and removes the Swift-era copy-from-current prompt.
It supersedes the sprint-4 deferral
(`docs/old/swift-feature-parity/sprint-4.md:33,407,415`) **for this surface
only**; every other deferral in that document stands.

Behavior contract, frozen page/transaction order, and the copy-from-current
decision live in [spec.md](spec.md). Implementers read spec.md and this file;
briefs carry deltas only.

## Task table

| Task | Surface | Route / seat | Rows closed | Depends on |
|---|---|---|---|---|
| 1 | [Wizard law + controller](task-1-brief.md): pure `NewSongWizardState`, bridged `NewSongController` owned by `SongDockController`, finish plan reusing `ProjectService.importSong` | **SDD-track / `sdd-implementer`** — new Swift domain + bridged controller interfaces with a persistence-commit contract and check wiring across two modules; judgment work, not mechanical. | none (producer) | — |
| 2 | [Mounted wizard + cutover](task-2-brief.md): `NewSongHost`/`NewSongWizard` QML reusing the import pages, File-menu route to the wizard, removal of the copy-from-current prompt, lane `shell-new-song-wizard` | **SDD-track / `sdd-implementer`** — mounted QML surface on hot shell files, user-visible route/enablement change, ledger row edits bound to new executed evidence. | dialogs A017, A018, A020 → MATCHED (S008–S010); A019, A021 → RETIRED-REPRESENTATION; header tally | 1 (checkpointed) |
| 3 | [Commit journeys + retirement](task-3-brief.md): lane `shell-new-song-commit`, deferral-doc cutover, delete `proof.dialogs.txt` at zero open rows | **SDD-track / `sdd-implementer`** — mounted commit journeys prove the creation transaction end-to-end; ledger deletion requires the all-closed judgment plus the doc cutover. | **`proof.dialogs.txt` deleted**; sprint-4/inventory/plan doc rows updated | 2 (checkpointed) |

No task touches the native C/C++ boundary: the only bridge surface is the
Swift-side `@QtBridgeable` controller, covered by `deno task checks:bridge`.
Seat stays `sdd-implementer` throughout; there is no `qt-cpp-reviewer` task.

## Global constraints

- **Proof rules** (from `.omp/rules/proof-ledger-workflow.md`, binding): row
  edits happen only in the commit whose checks prove them, via
  `deno task proof:edit` (S-entry additions and the final file deletion are
  direct edits; `proof:edit` cannot add or remove rows). `MATCHED` requires
  executed evidence for that predicate — the lane runs **before** `--apply`,
  and `build/debug/proof-evidence/*.json` must list the anchored test
  functions. Closed rows take compact form (header + `Disposition:` + one
  mapping line). Never edit rows outside `src/checks/visual/proof.dialogs.txt`
  A017–A021 and its header/S-entry section.
- **Verification reuse**: implementers run the exact commands recorded in each
  brief's Acceptance predicate without re-discovering them. Reassess only if a
  command proves stale or unavailable; report the concrete mismatch and the
  revised verification rather than silently narrowing it.
- **Single-writer serialization**: `src/checks/visual/proof.dialogs.txt` is
  flagged SHARED with the P4 sample-studio track (its A011–A016 rows); if P4
  is in flight, serialize this track's ledger edits against it. The hot shell
  files this plan touches (`ShellWindow.qml`, `ShellPresenter.swift`,
  `SongDockController.swift`, `src/checks/CMakeLists.txt`,
  `ShellQmlEntries.swift`, `tst_TextContrast.qml`) follow the same
  one-writer rule inside the plan: strictly serial task order.
- **Not in scope** (spec.md §9): the MIDI import wizard (do not reopen
  `MidiImportWizardState`, `MidiImportController` or `tst_ShellImportWizard.qml`;
  the named reuse of `ImportIdentityPage.qml`/`ImportSoundPage.qml` is the
  only import-file dependency), register/delete confirmations, the save-conflict
  fork (`forkSongAs`, `validNewSongLabel`), VG03's dock New Voicegroup flow,
  and subsequent edit/play/save of the created song (already owned by the
  song-tab path — spec.md §8).
- Briefs contain requirements only; envelopes, evidence shape and fix loops
  belong to the execution loop.

## Checkpoints

- **M1** after task 1 acceptance: controller law proven, not yet reachable.
  Checkpoint before task 2 re-edits `SongDockController.swift`.
- **M2** after task 2 acceptance: mounted wizard + rows closed. Checkpoint
  before task 3 re-edits `ShellQmlEntries.swift`, the checks CMake lists and
  the ledger.
- **Final** after task 3: ledger deleted, docs updated, remaining accepted
  work committed.

## Verification ownership

Implementers run their brief's lanes and proof commands under the shared-tree
rules (no project-wide builds; the recorded scoped lanes only). The controller
owns the project-wide gate after writers settle, plus the native macOS smoke
runs named in tasks 2 and 3.
