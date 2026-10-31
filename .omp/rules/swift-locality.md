---
name: swift-locality
description: "Declare Swift locals at first use in the narrowest scope"
scope: "tool:edit(*.swift), tool:write(*.swift)"
---

Declare locals immediately before first use, in the narrowest scope. Inline simple single-use
expressions unless naming improves clarity. Keep related parsing, validation, and use together;
never batch unrelated declarations upfront. Preserve evaluation and validation order. Stored
properties may remain grouped.

Declare helper functions and helper types above their first call site (bottom-up for helpers;
`init` and route registration such as `boot(routes:)` may remain at the top of the type).

Review locality in changed Swift declarations, then run the repo's configured formatter and covering Swift checks. Do not add or expand a baseline to suppress violations.
