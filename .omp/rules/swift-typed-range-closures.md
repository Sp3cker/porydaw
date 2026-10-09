---
description: Type closure parameters over literal ranges and strides when the body does numeric work
condition: "(\\(\\s*-?\\d[\\d_]*\\s*\\.\\.[.<]\\s*[\\w.]+\\s*\\)|stride\\(from:[^)]*\\))\\s*\\.\\w+\\s*(\\([^(){}]*\\)\\s*)?(\\((where|by):\\s*)?\\{(?!\\s*\\()"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
An untyped closure over a literal range or `stride` makes the solver infer the range bound, literals, arithmetic and conversions as one system: 33–73 ms per expression here.

Spell the parameter type and keep the body: `(1...500).allSatisfy { (d: Int) -> Bool in … }`, `(0..<6).map { (i: Int) in Tick(24 + i * 24) }`. Skip only trivial bodies (`{ _ in UUID() }`, `{ Int64($0) }`). Details: `swift-typecheck-complexity`.
