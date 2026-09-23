---
description: Prefer Synchronization.Mutex (or an actor) over NSLock, os_unfair_lock, pthread mutexes, and barrier queues
condition:
  - "\\bNSLock\\(\\)"
  - "\\bos_unfair_lock\\b"
  - "\\bpthread_mutex_"
  - "\\.sync\\s*\\(flags:\\s*\\.barrier"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Use `Mutex<State>` from `import Synchronization` (Swift 6, macOS 15/iOS 18+). The protected state lives inside the lock, so it cannot be touched unlocked. `withLock` scopes access, and the owning type becomes `Sendable` without `@unchecked`.

```swift
// Before
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

// After
final class Counter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
}
```

|Need|Use|
|---|---|
|Deployment target below macOS 15|`OSAllocatedUnfairLock<State>` (macOS 13+)|
|Access across `await`|`actor`. Never hold a lock across `await`|
|Raw `os_unfair_lock` as a stored `var`|Never. Its address is unstable in Swift|
