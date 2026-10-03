# Task 2 brief — File → New Song wizard mounted; copy-from-current removed

## Context

Task 1 delivered `NewSongController`. This task mounts the wizard (its own
`NewSongHost.qml`/`NewSongWizard.qml` on the `DialogWindow` base, reusing the
ported `ImportIdentityPage.qml`/`ImportSoundPage.qml` verbatim), reroutes
`file.new_song` to it with fork enablement, removes the copy-from-current
prompt and its service, and closes the dialogs ledger rows A017–A021 on
executed evidence from the new `shell-new-song-wizard` lane.

Fork visual contract: blank-mode `NewSongWizard` (`fceecd88`,
`newsongwizard.cpp:547-556,583-598`) — title "New Song", ClassicStyle,
`NoBackButtonOnStartPage`, minimum `52 × 38` base-font units; page texts and
defaults per spec.md §2.

Surface: File → New Song…, the mounted wizard window, its Identity and Sound
pages, and the route/enablement change.
Ledger spec: `src/checks/visual/proof.dialogs.txt` rows A017–A021 + header +
new S entries S008–S010 (spec.md §5).
Verify lanes: `shell-new-song-wizard` (new), `shell-songs`, `shell-menus`,
`shell-text-contrast`, `deno task checks:bridge`, `deno task proof check
--executed` then `--strict-mappings`.
Blocked rows left untouched: A001 (visual-baseline exclusion) and A002–A016
(retired/other families; A011–A016 belong to the P4 track); A022–A027
(import, closed); every other ledger.

## Exact write set

Production:
- `src/ui/shell/newsong/NewSongHost.qml` (new): host `Item` with the warning
  `MessageDialog` (`objectName: "shellNewSongWarning"`) and the wizard;
  `Connections` on `host.controller` for `onWarningRequested(title, message)`
  and `onWizardOpenChanged`.
- `src/ui/shell/newsong/NewSongWizard.qml` (new): `DialogWindow` with the
  wizard chrome (title/subtitle header, page `StackLayout`, Back/Next/Finish/
  Cancel row, `objectName`s `newSongWizard`, `newSongWizardTitle`,
  `newSongWizardBack`, `newSongWizardNext`, `newSongWizardFinish`,
  `newSongWizardCancel`), instantiating `ImportIdentityPage` and
  `ImportSoundPage` (same QML module; their page-internal `objectName`s stay
  as-is). Min size `Math.round(baseFontPx * 52)` × `Math.round(baseFontPx * 38)`.
- `src/ui/shell/ShellWindow.qml`: mount `NewSongHost` beside `MidiImportHost`
  (around line 262). The `SongConfirmDialog` loader (line 416) stays —
  register/delete still use it.
- `src/swift/app/shell/ShellPresenter.swift`: enablement
  `case "file.new_song": return session.projectOpen` (line 274) and dispatch
  `case "file.new_song": session.songDockController().newSongController()
  .requestNewSong()` (line 349).
- `src/swift/app/songlist/SongDockController.swift`: cutover per spec.md §1 —
  delete `requestNewSong()`, `newSongLabel`, the create branch of
  `acceptConfirmation` and its `newSongLabel` resets; keep
  `validNewSongLabel`, register and delete modes.
- `src/ui/songview/quick/docks/SongConfirmDialog.qml`: remove the create mode
  (title/OK-text "Create" branch, create-focus, `songNewName` field, taken
  hint); register/delete behavior unchanged.
- `src/swift/app/ProjectService+Songs.swift`: delete `createSong(label:from:)`
  and its doc comment. `forkSongAs` stays.
- `CMakeLists.txt` (root): register the two new QML files under the
  `porydaw_ui_plugin` sources beside `src/ui/shell/midiimport/*` (lines
  287-291).
- `src/swift/app/newsong/NewSongController.swift`: replace the interim
  `warningTitle`/`warningMessage` pair with
  `@QtSignal public func warningRequested(title: String, message: String)`
  emitted at the refusal site; publish via the existing publish path.

