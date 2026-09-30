# Task 3 brief — Commit journeys, ledger retirement, deferral-doc cutover

## Context

Tasks 1–2 delivered and mounted the wizard; A017–A021 are closed and
`proof.dialogs.txt` has zero open rows. This task proves the creation
transaction on the mounted surface (`shell-new-song-commit`), then deletes
the fully-closed ledger and updates the parity documents that still say the
blank wizard is deferred (spec.md §7). The transaction itself is task-1/2
code exercised end-to-end here; no new production transaction code is
expected.

Surface: File → New Song → Finish on the mounted wizard: blank MIDI bytes,
flags, registration, dock/status updates, new-voicegroup variant, refusals.
Ledger spec: deletion of `src/checks/visual/proof.dialogs.txt` at zero open
rows (proof-ledger-workflow "allowed ledger-only changes" clause).
Verify lanes: `shell-new-song-commit` (new), `shell-new-song-wizard`,
`swiftcore-projectsession`, `deno task proof check --executed` and
`--strict-mappings`.
Blocked rows left untouched: every other ledger (themelayout settings,
mainwindowrouting input/lifecycle/native, visual browsers, and the P4
samplecheck family). No row outside the deleted file changes.

## Exact write set

Checks:
- `src/checks/editorqml/tst_ShellNewSongCommit.qml` (new): functions
  `test_newSongFinishCreatesBlankSong`,
  `test_newSongFinishWithNewVoicegroupOpensTab`,
  `test_newSongRefusalsLeaveProjectUntouched`.
- `src/checks/editorqml/ShellQmlEntries.swift`: new entry
  `Entry(name: "shell-new-song-commit", inputFileName:
  "tst_ShellNewSongCommit.qml", <same fixture set as
  shell-new-song-wizard>)`.
- `src/checks/editorqml/ImportWizardProbe.swift`: add one member
  `public func blankSongFingerprint() -> String` — the probe's existing FNV
  `fingerprint` algorithm over `MidiFile.blankSong().encoded()`. The probe is
  already registered as a QML element and compiled into `shell_qml_lane`, so
  no registration change. It is a shared check helper, not import-wizard
  surface; this is an additive member only.

Ledger:
- `src/checks/visual/proof.dialogs.txt`: deleted (`git rm`), after confirming
  zero GAP/PARTIAL/DEFERRED rows (`deno task proof sites
  src/checks/visual/proof.dialogs.txt` shows none).

Docs (spec.md §7, exact lines):
- `docs/plans/swift-feature-parity/sprint-4.md:33` — replace the "not
  adopted" deferral with a pointer to this plan.
- `docs/plans/swift-feature-parity/sprint-4.md:407` — dialogs A017–A021 and
  PJ03's conjuncts: no longer deferred.
- `docs/plans/swift-feature-parity/sprint-4.md:415` — "Import mode only"
  planner decision superseded for New Song.
- `docs/plans/swift-feature-parity/inventory.md` — PJ03 row: name the landed
  owners (`NewSongController`/`NewSongWizard` + `ProjectService.importSong`
  reuse) instead of "Missing complete shell wizard/store transaction".
- `docs/plans/swift-feature-parity/plan.md:84` — PJ03 row leaves "blocked".
- `docs/plans/swift-feature-parity/plan.md:128` — J02 drops its PJ03 clause
  (VG03 remains).

Eight files, one verification surface (the commit lane) plus its bound
ledger/doc cutover.

## Prerequisites

- Task 2 (checkpointed): the mounted wizard, lane registration pattern, and
  the closed rows (this task re-edits `ShellQmlEntries.swift`).

## Interface contract (fork clauses, spec.md §3–§4)

- `test_newSongFinishCreatesBlankSong`: on the fixture project (per-file
  layout, existing voicegroups), choose an existing voicegroup, finish:
  - `<root>/sound/songs/midi/mus_<label>.mid` is the **blank template, not a
    copy of any song**: `probe.fingerprint(<mid path>) ===
    probe.blankSongFingerprint()` (and `probe.midiDivision(...) === 24`);
  - the midi.cfg flags line carries the chosen `-V/-R/-P/-E/-X/-N`;
  - the song registers (songs.h define, song_table row) with the chosen
    player and derived constant;
  - the dock lists the new song; the status reads
    "Created and registered <label> (song ID <id>)"; **no new tab** opens.
