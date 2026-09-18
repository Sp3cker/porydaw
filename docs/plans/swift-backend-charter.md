# Swift backend charter — guiding rules for the production conversion

Status: normative. Every wave spec, task brief, and review under the Swift
backend track inherits this document. Where a spec and this charter
disagree, the charter wins and the spec is a defect. Successor wave specs
(document seam, surfaces) must name this file in their Global Constraints.

## Prime directive

This is not a prototype. The Swift backend track converts production
surfaces. Production implementations and interfaces are designed to stay:

- No temporary workarounds. A workaround here means what it means in
  AGENTS.md: stop, name the root cause, recommend the root-cause fix, and
  request approval. Accommodating a broken invariant with a guard or
  fallback is not an option.
- No "transitional" production implementations scheduled for rework at
  cutover. If a production design cannot survive cutover unchanged, it is
  the wrong design now. The enumerated migration verification and mount
  machinery below is not a license for temporary production implementations.
- No parallel implementations kept "until later." Widget twins inside the
  song tab are cut over and deleted at their named retirement gate, not
  maintained beside their successors indefinitely.
- Production focus applies to checks too: a check that only passes in the
  sandbox proves nothing about production.

## Swift implementation policy

- Target Swift 6.4 and use current language and standard-library features
  where they improve ownership, safety, clarity, or performance. Apply this
  during implementation, not as a deferred modernization pass.
- Prefer spans for scoped borrowed access where supported. Verify concrete
  APIs and deployment availability; do not invent compatibility fallbacks.
- Raw pointer access is acceptable when bounds, initialization and lifetime
  are proven. A view into a callback's buffers must not escape that callback.
- Retained document state needs owned storage. Copy accepted input into that
  storage once; avoid intermediate arrays, redundant mapping, boxing and
  avoidable copy-on-write detachment. Reject stale snapshots before copying.
- Review these properties in every Swift task. Use modern features for a
  concrete benefit, not feature-count churn or unrelated rewrites.

## Compatibility and retirement decision (2026-09-18)

Required user behavior and explicitly permanent host interfaces create
compatibility obligations; migration-only machinery creates **none**.
Demo APIs, fixture loaders, sandbox checks, and parity adapters are not
public contracts merely because code or tests call them. Preserve the
behavior they help prove, not their implementation shape or entry points.
INV-3's root host window/focus/input boundary remains permanent, as do
INV-1 and INV-2's single keymap and arbitration authority.

The table is the authoritative, exhaustive permission for migration-only
verification and mount machinery. Each row has a removal gate, not an
open-ended exception to the prime directive. Production grid logic, value
feeds, and host integration must still be built to stay; being introduced
during migration does not make them disposable. Reaching a gate requires
evidence on the replacement surface, not a changed plan status.

| Migration-only machinery | Read-only production mount obligation | Removal gate |
| --- | --- | --- |
| Standalone demo entry point and demo fixture setup | Exclude the standalone app entry point and selftest drivers from the production library. Production content comes from the real document feed, not demo fixture initialization. Keep the standalone lane and fixtures still required by this wave's acceptance. | Remove the standalone lane and demo-only fixture hooks when production acceptance exercises all required behavior they still verify, including editable behavior. Delete a fixture only when no retained acceptance check needs it; production regression fixtures are not disposable merely because the demo also used them. |
| Duplicate local undo (`GridUndo` in the demo) | Read-only production mode records no local edits or undo entries. Keep demo undo for still-required editable sandbox acceptance; it is not a second production undo authority. | At editable cutover, connect Swift edits to the authoritative document undo path and prove production mutation/undo/redo behavior before deleting duplicate local undo and its demo callers in the same cutover. This does not authorize a rewrite of production undo in the read-only wave. |
| Rollout flag, read-only overlay mounting, and old C++ rendering path | Keep the flag and flag-off renderer while the opt-in mount is read-only. Use the shared production grid implementation, not a separate temporary grid implementation. | At default editable cutover, production rendering, editing, focus/key arbitration, cancellation, and undo acceptance must pass on Swift-backed surfaces. Then remove the rollout flag, overlay-only mounting/absorption machinery, and replaced C++ rendering path atomically; preserve normal production mounting and the permanent host boundary. Windows deferral cannot extend this gate. |
| Duplicate sandbox behavioral checks | Retain rows still required by prototype regression; a read-only mount cannot replace editable, keyboard, menu, or cancellation acceptance. | Delete each `cutover-disposable` row when its required behavior is covered and passing on the actual production replacement surface. Retire the duplicate harness when its last such row retires; never keep a parallel behavioral acceptance suite after cutover. |
| Callable parity adapters and dual-run oracle plumbing | Keep adapters needed by live parity sweeps. Distinguish oracle/test adapters from production seams even when colocated or sharing a prefix. | At the corresponding oracle implementation's cutover, pass the final dual-run sweep and replacement production acceptance, then remove oracle-only adapters and sweep plumbing with the retired oracle. Retain needed independent numeric regression coverage without a duplicate production implementation. Production value feeds and permanent host input/cancel interfaces do not retire with test adapters. |

