---
description: Use @Observable instead of ObservableObject/@Published for new models
condition:
  - ":\\s*(?:[\\w, ]+,\\s*)?ObservableObject\\b"
  - "@Published\\b"
  - "@StateObject\\b"
  - "@ObservedObject\\b"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
On macOS 14/iOS 17+, new models use the `@Observable` macro (add `import Observation`). Views track only the properties they read, so there are no whole-object invalidations and no `@Published` boilerplate.

|Combine-era|Observation|
|---|---|
|`class M: ObservableObject` + `@Published var x`|`@Observable final class M { var x }`|
|`@StateObject var m = M()`|`@State var m = M()`|
|`@ObservedObject var m`|`var m` (plain), or `@Bindable var m` for bindings|
|`@EnvironmentObject`|`@Environment(M.self)`|

Keep `ObservableObject` when the deployment target is below macOS 14/iOS 17, or when Combine publishers of the properties are consumed.
