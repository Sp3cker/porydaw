# Feature peels from `specker/cleanup/psg-velocity-history-pr`

The source branch bundles many features on top of a ~12k-line "editor drawer"
rewrite that main is not adopting. Each file here is a self-contained brief for
ONE independently implementable, reviewable, and testable feature, written for an
agent with no other context. Every brief starts by pointing at
`GROUND-RULES.md` — the shared method, build/test ritual, and conventions.

Already done (for reference, not a brief): **Pencil Mode** — merged to main as
`e5a5393` + `ad7ec32` + `6d48df5`; study those commits as the model peel.

## The peels

| # | File | Feature | Size | Depends on | Recommendation |
|---|---|---|---|---|---|
| 01 | 01-document-contracts.md | NoteId/revision/batch APIs + 4 hidden document fixes | L | — | Do first; prerequisite for 02, 03 |
| 02 | 02-eventlist-robustness.md | Event list follows track add/delete + 6 OOB guards | S | 01 | Clear win |
| 03 | 03-velocity-lane.md | Velocity lane with PSG detents (flagship) | XL | 01 | The headline feature; milestone-driven |
| 04 | 04-automation-node-selection.md | Band selects nodes; group drag; group delete | M | (01 helps) | DONE 2026-08-12 — branch `peel/04-automation-node-selection` (`fe94597`+`e8fad4f`), swept, awaiting user review/merge |
| 05 | 05-automation-point-menu.md | Point context menu + ContextMenu extraction + 2-D hit test | M | — | DONE 2026-08-12 — branch `peel/05-automation-point-menu` (`d553901`+`031bf17`), swept, awaiting user review/merge; right-click-delete UX change + Set-value duplicate healing flagged |
| 06 | 06-automation-axis-lock.md | Shift axis-lock on point drags | S | — | Clear win; one Shift-on-dot rule change (flagged) |
| 07 | 07-automation-hover-labels.md | Hover ring, voice-row readout, gesture value chips | M | — | Polish; low risk |
| 08 | 08-automation-lane-hiding.md | Hide/unhide lanes + lane-menu improvements | S/M | — | Clear win |
| 09 | 09-automation-grid-snap.md | Meter-aware sweep/ramp stepping + detent radius | S | — | Bugfix-grade |
| 10 | 10-automation-arrow-redesign.md | Arrow click = cursor/delete instead of write/no-op | M | 05 (pairs) | ⚠ USER DECISION before any work |
| 11 | 11-velocity-drag-selection.md | One-shot selection replace across Ctrl-drags | S | — | Refinement; hidden-state UX flagged |
| 12 | 12-fonts-hinting.md | Hinting policy + system-font toggle fix (+2 blocked items) | S | — | 12a/12b land; 12c/12d need user/author input |
| 13 | 13-harness-determinism.md | Windows sweep determinism | XS | — | DONE 2026-08-11 — MERGED to main `3784b6d` (ff, swept); Windows sweep check owed |

## Scheduling constraints

- **Peels 04–10 all edit main's `AutomationArea` inside `src/ui/songview.cpp`
  and extend the same rollcheck harness — run them SERIALLY** (any order except
  10-after-05), each merged (or at least rebased) before the next starts.
  Parallel agents on these will conflict on every hunk.
- 01 → 02 → 03 is the other chain. 11 touches the roll's velocity-drag code in
  songview.cpp (distinct region from 04–10, but serialize against them anyway if
  convenient). 12 and 13 are fully independent — safe to run in parallel with
  anything.
- Suggested batch order: 13, 12a/12b, 01, then {02, 09, 06, 08} (small wins),
  then 04, 05, 07, 11, then the user decision on 10, then 03 (largest, benefits
  from everything else being settled).

## Deliberately NOT ported (do not resurrect without a new decision)

- **The overlay drawer chrome** (`editordrawer.*`, `drawersections.*`, the A/V
  hard-coded window shortcuts, `EditorViewState`, viewsidecar rewrite,
  `splitterSizes` removal) — replaces main's working splitter/lanes pane,
  Windows-only styling hacks, hard-couples the pages. Each peel re-hosts its
  behavior in main's architecture instead.
- **Branch regressions**: automation surface losing `handleEditKey`
  (copy/cut/nudge/transpose), lost right-click voice-marker delete, area-local
  automation clipboard breaking interop with `SongView::Clip`, Ctrl+wheel row
  zoom losing cursor anchoring, `ContextMenu` dropping the `rect().contains()`
  guard. The relevant briefs call these out as keep-main / restore-guard.
- **Already on main in equivalent form**: pencil commits `6023635` (DPI cursor)
  and `8a74af1` (text-input guard — main's handleEditKey dispatch makes it
  structurally unnecessary).
- The `automation.pencil_mode` keymap registration on the branch (Context::
  Automation) vs main's (Context::PianoRoll): main's stands; never import the
  branch's duplicate.

## Bookkeeping

These files are UNCOMMITTED planning docs (matching prior plan-doc practice). If
an executing agent runs in a git worktree, hand it the brief's CONTENT or commit
this directory first — a worktree won't see uncommitted files. When a peel lands
or a decision is made (10, 12c, 12d), update the brief and this table in place.
