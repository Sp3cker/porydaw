# Windows build and runtime notes

This records the changes used to build and run `feature/swift-qml-grid` on
Windows x86_64. Verified on October 3, 2026. The fixes were integrated into
the feature branch in `8e3b6871`; the temporary
`codex/swift-qml-grid-build` branch was then deleted.

## Verified toolchain

| Component | Selection |
| --- | --- |
| Swift compiler, SDK, and runtime | 6.4.0, matching `.swift-version` |
| Native compiler | Swift's bundled `clang.exe` / `clang++.exe`, targeting the MSVC ABI |
| Windows native dependencies | Visual Studio 2022 C++ tools and Windows SDK |
| Qt | 6.11.2, `win64_msvc2022_64` package / `msvc2022_64` kit |
| Generator / configuration | Ninja / Release |
| Build entry point at verification | Deno 2 repository tasks (retired; current harness is uv/Python) |

This build was verified with Swift **6.4.0**, not Swift 6.2. The current
CMake configuration requires Swift 6.4 or newer on Windows and Linux.
The Windows build runner selects the version in `.swift-version` from the
standard installer directories under `%LOCALAPPDATA%\Programs\Swift`:

```text
Toolchains\6.4.0+Asserts\usr\bin
Runtimes\6.4.0\usr\bin
Platforms\6.4.0\Windows.platform\Developer\SDKs\Windows.sdk
```

Use the MSVC Qt kit with this toolchain. The old MinGW Qt environment is
not the environment used for this Swift build.

## Setup and build

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), the matching Swift compiler/SDK/runtime, Git, CMake 3.24+, Visual Studio's C++ workload and Windows SDK first. Setup validates host tools; it does not provision them or request elevation.

For a fresh checkout, start in a Visual Studio Developer PowerShell with
the x64 native tools initialized. Select Swift explicitly before setup,
which has its own prerequisite checks and configuration path:

```powershell
git clone https://github.com/Sp3cker/porydaw.git
Set-Location porydaw

$taskSwiftVersion = (Get-Content .swift-version).Trim()
$taskSwiftRoot = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
$taskSwiftBin = Join-Path $taskSwiftRoot "Toolchains\$taskSwiftVersion+Asserts\usr\bin"
$taskSwiftRuntime = Join-Path $taskSwiftRoot "Runtimes\$taskSwiftVersion\usr\bin"
$env:SDKROOT = Join-Path $taskSwiftRoot "Platforms\$taskSwiftVersion\Windows.platform\Developer\SDKs\Windows.sdk"
$env:Path = "$taskSwiftBin;$taskSwiftRuntime;" + $env:Path
$env:CC = Join-Path $taskSwiftBin 'clang.exe'
$env:CXX = Join-Path $taskSwiftBin 'clang++.exe'
$env:SWIFTC = Join-Path $taskSwiftBin 'swiftc.exe'

uv sync --locked
uv run --no-sync dev setup --qt-version 6.11.2
uv run --no-sync dev build:app --release
```

Setup initializes the pinned `poryaaaa` submodule and installs Qt into
`.cache/setup/qt/windows-win64_msvc2022_64/6.11.2/msvc2022_64`.
For subsequent builds, `tools/porydaw_dev/build.py` finds Visual Studio through
`vswhere`, imports `VsDevCmd.bat -arch=x64 -host_arch=x64`, sets `SDKROOT`,
and prepends the pinned Swift compiler and runtime directories automatically.

Use `uv run --no-sync dev` for builds and checks. Run `uv sync --locked` once per checkout/worktree and after lock/project changes. uv manages Python 3.13, Ninja and Ruff; the Qt installer group is added only when setup needs to download Qt.

The executable is `build/release/porydaw.exe`; the full build log is `build/release/build.log`. All new trees use standard Ninja. Remove and recreate trees configured with another generator; there is no multi-config artifact fallback.

The October 3 existing-checkout builds and launches below were verified under the retired harness. The uv/Python Windows environment, workflows and launch path have been source-reviewed, not executed on Windows. A clean Windows installation was not tested here.

## Build fixes

