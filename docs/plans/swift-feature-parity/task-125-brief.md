# Task 125 brief — raw engine promotion preserves roll owners and complete retained view state

# Context

Finish roll identity across structural document edits. The concrete divergence is in EventEditing: insertRawEvent, modifyRawEvent and deleteRawEvents can change MidiFile.engineTracks(), but commit without TrackRemap. Consume task 118's complete cosmetic-state/remap producer and task 124's lane identities; do not build another state owner.

Verified planning selection: **30 open rows (13 GAP + 17 PARTIAL)** from sprint-3 §14.

- `src/checks/rollcheck/proof.identity.txt` — A009, A010, A011, A012, A013, A014.
- `src/checks/rollcheck/proof.remap.txt` — A006, A009, A012, A019, A022, A025, A032, A035, A038, A044, A045, A048, A049, A052, A056, A057, A058, A061, A062, A063, A064, A065, A066, A067.

Oracle: `fceecd88`; both source pins are `85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`.

# Exact write set

- `src/swift/core/EventEditing.swift`
- `src/swift/core/EventEditing+Helpers.swift`
- `src/swift/app/timeline/DocumentProjectionCache.swift`
- `src/swift/app/roll/PianoGrid+SceneSync.swift`
- `src/checks/rollcheck/identity.swift`
- `src/checks/rollcheck/remap.swift`
- `src/checks/editorqml/tst_ShellTabsReload.qml`
- `src/checks/editorqml/tst_ShellEventListMenus.qml`
- The two selected proof files, owned only by the separate ledger writer.
- Conditional deletion only: `src/core/songdocument_range.cpp`.

Closed list. Both ledgers are conditional full closures. The range translation unit additionally requires task 124's lane-selection closure and §14's complete remaining-use audit; retain it if any other open ledger still exercises its range/selection behavior. SongDocument, smf, songhistory and XCMD units remain blocked by other ledgers and are not write targets.

# Prerequisites

Accepted and checkpointed 118, including complete EditorViewState and remap-before-session-publication; accepted 124. Tasks 118/119 retain all their exact and split write paths. Existing ReloadedTab capture and in-place reload remain the runtime-state interface, not permission to edit ApplicationSession+Tabs.swift.

# Interface contract

- Preserve SongDocument.insertRawEvent(chunk:event:), modifyRawEvent(chunk:index:event:), deleteRawEvents(chunk:indices:) and editRawAndTempo. Use makeTrackRemap before commit whenever a raw edit changes engine ownership; unchanged engine ownership publishes no structural remap. Compare actual before/after engine maps, not event opcode guesses. Carry the mapping in the existing DocumentChange/history transaction so Undo/Redo use the existing inverse/composed mappings and the session reconciles owners before presentation.
- In the fork metadata-to-engine fixture, the previous owner moves from engine 0 to 1: primary 1, stored scope {1}, only track 1 soloed, retained active time selection, raw cosmetics on 1 and none on 0. Undo restores the original owner with the original complete value; Redo re-applies it. No native two-signal ordering surrogate is added: observe the single complete publication and the mounted consumer at that boundary.
- Complete existing move/add/duplicate/delete and Undo/Redo tables with the entire cosmetic state and explicit lane selection. Move maps CC identities and preserves Tempo. Insert/duplicate inherit no owner cosmetics. Delete drops removed-owner cosmetics/time selection, and Undo does not resurrect dropped transient selection. Metadata rename rebuilds the required document projection without changing cosmetics or owner addresses.
- Identity A011 uses the fork's base lane height 64, CC7 height 96, range 91 and empty-lane membership through 118's public value. A012–A014 capture, perturb, apply normalized values and restore all camera scale/scroll, selected track, edit cursor, grid denomination/feel and event-list visibility fields while retaining those cosmetics. Exercise existing ReloadedTab/in-place reload and live per-tab ownership; do not invent a second generic snapshot interface merely for the check.
- For A009/A010 load the ordinary source note at [240,288), key 65, velocity 83, track 2 and prove those visible/projected facts. Retire only the unassigned-ID field of the old hand-built MidiTimeline representation: the Swift document assigns stable NoteIDs on adoption. Do not assert that a new test-only projector is the production path or retire visibility because a type is internal.
- The actual Event List raw insertion and Undo/Redo must repaint/rebind the correct roll/header owner. Runtime-state restoration uses actual tab/reload input. Pair mounted outcomes with full original/edited/restored MIDI bytes, revision and history index/count in the registered checks.

# Implementation steps

1. Extend the existing registered identity/remap cases with independent complete-state expectations and the raw-promotion fixture.
2. Repair raw mutation remap publication at EventEditing and reuse the existing history/session consumers unchanged.
3. Extend the split Event List and tab-reload journeys to exercise the production consumer, including source-note visibility and complete retained runtime state.
4. Give the separate ledger writer executed clauses and the bounded unassigned-ID representation decision; close the two inventories and apply the conditional range-unit retirement gate.

# Acceptance predicate

Raw promotion and its inverse reach the mounted editor with correct owners before observation, every structural operation preserves/drops the exact fork state, and capture/apply restores all retained runtime fields without editing MIDI. No task-118 or task-119 file is modified.

The implementer runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-event-list-menus --filter shell-tabs-reload --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No DocumentSession, DocumentWorkspace, ApplicationSession, EditorViewStateCodec, automation publication, history representation or fixture-file writes. Keep existing remap/identity cases cohesive and every file at most 600 lines. If the prerequisite state interface fails its promised contract, return that concrete mismatch to its owner instead of silently reopening a reserved file.
