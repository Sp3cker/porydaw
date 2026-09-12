# Task 3: Comment and changelog cleanup

## Context

The ratified encoding leaves stale references behind: the `SongViewModel`
coverage-stat comment still names `--viewcheck`, a retired flag
(tools/checks_walls.ts:31-33; the counters are consumed by the eventviews
harness), and the user-visible behavior change has no CHANGELOG entry.

## Exact write set

- `src/ui/songviewmodel.h`
- `CHANGELOG.md`

## Prerequisites

Task 1 accepted (songviewmodel.h is in its write set; checkpoint it before
this task re-edits the file).

## Interface contract

The comment above `SongViewModel::unpairedNoteOns` names the eventviews checks,
not `--viewcheck`. `CHANGELOG.md` gains one entry under Unreleased → Changed
stating only user-visible behavior: piano-roll notes store start tick plus
duration; an unpaired note-on is a zero-duration span no longer drawn to the
song end; the dashed unterminated note border is gone.

## Required tree properties

1. No `--viewcheck` reference remains in `src/ui/songviewmodel.h`.
2. The Changed entry exists under `## [Unreleased]` → `## Changed` and adds no
   implementation vocabulary (no `ViewNote`, no `endTick`).

## Acceptance predicate

`grep pattern="--viewcheck" path="src/ui/songviewmodel.h"` returns no matches;
the CHANGELOG entry renders under Unreleased → Changed. Named checks:
`deno task format --check src/ui/songviewmodel.h`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No behavior change; do
not touch any other file.
