---
description: Default to untyped throws; use throws(E) only for closed, exhaustively handled error domains
condition: "\\bthrows\\s*\\(\\s*(?!any\\s+Error|Never)\\w"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Typed throws (SE-0413, Swift 6) fixes the error type into the signature. Adding a new failure later breaks every caller, and wrapping underlying errors becomes mandatory.

Use `throws(E)` only when:

- The module is self-contained, E is a closed `enum`, and callers `switch` over it exhaustively.
- Embedded or no-allocation code where existential errors are not acceptable.
- A generic function that rethrows its closure's error: `func map<E>(_ f: (T) throws(E) -> U) throws(E)`.

Otherwise write plain `throws` and throw a domain error type.