These gates permit verification scaffolding and staged mounting, not
workarounds, backward-compatibility shims, or production code written to be
replaced later. A gate not reached means its acceptance machinery remains
necessary, not that its API becomes permanent. The current C++ document
and undo ownership is the production authority for these waves, not a
decision that the current document seam must exist forever; any later
ownership change requires its own explicit contract and acceptance gate.

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

## Platform decision (2026-09-18): Windows deferred, MinGW incidental

The rewrite proceeds macOS-first. Windows is **deferred, not dropped**:
existing users are frozen on the last C++ release until Windows returns.
MinGW was never a decision — it is an incidental toolchain fact and binds
nothing. Binding consequences:

- No MinGW accommodations, loader workarounds, or check tolerances are
  added or maintained anywhere in this track.
- No dual implementations to preserve Windows: the C++ roll band's
  retirement is unconditional. Windows returns **on the Swift codebase** —
  its own later wave covering toolchain selection (MSVC or otherwise),
  packaging, and CI — never by keeping C++ surfaces alive.
- Repo de-Windows-ification (Windows CI/release jobs, AGENTS.md toolchain
  section, windeployqt packaging, MinGW check handling) is one mechanical
  plan executed after the current wave; nothing blocks on it and no new
  work depends on it.

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
This preserves the current production document/undo authority; it does not
freeze that authority's implementation language or seam for all future waves.

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
This dual-run obligation lasts until the corresponding oracle retirement
gate in the retirement table is satisfied.

## Verification rules

**V-1 — Checks are the contract; implementations swap beneath them.** At
cutover, production suites run unmodified against Swift-backed surfaces.
That run is the acceptance gate — not a port of the suites.
The compatibility obligation is required observable behavior, not demo
entry points or migration-only test APIs.

**V-2 — Copied checks verify nothing but their copy.** Production checks are
never rewritten against sandbox surfaces as acceptance evidence. Parity for
callable values is proven by dual-run sweeps; behavior parity is proven by
the production suites at cutover.

**V-3 — Sandbox scenarios are cutover-disposable.** Smoke scenarios that
mirror production behavior (key priority, menu behavior, transport) are
tagged `cutover-disposable` and retire at the table's behavioral-coverage
gate. Merely mounting a read-only production surface does not satisfy it.
A permanent parallel suite is a defect.

## End-state architecture (decided)

- Host target: `QMainWindow` shell (native menu bar, native frame) plus a
  single Quick central surface. A full-QML host and per-tab embedded windows
  are rejected.
- Chrome and dialogs stay C++/QWidgets. Timeline bands are the track's
  entire blast radius until they are done.
- Ordering: shared seams first (view math → input jurisdiction → document
  feed and commands), surfaces after (grid, track headers, ruler, lanes). No
  surface serializes behind math it does not consume.
