# Task 5: Asynchronous pitch analysis and reusable Double windows

## Context

The same 8.32-second input spends about 132 ms Release / 1,548 ms Debug in pitch refresh. Source installation synchronously waits for it, although pitch provides a suggestion rather than rendered audio. Run the unchanged analysis in bounded background work and remove repeated Float-to-Double conversion from each lag comparison. Task 4 installs prepared documents without changing the presenter source/params/sourceRevision/processed interfaces used here.

## Exact write set

- `src/swift/sample/SampleAnalysis.swift`
- `src/swift/app/samplestudio/SampleLoopTools.swift`
- `src/checks/samplecheck/LoopToolsChecks.swift`
- `src/checks/samplecheck/SourceReplacementChecks.swift`

## Prerequisites

Existing plan Global Constraints and spec. Task 4's frozen presenter interfaces: `init(document: SampleDocument, validateName: @escaping (String) -> String?)` and `replaceSource(_ document: SampleDocument)`. Other presenter observation interfaces remain unchanged. No task 4 implementation dependency.

## Interface contract

- Preserve synchronous `SampleDsp.detectPitchYin(_:rate:)` for numerical consumers. Add an explicit `checkpoint: () throws -> Void` rethrows overload, delegating the synchronous entry point to the same implementation with a nonthrowing checkpoint. Cancellation throws, never becomes an unpitched sentinel.
- `SampleLoopTools.cancelAnalysis()` is public @QtIgnored and cancels/invalidates running and pending analysis/commands. Workflow close calls it. Deinitialization must not leave CPU work running indefinitely.
- `SampleLoopTools.waitForPitchAnalysis() async` is public @QtIgnored for deterministic local checks and the temporary harness; it awaits live analysis/completion handles, including canceled work, without blocking the main thread. It does not independently restart analysis after cancel/close.
- Preserve existing public QML method and property contracts. Eventual pitch/candidate results and explicit command effects stay the same. Refresh must not synchronously analyze. Pitch-dependent commands issued while analysis is pending defer until the current result rather than running YIN synchronously or using an unpitched placeholder. A deferred command cannot mutate a replacement source or override intervening incompatible parameter edits.

## Implementation steps

1. Convert each 4096-frame analysis window to Double once in reusable fixed storage, preferably InlineArray with borrowed spans. Reuse the storage across windows; no per-window/per-lag heap allocation and no full-input copy. Use the same converted window for fractional yinDifference refinement. Preserve every window/lag, sequential accumulation order, gate, refinement, divisor and median rule. Cancellation checkpoints interrupt the expensive lag/window loops promptly.
2. Replace pitchTried plus synchronous detection with an explicit analysis lifecycle. Capture the original canonical region rules and immutable source buffer before dispatch, and construct borrowed spans inside the worker, never across suspension. At most one CPU analysis job and one newest pending source snapshot. Cancel stale work and serialize worker replacement; do not create unbounded detached tasks when the user clicks rapidly.
3. Apply only current-source results on the main actor. Source revision changes immediately clear old pitch hints/candidates/status. A completed result refreshes the hint against current key/params without auto-changing the base key. Own and cancel task handles; no retain cycle, @unchecked Sendable, nil-for-error fallback or async result into a closed owner.
4. Preserve loop-toggle/suggestion/refinement semantics by explicitly deferring pitch-dependent user commands while pending. No unrelated background loop-search redesign. Expose the wait/cancel methods above; preserve seam and waveform-facing behavior.
5. Migrate presenter constructors and source replacement calls in the two owned checks to prepared-document arguments from task 4. For restored parameters build/set the document before replacement. Wait for real analysis with existing `runBlocking` from SwiftCoreCheckSupport and waitForPitchAnalysis before assertions/actions requiring its result; no sleeps, fake analysis or test-only synchronous bypass. Retain existing behavior assertions. Do not add permanent integration tests.

## Acceptance predicate

Source replacement returns without running YIN on the main actor; current-source analysis/explicit commands produce the original results, rapid changes/close cannot publish stale pitch, and numerical output is preserved with fewer repeated conversions. NAMED CHECKS: controller runs `uv run --no-sync dev checks --filter samplecheck-processing --filter samplecheck-render --filter samplecheck-editor --filter samplecheck-analysis --pool=1` (correct the analysis registered name only if manifest proves it differs), `uv run --no-sync dev checks:bridge`, and the temporary production CPU/race harness. Controller measures the original three added local checks together and preserves the user's <=3-second added-check budget.

## Task-specific constraints

Four files are one cohesive asynchronous-analysis behavior and two existing local check adaptations. Shared-tree build/tests/lint/format/index refresh are controller-owned. Core numeric changes must be validated against the checkpoint's detector using the real input and tonal/noise/boundary inputs; claimed CPU improvement requires measured evidence. No audio-thread work, reduced filter quality, analysis truncation, arbitrary window caps or generic job framework.
