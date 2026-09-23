---
description: No [String: Any] / Any at boundaries — decode into a typed model
condition:
  - ":\\s*\\[?String\\s*:\\s*Any\\]"
  - "\\bas\\?\\s*\\[String\\s*:\\s*Any\\]"
  - ":\\s*Any\\b(?![A-Z\\w])"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
`Any` and `[String: Any]` erase types the way an unconstrained `any` does. They push every shape check to runtime `as?` chains.

## Use instead

- `Codable` models decoded once at the boundary (JSON, plist, IPC, persisted data).
- A generic parameter when the caller supplies the type.
- `some P` for one concrete conforming type, and `any P` only for real heterogeneity.
- An `enum` with associated values for a closed set of shapes.

```swift
// Bad
guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = json["id"] as? String else { return nil }

// Good
struct Payload: Decodable { let id: String }
let id = try JSONDecoder().decode(Payload.self, from: data).id
```

## Exceptions

ObjC/Foundation APIs that really do traffic in `Any` (`userInfo`, `KVC`). Convert to a typed value right next to the call.
