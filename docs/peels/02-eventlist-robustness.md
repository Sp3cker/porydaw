# Peel 02 — Event list robustness (remap-following + OOB guards)

Read `docs/peels/GROUND-RULES.md` first. **Depends on Peel 01** (needs
`SongDocument::revision()` and `TrackRemap`/`tracksRemapped`). Source: the
`src/ui/eventlistview.{h,cpp}` portion (~87 lines) of branch commit `552d2ee`.
Branch line refs: `git show specker/cleanup/psg-velocity-history-pr:src/ui/eventlistview.cpp`.

This is a small, self-contained bugfix bundle for the MIDI event list. No drawer
involvement despite living in the drawer's integration commit.

## What to port

1. **Follow the chunk across add/delete, not just move.** Replace the event list's
   `trackMoved(from,to,map)` handler (main `eventlistview.cpp:~1173-1191`, hand-rolled
   rotation arithmetic) with the `tracksRemapped(TrackRemap)` table lookup
   (branch `eventlistview.cpp:1080`): `m_currentChunk = remap.smfTrackMap[m_currentChunk]`.
   Today, adding or deleting a track while the event list is open leaves it pointed
   at the wrong SMF chunk.
2. **Track the selected chunk explicitly.** `currentChunk()` returns a tracked
   `m_currentChunk` member instead of deriving from the combo's `currentData()`
   (branch `:1642`), so the selection survives combo rebuilds.
3. **Revision guard on selection sync.** `syncTrackSelection()` bails when
   `m_document->revision() != m_documentRevision` (branch `:1174`) — a selection
   notification from a newer revision must not clobber the pre-remap owner.
4. **Six out-of-range guards.** Main indexes `m_document->smf().tracks[chunk]` with
   only a `chunk < 0` check; add `chunk >= int(tracks.size())` bails in
   `addEvent`, `insertCopyOfRow`, `showContextMenu`, `deleteSelected`,
   `updateCountLabel`, `selectEventRow` (branch lines 1490, 1510, 1524, 1604, 1630,
   1646). These are latent OOB reads on main.

## Explicitly exclude

- Anything referencing the drawer, `EditorViewState`, or drawer actions being
  disabled while the event list is up — different feature.
- Main's event list otherwise stays as-is (same-tick reorder, sync-follow, etc.).

## Tests

- Extend `--eventviewcheck` (see `src/eventviewcheck.cpp` for the harness idiom):
  open the event list on a chunk, add and delete OTHER tracks, assert the list
  still shows the same chunk's events; delete the viewed chunk's track and assert
  a sane fallback (no crash, valid chunk); drive each of the six guarded paths at
  a stale chunk index (the guard is the observable: no crash under ASAN).
- Negative-test the remap-follow probe (revert to rotation arithmetic → probe fails)
  and at least one OOB guard (remove it → ASAN aborts).
- Full ASAN sweep + ctest.
