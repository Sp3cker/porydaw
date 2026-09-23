---
description: Use if let x / guard let x shorthand, not if let x = x
astCondition:
  - "if let $X = $X { $$$B }"
  - "guard let $X = $X else { $$$B }"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
Swift 5.7 (SE-0345) added unwrap shorthand. Write `if let name {` and `guard let url else { return }`. Repeating the name adds nothing.

Keep the long form when renaming for clarity (`if let track = selectedTrack`) or unwrapping a member (`if let id = model.id`).
