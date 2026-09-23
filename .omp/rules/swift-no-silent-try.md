---
description: Do not discard errors with try? unless failure is genuinely irrelevant
condition:
  - "(?m)^\\s*_\\s*=\\s*try\\?"
  - "(?m)^\\s*try\\?\\s"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
A bare `try? save()` statement or `_ = try? …` turns a failure into silence.

## Use

- Propagate: `try save()` from a `throws` function.
- Handle: `do { try save() } catch { logger.error("save failed: \(error)") }`.
- Fallback on purpose: `let cfg = (try? load()) ?? .default` is fine. The fallback documents the intent.

## Exceptions

Best-effort cleanup whose failure changes nothing, such as removing a temp file that may not exist. Add a short comment.
