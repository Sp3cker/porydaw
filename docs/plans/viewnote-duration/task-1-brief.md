# Task 1: ViewNote pos+duration projection

## Context

Producer for Task 2. `ViewNote` carries start+duration per spec.md; Task 2 cuts
consumers over to `endTick()` and empty-span geometry. The property list below
holds whether the dirty tree is ratified (verify + repair) or the slice is
re-landed from HEAD (implement).

## Exact write set

- `src/ui/songviewmodel.h`
- `src/ui/songviewmodel.cpp`
- `src/checks/eventviews/viewbuckets_grid.cpp`

## Prerequisites

None.

## Interface contract

`ViewNote` matches spec.md: fields `noteId`, `startTick`, `duration`, `key`,
`velocity`, `track`; method `uint64_t endTick() const` returning
`uint64_t(startTick) + duration`. No `unterminated`, no `endTick` data member.

`buildSongViewModel` writes `duration = 0` on note-on, `duration = ev.tick -
startTick` on the stack close, leaves unpaired ons at duration 0, counts them
in `unpairedNoteOns`, and does not extend them or add strip rows.

`unpairedNoteOns` comment: counted, duration 0, still in `notes`.

## Required tree properties

1. The struct layout above, including the inline `endTick()` method.
2. Projection: no closeout writes a fake duration (`startTick + 1`,
   `lengthTicks`, song-end extension); the closeout only counts unpaired ons.
3. `quirkProjection`: the unpaired key-72 note at tick 100 has
   `duration == 0` and `endTick() == 100`; no `UINT32_MAX+1` last-tick
   assertion remains; the dropped-tracks clamp coverage stays.

## Acceptance predicate

`buildSongViewModel` unpaired ons have duration 0 and remain in `notes`;
ordinary paired notes keep `endTick() == startTick + duration`. Named checks:
file-local diagnostics on the write set; focused `eventviews` deferred to
parent SHARED_TREE.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: leaving
a closeout that writes a fake duration reintroduces the stub Task 2's geometry
would paint. Do not edit roll files.
