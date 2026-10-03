# Task 163 brief — reload drops a stale primary track instead of installing it

# Context

Review159 found a production defect in the tab-restore path:
`src/swift/app/ApplicationSession+Tabs.swift:177` installs
`session.selectedTrack = tab.selectedTrack` unfiltered, while its direct neighbors at
`:187-189` intersect `tab.selectedTracks`/`mutedTracks`/`soloedTracks` with
`usedTracks` (`0..<session.document.engineTracks.usedTrackCount`, computed at `:186`).
A `ReloadedTab` captured from a live session whose primary indexes a track the reloaded
document does not have (the live tab had grown used tracks through unsaved edits, the
on-disk MIDI still has fewer) installs a primary beyond `usedTrackCount`. Consequences
flow from `DocumentSession.selectedTrack`'s `didGet` contract
(`src/swift/app/DocumentSession.swift:91-104`): the primary drives track-header
highlight, note lookup (`:280`) and selection scoping against a nonexistent track.

This is a Swift-internal consistency defect, not a fork clause: the fix makes `:177`
match its neighbors' filter, and the regression proves it on the mounted reload
surface. No ledger row is attached and the regression predicate carries no A-id.

# Exact write set

- `src/swift/app/ApplicationSession+Tabs.swift` — the `if let tab` restore block only.
- `src/checks/editorqml/tst_ShellTabsReload.qml` — one new regression leg.

# Prerequisites

None. Disjoint from in-flight Task 158 (`tst_SwiftRollTrackHeaders.qml`,
`proof.tst_hostadapter.txt`, `TrackHeadersGeometry.swift`). Read sprint-3 §19 for
shared constraints.

# Interface contract

Preserve `openTab(label:at:restoring:)`, `ReloadedTab` and every retained field's
semantics. The change: hoist `let usedTracks = 0..<session.document.engineTracks.usedTrackCount`
above the restore assignments and install
`session.selectedTrack = tab.selectedTrack.flatMap { usedTracks.contains($0) ? $0 : nil }`
— a stale primary drops to nil (no invented default track), exactly matching the
neighbors' drop-invalid semantics; `:187-189` reuse the hoisted range. Nothing else in
the block changes: editCursor, grid, scale and note-filtering behavior stay identical.

The regression extends the mounted reload journey family in `tst_ShellTabsReload.qml`
(its nine-field retention test is the pattern): stage a live tab whose primary exceeds
the on-disk song's used tracks — select the higher track and draw a note there through
real input so the track is live-used and selected — then trigger the in-place reload
(`session().openSong` on the already-open selected tab, accepting the real reload
prompt machinery this file already drives). Assert the landed tab's primary is not the
stale index and resolves inside the reloaded document's used tracks, and that the
filtered multi-track selections still restore as before. Expected values are
independent literals (the fixture's on-disk used-track count), never read-back.

# Implementation steps

1. Apply the production filter exactly as specified; keep one `usedTracks` computation.
2. Add the regression leg: higher-track note + selection, real reload trigger, prompt
   acceptance, landed-primary assertions plus the unchanged neighbor-field retention.
3. Run the reload lane and confirm the pre-fix journey would fail the new leg (verify
   by reasoning over the old code path in the report; do not commit a broken state).

# Acceptance predicate

A reload cannot install a primary the reloaded document does not have; all nine
retained-view fields of the existing journey still round-trip. `ShellQmlEntries.swift`
registers `shell-tabs-reload` for this file.

Named checks under §19 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-reload --verbose
deno task proof check --executed
```

# Task-specific constraints

No `SessionChecks.swift`, no `tst_ShellTabs*.qml` file other than the reload one, no
ledger edits, no new API on `ReloadedTab`. The dirty-tab reload prompt is part of the
journey: drive its real control, do not bypass with a direct `reloadApproved` call.
