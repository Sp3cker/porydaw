---
description: Use static let for lazy globals — no hand-rolled optional static + accessor
condition: "(?m)static\\s+(?:private\\s+)?var\\s+_?\\w+\\s*:\\s*[\\w<>\\.]+\\?\\s*(?:=\\s*nil)?\\s*$"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`static let shared = Store()` is already lazy and initialized once, thread-safely. A `static var _shared: Store?` plus a `get { if _shared == nil { … } }` accessor is racy boilerplate.

Keep an injectable dependency, not a singleton, when tests need to substitute it.
