# Tick width

Introduce `Tick` / `kNoTick` / `kMaxTick`, reject overlong SMF ticks at parse, then narrow every musical position to `Tick`. Behavior: [spec.md](spec.md).

Layout reorders are a sequel, not this plan.

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Parse bound](task-1-brief.md) | Direct | Three files, one predicate, reversible strict-parse addition | None |
| 2 | [SMF, timeline, Tick, rescale](task-2-brief.md) | SDD-track / sdd-implementer | Alias + storage + `rescaleDivision` / `songFile` fail-closed | 1 |
| 3 | [xcmd vocabulary](task-3-brief.md) | SDD-track / sdd-implementer | xcmd / lanemoveplan tick width; identity fields stay uint64 | 2 |
| 4 | [SongDocument tick API](task-4-brief.md) | SDD-track / sdd-implementer | `loopTick` + time-editor overflow pin + player | 2, 3 |
| 5 | [Songview positions](task-5-brief.md) | SDD-track / sdd-implementer | Mechanical same-shape batch, closed per-file list | 4 |
| 6 | [Drawer and remaining UI](task-6-brief.md) | SDD-track / qt-cpp-reviewer | `EventTableModel` setData + `std::map` key width | 4 |
| 7 | [Checks sweep](task-7-brief.md) | SDD-track / sdd-implementer | Mechanical same-shape batch; deferred UI named checks | 4, 5, 6 |

Tasks 5 and 6 have disjoint write sets and may run SHARED_TREE after Task 4. Task 7 consumes both.

Do not start Tasks 3–4 while `docs/plans/time-editing` is executing on `songdocument*`.

## Global Constraints

- Every brief inherits this section. Write sets are closed; preserve unrelated changes. Refresh source sections before editing. Unlisted production file the compiler names is a brief defect — escalate, do not expand. Task 7: same rule for files outside `src/checks/`; an unlisted file **under** `src/checks/` the compiler names is also a brief defect (escalate), not a silent expansion.
- Behavior lives in [spec.md](spec.md). Positions are `Tick`. Durations stay `uint32_t`. Computed `start + duration` ends stay `uint64_t`. Sample / xcmd index / revision stay `uint64_t`. `setLoopTick(int64_t)` untouched as a signature. No `#pragma pack`, no PortSMF, no `std::optional<Tick>`, no strong `struct Tick`, no member reorders.
- A tick field and its tick-domain sentinel literals flip in the same task. Overflow / absent-loop **behavior** is pinned in that task’s named checks, not deferred to grep.
- Multiply-before-divide locals (`parseTrack` accumulator, `rescaleDivision` / `scaleTick` internals) stay `uint64_t`.
- Use `deno task` for format/build/harness. SHARED_TREE: implementers format their slice; focused checks follow the table below. Tasks 5 and 6 do not run harnesses whose sources live in Task 7.

## Verification policy

Controller, after each accepted task, format-checks that task’s write set then:

| After | Command |
| --- | --- |
| 1 | `deno task verify --filter smfcheck --verbose` |
| 2 | `deno task verify --filter smfcheck --filter onboardcheck --verbose` |
| 3 | `deno task verify --filter xcmdcheck --verbose` |
| 4 | `deno task verify --filter editcheck --filter savecheck --filter selectionkey-core --verbose` |
| 5 | `deno task build:app` |
| 6 | `deno task build:app` |
| 7 | `deno task verify --verbose` |

After 5–6, also grep that task’s write set: no tick-domain `UINT64_MAX` or `std::numeric_limits<uint64_t>::max()` remains. After 2–4 and 7: same grep on that task’s write set (`loop*Sample` and sample seeks may keep `UINT64_MAX`).

Task 7’s `verify --verbose` is the named-check run for roll / clipboard / drawer / automation / event-list / pitch-bend / loopcheck (those harness files are in Task 7).

## Checkpoints

No commit is authorized by this plan. When the user authorizes persistence:

- After Task 1 (Task 2 re-edits `smf.cpp`; Task 7 re-edits `tst_midismf.*`)
- Final handoff after Task 7

## Source anchors

| Owner | Current |
| --- | --- |
| [parseTrack](../../../src/core/smf.cpp) | uint64 accumulator, no 32-bit bound |
| [timedefaults.h](../../../src/core/timedefaults.h) | no `Tick` |
| [SmfEvent::tick](../../../src/core/smf.h) | `uint64_t` |
| [MidiTimeline loop ticks](../../../src/core/miditimeline.h) | `uint64_t` + `UINT64_MAX` |
| [rescaleDivision](../../../src/core/midiimport.h) | `void` |
| [NewSongWizard::songFile](../../../src/ui/newsongwizard.h) | returns `SmfFile`; rescale cannot fail |
| [DocNote::tick](../../../src/core/songdocument.h) | `uint64_t`; `loopTick` comment says `UINT64_MAX` |
| [ViewNote](../../../src/ui/songviewmodel.h) | `uint32_t startTick`; `endTick()` returns `uint64_t` |
| [GridSegment](../../../src/ui/songview/timeaxis.h) | four `uint64_t`; `next = UINT64_MAX` |
