# Task 27 — Event-driven VST helper control and coherent state observation

## Placement and authority

Approved energy follow-up to tasks 23–26. Read `plan.md` Global Constraints and the linked `spec.md`, especially bridge/control, plugin-state recording, native lifecycle and editor contracts. The user's current direction selects **m1 / Claude Opus 5.5** as implementer and explicitly permits queued callback notifications. This brief supersedes only the old timer, exclusive-control and editor-open-only observation mechanics, not their behavioral guarantees. Audit: `agent://FableVstEnergyAudit` (F1–F5 and the scanner portion of F6). Source claims are not power measurements.

SHARED_TREE. HEAD/checkpoint is `290d15671db8d3e8f2e49d63ecc9579e1ea2d5a0`; existing dirty header/rack/voice/stopped-audition changes are accepted preexisting work, not this task. Controller captured bounded file preimages to isolate this task from that work. Preserve them exactly outside this brief's changes. No commits, merges, rebases or source-control changes.

## Target / ownership

Own: `src/pluginhost/helper/{host.h,host_main.cpp,host_control.cpp,host_rt.cpp,editor.cpp,editor_mac.mm}`, `src/pluginhost/{pluginbridge.h,pluginbridge_wait.c,pluginhost.h,pluginhost.cpp,pluginhost_internal.h}`, `src/pluginhost/scanner/scanner_main.cpp`, `src/swift/pluginhost/{HelperProcess.swift,PluginInstance.swift}`, `src/swift/app/miditools/{PluginStateRecorder.swift,TrackEffectsController.swift}`. Cover behavior in existing `src/checks/pluginhost/{BridgeChecks.swift,PluginHostABIChecks.swift,PluginHostChecks.swift,PluginHostEditorChecks.swift}`, `src/checks/miditools/TrackEffectsControllerChecks.swift`, `src/checks/vstfixture/porydawtestgen.cpp` only where missing coverage requires it. New cohesive check files may be proposed to controller for registration. No catalog implementation/check edits: those belong to task 28. Controller owns CMake/check registration, all docs and all shared-tree commands.

Over-cap exception: native synchronization, callback/exposure events and state replies form one cross-process lifecycle/observation contract. Keep one writer across both protocol endpoints and the recorder; no transient protocol compatibility layer. Scanner component probing reuses the same native module/component lifecycle boundary and public header. Do not split files for line count.

## Change (five steps)

1. Replace unconditional 10 ms callback polling with one coalesced queued drain on enqueue. Preserve bounded callback integrity, overflow failure, error shutdown, ordering and no calls after destroy. User permits queued callback allocation; app audio callback and native processing remain allocation/lock/dispatch-free. Replace reader's 1 ms in-flight-control polling with a blocking, shutdown-safe handoff; preserve parent-disconnect and stop behavior. Do not use a blocking queued Qt invocation that can deadlock join.
2. Give lifecycle mutations exclusive processing ownership, not all control operations. Editor create/raise/close, shortcuts and component state read/hash must not hold RT ownership for their whole duration. Keep restore safely exclusive unless a stronger verified contract is needed. Preserve sole RT parameter-queue consumption. Explicitly wake pending parameter flushes instead of relying on the 100 ms RT timeout; wait safely without millisecond spin or lost wakeups. Distinguish work wake, real request, timeout and stop coherently across macOS/Linux/Windows; do not fabricate empty bridge requests or weaken watchdog deadlines. Check real C++ shared state for races before permitting concurrency.
3. Pair a component snapshot with a digest of exactly its returned bytes, cutting redundant serialization while retaining required post-restore rebaselining and component/controller stability checks. Initial component→controller handoff is required and stays. No reuse of pre-normalization saved bytes as a proven baseline. Migrate all protocol callers, reject malformed replies, preserve state size limits and reusable stream/buffer ownership; no shims.
4. Observe actual native editor exposure/visibility through the existing callback/control route. Poll silent edits only when exposed and otherwise permitted. Settle silent pending changes on hide/minimize/close and reconcile on return without duplicate history, stale-generation writes, restore-generated steps or lost redo. Keep end-edit observation and required fallback for silent/asynchronous vendor changes; no activity-timeout heuristics. Shutdown/remove/render suppression and all existing cancellation joins remain. An armed Live plugin MUST continue processing while stopped/paused/hidden so GUI-produced MIDI still works. Do not modify QML-facing declarations or unrelated audio ownership.
5. Make scanner bus discovery component-only: instantiate/initialize/query/terminate the component without controller construction, state synchronization or parameter enumeration. Preserve scan JSON, class filtering, error containment, module ownership, diagnostics and platform behavior. Use a small native query at the existing boundary, not a scanner mode in full plugin creation. Keep actual plugin creation semantics unchanged. Add/extend only behavior regressions for uncertain concurrency, capture consistency, silent close, or controller-free discovery; do not test SDK implementation or source wiring.

