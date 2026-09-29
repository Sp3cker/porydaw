# Task 233 brief — File → Import MIDI: picker, wizard window and its three pages, mounted

# Context

Task 232 delivered `MidiImportController`, which owns every wizard law and
the Finish commit. This task makes the controller reachable: the File menu
action, the file picker with the remembered directory, the warning dialog,
and the wizard window with its Analysis, Identity and Sound pages. It also
proves the page flow, the Analysis page and the Identity page, and one
successful import on the mounted surface.

Ruling 10 allows new QML for this family. The visual reference is the fork's
QWidget wizard (`fceecd88:src/ui/newsongwizard.cpp`), which uses
`QWizard::ClassicStyle` (themeruntime `:69`) and
`NoBackButtonOnStartPage` (`:585`).

The window convention is Settings' base: `DialogWindow` (`src/ui/shell/DialogWindow.qml`, the base Settings uses: native `Qt.Dialog` window with the platform open animation, focus return to `transientParent`, `present()` to open, Escape → `close()` unless `escapeCloses: false`; do not redeclare `flags`, the focus-return handler or an Escape shortcut), with font-derived geometry and colors from `colors.*` pairs.

The route follows the fork File menu (`mainwindow.cpp:289-300`):
"&Import MIDI..." sits right after New Song. It is enabled whenever a project
is open (`:960-961`), with no open song required. `file.import_midi` is
already registered in `KeybindingRegistry` (window scope, no key).

Surface: File → Import MIDI…, its picker and warning, and the mounted
wizard.
Ledger spec: `src/checks/onboardcheck/proof.import.txt` and
`src/checks/visual/proof.dialogs.txt` (the rows below).
Verify lanes: `shell-import-wizard` (new), `shell-menus`,
`shell-text-contrast-*`, the bridge guard and the proof check.
Blocked rows left untouched:
- onboard A046–A052, A061, A062, A066–A068 and A073–A077 (task 234).
- dialogs A001: the shared frozen-PNG helper across five dialog families; a
  visual-baseline exclusion.
- dialogs A003–A016: settings, theme, sample editor and Sf2 families (other
  tracks and exclusions).
- dialogs A017–A021: the New Song blank-mode wizard. It is not ported;
  New Song keeps its task-171 prompt pending the user decision recorded in
  the sprint section.

# Exact write set

Production:
- `src/ui/shell/midiimport/MidiImportHost.qml` (new): an `Item` that holds
  the `FileDialog`, the warning `MessageDialog`, the `MidiImportWizard`
  window, and one `Connections` on the controller.
- `src/ui/shell/midiimport/MidiImportWizard.qml` (new): the `DialogWindow`
  that holds the header, a `StackLayout` of pages, and the button row.
- `src/ui/shell/midiimport/ImportAnalysisPage.qml`,
  `ImportIdentityPage.qml`, `ImportSoundPage.qml` (new).
- `CMakeLists.txt` (root, `qt_add_qml_module(porydaw_app …)` QML_FILES): add
  the five files after `src/ui/shell/settings/SongSettingsPage.qml`.
  **Shared** with P3/P4 tracks.
- `src/ui/shell/ShellWindow.qml`: one `MidiImportHost { controller:
  shell.session.songDockController().midiImportController(); hostWindow:
  root; colors: root.colors; applicationSession: shell.session }` after
  `AboutDialog`. **Shared hot file.**
- `src/swift/app/shell/ShellPresenter.swift`: the following edits.
  **Shared hot file (task 222).**
  - `Action("file.import_midi")` directly after `Action("file.new_song")`.
    Put it in task 222's head file group.
  - `menuLabels["file.import_midi"] = "Import MIDI..."`.
  - `actionEnabled`: `case "file.import_midi": return session.projectOpen`.
  - `activate`: `case "file.import_midi":
    session.songDockController().midiImportController().requestImport()`.

Checks:
- `src/checks/editorqml/tst_ShellImportWizard.qml` (new).
- `src/checks/editorqml/ImportWizardProbe.swift` (new): a `QmlInstantiableStatus`
  check probe. It holds only check-side reads of files the app wrote:
  - `midiDivision(path:) -> Int`
  - `midiCfgFlags(projectRoot:label:) -> String`
  - `songTablePlayer(projectRoot:label:) -> String`
  - `fileExists(path:) -> Bool`
  - `fingerprint(path:) -> String` (reuse `TabsDrawerProbe`'s FNV shape; do
    not duplicate it if a shared helper exists).
- `src/checks/editorqml/ShellQmlTests.swift`: `ImportWizardProbe.registerQmlElement()`.
- `src/checks/CMakeLists.txt`: add `editorqml/ImportWizardProbe.swift` to
  `shell_qml_lane`. **Shared.**
