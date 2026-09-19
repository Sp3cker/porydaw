## Fast path for agents

Before changing code, be able to name five things in one sentence each:

1. The owner of the state or behavior.
2. The source of truth (canonical stored fact vs. derived projection).
3. The named domain operation that changes it.
4. What is derived rather than stored — and why any stored derivation exists.
5. The observable behavior that proves the change works.

If any answer is unclear, investigate before creating a new state holder,
callback layer, cache, or compatibility path.

## Decision priority

When rules pull in different directions, resolve in this order:

1. Correctness of the canonical document and project data.
2. The module seams (`core/` pure, `project/` owns I/O and workers, `ui/`
   passive) — never let `ui/` perform disk I/O or reach into worker internals.
3. Atomic, coherent publication of interrelated state.
4. Throughput and latency for real interactions (playback, gestures, redraws).
5. Local simplicity — fewest owners, fewest moving parts.

A convenience for the writer never outranks 1–3. A measured or structural
need under 4 can justify caching or materializing derived state that rule 5
would otherwise forbid.

## Ownership and source of truth

- Give each coherent decision one owner. `SongDocument` owns the editable
  `SmfFile` + `SongCfg` facts and the `QUndoStack`; `ProjectWorkspace` is the
  only seam the GUI may submit through; `SongTab` owns one tab's
  document/view/timeline lifecycle. Do not let two widgets keep competing
  copies of the same selection, context, or lifecycle state.
- When one action changes several facts that must agree, resolve and validate
  all of them first, then publish in a single transition — the way
  `SongTab::applyMidiStage` swaps a fully built timeline in one step. A reader
  must never see a half-updated invariant spread across setters.
- Cross module and thread boundaries with immutable snapshots and tokens
  (`ProjectSnapshot`, `SongSaveSnapshot`, `LoadedBankView`), not shared
  mutable references.

## Plan before you mutate

- For multi-step, collision-prone, or structural edits, compute the change as
  a pure value first: `planLaneMoves` (`src/core/lanemoveplan.h`) returns
  `std::optional<LaneMovePlan>`; `TrackRemap` (`src/core/songdocument.h`)
  translates indices without touching the document. Validate invariants on
  plain value structs, then execute in one step.
- Every `SongDocument` edit goes through the `QUndoStack` as one undoable
  command. A composite user action must not push several undo items; nested
  helpers apply inside the command's redo.
- Validate before mutation: early return or fail-fast assertion when an
  operation has no valid target. An impossible internal state fails visibly —
  assert or return a typed failure; never add recovery for a state the design
  says cannot occur, and never silently rewrite project or MIDI data to make
  a malformed case convenient for the UI.

## Facts vs. derived state

- Store only what must persist; derive the rest on demand. Canonical state is
  `SmfFile` + `SongCfg`; `MidiTimeline`, `SongViewModel`, and
  `AutomationViewModel` are rebuilt by pure builders
  (`buildSongViewModel`, `buildAutomationViewModel`) or downstream of
  `documentChanged`, not maintained as parallel caches.
- Exception — materialize derived state when it protects something real:
  - throughput (a lookup index that removes a per-frame linear scan),
  - atomic publication (precomputing interrelated fields so one setter can
    publish them together),
  - lifecycle (a snapshot that must stay valid while the source mutates),
  - expensive work (a parse or decode whose cost cannot repeat per query).
- When you materialize, name the owner, what makes it stale, and the exact
  behavior it protects. Do not add a mirror, revision flag, or invalidation
  layer for a consumer that does not exist yet.

## Composition and abstraction threshold

- Keep the main path top-down: public contract first, then the normal flow in
  execution order. Move parsing, lookup, and formatting into named helpers
  near their single caller when that makes the decision easier to scan.
- Name operations for the domain action (`adoptSmf`, `applyBankView`,
  `applyMidiStage`), not the mechanism. Callers see a small input, a clear
  outcome, one owner.
- High threshold for new abstraction: prefer free functions and value structs;
  introduce a class for a stateful accumulator or a lifecycle that must be
  owned, not to wrap a single direct call. Exception: a small wrapper is
  justified when it isolates a flaky external boundary (device, codec,
  process) from domain callers.
