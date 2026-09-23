---
description: Do not reach for Task.detached — use Task {}, async let, task groups, or a nonisolated/@concurrent function
condition: "Task\\.detached\\b"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`Task.detached` drops priority, task-locals, and actor context, and it escapes structured cancellation.

|Goal|Use|
|---|---|
|Child work tied to the caller's lifetime|`async let` / `withTaskGroup`|
|Fire-and-forget from sync code|`Task { }` and keep the handle to cancel|
|Get off the main actor for CPU-heavy work|A `nonisolated` async function, or `@concurrent` (Swift 6.2+)|

Keep `Task.detached` only when you really must not inherit context. Add a comment saying why.
