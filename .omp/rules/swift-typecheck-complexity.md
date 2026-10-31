---
name: swift-typecheck-complexity
description: "Keep Swift expression type-checking local; apply Porydaw's measured fixes without mechanical rewrites"
scope: "tool:edit(*.swift), tool:write(*.swift)"
---

Swift's type checker can spend seconds solving a single expression that mixes closures, overloads, conversions, optionals, and chained operators. Keep inference local when writing such code.

- Prefer named, typed intermediate values over nesting `map`/`compactMap`/`reduce`/`sorted`, optional `map` plus `??`, ternary comparators, or multiple conversions inside one expression.
- For multi-step projections or accumulations, use a typed result and a `for` loop when that makes the operations easier to read and type-check. Reserve capacity when the result size is known. Bind nontrivial matcher closures to an explicitly typed local before passing them to generic APIs.
- Keep simple `map`, `filter`, `sorted`, and trailing closures. Do not mechanically ban closures or extract one-line wrappers just to shorten an expression.
- If build time is the reason for a refactor, identify the slow expression with compiler diagnostics, compare the same build target before and after, and run the behavior check for the changed path.

Measured in this repo (Swift 6.4, Debug). Module structure costs more than expression shape; see `swift-interop-scope`.

## Slow shapes and the fix that worked

|Shape|Measured|Fix|
|---|---|---|
|Untyped closure over a literal range or `stride` whose body mixes integer literals, arithmetic and numeric conversions: `(1...500).allSatisfy { d in abs(Double(a[d]) - Double(b[d])) <= 2e-6 }`|33–73 ms each, 9 sites|Type the parameter: `{ (d: Int) -> Bool in … }`, body unchanged → 0.4–1.3 ms|
|One expression chaining several generic closures: `.flatMap { … }.filter { … }.min(by: { … })`|23 ms|Bind each stage to a named `let` → <0.6 ms per stage|
|Large inferred array of records: `static let entries = [Entry(…), …]`|17 ms|Untested; annotate `[Entry]` first|

The parameter type is what matters: `(0..<6).map { Int64(24 + $0 * 24) }` 9 ms, `{ (i: Int) in … }` 0.3 ms, result type only `{ i -> Int64 in … }` 4 ms.

## Not slow; leave as written

Known-type `==`/`&&` chains, `optional.map { … } == true`, short `Data`/`String`/array `+` chains, `.init(…)` implicit members, small literal comparisons, tuple compares: all ≤6 ms. Do not add `Int(3)` coercions, `var ok = false; if … { ok = … }` ladders or `as [T]` casts; they bought <1 ms.

## Not a win

- Moving cost into macro-generated code or another file. Rewriting `UndoHistoryPanel` cut its authored time 390 → 20 ms and raised QtBridge-generated time by 350 ms; module wall time stayed flat. Judge by module wall time.
- Rewriting expressions in C++-interop modules whose time is lazy Clang import: 20–600 ms billed to whichever expression first touches Qt/C++ declarations in each frontend process.

## Guard and constraints

- Debug builds warn past 50 ms per expression in interop-free modules; `porydaw_swift_qt_interop` raises interop modules and their importers to 1000 ms. `uv run --no-sync dev build:app` and `build:checks` print `warning: expression took Nms to type-check`; fix the shape with the table above.
- Preserve ordering, short-circuiting, optional semantics and numeric bounds. Never trade runtime allocation or copies for compile time.
