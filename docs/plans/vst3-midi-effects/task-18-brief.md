# Swift setup and capture payload cleanup
# Execution
Worktree: /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects
BASE: d73c6a1ec20a910e762265f61ea3abd4dde705f6
Read plan.md Global Constraints and linked spec.md. This is the user-approved cleanup extension, not a new feature. SHARED_TREE: no builds, checks, linters, formatters, index/reconfigure, desktop actions, subdelegation or commits. Read-only file-local inspection is required; controller runs named verification on settled sources. SourceKit semantic references were unavailable; report that honestly and trace consumers if still unavailable. Use existing patterns. No generic FSM, new dispatcher, fallback, compatibility alias or task-lifetime collapse. No proof ledgers exist for these VST checks. Return full result fields: status (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT), summary, implementation, tests (commands/output, DEFERRED_TO_CONTROLLER where unrun), changedFiles, selfReviewFindings (before/after symbols/diagnostics, permitted vs actual scope changes, unavailable tooling), concerns. Write no reports/scratch files.

# Exact write set
src/swift/pluginhost/PluginInstance.swift; CaptureDriver.swift; src/checks/pluginhost/PluginHostChecks.swift; docs/plans/vst3-midi-effects/spec.md; task-7-brief.md. Over-cap: one host setup/capture contract with real consumers and its former written payload promises. No other files, native C, HelperProcess, BridgeChecks, plan.md or BUILDING edits.
# Four steps
1. Inspect declarations/diagnostics/references. Replace needsSetup + setupRealtime/setupRate/setupPeriod cache with a local SetupKey and optional configured key/revision, retaining separate current setup invalidation revision. needsSetup may remain a derived projection because consumers/spec read it; no compatibility shim storage.
2. Snapshot revision before awaited deactivate/setup/activate/latency calls; successful completion records that snapshot, so a newer invalidation remains visible. Preserve reload/startup invalidation and independent editor/live/render/control lifetimes. Remove .log from PluginInstance's ignored event arm (task17 removes native/Swift event producer contract).
3. Delete CaptureProgress.events and its per-bar cumulative array capture; keep fraction notification cadence. Delete unread CaptureResult.pacing; execution still reads request.pacing. Keep all final raw events, preroll/tail/latency, non-note diagnostics, main-actor progress publication, cancellation and off-main normalization. Migrate all consumers; realtime-progress check must verify early bounded percentage and actual cancellation/final results, not the deleted payload. Delete any now-tautological assertion rather than repin implementation details.
4. Update spec and original task7 brief narrowly to remove obsolete payload promises and describe setup validity accurately. Complete local inspection; identify exact contract deltas.
# Acceptance
Real host capture still yields identical final events and timing, supports early realtime percentage/cancel/supersede, and a restart during setup remains invalidating; no unused progress snapshots or result pacing field remain.
# Controller verification
uv run --no-sync dev build:checks
uv run --no-sync dev checks --filter pluginhost --no-windowing-checks --pool=1
uv run --no-sync dev checks --filter projectsession --no-windowing-checks --pool=1
Matching ASAN; lsp:swift after edits.
