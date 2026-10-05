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

## Superseded 2026-10-01

Startup no longer waits for the first frame. `ShellPresenter` prefetches at
construction (`prepareAudio` + project/song read) and `openStartup` runs at
`chromeRestored`; `firstFrameRendered` only re-offers startup. Measured
cause: both loaders serialized behind QML construction by MainActor hops —
`prepareAudio`'s task inherited MainActor and `ProjectService.open` awaited a
MainActor bank-views reset. Now `NativeAudio.make` prepares off-main with
main-side adoption, `open` never hops (adoption sites reset bank views
explicitly), and the project/song read runs in a `@concurrent` task whose
result a matching switch adopts; unused prefetches close their service.
`--song` without `--project` now opens in the recipe's project. Failure,
cancellation, and settlement semantics above are unchanged. `MidiFile` and
`LoadedSong` are `Sendable`, so the song prefetch keeps bytes and decode
off-main; the song composes on the main actor at `openTab`. Residual: the
prefetch's `openSong` still publishes bank views through the main actor (a
no-op before adoption) — a later change can defer that publish to adoption.

## Superseded 2026-10-02: window-first startup

The eager-construction policy above is superseded. `ShellWindow` owns the persistent
window, font-readiness gate, restored chrome, and close coordination before its first
frame. It uses the native ApplicationWindow template directly, avoiding Controls
style initialization for an empty window. The captured font's requested pixel size
supplies typography without resolving an unused system font face. Saved geometry is
applied before native show.

The actual `frameSwapped` delivery requests the separate `ShellContent.qml`.
Its control tree is constructed synchronously after that frame, preserving menu
ordering and dialog readiness. Once preferences and the editor scene are restored,
`contentReady` releases audio preparation and the existing
startup prefetch/open path. Hidden windows remain idle. Explicit-open precedence
and the single-flight audio ownership contract remain unchanged.

The outer content Loader owns scene-removal acknowledgement, including the case
where it was already inactive and never created an item. Close-before-frame and
close-on-first-frame checks preserve the saved song recipe. All three bundled
Atkinson faces must be ready before the window shows; missing fonts or failed
content creation fail visibly in diagnostics rather than displaying fallback
text or leaving a permanently empty application.

`deno task bench:startup` measures monotonic process spawn through the native
render-thread frame marker. It includes the first launch in the strict budget
and labels the result as queued presentation, not physical display scanout.

Measured on macOS arm64 with the Release application, the Hearth project, and
`mus_title`: the previous eager startup's warm median was 485.15 ms. The initial
window-first implementation passed 11/11 ordinary launches below 300 ms: median
248.58 ms, range 223.84–281.03 ms. Its first launch immediately after linking was
370.28 ms and failed the strict budget; this does not establish a cold-start guarantee.
The benchmark reports that first launch rather than silently warming or dropping it.

The minimum-work audit removed the unused system-face lookup, pre-frame Controls
style initialization, and the application's Widgets link dependency. Metal
prewarming and executable-symbol pruning were measured and rejected, not retained
as speculative optimizations.

The final production-bundle smoke verified the same regular, semibold, and mono
Atkinson faces at the first window frame and after song rendering, 115 visible
notes, an advancing playback clock with PCM/CGB activity, stop, and graceful close
after scene removal. The affected check sweep passed: 90 shell lanes, 13 selected
Swift-core groups, two QML lanes, one piano-roll lane, and the bridge guard.

## Further minimum-work audit: file-backed font registration

The bundled faces used to load from compressed qrc data. `QFontDatabase::addApplicationFont`
reads a non-native path into memory, and CoreText then parses it through
`CTFontManagerCreateFontDescriptorsFromData`, with Qt keeping another copy per face.
A native file path goes straight to file-backed registration instead
(`CTFontManagerCreateFontDescriptorsFromURL` on macOS, the file path elsewhere).

The three files now ship beside `PorydawApplication.qml`: in `Contents/Resources` in
the macOS bundle, and in the runtime directory for every other executable, including
check hosts. `BundledFont` resolves them through `Bundle.main`, the same lookup QtBridge
uses for the shell QML. `ShellWindow`'s FontLoaders load them by `file:` URL on every
platform, and `resources/fonts.qrc` was removed. A missing file is a packaging bug, so
`BundledFont` stops the app with `fatalError`. A file that fails to load still fails
the FontLoader check, which exits before any window is shown. Font families,
weights, hinting policy, typography size, and the persistent window are unchanged.

