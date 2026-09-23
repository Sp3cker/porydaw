---
description: No implicitly unwrapped optional (T!) stored properties outside IBOutlets
condition: "(?m)\\b(?:var|let)\\s+\\w+\\s*:\\s*[\\w<>\\[\\]\\.: ]+!\\s*(?:$|=)"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Do not declare `var engine: AudioEngine!`. An implicitly unwrapped optional is a force-unwrap spread across every use site.

## Use instead

- Initialize in `init`, and make it `let` if possible.
- `lazy var` when construction needs `self`.
- A real `Optional` when the value can actually be absent.
- Pass dependencies into `init` instead of setting them after construction.

## Exceptions

`@IBOutlet` properties and legacy `XCTestCase` `setUp` fixtures. Swift Testing suites initialize in `init` instead.
