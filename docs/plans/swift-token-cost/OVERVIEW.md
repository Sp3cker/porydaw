# Swift token-cost simplification — investigator overview

Source: main-checkout audit (60,086 lines / 260 Swift files) + 3 scout audits + 3 evidence-plan-architect verdicts.
Worktree: `.worktrees/swift-token-plans`, branch `feature/swift-token-plans`.
Consumer: next agent picks up from these files. No code edits made; plans only.

## Ranked starting points (investigator call)

1. **Drawer lanes** — planner REJECTED the shared-kernel hypothesis (NOT VERIFIED).
   37 files / 11,805 lines share a lifecycle pattern, not a pipeline; extractable overlap ~3.4–5.5%.
   Approved narrow win only: literal-dedup (~60–100 lines) + lane anatomy map. See `01-drawer-lanes.md`.
   Investigator's original #1 ranking was wrong; best verified structural win is now #2 (roll).
2. **Roll gestures + scene sync** — `src/swift/app/roll/`.
   One drag co-loads ~5 files / ~1631 lines (PianoGrid 423 + Gestures 512 + GridGesture 211 + SceneSync 393 + Rebuild 92).
   Planner verdict: PARTIALLY VERIFIED — consolidate gesture side only, keep scene sink separate.
   Plan: `02-roll-gestures.md` (planner: StripedLeopard — COMPLETE).
3. **Core editing extensions** — `src/swift/core/` SongDocument extension cluster
   (SongDocument 565 + NoteEditing 509 + EventEditing 533 + TimeEditing 417 + TimeEditing+Plan 299
   + NoteMovement 156 + NoteProjection 187; PlaybackTimeline 674 adjacent).
   Collision kernel approved, emitter merge rejected. Plan: `03-core-editing.md` (planner: ThoughtfulSilkworm — COMPLETE).

## Explicit non-starts

- `app/timeline/ThemeColorTables.swift (961 lines)` — generated/precomputed palette bulk, verified by
  `src/checks/themecolor`. Isolate from agent context; do not rewrite.

## Handoff state

- [x] 01-drawer-lanes.md — complete, kernel REJECTED; execute narrow steps 1–4 only.
- [x] 02-roll-gestures.md — complete, PARTIALLY VERIFIED; gesture-side consolidation approved.
- [x] 03-core-editing.md — complete, PARTIALLY VERIFIED; collision kernel approved (~80 ln, net −80..−100), emitter merge REJECTED.
- Next agent: double-check each plan against its verdict section, then execute roll → core-kernel → drawer-narrow.
- Order rationale: roll is the only approved structural consolidation (−40–45% gesture-task context); core kernel is pure + strongly gated by editcheck corpus; drawer is literals + anatomy map (smallest, safest last).