- Avoid both extremes: one file owning unrelated concerns, and a web of
  single-use indirections hiding the real flow. Cohesion, not line count, is
  the test here — file-size targets and review signals live in AGENTS.md.

## Boundaries and failure shape

- Validate aggressively at ingress — file formats, SMF data, project files,
  settings, worker results — and assume invariants hold downstream. Do not
  sprinkle defensive checks through `core/`.
- Model fallible cross-seam outcomes as closed sum types
  (`ProjectMutationFailure` is a `std::variant` of exactly four alternatives)
  or `std::optional`, so every caller handles all cases. Do not flatten
  concrete failures into generic strings.
- Bounded resilience belongs at user-facing and external-system seams: a UI
  orchestrator may catch an unexpected failure, log it, and restore a safe
  state (deselect, empty view, unavailable status) rather than crash the
  workspace. Inside `core/` parsers and planners, the same input fails fast.
  Recovery must be bounded and explicit — never a silent fallback that makes
  a broken invariant look valid.

## Async, stale work, and resource lifetimes

- Long-running operations use discrete lifecycle states with input gating
  (`ProjectOpenState`, `SongTab`'s `InputGate`), not ad-hoc busy booleans.
  Keep the last good presentation live while gating input until terminal
  facts arrive.
- Suppress stale in-flight work at the source: generation/revision tokens
  (`DocumentStateIdentity`, save-state tokens) or explicit cancellation when
  the context changes. Do not let a superseded async result land.
- Replace shared or borrowed resources with a borrow-safe swap: build the new
  object locally, repoint every borrow
  (`m_view->setSong(newTimeline.get(), voicegroup)`), then retire the old
  owner — the parked lease outlives the borrow (`SongTab::applyMidiStage`,
  `applyBankView`).
- Pair every acquired handle (file, device, lease, worker) with an
  unconditional release path that runs on early return, failure, and
  teardown. Destructor ordering is part of the contract
  (`SongTab::~SongTab` detaches the Quick host before the view).

## UI and rendering

- Keep domain state and rendering policy separate: the model supplies facts;
  the renderer decides presentation at current geometry and scale. A draw or
  layout helper receives what it needs; it does not reach up into controller
  state.
- Keep high-frequency interaction state local to the surface that owns it —
  drag offsets, hover, pan/zoom, popup state. Promote to shared state only
  when a second owner must coordinate with the result.
- Inside a tightly coupled UI cluster, prefer synchronous value diffs
  (`DrawerDiff`) or a single typed observer (`EditorSelectionModel::Observer`)
  over cascading Qt signals. Cross-module events (`timelineChanged`,
  `readinessChanged`) are the right place for signals.
- Use Qt's ownership, focus scopes, models, and layouts when they express the
  behavior. Add custom coordination only for a Porydaw-specific rule Qt cannot
  own; never duplicate a Qt mechanism with focus memory or a second
  dispatcher.

## Checks and proof

- Prove behavior at the closest useful boundary: a named operation produces
  the expected document, audio, or visible result. Include real boundary
  cases the operation can reach.
- Do not write a check for an impossible internal call sequence. If a
  cleanup, gating, or stale-write guarantee matters, exercise that lifecycle
  boundary directly.
- Before adding a check, name the production rule it proves; before removing
  one, name the behavior that disappears with it. Harness placement and the
  verify commands are defined in AGENTS.md.

## Review checklist

- Is there one source of truth and one owner for each decision?
- Does each state-changing operation publish a coherent invariant in one step?
- Is every stored derivation justified by throughput, atomic publication,
  lifecycle, or cost — with a named owner and staleness rule?
- Are multi-step mutations planned as pure values before touching the
  document, and do they land as a single undo command?
- Do shared-resource updates use borrow-safe swaps, and does every acquired
  handle have an unconditional release path?
- Are failures typed and exhaustive at seams, fail-fast inside `core/`, and
  bounded-self-healing only at user-facing edges?
- Can a reader find the normal path before the exceptional details?
- Did the change add only behavior the request requires?
- Does each added or retained check prove a real production rule?
