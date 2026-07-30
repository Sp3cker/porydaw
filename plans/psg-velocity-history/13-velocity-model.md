# 13 — Pure PSG velocity model and axis

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/velocity-model`  
**Worktree:** `13-velocity-model`  
**Base:** `INFRA_SHA`.

`git-operations-runner` creates/verifies the `13-velocity-model` worktree and `task/psg-velocity/velocity-model` branch from the exact `INFRA_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

This initial foundation task runs in parallel with 10A, 12A, and 12B. The task agent
writes implementation, its dedicated check, and one commit, but does **not** build,
test, format, lint, or validate. The coordinator runs the focused command once after
the completed foundation wave; a `reviewer` agent then reviews the committed range.

## Exclusive paths

1. `src/core/psgvelocitymodel.h`
2. `src/core/psgvelocitymodel.cpp`
3. `src/ui/velocityaxis.h`
4. `src/ui/velocityaxis.cpp`
5. `src/psgvelocitymodelcheck.cpp`

Do not edit `SongDocument`, `NoteId`, `SongView`, `TimelineSurface`,
`PlayheadOverlay`, `AutomationPage`, `EditorViewState`, layout sources, a
velocity page/area, `mainwindow.*`, CMake, main dispatch, or another packet's
test harness. Packet 05 conditionally registers this group only when the new
`src/psgvelocitymodelcheck.cpp` sentinel and its exact five-file set are
present.

## Contract

Publish document-free primitives only:

- `PsgVelocityContext` resolves voice/key context, represents invalid and unresolved
  contexts explicitly, describes detents/graduations, and compares compatibility.
- Canonicalization maps a proposed continuous velocity through *each note's own* PSG
  context while retaining exact DirectSound and unresolved values.
- An origin-aware intrinsic-level conversion restores the exact stored velocity when
  a gesture returns to its origin level.
- `VelocityAxis` is a data/presentation contract with continuous and intrinsic modes,
  labels, graduations, accessible description, and supplied resolved semantic layout
  geometry.

The axis does not know `SongDocument`, selection ownership, gestures, Undo, or a
screen-local geometry constant. Its caller supplies resolved layout geometry, so it
can be developed independently of 12A and then bound during foundation integration
without a competing layout-source edit.

## Required behavior and edge cases

These pure primitives satisfy **VEL-03** and **VEL-04**:

- DirectSound, invalid voice context, unresolved context, a mixed PSG/PCM selection,
  or incompatible PSG contexts select a continuous axis.
- A compatible PSG selection selects the matching Square, Noise, or Wave intrinsic
  graduations. An origin-level return preserves the exact stored value; another level
  uses that level's representative.
- For a continuous mixed/incompatible edit, one proposed velocity delta applies to
  the complete snapshot, then each PSG note canonicalizes through its own context
  while DirectSound stays exact. A proposal of 65 yields Wave 64, Square/Noise 68,
  and DirectSound 65 for those corresponding contexts.
- Labels and graduations describe the actual available levels, use the supplied
  semantic geometry, and expose the exact continuous or intrinsic accessible
  description. Nodes and graduation labels are not focus targets.

No drawer-context tick lookup, selection, relative/freehand gesture, preview,
document-batch submission, or Undo implementation belongs here.

## Dedicated check, review, and handoff

`src/psgvelocitymodelcheck.cpp` provides deterministic pure-model/axis coverage for
DirectSound and invalid-context continuous fallback; compatible and incompatible
selection; Square, Noise, and Wave graduations; canonical mixed values; origin exact
restoration; label layout; and continuous/intrinsic accessible descriptions with no
node or graduation-label focus target. It is not a UI integration or source-audit
gate.

After the task commit, the coordinator runs the packet-05 registered
self-contained `porydaw --check-velocity-model` command once. A `reviewer`
inspects that exact committed range against `INFRA_SHA`. On approval, merge the
head normally into `feature/psg-velocity-history-upstream`; do not cherry-pick
or transport a staged tree. This merge remains an ordinary initial-foundation
contribution. It joins the
approved 12A/12B work and the later `CONTRACT_SHA` descendants 14A/14B before the
coordinator records `FOUNDATION_SHA`.
