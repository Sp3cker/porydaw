---
description: Do not sleep in tests — await the signal or inject a clock
condition:
  - "Task\\.sleep\\("
  - "Thread\\.sleep"
  - "\\busleep\\("
  - "\\bsleep\\(\\d"
scope: "tool:edit(*Tests.swift), tool:write(*Tests.swift)"
interruptMode: never
---
Avoid wall-clock waits in tests. They add fixed latency to every run, mask races, and flake under CI load.

## Use

- Await the value or event the code already exposes (`await store.load()`, `for await` on the stream).
- Swift Testing: `await confirmation(expectedCount:) { confirm in … }` for callbacks.
- XCTest: `await fulfillment(of: [exp], timeout: 1)`.
- Inject a `Clock` (`any Clock<Duration>`) into time-dependent code and drive it with a test clock.

## Exceptions

Integration tests that deliberately exercise real timing. Add a comment explaining why a controllable clock will not work.
