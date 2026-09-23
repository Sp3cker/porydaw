---
description: Do not leave @available(*, deprecated) shims behind after refactors
condition: "@available\\([^)]*deprecated"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
In code you control, update every call site and delete the old name in the same change. Do not leave `@available(*, deprecated, renamed:)` aliases behind. Two live APIs means maintainers keep both working.

## Exceptions

Published library API with external clients under semantic versioning. Deprecate for one release, then remove.
