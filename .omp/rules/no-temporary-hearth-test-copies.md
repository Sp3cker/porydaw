---
name: no-temporary-hearth-test-copies
description: "Never copy hearth-test into a temporary directory merely to run tests"
condition: "cp\\s+-cR\\s+\\.\\.\\/\\.\\.\\/hearth-test\\s+\\/tmp\\/porydaw-"
scope: "tool"
---

Do not copy `../../hearth-test` into `/tmp` merely to run a test. Run the applicable test against the existing `hearth-test` project. If the test would mutate that project, use a non-copying test mode or ask before creating an isolated fixture.