An intermediate macOS-only variant registered the files through process-scoped
`CTFontManagerRegisterFontsForURL` before `QGuiApplication` existed. In a
same-executable, alternating eight-pair experiment, the ordinary first-frame median
was 256.11 ms with qrc registration and 241.69 ms with native pre-Qt registration.
A second alternating run (eight pairs of five-launch batches with each batch's first
launch discarded; 32 warm launches per variant) measured 221.07 ms for native pre-Qt
registration and 216.33 ms for Qt file-path registration. The saving comes from
file-backed registration, not from registering before Qt, so the macOS-only
Objective-C++ path was removed.

The native-variant Release build was then benchmarked immediately after linking, with the
recorded Hearth fixture and `mus_title`. Run 1 took 366.69 ms; the subsequent ten
launches all passed, with median 243.17 ms and range 227.69–253.47 ms. The strict
all-run check correctly failed 1/11 launches. The first-post-link miss remains;
this is not an all-launches-under-300-ms result.

The remaining-cost experiments distinguish reduced work from displaced work:

| Candidate | Observation | Decision |
| --- | --- | --- |
| Minimum Qt window, small executable | After relinking: `main` at 33.73 ms; frame at 234.34 ms | Lower-bound probe, not a replacement application |
| Same minimum window with the complete application image linked | `main` at 130.14 ms; frame at 346.51 ms | Initial load graph matters even without constructing application models |
| Eager shared-library packaging | Relinked `main` at 349.75 ms; frame at 618.35 ms | Rejected; merely repackaging the image worsened the first launch |
| Load the complete image after the first frame | Frame at 235.94 ms, followed by 274.72 ms in library loading | Rejected; moves substantial work behind the window rather than removing it |
| Combined export pruning, dead stripping, and local-symbol removal | Executable shrank from 19.3 MB to 10.6 MB; first frame still 355.88 ms | Rejected; no demonstrated launch-time improvement |
| In-memory CoreText graphics-font registration | Qt failed to resolve the mono face and chose Helvetica | Rejected; violates the first-text font invariant |
| Native AppKit-only window | Useful platform lower bound, but its CPU draw endpoint is not Qt queued presentation | Rejected as an application implementation; does not preserve the existing Qt window contract |

Eager Swift/QML type registration measured about 4.25 ms. The Qt platform still
needs application ownership, screens, input integration, and a real native window.
Changing to plugin-application semantics, stripping native menus, or introducing a
second native window is not an equivalent startup. Earlier Metal prewarming,
render-loop, and ad-hoc-signing experiments did not establish a retained benefit.
Launch-policy activity was observed, but the uninstrumented pre-main interval is
not attributed entirely to one macOS service.

The native-variant production-bundle smoke resolved regular, semibold, and mono
Atkinson faces before the first frame and after `mus_title` opened, all at the
expected 15 px. Actual editor and toolbar captures were inspected. Playback advanced
the audio clock with PCM/CGB activity; stop and scene-removal close completed.
Removing the mono font from an isolated bundle failed before root-window creation.
Its shell sweep failed `shell-event-list-keyboard-selection`
(`test_tickBoundariesThroughMountedEditor`), and a control with the qrc loaders
restored reproduced that failure.

The file-backed version was verified with the Release bundle on the Hearth fixture:
all 64 alternating launches reached a first frame. With the mono file removed from a
copied bundle, startup stopped at `BundledFont`'s `fatalError` before any window was
shown. Native checks passed 37/37, both editor QML lanes passed, the piano-roll lane
passed, and the bridge guard reported zero findings. The shell sweep passed 89/90,
including `shell-event-list-keyboard-selection`. `shell-clipboard`, which uses the
system pasteboard, failed once in the sweep and passed when rerun alone.

## Current 2026-10-05: project indexing before Qt construction

`PorydawShellApp.init` configures the production preferences domain and starts the
project/song read after the help/version exits, before Qt application, engine,
type registration, or window construction. CLI project/song selection still
overrides the saved recipe. The existing concurrent task and dedicated Swift
native-project worker are unchanged.

`StartupSelection` decides once (CLI `--project`/`--song`, else the saved recipe)
and `StartupPrefetch.parked` holds that decision with its read until the first
`ShellPresenter` session adopts it as `prefetchedProject`. `openStartup()` opens
that selection through the ordinary entry points; the project-switch path consumes
the read when the path matches, and a different project or a close before content
mounts retires its service. Audio preparation and visible project adoption still
wait for mounted chrome. `contentReady` no longer schedules a separate prefetch.

`ProjectService` actors run on one private serial queue (`ProjectIOSerialExecutor`)
so the early read no longer competes with MainActor and QML construction for
cooperative-pool threads (warm editor frame 735ms → 617ms).

Startup tracing adds `project-read-start` (scheduled), `project-read-begin`
(off-main execution), and `project-read-end` (read settled, including failure).
These are not window, editor, or audio readiness markers.
