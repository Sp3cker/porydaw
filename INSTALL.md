# Installation

Installation is not required to use Porydaw. You can download the latest release and start immediately.

- [Download Porydaw for Windows](https://github.com/Sp3cker/porydaw/releases/latest/download/porydaw-windows.zip).
- [Download Porydaw for macOS (arm)](https://github.com/Sp3cker/porydaw/releases/latest/download/porydaw-macos-arm64.zip) (macOS 26 or later).
- [Download Porydaw for macOS (intel)](https://github.com/Sp3cker/porydaw/releases/latest/download/porydaw-macos-x86_64.zip) (macOS 26 or later).
- [Download Porydaw for Linux](https://github.com/Sp3cker/porydaw/releases/latest/download/porydaw-linux.zip) (AppImage).

**macOS users**: Porydaw requires macOS 26 or later. It is not notarized with Apple, so macOS quarantines the downloaded app and blocks the first launch. Copy the app into `/Applications`, then run `xattr -d com.apple.quarantine /Applications/porydaw.app` in Terminal. These steps are also in `RUN AFTER INSTALL.txt` inside the `.dmg`. This build uses bundle identifier `com.sp3cker.porydaw` and stores preferences under organization `sp3cker`, so it does not share settings with upstream Porydaw releases. Dragging over an existing `/Applications/porydaw.app` still replaces that file — rename the older app first if you want both installed.

**Windows users**: Unzip into a new folder if you want to keep an older install. Preferences are stored under organization `sp3cker` and do not share with upstream Porydaw releases. Unzipping over the previous folder replaces the binaries.

## Build from source

Porydaw is a Swift 6.4 + QML application (Swift owns behavior, exposed to QML through QtBridge; no QWidgets). The application entry point is the Swift shell (`src/swift/app/shell/PorydawShellApp.swift`), which loads `src/ui/shell/PorydawApplication.qml` and `ShellWindow.qml`.

The Swift app builds on macOS, Linux, and Windows x86_64. Linux ARM64 and Windows x86_64 have been validated with Swift 6.4.0 and Qt 6.11.2. See [Windows build and runtime notes](docs/windows-build.md) for the Windows toolchain, build fixes, launch commands, and check limitations. Release downloads above may still contain the older C++ application.

The scripting harness is Python 3.13, provisioned by [uv](https://docs.astral.sh/uv/getting-started/installation/) 0.13.0 or newer. No Deno, Node, pip or global Python packages are needed. Install uv first, then the host native tools:

- Git and CMake 3.24 or newer.
- A C/C++20 toolchain: Xcode command-line tools on macOS, your distribution's compiler tools on Linux, or Visual Studio 2022's C++ workload and Windows SDK.
- [Swift 6.4 or newer](https://www.swift.org/install/), including `swift format`. macOS uses `.swift-version` through swiftly; Windows also needs Swift's matching SDK and runtime.

Setup validates these host tools; it never runs a host package manager, requests elevation or installs Swift. Install missing prerequisites manually using the links in its errors.

```bash
git clone https://github.com/Sp3cker/porydaw
cd porydaw
uv sync --locked
uv run --no-sync dev setup

# Optional: select a specific Qt 6.11 patch.
uv run --no-sync dev setup --qt-version 6.11.2
```

`uv sync --locked` creates this checkout's `.venv`, downloads Python if needed, and installs pinned Ninja and Ruff. Run it once per checkout/worktree and after `pyproject.toml` or `uv.lock` changes. Normal commands use `--no-sync`: warm harness invocation does not check a Python package registry or implicitly synchronize dependencies.

Setup initializes the pinned `poryaaaa` dependency, provisions checkout-local Qt, then builds the Release app with checks enabled. Its four stages report elapsed time. The optional Qt installer dependencies are synchronized with `uv sync --locked --group qt` only when Qt needs downloading; they are not installed by default. Local Qt lives under `.cache/setup/qt/<host>-<architecture>/<version>/<kit>`. Existing selected local Qt is reused. Explicit `--qt-version` replaces cached Qt package paths; later builds retain the selection.

New builds use standard Ninja. A tree configured with another generator must be removed and recreated; there is no generator compatibility layer. Debug, Release and ASAN use separate `build/debug`, `build/release` and `build/asan` trees.

```bash
uv run --no-sync dev --help
uv run --no-sync dev build:app
uv run --no-sync dev build:checks --release
uv run --no-sync dev checks --release
uv run --no-sync dev tools:check
uv run --no-sync dev format --check
```

Build output shows phase wall times and the slowest new Ninja commands. The full log is `build/<config>/build.log`; read it on failure instead of rebuilding for detail. Swift command hashes invalidate objects when compile flags change, including CMake regeneration during Ninja. Unchanged builds retain incremental objects and the shared QtBridge macro cache.

Launch the Release application with:

```bash
# macOS
open build/release/porydaw.app

# Windows — use the runtime environment in docs/windows-build.md
.\build\release\porydaw.exe

# Linux
./build/release/porydaw
```

Native Swift suites run on macOS and Linux; Windows currently skips those suites because the check harness does not link its Swift test library there. QML lanes currently build only on macOS. Windows checks use Release by default. An empty selection exits 2 rather than passing. Prebuilt binaries can be run with `uv run --no-sync dev checks:run <binary>`.
