---
description: Use withChecked(Throwing)Continuation, not the Unsafe variants
condition: "withUnsafe(?:Throwing)?Continuation"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Use `withCheckedContinuation` / `withCheckedThrowingContinuation` when bridging callbacks. The checked variants trap on a double resume and warn on a leaked continuation. The unsafe variants silently hang or corrupt state.

Resume exactly once on every path, including error and cancellation paths. Switch to the Unsafe variant only after profiling shows the check costs something on a proven hot path, and leave a comment saying so.