| Failure or incompatibility | Change and location |
| --- | --- |
| Visual Studio and Swift environment missing from ordinary PowerShell | `tools/porydaw_dev/build.py` initializes the x64 developer environment and selects the pinned compiler, SDK, and runtime. |
| Visual Studio generator unsuitable for the mixed Swift build | `tools/porydaw_dev/build.py` selects standard Ninja, including Windows. |
| Swift importer could not convert Qt's ordering result | `tools/porydaw_dev/qt.py` patches checkout-local Qt's `qversionnumber.h` return to explicit `std::strong_ordering` values during Windows setup; `dev qt:patch <prefix>` handles CI's external kit. |
| Mixed native/Swift archives and Release headers disagreed | `CMakeLists.txt` selects the C++ archive driver for the native app library, disables Windows Release IPO/LTO, and passes `QT_NO_DEBUG` / `NDEBUG` to Swift's Clang importer in Release. |
| MSVC linker failed to open a macro dependency object at a long path | Windows Swift links use `-use-ld=lld` in `CMakeLists.txt`. The failing path in this worktree was about 265 characters long. |
| Swift autolink requested library names that did not match generated archives | Windows Swift archives receive the `lib` prefix; the app link searches the SDK runtime directory and each Swift module's archive directory. |
| Swift generic type metadata lookup failed at runtime | The C++ executable link explicitly includes the SDK's `swiftrt.obj` COFF image-registration object. |
| `CoreFoundation` imports and type checks did not compile on Windows | `PreferencesStore.swift` imports CoreFoundation conditionally and uses Foundation's `NSNumber.objCType` to identify booleans where CoreFoundation is unavailable. The unused import in `EditorViewStateCodec.swift` was removed. |
| Direct Swift iteration over Qt standard key bindings failed | `keybindings_bridge.h` exposes count/index access to `QKeySequence::keyBindings`; `KeybindingRegistry.swift` uses those native boundary helpers. |

## Loader fixes and launch

A successful compile was insufficient: the executable also had to load
the matching Swift and Qt DLLs and register Swift metadata correctly.

| Windows error | Diagnosis and fix |
| --- | --- |
| “Side-by-side configuration is incorrect” | Windows' SideBySide event named a missing `level` attribute on `requestedExecutionLevel`. The linker had rewritten the manifest attributes into the wrong XML namespace. Post-build `mt.exe` commands reembed Qt's original generated manifest for both `porydaw.exe` and `porydaw_checks.exe`. |
| “Entry Point Not Found”, including `$sScM6sharedScMvau` | The executable was resolving incompatible Swift runtime DLLs. The app's post-build step copies DLLs from the compiler-selected Swift runtime beside the executable. Qt's `windeployqt` does not deploy Swift DLLs. |
| Missing Qt DLL, platform plugin, or QML module | `windeployqt` stages Qt DLLs and imports. For development launches, explicitly select the same Qt kit in the launching process as shown below. |

From the checkout root, launch with the matching runtime environment:

```powershell
$taskQt = Join-Path $PWD '.cache\setup\qt\windows-win64_msvc2022_64\6.11.2\msvc2022_64'
$env:Path = "$taskQt\bin;" + $env:Path
$env:QT_PLUGIN_PATH = "$taskQt\plugins"
$env:QML2_IMPORT_PATH = "$taskQt\qml"
Start-Process -FilePath "$PWD\build\release\porydaw.exe" -WorkingDirectory "$PWD\build\release"
```

The child inherits these variables. Setting them in a different PowerShell
process does not configure the process that launches the app. Select a
different Qt patch path if setup was run with another version.

For loader diagnosis, inspect the Windows Application event log's
`SideBySide` events and capture the app's stderr. Do not treat a loader
failure as a successful runtime test or as an application assertion failure.

## Checks and evidence

With the Qt environment above, run:

```powershell
uv run --no-sync dev checks --verbose
uv run --no-sync dev checks:bridge
uv run --no-sync dev tools:check
uv run --no-sync dev format --check
```

The historical runner fixes covered Windows environment setup, Release tree selection and the missing `swiftSample` null-handler declaration in `src/checks/checkcatalog.cpp`. The check executable also needed the manifest embedding described above.

Historical October 3 results (pre-uv):

- Release app and native check executable built successfully.
- The app opened the fixture project and displayed song rows, tracks,
  notes, and automation. The Play and Stop controls were exercised.
- `deno task checks --verbose`: **1 passed, 36 platform-skipped**. The
  passing check is `production-startup`, which invokes `--version`; it
  does not exercise a rendered editor or audio playback.
- Bridge surface guard: 0 baselined findings.
- Setup tests: 5 passed, 3 ignored, 0 failed.
- Type checking of the build runner and CLI passed; focused formatting
  checks for the Windows changes passed.

The native Swift suites are enabled on macOS/Linux, not Windows. QML test
lanes are currently enabled only on macOS. The skipped suites were not
executed and are not evidence that their behavior passed on Windows.

## Related Windows visual fix

The moving playhead appeared to pulse in width at fractional positions.
`SharedPlayhead.qml` now aligns its center to physical pixels using the
screen's device pixel ratio and uses a one-physical-pixel core. This was
committed separately as `5805aed6` and included in the feature-branch merge;
it was a rendering fix, not a compiler or loader fix.
