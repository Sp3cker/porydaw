# Native lifecycle cleanup
# Execution
Worktree: /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects
BASE: d73c6a1ec20a910e762265f61ea3abd4dde705f6
Read plan.md Global Constraints and linked spec.md. This is the user-approved cleanup extension, not a new feature. SHARED_TREE: no builds, checks, linters, formatters, index/reconfigure, desktop actions, subdelegation or commits. Read-only file-local inspection is required; controller runs named verification on settled sources. SourceKit semantic references were unavailable; report that honestly and trace consumers if still unavailable. Use existing patterns. No generic FSM, new dispatcher, fallback, compatibility alias or task-lifetime collapse. No proof ledgers exist for these VST checks. Return full result fields: status (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT), summary, implementation, tests (commands/output, DEFERRED_TO_CONTROLLER where unrun), changedFiles, selfReviewFindings (before/after symbols/diagnostics, permitted vs actual scope changes, unavailable tooling), concerns. Write no reports/scratch files.

# Exact write set
src/pluginhost/pluginhost.h; pluginhost.cpp; pluginhost_internal.h; pluginhost_process.cpp; pluginbridge.h; helper/host.h; helper/host_control.cpp; helper/host_rt.cpp; src/swift/pluginhost/HelperProcess.swift; src/checks/pluginhost/BridgeChecks.swift; src/checks/pluginhost/PluginHostABIChecks.swift only discriminating lifecycle checks if needed. Over-cap: one native lifecycle/control seam with its complete C/Swift protocol cutover and real fixture checks. No CMake/registrations, editor/scanner code, PluginInstance.swift, spec or plan edits.
# Four steps
1. Inspect symbols/diagnostics/references and complete enclosing constructs. Remove pdph_standard_module_paths plus pdph_free_string_array (definitions/declarations and ownership comment): no caller; Swift catalog owns roots on all platforms.
2. Replace engine setup/active/processing boolean tuple with one local enum (unprepared/prepared/active/processing). Migrate every engine read including destructor and zero-frame mode selection. Failed setup invalidates preparation; repeated setters still call SDK; zero-frame parameter flush is allowed before setup; teardown stops before deactivation. Remove Host.processing/maxBlock mirrors; RT reads canonical engine state/block under processingOwner. Keep sampleRate/periodFrames and all SDK/ownership ordering.
3. Remove PDPB_LOG without renumbering/reusing IDs, HelperEvent.log and decoder, and vacuous negative log assertion; retain real failure/termination assertions. Task18 owns removing PluginInstance's .log ignored arm. Simplify flush to one in-flight request flag: main publishes true, relinquishes ownership; RT writes result, restores main ownership, then release-clears request; main acquire-waits on clear with same stopping escape. Remove second completion flag. Single outstanding requester remains invariant.
4. Preserve all real fixture behaviors; adjust/add only a plausible consumer-visible invalid lifecycle/cleanup assertion if existing coverage lacks it. Complete local inspection. Controller updates BUILDING docs.
# Acceptance
Existing ABI/bridge/capture real fixture paths preserve processing, zero-frame edits, crash/overflow and teardown while dead native capability/mirrors/second acknowledgment are absent and exactly four engine phases represent reachable lifecycle.
# Controller verification
uv run --no-sync dev build:checks
uv run --no-sync dev checks --filter pluginhost --filter pluginbridge --no-windowing-checks --pool=1
Same check with --asan; actual helper capture path is exercised by host suite.
