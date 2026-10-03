# Task 95 brief — local capture and keyboard routing survive tab replacement

# Context

Own the visible input target's lifetime: automation-focused commands after tab
switch/close/reopen, pitch-bend opener capture/repeat, and velocity overlap/stem
capture followed by Escape and resumed window commands. This extends task 87's
keyboard pair outcomes, not its selected rows. The visible following velocity
node must be the same target that receives the subsequent edit command.

Verified selection: **35 open rows (25 GAP + 10 PARTIAL)**:

- `src/checks/selectionkey/proof.windowtier_lifetime.txt`: 18 — A002, A004,
  A005, A009, A012, A015, A017, A022, A032, A041, A043, A044, A049, A050,
  A052–A055.
- `src/checks/selectionkey/proof.localinputtier_pitchbend.txt`: 10 — A001,
  A006, A008–A011, A014, A015, A038, A039.
- `src/checks/selectionkey/proof.gesturevelocity.txt`: 7 — A001, A005, A006,
  A009, A017–A019.

Read the matching fork files at `fceecd88`, using each ledger's pinned
revision where the assertion extraction differs. `gesturevelocity.cpp` is
pinned at `1d2d8a819b851071e8b1ec5767832a17d9fc271e`: its A001 is a shared
**painted node-above-stem** predicate, not a generic QTest setup failure to
retire. Current successor seams are `drawerOriginalNumericPromptTransaction`,
`EditKeyArbiter`, the ShellWindow shortcuts, existing ShellTabs close/reopen
journeys and ShellPitchBend repeated-opener tests.

# Exact write set

- `src/swift/app/commands/EditKeyArbiter.swift` — conditional priority repair.
- `src/ui/shell/ShellWindow.qml` — conditional existing window-routing repair.
- `src/swift/app/drawer/velocity/VelocityInteraction.swift` — conditional capture/cancellation repair.
- `src/checks/selectionkey/localinputtier_text.swift`
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/editorqml/tst_ShellPitchBend.qml`
- `src/checks/selectionkey/proof.windowtier_lifetime.txt` — selected 18 rows only.
- `src/checks/selectionkey/proof.localinputtier_pitchbend.txt` — selected ten rows only.
- `src/checks/selectionkey/proof.gesturevelocity.txt` — selected seven rows only.

Do not write `EditorSurface.qml`, automation interaction/publication,
`tst_EditorDrawer.qml` or `tst_ShellGridInput.qml`; other Group B tasks own
those files. No new bridge probes, fixture content or registration changes.

# Prerequisites

Group B starts after Group A's accepted checkpoint. Rebase
`tst_ShellWindow.qml` over 91 and 87, `VelocityInteraction.swift` over 94,
`localinputtier_text.swift` over 87, and `ShellWindow.qml`/`tst_ShellTabs.qml`
over 84. Read 86's accepted `EditorSurface.qml` press-focus contract and
89's `DocumentSession.swift` lifetime changes. Preserve 84's full restored
view state and 91's standalone/range time-command separation.

# Interface contract

- Keep the existing key arbiter and ShellWindow shortcut dispatch interfaces.
  Commands follow the selected document/primary track, not a stale captured
  page. Pan/Tempo parameter activation and actual automation focus survive
  A→B→A selection, primary-track change and B close/reopen. The old sibling
  document remains byte-exact during reopened-tab Right/Up commands.
- Open the second song with one additional tab while retaining A; unwind
  edits to clean before closing. On reopen, a newly seeded tick-960 pair
  responds to routing, A's bytes remain unchanged and the reopened document
  can return to clean. Never use direct document nudge as mounted key proof.
- Resolve the real registered pitch-bend/Solo/Copy/Mute bindings. The
  tick-4800 note must be published and be the actual selected target before
  opening. A repeated eligible opener is consumed without opening another
  popup; dismissing the popup permits a real roll-focus/key journey again.
  Preserve task 87's shortcut priorities and intentional modal exceptions.
- The following velocity node paints above the selected earlier stem in
  idle, hover, selected and zoomed states. A drag at their overlap captures
  only the visible following node. Escape restores the pre-press earlier-note
  selection, exact bytes, revision and history, and leaves no live gesture.
  A subsequent click then Right moves only the following note.
- A selected velocity-stem drag retains its captured two-note selection.
  Edit keys during capture leave bytes/selection/revision/history unchanged;
  Escape preserves those values and ends the gesture. Each clause gets its
  own literal anchor rather than one aggregate assertion for all outcomes.
- Retire only lifetime A002/A049/A050 and pitch-bend A006: native tab pointer,
  seed-helper and Quick-window prerequisites superseded by these real mounted
  journeys. All other selected rows require behavioral evidence (31 MATCHED,
  four RETIRED-REPRESENTATION); never retire A001's raster outcome.

# Implementation steps

1. Extend the existing lifetime Swift transaction and mounted ShellTabs /
   ShellWindow journeys with exact per-document bytes, clean-history and
   input-target observations, through actual focus and key events.
2. Extend the existing ShellPitchBend opener test with publication/target,
   repeat and post-dismissal roll-routing clauses; no synthetic forwarding.
3. Add the overlap pixel/capture/cancel/resume and selected-stem key-suppression
   journeys to ShellWindow, using the existing real velocity drawer and frame
   capture facilities. Do not steal the editor-drawer check file from 96.
4. Repair only demonstrated owner divergence. **RED may be absent if
   production already matches; then the check is the deliverable.** Preserve
   all existing anchors and update only these 35 rows in the proving change.

# Acceptance predicate

Controller-run after Group B settles. The project-session lane covers the
existing lifetime transaction; the three mounted lanes prove actual shortcut,
focus, popup, raster and close/reopen behavior. Source-level focus claims or
Swift-only direct calls are insufficient.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --filter shell-tabs --filter shell-pitch-bend --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json`, `shellwindow.json`,
`shell-tabs.json` and `shell-pitch-bend.json` under `build/proof-evidence`.
Every process must finish in ≤180 s with the 175 s alarm after lock acquisition.
Full shell means all 26 lanes (~40 s warm); full verify (~10 s warm) is mandatory.
Offscreen raster/focus observations are not claims about physical macOS host
focus. Unselected text-prompt/event-list/native-host rows remain unchanged.

# Task-specific constraints

Apply sprint-3 §10: no new C++; Swift 6.4 idioms; comments ≤2 lines; base-font
sizing; WCAG AA before pixel parity. One keyboard authority, no second
 dispatcher, synthetic forwarding or focus memory; chrome never claims bare
Space. No `Qt.callLater` coalescing or new idempotence guards. One message
anchor per fork clause, old messages verbatim, real fixtures, no test-only
seams. Stage preferences through CFPreferences/UserDefaults, never plist
bytes. Fixture-content changes are excluded; an approved expansion first
lists every exact-content consumer. Workarounds need user approval. Parked
areas, deferred menus and savecore A016–A026 are outside this task.
