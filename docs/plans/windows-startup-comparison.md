# Windows handoff: pocketed startup sequence A/B

## Goal and decision ownership

Measure the additional effect of the pocketed workspace-loading sequence on
Windows. The receiving agent owns the keep/reject decision. Time to an editable
restored song is the primary endpoint; first-frame and chrome regressions must
also be reported. Earlier workspace construction alone is not a win.

Do not port the macOS keep decision blindly. Both variants retain the same font
prewarm, lazy WAV windows, truthful editor endpoint, project/audio adoption order,
and canonical dependency resolver. Do not revive dense incubation or viewport
coalescing, add early audio adoption, or change the workload while comparing.

Windows commands below are source-checked, not executed on Windows by the author.

## Published variants

Repository: `https://github.com/Sp3cker/porydaw.git`

Branch: `feature/startup-avenues-v7`

| Variant | Exact revision | Behavior |
| --- | --- | --- |
| WITHOUT pocketed sequence | `cb17b70d2af9679bef3df9ec94ebb7bb04b34963` | Retained font prewarm + lazy WAV dialogs; asynchronous workspace |
| WITH pocketed sequence | `7966b9df1081a5d6af3946a57c89b175f833c2d5` | Same baseline plus content-ready-before-synchronous-workspace sequence |

The WITH commit's parent is the WITHOUT commit. Its complete diff is only:

- `src/ui/shell/ShellWindow.qml`: outer content Loader's `onLoaded` calls
  `shell.contentReady()` and then `item.loadWorkspace()`.
- `src/ui/shell/ShellContent.qml`: `loadWorkspace()` owns the existing `setSource`
  arguments; workspace Loader is synchronous; its old `Component.onCompleted`
  construction call is removed.
- `README.md`: describes that sequence.

The branch tip also contains this handoff, a documentation-only commit. Use the
exact code revisions above, not `fork-main` or a moving `swift-qml-grid` baseline.

## Preparation

Use an isolated, clean clone for this experiment, or the repository's worktree
creator when an existing checkout must be preserved. Do not reset/stash another
agent's WIP or replace a dirty dependency. This example assumes a clean dedicated
clone and an x64 MSVC Developer PowerShell with Deno and Swift available:

```powershell
git clone --branch feature/startup-avenues-v7 https://github.com/Sp3cker/porydaw.git porydaw-windows-startup
Set-Location porydaw-windows-startup
$repo = (Get-Location).Path
$without = 'cb17b70d2af9679bef3df9ec94ebb7bb04b34963'
$with = '7966b9df1081a5d6af3946a57c89b175f833c2d5'
$handoffTip = (git rev-parse HEAD).Trim()
git submodule sync -- external/poryaaaa
git submodule update --init --recursive external/poryaaaa
```

Requirements:

- Windows x86_64; MSVC Qt `msvc2022_64`, not a MinGW Qt kit.
- Swift version pinned by `.swift-version`: **6.4.0**. Preserve the Swift
  toolchain/runtime directories supplied by the existing Developer PowerShell.
- Qt **6.11**, the same actual patch release and kit for both builds. The build
  task discovers repository-managed Qt under
  `.cache/setup/qt/windows-win64_msvc2022_64/<version>/msvc2022_64`; an existing
  configured build records the selected kit in `Qt6_DIR` in its `CMakeCache.txt`.
- Canonical SDK HEAD and parent indexed gitlink both
  **`c504afebe5c56cf9393e6ae632b9cef632480ab6`**, clean. In a linked worktree, the
  resolver uses the main checkout's physical `external/poryaaaa/packages/poryaaaa`,
  not a nested worktree clone. Do not substitute another SDK to make a build pass.

Resolve `$qt` to the actual selected MSVC kit using that installation/cache before
running the following environment setup. Do not infer a kit from a DLL error:

```powershell
$env:Path = "$qt\bin;" + $env:Path
$env:QT_PLUGIN_PATH = "$qt\plugins"
$env:QML2_IMPORT_PATH = "$qt\qml"
```

Set these in the SAME PowerShell process that builds, runs checks and launches.
A `Qt6*.dll`/`vcruntime140*.dll` popup or immediate `0xc0000602` is a loader/setup
failure, not a startup-time sample or application regression. If Swift, the
configured generator or another platform prerequisite fails, preserve the exact
build errors/log and resolve the actual prerequisite before timing. Do not add
fallbacks or change application behavior to obtain numbers. Build/check tool
calls must have a timeout no greater than 180 seconds; inspect `build/<config>/build.log`
on failure rather than rebuilding merely to reprint it. Use `deno task`, never
invoke CMake/Ninja directly.

## Build both once, retain binaries in the same runtime directory

