---
description: Use AsyncStream.makeStream() instead of the closure-based AsyncStream initializer
condition:
  - "AsyncStream(?:<[^>]*>)?\\s*\\{"
  - "AsyncThrowingStream(?:<[^>]*>)?\\s*\\{"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Prefer `AsyncStream.makeStream(of:)`. It returns the stream and its continuation side by side, with no closure-escape trick.

```swift
// Bad — continuation smuggled out of the builder closure.
var cont: AsyncStream<Event>.Continuation!
let events = AsyncStream<Event> { cont = $0 }

// Good
let (events, continuation) = AsyncStream.makeStream(of: Event.self)
continuation.onTermination = { _ in source.stop() }
```

It was added in Swift 5.9 and is back-deployed. Always call `finish()` and set `onTermination` so the producer's resources are released.
