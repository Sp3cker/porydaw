# First-frame audio startup — completed change

Recorded 2026-10-01. Design reviewed with m1 before implementation; final changes independently approved by `thermo-nuclear-reviewer`.

## Problem

QML construction of `ShellPresenter` synchronously constructed `ApplicationSession`, `NativeAudio`, and `AudioDevice`. CoreAudio initialization therefore blocked the GUI thread before the first shell frame. LLDB and Instruments established this ownership chain without source logging.

## Implementation

- `ShellPresenter` waits for both chrome preference restoration and the first `frameSwapped` delivery. Either event can arrive first. A latched `startupBegun` makes startup idempotent and disables further frame notifications. Cancelling a pending close resumes eligible startup.
- `ApplicationSession` construction no longer creates audio. Its readiness state is `idle`, `preparing`, `ready`, or `failed`; all consumers share one preparation task. Direct Swift opens start preparation on demand rather than requiring a rendered window.
- `AudioDevice.prepare()` is `@concurrent` and returns a uniquely owned, stopped device using Swift's `sending` transfer. `NativeAudio` adopts it on MainActor through its async initializer. Existing shutdown-before-bank-release ordering remains.
- Desired engine settings, volume, resonance suppression, and polyphony inversion survive the preparation interval and are applied when audio becomes ready. No song workspace binds before readiness.
- Deliberate project opens supersede deferred saved-tab restoration, including opens completed before the first frame.
- Cancelling one readiness waiter does not cancel preparation for other consumers. A genuine initialization failure retains its cause instead of becoming a generic unavailable-audio error; preparation is not silently retried.
- Committed close cancels pending preparation but retains its task for settlement. Late devices are discarded rather than adopted; disposal publishes no late error. Scene detachment completes before `closeReady`, which waits for preparation to settle.
- While close waits, persistent chrome and actions are disabled and the status bar shows “Closing…”. The window remains visible until native last-window quit can finish normally.

Qt queues the render-thread `frameSwapped` signal's QML handler to the GUI thread. No additional native dispatcher was introduced. Menus, effects, glyphs, keyboard shortcut priority, and preference storage remain unchanged. No logging, fallback, retry, or new unchecked `Sendable` was added.

## Responsibility map

| Owner | Responsibility |
| --- | --- |
| `src/swift/app/audio/AudioDevice.swift` | Off-main stopped-device preparation and ownership transfer |
| `src/swift/app/NativeAudio.swift` | MainActor audio ownership and native lifetime |
| `src/swift/app/ApplicationSession+Audio.swift` | Single-flight readiness, adoption, and non-starting settlement wait |
| `src/swift/app/ApplicationSession+Tabs.swift` | Await readiness and preserve failure/cancellation behavior |
| `src/swift/app/ApplicationSession+ProjectOpening.swift` | Explicit-open precedence over saved restoration |
| `src/swift/app/ApplicationSession+Close.swift` | Disposal and cancellation without losing settlement ownership |
| `src/swift/app/shell/ShellPresenter.swift` | First-frame latch and scene-close settlement |
| `src/ui/shell/ShellWindow.qml`, `ShellStatusBar.qml` | Frame delivery and visible closing feedback |
| Transport and polyphony presenters | Retain desired settings before the native owner exists |

Constructor callers and readiness-dependent checks migrated to the async contract. New checks live in `src/checks/workspace/startup_checks.swift` and `src/checks/editorqml/tst_ShellStartup.qml`. No proof ledgers were present or modified.

## Verification observed

- `deno task build:app`: passed, including restoration of the normal non-profiled build.
- `deno task checks --filter swiftcore --verbose`: all 13 Swift suites passed across the full run and the targeted `swiftcore-projectsession` recheck after correcting a test task-wait race.
- `deno task checks:shell --filter shell-startup --filter shell-transport --filter shell-tabs --filter shell-open-failure --filter shell-settings --filter shell-menus --verbose`: 18 selected entries passed.
- `deno task checks:bridge`: zero baselined findings.
- `deno task format --check --base HEAD`: passed.
- Actual-app LLDB observed `showEvent` on main, then `frameSwapped` on the render thread, then `firstFrameRendered` on main, then `ma_device_init` on a cooperative worker.
- The real app restored a saved song; Space advanced the playhead and native voice meters; normal close exited 0.
- With only the device-initialization worker suspended, native close displayed disabled chrome and “Closing…”. Releasing the worker allowed exit 0, preserving the saved-song recipe.

Spec, GUI, and independent thermo-nuclear reviews found no blockers. The reviewer accepted `ShellPresenter.swift` at 726 lines because startup and close share its existing lifecycle ownership, and the 668-line checks CMake source catalog received only one registration line. No touched file exceeded 1,000 lines.

Startup timing captures were single runs with uncontrolled cache state and did not measure process-to-screen latency. They do not establish a quantified speedup. Generated profiling reports were deleted at the user's request; raw captures remain local and are not part of this change.
