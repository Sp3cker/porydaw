# task-1-brief.md — Existing song-list service feed

## Context

The service contract needed by the Songs panel already exists in the current Swift rewrite. `pd_service_list_songs` returns `PdSongListEntry` values, and `ProjectService.songs()` exposes `[SongListing]`, including the playable flag, stable song ID, registration state, constant, and registration gaps. The implementation is consumed by the existing `SongListPresenter`.

## Exact write set

None. Keep the existing service bridge, Swift service, and checks unchanged:

- `src/project/swift_project_service.cpp` — `pd_service_list_songs`.
- `src/swift/app/ProjectService.swift` — `ProjectService.songs()` and `SongListing`.
- `src/checks/songlist/songlist_service.swift` — service feed and mutation proofs, already dispatched by `SessionChecks.swift` and included in the checks target.

## Prerequisites

None.

## Interface contract

- `pd_service_list_songs` supplies the current project snapshot to `ProjectService.songs() async throws -> [SongListing]`.
- Each listing retains `id`, `label`, `constant`, `player`, `midiPath`, `trackBudget`, `hasMid`, `hasCfg`, `registered`, and `registrationGaps`; `isPlayable` and `registrationIncomplete` are derived from that metadata.
- `songs()` returns the service listing, including playable unregistered songs. `songLabels()` remains a separate existing API; do not substitute it for the panel feed.
- The consumer is `SongListPresenter.setSongs(_:)` in `src/swift/app/songlist/SongListPresenter.swift`, which applies the playable-row policy.

## Implementation steps

1. Retain this existing bridge and its current Swift projection; do not add another C operation, entry type, or service method.
2. Keep the existing service-feed and service-mutation proof rows as the evidence for this contract.

## Acceptance predicate

- `deno task verify --filter swiftcore --verbose` passes the existing `swiftcore/SongList::serviceFeed` and `swiftcore/SongList::serviceMutations` proofs.

## Task-specific constraints

- Do not change `pd_service_list_songs`, `ProjectService.songs()`, or `songLabels()`.
- Do not add a parallel song-entry bridge, check file, dispatch call, or CMake source entry.
