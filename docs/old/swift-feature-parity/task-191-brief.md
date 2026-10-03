# Task 191 brief — selection and byte invariance across the mounted tab lifecycle

# Context

Three small ledger tails share one mounted surface family — real input that
must leave a document byte-identical across tab lifecycle events:

- `windowtier_lifetime` A054 (PARTIAL): the fork compares the first document's
  in-memory serialized bytes before and after edits made on a reopened second
  tab (`windowtier_lifetime.cpp:243` `documentA.smf().write()`); S083–S089
  prove only the saved-file fingerprint, not the unsaved document's bytes.
- `windowtier_keyboard` A103 (PARTIAL): bare Space must leave the fork's
  **two-lane** automation selection unchanged; the mounted journey
  (`test_kParameterTabActivationAndTapCession`) selects only one lane.
- `tabs_transport` A050 (PARTIAL residue): the stationary output-dial click
  leaves the exact undo count/index unchanged — S227 proves "no song undo"
  but not the index equality the fork asserts.

Surface: mounted tab close/reopen, bare Space over a two-lane automation
selection, and the stationary volume-dial click — each preserving exact
document/history invariance.
Ledger spec:
`src/checks/selectionkey/proof.windowtier_lifetime.txt` A054, fork
`windowtier_lifetime.cpp:243` at `c17d966f`;
`src/checks/selectionkey/proof.windowtier_keyboard.txt` A103, fork
`windowtier_keyboard.cpp:430` at `c17d966f`;
`src/checks/workspace/proof.tabs_transport.txt` A050, fork
`tabs_transport.cpp` at `02dce75d` (stationary click's exact undo index).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-drawer --verbose`,
`deno task verify:shell --filter shellwindow-parameter-keys --verbose`,
`deno task verify:shell --filter shell-transport-volume --verbose`, and
`deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: tabs_transport A062 (physical audio readback —
`NativeAudio.updateSettings` has no observable Null-backend counterpart);
windowtier_lifetime/keyboard are otherwise closed ledgers after these rows.

# Exact write set

- `src/checks/editorqml/tst_ShellTabsDrawer.qml` — extend
  `test_sharedDrawerCloseAndReopen`: reopen a second tab, edit it, then assert
  the first document's serialized bytes are byte-identical to the pre-reopen
  snapshot. If the mounted lane cannot see in-memory bytes, pair it with the
  Swift-side predicate below rather than approximating with file bytes.
- `src/checks/selectionkey/localinputtier_text.swift` — the Swift-side
  byte-equality conjunct for A054 (`drawerOriginalNumericPromptTransaction`'s
  sibling): encode the first document before reopen and after the second
  tab's edits, compare byte-for-byte.
- `src/checks/editorqml/tst_ShellWindowParameterKeys.qml` — stage the fork's
  two-lane automation selection, tap Space twice through real key input,
  assert the lane range and note selection are unchanged (A103).
- `src/checks/workspace/session_edit_routing.swift` — model conjunct for the
  two-lane Space preservation if the mounted read cannot express the lane
  set (S215/S216's sibling).
- `src/checks/editorqml/tst_ShellTransportVolume.qml` — the stationary
  click's exact undo index/count equality around
  `test_outputDialIncrementalDrag`'s press-without-drag point (A050).
- `src/swift/app/` — conditional repair only where a predicate provably
  fails (e.g. Space mutating a multi-lane selection, or the stationary dial
  click moving the undo index).
- `src/checks/selectionkey/proof.windowtier_lifetime.txt` — A054 only.
- `src/checks/selectionkey/proof.windowtier_keyboard.txt` — A103 only.
- `src/checks/workspace/proof.tabs_transport.txt` — A050 only.

# Prerequisites

All write-set files are clean at `85a806f9`. Read sprint-3 §23. The A054
byte comparison must use an independent in-memory snapshot — the fork compares
`documentA.smf().write()`; the Swift equivalent is the document's encoded
bytes, not the saved file. Confirm the two-lane automation selection can be
staged through published presenter/API input, not a test-only setter.

# Interface contract

Each clause keeps the fork's shape: serialized-byte equality across the
reopened-tab edit, selection/lane-range preservation across bare Space, exact
undo index/count preservation across the stationary click. Independent
literals; opaque pre-stimulus snapshots are allowed (the fork snapshots the
document). One predicate per fork clause with its unique literal message.

# Implementation steps

1. Read the three fork sites (`windowtier_lifetime.cpp:243`,
   `windowtier_keyboard.cpp:430` at `c17d966f`; the stationary-click clause in
   `tabs_transport.cpp` at `02dce75d`) for the exact staged inputs.
2. Extend the mounted journeys for the two-lane Space selection and the
   stationary-dial undo index; pair the byte-equality conjunct with the Swift
   check.
3. Repair the publication only where a predicate provably fails.
4. Close A054, A103, A050 in the same commit, compact form.

# Acceptance predicate

The reopened-tab edit leaves the first document's bytes identical; bare Space
preserves the two-lane selection; the stationary dial click preserves the
exact undo index — all with executed evidence on the named lanes.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-drawer --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-parameter-keys --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport-volume --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

No saved-file fingerprint substitutions — A054 wants the in-memory document.
No second Space tap count or approximate lane reads — the fork's clause names
the selection, not the gesture. Sole wave-23 writer of the two selectionkey
ledgers and of `tst_ShellTransportVolume.qml`/`session_edit_routing.swift`;
189 owns `session_editor_semantics.swift` and the tabs_scale ledger, 193 owns
`session_view_state_fanout.swift` and the state ledger. Do not touch
`tst_ShellTabsClose.qml` (188).
