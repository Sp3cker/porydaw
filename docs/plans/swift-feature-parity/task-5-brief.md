# Context
Repair R02/R03/R04/R05 on the existing workspace/transport surface. Audio mask setters have no app callers; cancellation omits ruler sweep; background callbacks must not mutate selected shared presenters; toolbar Play must resume while Space starts at edit cursor. Read plan.md Global constraints and spec.md, and original transport proofs before altering semantics.

# Exact write set
- src/swift/app/DocumentWorkspace.swift
- src/swift/app/ApplicationSession.swift
- src/swift/app/transport/TransportBarPresenter.swift
- src/checks/workspace/transport_checks.swift
- src/checks/editorqml/tst_ShellTransport.qml
- src/checks/audio/AudioControllerChecks.swift

# Prerequisites
None. This cohesive ownership task has five files because the same application/workspace boundary owns activation, cancellation and transport routing.

# Interface contract
DocumentWorkspace remains the sole audio activation/publication owner. Apply session mute/solo masks on activation and active-session mix changes; hidden workspaces never overwrite selected audio masks. DocumentWorkspace.cancel clears ruler sweep state; remove redundant application-layer cancellation. Shared event-list/playhead updates are active-workspace-only; local hidden document state remains current. Preserve toolbar resume versus Space restart-at-edit-cursor through existing semantic routes, with immediate transport presentation. No extra dispatcher, cached shadow state, UI or forwarding layer.

# Implementation steps
1. Trace real render masks, session remaps, shared presenter attach/detach, and original Play/Space contract. Reject any audit allegation contradicted by source with evidence rather than changing correct behavior.
2. Implement active mask publication including track removal/remap and reactivation. Use safe fixed-width mask conversion within supported tracks.
3. Centralize sweep cancellation for all workspace termination paths; late updates cannot revive a cancelled sweep.
4. Correct transport routes and background publication at existing owners. Preserve stopped versus paused ruler seek and origin guards.
5. Add deterministic behavioral assertions to existing registered checks: audio effect where existing renderer seams allow it, tab switching, remap/mask restoration, cancelled ruler sweep, Play resume/Space cursor restart, and immediate state refresh. Avoid wiring/mock-echo tests. Return proof handoff paths/site identities, without editing ledgers.

# Acceptance predicate
Selected mute/solo affects rendered sound, tab switching cannot leak state, every workspace cancellation clears sweep, and production toolbar/Space semantics match the preserved contract: controller runs `deno task verify --filter swiftcore --verbose` and `deno task verify:shell --filter shell-transport --filter shell-tabs --filter shell-grid-input --verbose`, then actual desktop smoke. Existing renderer PCM checks already prove mask semantics; add an actual workspace-to-NativeAudio observation using existing activity/polyphony telemetry, not a mask getter or duplicated renderer test. AudioControllerChecks.swift is available only if the integration observation requires its existing fixture; do not add a sixth-file edit gratuitously.

# Task-specific constraints
SHARED_TREE. Skip all builds, tests, lint and formatters; edit only. No comments, commits, scratch reports, new C++, or workarounds. Source-level local inspection is required. Proof-only reconciliation belongs to the controller's ledger agent after sources freeze.
