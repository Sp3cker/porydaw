# Porydaw

[![Actions Status](https://github.com/huderlem/porydaw/workflows/Build/badge.svg)](https://github.com/huderlem/porydaw/actions)

A music editor for the Pokémon generation 3 decompilation projects ([pokeruby][pokeruby], [pokeemerald][pokeemerald], and [pokefirered][pokefirered]).

In Porydaw, load your decomp project directory to load the music-related project data. Then, play, edit, and create music. It sounds just like it does in-game.  When saving, Porydaw writes and creates the necessary files directly into the decomp project.  It also supports importing MIDI files, making it easy to whip up songs and voicegroups for brand new songs.

Porydaw is designed for both music beginners and power users who are familiar with DAW programs.  If you've used Sappy or Anvil Studio for your musical needs in the past, then Porydaw is for you!  If you're a power user who loves your existing DAW (FL Studio, Reaper, etc.), give Porydaw a try--but if you can't be pulled away, the [poryaaaa CLAP plugin](https://github.com/huderlem/poryaaaa) helps serve that power-user workflow.

View the work-in-progress documentation: https://huderlem.github.io/porydaw

View the [Changelog][changelog] to see what's new.

<img src="docsrc/img/introduction-porydaw-screen.png" width="600" alt="Porydaw main window">

## Download

Download Porydaw below to start using it immediately. Older versions of Porydaw may be downloaded from the [Releases][releases] page.

 - [Download Porydaw for Windows](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-windows.zip).
 - [Download Porydaw for macOS (arm)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-arm64.zip).
 - [Download Porydaw for macOS (intel)](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-x86_64.zip).
 - [Download Porydaw for Linux](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-linux.zip) (AppImage).

Read [INSTALL.md](INSTALL.md) for instructions on how to compile Porydaw from source.

## Architecture

Porydaw is a Swift 6.4 + QML application. Swift owns behavior and exposes it to
QML through QtBridge; there are no QWidgets. Native boundaries include
`src/app/`, `font_metrics.cpp`, and `src/project/`.
The application entry point is the Swift shell
(`src/swift/app/shell/PorydawShellApp.swift`), which loads
`src/ui/shell/PorydawApplication.qml` and `ShellWindow.qml`.

Builds run through Deno tasks against a checkout-local Qt 6.11. On macOS the
Swift toolchain is pinned by `.swift-version` (currently 6.4.0) via swiftly.
The Swift app builds on macOS and Linux. Linux ARM64 has been validated with
Swift 6.4.0 and Qt 6.11.2; Windows Swift build support is pending.

## Contributing

Swift is formatted with swift-format, which ships with the Swift toolchain (`swift format`;
config in `.swift-format`). Only Swift lines you change are formatted, so untouched code keeps
its existing style. TypeScript under `tools/` is formatted with `deno fmt`. Before opening a
pull request, run:

```bash
deno task format                              # format uncommitted Swift changes and tools/*.ts
deno task format --check --base origin/fork-main  # what CI checks for a pull request
```

Build and run the check sweep with Deno:

```bash
deno task checks                             # native check runner harnesses (builds first)
deno task checks --filter swiftcore          # Swift core/presenter suites
deno task checks:shell                       # production ShellWindow QML lanes
deno task checks:qml                         # editor drawer QML lane
deno task checks:qml-roll                    # Swift roll window QML lane
deno task checks:bridge                      # Swift/QML boundary guard
deno task proof check                        # assertion-ledger structure
```

`deno task build:checks --asan` builds the app and native checks with AddressSanitizer
in `build/asan`, separate from normal Debug and Release builds. On macOS it uses
Clang from the selected Swift toolchain so both languages share an ASAN runtime.
Run its native checks with:

```bash
deno run --allow-read --allow-write --allow-run --allow-env=ASAN_OPTIONS,DISPLAY,HOME,PORYDAW_SAMPLE_CORPUS tools/run_checks.ts build/asan/porydaw_checks
```

Checks pin consumer-visible behavior and distinct input/state transitions. Prefer typed
rejections and preserved state over diagnostic wording. Remove assertions implied by
stronger checks in the same state, but retain fixture guards and lifecycle scenarios.
Rendering checks observe painted output rather than pinning renderer-specific primitives.
Update affected proof ledgers with their check changes; compile only referenced support.

### Startup profiling

`bash autoresearch.sh` measures the configured live-project cold launch on a
Debug build, including song restoration and a settled rendered window. It is
not a portable fixture-based check.

Track-name, automation-lane, and time-signature scans borrow a Swift `Span`
from an explicitly scoped array owner to reduce Debug-build iterator
allocations. They still read the current document without caching results
or copying the event buffer.
Catalog parsing likewise iterates borrowed line spans while reading project
files live.

Settings pages are constructed only while the dialog is visible. Opening
the dialog initializes controls from the current settings draft; reopening
after Cancel discards uncommitted field edits.

## License

Porydaw is licensed under [GPL-3.0](LICENSE). The embedded poryaaaa engine is
licensed under MIT.

## AI Disclaimer

Porydaw's code has been built with heavy usage of Claude Code--bootstrapped with the Fable model.

[pokeruby]: https://github.com/pret/pokeruby
[pokeemerald]: https://github.com/pret/pokeemerald
[pokefirered]: https://github.com/pret/pokefirered
[changelog]: https://github.com/huderlem/porydaw/blob/main/CHANGELOG.md
[releases]: https://github.com/huderlem/porydaw/releases
