---
description: Balance every Unmanaged.passRetained with takeRetainedValue/release
condition: "Unmanaged(?:<[^>]*>)?\\.passRetained\\("
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`Unmanaged.passRetained(self)` adds a retain that ARC never balances, so it is Swift's `Box::leak`. Pair it with exactly one `takeRetainedValue()` or `release()` on the teardown path, such as the C API's unregister callback. Prefer `passUnretained` when the Swift owner keeps the object alive for the callback's lifetime.
