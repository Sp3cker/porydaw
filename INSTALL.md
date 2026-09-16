# Installation

Installation is not required to use Porydaw. You can download the latest release and start immediately.

- [Download Porydaw for Windows](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-windows.zip).
- [Download Porydaw for macOS (arm)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-arm64.zip).
- [Download Porydaw for macOS (intel)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-x86_64.zip).
- [Download Porydaw for Linux](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-linux.zip) (AppImage).

**macOS users**: Porydaw is not notarized with Apple, so macOS quarantines the downloaded app and blocks the first launch. Copy the app into `/Applications`, then run `xattr -d com.apple.quarantine /Applications/porydaw.app` in Terminal. These steps are also in `RUN AFTER INSTALL.txt` inside the `.dmg`. This build uses bundle identifier `com.sp3cker.porydaw` and stores preferences under organization `sp3cker`, so it does not share settings with older `huderlem` releases. Dragging over an existing `/Applications/porydaw.app` still replaces that file — rename the older app first if you want both installed.

**Windows users**: Unzip into a new folder if you want to keep an older install. Preferences are stored under organization `sp3cker` and do not share with older `huderlem` releases. Unzipping over the previous folder replaces the binaries.

## Build from source

Porydaw uses one cross-platform Deno setup command. It initializes `poryaaaa`, installs the native build prerequisites, creates checkout-local Qt and formatter tooling, configures the complete check-enabled build, and builds the application.

Install Deno 2 first. The setup command cannot install Deno because Deno runs the command.

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
```

`deno task setup` needs an internet connection and permission to install native packages. It uses:

- Homebrew plus Xcode Command Line Tools on macOS;
- WinGet plus Visual Studio 2022 Build Tools on Windows;
- `apt-get` (Debian/Ubuntu), `pacman` (Arch), or `dnf` (Fedora) on Linux.

The command installs CMake 3.24 or newer, a C++20 compiler, Python, and the appropriate generator. It installs Qt 6.11 and the CI-matched `clang-format` 22 into this checkout:

```text
.cache/setup/qt/
.cache/setup-venv/
```

The cache is reusable and ignored by Git. Delete `.cache/setup/` and `.cache/setup-venv/` to download fresh local Qt and Python tooling. The setup command preserves an existing CMake build generator rather than replacing it.

`deno task setup` reports six numbered stages, marks reusable local tooling, and shows elapsed time while Qt or the application builds in an interactive terminal. If prerequisite provisioning fails, it prints relevant official manual-install links; rerunning the command reuses completed local work.

After setup, use the repository tasks:

```bash
deno task build:app
deno task build:checks
deno task verify
deno task format:check
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
