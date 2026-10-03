# Task 181 brief — velocity gestures are byte/history-invariant on cancel, and handles track scroll in the same frame

# Context

Two pieces share one surface — the velocity drawer's mounted gestures.

1. The selectionkey gesture ledgers keep PARTIAL conjuncts the mounted lane
   "cannot observe" but the Swift check hosts can: full in-memory SMF-byte
   equality and exact undo-depth equality around velocity stem drags and roll
   note drags, plus a literal anchor for the active-gesture delivery clause.
   The fork staged real gestures and compared `document().smf().write()`,
   `revision()` and `undoStack()->count()` at the cancel point.
2. Controller-flagged defect (0504b68b follow-up): `VelocityPage.handlesOriginX`
   is a bridge scalar bound per delegate (`VelocityPage.qml:333`
   `x: page.pageModel.handlesOriginX`), so a scroll moves every handle one
   queued NOTIFY behind the roll. `OtherEventsBand` was fixed the same day with
   a container item `x: -band.overlayRoot.scrollX`; velocity needs the same
   container-translate.

Surface: the mounted velocity drawer — stem/overlap drag gestures, their
cancellation invariance, and scroll-stable handle painting.
Ledger spec:
`src/checks/selectionkey/proof.gesturevelocity.txt` A005, A006, A017, A018,
A019 (5 PARTIAL), fork `gesturevelocity.cpp:117,124,192,...` at pinned revision
`1d2d8a81` (`overlapNodeTargetsVisibleNode`, `velocityStemDragGuardsEdits`);
`src/checks/selectionkey/proof.gesturecommands.txt` A005–A007 (3 PARTIAL),
fork `gesturecommands.cpp:83,92,96` at pinned revision `c17d966f`
(`rollNoteDragGuardsSharedCommands` — Escape cancel restores bytes, selection,
revision, undo depth);
`src/checks/host/proof.tst_hostintegration.txt` A119 (PARTIAL —
song-null/song-replacement selection clearing conjuncts; voice-replace/null is
unreachable per A120) and A122 (GAP — the override cursor is never the
closed-hand pan cursor after gesture termination), fork
`tst_hostintegration.cpp:523,528` at `c17d966f`.
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose`,
`deno task verify:shell --filter shellwindow-velocity --verbose`, and
`deno task verify:qml --verbose` (editorqml-drawer, VelocityRaster/VelocityEditing
selectors) for the scroll-alignment predicate.
Blocked rows left untouched: hostintegration A083–A098 (task 180),
A162/A174–A185, and hostadapter A095's same-GUI-pass residue (the scroll fix is
proven by mounted alignment, not claimed against that row).

# Exact write set

- `src/checks/velocity/VelocityClickSelectionChecks.swift` — cancel/capture invariance predicates: full song bytes, revision, undo depth and selected IDs restored at the cancel point for the overlap-node drag and the selected-stem drag; song-null and song-replacement clear the note selection (A119's remaining conjuncts).
- `src/checks/velocity/VelocityClickCancellationChecks.swift` — same family if the cancellation hosts live there; the implementer picks one home, not both.
- `src/checks/rollcheck/note_commands.swift` — roll note-drag Escape-cancel byte/revision/undo-depth/selection restoration (gesturecommands A006/A007) and the live-gesture flag predicate with its literal message (A005's anchor conjunct).
- `src/checks/editorqml/tst_ShellWindowVelocity.qml` — mounted velocity Escape/MouseHints-cursor predicates: after gesture termination the published hint/cursor surface shows no pan cursor (A122) and the overlap/stem cancel restores selection on the mounted lane.
- `src/checks/editorqml/tst_EditorDrawerVelocityRaster.qml` — conditional scroll-alignment predicate for the container-translate fix (below); mounted, not model-level.
- `src/ui/songview/quick/drawer/VelocityPage.qml` — replace the per-delegate `x: page.pageModel.handlesOriginX` with a single container item translated by the local scroll origin (the 0504b68b `OtherEventsBand` pattern), so all handles move in the same evaluation pass as the scroll.
- `src/swift/app/drawer/velocity/VelocityPublication.swift` / `VelocityPage.swift` / `VelocityInteraction.swift` — conditional repairs only if the published values diverge under the new container.
- `src/checks/selectionkey/proof.gesturevelocity.txt` — A005/A006/A017/A018/A019 only.
- `src/checks/selectionkey/proof.gesturecommands.txt` — A005–A007 only.
- `src/checks/host/proof.tst_hostintegration.txt` — A119/A122 only.

# Prerequisites

The performance wave is committed at `0504b68b`; all write-set files are clean.
The container-translate pattern to mirror is `0504b68b`'s OtherEventsBand fix.
Read sprint-3 §22.

# Interface contract

Model-level invariance predicates compare the session document's serialized
bytes, revision and undo depth captured before the press against the values at
the cancel/termination point — the values the mounted lane cannot see, asserted
in the Swift check host. Mounted predicates deliver real keys and pointer input
to `tst_ShellWindowVelocity`'s production window. The scroll fix keeps every
handle inside one container whose `x` is the local scroll origin; no delegate
reads a queued bridge scalar for its own position. MouseHints cursor assertion
observes the published hint surface, not `QApplication::overrideCursor`.

# Implementation steps

1. Add the byte/revision/undo-depth cancel predicates to the velocity Swift
   checks for the overlap-node and selected-stem drags (gesturevelocity
   A006/A018/A019; give A005/A017 their literal-anchored gesture-delivery
   conjuncts).
2. Add the roll note-drag equivalents in `note_commands.swift`
   (gesturecommands A005–A007).
3. Prove A119's song-null/song-replacement selection clearing and A122's
   no-closed-hand-cursor in their owners.
4. Apply the container-translate fix in `VelocityPage.qml` and add the mounted
   scroll-alignment predicate.
5. Close the ten rows in the same commit, compact form.

# Acceptance predicate

Velocity and roll-note cancels restore the pre-press document byte-for-byte
with exact undo depth; scroll moves velocity handles with the roll in the same
frame; the shell velocity lane and editorqml-drawer velocity selectors stay
green.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-velocity --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
deno task proof check --executed
```

# Task-specific constraints

No `QCursor`/override-cursor test API; observe the published hint surface. The
scroll fix must not add a per-delegate fallback or a second origin binding —
one container, one translate. Do not touch `tst_ShellGridInput*.qml` (task 186)
or task 180's hostintegration/gesturecommands rows. Ledger serialization:
gesturecommands and hostintegration rows land through the single ledger writer
against disjoint A-row subsets.
