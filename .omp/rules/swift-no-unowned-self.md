---
description: Do not capture [unowned self] — use [weak self] or restructure ownership
condition: "\\[unowned\\s+self\\]"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`[unowned self]` crashes if the closure outlives `self`. With escaping closures and Tasks you rarely know it will not.

## Use

- `[weak self]` plus `guard let self else { return }` for escaping callbacks stored by others.
- `Task { }` in an actor or `@MainActor` type: capturing `self` strongly is usually correct. Keep the `Task` handle and `cancel()` it on teardown instead of adding weak captures.
- Break the cycle structurally: have the owner hold the closure and pass values in, not `self`.
