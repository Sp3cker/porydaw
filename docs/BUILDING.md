# Building Porydaw — pipeline, timings, and the parts that must not regress

Measurements below are from a 10-core Apple Silicon machine, Swift 6.4.0, Qt 6.11,
2026-10-05. Treat them as the baseline to beat, and re-measure with the procedure
in [Verifying a build-system change](#verifying-a-build-system-change) before
touching anything in this file's "do not" lists.

## Entry points

```bash
uv run --no-sync dev build:app [--release|--asan]    # app -> build/debug|release|asan
uv run --no-sync dev build:checks [--release|--asan] # app + native checks + mid2agb
uv run --no-sync dev checks ... [--release|--asan]   # native lanes and AOT ratchet
uv run --no-sync dev checks:qml ...                 # drawer; also checks:qml-roll/checks:shell
uv run --no-sync dev checks:qml-aot [--release|--asan]
uv run --no-sync dev checks:backups                 # Foundation-only Swift package tests
```

AGENTS.md § Build & checks is the task index; this file is the pipeline
reference. For `checks:bridge`, `format`, and `setup` see that table.

The commit hook runs `uv run --no-sync dev format --check --staged`. It checks
indexed Swift hunks and Python files using indexed formatter configuration;
unstaged edits and untracked files are excluded. Fix formatting in the working
tree and stage the intended result again; the hook never rewrites the index.

Swift compiler warnings remain visible without being promoted to errors.
This applies to Porydaw and third-party targets, including imported Qt headers
and Debug type-check timing diagnostics.

Popup-menu presenters publish `QListModel<MenuRow>` in `PorydawApp`.
`QuickMenuPanel` consumes typed required scalar roles and a `MenuRow` display handle.
Hosts retain action dispatch and any action-ID-to-object-name mappings.

Text inputs forward raw text to Swift; QML never parses, folds or filters it.
Numeric prompt editing uses `PromptStyle.integerInput`; every style SpinBox
goes through `NumberFieldFormat` (QML's default `NumberFieldFormat {}` shows plain
digits). Integer fields commit only a whole integer after trimming spaces; decimal
fields (Sample Studio rate, cents) accept `[+-]?digits[.digits]`; key fields
accept a MIDI number 0...127 or a note name such as `C#4` (`midiKey(from:)`).
Any other text keeps the current value. Search boxes share `SearchQuery`: every
whitespace-separated word must appear, case- and diacritic-insensitively, in
some searchable field. Menu type-ahead stays prefix-based.

Workflow enums own decisions; QtBridge fields are observable projections, not
second authorities. Sample Studio's stereo/zone decision is separate from its
editor and Loader-release lifetimes. MIDI import distinguishes loading, wizard
editing and registration. Tab close/reload requests carry their target together;
save-conflict requests keep only a weak document identity.

Provision once with `uv sync --locked`, including each new worktree and after lock/project changes. Warm commands use `--no-sync`; no implicit Python dependency resolution. `--help` loads only the command front end. See [INSTALL.md](../INSTALL.md) for native host prerequisites and optional checkout-local Qt provisioning.

On macOS, the runner asks Swiftly for the effective project selection and checks
it against `.swift-version`; Swiftly's global default may differ.

On macOS, native targets use the selected Qt framework's non-system search
path. This keeps an older `/usr/local/include/Qt*` installation from
shadowing Homebrew or checkout-local Qt headers during QML AOT compilation.

Homebrew Qt 6.12's framework export adds Clang's `-idirafter` option.
`cmake/QtBridge.cmake` preserves it for native compilation and forwards it
through `-Xcc` for Swift. App targets snapshot Qt Core's declared include
directories to avoid recursive transitive generator queries emitting a bare `-I`.

Qt 6.12 separates `QMetaObjectBuilder` signal indices from slot/method indices.
The QtBridge patch uses `signal()` to attach NOTIFY signals and translates
finalized slot indices back to builder-local callback indices; Qt 6.12 is the
required floor.

An earlier Homebrew Qt 6.12 smoke reached chrome/workspace frames and passed
`uv run --no-sync dev checks:shell --filter shell-startup`.
The Swift importer emits a `QChar::fromUcs4` cycle warning with both that kit
(`qchar.h:156`) and checkout-local Qt 6.11.2 (`qstringview.h:533`).
Warnings-as-errors previously blocked compilation on this diagnostic;
warnings now remain warnings. Checkout-local provisioning and CI select Qt 6.12.x.

Never call `cmake` or `ninja` directly; `tools/porydaw_dev/cli.py` →
`build.py:run_build` does things a bare `cmake --build` does not:

1. **Configure only when needed** (`needs_configure`): compares cached build type,
   compilers, checks, ASAN, Qt selection and canonical poryaaaa source. Matching
   trees skip explicit configure; Ninja can still regenerate CMake internally.
2. **Reconcile Swift objects** (`reconcile_swift_objects`): Swift's incremental driver
   reuses objects whenever sources are unchanged, even if compile flags changed, so a
   reconfigure that rewrites Swift flags would silently keep stale objects. The runner
   hashes each Swift compile edge's command line into
   `build/<cfg>/.porydaw-swift-commands.json` and deletes the objects of edges whose
   command changed, before and (if a reconfigure happened mid-build) after the build.
3. **Summarize**: only actionable lines are printed; everything is in
   `build/<cfg>/build.log`. Read that log on failure; rebuilding adds no detail.

The Python runner reports environment, poryaaaa, explicit configure, Swift reconcile and Ninja phase wall times. It snapshots Ninja's log before/after each invocation and ranks only new command records, grouped by start/end/hash. Parallel command durations overlap: their sum is not elapsed time or a critical-path calculation. Full details stay in the build log.

Migration smoke on Apple Silicon, Qt 6.11.2, shared QtBridge macro cache: fresh Debug app build 58 s; Release app 92.1 s (explicit configure 8.312 s, Ninja 83.679 s). An observed warm Debug no-op was 0.26 s wall, 0.011 s Ninja. These are single observations, not an A/B comparison against the older table. A native-check build attributed 67.825 s to AudioControllerChecks and 32.079 s to AudioAuditionChecks, exposing the slow consumer commands instead of charging everything to the harness.

Bootstrap observation: uv 0.13.0 ARM64 archive 14,692,549 bytes in 0.778 s; managed Python 3.13.16 download 24.1 MiB; Ruff wheel 8.8 MiB. Default sync installs the project, Ninja and Ruff; the optional Qt group is absent until provisioning needs it. Cached locked offline sync completed in 0.15 s. Qt and the host compiler/SDK remain the larger environment costs; no claim that the complete environment is only the uv archive.

The `Build` and `All checks` workflows run only on pushes to `fork-main`.
Linux artifact builds and ASAN checks run on GitHub-hosted `ubuntu-latest`
runners, installing Qt 6.12 and native dependencies explicitly. ASAN uses a fresh
`build-asan` tree with two build jobs, two Swift threads and check pool four.
It runs Python harness tests before the native sweep, excluding windowing checks
and QML lanes; those run in the GitHub-hosted macOS `All checks` job.
macOS/Windows artifact builds and the standalone Linux harness-test job also
remain GitHub-hosted.
Startup benchmark commands remain available, but their synthetic process and
statistics tests are excluded from the harness suite.

## Vendored VST3 SDK

`external/vst3sdk/` contains the source subset from `steinbergmedia/vst3sdk`
tag `v3.8.1_build_84` (SDK 3.8.1). `VERSION.txt` records the SDK commit, the
tag's exact `base`, `pluginterfaces`, and `public.sdk` submodule commits,
and the `cmake` commit used to compare the hosting source list.
This is an in-tree copy, not a submodule or a configure-time download.

The byte-identical subset is `base/{source,thread}/`,
`pluginterfaces/{base,gui,vst}/`, `public.sdk/source/{common,main,vst}/`,
and `public.sdk/LICENSE.txt`. Every `samples`, `testsuite`, and `test*`
directory is excluded. Copied SDK sources must not be edited.
The SDK's CMake and VSTGUI are not used.

`src/pluginhost/CMakeLists.txt` declares `porydaw_vst3_sdk`, a static C++17
target with an explicit source list based on the pinned
`cmake/modules/SMTG_VST3_SDK.cmake` hosting macro and its base dependencies.
It selects exactly one platform module loader; the macOS loader uses
Objective-C++17 with ARC. Debug uses `DEVELOPMENT=1`; other configurations
use `RELEASE=1` and `NDEBUG`. Project warning flags are not applied to the SDK.
Its include directory is a system include for native helper/check consumers
only: no SDK includes in Swift module maps, and no SDK linkage in Porydaw's
process. The helper owns plugin loading.

The MIT notice in `public.sdk/LICENSE.txt` is copied without changes as
`VST3-SDK-LICENSE.txt`. On macOS it is a `porydaw` bundle resource in
`Contents/Resources/`, using the shell QML/font resource mechanism. Windows
and Linux copy it beside the executable after building. Windows installation
includes it in the staged release folder; Linux AppImage packaging copies it
into `AppDir/usr/bin/` beside the executable.

`PorydawPluginBridge` compiles the SDK-free shared-memory wire format and C11
wait/wake implementation. The helper links the same bridge library plus Qt Gui;
Swift imports its C module without C++ interop or SDK linkage. MSVC enables
`/experimental:c11atomics` on that C target only. C/C++ assertions enforce matching
lock-free atomic sizes, alignment, field offsets and wire size. POSIX backing may
be page-rounded; mappings still expose only the logical wire extent.

`PorydawPluginHost` owns discovery, framed control, capture and live insertion.
Its Swift sources depend on Core, Playback and the SDK-free C bridge, with
no C++ interop. Discovery supervises separate scanner children and keeps usable
cached entries during progressive scans and cancellation.
Setup validity is a request key paired with the invalidation revision captured
before reconfiguration. Interrupted reconfiguration leaves no valid cache;
a restart during setup cannot be erased by that setup's completion.

Each instance lazily launches one helper. One non-Sendable producer owns
request/reply payload access; a separate main-actor mapping monitors atomics and
unlinks the name after `Ready`. An atomic reservation excludes the audio callback
from the dedicated capture worker; detach/join precedes transfer and reclamation.
Control/state operations are async, never main-actor blocking.
Swift owns control, watchdog and shutdown deadlines; native teardown never adds
a competing hang policy. The helper supports both `scan` and `host --channel`.
The native engine owns four phases: unprepared, prepared, active and processing.
The helper reads that authority under processing ownership instead of mirroring
it. Parameter flushing uses one request/acknowledgment flag: the RT thread
publishes its result and restores control ownership before release-clearing it.

Live feedback carries actual dispatches, completed positions and boundaries in
one bounded SPSC ring. Callback-resolved ticks preserve old-timeline endpoints
and silent tails across seeks and adoption; the main-thread drain never estimates
them from a later transport snapshot. Loop input offs precede chase at offset
zero of the first wrapped block, under the new loop context.
Render reports percentage progress per completed bar; only its final result
carries raw notes. No cumulative note-array snapshots cross to MainActor per bar.
Recorder initialization, synchronized baseline and pending restore are explicit
phases; permission, pending edits and cancellation joins remain separate.

Run `uv run --no-sync dev checks --filter swiftcore-pluginbridge` for real-helper
transport, state, crash, hang and shutdown coverage; add `--asan` for sanitizer
coverage. `swiftcore-pluginhost-abi` covers the native engine separately.
Run `uv run --no-sync dev checks --filter swiftcore-pluginhost` for discovery,
capture, lifecycle, live/take and warmed callback-allocation coverage.

The ABI checks verify opaque state restoration through processed MIDI output,
not the test plugin's private legacy state formats. All processing blocks and
repeated instance cycles remain exercised; failures are aggregated with block
or class/iteration context. Scanner JSON decoding checks required fields and
types without requiring nonempty vendor-supplied metadata.

To update the dependency:

1. Check out the new upstream SDK tag cleanly and check out its recorded
   `base`, `pluginterfaces`, `public.sdk`, and `cmake` submodule commits.
2. Re-copy only the directories and license listed above, retaining the
   directory exclusions and removing files no longer present upstream.
   Do not patch copied sources or add a Porydaw submodule.
3. Update `external/vst3sdk/VERSION.txt` with the tag and all recorded commits.
4. Re-check the explicit source list against
   `smtg_create_public_sdk_hosting_target` in the new tag's
   `cmake/modules/SMTG_VST3_SDK.cmake` and its base/common dependencies.
   Name any extra link-required source explicitly and retain its macro
   provenance comment; keep the single platform-loader selection.
5. Run `uv run --no-sync dev build:checks` and
   `uv run --no-sync dev format --check`. Confirm
   `build/debug/porydaw.app/Contents/Resources/VST3-SDK-LICENSE.txt`
   exists on macOS. CI supplies Windows MSVC and Linux compile coverage;
   packaged releases must retain the notice on every platform.

## Standalone backup module

`src/swift/backups` is the `PorydawBackups` Swift 6 package. It depends only on
Foundation. SwiftPM and the application's CMake target compile the same
`MidiBackupStore.swift`; no copied implementation or app test harness is involved.

From the repository, run `uv run --no-sync dev checks:backups`. Outside the app build, run:

```bash
swift test --package-path src/swift/backups
```

The package directory can be used as a local SwiftPM dependency or copied out of
the repository. Import `PorydawBackups` and initialize `MidiBackupStore(root:)`
with an explicit backup directory. Call `preserveOriginal(songName:bytes:at:)`
for initial raw bytes, and `record(songName:bytes:at:)` for subsequent snapshots.
Both are actor-isolated throwing methods. `directory()` creates and returns the
root. Without an explicit root, the existing Porydaw app-data location applies.
Storage treats MIDI as opaque bytes; it does not parse or repair them.

Swift Testing covers real filesystem storage, naming, deduplication, retention,
restart and write failures. Porydaw's `swiftcore-projectsession` lane retains the
document/save integration checks; storage tests do not import its model or Qt.
Run these tests as a regular user: the unreadable-snapshot regression requires
filesystem permissions to deny a read and intentionally fails if root bypasses them.

One-source incremental app-build check on 2026-10-07, Apple Silicon, Debug:

| Storage placement | Warm `build:app` wall time | Swift module rebuilt |
|---|---:|---|
| Before extraction | 1.08 s | PorydawProject, 34 sources |
| Standalone module | 0.59 s | PorydawBackups, 1 source |

Measured once per layout with `touch MidiBackupStore.swift` followed by
the then-current Deno harness under `/usr/bin/time -p`, with no concurrent builds. The logs showed
only the named Swift module rebuilding; this is an unchanged-interface
invalidation measurement, not a clean-build benchmark.

## Lifetime-aware Swift views

`PorydawCore`, `PorydawDocument`, `PorydawApp`, and `PorydawAppAudio` enable
`-enable-experimental-feature Lifetimes` privately with the Swift 6.4 toolchain.
The roll renderer and playback builder use lifetime-bound `Span` views for
synchronous reads; a view cannot outlive its storage owner. Published timelines,
history origins, and retained presenter inputs remain owned snapshots. Borrowing
does not remove legitimate copy-on-write allocations for retained readers.

## Allocation verification

Build Release before profiling (`uv run --no-sync dev build:checks --release`). Compare
identical fixtures and operation counts with Instruments **Allocations**. In its
Statistics export, `All Heap Allocations` → `count-total` and `total-bytes`
include allocations that were later freed. A surviving-object List export
cannot measure allocation churn.

State whether the measurement covers core editing, presenter rendering, or the
whole app, and whether fixture setup and undo/redo are included. Do not divide
whole-process totals into a claimed per-note or steady-state cost.

The MIDI Event List formats and publishes rows only while open. Closing it
unloads the QML page and leaves the last published rows untouched; hidden
document and transport updates do not format or publish rows. Reopening
rebuilds the selected track's mapped MIDI chunk from the current document.
Cover this behavior with `uv run --no-sync dev checks:shell --filter shell-event-list`.
Tab return and background reload are covered by
`uv run --no-sync dev checks:shell --filter shell-tabs-open-select --qt ShellTabs::test_eventListRowsResumeWithTab`.
Compare CPU-profile stacks under keyboard commands separately from loading
and opening the page.

Unchanged bank rebinds skip Voicegroup row derivation. Bank edits, loading and
binding transitions, nil-bind used-mark clears, and catalog callbacks still
refresh rows. Headers, selector, used marks, and editor state update independently.
Bank titles reuse cached `000`–`127` labels and Swift strings instead of printf.
Cover with `uv run --no-sync dev checks --filter swiftcore-projectsession` and
`uv run --no-sync dev checks:shell --filter shell-voicegroup`.

## Where the time goes

Fresh tree = new worktree or new `build/<cfg>` directory.

| scenario (Debug unless noted) | time | what runs |
|---|---|---|
| no-op `build:app` | 0.3 s | glob re-check |
| QML file edit | 2.5 s | qmlcachegen of that file + link |
| C++ file edit | 2.5 s | one object + link |
| Swift edit in `PorydawDocument` (Qt-free) | **~1 s** | module recompiles; unchanged `.swiftmodule` stops the cascade (restat) |
| Swift edit in `PorydawApp` (118 files + `PorydawAppPresentation` 21 files) | **6.4 s** | see [Swift incremental floor](#swift-incremental-floor) |
| fresh worktree, `build:app` | **105 s** (was 166 s) | configure 16 s, QtBridge/C++/QML ~60 s, Swift chain Core→Project→Document→App |
| fresh worktree, `build:app --release` | ~175 s expected (was 348 s) | the 173 s swift-syntax step is gone; not re-measured end to end |
| existing tree after a QtBridge patch change | 125–285 s | plugin rebuild (if the key is new) + every Swift module recompiles |

The two numbers that used to dominate — 134 s (Debug) / 173 s (Release) of
swift-syntax compilation per build tree plus a GitHub clone — are now paid once per
machine. That is the mechanism described next.

Core checks are three modules. `SwiftCoreCheckSupport` (fixtures, `CheckReport`)
and `SwiftCoreCheckLogic` (checks that need no `PorydawApp`) compile without C++
interop and build beside the app chain. `SwiftCoreCheck` holds the app-facing
checks and `pdc_suite_run`; it imports `SwiftCoreCheckLogic` only in files that use
it, so a Logic declaration edit recompiles those files, not the module. A check that
needs no `PorydawApp`/QtBridge type belongs in Logic: interop costs ~0.4–0.6 s per
module compile plus lazy C++ lookups (`PorydawAppAudio` 760 → 360 ms when dropped).

Linux ASAN CI compiles `SwiftCoreCheckLogic` with optimized incremental batches,
preserving `-O`, debug information, and the Swift/C parity timing gate. Product
modules remain whole-module optimized. `CMAKE_Swift_NUM_THREADS` limits Swift
driver parallelism; Ninja's `-j` does not limit frontends within a Swift build
edge. Configure both limits explicitly to avoid nested oversubscription.

Pre-uv `build:checks` wall time, Debug, before (six chained interop lanes,
support → media → edit → roll → pages → project → dispatcher) and after:

| scenario | before | after |
|---|---|---|
| public API added in `PorydawCore` | 27.9 s | 18.8–20.4 s |
| internal declaration added in `PorydawApp` | 23.2 s | 15.2 s |
| every core-check source touched | 13.3 s | 7.1–7.8 s |
| declaration added in a Logic check file | 7.4 s | 3.6 s |
| declaration added in a `SwiftCoreCheck` file | — | 2.5 s |
| body-only edit in a Logic check file | — | 1.2 s |

A single file copying a large C struct (`LoadedVoiceGroup`) by value cost 57 s
in the `SendNonSendable` SIL pass — access such structs through the pointer
(see `VoicegroupLoaderChecks.loaderSameVoiceNames`).

## CI

`.github/workflows/build.yml` and `release.yml` call `cmake` directly (sccache,
`cmake --install`); that is the only permitted direct caller.

The `QtKeybindings` Clang module names only the project-owned bridge header.
That header includes Qt through the `Qt6::Gui` target's normal header/framework
search paths; do not name a kit's forwarding headers directly in the module map.

Actions uploads expire after one day. Artifact retention runs hourly, manually, and
after Build, All checks, or Release completes; it keeps unfinished runs and the
newest successful run with unexpired artifacts per workflow, deleting older or
failed completed-run artifacts. GitHub Releases and workflow logs are unaffected.

## Shared QtBridge macro plugin (`~/.cache/porydaw`)

QtBridge's `@QtBridgeable` macros run in a host plugin (`QtBridgeMacros`) compiled from
swift-syntax by an `ExternalProject` inside the fetched QtBridge source. The plugin's
inputs are exactly: the QtBridge git pin, `cmake/patches/qtbridge/*`, the Swift
compiler path and version, and configuration-independent `CMAKE_Swift_FLAGS`. So:

- `cmake/QtBridge.cmake` hashes those inputs into a 16-hex key and sets
  `QTBRIDGE_MACROS_CACHE_DIR = ${PORYDAW_BUILD_CACHE}/qtbridge-macros/<key>`.
  `PORYDAW_BUILD_CACHE` defaults to `~/.cache/porydaw`
  (`%LOCALAPPDATA%\porydaw\build-cache` on Windows); the environment variable seeds
  the CMake cache variable on first configure. `OFF` keeps the plugin in the tree.
- The patched QtBridge `CMakeLists.txt` (hunk in `cmake/patches/qtbridge/qtbridge.patch`)
  points the ExternalProject's `PREFIX`/`BINARY_DIR` at that directory and **copies the
  macro sources beside it** (`configure_file(... COPYONLY)`, which rewrites only on
  content change). The copy exists because an ExternalProject's `SOURCE_DIR` is baked
  into its CMake cache: every tree sharing the build must present the same source path.
- Configure and build steps run through `Sources/QtBridgeMacros/LockedStep.cmake`
  under `file(LOCK <dir> DIRECTORY)`, so two trees first-building the same key
  serialize instead of driving one Ninja directory concurrently. The step's argument
  list travels as a `|`-joined `-DSTEP_COMMAND` (semicolons do not survive
  ExternalProject's command plumbing).
- A tree that joins an existing key still runs the inner configure once (~3 s, "ninja:
  no work to do") because its own Ninja log has no record of the stamp edges.
- The plugin is always built `Release` regardless of the host configuration: an
  unoptimized swift-syntax made macro expansion dominate every Debug Swift compile
  (PorydawApp emit-module 20 s → 7.5 s).

Expected log lines on a cache hit (`build/<cfg>/build.log`):

```
[..] Performing build step for 'QtBridgeMacros_External'
ninja: Entering directory `/Users/<you>/.cache/porydaw/qtbridge-macros/<key>/build'
ninja: no work to do.
```

Do not:

- move `QTBRIDGE_MACROS_EP_ROOT` back under `CMAKE_BINARY_DIR`, or add per-tree
  values (build type, `CMAKE_BINARY_DIR`, timestamps) to the key — either reintroduces
  the per-tree 3-minute build;
- drop the `FORCE` on `QTBRIDGE_MACROS_BINARY_DIR` / `QTBRIDGE_MACROS_PLUGIN_PATH`:
  the keyed directory moves when inputs change and a stale cache entry would load the
  previous plugin silently;
- remove the lock or run the inner build outside `LockedStep.cmake`;
- set `-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}` for the plugin again.

Editing the patch: modify the fetched copy under `build/debug/_deps/qtbridge-src`,
`git add -N` any new files there, then `git -C build/debug/_deps/qtbridge-src diff >
cmake/patches/qtbridge/qtbridge.patch`. The three `new file` sections already in the
patch (`QmlColor.swift`, `QmlFont.swift`, `qmlvaluetypes.h`) must stay intent-to-add
or they vanish from the regenerated diff. Any patch change rotates the key: one
3-minute plugin build on the next configure, then every Swift module recompiles
(`-DQTBRIDGE_PATCH_<digest>` is on every consumer's command line on purpose).

Reset: `rm -rf ~/.cache/porydaw` — the next build rebuilds the plugin once.

## `PorydawApp.qmltypes` (Swift types visible to QML)

`porydaw_qmltypes` (`src/swift/qmltypes/main.swift`) walks the registered Swift
presenters' meta-objects and writes `build/<cfg>/qmltypes/PorydawApp/PorydawApp.qmltypes`,
which qmlcachegen uses to compile every production QML file. Two properties are
load-bearing:

1. **It writes the file only when the content changes.** Every `_qml.cpp` depends on
   it; an unconditional write recompiled every QML cache unit (87 in porydaw_app alone) after every Swift edit.
   The custom command is `restat`-ed by CMake, so an unchanged file stops the cascade.
2. **Methods are emitted in meta-object order, never sorted.** qmlcachegen bakes
   relative method indices from the manifest for plugin-less modules. A sorted manifest
   builds and links fine and then crashes the Release app at startup in
   `QMetaObject::method(int)` (SIGSEGV right after `presenter-end`). Debug trees can
   mask it.

A Swift edit that changes the QML-facing surface (new `@QtTracked`/signal/slot) is the
one legitimate trigger for the QML cascade; expect 30–60 s.

## QML AOT statistics and the ratchet

`tools/porydaw_dev/qml_aot.py` reads `build/<cfg>/.rcc/qmlcache/module_*.aotstats` and compares
per-file qmlsc rejection counts against `tools/qml_aot_baseline.json`. Qt only writes
those files for the `all_aotstats` target, which is not part of `all`; the `checks`
lane and `checks:qml-aot` therefore build it explicitly. Qt's own aggregate
`all_aotstats.aotstats` repeats every module and is ignored by name. "Missing or empty
AOT statistics" means something built `porydaw` without `all_aotstats`.

When QML or exposed Swift types change legitimately: `uv run --no-sync dev qml-aot:baseline`,
then review the baseline diff — rejections should
be explainable. Keep component references and QObject return values explicitly
typed where qmlsc needs them: `EventListPage` casts its child `page` bindings and
row handles, compiling 116/123 entries on Qt 6.11 without a baseline update.

To see one file's rejections without a build, run
`uv run --no-sync dev qml-aot:file <src/ui/...qml>`: it reruns the build's own qmlcachegen
command for that file into a scratch directory. qmllint's compiler warnings are a separate
analysis and disagree with qmlcachegen; never use them as the AOT measure. Cross-file QML
type changes show only after the next build refreshes the type registry.

AOT statistics do not validate runtime component loading or behavior. After AOT
edits, run `checks`, `checks:shell`, `checks:qml`, `checks:qml-roll`, and
`checks:bridge`, then record `checks:qml-aot`. Keep `Qt.callLater`, parsing,
TableView positioning, and Fusion color semantics intact; a lower rejection count
does not justify replacing them with approximate implementations. Delegate `model`
is a role wrapper, not the typed QObject exposed by its `display` role, and role
properties must not override inherited final control properties.

## Swift incremental floor

`PorydawApp` is 118 files plus `PorydawAppPresentation` at 21 files, with C++
interop (Qt headers). A one-file edit measures 6.4 s (emit-module 6.1 s, was
9.2/7.2 s before the split). The emit-module job type-checks every declaration
in the module plus the imported Clang decls, and pays a per-process ~1 s lazy Qt
C++ decl import on the first `==`/`String.init` overload resolution. Debug builds
warn (never fail) past 2000 ms per body and 50 ms per expression; interop modules and
their importers warn at 1000 ms per expression because lazy C++ import lands on
expressions (see `.omp/rules/swift-typecheck-complexity.md`).
`-incremental -enable-batch-mode` are already on (Debug). Only moving code out of
`PorydawApp` into smaller modules lowers the floor further; `PorydawDocument`
(Qt-free, no interop) shows the payoff at ~1 s per edit with no downstream rebuild
when the interface is unchanged.

`PorydawPluginHost` isolates the new SDK-free hosting behavior from the app module.
Task 7 measured the same warm Debug app probe before and after adding its runtime,
before the later off-main audio integration:

| Hosting runtime | `build:app` samples (s) | Median (s) |
|---|---|---:|
| Before task 7 | 7.5, 7.5, 7.5 | 7.5 |
| After task 7 | 8.3, 7.5, 7.9 | 7.9 |

Each sample touched `src/swift/app/shell/ShellPresenter.swift` then ran
`uv run --no-sync dev build:app`, without concurrent builds or indexing.
These are harness-reported build times; median Ninja phases were 7.335 s and
7.689 s. The app edit floor did not improve; the boundary provides isolation,
not a measured app-compilation speedup.

`PorydawAppHistory` owns the history presenter and retained row type; `PorydawApp`
only supplies session context and shell callbacks. Replay and labels stay in
Document/Core. A history-only edit rebuilds the two-source leaf, not the app module.
The QML shell uses its horizontal `SplitView` to resize history from the pane's
left divider. The chosen width survives hide/show within the current window;
it is not a saved preference.

| History presenter placement | Warm build samples (s) | Median (s) |
|---|---|---:|
| `PorydawApp` | 7.40, 6.75, 7.11 | 7.11 |
| `PorydawAppHistory` | 1.16, 1.15, 1.15 | 1.15 |

Measured 2026-10-08 on Apple Silicon, Debug, with no concurrent builds: each sample
ran `touch src/swift/app/history/UndoHistoryPanel.swift` then
timed an app build through the pre-uv harness. This measures interface-preserving
recompilation; public-interface changes can still rebuild downstream modules.

`PorydawVoicegroup` (`src/swift/voicegroup/`, 20 files, 4.6k lines, no Swift
dependencies, C interop only via `voicegroup_asset_batch.h`) was split out of
`PorydawProject` (33 → 21 files). Measured on the same semantic one-file edit in
`VoicegroupSource.swift`: body-only edit 2.1 s → 1.9 s; declaration-adding edit
18.2 s → 19.5 s (the `.swiftmodule` changes, so Project → Document →
AppPresentation → App still recompile). The split pays for itself through
isolation and the benchmark below, not the floor.

`PorydawSampleUI` (`src/swift/sampleui/`) holds the sample library model and the PCM
audition player shared by Sample Studio and Split Studio. It sits on Sample, AppAudio,
AppPresentation and QtBridge; `PorydawApp` links it.

| `SampleLibraryModel.swift` placement | Warm build samples (s) | Median (s) |
|---|---|---:|
| `PorydawApp` | 7.77, 7.72 | 7.75 |
| `PorydawSampleUI` | 1.54, 1.52 | 1.53 |

Measured 2026-10-13, Debug, `touch` then `uv run --no-sync dev build:app`. A
one-file `PorydawApp` edit (`SampleStudioPresenter.swift`) measured 7.00/6.91 s afterward.

`PorydawKitStudio` (`src/swift/kitstudio/`) owns Split Studio's kit draft, codec,
source session and presenter on Sample, SampleUI, Voicegroup, AppAudio and QtBridge.
A `KitDraft.swift` edit measured 0.42/0.42 s, against 6.52 s for the same-day
one-file `PorydawApp` edit it would otherwise cost.

Swift incremental state is mtime-based: `touch`, `git checkout` across branches, or
`git stash pop` recompile whole modules even when content is identical. Changing a
module's compile flags (including via `-D` defines) drops its objects (see
`reconcile_swift_objects`), which is intended.

## Audio execution and sample previews

Main owns intent, presentation and preview arbitration. `AudioControl` is an actor
on a dedicated serial queue; it owns the device, renderer and project bank lease.
Device preparation starts off main; the first rendering command starts the device.
The audio callback does the realtime work. `AudioStatus` exposes atomic scalar
state, including requested and applied transport, settings, positions and telemetry generation.

Bind, unload, settings, voicegroup and pattern start/stop return awaitable
`AudioOperation` receipts. Hot transport and preview commands write lifetime-stable
endpoints directly when main owns the producer. While a cold receipt or queued hot
write is outstanding, they use control's FIFO; main acquires the final queued write
before resuming direct production. Start readiness and producer ownership are
cached only across this explicit handover, not inferred from callback state.
Cold operations never stop the device: control closes a callback gate, waits out
at most the block in flight, and applies the change; blocks arriving meanwhile render silence.
One main-actor task consumes completions, sample events and telemetry. Control
drains CPU frames and activity peaks; main coalesces delivered batches. Telemetry
epochs and generations discard late batches after invalidation.

VST Live attachment uses the same cold FIFO and receipts. Commands carry a retained
`LiveInsert` owner; control installs its borrowed slot under callback exclusion.
Detach matches exact owner identity, so late cleanup cannot remove a successor,
and clears notes, take state and the slot before acknowledging. Host awaits that
receipt before transferring the bridge producer to Render or reclaiming storage.
Main never dereferences the slot. The dedicated control executor uses portable
`DispatchQueue`/`SerialExecutor`, including queue isolation checks for direct submits.

Render timeouts return typed data to the MainActor helper owner, which records
stopped-responding before terminating the process; later EOF cannot replace the
first cause. The armed 50 ms take/watchdog drain never awaits helper IPC.
Digest polling coalesces into one owned task per instance and is awaited during
cleanup, independently of that drain.

`NativeAudio.beginSampleAudition` claims a main-actor `SampleAuditionLease`; a new
lease displaces the old holder. Leases submit value notes (PCM, wave or kit) to
control, which prepares and reuses PCM and kit assets, retries busy slots and
reclaims retired storage. Callback progress signals a semaphore-backed waiter;
unchanged notes and retired idle slots do not wake control. Callback feedback
identifies adoption and natural completion: `.started` means adopted, `.finished`
means ended, and `soundingFrame` reports the current note's callback-published
position. Lease and note identities reject stale events.

`PcmAuditionPlayer` moves through idle, starting, sounding and repeat-gap states.
Its policies are `.once` for library previews, `.repeatSame` for Split Studio
slices and `.repeatFresh` for Sample Studio; repeating waits 0.5 seconds after
completion. Its playhead reads `soundingFrame`, not an estimated playback clock.

Studio DSP runs off main as latest-work-wins jobs (edit renders, loop tools, slice
and key renders, save renders, Split Studio source decoding); stale results are rejected.
Sample Studio publishes waveform state and republishes an active audition from
the same landed render revision in one main-actor turn. Split Studio rerenders the
active slice on boundary edits and republishes it with its playhead mapping; a key
audition whose draft revision changed never sounds. Both map the engine's
actual sounding frame onto their waveform.

The shell close barrier awaits audio shutdown. Control joins the device and tears
it down while retaining the bank lease; project retirement waits for queued audio
unload. This does not guarantee off-main bank destruction: `Bank.deinit` may still
free memory on main.

## Voicegroup loading: parity and performance gate

Voicegroups are parsed, resolved and assembled in Swift (`PorydawVoicegroup`);
C keeps only the byte-span sample decoders and the engine. `uv run --no-sync dev checks
--filter projectstore-parity` loads every hub voicegroup through the reference
C loader and the Swift `BankBuilder` and asserts byte-identical banks (tones,
names, keysplit tables, sub-banks, decoded sample bytes). Set
`PORYDAW_PARITY_PROJECT_ROOT=<decomp project>` to sweep a real project.

`uv run --no-sync dev checks --filter projectstore-locator` also covers legacy
numeric declarations such as `voicegroup017::` in independently named files,
with LF and CRLF input, through a real `VoicegroupStore` bank load. Directory
fallback resolves these labels even when the file has no `voice_group` macro
and does not qualify as a multi-bank monolithic source.

The parity check gates performance per target on the warm (second) load:
Swift malloc calls ≤ C, Swift live blocks ≤ C + 1 + sub-bank count (one Swift
instance each), and, on optimized builds only, total load time ≤ C. Debug
builds print times but assert only allocations. Release, warm,
pokeemerald-expansion (274 voicegroups): C 342.7 ms / 54,840 mallocs, Swift
158.7 ms / 41,116; fixture (7): C 0.55 ms / 246, Swift 0.47 ms / 102.

Every `Unsafe*` site in the module was A/B'd against a `Span`/`MutableSpan`/
`InlineArray`/`ParserSpan` variant on that sweep (5 alternating rounds,
medians); the safe variant ships unless it is more than 25 % slower. Thirteen of
fourteen sites are safe; the one exception is the sample picker's bulk PCM copy
(`Array(UnsafeBufferPointer)` vs `OutputSpan` append: 369 ms vs 661 ms). The
C-boundary handoffs (`ToneData*` to `m4a_engine_set_voicegroup`, decoder
outputs, `free`, POSIX syscalls) are exempt and marked in code.

Split Studio's existing-kit edit path reads one `KitEditValue` and passes it to
`KitEditLoader` for asset resolution; that same snapshot remains the save
expectation. Do not re-read the kit while preparing its draft. Exercise drumkit
and keysplit edit/save flows with
`uv run --no-sync dev checks:shell --release --filter shell-edit-in-studio`.

## Verifying a build-system change

1. Idle machine. Builds and benchmarks taken during or right after another build are
   30–80 % slower and not comparable.
2. Fresh-tree time: `uv run --no-sync dev worktree:create <name> --base <branch>` from the main
   checkout, then `uv sync --locked` and `time uv run --no-sync dev build:app` inside it, then
   `git worktree remove --force .worktrees/<name> && git branch -D feature/<name>`.
   Check `build/debug/build.log` for the cache-hit lines above.
3. Incremental time: append `// bench` to a file, `time uv run --no-sync dev build:app`, restore,
   build again. Compare against the table.
4. Rank commands with the runner's slowest-new-commands line and compare its phase
   wall times. Do not sum overlapping Ninja durations or rank the entire historical log.
5. Gates: `uv run --no-sync dev checks`, `uv run --no-sync dev checks:shell`,
   `uv run --no-sync dev checks:qml-aot`
   all green before merging anything in `cmake/`, `tools/`, or the QtBridge patch.

## Startup benchmarking

`uv run --no-sync dev build:app --release && uv run --no-sync dev bench:startup --until editor-frame` measures
spawn → native frame on the saved-session path. Serial runs of two binaries are not
comparable (see point 1 above): copy the baseline bundle outside `build/` before
rebuilding and use `uv run --no-sync dev bench:startup:ab --until editor-frame --stages
old=<baseline exe> new=<exe>`, which alternates launches and prints per-stage
medians. Known reference points (idle machine, warm, Release, restore path):
first-frame ≈ 250 ms, workspace-frame ≈ 440 ms, editor-frame ≈ 560 ms; under a
load average of 8+ the same binary reads ≈ 650 ms. Stage timestamps are printed
on stderr with `PORYDAW_STARTUP_TRACE=1`.