Checks:
- `src/checks/editorqml/tst_ShellNewSongWizard.qml` (new): functions
  `test_newSongRouteGateAndOpen`, `test_newSongWizardPageFlow`.
- `src/checks/editorqml/ShellQmlEntries.swift`: new entry
  `Entry(name: "shell-new-song-wizard", inputFileName:
  "tst_ShellNewSongWizard.qml", fixtureFiles: songs("mus_route101",
  "mus_petalburg", "mus_gym", "mus_surf", "mus_victory_wild",
  "se_fanfare_1trk", "se_pc_login", "se_use_item") + [
  "sound/voicegroups/fixture_alt.inc", "include/constants/songs.h"])` — the
  shell-songs fixture set (per-file layout present → `canCreateVoicegroup`).
- `src/checks/editorqml/tst_ShellSongs.qml`: delete the five create-mode
  journeys (spec.md §1); register/delete journeys untouched.
- `src/checks/editorqml/tst_TextContrast.qml`: audit function walking both
  wizard pages (open via `activate("file.new_song")`, audit each page, click
  `newSongWizardNext` between them, cancel), invoked from
  `auditShellMode(...)`.

Ledger (after the lane runs green):
- `src/checks/visual/proof.dialogs.txt`: A017, A018, A020 → MATCHED (compact,
  `Mapping: S008` / `S009` / `S010`); A019, A021 → RETIRED-REPRESENTATION
  (compact, one-line reason per spec.md §5); append S008–S010 under
  `Swift assertion predicates` (direct edit — `proof:edit` cannot add rows);
  update the header tally line to `0 GAP, 7 MATCHED, 20
  RETIRED-REPRESENTATION` and replace the closing "Fork File > New Song
  wizard feature obligations remain open." sentence with the new-song
  closure note (`deno task proof:edit ... header --before ... --after ...`).

Over the file cap: one mounted surface with one verification entry plus its
bound ledger rows (sprint-4 task-233 precedent). The removals are the same
surface's cutover, not a second task's worth of behavior: after this task
there is exactly one New Song command.

## Prerequisites

- Task 1 (checkpointed): `NewSongController`'s contract, used verbatim.

## Interface contract (visual contract = fork clauses)

- **Route/enablement**: `file.new_song` enabled iff `session.projectOpen`;
  activation opens the wizard; silent refusal under the intake gate (no
  status, no dialog). With zero tabs open the wizard opens.
- **Wizard open**: page 0 = Identity (title "Song identity", subtitle
  "Names the .mid file, the song_table.inc entry, and the songs.h
  constant.", name field placeholder `mus_my_song`, constant field, player
  combo with the fork tooltip). No Back button on page 0. Window title
  "New Song".
- **Name law on the mounted field**: per-keystroke whole-edit fold through
  `controller.editLabel` (identical to the import page's TextField loop).
- **Next gate**: `newSongWizardNext` disabled while `!identityComplete`;
  enabled with a valid untaken name; click advances to page 1 = Sound (title
  "Sound settings", voicegroup combo with the create entry first and
  existing groups after, `-V` 100, `-R` default reverb, `-P` 0, `-E` checked,
  `-X`/`-N` unchecked, fork tooltips).
- **Cancel/Escape**: closes without writes (`controller.cancel()`).
- **Warning**: voicegroup-collision Finish refusal surfaces via
  `warningRequested` → `MessageDialog` titled "New Voicegroup". (Finish's
  full journey is task 3; this task wires and proves the dialog on the
  refusal path.)

## Implementation steps

1. Build the two QML files and the host; mount in `ShellWindow.qml`; register
   in the root `CMakeLists.txt`. Reuse `ImportIdentityPage`/`ImportSoundPage`
   unchanged — the controller exposes the member names they bind.
2. Reroute `ShellPresenter` (enablement + dispatch) and swap the controller's
   interim warning properties for the signal + host `Connections`.
3. Cut over `SongDockController`, `SongConfirmDialog.qml`,
   `ProjectService+Songs.swift` per spec.md §1 (delete create mode,
   `createSong(label:from:)`); delete the five `tst_ShellSongs` create-mode
   journeys.
4. Add the lane, entry and contrast audit.
5. Run the lanes (below); confirm
   `build/debug/proof-evidence/shell-new-song-wizard.json` lists
   `::NewSongWizard::test_newSongRouteGateAndOpen` and
   `::NewSongWizard::test_newSongWizardPageFlow`.
6. Edit the ledger: dry-run each `proof:edit` (no `--apply`) with `--before`
   = the entry's current full block (read via
   `deno task proof show src/checks/visual/proof.dialogs.txt A017`) and
   `--after` = the compact form from spec.md §5; then `--apply`. Append
   S008–S010 and update the header. Re-run the proof checks.

