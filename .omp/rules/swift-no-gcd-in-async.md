---
description: Do not mix GCD primitives into Swift concurrency code
condition:
  - "\\bDispatchSemaphore\\b"
  - "\\bDispatchGroup\\(\\)"
  - "DispatchQueue\\.main\\.async"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
New code uses async/await, actors, and structured concurrency, not GCD queues and semaphores.

## Why

- A semaphore that blocks a cooperative-pool thread can deadlock the runtime.
- `DispatchQueue.main.async` hides actor isolation from the compiler, so it cannot check it.
- Groups and queues lose cancellation and priority propagation.

## Migration

|GCD|Concurrency|
|---|---|
|`DispatchQueue.main.async { … }`|`@MainActor` function/type, or `await MainActor.run { … }`|
|`DispatchGroup` + `notify`|`async let` or `withTaskGroup`|
|`DispatchSemaphore` waiting on a callback|`withCheckedContinuation`|
|Serial queue guarding state|`actor` or `Mutex`|

## Exceptions

Real-time or audio render threads, and C callbacks on threads you do not own. Keep the GCD code at that edge and bridge into concurrency once.
