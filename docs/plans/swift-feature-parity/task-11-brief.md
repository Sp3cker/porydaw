# Context
R09: sustained Swift main-executor work can prevent Qt from processing its queued events. Route: SDD-track, SHARED_TREE. Base: `86c88903661ee6d44a77da505bf4b9fef777f6e0`. Read plan.md Global constraints and rule://swift-standards. Preserve the user's recent Linux fix from c47b55f4; this task repairs the drain policy, not the Qt-main integration or ProjectContext.ContextWorker.

# Exact write set
- src/swift/app/shell/QtMainExecutor.swift

Read-only: src/app/qt_main_executor.cpp, src/swift/app/shell/PorydawShellApp.swift, CMakeLists.txt, and the controller-owned throwaway probe under build/qt-executor-probe/. No other source, CMake, proof, or test-registration changes.

# Before evidence
The default Apple Swift 6.3.3 SDK lacks MainExecutor, but the installed Swift 6.4 release toolchain provides the experimental SPI. The controller compiled the actual production Swift executor and native Qt bridge into a QCoreApplication probe. MainActor.executor reports QtMainExecutor. Ordinary Task.yield loads (one and 64 workers) allow a queued Qt event through; do not claim they reproduce starvation.

A sustained chain where each main-actor task schedules its successor does reproduce it: the one-second watchdog expires while the queued Qt event remains unobserved, and the probe exits 1. The existing drain's while-true loop consumes newly enqueued batches without returning to Qt. This is an observed failure of the actual executor on macOS using Swift 6.4, not Linux qualification and not a repository-suite failure.

# Contract and steps
1. Inspect enqueue/drain and startup posting. Keep MainExecutor conformance, isolation checks, factory, C entry point, default executor, failed-pre-application scheduling behavior, and the native startup callback unchanged.
2. One drain invocation executes only a finite batch already queued at entry. Transfer that batch under the existing lock; consume the current scheduling token under that lock before executing. Jobs enqueued during execution must get a later queued Qt turn through the existing enqueue path. No job execution while holding the lock; preserve FIFO and exactly-once delivery.
3. Avoid the current copy-on-write snapshot/clear churn and avoid allocating a replacement buffer on every busy turn. Keep ownership explicit and bounded; do not assume drain cannot be re-entered through Qt event processing. No new dispatcher, arbitrary job/time quota, timer, dependency, generic queue abstraction, or guard that silently drops work.
4. Keep public/native symbols and all callers unchanged. Add no comments. Report the buffer ownership and wakeup-race argument, including enqueue while a batch is running and enqueue before QCoreApplication exists.

# Acceptance
After the source freezes, the controller exercises the actual production source using:
- `deno task --config build/qt-executor-probe/deno.json native`
- `deno task --config build/qt-executor-probe/deno.json probe`

The existing reproducer must observe the queued Qt event before its watchdog, complete, and exit 0. The controller also checks a Qt timer, FIFO/exactly-once delivery, pre-QCoreApplication enqueue/startup drain, and nested event processing against the same implementation. The temporary Deno task compiles the actual executor with the installed Swift 6.4 toolchain, explicit macOS SDK, and actual src/app/qt_main_executor.cpp; it does not replace production behavior with a mock.

The default macOS target excludes this file and its SDK cannot compile the SPI. Consequently ordinary app builds alone cannot qualify this change; no new conditional empty lane may stand in for the exercising probe. Linux/Windows runtime qualification remains blocked on hosts. The controller removes throwaway probe artifacts after recording observed results and performs the settled formatting/review gates. A registered harness would require broader cross-toolchain build integration; this bounded repair uses the actual-source runtime probe instead.

# Shared-tree execution
Skip builds/tests/lints/formatters during implementation; report DEFERRED_TO_CONTROLLER. No commits, proof edits, generated-file edits or changes to the controller-owned probe. Return the exact diff scope and source-level correctness argument. Report a missing prerequisite rather than modifying the recently fixed Linux architecture.

# Accepted result
The original actual-source starvation reproducer changed from watchdog expiry/exit 1 to queued-event progress/exit 0. An expanded probe caught a reentrant FIFO regression in the first implementation; the correction serializes entry batches and preserves the consumed wakeup for outer completion. The final Swift 6.4 compiler run with `-swift-version 6` passed: queued Qt event and a real 1 ms Qt timer observed; all 128 jobs delivered in FIFO order exactly once; 64 initial jobs enqueued before QCoreApplication construction; nested event processing did not execute later Swift jobs ahead of the active batch. The sustained chain completed before the watchdog (492 successor jobs in this observation; not an acceptance threshold). Spec and quality review approved. Native Qt startup, factory and ContextWorker remain unchanged; this is not Linux/Windows runtime qualification.
