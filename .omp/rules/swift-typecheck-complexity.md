---
name: swift-typecheck-complexity
description: "Keep Swift expression type-checking local; avoid compound closure constraint systems"
scope: "tool:edit(*.swift), tool:write(*.swift)"
---

Swift's type checker can spend seconds solving a single expression that mixes closures, overloads, conversions, optionals, and chained operators. Keep inference local when writing such code.

- Prefer named, typed intermediate values over nesting `map`/`compactMap`/`reduce`/`sorted`, optional `map` plus `??`, ternary comparators, or multiple conversions inside one expression.
- For multi-step projections or accumulations, use a typed result and a `for` loop when that makes the operations easier to read and type-check. Reserve capacity when the result size is known. Bind nontrivial matcher closures to an explicitly typed local before passing them to generic APIs.
- Keep simple `map`, `filter`, `sorted`, and trailing closures. Do not mechanically ban closures or extract one-line wrappers just to shorten an expression.
- Preserve ordering, duplicate-key behavior, short-circuiting, numeric bounds, and optional precedence when changing expression shape. Do not trade runtime allocations or copies for speculative compile-time savings.
- If build time is the reason for a refactor, identify the slow expression with compiler diagnostics, compare the same build target before and after, and run the behavior check for the changed path.
