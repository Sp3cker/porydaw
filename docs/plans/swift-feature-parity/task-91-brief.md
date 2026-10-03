# Task 91 brief — active-tab range Insert/Delete Time during playback

# Context

Own the shell's selected-range Insert Time and Delete Time journey, including
playback anchoring, track scope, one-edit history and inactive-tab isolation.
This is not task 81's no-selection insertion prompt or task 86's ruler menu.
Task 95 subsequently consumes this task's accepted `tst_ShellWindow.qml`.

Verified selection: **52 open rows (7 GAP + 45 PARTIAL)** in
`src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`:
A122, A126–A145, A176–A190, A192–A207. All are behavioral; none is a
representation retirement. The fork's `0xFFFF` scope means all used tracks,
not a requirement to restore a fixed-width Swift selection representation.

Oracle: `git show fceecd88:src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`,
`insertTimeActionAnchorsSelectionDuringPlayback` and
`deleteTimeActionRipplesScopedAndWholeSongSelections`. Current owners are
`EditorCommandRouter.isAvailable/perform`, `runTimeRoutingChecks` in
`session_time_routing.swift`, and the mounted
`test_jTimeSelectionInsertAndDeleteMutatesDocument`. The range transform
already lives in `AutomationSelectionCommands.consumeSelectionCommand`.

# Exact write set

- `src/swift/app/EditorCommandRouter.swift` — conditional selected-route repair.
- `src/checks/workspace/session_time_routing.swift`
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt` — only the 52 selected rows and their anchors.

No checked-in fixture, registration, ApplicationSession or automation owner
edits. Task 92 exclusively owns `AutomationSelectionCommands.swift` in this
group; a demonstrated defect there requires a coordinated contract correction,
not an alternate transform in the router.

# Prerequisites

Start only after 84/86/87/89 land and their accepted tree is checkpointed.
Rebase `tst_ShellWindow.qml` over 87; reread 84's
`ApplicationSession.swift`/`DocumentWorkspace.swift`, 86's `EditorSurface.qml`
press-focus/ruler ingress, and 89's `DocumentSession.swift`. Preserve those
interfaces. Group A is disjoint; no new API is produced for task 92.

# Interface contract

- Keep `EditorCommandRouter.isAvailable` and `perform` signatures and routing:
  an active time range goes to the existing range command, while insertion
  without a range still opens the ruler-owned prompt.
- For range insertion while playing, keep the selected start/end and track
  scope, park the edit cursor at the selection start rather than the playback
  head, bypass the prompt, and commit exactly one revision and one undo step.
  A seam note on a selected track advances by the interval width with its
  pitch unchanged; excluded tracks and the sibling document stay byte-exact.
  Stop and undo restores the original history position and song bytes.
- Track-scoped deletion bypasses the prompt, removes inside notes, shifts later
  notes left by the width, preserves earlier/excluded-track notes and the
  inactive song, clears the range and parks the edit cursor at its start.
  One undo restores the exact original bytes and history position.
- Whole-song deletion starts at zero, covers all used tracks and the tempo
  scope, removes the designated inside notes on every track, shifts the
  excluded-track later note to its exact expected tick, clears the range,
  leaves cursor zero, and is one reversible document transaction.
- Split each compound fork clause into independently anchored observations:
  enabled action, prompt absence, cursor, range start/end/scope, revision,
  undo index, each note result, bytes and inactive document. Do not turn
  an existing aggregate message into evidence for a newly untested clause.

# Implementation steps

1. Extend `runTimeRoutingChecks` using its real two-track and sibling-session
   fixtures. Seed only through existing document APIs; record actual IDs,
   serialized bytes, revision and history before each journey.
2. Exercise the three contracts above through the existing router, including
   a playhead before the selection start. Keep edit cursor and playhead
   observations separate; undo after stopping must restore the baseline.
3. Extend the mounted ShellWindow journey through actual menu/shortcut input,
   including playback and the whole-song range. Observe visible notes,
   active-tab routing and the absence of the insert prompt, not direct calls
   to the transform as a substitute for shell input.
4. Repair the router only if these predicates expose a route divergence.
   **RED may be absent if production already matches; then the check is the
   deliverable.** Update only selected rows with fresh executing evidence in
   the same surface change.

# Acceptance predicate

Controller-run after Group A settles, using sprint-3 §10's serialized policy.
The narrow Swift lane proves bytes/history/scope; `shellwindow` proves the
mounted menu/shortcut/playback path. Full shell and full verify are mandatory,
not optional substitutes for either narrow lane. Each process has a 175 s
alarm and must finish within 180 s; lock acquisition is serialized separately.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Evidence: `build/proof-evidence/swiftcore-projectsession.json` and
`shellwindow.json`, including the mounted journey functions. Full shell covers
all 26 lanes (~40 s warm); full verify is ~10 s warm. Exactly the selected 52
rows may leave GAP/PARTIAL; unselected routing rows remain untouched.

# Task-specific constraints

Apply sprint-3 §10: no new C++; Swift 6.4 idioms on touched Swift; comments
at most two lines; base-font sizing; WCAG AA beats pixel parity. Preserve the
single keyboard authority: no second dispatcher, synthetic forwarding or
focus memory; chrome never claims bare Space. No `Qt.callLater` coalescing or
new idempotence guards. One message-anchored predicate per fork clause;
preserve existing messages verbatim; real fixtures and no test-only seams.
Preferences, if touched by setup, use CFPreferences/UserDefaults, never plist
bytes. Fixture-content edits are excluded; widening that boundary requires
listing every exact-content consumer in the write set first. Workarounds
need user approval. Parked areas, deferred menus and savecore A016–A026 stay out.
