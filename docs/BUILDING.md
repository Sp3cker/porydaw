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
deno task checks:backups                 # Foundation-only Swift package tests; no app/Qt build
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

## Standalone backup module

`src/swift/backups` is the `PorydawBackups` Swift 6 package. It depends only on
Foundation. SwiftPM and the application's CMake target compile the same
`MidiBackupStore.swift`; no copied implementation or app test harness is involved.

From the repository, run `deno task checks:backups`. Outside the app build, run:

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
`/usr/bin/time -p deno task build:app`, with no concurrent builds. The logs showed
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

Build Release before profiling (`deno task build:checks --release`). Compare
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
Cover this behavior with `deno task checks:shell --filter shell-event-list`.
Tab return and background reload are covered by
`deno task checks:shell --filter shell-tabs-open-select --qt ShellTabs::test_eventListRowsResumeWithTab`.
Compare CPU-profile stacks under keyboard commands separately from loading
and opening the page.

Unchanged bank rebinds skip Voicegroup row derivation. Bank edits, loading and
binding transitions, nil-bind used-mark clears, and catalog callbacks still
refresh rows. Headers, selector, used marks, and editor state update independently.
Bank titles reuse cached `000`–`127` labels and Swift strings instead of printf.
Cover with `deno task checks --filter swiftcore-projectsession` and
`deno task checks:shell --filter shell-voicegroup`.

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

`deno task build:checks` wall time, Debug, before (six chained interop lanes,
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
be explainable. Keep component references and QObject return values explicitly
typed where qmlsc needs them: `EventListPage` casts its child `page` bindings and
row handles, compiling 116/123 entries on Qt 6.11 without a baseline update.

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
`/usr/bin/time -p deno task build:app`. This measures interface-preserving
recompilation; public-interface changes can still rebuild downstream modules.

`PorydawVoicegroup` (`src/swift/voicegroup/`, 20 files, 4.6k lines, no Swift
dependencies, C interop only via `voicegroup_asset_batch.h`) was split out of
`PorydawProject` (33 → 21 files). Measured on the same semantic one-file edit in
`VoicegroupSource.swift`: body-only edit 2.1 s → 1.9 s; declaration-adding edit
18.2 s → 19.5 s (the `.swiftmodule` changes, so Project → Document →
AppPresentation → App still recompile). The split pays for itself through
isolation and the benchmark below, not the floor.

Swift incremental state is mtime-based: `touch`, `git checkout` across branches, or
`git stash pop` recompile whole modules even when content is identical. Changing a
module's compile flags (including via `-D` defines) drops its objects (see
`reconcileSwiftObjects`), which is intended.

## Voicegroup loading: parity and performance gate

Voicegroups are parsed, resolved and assembled in Swift (`PorydawVoicegroup`);
C keeps only the byte-span sample decoders and the engine. `deno task checks
--filter projectstore-parity` loads every hub voicegroup through the reference
C loader and the Swift `BankBuilder` and asserts byte-identical banks (tones,
names, keysplit tables, sub-banks, decoded sample bytes). Set
`PORYDAW_PARITY_PROJECT_ROOT=<decomp project>` to sweep a real project.

The same check gates performance per target on the warm (second) load:
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
