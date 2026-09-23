---
description: Use os.Logger, not print/NSLog, in app and library code
condition: "(?m)^\\s*(?:print|debugPrint|NSLog)\\("
scope: "tool:edit(Sources/**/*.swift), tool:write(Sources/**/*.swift)"
interruptMode: never
---
`print` has no level, category, or privacy redaction, and it vanishes in release builds run outside Xcode. Use `Logger(subsystem:category:)` from `import os` and interpolate with privacy: `logger.error("load failed \(path, privacy: .public)")`. Value types interpolate as `.public` by default; only `String`/`NSString` default to `.private`, so annotate `privacy:` where a string must be visible in logs.

The exception is CLI executables, where stdout is the product.
