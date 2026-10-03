# Task 234 brief — Import MIDI commit variants, refusal and partial success on the mounted wizard; the onboarding ledger closes

# Context

Task 233 mounted File → Import MIDI and proved the page flow and one
successful registration. The remaining fork contract is the set of commit
variants on the same mounted surface:

- **Rescale off** keeps the source division (`newsongwizard.cpp:647-652`).
- **Dedup before rescale** (`:643-646`) comes from the fork's
  `importWizard` dedup leg (onboard A073–A077).
- **Overflow refusal**: an import that would overflow the tick range writes
  nothing and shows the warning titled "Import MIDI" with the rescale text
  (`workspaceui_samples.cpp:78-81`, onboard A046–A052).
- **Explicit default reverb**: the Sound page writes `-R50`, and Song
  Settings leaves an unset reverb unset (A066–A068).
- **New voicegroup**:
  - The voicegroup file and include are created, the catalog refreshes, and
    the song opens in a new tab (`projectio.cpp:329-336,370-380`,
    `workspaceui_project.cpp:195-204`).
  - A voicegroup name that already exists shows the "New Voicegroup" warning
    and keeps the wizard open (`newsongwizard.cpp:241-251`).
- **Refusals and partial success** from task 231's taxonomy, seen through the
  mounted route:
  - An existing `.mid` refuses with the fork text.
  - An unwritable registration file leaves the song listed with its retry
    badge, and File → Register Song (task 211) completes it.

These close verification journey J03 (external MIDI) and inventory PJ04,
except the file-drop behavior that the parity scope excludes (`plan.md`
§ Scope decisions). The finish legs import without touching open or dirty
tabs, which is the dirty-tab clause of the plan's Onboarding prerequisite.

Surface: the mounted Import MIDI wizard's Finish outcomes, the Song
Settings reverb field, and Register Song retry after a partial import.
Ledger spec: `src/checks/onboardcheck/proof.import.txt`. This task closes
its last 17 open rows and deletes the ledger.
Verify lanes: `shell-import-commit` (new), `shell-import-wizard`
(regression), the proof check.
Blocked rows left untouched:
- `visual/proof.dialogs.txt`: all rows outside A022–A027 (see task 233).
- `project/proof.iomutations.txt` (task 171 creation rows).

# Exact write set

- `src/checks/editorqml/tst_ShellImportCommit.qml` (new).
- `src/checks/editorqml/ShellQmlEntries.swift`: add
  `Entry(name: "shell-import-commit", inputFileName:
  "tst_ShellImportCommit.qml", fixtureFiles: importFixture)`. It reuses
  task 233's private list. **Shared** with task 233 and other tracks.
- `src/checks/editorqml/ImportWizardProbe.swift` (task 233's file). Add these
  check-side staging and reading methods:
  - `writeOverflowSource(path:) -> Bool`: builds a division-12, one-chunk
    `MidiFile` with a note-on at `TimeDefaults.maxTick` (the fork boundary)
    and writes its `encoded()` bytes. If the encoder refuses that tick, use
    the largest encodable tick above `maxTick / 2`. Rescaling ×2 or ×4 still
    overflows, so A048–A052 keep their meaning.
  - `setWritable(path:writable:) -> Bool`: sets POSIX 0o644 or 0o444.
  - `copyFile(from:to:) -> Bool`.
  - `removeFlag(projectRoot:label:flag:) -> Bool`: rewrites that label's
    `midi.cfg` line without one `-X…` token, preserving the order of every
    other token.
  - `chunkCount(path:) -> Int`.
  - `controllerCount(path:chunk:controller:) -> Int`.
  - `programCount(path:chunk:) -> Int`.
- `src/checks/onboardcheck/proof.import.txt`: close its rows, then **delete**
  the file (the directory becomes empty).

No production files. If a journey below fails because of a production
defect, stop and report it. Do not patch production code inside this task.

# Prerequisites

- Task 233 accepted and checkpointed: it owns `ImportWizardProbe.swift`,
  `ShellQmlEntries.swift`'s `importFixture` and the onboard S entries this
  task deletes.
- Tasks 231, 232 and 215 (their behavior is under test).
- Task 211 (the File → Register Song route).

# Interface contract (observable outcomes pinned by the checks)

Each journey is one `test_` function. It starts from its own copied project,
through `prepareSongActionFixture` style or a fresh shell as in
`tst_ShellSongs`. It enters only through the File menu, the picker
(`selectedFile` + `accept()`), real key or mouse input on wizard controls,
and dock activation. Expectations are fixture literals.

1. `test_importOverflowRefusesWithoutWriting` (A048–A052):
   - Stage `<root>/test_midis/overflow.mid` and pick it.
   - `importRescale` is visible and checked (A048).
   - On the Sound page, `importExtendedClocks` exists (A049). Check it.
   - Finish: the wizard closes, and `shellImportMidiWarning` shows "Import
     MIDI" with text that contains "Tick rescale to division 48 exceeds
     32-bit tick range" (A052).
   - `sound/songs/midi/mus_overflow.mid` does not exist, and `midi.cfg` and
     `song_table.inc` fingerprints are unchanged (A050).
   - The Songs dock does not list `mus_overflow` (A051).
2. `test_importWithoutRescaleKeepsSourceDivision` (A061, A062, A066, A067):
   - Pick `external_import.mid`, uncheck `importRescale`, and type the name
     `mus_external_raw`.
   - On the Sound page, `importReverb` shows 50 (A066).
   - Finish: the song is listed (A061), its written division is 400 (A062),
     and its `midi.cfg` flags contain `-R50` (A067).
3. `test_songSettingsKeepsUnsetReverb` (A068):
   - Remove `-R50` from `mus_route101`'s `midi.cfg` line, then open that
     song.
   - Edit → Song Settings shows `song.reverb` as "Default (50)".
   - OK, then Save Song: the saved `midi.cfg` line has no `-R` token, and
     reopening Song Settings still shows "Default (50)".
4. `test_importDedupsDuplicateSetters` (A074–A077):
   - Pick `duplicate_setters.mid` and keep the suggested name
     `mus_duplicate_setters` and the defaults.
   - Finish: the song is listed (A074).
   - The written file has 2 chunks (A075), and chunk 1 has 3 CC7 events
     (A076) and 2 program changes (A077).
5. `test_importCreatesVoicegroupAndOpensTab`:
   - Name `mus_newvg_import`, and choose "(create a new voicegroup for this
     song)".
   - Finish produces:
     - `sound/voicegroups/mus_newvg_import.inc` exists.
     - `voice_groups.inc` gained its include.
     - The flags contain `-G_mus_newvg_import`.
     - A new tab titled `mus_newvg_import` is selected.
     - Song Settings' `song.voicegroup` list contains `mus_newvg_import`,
       which is the catalog refresh.