- `test_newSongFinishWithNewVoicegroupOpensTab`: choose the create entry:
  `sound/voicegroups/<label>.inc` exists (dummy template), the song's `-G` is
  `_<label>`, the voicegroup catalog refreshes (combo offers the new group on
  reopen), and the song opens in a new tab.
- `test_newSongRefusalsLeaveProjectUntouched`:
  - voicegroup collision (create entry while `_<label>` exists): Finish
    refuses, warning dialog titled "New Voicegroup" with the fork message,
    wizard stays open, no bytes change;
  - existing `.mid` (stage a stray file first): service refusal
    "MIDI file already exists: <path>" via the Operation Failed channel, dock
    refresh shows the stray with its retry badge, File → Register Song
    enabled for it;
  - taken label: Next never enables (page gate), no writes.

## Implementation steps

1. Write the commit test QML: reuse task 2's open/fill helpers; assert on
   staged files (read bytes via the existing check file helpers) and on
   `shell.session` state (status text, song listing rows, tab count).
2. Register the entry (fixture identical to `shell-new-song-wizard`).
3. Run the lanes; then `deno task proof sites
   src/checks/visual/proof.dialogs.txt` — expect zero open rows.
4. `git rm src/checks/visual/proof.dialogs.txt`; re-run the proof checks
   (they must no longer list the file).
5. Apply the six doc edits (spec.md §7).

Edge cases: finish with the create entry on a **non**-per-file project is
unreachable (no create entry offered — assert the combo omits it when the
fixture hides the voicegroups dir, if the fixture supports it; otherwise
cover via the state checks from task 1 and note it); partial registration
badge after the existing-`.mid` refusal path is the retry surface, already
owned by Register Song.

## Acceptance predicate

Finish on the mounted wizard writes the blank template, flags and
registration in the frozen order with the frozen refusals; the new-voicegroup
variant creates `sound/voicegroups/<label>.inc`, refreshes the catalog and
opens a tab; refusal paths write nothing. The dialogs ledger is deleted at
zero open rows and the parity docs no longer defer this surface.

```sh
deno task checks:shell --filter shell-new-song-commit --verbose
deno task checks:shell --filter shell-new-song-wizard --verbose
deno task checks --filter swiftcore-projectsession --verbose
deno task proof sites src/checks/visual/proof.dialogs.txt   # before deletion: no GAP/PARTIAL/DEFERRED rows
deno task proof check --executed
deno task proof check --strict-mappings                     # after deletion: no line names proof.dialogs.txt
```

Coverage: `shell-new-song-commit` proves the PJ03 creation transaction
end-to-end on the mounted surface (blank bytes, flags, registration, status,
tab rule, catalog refresh, refusal taxonomy, partial-registration badge);
`shell-new-song-wizard` re-proves the page flow still green beside the new
lane; `swiftcore-projectsession` re-proves the service suites (incl. after
task 2's `createSong` removal); the proof checks prove the deletion is clean
(no dangling S anchors, no executed-evidence complaints).
Gaps: on-device playback of the created song is a physical-output exclusion;
native delivery is Controller verification.

Implementer runs all commands; the controller owns the project-wide gate.

## Controller verification

- Native macOS smoke (`deno task build:app`): create a song via the wizard
  with a new voicegroup; confirm the tab opens, the status message appears,
  and reopening the wizard lists the new voicegroup. Then register-stray
  retry via File → Register Song on the badge row.

## Task-specific constraints

- The ledger deletion is legal **only** at zero open rows; if any row is
  still GAP/PARTIAL/DEFERRED, stop and report instead of deleting.
- After deleting the ledger, sweep for orphaned C++ production units: `git
  ls-files 'src/*.cpp' 'src/*.h'` and grep the remaining open
  `src/checks/**/proof.*.txt` for each hit's header name; delete a remaining
  unit only if this ledger was its last exerciser. Expected result: none
  (`src/ui/newsongwizard.*` and `src/checks/visual/dialogs.cpp` are already
  deleted; settings/sample/SF2 families belong to open ledgers in other
  tracks). Record the sweep result in the task report.
- Doc edits are line-precise (spec.md §7); do not rewrite surrounding
  paragraphs or touch other deferrals.
- Do not re-open the import wizard, its lanes or its rows; the commit tests
  use only the new-song surface.
