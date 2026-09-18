# Swift backend charter — guiding rules for the production conversion

Status: normative. Every wave spec, task brief, and review under the Swift
backend track inherits this document. Where a spec and this charter
disagree, the charter wins and the spec is a defect.

## Prime directive

This is not a prototype. The Swift backend track converts production
surfaces. Every seam, rule, and check is designed as it will ship:

- No temporary workarounds. A workaround here means what it means in
  AGENTS.md: stop, name the root cause, recommend the root-cause fix, and
  request approval. Accommodating a broken invariant with a guard or
  fallback is not an option.
- No "transitional" implementations scheduled for rework at cutover. If a
  design cannot survive cutover unchanged, it is the wrong design now.
- No parallel implementations kept "until later." Widget twins inside the
  song tab are cut over and deleted, not maintained beside their successors.
- Production focus applies to checks too: a check that only passes in the
  sandbox proves nothing about production.

## The three migration invariants

These predate every wave. A plan that violates one is rejected at triage.

**INV-1 — One keymap source.** `keymap::Registry` is the single definition
of window-tier key bindings. Every Quick surface binds keys generated from
the registry; hand-written `Shortcut`/`Keys` bindings in QML are forbidden.
A second keymap is a silent fork of the global priority contract.

**INV-2 — Arbitration moves wholesale or not at all.** Window-tier key
arbitration lives in exactly one tier. Mixed tiers — some surfaces
dispatching through `QAction`s, others through QML dispatch — are forbidden.
When arbitration migrates, the `selectionkey` suites are re-pointed at the
new tier and green before the old tier is deleted: one atomic cutover, never
two live authorities.

**INV-3 — Swift never sees the window.** Swift owns band math and policy
data. It receives normalized input, named cancel reasons, and value
snapshots; it returns intents and geometry. Window-tier arbitration, focus
chains, pointer grabs, popup stacking, and platform events stay in the
C++/QML host forever. Swift never becomes a dispatcher of window input
(AGENTS.md: no second dispatcher).

## Seam rules

**S-1 — Production C++ is the read-only oracle.** Until cutover, production
implementations are normative and never modified to accommodate Swift. A
parity mismatch is a defect report against the port or a stale oracle claim
— never a silent edit of expected values.

**S-2 — Value feeds, not object borrows.** State crosses the C seam as
copied value structs (the `TimeMap` pattern). No `MidiTimeline*`,
`SongDocument*`, or Qt object pointers cross into Swift. Cross-boundary
staleness is guarded by document identity plus revision (the
`PendingHeaderMenu` pattern).

**S-3 — Undoability is existential.** Every gesture commit or command that
mutates musical state through the Swift seam produces an undoable document
edit on the C++ side. In-place mutation with "undo later" is forbidden;
non-undoable edits fail cutover regardless of raster parity.

**S-4 — The four cancel reasons are contract.** `FocusLost`,
`PointerUngrabbed`, `Hidden`, `WindowDeactivate` arrive as distinct named
reasons with per-band teardown semantics, mirroring
`TimelineInputCancelReason`. Collapsing, substituting, or inferring reasons
inside Swift is forbidden; the host names the reason. (Worked example: a
`hide()`-driven proof of `onVisibleChanged` proves `Hidden`; it can never
stand in for `WindowDeactivate`, whose defining predicate is that the window
remains visible.)

**S-5 — Compute, don't freeze.** Every expected value ported from a
production check carries a live dual-run sweep counterpart against the
production oracle (the `sgm_*` pattern), or a written justification of why
the value is not callable. Frozen literals name their source check in
brackets; a sweep mismatch names both sides loudly.

## Verification rules

**V-1 — Checks are the contract; implementations swap beneath them.** At
cutover, production suites run unmodified against Swift-backed surfaces.
That run is the acceptance gate — not a port of the suites.

**V-2 — Copied checks verify nothing but their copy.** Production checks are
never rewritten against sandbox surfaces as acceptance evidence. Parity for
callable values is proven by dual-run sweeps; behavior parity is proven by
the production suites at cutover.

**V-3 — Sandbox scenarios are cutover-disposable.** Smoke scenarios that
mirror production behavior (key priority, menu behavior, transport) exist
only until the real surfaces exist, are tagged `cutover-disposable`, and are
deleted at cutover. A permanent parallel suite is a defect.

## End-state architecture (decided)

- Host target: `QMainWindow` shell (native menu bar, native frame) plus a
  single Quick central surface. A full-QML host and per-tab embedded windows
  are rejected.
- Chrome and dialogs stay C++/QWidgets. Timeline bands are the track's
  entire blast radius until they are done.
- Ordering: shared seams first (view math → input jurisdiction → document
  feed and commands), surfaces after (grid, track headers, ruler, lanes). No
  surface serializes behind math it does not consume.
