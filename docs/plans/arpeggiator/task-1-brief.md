# Context
Implement pure track-arpeggiator generation consumed by the per-track presenter. Read plan.md Global Constraints and Shared specification first, exact interface values verbatim.

# Exact write set
- src/swift/core/Arpeggiator.swift (new)
- src/swift/core/CMakeLists.txt (register new source only)

# Prerequisites
None; presenter consumes the fixed interface in plan.md.

# Interface contract
Implement all generator types and semantics in plan.md. Additionally `ArpeggiatorResult` exposes public `stepTicks: [Tick]` and `stepIndices: [Int]` (parallel arrays, each actual shuffled tick and pad index, including disabled/rest slots). Controller uses these for accurate audition pad highlighting. Limit clock events as well as emitted notes to 65,536 and return a descriptive error rather than unbounded work. All default and explicit settings must be validated at the public entry point. No generic scheduling framework.

# Implementation steps
1. Inspect complete Note, NewNote, tick and MIDI contracts plus LSP diagnostics/symbols where available. Add pure types and source registration.
2. Implement deterministic source chord feed, mode traversal, integer hardware-clock lattice including shuffle/retrigger, pads/custom/random/insert/velocity/gate/tie and range/pitch policies from spec. Reuse mid2agbEffectiveDuration for gate fixed points; generator takes explicit PlaybackSettings. Avoid quadratic whole-source rescans per step where sorted event processing is straightforward.
3. Ensure emitted same-pitch intervals are disjoint, simultaneous duplicate pitches are resolved, every boundary is exactly representable by document and GBA clocks, all output is in loop, and clocks always progress. Unsupported rate/Insert combinations produce errors, never rounded/collapsed steps. Implement bounded errors, not silent truncation.
4. Read-only local inspection; report exact semantic assumptions and structural diagnostics. Do not edit check/proof files.

# Acceptance predicate
Generation matches plan's behavior and default settings on 3-note chords, changing chords, disabled/accent pads, Custom/R, Insert, tie, high/coarse PPQ, normal/extended clocks, Exact Gate on/off and pre-loop sustaining notes; output deterministic, on the shared GBA/document lattice, and within bounds. NAMED CHECKS: controller runs `uv run --no-sync dev build:checks` and `uv run --no-sync dev checks --filter swiftcore-noteedits` after adding focused new checks.

# Task-specific constraints
SHARED_TREE: do not run builds, tests, lint or formatters; report DEFERRED_TO_CONTROLLER. No commits. New code follows rule://swift-standards and swift-typecheck-complexity. Controller owns test registration and whole-surface review. Preserve unrelated core declarations exactly.
