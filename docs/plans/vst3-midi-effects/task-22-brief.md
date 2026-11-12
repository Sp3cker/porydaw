# MIDI import controller I/O lifecycle
# Execution
Worktree: /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects
BASE: d73c6a1ec20a910e762265f61ea3abd4dde705f6
Read plan.md Global Constraints and linked spec.md. This is the user-approved cleanup extension, not a new feature. SHARED_TREE: no builds, checks, linters, formatters, index/reconfigure, desktop actions, subdelegation or commits. Read-only file-local inspection is required; controller runs named verification on settled sources. SourceKit semantic references were unavailable; report that honestly and trace consumers if still unavailable. Use existing patterns. No generic FSM, new dispatcher, fallback, compatibility alias or task-lifetime collapse. No proof ledgers exist for these VST checks. Return full result fields: status (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT), summary, implementation, tests (commands/output, DEFERRED_TO_CONTROLLER where unrun), changedFiles, selfReviewFindings (before/after symbols/diagnostics, permitted vs actual scope changes, unavailable tooling), concerns. Write no reports/scratch files.

# Exact write set
src/swift/app/midiimport/MidiImportController.swift; src/checks/songlist/MidiImportWizardChecks.swift only if a missing controller behavior is expressible through existing fixture. No wizard state, app session, QML production, CMake/registration or studio edits.
# Four steps
1. Inspect source and consumers plus MidiImportWizardState; baseline symbols/diagnostics/references. Existing pure wizard page/navigation state is already explicit, preserve it.
2. Replace busy/wizardOpen/state internal authority combinations with a controller-local lifecycle (idle, loading, editing(wizard state), importing) or equivalent tagged representation that removes invalid combinations. Keep public busy/wizardOpen and row/value properties as required QtBridge projections derived/published from the canonical lifecycle.
3. Keep task/service ownership and stale-completion guards, install/detach cancellation, picker request guards, error behavior, prepare/register ordering and synchronous wizard navigation semantics. Cancel/finish must not keep an editing payload after it is dismissed; loading/importing both project busy=true but remain distinguishable internally. No extra dispatcher or generic operation framework.
4. Preserve existing check behavior, add a regression only if a missing consumer-visible transition can be exercised without mock echoes/source-text tests. Complete local inspection.
# Acceptance
Controller phase is explicit and cannot simultaneously be idle/editing/busy; import/cancel/service replacement and wizard navigation remain unchanged through the production presenter contract.
# Controller verification
uv run --no-sync dev build:checks
uv run --no-sync dev checks --filter projectsession --filter midiimport --no-windowing-checks --pool=1
uv run --no-sync dev checks:shell --filter import --pool=1
checks:bridge; checks:qml-aot; lsp:swift. Flag stale filters with registry evidence.
