# Peel 11 — One-shot selection replace across consecutive modifier velocity drags

Read `docs/peels/GROUND-RULES.md` first. Small peel in the PIANO ROLL (not the
lanes). Target: main's modifier velocity-drag path in `src/ui/songview.cpp`
(`m_velModPress` promotion, `Drag::Velocity`). Source: branch commit `d60df67`
(its `songview.cpp` hunks + `rollcheck.cpp` +123); the branch diff will NOT apply
(different selection model) — port the idea.

## Background — main's deliberate semantics (preserve them)

- Ctrl (`roll.velocity_drag` chord) + vertical drag on an UNSELECTED note JOINS it
  to the selection and nudges the whole selection (main commit 5895186).
- Ctrl+click without drag toggles membership (aad5bf2).
Both are ancestors of the branch's merge-base and the branch keeps them; `d60df67`
is a refinement on top, not a conflict.

## The refinement

Problem: adjust note A's velocity with Ctrl+drag, then — still holding Ctrl —
drag note B: B JOINS the selection, so the second drag moves A and B together
when the user almost certainly wanted to adjust B alone.

Fix — a one-shot suppression scoped to a single uninterrupted modifier hold:

- On release of a modifier velocity drag that COMMITTED, with the chord still
  held, arm the one-shot (branch `songview.cpp:2046-2051`).
- On the next modifier drag's promotion: if armed AND the anchor is a DIFFERENT
  note, REPLACE the selection with that note instead of joining (branch
  `:1799-1810`). Same anchor → normal path, so a deliberate bulk selection
  survives repeated drags on its own anchor (harness: "+2349-2370").
- Disarm on: modifier key release, FocusOut, Hide, WindowDeactivate. Plain clicks
  and Ctrl+clicks do NOT disarm (branch asserts this explicitly).
- Also port the leak fix: clear the "modifier drag live" flag in the velocity-
  gesture cancel path and on fresh mouse press (branch `:1449`, `:1621`).

Port against main's `{tick,key}` selection and `nudgeNotesVelocity` commit path;
"different note" compares main's note identity, and "committed" means the drag
actually pushed an undo entry (main skips no-motion drags — reuse that signal).

## Honest caveat for the summary

This introduces hidden-state behavior: the same input (Ctrl+drag on unselected B)
joins or replaces depending on whether an earlier drag happened during this hold.
The branch's tests pin every edge; port them all so the mode's boundaries are
enforced, and flag the UX for the user's manual feel-check.

## Tests

- Extend rollcheck's existing velocity-drag section (it already asserts join and
  toggle semantics — those probes must stay green): drag A then drag B in one
  hold → selection == {B}, one undo entry per committed drag; drag A then drag A
  again → bulk selection preserved; release Ctrl between drags → join semantics
  back; Ctrl+click between drags → does not disarm; focus loss disarms. Mind
  rollcheck's exact undo-count arithmetic — update the tallies deliberately.
- Negative-test each probe; SF 1/1.5/2 not required beyond existing coverage
  (no new geometry); ASAN sweep + ctest; SPEC.md velocity-drag paragraph +
  CHANGELOG.