Both build tasks use the same tree and dependency. No build, test, index or format
job may run concurrently with timing. Check `$LASTEXITCODE` after every external
command; do not keep going after a failed build.

```powershell
git switch --detach $without
deno task build:app --release
# Visual Studio multi-config output; for an already configured single-config
# tree use build\release\porydaw.exe instead. The benchmark prints its resolved path.
$exe = Join-Path $repo 'build\release\Release\porydaw.exe'
Copy-Item $exe (Join-Path (Split-Path $exe) 'porydaw-without-pocketed.exe')
Get-FileHash (Join-Path (Split-Path $exe) 'porydaw-without-pocketed.exe') -Algorithm SHA256

git switch --detach $with
deno task build:app --release
Copy-Item $exe (Join-Path (Split-Path $exe) 'porydaw-with-pocketed.exe')
Get-FileHash (Join-Path (Split-Path $exe) 'porydaw-with-pocketed.exe') -Algorithm SHA256
```

Keep those copies alongside the executable, bundled plain font files and runtime
resources. Do not move a lone executable into an empty scratch directory. DLL,
font, QML import or resource discovery differences would invalidate the A/B.

## Workload and smoke

Use the SAME checked-in/staged project, song, preferences, theme, window geometry,
drawer configuration and physical screen for both variants. Select one song with
a visible piano roll, not an event-list-only or empty session. Record the absolute
project path and exact label once; assign them to `$project` and `$song`. Omit
`--project`/`--song` only when intentionally measuring an identical saved session.
Do not edit the benchmark song. Snapshot preferences and confirm they are unchanged
when finished.

The existing public CLI is a smoke and single-variant summary, not the matched A/B
runner. It resolves the normal Release executable automatically. Example:

```powershell
deno task bench:startup --until editor-frame --runs 2 --project $project --song $song
```

Its default 300 ms ceiling is reported even without `--check`; it is not a promise
that these builds pass. Do not hide a budget miss by raising the ceiling. Report
first launch separately; a fresh process is not proof of a cold OS cache.

Also run the real WITH app, verify the chosen song is rendered, draw one note,
Undo back to the original document, and close without saving the temporary edit.
Exercise first and repeated WAV options/progress/error window requests, cancel and
close behavior. Check the corresponding WITHOUT surface if behavior differs.
Only terminate processes you launched, not a user's existing Porydaw instance.

## Matched timing protocol

1. Use a throwaway observer based on `measure()` in `tools/startup_bench.ts`
   (the source contains the process launch, stream reader, timeout and cleanup).
   Point it at the two saved executable copies. Do not add a production feature
   flag, change presenter scheduling, or commit a new benchmark API for this run.
2. Set `PORYDAW_STARTUP_TRACE=1` for each child. Start a monotonic timer immediately
   before `Deno.Command.spawn()`; include process creation/dynamic loading. Read
   stderr continuously. Record ALL frame markers in one launch and stop only at
   `editor-frame`, not at `workspace-ready`, `workspace-frame`, or `editor-ready`.
   Use the same cwd/arguments/environment for both binaries; capture diagnostics,
   exit/timeout failures and the entire raw stage sequence. Always reap only the
   owned child, including on observer error.
3. Measure at least **two blocks of 16 alternating pairs**. Pair 0 is separately
   reported and excluded from each block's warm statistics. For even pairs use
   WITHOUT then WITH; odd pairs WITH then WITHOUT. This yields **30 warm pairs**.
   No fixed-order block comparison or median from another machine/run.
4. Each pair must have matching positive values for
   `primary-screen-refresh-millihz`, `primary-screen-refresh-millihz-after`, and
   `screen-refresh-millihz`. Each launch's early/late primary values must agree.
   Keep the Windows display's NATURAL refresh rate; do not force it to the Mac's
   240 Hz. The early primary sample occurs after default Qt controller creation:
   it is not proof of the controller's constructor input or its private budget.
5. Preserve all attempts. A launch failure, changed workload, drift or Qt diagnostic
   stops that block for investigation; do not silently drop the bad pair or suppress
   the message. Distinguish a control/baseline warning from a candidate defect.
   Report an incomplete block separately, not as completed clean evidence.
6. For first/chrome/workspace/editor frames report each variant's warm median,
   **median of paired WITH-minus-WITHOUT differences**, wins/total, range/spread,
   first-pair observations, and failed/interrupted launches. Negative delta is
   faster. Difference of medians is NOT the paired median. Report per-block results
   as well as the combined result.
7. Record OS, CPU, Swift, MSVC, Qt patch/kit, power plan, display scale/refresh,
   binary hashes, source revisions, SDK SHA and recipe. Keep background work and
   desktop interaction quiet and consistent. Do not change antivirus/power/display
   policies or introduce application workarounds to manufacture a win.

