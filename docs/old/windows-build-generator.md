# Windows build generator inconsistency

Status: idea. Not scheduled.

## Problem

The Deno build path and CI disagree about the Windows CMake generator, and the
configuration naming makes `build/debug` produce a Release configuration.

## Evidence

- `tools/local_build_environment.ts` `defaultGeneratorArguments` selects
  `Visual Studio 17 2022` with `x64` on Windows, while selecting Ninja elsewhere.
- `tools/build.ts` `runBuild` adds `--config Release` whenever the tree is
  multi-config, including the `debug` path; `artifactPath` puts multi-config
  artifacts in `<tree>/Release`, so Windows artifacts land in
  `build/<config>/Release/`.
- `tools/cli.ts` `runChecks` builds `debug` but appends `Release` when the tree
  is Windows multi-config. `tools/setup.ts` likewise launches
  `build\\release\\Release\\porydaw.exe` and passes `--config Release`.
- `tools/build.ts` `hasBuildSystem` treats a `Makefile` as a build system,
  although no supported path generates one.
- `AGENTS.md` "Windows toolchain and launch" documents Windows MSVC builds
  using `cl` and `ninja` from a Visual Studio developer shell; `INSTALL.md`
  says Windows Swift build support is pending. This conflicts with the Deno
  path's Visual Studio generator choice.
- CI uses Ninja directly: the `build-native` Windows job in
  `.github/workflows/build.yml` and the `build-windows` job in
  `.github/workflows/release.yml` configure with `-G Ninja`. This differs from
  the Deno Windows path.

## Why it matters for agents

Agents can select a generator inconsistent with CI and interpret a nominal
Debug build as Release, making artifact paths, launch commands, and debugging
expectations unreliable.

## Open decision

Choose the supported Windows generator: Visual Studio multi-config, or
Ninja+MSVC. Decide whether Windows `Debug` should actually build Debug rather
than Release. No implementation is proposed here.