- `src/checks/editorqml/ShellQmlEntries.swift`: the following edits.
  **Shared.**
  - Add `Entry(name: "shell-import-wizard", inputFileName:
    "tst_ShellImportWizard.qml", fixtureFiles: importFixture)`, where the
    private `importFixture` is `songs("mus_route101")` plus:
    `include/constants/songs.h`, `sound/music_player_table.inc`,
    `sound/voice_groups.inc`, `sound/voicegroups/dummy.inc`,
    `sound/voicegroups/fixture_alt.inc`, `ld_script.ld`, `charmap.txt`,
    `src/debug.c`, `test_midis/external_import.mid` and
    `test_midis/duplicate_setters.mid`.
  - Add `test_midis/external_import.mid` to the text-contrast entries'
    fixtures.
- `src/checks/editorqml/tst_TextContrast.qml`: `auditImportWizard(context)`,
  called from `test_songShellText`. **Shared with P4.**
- `src/checks/editorqml/tst_ShellMenus.qml`: in
  `test_forkMenuTopologyAndLabels`, insert `"file.import_midi"` after
  `"file.new_song"` in the File order and raise the File count by one.
  **Shared (task 222).**

Ledgers:
- `src/checks/onboardcheck/proof.import.txt`: the rows listed below and new
  S entries.
- `src/checks/visual/proof.dialogs.txt`: A022–A027, new S entries and the
  header tally.

Over the three-file cap: one mounted surface with one verification entry.
The QML files split at the fork's page boundaries.

# Prerequisites

- Task 232: the controller contract, used verbatim.
- Task 222 landed and was checkpointed, because it edits `ShellPresenter`'s
  File groups and `tst_ShellMenus`.
- Task 215 landed, because the catalog refresh sits on the Finish path.

# Interface contract (visual contract = fork clauses)

- **Picker**, `FileDialog { objectName: "shellImportMidiPicker" }`:
  - `title: qsTr("Import MIDI")`, `nameFilters: [qsTr("MIDI (*.mid)")]`,
    `fileMode: FileDialog.OpenFile`, and `currentFolder:
    controller.startFolder` (`workspaceui_samples.cpp:50-54`).
  - `onAccepted: controller.chooseSource(selectedFile.toString())`.
- **Warning**, `MessageDialog { objectName: "shellImportMidiWarning";
  buttons: MessageDialog.Ok }`:
  - `onWarningRequested(title, message)` sets `title` and `text`, then
    opens.
  - Its `parentWindow` is the wizard while the wizard is visible, and the
    host window otherwise.
- **Window**, `MidiImportWizard { objectName: "midiImportWizard" }`:
  - `title: controller.windowTitle`,
    `modality: Qt.ApplicationModal` (fork `exec()`),
    `transientParent: hostWindow`.
  - It is shown while `controller.wizardOpen`. `onClosing` and Escape call
    `controller.cancel()`.
  - Minimum size: `round(baseFontPx*60)` × `round(baseFontPx*44)`
    (`:586-587`).
- **ClassicStyle chrome**:
  - A header band on the Base-role surface (`colors.inputBackground`,
    `windowText`) holds the bold page title (`importWizardTitle`) and the
    subtitle (`importWizardSubtitle`, wraps), followed by an `outline`
    rule.
  - The page body sits on `windowBackground`.
  - An `outline` rule sits above a right-aligned button row, in this order:
    - `importWizardBack` "< Back": hidden on page 0.
    - `importWizardNext` "Next >": on pages 0–1; enabled on page 0, and on
      page 1 only when `identityComplete`.
    - `importWizardFinish` "Finish": page 2 only; enabled when
      `identityComplete && !controller.busy`.
    - `importWizardCancel` "Cancel".
  - Return/Enter triggers the visible default: Next, or Finish.
- **Page titles and subtitles**, verbatim:
  - Analysis (`:299-300`): "Check the MIDI file", with the source file name
    as the subtitle.
  - Identity (`:97-99`): "Song identity" / "Names the .mid file, the
    song_table.inc entry, and the songs.h constant."
  - Sound (`:193-196`): "Sound settings" / "The song's voicegroup and mid2agb
    flags — its entry in midi.cfg (or songs.mk). All of this can be changed
    later in Song Settings."
