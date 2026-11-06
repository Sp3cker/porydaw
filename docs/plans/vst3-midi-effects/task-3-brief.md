# Context

Effects persist as config plus plugin state in a config-only sidecar; nothing derived from the song is stored, so nothing can go stale. Save and fork write `<projectRoot>/.porydaw/midi-effects/<label>.json` after the `.mid`, and remove the json when there are no effects. Open restores the sidecar, dropping effects whose track is gone and moving a corrupt sidecar aside, both with a notice. Song deletion removes the json; backups keep only the `.mid`. Consumer: task 9 (the controller opens panels and arms Live on the restored effects). Depends on task 2; checkpoint A1 must be committed before this task re-edits `SongDocument.swift`. Read plan.md Global Constraints and spec.md "Session and persistence" first.

# Exact write set

- src/swift/core/EffectsSidecar.swift (new): `EffectsSidecar`, `StoredEffect` (a field-by-field Codable mirror of `TrackEffect`; classUID as 32 lowercase hex characters; state as base64; deterministic key order)
- src/swift/core/SongDocument.swift:
  - `SongDocument.init(…, effects: [TrackEffect] = [])`, which sets the effect-ID counter past the restored maximum;
  - `captureSave` fills `SaveSnapshot.effectsSidecar: EffectsSidecar?`.
- src/swift/document/DocumentSession.swift: `SessionChangeDomains.effects` as the next bit (`src/swift/document/DocumentSession.swift:9-24`); `LoadedSong.effects: LoadedEffects?` handling on open (see service files)
- src/swift/document/DocumentSession+Internals.swift: a `DocumentChange` with `effectsOnly` publishes `[.effects, .dirty, .history]` without a timeline rebuild and without selection reconciliation
- src/swift/document/service/ProjectService.swift: `LoadedSong.effects: LoadedEffects?` on the `LoadedSong` struct (`:243`)
- src/swift/document/service/ProjectService+Bank.swift: `openSong` reads the json when present (`:133`); `save` writes the `.mid` then the sidecar, or removes a stale json (`:179`)
- src/swift/document/service/ProjectService+Songs.swift: `forkSongAs` writes the sidecar under the new label when `snapshot.effectsSidecar` is non-nil (`:57`)
- src/swift/project/SongRegistration+Store.swift: the song delete path also removes `.porydaw/midi-effects/<label>.json` when present (`:86-125`). Sidecar I/O everywhere uses the existing `ProjectFileStore` `mkpath`/`move`/`remove`/`writeAtomic`/`exists` statics, with `mkpath` before writes.
- src/swift/app/ApplicationSession.swift: `lastOpenNotice: String`, following the `lastSaveError` pattern (`:16`)
- src/swift/app/ApplicationSession+Tabs.swift: after opening a tab whose session reports dropped or corrupt effects, set `ApplicationSession.lastOpenNotice` to the spec message
- src/swift/app/shell/ShellPresenter.swift: present a non-empty `lastOpenNotice` through `criticalRequested(title:message:)` (`:614`), then clear it, mirroring `saveStateChanged` (`:488`)
- src/checks/workspace/EffectPersistenceChecks.swift (new; `@MainActor public func runEffectPersistenceChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService)`)

Registration (controller): sources; the check called from `runProjectSessionSuite`.

# Prerequisites

Task 2 (`TrackEffect`, document operations, `recordPluginState`, `init(effects:)` counter rule).

# Interface contract

Exactly spec.md "Session and persistence", with these details:

- **Session.** `SessionChangeDomains` gains `.effects`. A change with `effectsOnly` publishes `[.effects, .dirty, .history]`, skips the timeline rebuild, and skips selection reconciliation. The session timeline is built from the song unchanged; there is no playback-only timeline variant.
- **Save.** `SaveSnapshot` gains `effectsSidecar: EffectsSidecar?`. `ProjectService.save` and `forkSongAs` write `<label>.mid`, then `<projectRoot>/.porydaw/midi-effects/<label>.json` atomically. With no effects they remove any existing json.
- **Open.** `ProjectService.openSong` reads the json when it exists. `LoadedSong.effects: LoadedEffects?` is `restored(EffectsSidecar, dropped: Int)` or `corrupt(movedTo: String)`.
  - Effects whose track is ≥ the engine track count, or duplicates per track, are dropped. A notice goes through `ShellPresenter.criticalRequested`: title "MIDI effects", message "<label>: N MIDI effect(s) referred to missing tracks and were removed."
  - A corrupt json is renamed `<label>.corrupt-<yyyyMMdd-HHmmss>[-N].json` (the smallest free `N` on a collision; never overwrite), with title "MIDI effects" and message "<label>: the MIDI-effects sidecar was corrupt and was moved aside."
  - A pair-less song with no effects opens exactly as today; `LoadedSong.effects == nil`.
- **Song deletion.** The `SongRegistration+Store.swift` delete path removes the json. Backups keep only the `.mid`. No rename path exists; any future one must move the json.
- **Unchanged paths.** WAV export, CPU profile and backups are unchanged (song only). No flattening anywhere.

# Implementation steps

1. Write the sidecar codec with an explicit `version: 2` check; other versions count as corrupt and are moved aside.
2. Make save capture the sidecar in `captureSave`; add the service write, delete and read paths.
3. Session: add the `.effects` domain; restore on open from `LoadedSong.effects` via `init(effects:)`; publish `effectsOnly` changes as `[.effects, .dirty, .history]` with no timeline rebuild and no selection reconciliation.
4. Add the open-notice plumbing through `lastOpenNotice` and `criticalRequested`.
5. Checks. Build effects through the document API:
   - a recorded plugin edit is one undo step: `isDirty` goes true after the record and false after save or undo;
   - the on-disk `.mid` is byte-identical with and without effects, and the json exists only with effects;
   - reopening restores config and plugin state exactly, with no timeline change;
   - an effect whose track is gone reopens dropped: the effect is gone, the notice text matches, and the session is dirty;
   - a corrupt sidecar is renamed with the timestamp pattern and the notice matches; a second corrupt rename in the same second gets a `-1` suffix and overwrites nothing;
   - removing all effects and saving deletes the json;
   - `forkSongAs` writes the json under the new label;
   - a song without effects round-trips byte-identically, as before;
   - deleting the song removes its json.

# Acceptance predicate

NAMED CHECKS (controller):

- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-projectsession`: persistence, drop/corrupt notices, dirty state.
- `uv run --no-sync dev checks --filter projectstore-savecore`: save regression.
- `uv run --no-sync dev checks:shell --filter shell-tabs-window-close`: close and reopen regression.

# Task-specific constraints

- The sidecar never enters `SongHistory`.
- No flattened export, no `source.mid`, no digests pairing the sidecar with the `.mid`, no detach.
- Backups stay MIDI-only (spec non-goal).
- Pair writes are not crash-atomic together; re-reading the json on open is the designed recovery.
