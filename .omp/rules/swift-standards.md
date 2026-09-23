---
description: Swift code-quality standards — style, optionals, value semantics, concurrency, API design, performance, testing
globs: "*.swift, Package.swift"
---
## Style
- Run the repo's configured formatter (SwiftFormat or swift-format) and SwiftLint. Never hand-format, and never add a second style. If the repo has no config, use Xcode defaults: 4-space indent, trailing commas in multiline collections.
- `// swiftlint:disable:next <rule>` goes on a single line with a reason. Never use a file-wide `disable`.
- Access control is `private` by default. Widen deliberately. Mark classes `final` unless designed for subclassing.
- One primary type per file. Group protocol conformances in `extension T: P { }` blocks.
- No tiny wrappers: inline one-expression functions and computed properties unless the name is a durable domain concept, a protocol requirement, or a test seam.

## Optionals and errors
- Handle absence with `guard let` early exits. The happy path is not indented.
- Throw domain errors (`enum StoreError: Error`) carrying context. Never throw `NSError(domain:code:)` from new Swift code.
- `Result` is for storing or passing outcomes (callbacks, caches). Use `throws` for control flow. Never write `typealias Result<T> = Swift.Result<T, MyError>`; it shadows the standard library `Result`.
- Use `precondition`/`preconditionFailure` for programmer errors that must hold in release builds. `assert` disappears in release.
- Use `defer` for cleanup that must run on every exit path.

## Value vs reference types
- Default to `struct` and `enum`. Use `class` only for identity, shared mutable state, or ObjC interop. Use `actor` for shared mutable state accessed concurrently.
- Prefer `let`. Use `mutating` methods on structs over classes-for-mutability.
- Model closed states with `enum` plus associated values, not a bag of optionals and flags. `switch` exhaustively and avoid `default:` on your own enums so new cases fail to compile.

## Concurrency (Swift 6 language mode)
- Target strict concurrency (`-strict-concurrency=complete` / Swift 6 mode). Fix diagnostics; do not suppress them.
- Put UI types on `@MainActor` at the type, not per method.
- Actor state can change across any `await` (reentrancy). Re-validate invariants after each suspension, and do not split read-modify-write across an `await`.
- Prefer structured concurrency (`async let`, task groups) over unstructured `Task { }`. Keep and cancel the handles of unstructured tasks.
- Check `Task.isCancelled` or `try Task.checkCancellation()` in long loops.
- Values crossing isolation must be `Sendable`. Do not work around this with `@unchecked`.

## API design (swift.org API Design Guidelines)
- Clarity at the point of use over brevity. Name for the role, not the type (`remove(at:)`, not `removeElement(atIndex:)`).
- Mutating/non-mutating pairs: `sort()`/`sorted()`, `formUnion`/`union`.
- Booleans read as assertions (`isEmpty`, `hasSuffix`). Protocols are nouns (`Collection`) or capabilities (`Equatable`, `…able`).
- Label arguments so calls read as English phrases. Omit the label only when the first argument completes the base name.
- Prefer `some P` over `any P` for parameters and returns. Use `any` only for heterogeneous storage.
- Document public API with `///` DocC comments: a summary line plus `- Parameter`, `- Returns`, `- Throws`.
- Use `@discardableResult` only when ignoring the result is common and safe.

## Memory and performance
- ARC cycles: an escaping closure stored on `self` that captures `self` strongly leaks. Use `[weak self]` or restructure.
- Delegates are `weak var delegate: (any Delegate)?` with `AnyObject`-constrained protocols.
- Copy-on-write: mutating a collection while another reference holds it copies the whole buffer. Avoid copying large arrays in hot loops, and use `reserveCapacity`.
- Prefer `final` and `private` so calls dispatch statically. Avoid existentials (`any P`) in hot paths.
- Use `lazy` sequences for chains over large collections consumed once. Use `ContiguousArray` for non-class elements in hot code.
- Real-time/audio threads: no allocation, locks, `await`, ObjC messaging, or logging on the render thread.
- String: index with `String.Index`, not `Int`. `count` is O(n).

## Testing
- New tests use Swift Testing: `@Test`, `#expect`, `try #require`, parameterized `@Test(arguments:)`, and `@Suite` structs initialized in `init`. Use XCTest only where the project already standardizes on it, or for UI/performance tests.
- One behaviour per test. Name tests for the observable contract.
- No sleeps (see swift-no-test-sleep). Inject `Clock` and dependencies through protocols or closures, not singletons.
- Tests must not depend on execution order or shared global state. Swift Testing runs them in parallel by default.
