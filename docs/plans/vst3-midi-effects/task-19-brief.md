# Recorder synchronization phase
# Execution
Worktree: /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects
BASE: d73c6a1ec20a910e762265f61ea3abd4dde705f6
Read plan.md Global Constraints and linked spec.md. This is the user-approved cleanup extension, not a new feature. SHARED_TREE: no builds, checks, linters, formatters, index/reconfigure, desktop actions, subdelegation or commits. Read-only file-local inspection is required; controller runs named verification on settled sources. SourceKit semantic references were unavailable; report that honestly and trace consumers if still unavailable. Use existing patterns. No generic FSM, new dispatcher, fallback, compatibility alias or task-lifetime collapse. No proof ledgers exist for these VST checks. Return full result fields: status (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT), summary, implementation, tests (commands/output, DEFERRED_TO_CONTROLLER where unrun), changedFiles, selfReviewFindings (before/after symbols/diagnostics, permitted vs actual scope changes, unavailable tooling), concerns. Write no reports/scratch files.

# Exact write set
src/swift/app/miditools/PluginStateRecorder.swift; src/checks/miditools/TrackEffectsControllerChecks.swift only if a discriminating missing behavior needs coverage. No TrackEffectsController or other files.
# Four steps
1. Inspect all source/callers and before symbols/diagnostics. Baseline, suppressed and restorePending currently describe initializing vs synchronized vs restore-pending.
2. Raise that synchronization phase into a small local enum with associated baseline/revision payload as needed. Remove superseded flag/optional storage, not rename it behind accessors. Keep initialState snapshot semantics, permission enablement and candidate digest stability separate where genuinely independent.
3. Preserve restoreRevision versus observation generation, initialization superseded by restore, pending edits across pause, suppression during history restore, 300ms edit debounce/500ms silent-preset polling, permission checks across awaits, snapshot stability, and callbacks. Keep every cancelled task in tasks until completion, identity guards and idle joins. No global epoch/serial queue or speculative nil-baseline recording.
4. Use existing real helper checks for edit coalescing, silent preset, history restore and cancellation. Add a regression only for a missing transition at this seam; no enum/source-text tests. Finish local inspection and full result.
# Acceptance
Synchronization phases cannot contradict one another; real edit/preset undo and restore remain correct with no late record after suppression/retirement and no lost pending edit on resume.
# Controller verification
uv run --no-sync dev build:checks
uv run --no-sync dev checks --filter projectsession --no-windowing-checks --pool=1
uv run --no-sync dev checks:shell --filter shell-midieffects --pool=1
Matching ASAN; lsp:swift. Existing native-window acceptance remains separately pending, never claimed executed.
