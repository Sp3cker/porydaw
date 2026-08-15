# Peel 10 — Arrow-tool click redesign in the lanes (⚠ USER DECISION REQUIRED FIRST)

Read `docs/peels/GROUND-RULES.md` first. **Do not implement without explicit
user approval — this changes main's core automation click semantics.** Source:
branch `automationgesture.cpp:256-263`, `automationarea.cpp:882-933`; harness
`src/rollcheckautomation.cpp:588-769`.

## What the branch does differently (vs main today)

| Input (arrow tool) | main today | branch |
|---|---|---|
| Left click on empty lane | writes a point at the snapped tick | moves the edit cursor; writes nothing |
| Left click on a node | no-op (grab without motion) | **deletes the node** (one undo entry) |
| Double-click on a node | value type-in dialog | no-op (first click already deleted) |
| Sweep start | draws from the first pixel | activation slop (`nodeDragActivationDistance`), slop offset subtracted so the threshold isn't motion |

Rationale on the branch: with a pencil mode for drawing, the arrow tool becomes a
select/adjust tool — clicks shouldn't create data, and click-delete replaces
right-click-delete (which its menu peel repurposes). Sub-threshold jitter must
change nothing (harness :596-636 asserts byte-identical MIDI for sub-slop
clicks).

## Why this needs a decision

- It conflicts with main's documented behavior ("writeLanePoints even for a plain
  click"), with main's double-click type-in flow (whose first click currently
  creates the point being edited), and with muscle memory from every existing
  build.
- It only makes sense as a package with Pencil Mode (landed), Peel 05 (menu), and
  arguably Peel 04 — sequencing matters.
- Click-to-delete is destructive-on-click; the user may prefer main's semantics
  even post-pencil.

## If approved

- Implement all four rows of the table as one coherent change; keep double-click
  type-in reachable via empty-space double-click or the Peel 05 menu (decide,
  document in SPEC.md).
- The activation slop must be DIP-scaled (`layout::`), and the pencil path keeps
  its own existing behavior (pencil click still draws a single point — that is
  the pencil's contract; verify the pencil rollcheck section still passes
  UNCHANGED, and extend it if the slop touches shared code).
- Tests: adapt harness :588-769 (click-delete exact undo/revision arithmetic;
  sub-slop jitter → byte-identical document; empty click → edit cursor moved,
  nothing written; double-click no-op). Negative-test each; SF 1/1.5/2; ASAN
  sweep + ctest; prominent SPEC.md + CHANGELOG entries.

## If rejected

Record the decision in this file (edit it in place) so no future peel re-proposes
it, and check whether Peel 05's menu still stands alone (it does — it replaces
right-click instant delete regardless).
