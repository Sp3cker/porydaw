# Installation

Installation is not required to use Porydaw. You can download the latest release and start immediately.

- [Download Porydaw for Windows](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-windows.zip).
- [Download Porydaw for macOS (arm)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-arm64.zip).
- [Download Porydaw for macOS (intel)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-x86_64.zip).
- [Download Porydaw for Linux](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-linux.zip) (AppImage).

**macOS users**: Porydaw is not notarized with Apple, so macOS quarantines the downloaded app and blocks the first launch. Copy the app into `/Applications`, then run `xattr -d com.apple.quarantine /Applications/porydaw.app` in Terminal. These steps are also in `RUN AFTER INSTALL.txt` inside the `.dmg`. This build uses bundle identifier `com.sp3cker.porydaw` and stores preferences under organization `sp3cker`, so it does not share settings with older `huderlem` releases. Dragging over an existing `/Applications/porydaw.app` still replaces that file — rename the older app first if you want both installed.

**Windows users**: Unzip into a new folder if you want to keep an older install. Preferences are stored under organization `sp3cker` and do not share with older `huderlem` releases. Unzipping over the previous folder replaces the binaries.

## Build from source

Porydaw is a Swift 6.4 + QML application (Swift owns behavior, exposed to QML through QtBridge; no QWidgets). The application entry point is the Swift shell (`src/swift/app/shell/PorydawShellApp.swift`), which loads `src/ui/shell/PorydawApplication.qml` and `ShellWindow.qml`.

The Swift app builds on macOS and Linux. Linux ARM64 has been validated with Swift 6.4.0 and Qt 6.11.2; Windows Swift build support is pending. Release downloads above may still contain the older C++ application.

Porydaw uses one Deno setup command. It checks installed host build tools before making changes, provisions only missing prerequisites, initializes `poryaaaa`, creates checkout-local Qt and formatter tooling, configures the complete check-enabled build, and builds the application.

Install Deno 2 first. The setup command cannot install Deno because Deno runs the command.

Install a working [Swift 6.4 toolchain](https://www.swift.org/install/) before running setup. Setup checks that the selected Swift compiler can compile and link a Swift 6.4 program; it does not provision Swift or its platform runtime dependencies. On macOS, use the version in `.swift-version`.

- macOS: `brew install deno`
- Windows: `winget install DenoLand.Deno`
- Linux: install Deno 2 using the [official Deno instructions](https://docs.deno.com/runtime/getting_started/installation/).

Then clone and set up the checkout:

```bash
git clone https://github.com/huderlem/porydaw
cd porydaw

# Optional: inspect the selected platform setup without changing the machine.
deno task setup --dry-run

deno task setup

# Optional: select a specific Qt patch if the latest download is unavailable.
deno task setup --qt-version 6.11.2
```

Selecting a Qt patch replaces cached Qt package paths in the existing build. Later setup and build tasks reuse that selection. Swift compiler options supplied through `SWIFTC` or cached `CMAKE_Swift_COMPILER_ARG1` are preserved during prerequisite checks. Swift's version is checked before provisioning; compilation and linking are checked after missing native tools are installed.

`deno task setup` needs an internet connection when a prerequisite is missing. Before invoking a package manager, it checks CMake, the selected generator, a C and C++20 toolchain, a Swift 6.4 toolchain, and Python. Compatible installed tools are left unchanged. If an installed tool is incompatible, setup stops before provisioning it and reports the required and detected versions. On macOS the Swift toolchain is pinned by `.swift-version` (currently 6.4.0) via swiftly.

When it must provision a missing host prerequisite, it uses:

- Homebrew for CMake, Ninja, and Python, plus Xcode Command Line Tools for the macOS compiler;
- WinGet plus Visual Studio 2022 Build Tools on Windows;
- `apt-get` (Debian/Ubuntu), `pacman` (Arch), or `dnf` (Fedora) on Linux.

The required host tools are CMake 3.24 or newer, a C++20 compiler, Swift 6.4 (pinned by `.swift-version` on macOS via swiftly), Python 3.10 or newer that can create a virtual environment with pip, and the generator selected for the build. Qt 6.11 and the CI-matched `clang-format` 22 are installed only into this checkout:

```text
.cache/setup/qt/
.cache/setup-venv/
```

The cache is reusable and ignored by Git. Delete `.cache/setup/` and `.cache/setup-venv/` to download fresh local Qt and Python tooling. The setup command preserves an existing CMake build generator rather than replacing it.

`deno task setup --dry-run` checks the installed native toolchain and reports whether it is compatible, incompatible, or missing tools that setup would install; it never invokes a package manager. The normal command reports six numbered stages, marks reusable local tooling, and shows elapsed time while Qt or the application builds in an interactive terminal. If prerequisite provisioning fails, it prints relevant official manual-install links; rerunning the command reuses completed local work.

After setup, use the repository tasks:

```bash
deno task build:app
deno task build:checks
deno task verify
deno task format:check
deno task setup:check
```

Launch the built application with the platform-appropriate command:

```bash
# macOS
open build/porydaw.app

# Windows
.\build\Release\porydaw.exe

# Linux
./build/porydaw
```

`deno task verify` runs the check lanes declared for the host platform. On macOS every lane runs. On Linux and Windows the Swift lanes (`swiftcore`, `projectidentitycheck`, `projectstore-*`, `bankleases`, `vgbankcheck`, `exportcheck-*`) are still listed by `porydaw_checks --manifest` with `"platforms": ["macos"]`, but the runner reports them as platform-skipped because the check harness does not link Swift there yet. A verify selection that leaves no runnable check on the host exits with status 2 instead of passing.
