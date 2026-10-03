# Context

R25: cohesion and stale-comment repair in the owners the recent repair wave touched — nothing else. Named concrete defects, all confirmed by source inspection:

1. `src/swift/app/ApplicationSession.swift` (1302 lines): `play()` (~1080-1093) and `playPause()` (~1095-1107) duplicate the seek-to-editCursor + `audio.play()` + `playhead.observe` block near-verbatim; `stop()` (~1109-1115) repeats the `playhead.refreshImmediate` + `transportBar.refresh` tail a third time; `seekToTick` (~1116-1122) is a fourth seek+observe variant with an origin guard. Extract the shared transport publication behind one private path; keep the four public entry points and their distinct semantics (play vs playPause origin, seekToTick's guard).
2. `src/checks/workspace/transport_checks.swift`: `checkSelectedWorkspaceAudio` (lines 38-158) is a 121-line function mixing fixture mutation, RunLoop polling helpers, a single-note observation helper with a failure-string out-param, a mute/solo matrix and the two-tab isolation journey — five reasons to change in one function. Split along those seams into private helpers; preserve the journey's assertions and ordering exactly.
3. Stale comments (delete, do not rewrite): `DocumentSession.swift` lines 42, 50, 51, 100-101 ("Task 8's ownership interface", "Playback is published as an immutable value for Task 7 to bind" ×2, "the old AudioEngine timeline API is not referenced here" — all historical/completed-task or negative-history statements); `ProjectService.swift` lines 22, 39, 49, 100-101, 120, 196-197 (the "mirroring VgMacro/VgVoice/VoicegroupSlotView/SongInfo" and VoicegroupBrowser ancestry comments); `SongTabsController.swift` lines 274-276 ("mirroring the legacy View-menu check" ancestry). NOT stale — do not touch: `AudioDevice.swift` "Sole device start point" / "Stay stopped" (measured guards), `AsmLine.swift` allocation comment (measured guard), `SongDocument.swift:68` Task-2/3 producer note is borderline — leave it (file is under review threshold and settling).
4. Repeated play/start publication: the transport trio above is the R25-named instance; the extraction in step 1 removes it. No ledger rows map to R25 — no proof edits.

Read plan.md Global constraints. This is a pure refactor: zero behavior change, zero API change.

# Exact write set

- `src/swift/app/ApplicationSession.swift`
- `src/checks/workspace/transport_checks.swift`
- `src/swift/app/DocumentSession.swift`
- `src/swift/app/ProjectService.swift`
- `src/swift/app/SongTabsController.swift`

# Prerequisites

Tasks 12/13/15 are accepted and pushed; transport behavior is pinned by `runTransportBarChecks` (swiftcore) and `shell-transport` (mounted). The refactor must keep both green byte-for-byte in observable terms.

# Interface contract

- `ApplicationSession` public surface unchanged: `play()`, `playPause()`, `stop()`, `seekToTick` and all consumed facades keep signatures and semantics. The extracted private helper(s) may be named by the implementer to fit the file's conventions; they must not be bridged/public.
- `checkSelectedWorkspaceAudio` keeps its registered name, entry point and assertion order; extraction is private-function-level only.
- Comment deletions remove exactly the named lines/regions; nothing adjacent is reworded.

# Implementation steps

1. Extract the shared seek+play+observe publication in `ApplicationSession` behind one private method; rewrite `play`/`playPause`/`stop`/`seekToTick` to call it, preserving each caller's distinct guard/origin semantics. No logic changes beyond deduplication.
2. Split `checkSelectedWorkspaceAudio` into fixture setup, observation helper, mute/solo matrix and isolation-journey phases; keep the assertions and their order identical.
3. Delete the named stale comments in `DocumentSession`, `ProjectService`, `SongTabsController`. Confirm no other completed-task/"mirroring" ancestry comments exist in the touched ranges; leave load-bearing measured-guard comments alone.
4. No proof ledger edits — no predicates change.

# Acceptance predicate

Identical observable behavior; the deduplicated transport path is the single implementation of seek+play+observe+refresh; the named stale comments are gone; file structure reads as phases, not a 121-line blob.

Controller-run named checks after the writer freezes:
- `deno task verify --filter swiftcore --verbose` — transport bar + session suites.
- `deno task verify:shell --filter shell-transport --verbose` — mounted transport regression.
- `deno task verify --filter projectstore --verbose` — ProjectService-adjacent regression.

# Task-specific constraints

Refactor-only: no new checks, no ledger edits, no reformatting of untouched code. Do not touch `gridCommandAvailable`/`routeGridKey` facades (R22 territory). The selftest GAP rows naming `DocumentSession`/`SongTabsController` (A005/A006/A009/A016) remain pending — do not claim or disturb them. No extraction into new files: deduplicate in place; `ApplicationSession` stays cohesive as the session facade (file size alone is not a defect here).
