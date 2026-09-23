---
description: Do not subclass NSObject unless Objective-C interop requires it
condition: "class\\s+\\w+\\s*:\\s*NSObject\\b"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`NSObject` brings dynamic dispatch, reference identity equality, and ObjC runtime overhead. Use a Swift `struct`, `enum`, or `final class`. Subclass `NSObject` only for `@objc` delegates/protocols, KVO, target-action, or `NSCoding`.
