# Task 210 brief — the New Song name field takes only the fork's accepted labels

# Context

Task 171 mounted a simple New Song prompt: a `TextField` plus
`ProjectService.isValidSongLabel` (`src/swift/app/ProjectService+Songs.swift:81-84`,
`^[a-z_][a-z0-9_]*$` + `SongName(label)` nonempty) gating Create. The fork's
acceptance contract is richer and lives on the identity field of the New Song
wizard (`newsongwizard.cpp:78-149` at the `fceecd88` oracle):

- `LowercaseNameValidator` folds typed capitals into lowercase and drops
  characters outside `[a-z0-9_]` per keystroke; the regex `[a-z_][a-z0-9_]*`
  additionally refuses a leading digit. The accepted set after validation is
  `^[a-z_][a-z0-9_]*$` — equivalent to Swift's regex over the folded text.
  Swift currently *refuses* "Mus_X" where the fork folds it to "mus_x",
  and lets invalid characters (e.g. "mu$ic", "9lives") sit in the field
  until Create is tried, where the fork's field could never hold them.
- `IdentityPage::isComplete` (`:134-149`) gates progress on nonempty name +
  nonempty constant *and* shows the red hint "A song named %1 already exists."
  while the name collides with any snapshot song. Swift gates Create only on
  `validNewSongLabel`; a same-name collision refuses only after accept with a
  dialog error, and there is no live hint.

`SongName::create` itself is empty-only validation
(`projectidentity.cpp:8-13`), already mirrored by `SongName.init?` in
`src/swift/project/ProjectIdentity.swift` — no value-type work needed. The
fork has no song-rename flow (track rename only), so this mounted prompt is
the whole surface.

Surface: the New Song prompt's name entry (`SongConfirmDialog.qml`,
`confirmation === "create"`) — folded+filtered input, live collision
hint and the taken-name Create gate.
Ledger spec: none. No open ledger row pins the name-field input mechanics
(visual chrome A007 is a `SongName::create` construction row parked with its
unported-dialog family). Feature port proven by presenter predicates and the
mounted prompt journeys; zero ledger edits.
Verify lanes: `deno task verify --filter swiftcore-projectsession --verbose`
(presenter predicates via `runSongListModelChecks` in
`src/checks/songlist/songlist_checks.swift`) and
`deno task verify:shell --filter shell-songs --verbose` (mounted journeys).

# Exact write set

Production:

- `src/swift/app/songlist/SongListPresenter.swift` — two public APIs on the
  existing presenter:
  - `normalizeSongLabel(_ text: String) -> String`: folds the input to
    lowercase, drops characters outside `[a-z0-9_]`, and refuses a leading
    digit (drops it, letting a later valid lead through), i.e. the folded
    `^[a-z_][a-z0-9_]*$` accepted set. Deterministic, allocation-light.
  - `songLabelTaken(_ label: String) -> Bool`: exact-match membership over
    the full snapshot listing — keep the unfiltered `setSongs` input (a
    private `allListings`) so a non-playable table row also trips the hint,
    matching `IdentityPage`'s `m_songs` (the snapshot, not the playable
    filter). `songs` stays the playable feed; add `allListings` beside it.
- `src/swift/app/ProjectService+Songs.swift` — `createSong(label:from:)`
  normalizes the accepted label once (`SongListPresenter.normalizeSongLabel`)
  before the existing guard, so service calls agree with the validated field.
  Keep `isValidSongLabel` unchanged for other callers.
- `src/ui/songview/quick/docks/SongConfirmDialog.qml` — name-field legs only:
  on text change, `nameField.text = controller.songListPresenter().normalizeSongLabel(text)`
  (preserve `cursorPosition` across the rewrite; normalization is idempotent so
  no recursion), `controller.newSongLabel = nameField.text`; a new
  `songConfirmationTaken` hint Label (`text: qsTr("A song named %1 already
  exists.").arg(nameField.text)`, `visible:` create-mode && taken && nonempty);
  OK gate becomes `controller.confirmation !== "create"
  || (nameField.text.length > 0 && !taken)`.

Checks:

