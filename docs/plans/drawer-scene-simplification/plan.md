# Drawer scene simplification

Status: architecture proposal, not an approved implementation design. Candidate 1 is the top recommendation; candidate 2 needs further design scrutiny. No new interfaces are proposed here.

## Scope and constraints

The review followed 55 recent commits through project startup, Sample Studio and drawer publication. Two independent read-only investigations covered startup and Sample Studio; the drawer investigation produced the candidates below.

- Preserve observable behavior, current Swift ownership and QtBridge declarations.
- Keep the existing QML adapters and publication/rendering seams. Do not introduce another owner or a generic adapter interface.
- Preserve font-relative geometry, unhinted typography, theme contrast, stable row identity and reuse, camera overscan, gesture previews and history.
- Keep actual display-list construction separate from row projection where their responsibilities differ.
- Treat locality and interface depth as the gains; no performance improvement has been measured.
- Do not add tests for result shapes, forwarding or source spelling. Test the existing production interfaces and rendered behavior.
- Reuse the recorded verification commands when implementing; reassess if scope changes or a command proves stale. The observed runtime lane is not a complete acceptance suite for either candidate.
- This document records the review, not authorization to implement either candidate. Select the candidate and settle its design before dispatch.

## 1. Collapse Velocity's duplicate scene results — Strong

### Files

- [VelocityScene.swift](../../../src/swift/app/drawer/velocity/VelocityScene.swift): `VelocitySceneSnapshot.build`, `buildAxisAndHandles`, `axisAndHandles`, and `VelocityAxisAndHandles.init(_:)`.
- [VelocityPublication.swift](../../../src/swift/app/drawer/velocity/VelocityPublication.swift): `rebuildContent`, `buildScene`, `refreshAxisAndHandles`, `projectHandles`, and `publishDisplayLists`.

### Problem

The full and scoped builds run the same `axisAndHandles` computation. The full result flattens ruler rows into separate fields; publication immediately converts them back into `VelocityAxisAndHandles`. Comments still claim the full build produces grids and PSG bands, but `publishDisplayLists` builds those separately.

```text
Before:
  rebuild -> full result -> grouped result -> publication
  hover   -> grouped result                -> publication

After:
  rebuild / hover -> same result -> publication
```

### Proposed change

Use one result path for rebuild and hover publication, removing the redundant result representation and conversion. Retain the genuinely narrower handle-only gesture path and the existing display-list construction.

### Deletion test and benefits

Deleting the full/scoped result distinction removes interface facts without distributing axis or handle computation among callers. The existing module's implementation remains authoritative.

- Depth: smaller internal interface, same behavior.
- Locality: remove conversions and misleading distinctions.
- Leverage: rebuild and hover share one result.
- Tests: keep production behavior as the surface.
- Dependency category: in-process; existing QML adapter and display-list seam stay unchanged.

### Preservation and verification

Preserve hover/detent axis refresh, full content rebuilds, handle-only gesture updates, geometry reuse, camera refresh and display-list publication. Do not merge these distinct update responsibilities merely because two result shapes are redundant.

The mounted verification below exercises Velocity early/late unlock and real drag rendering. Before implementation dispatch, supplement it with the existing presenter checks covering axis/ruler publication, hover, detents, reuse and camera behavior; the mounted lane alone does not prove every preserved path.

## 2. Remove Voice-change Drawer's shallow snapshot staging — Worth exploring

### Files

- [VoiceChangesScene.swift](../../../src/swift/app/drawer/voicechanges/VoiceChangesScene.swift): `VoiceChangesSceneInput`, `VoiceChangesSceneSnapshot.build`, and the projection calls they stage.
- [VoiceChangesPublication.swift](../../../src/swift/app/drawer/voicechanges/VoiceChangesPublication.swift): `rebuildContent`, `sceneInput`, `projectMarkers`, and `publishDisplayLists`.
- [VoiceChangesPage.swift](../../../src/swift/app/drawer/voicechanges/VoiceChangesPage.swift): `detach`, which uses the detached snapshot to publish empty gutter content.
- [VoiceChangesProjection.swift](../../../src/swift/app/drawer/voicechanges/VoiceChangesProjection.swift): existing marker, gutter and readout rules to preserve.

### Problem

The snapshot passes through track availability and marker entries, then packages gutter and readout calculations. Marker projection and actual display-list construction happen separately. Understanding a rebuild therefore crosses shallow staging that does not own the complete drawing behavior.

```text
Before:
  drawer -> scene input -> snapshot -> drawer publication

After:
  drawer -> existing projection rules -> publication
```

### Proposed change

Fold snapshot staging into the existing drawer module's implementation while retaining meaningful projection rules. Do not introduce a replacement publication owner or discard useful pure geometry and context calculations.

### Deletion test and benefits

Removing the snapshot should concentrate build facts in the existing publication implementation, not scatter projection decisions among QML or interaction callers. If it merely replaces a compact input with duplicated argument assembly, reject that design.

- Depth: remove shallow staging, retain rules.
- Locality: build facts stay with publication.
- Leverage: rebuild and detach need fewer concepts.
- Tests: observe markers, readouts and actual drawing.
- Dependency category: in-process; existing QML adapter and publication seam stay unchanged.

### Preservation and verification

Preserve marker identity/reuse, label geometry, context readout, gutter text, detached-state publication, gesture previews, hit testing, camera projection and actual display lists.

The mounted verification below exercises Voice Change drag commit/cancel and rendered preview retirement. It does not exhaust gutter, readout or detach behavior. Settle the deletion's design and select existing presentation/lifecycle coverage before implementation dispatch.

## Existing runtime observation

```sh
deno task checks:shell --filter shell-drawer-parity-voice-velocity --verbose
```

Observed on 2026-10-01: build succeeded; `shell-drawer-parity-voice-velocity` passed in 13.45 seconds; runner reported `1/90 ok`, with 89 entries skipped by the filter.

The mounted production shell exercises Voice Change drag commit/cancel, raster preview assertions and undo, plus Velocity early/late unlock. This is evidence for current behavior, not proof of an unimplemented refactor.

No source code was changed during the review.

## Rejected alternatives

- **Extract a project startup/replacement owner:** `ApplicationSession` already owns prefetch/adoption, close gates, tab retirement, resource lifetime and publication. Same-type extensions partition implementation, not competing owners. Another module would mainly relocate that sequencing.
- **Extract Sample Studio commit orchestration:** `SampleStudioWorkflow.accept()` already hides commit, provenance, catalog refresh and optional assignment ordering. The presenter owns editor history; the project modules own registration and shared-bank rebind. Moving private code into another owner would not deepen the caller interface.

## Top recommendation

Start with candidate 1: the redundant result distinction is demonstrated in the current implementation, its deletion is bounded, and it does not require a speculative abstraction. Explore candidate 2 only after its staging can be removed without duplicating projection inputs.
