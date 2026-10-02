---
description: Answer performance questions with xctrace, not in-code clocks or logging
condition: "(ContinuousClock\\(\\)|SuspendingClock\\(\\)|\\bDate\\(\\)|\\bDate\\.now\\b|DispatchTime\\.now\\(\\)|mach_absolute_time\\(|CFAbsoluteTimeGetCurrent\\(|clock_gettime\\(|std::chrono::steady_clock::now\\(|\\bQElapsedTimer\\b)"
scope: "tool:edit(src/swift/**/*.swift, src/app/**, src/audio/**, src/project/**, src/render/**, src/ui/**/*.qml), tool:write(src/swift/**/*.swift, src/app/**, src/audio/**, src/project/**, src/render/**, src/ui/**/*.qml)"
interruptMode: never
---
Ad-hoc timing is not accepted in app code or checks: no clock snapshots, manual counters, or `print`/`Logger` output used as performance measurement.
Answer performance questions with Instruments: `deno task xctrace record` plus `summarize`/`compare` (templates: `CPU Profiler`, `Time Profiler`, `Logging` for signposts, `Allocations`).
For playback CPU, follow the `porydaw-instruments-playback-cpu` skill.
The only permitted in-code instrumentation is `OSSignposter` (`import os`) interval/event signposts with a stable subsystem and one category per feature; signposts may stay in production code:
```swift
import os
let signposter = OSSignposter(subsystem: "com.sp3cker.porydaw", category: "playback")
let state = signposter.beginInterval("decode")
signposter.endInterval("decode", state)
```
Exempt: `ContinuousClock` (or equivalent) as product behavior, e.g. an audition tick advancing a playhead, and benchmark executables under `tools/`.
The exemption is for behavior, never for measurement that will be reported.
Never write trace parsers; `tools/xctrace.ts` is the single parser.
