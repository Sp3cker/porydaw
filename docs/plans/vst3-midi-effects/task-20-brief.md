# Sample Studio source-decision state
# Execution
Worktree: /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects
BASE: d73c6a1ec20a910e762265f61ea3abd4dde705f6
Read plan.md Global Constraints and linked spec.md. This is the user-approved cleanup extension, not a new feature. SHARED_TREE: no builds, checks, linters, formatters, index/reconfigure, desktop actions, subdelegation or commits. Read-only file-local inspection is required; controller runs named verification on settled sources. SourceKit semantic references were unavailable; report that honestly and trace consumers if still unavailable. Use existing patterns. No generic FSM, new dispatcher, fallback, compatibility alias or task-lifetime collapse. No proof ledgers exist for these VST checks. Return full result fields: status (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT), summary, implementation, tests (commands/output, DEFERRED_TO_CONTROLLER where unrun), changedFiles, selfReviewFindings (before/after symbols/diagnostics, permitted vs actual scope changes, unavailable tooling), concerns. Write no reports/scratch files.

# Exact write set
src/swift/app/samplestudio/SampleStudioWorkflow.swift; src/checks/samplecheck/SourceReplacementChecks.swift only if behavior coverage needs adjustment. Existing QML observation contract stays unchanged. No other source or registration files.
# Four steps
1. Inspect complete source transitions and src/ui/shell/samplestudio/SampleStudioHost.qml Loader release consumers, baseline symbols/diagnostics/references.
2. Replace pendingSource + sf2File and overlapping source-decision authority with a local tagged state: idle, stereoDecision(request), zoneDecision(request,file), naming adapted to local domain. Derive/publish existing stereoPromptOpen/zonePickerOpen projections through existing supported QtBridge patterns. No second authority for those decisions.
3. Preserve orthogonal editor lifetime and commit state, picker request, preparation/session generations and task cancellation. Existing editor remains open beneath picker/decisions. zonePresenter must survive accept/cancel until zonePickerReleased after Loader teardown; editor tools/wave/player likewise survive close until editorReleased. A source enum must not destroy a presenter early or erase preparation-in-flight acceptance guards. Preserve successful/failed transactional source replacement and destination assignment.
4. Keep existing tests; add only a missing source replacement/cancel/stale-completion behavior if necessary. No file splitting for size, no public bridge/baseline changes. Complete local inspection.
# Acceptance
Source decisions always carry their required request/file, are mutually exclusive, and preserve existing source transaction/editor/Loader lifetime and cancellation behavior without changing QML surface.
# Controller verification
uv run --no-sync dev build:checks
uv run --no-sync dev checks --filter samplecheck-editor --no-windowing-checks --pool=1
uv run --no-sync dev checks:shell --filter shell-sample-studio --pool=1
checks:bridge; checks:qml-aot; matching focused ASAN if lifetime paths apply; lsp:swift.
