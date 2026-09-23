---
description: Use bare `catch {` — `error` is already bound
condition:
  - "catch\\s+let\\s+error\\s*\\{"
  - "catch\\s+_\\s*\\{"
  - "catch\\s+let\\s+_\\b"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`catch { }` already binds `error` implicitly. `catch let error {` and `catch _ {` are noise.

Bind explicitly only when pattern-matching: `catch let error as DecodingError`, `catch StoreError.notFound(let id)`. Catch specific errors before the general one.