Endpoint meaning: `first-frame`, `chrome-frame` and `workspace-frame` are submitted
frames, not editable-song proof. `editor-frame` requires a visible selected ready
piano roll, positive configured viewport, nonzero display revision and applied
revision, followed by native `afterSynchronizing`/`frameSwapped`. It does not
establish physical scanout, audible playback, readiness of every tab, or cold-cache
latency. All four must be measured; workspace improvement can conceal chrome cost.

## Covering checks

Run after timing so builds/desktop input do not contaminate samples:

```powershell
deno task checks:bridge
deno task checks:shell --filter shell-startup --filter shell-tabs-open-select --filter shell-tabs-close --filter shellwindow-prompts --pool=1 --verbose
deno task checks:shell --filter shell-export --filter shell-text-contrast --pool=1 --verbose
deno task checks:qml-roll --pool=1
```

- Startup proves actual pointer insertion with exact note attributes and real Undo;
  tabs/prompts cover mount, selection, close and shell-owned dialog lifecycle.
- Export covers first-use/reuse/cancellation; contrast checks fonts/surfaces; roll
  covers renderer behavior. Do not weaken assertions or exclude a failing scenario.
- Known Mac baseline failures in the complete shell lane: Ctrl edge resize at
  `tst_ShellGridInputEditing.qml:129` (unchanged Ctrl routing selects velocity),
  note-label ink contrast at `tst_ShellNoteVisuals.qml:219`, settings-dialog
  `active` at `tst_ShellSettings.qml:158` BEFORE Escape. All were baseline-confirmed
  on the fresh branch. Do not assume Windows reproduces them; report exact predicate
  and whether each occurs in WITHOUT as well as WITH. Do not expand editing semantics
  merely to make this startup experiment green.

## Mac observations: context, not Windows acceptance

Both variants used SDK `c504afeb`, the same saved `fightsong1_copy_2` in the local
`hearth-test` project, naturally matching 240000 mHz, unchanged preferences, and
same-bundle Release copies. Two completed blocks, 30 warm matched pairs:

| Endpoint | WITHOUT warm median | WITH warm median | Paired delta | WITH wins |
| --- | ---: | ---: | ---: | ---: |
| First | 220.873 ms | 223.390 ms | +0.868 ms | 14/30 |
| Chrome | 360.740 ms | 389.583 ms | +33.433 ms | 5/30 |
| Workspace | 504.572 ms | 389.590 ms | -115.913 ms | 30/30 |
| Editable song | 507.328 ms | 479.870 ms | -31.767 ms | 28/30 |

Editor paired improvements by block: -24.204 ms and -37.300 ms, 14/15 wins each.
The extra editable-song gain survives the font/dialog changes, but chrome regresses.
The 300 ms ceiling remains unmet. Earlier unmatched retained-only observations were
~334 ms: BOTH today's baseline and candidate are slower, so do not subtract these
absolute values from earlier runs or attribute that machine-state drift to code.

One intermediate attempt stopped on an unchanged-control-only
`QUnifiedTimer::stopAnimationDriver: driver is not running` diagnostic; it was
saved separately, not included in either completed block. No source workaround.
The WITH Release build, bridge guard and four startup/tabs/prompts suites passed.
Mac capture could not enumerate AX window 1 (-1719) for direct or Launch Services
launches; there is no screenshot claim. SourceKit refresh found zero Swift targets;
there is no semantic-index proof. Compiler, bridge, configured C++ AST/LSP, actual
production launches and QML input/raster evidence were observed.

Raw Mac data remains in the author's ignored `build/startup-profile/` directory;
it is not part of the remote branch. This table is the portable handoff evidence.

## Return report and clean decision

Return exact revisions/toolchain/recipe, raw per-launch data, two-block paired
statistics for all four endpoints, actual surface/check results, and one explicit
**KEEP**, **REJECT**, or **INCONCLUSIVE** decision with its Windows evidence.
Name the chrome/editor tradeoff and noise/first-launch limits. If inconclusive,
say which prerequisite or instability prevents a causal comparison; do not fake a
choice or shrink the surface. The receiving agent makes the keep decision.

To reject only the pocketed sequence while keeping fonts/dialogs/observation and
this handoff, revert commit `7966b9df1081a5d6af3946a57c89b175f833c2d5` on the
experiment branch; do not revert the retained baseline. Review/verify any further
source change and push every new commit to its corresponding remote branch.
Restore the working checkout to `$handoffTip` or the experiment branch after
measurement; remove owned temporary executables/observer scripts, keep raw evidence,
and leave unrelated project/preferences/WIP untouched.
