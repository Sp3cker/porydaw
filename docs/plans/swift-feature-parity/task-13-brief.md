# Context

R24: `NativeAudio` is MainActor-owned but suppresses isolation on its private `AudioDevice` solely to use it from deinit. Enforce that lifetime boundary with an isolated deinitializer rather than an unsafe stored-property escape. Base: `fea4034d`. Read [plan.md](plan.md) Global constraints and its linked spec. Production ownership is independent of task 12 and preserves NativeBankLease's public interface; the check envelope also consumes task 12's newly MainActor-qualified bank-lease suite.

# Exact write set

- `src/swift/app/NativeAudio.swift`
- `src/checks/audio/AudioControllerChecks.swift`
- `src/checks/support/corecheck/CoreCheckSupport.swift` (only actor-qualified dispatch of `runAudioControllerChecks` in suite 3 and task 12's `runBankLeasesSuite` in suite 31)

Proof-only owner, after sources freeze: `src/checks/audio/proof.tst_audiobackend.txt`. No implementer proof edits. The retained C++ backend check and registration stay: the Swift suite is still Apple-gated, so retiring the only non-Apple backend lane would silently shrink coverage. Other audio ledgers are not this task's write set.

# Prerequisites

Task 5's real workspace audio behavior and task 11's Qt-main executor remain intact. The runner sets `PORYDAW_AUDIO_BACKEND=null` in `tools/run_checks.ts`; no hardware dependency or environment mutation belongs in the new checks. `@testable import PorydawApp` is an existing check convention. The C envelope invokes its suites on the Qt main thread and already uses `ReportBox` plus `MainActor.assumeIsolated` for actor-owned suites.

# Interface contract

- Remove `nonisolated(unsafe)` from `NativeAudio.device` and use `isolated deinit` on the existing MainActor class.
- Preserve `withExtendedLifetime(bankLease) { device.shutdown() }`: miniaudio callbacks are joined and both engines destroyed before releasing the borrowed native bank. Do not change `AudioDevice.shutdown`, rendering, sample/audition storage, public methods, actor assignment or native ABI.
- Keep `runAudioControllerChecks(_:)` as the suite entry point, now MainActor-qualified. Reuse the existing `ReportBox` / `MainActor.assumeIsolated` envelope for that call in `pdcSuiteRun` case 3 and for `runBankLeasesSuite(_:)` in case 31. Task 12 owns the latter suite's annotation and service-wait repair; this task remains the sole envelope writer. Other routing and thread assumptions stay unchanged. No new unchecked-Sendable wrapper.
- Add private actor-qualified `checkNativeAudioLifetime(_:)` in the existing audio controller check file. It uses the actual NativeAudio, project-backed bank and real null-backend callback, not a fake device or new production diagnostic hook.

# Implementation steps

1. Inspect the ownership chain from NativeAudio through AudioDevice to AudioRenderEngine and the existing native bank lease. Apply the isolated-deinit cutover without modifying the teardown order or introducing detached cleanup, a fallback executor, locks, dispatchers or shutdown flags.
2. Extend the existing audio suite with one combined forced-null behavior assertion (`usingNullBackend`, `nullBackendForced`, resolved backend `Null`) rather than copies of the six overlapping C++ setup checks. Exercise an actual sounding bank before teardown.
3. Prove bounded ownership release after both a MainActor last release and a last release from a detached task. Use weak facade/bank references and a deterministic one-shot handoff that keeps the detached task as the sole final owner; no sleeps to guess ownership, polling stress loop, fake teardown counter or production test getter. Close the project service before final release so its canonical bank cache does not conceal the facade's lease lifetime. Let the existing MainActor/run-loop test support deliver isolated cleanup, then assert that the facade and pinned lease are released. The deadline must expire before `runBlocking`'s outer timeout.
4. Preserve renderer/control assertions and fix actor dispatch only at their existing entry seam. Remove any stale comment in the constructs touched, without adding new code comments. Report which backend oracle sites the new predicate actually proves; keep device-start setup and unsupported-platform qualifications honest.

# Acceptance predicate

The production source compiles without unsafe isolation suppression. Real null-backend playback reaches its observable sounding state; both final-owner paths release the facade and its pinned bank within the bounded wait. There is no fallback deinit path or surviving owner introduced by the test. Existing transport/audio checks remain green.

Controller-run named checks after writers settle:
- `deno task verify --filter swiftcore --verbose` — audio suite, actual facade release cases, and existing playback/transport consumers.
- `deno task verify --filter audiocheck-backend --verbose` — retained C++ backend qualification remains registered.
- `deno task verify:shell --filter shell-transport --verbose` and `deno task verify:shell --filter shell-polyphony --verbose` — live GUI audio consumers.
- `deno task build:app` — production actor/deinit compilation.
- Native macOS launch of the built app against `src/checks/fixtures/decompproject` / `mus_route101`, Space playback and normal Cmd-Q exit — actual application lifetime, not offscreen-only evidence.
- `deno task proof check --executed` — after the proof-only handoff; no unsupported platform-parity claim.

# Task-specific constraints

No C++ retirement, build registration edit, new audio policy, blanket Sendable conformance, `nonisolated(unsafe)` replacement elsewhere or MainActor implementation change. If the supported compiler cannot express isolated deinit, report the concrete diagnostic rather than invent a workaround. The controller owns shared build/test/lint/format commands and proof files; required local structural inspection is read-only.
