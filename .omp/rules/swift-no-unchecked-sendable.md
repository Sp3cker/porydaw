---
description: Do not silence the concurrency checker with @unchecked Sendable or nonisolated(unsafe)
condition:
  - "@unchecked\\s+Sendable"
  - "nonisolated\\(unsafe\\)"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`@unchecked Sendable` and `nonisolated(unsafe)` switch off data-race checking exactly where the boundary needs it. Do not use them to quiet the checker.

## Use instead

|Shape|Reach for|
|---|---|
|Immutable data|`struct`/`enum` with `Sendable` members; `final class` with only `let` Sendable properties|
|Shared mutable state accessed asynchronously|`actor`|
|UI state|`@MainActor` on the type|
|Mutable state needing synchronous access|`final class` holding a `Mutex<State>` (`import Synchronization`, macOS 15/iOS 18+). It is then `Sendable` without `@unchecked`|
|Global constant|`static let`, which is Sendable when the type is|

## Exceptions

A type that wraps a thread-safe C/ObjC handle, or one that does its own locking the compiler cannot see. Add a one-line comment naming the synchronization mechanism, and keep the unchecked surface to one small type.