- **Analysis page** (`:302-392`):
  - Margins `layoutSpaces.three` and spacing `three`.
  - A form row: "The song will be used as:" beside the `importAnalysisPlayer`
    ComboBox. Its model is `analysisPlayers` and its `currentIndex` is bound
    to `playerIndex`. `onActivated` calls `selectPlayer`. Its tooltip is
    "Select Background music for a song. Select Sound effect for a sound.
    Also select it for a fanfare."
  - A `layoutSpaces.one` gap, then these texts:
    - `importFileTracks`, `importGameTrackLimit`
    - `importStatus`: bold, wraps
    - `importSummary`: wraps
    - The notices `importTrackAction`, `importPolyphony`,
      `importDefaultInstrument`, `importFormat` and `importControllerNotice`.
      Each uses `warningText` on `windowBackground`, wraps, and is visible
      only when its text is non-empty.
  - `importRescale` CheckBox: "Adjust note timing for the Game Boy Advance
    (recommended)". Visible when `offersRescale`, bound to `rescale`, and
    `onToggled` calls `setRescale`. Its tooltip is "Use this adjustment to
    make the note timing in Porydaw agree with the note timing in the game."
  - When `hasControllerRows`, a flat toggle `importControllerToggle` reads
    "CC commands" with a right/down arrow glyph.
  - It reveals `importControllerTable`, indented by `layoutSpaces.eight` and
    collapsed at open.
    - Headers: Controller | Function (stretch) | Events | In the game.
    - Uniform rows with no alternating fill.
    - An "In the game" cell uses `warningText` when `needsAttention`.
- **Identity page** (`:100-127`), as a form:
  - "Name:" beside `importSongName` (placeholder `mus_my_song`). In
    `onTextChanged`, `const accepted = controller.editLabel(text)`; when it
    differs from the text, restore it with the cursor rule from task 232.
  - Hint row: `importSongNameHint` in `errorText`, visible when non-empty.
  - "Constant:" beside `importSongConstant`, where `onTextEdited` calls
    `editConstant`.
  - "Player:" beside `importIdentityPlayer`. Its model is `identityPlayers`,
    it is bound to `playerIndex`, and it carries the same tooltip.
  - The label column is left-aligned (Fusion `QFormLayout`).
- **Sound page** (`:198-231`), as a form:
  - "Voicegroup:" beside the editable `importVoicegroup`. Its model is
    `voicegroupOptions`, its edit text is bound to `voicegroupText`, and it
    commits through `changeVoicegroupText`. Its tooltip is: The symbol is
    "voicegroup_" + this name (mid2agb -G).
  - "Master volume (-V):" `importVolume`, "Reverb (-R):" `importReverb` and
    "Priority (-P):" `importPriority`. Each is a SpinBox from 0 to 127.
  - `importExactGate` "Exact gate time (-E)", `importExtendedClocks` "48
    clocks per beat (-X)" and `importNoCompression` "Disable compression
    (-N)". Each sits in the field column.
- Geometry comes from `applicationSession.baseFontPx`/`layoutSpaces`, and
  fonts come from `typographyFonts.body` (the title uses a bold body). Do not
  use pixel literals.

# Implementation steps

1. Build the four QML files and the host. Keep each page self-contained
   (`required property QtObject controller`, `colors`, `typography`,
   `layoutSpaces`, `baseFontPx`). When a page is shown, give focus to its
   first control. The Identity page focuses the name field.
2. Mount the host in `ShellWindow` and add the `ShellPresenter` rows.
3. Write `tst_ShellImportWizard.qml`. It drives only production ingress: the
   File menu row, `picker.selectedFile` plus `accept()` (the
   `tst_ShellWindow` project-picker pattern), key or mouse clicks on
   buttons, and ComboBox activation by popup click or keys. Use `insert` for
   pastes. Use fixture literals, and never read expectations back from the
   controller. Test functions and the predicates they must carry:
   - `test_importRouteGateAndPicker`:
     - With no project, the File row `shellAction_file.import_midi` is
       disabled. With a project open and no song, it is enabled and reads
       "Import MIDI...", right after New Song.
     - With `lastImportDir` seeded to `<root>/test_midis`, clicking the row
       opens the picker with the fork title, filter and `currentFolder`.
   - `test_importReadFailureWarns`:
     - Accepting `sound/song_table.inc` shows `shellImportMidiWarning`
       titled "Import MIDI" with non-empty text.
     - No wizard appears, and the `lastImportDir` preference is unchanged.
   - `test_importWizardPageFlow` (dialogs A022/A024/A026):
     - Accepting `test_midis/external_import.mid` opens the wizard titled
       "Import MIDI — external_import.mid".
     - Page 0 shows its title and subtitle, and Back is hidden.
     - Next goes to "Song identity", and Next again goes to "Sound
       settings" with Finish shown.
     - Back returns to page 1.
     - Escape closes the wizard. `midi.cfg`'s fingerprint is unchanged,
       `sound/songs/midi/mus_external_import.mid` does not exist, and
       `lastImportDir` now holds the `test_midis` path.
   - `test_importAnalysisPage` (A057, A058, A069, A070, A071, A078):
     - The rescale box exists and is checked.
     - Both player combos exist.
     - Activating each analysis entry moves the identity combo to the same
       index, and its text begins with the analysis role name.
     - Choosing the `MUSIC_PLAYER_SE_1TRK` entry shows a notice that
       contains "mute track 2".
     - Activating identity index 0 returns the analysis combo to 0.
     - The CC toggle reveals the table with the four headers.
   - `test_importIdentityPage` (A063, A064, A065):
     - The name field has the placeholder "mus_my_song", and starts with
       "mus_external_import" and the constant "MUS_EXTERNAL_IMPORT".
     - Select-all, delete and `insert("MUS_Loud_3")` give "mus_loud_3" with
       the constant "MUS_LOUD_3".
     - Select-all, delete and `insert("mus 3!")` leave the field empty and
       Next disabled.
     - Typing "mus_route101" shows "A song named mus_route101 already
       exists." and disables Next.
     - Retyping "mus_external_import" re-enables Next.
   - `test_importFinishRegistersSong` (A056, A059, A060, A072):
     - Choose the SE_1TRK role and leave rescale checked.
     - On the Sound page, the voicegroup list contains "fixture_rich" and
       starts with "(create a new voicegroup for this song)".
     - Finish closes the wizard.
     - When no longer busy, the Songs dock lists `mus_external_import`
       without a warning badge.
     - The status text matches `^Created and registered mus_external_import
       \(song ID \d+\)$`.
     - `midiDivision` is 24.
     - `songTablePlayer` is `MUSIC_PLAYER_SE_1TRK`.
     - The tab count is unchanged, because no voicegroup was created (fork
       `reconcileSnapshot:195-204`).
