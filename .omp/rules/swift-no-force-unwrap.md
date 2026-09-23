---
description: Never force-unwrap, force-try, or force-cast — bind, throw, or fail with a message
astCondition:
  - "$X!"
  - "try! $E"
  - "$X as! $T"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Never use `x!`, `try!`, or `as!` in production code. Each is a crash waiting on an input you did not validate.

## Why

- The crash has no context: `Fatal error: Unexpectedly found nil`.
- It hides the real contract. Readers cannot tell whether nil is impossible or merely unhandled.
- `try!` throws away the error value exactly where you need it.

## Use instead

|Situation|Reach for|
|---|---|
|Absence is a normal case|`if let x` / `guard let x else { return }` / `??`|
|Absence is a caller error|`throw` a domain error|
|Absence means a programmer bug|`guard let x else { preconditionFailure("why this can't be nil") }`|
|Downcast|`as?` plus handling, or fix the type so no cast is needed|

```swift
// Bad
let url = URL(string: config.endpoint)!
let model = try! JSONDecoder().decode(Model.self, from: data)
let cell = view as! TrackCell

// Good
guard let url = URL(string: config.endpoint) else { throw ConfigError.badEndpoint(config.endpoint) }
let model = try JSONDecoder().decode(Model.self, from: data)
guard let cell = view as? TrackCell else { preconditionFailure("registered TrackCell for \(id)") }
```

## Exceptions

- Compile-time literals whose failure is impossible, such as `URL(string: "https://example.com")!`, in a `static let` with a comment.
- Tests: prefer `try #require(x)` (Swift Testing) or `XCTUnwrap`. Do not use `!`.
