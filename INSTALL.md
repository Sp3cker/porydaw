# Installation

**Note**: Installation is not required to use Porydaw. You can download the latest release to begin using Porydaw immediately.

 - [Download Porydaw for Windows](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-windows.zip).
 - [Download Porydaw for macOS (arm)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-arm64.zip).
 - [Download Porydaw for macOS (intel)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-x86_64.zip).
 - [Download Porydaw for Linux](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-linux.zip) (AppImage).

**macOS users**: Porydaw is not notarized with Apple, so macOS quarantines the downloaded app and blocks the first launch. To allow it, try to open the app once, then go to System Settings → Privacy & Security, scroll down to the message about porydaw, and click **Open Anyway**. Alternatively, run `xattr -d com.apple.quarantine /Applications/porydaw.app` in Terminal.

Building from source requires CMake 3.21+, a C11/C++17 compiler, and Qt 6.2 or newer (Widgets).

Porydaw embeds the [poryaaaa](https://github.com/huderlem/poryaaaa) engine as a git submodule, so clone with `--recursive`. If you already cloned without it, run `git submodule update --init` inside the repository.

## macOS

The easiest way to get the build tools is through [homebrew](https://brew.sh/).
Once homebrew is installed, run these commands in Terminal:

```bash
xcode-select --install

brew update
brew install cmake qt

git clone --recursive https://github.com/huderlem/porydaw
cd porydaw

cmake -B build
cmake --build build

open build/porydaw.app
```

## Windows

Install [Qt development tools](https://www.qt.io/download-qt-installer) (select a Qt 6 kit along with CMake and a compiler), and use Qt Creator, the official Qt IDE, for development purposes. Qt Creator opens `CMakeLists.txt` directly as a project.

## Ubuntu

You need CMake, a C/C++ compiler, and Qt 6. You can check your Qt version with `qtdiag` or `qmake6 --version`.

```bash
sudo apt-get install cmake build-essential qt6-base-dev

git clone --recursive https://github.com/huderlem/porydaw
cd porydaw

cmake -B build
cmake --build build

./build/porydaw
```

## Arch Linux

You need CMake, a C/C++ compiler, and Qt 6. You can check the version of your Qt packages with `qtdiag` or `qmake6 --version`.

```bash
sudo pacman -S cmake gcc qt6-base

git clone --recursive https://github.com/huderlem/porydaw
cd porydaw

cmake -B build
cmake --build build

./build/porydaw
```
