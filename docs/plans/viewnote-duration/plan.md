# ViewNote duration

Replace the invented `ViewNote` endTick/unterminated presentation with
LMMS/Rosegarden pos+duration. Pixels stay at the roll camera. Duration 0 is an
empty span. PortSMF is not vendored — both user gates fail on the evidence in
[spec.md](spec.md#alternatives-considered).

## Accidental working-tree cutover — keep and ratify

The uncommitted `fork-main` diff (14 files, +53/−92) implements this plan:
`ViewNote` duration model + `endTick()` consumers, empty-span `noteRect`,
dashed-border deletion, and the check-corpus updates. Verified against
spec.md: struct (songviewmodel.h:17-26), projection (songviewmodel.cpp:74-103;
the closeout only counts unpaired ons), null rect before minimum width
(pianoroll_geometry.cpp `noteRect`), dash constants gone (pianoroll.h), checks
cut to `endTick()` with duration-0 re-pins.

Decision: keep the diff and ratify it through this plan's tasks. Reverting
would resurrect the dashed-border geometry and the song-end closeout only to
re-delete them. Fallback (only if the user prefers a clean history): revert
the task write sets to HEAD and execute Tasks 1–2 as implementation briefs —
they are property-shaped and hold for both paths.

Leave the other untracked `docs/plans/*` folders (time-editing,
automation-refresh-flags, automation-tabs-qml) alone: separate work.

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Projection/encoding conformance](task-1-brief.md) | Direct | Verify-and-repair against a fully decided struct+projection contract; single predicate | None |
| 2 | [Roll consumer conformance](task-2-brief.md) | SDD-track / qt-cpp-reviewer | Qt paint/hit geometry judgment: empty-span ordering, drag-preview and draw-pending math | 1 |
| 3 | [Comment and changelog cleanup](task-3-brief.md) | Direct | Two doc-line edits, no behavior | None |

Tasks 1–2 have disjoint write sets and may run SHARED_TREE. Compile/check only
after both land (Task 3 is doc-only).

## Global Constraints

- Every brief inherits this section. Write sets are closed; preserve unrelated
  changes. Refresh source sections before editing; LSP references for exported
  `ViewNote` field changes.
- Behavior lives in [spec.md](spec.md). No `unterminated` on `ViewNote`, no
  song-end bar, no 1-tick stub, no pixel fields, no strip move for unpaired
  ons, no `DocNote` edits, no PortSMF vendoring.
- Keep the dashed note-border deletion (`noteBorderDashLength` /
  `noteBorderDashGap` absent; Quick `addNoteBorder` solid). Do not restore it.
- Extend existing projection/roll fixtures. Delete the `UINT32_MAX+1` endTick
  pin; do not replace it with another overflow stub.
- Use `deno task` for format/build/harness. SHARED_TREE: implementers format
  their slice and run file-local inspection; focused checks are
  `DEFERRED_TO_CONTROLLER`.

## Verification policy

Controller runs once, after Tasks 1–2 (Task 3 needs only the format line):

```sh
deno task format --check src/ui/songviewmodel.h src/ui/songviewmodel.cpp src/checks/eventviews/viewbuckets_grid.cpp src/ui/songview/pianoroll.h src/ui/songview/pianoroll_geometry.cpp src/ui/songview/pianoroll_gestures.cpp src/ui/songview/quick/timelinequickview_pianoroll.cpp src/ui/songview/rangeedit.cpp src/ui/songview/timeruler_interaction.cpp src/ui/songview/trackvoiceops.cpp src/checks/rollcheck/identity.cpp src/checks/rollcheck/keyboard.cpp src/checks/rollcheck/timemenu.cpp src/checks/host/tst_rulergridmenu.cpp
deno task verify --filter eventviews --filter rollcheck --filter ruler-grid-menu --verbose
```

The ruler-grid-menu harness is named `ruler-grid-menu`
(src/checks/checkcatalog.cpp:413); filters are substring matches
(tools/run_checks.ts:527-530), so `--filter host` would not select it.

## Checkpoints

No commit is authorized by this plan alone. When the user authorizes
persistence: one checkpoint after Tasks 1–2 are accepted (the ratified
behavior change); the final handoff checkpoints Task 3 with any remaining
accepted work.

## Source anchors

| Owner | Current |
| --- | --- |
| [ViewNote](../../../src/ui/songviewmodel.h) | Dirty tree: `duration` + `endTick()`. HEAD: `uint32_t endTick` + `unterminated`. |
| [Projection](../../../src/ui/songviewmodel.cpp) | Dirty tree: duration 0 on note-on, stack close sets duration, closeout counts unpaired. HEAD: song-end extension to `tl.lengthTicks`. |
| [noteRect](../../../src/ui/songview/pianoroll_geometry.cpp) | Empty-span null rect before minimum width; camera seam `TimeCamera::displayX` (timecamera.cpp). |
| LMMS `Note` / importer | include/Note.h pos+length (int32 ticks); MidiImport.cpp:406-414 clamp; piano roll skips length 0. |
| allegro `Alg_note` | Double beats; unmatched ons kept at dur 0; reader-only vendoring is the only small shape — rejected. |
| Rosegarden | Event timeT+duration; `consolidateNoteEvents` extends orphans (it bakes a copy — N/A here); `MatrixElement` converts at paint. |