## Acceptance (one predicate)

Existing VST MIDI, lifecycle, cancellation, failure, state/history and editor behavior remains correct while callback work is demand-driven, control/state/editor operations avoid unnecessary RT exclusion and timer-dependent flushes, hidden-editor polling is quiescent with edits preserved, snapshot digests describe the captured bytes, and scanner discovery no longer needs a controller. No unproven numerical energy/allocation claims.

## Verification / controller ownership

Implementer performs read-only local inspection, no builds/tests/formatters/indexing or profilers. Report `DEFERRED_TO_CONTROLLER`, never passed. Controller serially runs:

- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks:run build/debug/porydaw_checks --filter swiftcore-pluginhost --filter swiftcore-pluginbridge --filter pluginhost-parameter-batch --filter swiftcore-projectsession --no-windowing-checks --pool=1`
- `uv run --no-sync dev checks:run build/debug/porydaw_checks --filter swiftcore-pluginhost-editor --filter swiftcore-trackeffects-editor --pool=1` for real editor/exposure behavior; no repeated human-input stress.
- `uv run --no-sync dev format --check <changed Swift files>` and `uv run --no-sync dev lsp:swift` after settled edits.

No proof ledgers exist in these check directories. Do not create or reconcile one. Do not invoke cmake/ninja directly; AGENTS/verify override generic skill commands.

## Implementer local inspection

Applies to every implementation and fix pass, including Qt Implement mode and SHARED_TREE work. Keep baselines in working context; return evidence in the result, not new report/scratch files. This is scoped inspection, not a workspace-wide audit or a substitute for the named build/check.

1. **Before editing:** use `lsp symbols` and file-local `lsp diagnostics` where supported to record declarations/scopes and baseline diagnostics. Use `read` to inspect complete affected constructs and their enclosing boundaries; recover elided content. Identify permitted whole-declaration deletions, body-only changes, and declarations/signatures/scopes that must remain. Resolve symbol references before exported-symbol changes.
2. **For structural surgery:** before partial-function deletions or moves, capture a scoped AST when supported. With clangd, use `lsp request` with `textDocument/ast`, the file URI and optional range, using the project's compilation configuration. Whole-file AST comparison is not mandatory for ordinary edits.
3. **Edit within those boundaries:** use LSP refactors where available, `ast_edit` for suitable structural rewrites, and anchored `edit` for small statement changes. Inspect staged AST proposals before applying. A body-only edit must not consume its enclosing declaration. Re-ground locations after edits; do not reuse stale ranges.
4. **After each logical edit:** run file-local diagnostics and obtain the declaration inventory again. Compare observed deletions, signatures and enclosing scopes with the permitted changes. For captured ASTs, compare the affected subtrees and parents, not raw dumps containing shifted offsets or unstable IDs. Fix new syntax errors and unintended structural changes before handing off. A recovery AST or an empty symbol result is not proof of a clean parse; these checks do not prove semantic intent.
5. **When inspection is unavailable:** report UNAVAILABLE with the tool, scope and reason; never turn missing configuration, stale results or changing dependencies into a pass. Do not rebuild/reconfigure a shared tree to hide the gap. The controller must arrange equivalent structural inspection and covering parse/compile evidence before acceptance.

## Return contract

Return status (DONE/DONE_WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT), summary, implementation, tests with commands/output or DEFERRED_TO_CONTROLLER, changedFiles, selfReviewFindings (before/after declaration and diagnostic evidence), concerns, and any exact registration needed. No report/scratch files, commits or subagent dispatches. If an actual workaround is needed, stop and explain the root invariant; do not add a silent fallback. Audio-bus deactivation, larger Render blocks and changing panel prewarm policy are not in scope.
