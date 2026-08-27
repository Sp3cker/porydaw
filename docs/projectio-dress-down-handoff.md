# Handoff: ProjectIo dress-down plan findings

Next session: the remaining dual-audit findings are **already folded into** `docs/projectio-dress-down-plan.md` (working tree / this commit). Verify that contract, optionally re-audit, and **do not start C++** until asked.

## Repo

- Branch: `feature/project-io-thread`
- Canonical plan: `docs/projectio-dress-down-plan.md`
- Types are declared once under **Implementation-ready target interfaces**

## Suggested skills

- `skill://codebase-design`
- `skill://thermo-nuclear-code-quality-review`
- `skill://thermo-nuclear-dual-audit` (optional; freeze the unstaged/committed plan diff)
- `skill://following-conventions` only if editing C++

## Locked (still)

Worker `LoadedBankEntry` owns the bank. GUI published views live in `WorkspaceUi`'s private `VoicegroupViewCache`. `Loading` ends at open. Open Project disablement and load tombstones are WorkspaceUi policy. No remainder set, `SongAvailability`, `TabId`/request IDs, `docs/projectio/` split, eight-file `projectio/` layout, `const_cast`, or worker-owned undo stack. Private `CommandFailure` stays unkeyed (FIFO). One product decision remains: missing/unplayable skeleton remain vs remove.

## Findings now in the plan

These were the open items from `ReviewerAgent-2` after the first alignment (`362676a`). The current plan incorporates them:

| Id | Finding | Plan response |
|---|---|---|
| B1 | 22-slot `ProjectWorkspace`; `WorkspaceUi` sequenced saves | `openProject(OpenProjectInput)` + `submit(ProjectOperation)`. One `SaveSongInput` recipe; worker sequences stages; UI applies keyed `LoadedBankView` + terminal `SongSaved`/`SongFailed`. |
| B2 | Optional-pair `ProjectMutationFailed`; thin `*Command{Input}` | Exhaustive `ProjectMutationFailure` (song / voicegroup / sample). Commands hold public `*Input` where there is no enrichment. |
| B3 | Async undo vs `QUndoStack` / dirty conflation | `SongHistory` on the tab stack; `VoicegroupViewCache` holds one pending bank transition; stack index moves only on worker confirmation; document dirty ≠ `LoadedBankView.dirty`. |
| B4 | `LoadSongCommand` carried `SongInfo`/`SongCfg` | Load commands carry `SongName`/`VoicegroupId` + user inputs; worker resolves catalog at execution. |
| B5 | Close + reopen same `SongName` | Transient `QSet<SongName>` tombstone on `WorkspaceUi`; refuse reopen until terminal; clear on accepted project replacement. |
| B6 | `SelectedAudioState` vs `applySelectedAudio` | `SelectedAudioState` removed. `MainWindow` reads the selected `SongTab`. |
| B7 | Empty `SongName`; `ProjectState.error` as `QString` | Validating identities; `ProjectState.error` is `optional<QString>`. |
| B8 | Restate types outside Implementation-ready | Cite the contract; forbidden-scan row in the acceptance matrix. |

Stale in the old audit freeze (already in `362676a`): `ApplyVoicegroupEditCommand`, `SongName` on song-bound results, Phase 6 not replaying the previous project's `lastOpenSongs`.

## Next agent work

1. Read Implementation-ready + acceptance matrix in `docs/projectio-dress-down-plan.md`.
2. Grep forbidden leftovers: `SelectedAudioState`, `resolvedSong`, `SongAvailability`, `const_cast`, remainder set, five `*Failed` payload structs.
3. If anything above is incomplete, patch **only** the plan.
4. Optional dual-audit of that diff.
5. Do not implement production C++ until the user asks.

## Product decision (leave open)

Missing/unplayable saved label: keep a failed skeleton vs remove it. `SongFailed{ SongStage::Reconcile }` identifies the label either way.
