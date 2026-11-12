# Task 28 — Idempotent plugin catalog cache persistence

## Placement and authority

Independent energy follow-up to task 26, implementing catalog-only audit F6 from `agent://FableVstEnergyAudit`. Read `plan.md` Global Constraints and linked `spec.md` catalog requirements. User selects **m1 / Claude Opus 5.5**. SHARED_TREE; checkpoint `290d15671db8d3e8f2e49d63ecc9579e1ea2d5a0`. Preserve existing dirty UI/header/stopped-audition work. No commits or merges.

## Target / ownership

Only `src/swift/pluginhost/PluginCatalog.swift` and `src/checks/pluginhost/PluginCatalogChecks.swift`. Controller owns docs, registration and all build/check/format/index commands. Native scanner changes belong to task 27. No other source edits.

## Change

1. Inspect existing scan publication, persistence, cache load/create/repair, write failures, retry, cancellation and progressive result behavior. The prior task-26 review explicitly preserved necessary create/repair/error-retry writes; do not blindly delete the first/final persist calls.
2. Persist catalog records only when persistence is actually needed, avoiding duplicate encodes/atomic replacement for a healthy unchanged scan. Preserve required cache creation after no cache, repair after malformed/missing cache, retry after failed writes, pruning removed modules, per-result progress, forced rescan, cancellation and unavailable scanner reporting. Keep scan-state/error notifications even when records don't change, but do not fan out redundant record projections. Prefer one canonical ownership model rather than parallel cache generations/booleans that drift. No timer, hashing of serialized JSON to detect change, or unrelated cache framework.
3. Preserve or extend only consumer-visible regression coverage for cache coherence/recovery and scan results. Do not add tests for implementation counters, callback counts, JSON encode counts or source wiring. Existing behavior tests cover unchanged scans; use a disposable measurement if needed to establish unchanged file replacement rather than pinning incidental timestamps as a permanent contract.

## Acceptance (one predicate)

A successful unchanged scan keeps a healthy durable catalog without redundant encodes/replacements while all catalog discovery, refresh, create/repair/retry, cancellation, cache and error behavior remains correct.

## Verification

Read-only file-local LSP symbols/diagnostics before and after; references before changing exported APIs. Inspect complete affected constructs/scopes; compare permitted vs actual declaration changes and report unavailable tooling honestly. Do not run builds/tests/formatters/indexers while shared-tree implementation is active. Controller runs `uv run --no-sync dev build:checks`, the existing `swiftcore-pluginhost` suite (which includes PluginCatalogChecks), changed Swift formatting check and final Swift index. Report DEFERRED_TO_CONTROLLER. No proof ledgers are in scope.

## Return

Return full status (DONE/DONE_WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT), summary, implementation, tests (command/output or DEFERRED_TO_CONTROLLER), changedFiles, selfReviewFindings (baseline/final symbols and diagnostics, declaration changes), concerns. No scratch/report files, commits, other source edits or subagents. No workaround without controller approval; use the responsible cache owner's root-cause fix.