Edge cases: wizard open with no song tab; taken-name hint disables Next
(message "A song named %1 already exists."); Escape during the wizard;
double-open attempt while the wizard is up (silent); confirm-dialog state
pending when File → New Song fires (silent refusal).

## Acceptance predicate

On an open project, File → New Song… (and Cmd+N) opens the two-page wizard on
Identity; Next is disabled until the name is valid and unused; a complete
Identity page advances to Sound with the fork's voicegroup/config controls
and defaults; Cancel/Escape writes nothing; the copy-from-current prompt is
gone (File → New Song no longer opens `SongConfirmDialog`), and register/
delete confirmations still work. Every new text passes the contrast audit.
The five rows close on executed evidence.

```sh
deno task checks:shell --filter shell-new-song-wizard --verbose
deno task checks:shell --filter shell-songs --verbose
deno task checks:shell --filter shell-menus --verbose
deno task checks:shell --filter shell-text-contrast
deno task checks:bridge
deno task proof check --executed
deno task proof check --strict-mappings
```

Order matters: lanes first (the evidence JSON must contain both anchored
functions before `proof:edit --apply`), then the row edits, then both proof
checks.

Coverage: `shell-new-song-wizard` proves A017 (identity name field + required
gate), A018 (opens on Identity) and A020 (Next → Sound) — the MATCHED rows —
plus the name-law journeys that replace the deleted `tst_ShellSongs`
predicates; `shell-songs` proves the create-mode removal broke nothing
(register/delete/collision-free listing); `shell-menus` proves the File menu
and enablement change (order pin at `tst_ShellMenus.qml:99` is untouched —
new_song keeps its position); `shell-text-contrast` covers both pages;
`--strict-mappings` output must contain no line naming `proof.dialogs.txt`.
Gaps: native window animation/real menu-bar delivery is offscreen-excluded —
Controller verification below.

Implementer runs everything above; the controller owns the gate re-run.

## Controller verification

- Native macOS smoke (`deno task build:app`): open a project with no tab,
  File → New Song, verify the wizard opens animated on Identity, type a
  taken name (hint + disabled Next), valid name → Next → Sound page shows
  player-inherited voicegroup list and defaults, Cancel closes cleanly.
  Screenshot via `capture-macos-app-window` against the fork reference build
  (`build-asan/porydaw.app`) if present; list deviations.

## Task-specific constraints

- Do not add a second name field, picker or warning path: the pages, host and
  controller from task 1 are the only owners. `ShellPresenter` only reroutes.
- Do not edit rows outside A017–A021/header/S-section, and make no ledger
  edit before the lane evidence exists.
- Do not keep dead create-mode symbols "temporarily": the cutover is complete
  in this task (clean-cut; `validNewSongLabel` and `forkSongAs` are not dead
  — spec.md §1).
- `ImportIdentityPage.qml`/`ImportSoundPage.qml` are reused verbatim; if a
  page seems to need a behavioral fork, stop and report instead of editing
  them.