- `src/checks/songlist/songlist_checks.swift` — presenter predicates:
  folding ("Mus_X" → "mus_x"), invalid-character drop ("mu$ic" → "muic",
  "9lives" → "lives"), empty/idempotent cases, `songLabelTaken` true for a
  playable row, true for a non-playable snapshot row (via `setSongs` with a
  `hasMid: false` listing — the presenter must store it in `allListings`
  even though the playable feed filters it), false for a free label.
- `src/checks/editorqml/tst_ShellSongs.qml` — mounted legs appended as new
  test functions (never edit the three existing New Song tests):
  - real keyClicks of capitals/invalid characters show only the folded,
    filtered text in `songNewName` and publish it to `controller.newSongLabel`;
  - typing the open song's label disables OK, shows `songConfirmationTaken`,
    and a fresh valid label re-enables;
  - the existing stray-collision test stays valid: "mus_stray_test" is
    unregistered so the hint stays off and the service-level refusal path
    still runs.

Ledgers: none.

# Prerequisites

None in-wave. Disjoint from 211/212 (write sets share no file; 211's mounted
journey lives in `tst_ShellMenus`, not `tst_ShellSongs`). Read sprint-3 §28.

# Interface contract (fork clauses)

- Folding (`LowercaseNameValidator`, `newsongwizard.cpp:78-88`): capitals
  entered by key or paste appear lowercase; never refuse-with-beep, always
  fold.
- Filtering (`QRegularExpressionValidator` on `[a-z_][a-z0-9_]*`, `:102-105`):
  characters outside the name alphabet never reach the field; a leading
  digit never leads. The field's text is always a folded `^[a-z_][a-z0-9_]*$`
  prefix, so the Create gate only needs nonempty + not-taken — matching
  `isComplete`'s `!name.isEmpty()` clause (the wizard's constant clause has
  no Swift counterpart: Swift's flow carries the source song's constant,
  task-171 layering).
- Collision completion (`:134-149`): while the entered name equals any
  snapshot song label, Create is disabled and the hint text is the fork's
  literal. Registry/stray-MIDI collisions (name absent from the snapshot but
  bytes exist) still reach the service refusal — the hint must not fire for
  them (`mus_stray_test` fixture proves it).
- Accept path (`SongDockController.acceptConfirmation`,
  `ProjectService.createSong`): the service sees the normalized label; a
  normalized-empty name refuses without touching disk (already covered by
  the existing `isValidSongLabel` guard — the normalized input makes it
  unreachable through the mounted field, which is the point).
- Status/failure seams unchanged: `operationFailed` remains the only error
  channel; the taken state is prompt-side gating, never an error.

# Implementation steps

1. `SongListPresenter`: add `allListings` (stored in `setSongs` before the
   playable filter), `normalizeSongLabel`, `songLabelTaken`.
2. `ProjectService+Songs.createSong`: normalize `label` first.
3. `SongConfirmDialog.qml`: rewrite-on-change normalization, hint label,
   OK gate.
4. `songlist_checks.swift`: the normalize/taken predicates.
5. `tst_ShellSongs.qml`: the three mounted legs.
6. Run both lanes; no ledger edits (zero open rows claimed).

# Acceptance predicate

Real typing and paste into the mounted New Song name field produces exactly
the fork's accepted strings (folded, filtered, digit-leading refused); a
name equal to any snapshot song disables Create with the fork's hint while a
free/stray-colliding name stays enabled and reaches the service refusal —
the fork's identity-field contract on the mounted prompt.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
deno task proof check --executed
```

# Task-specific constraints

One predicate per fork clause; independent literals (fixture labels typed by
the check, never read back); real production ingress only — normalization
runs through the mounted `TextField`/`onTextChanged`, the service sees the
accepted value; no test-only properties, no `Qt.callLater`, no hard-coded px
(the hint label follows `songConfirmationDetail`'s layout, no new geometry);
fail-closed staging (a failed normalize must disable Create, not fall
through). `validNewSongLabel` stays as the accept-path guard — the dialog
gate's nonempty+not-taken check applies to already-normalized text. Existing
New Song journeys must not be re-pinned or edited. Swift 6.4, comments ≤2
lines. Workarounds or architectural changes: stop and report.