4. Add `auditImportWizard`: activate the action, accept
   `test_midis/external_import.mid` through the picker, and audit each page
   (page 0 with the CC table expanded) through the audit's
   window/popup path. Then press Cancel.
5. Update the ledgers with `deno task proof:edit`:
   - Onboard:
     - NATIVE-SETUP with a staging reason: A053 (fixture copy), A054
       (project open) and A055 (fixture decode). The lane's staged copy,
       project open and source decode fail fast before the wizard
       predicates.
     - MATCHED to new message-anchored S entries (S060 onward, one per
       predicate, header `S0xx | test_… (shell-import-wizard lane) |
       src/checks/editorqml/tst_ShellImportWizard.qml`): A056, A057, A058,
       A059, A060, A063, A064, A065, A069, A070, A071, A072 and A078.
   - Dialogs:
     - MATCHED to S001–S003 (page-flow messages): A022, A024 and A026.
     - RETIRED-REPRESENTATION: A023, A025 and A027. Reason: a QWizard
       widget-tree region lookup that feeds only the frozen QWidget PNG
       comparison (A001). Page content is proven by S001–S003 and the
       onboard wizard predicates.
     - Update the header tally and the `Swift counterpart:` line.

# Acceptance predicate

On an open project, File → Import MIDI… opens the fork picker at the
remembered directory, refuses unreadable input with the fork warning, and
runs the three-page ClassicStyle wizard. The pages have the fork's texts,
defaults, synchronized players, name law, taken-name gate and rescale
choice. Finish registers the song on disk with the chosen player and the
rescaled division, and updates the Songs dock and status. Every new text
passes the contrast audit, and the named rows close on executed evidence.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-import-wizard --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-menus --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-text-contrast
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

Coverage:
- `shell-import-wizard` covers the route, picker, warning, page flow, the
  Analysis/Identity/Sound pages and one committed import.
- `shell-menus` covers the File order.
- `shell-text-contrast-*` (six entries) covers AA text on every wizard page.

Gaps:
- Offscreen lanes use Qt Quick's non-native `FileDialog`. Native NSOpenPanel
  delivery and the visual comparison are covered by Controller
  verification.

# Controller verification

- A native smoke run on macOS with `deno task build:app`: launch the app,
  open the fixture project, choose File → Import MIDI…, pick
  `test_midis/external_import.mid` from a copy, and step through all pages.
- Capture each page with the `capture-macos-app-window` skill next to the
  fork reference build (`build-asan/porydaw.app`, main checkout) on the same
  file. List every deviation (control types, order, labels, grouping,
  per-state visibility, focus) with its justification in the task report.

# Task-specific constraints

- Do not add a second picker or warning path in `ShellPresenter`. The
  controller signals are the only route.
- Do not bind `Window.visible` both ways. `wizardOpen` is the only authority,
  and user closing calls `cancel()`.
- The existing New Song tests and the other `tst_ShellMenus` assertions
  stay unedited, except for the single File-order pin.
- No `Qt.callLater`, no test-only properties, and no hard-coded pixels.
