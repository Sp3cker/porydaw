# Building Porydaw — pipeline, timings, and the parts that must not regress

Measurements below are from a 10-core Apple Silicon machine, Swift 6.4.0, Qt 6.11,
2026-10-05. Treat them as the baseline to beat, and re-measure with the procedure
in [Verifying a build-system change](#verifying-a-build-system-change) before
touching anything in this file's "do not" lists.

## Entry points

```bash
deno task build:app   [--release|--asan]   # porydaw only            -> build/debug|release|asan
deno task build:checks [--release|--asan]  # porydaw + porydaw_checks + mid2agb
deno task checks ... [--asan]              # builds porydaw_checks, mid2agb, all_aotstats, then runs
deno task checks:qml ... [--asan]          # editor drawer QML lane (same flags for checks:qml-roll, checks:shell)
deno task checks:qml-aot [--release|--asan] # builds porydaw + all_aotstats, then the AOT ratchet
```

AGENTS.md § Build & checks is the task index; this file is the pipeline
reference. For `checks:bridge`, `format`, and `setup` see that table.

Never call `cmake` or `ninja` directly; `tools/cli.ts` → `tools/build.ts:runBuild` does
things a bare `cmake --build` does not:

1. **Configure only when needed** (`configure()`): compares the cache's build type,
   compilers, `PORYDAW_BUILD_CHECKS`, ASAN, and the poryaaaa submodule revision; a
   matching tree skips CMake entirely (no-op build: ~0.3 s).
2. **Reconcile Swift objects** (`reconcileSwiftObjects()`): Swift's incremental driver
   reuses objects whenever sources are unchanged, even if compile flags changed, so a
   reconfigure that rewrites Swift flags would silently keep stale objects. The runner
   hashes each Swift compile edge's command line into
   `build/<cfg>/.porydaw-swift-commands.json` and deletes the objects of edges whose
   command changed, before and (if a reconfigure happened mid-build) after the build.
3. **Summarize**: only actionable lines are printed; everything is in
   `build/<cfg>/build.log`. Read that log on failure; rebuilding adds no detail.

## Lifetime-aware Swift views

`PorydawCore`, `PorydawDocument`, `PorydawApp`, and `PorydawAppAudio` enable
`-enable-experimental-feature Lifetimes` privately with the Swift 6.4 toolchain.
The roll renderer and playback builder use lifetime-bound `Span` views for
synchronous reads; a view cannot outlive its storage owner. Published timelines,
history origins, and retained presenter inputs remain owned snapshots. Borrowing
does not remove legitimate copy-on-write allocations for retained readers.

## Allocation verification

Build Release before profiling (`deno task build:checks --release`). Compare
identical fixtures and operation counts with Instruments **Allocations**. In its
Statistics export, `All Heap Allocations` → `count-total` and `total-bytes`
include allocations that were later freed. A surviving-object List export
cannot measure allocation churn.

State whether the measurement covers core editing, presenter rendering, or the
whole app, and whether fixture setup and undo/redo are included. Do not divide
whole-process totals into a claimed per-note or steady-state cost.

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

`swift_core_check` is six chained lanes (support/media/edit/roll/pages/project).
A single file copying a large C struct (`LoadedVoiceGroup`) by value cost 57 s
in the `SendNonSendable` SIL pass — access such structs through the pointer
(see `VoicegroupLoaderChecks.loaderSameVoiceNames`).

## CI

`.github/workflows/build.yml` and `release.yml` call `cmake` directly (sccache,
`cmake --install`); that is the only permitted direct caller.

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

`tools/qml_aot.ts` reads `build/<cfg>/.rcc/qmlcache/module_*.aotstats` and compares
per-file qmlsc rejection counts against `tools/qml_aot_baseline.json`. Qt only writes
those files for the `all_aotstats` target, which is not part of `all`; the `checks`
lane and `checks:qml-aot` therefore build it explicitly. Qt's own aggregate
`all_aotstats.aotstats` repeats every module and is ignored by name. "Missing or empty
AOT statistics" means something built `porydaw` without `all_aotstats`.

When QML or exposed Swift types change legitimately: `deno task qml-aot:baseline`
(the only task permitted to write `tools/`), then review the diff — rejections should
be explainable (e.g. `page: parent` self-references qmlsc cannot type).

## Swift incremental floor

`PorydawApp` is 118 files plus `PorydawAppPresentation` at 21 files, with C++
interop (Qt headers). A one-file edit measures 6.4 s (emit-module 6.1 s, was
9.2/7.2 s before the split). The emit-module job type-checks every declaration
in the module plus the imported Clang decls, and pays a per-process ~1 s lazy Qt
C++ decl import on the first `==`/`String.init` overload resolution. Type-check
budgets of 2000 ms per body / 1000 ms per expression warn (never fail) in Debug.
`-incremental -enable-batch-mode` are already on (Debug). Only moving code out of
`PorydawApp` into smaller modules lowers the floor further; `PorydawDocument`
(Qt-free, no interop) shows the payoff at ~1 s per edit with no downstream rebuild
when the interface is unchanged.

Swift incremental state is mtime-based: `touch`, `git checkout` across branches, or
`git stash pop` recompile whole modules even when content is identical. Changing a
module's compile flags (including via `-D` defines) drops its objects (see
`reconcileSwiftObjects`), which is intended.

## Verifying a build-system change

1. Idle machine. Builds and benchmarks taken during or right after another build are
   30–80 % slower and not comparable.
2. Fresh-tree time: `deno task worktree:create -- <name> --base <branch>` from the main
   checkout, then `time deno task build:app` inside it, then
   `git worktree remove --force .worktrees/<name> && git branch -D feature/<name>`.
   Check `build/debug/build.log` for the cache-hit lines above.
3. Incremental time: append `// bench` to a file, `time deno task build:app`, revert,
   build again. Compare against the table.
4. Rank edges when something is slow:
   `awk 'NR>1 && NF>=4 {print $2-$1"\t"$1"\t"$2"\t"$4}' build/debug/.ninja_log | sort -rn | head`
   (the log spans several builds; the start/end columns disambiguate).
5. Gates: `deno task checks`, `deno task checks:shell`, `deno task checks:qml-aot`
   all green before merging anything in `cmake/`, `tools/`, or the QtBridge patch.

## Startup benchmarking

`deno task build:app --release && deno task bench:startup --until editor-frame` measures
spawn → native frame on the saved-session path. Serial runs of two binaries are not
comparable (see point 1 above): copy the baseline bundle outside `build/` before
rebuilding and use `deno task bench:startup:ab --until editor-frame --stages
old=<baseline exe> new=<exe>`, which alternates launches and prints per-stage
medians. Known reference points (idle machine, warm, Release, restore path):
first-frame ≈ 250 ms, workspace-frame ≈ 440 ms, editor-frame ≈ 560 ms; under a
load average of 8+ the same binary reads ≈ 650 ms. Stage timestamps are printed
on stderr with `PORYDAW_STARTUP_TRACE=1`.
