---
name: swift-typecheck-complexity
description: "Write Swift that type-checks fast: typed parameters on numeric generic closures, split generic pipelines, no mechanical rewrites"
scope: "tool:edit(*.swift), tool:write(*.swift)"
---

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

- Debug builds warn past 50 ms per expression in interop-free modules; `porydaw_swift_qt_interop` raises interop modules and their importers to 1000 ms. `deno task build:*` prints `warning: expression took Nms to type-check`; fix the shape with the table above.
- Preserve ordering, short-circuiting, optional semantics and numeric bounds. Never trade runtime allocation or copies for compile time.
