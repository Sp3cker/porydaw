---
description: Use optional chaining for single calls, not an if-let wrapper
astCondition:
  - "if let $X { $X.cancel() }"
  - "if let $X { $X.invalidate() }"
  - "if let $X { $X.removeFromSuperview() }"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`if let task { task.cancel() }` is `task?.cancel()`. The unwrap adds a branch and does nothing else.

Keep the unwrap only when the body does more, for example `task.cancel(); task = nil`. In that case prefer `task?.cancel(); task = nil`.