6. `test_importNewVoicegroupCollisionWarns`:
   - Name `fixture_alt`, and choose the create entry.
   - Finish shows the warning "New Voicegroup" with "A voicegroup named
     voicegroup_fixture_alt already exists — pick it from the list instead.".
   - The wizard stays open on "Sound settings", and no file changes.
7. `test_importExistingMidiRefuses`:
   - Copy `mus_route101.mid` to `sound/songs/midi/mus_stray_import.mid`,
     then import with that name. The name is free in the table, so no hint
     shows.
   - Finish shows `shellCriticalDialog` with text that contains "MIDI file
     already exists:".
   - The stray's fingerprint is unchanged, and `midi.cfg` is unchanged.
8. `test_importPartialRegistrationRetries` (J03):
   - Open `mus_route101`. Set Song Settings priority to 5 with OK, so the tab
     is dirty (`session.songDocumentDirty`).
   - Make `include/constants/songs.h` read-only, then import `external_import`
     as `mus_partial_import`.
   - Finish shows `shellCriticalDialog`.
   - `sound/songs/midi/mus_partial_import.mid` exists, and the dock row shows
     the not-registered badge.
   - `mus_route101` stays dirty. Its `.mid` fingerprint and its `midi.cfg`
     line are unchanged.
   - Restore write access, then open the `mus_partial_import` row in a new
     tab through the dock's "Open in New Tab" row menu. This leaves the
     dirty `mus_route101` tab in place. Use File → Register Song and accept.
     The badge clears.
   - Restore permissions in `cleanup()` even when the test fails.

# Implementation steps

1. Add the probe methods, the lane entry and the eight journeys.
2. Update the ledger with `deno task proof:edit`. Each MATCHED row gets a new
   message-anchored S entry in the `(shell-import-commit lane)` header form
   from task 233.
   - NATIVE-SETUP with staging reasons: A046 (project copy), A047 (project
     open) and A073 (duplicate fixture decode).
   - MATCHED: A048–A052, A061, A062, A066–A068 and A074–A077.
3. Confirm that `proof check --executed --strict-mappings` reports no
   onboard site. Every row is then MATCHED or NATIVE-SETUP. Delete
   `proof.import.txt` in the same commit (`proof-ledger-workflow`
   § Allowed ledger-only changes). The Swift `cppID` strings in
   `MidiImportChecks.swift` remain as lineage, and no other file registers
   the ledger.

# Acceptance predicate

Through the mounted wizard, every fork commit variant produces the fork's
files or refusal:
- rescale off/on;
- dedup;
- overflow refusal with no write;
- explicit `-R50` against an unset Song Settings reverb;
- new voicegroup with catalog refresh and tab open;
- the voicegroup-collision warning;
- the existing-MIDI refusal;
- partial registration with retry, without disturbing a dirty open tab.

The onboarding ledger closes on executed evidence and is deleted.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-import-commit --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-import-wizard --verbose
deno task proof check --executed --strict-mappings
```

Coverage:
- `shell-import-commit` runs journeys 1–8.
- `shell-import-wizard` guards that the shared fixture list and probe still
  serve task 233.

Gap: on-device audio of the imported song is not covered (a standing
physical-output exclusion). Task 231's lane already covers the compile of
wizard output through mid2agb (onboard A102 domain).

# Task-specific constraints

- Journeys use only fixture literals. Never read an expected value back from
  `MidiImportController`.
- Permission changes use real POSIX modes. Do not mock service completions.
- Do not edit `tst_ShellImportWizard.qml`, production QML or Swift.
