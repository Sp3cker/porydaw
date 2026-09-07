---
name: verify
description: Build porydaw and run in-repo harnesses through deno task. Use when verifying a change, running checks, or choosing a build/verify command.
---

# Verifying porydaw changes

Agents MUST use `deno task`. Do not invoke `cmake` / `cmake --build` directly.
There is no `deno task build`.

## Build

```bash
deno task build:app       # porydaw app only
deno task build:checks    # app + porydaw_checks + mid2agb
```

The tasks configure `build/` as Release if needed, then compile. Prefer
`build:checks` when you will run harnesses.

## Run harnesses

```bash
# Normal source change: build checks, then run the affected harnesses.
deno task verify --filter rollcheck --verbose
# Reuse build/ only after confirming it was built from the changed source.
deno task verify --no-build --filter vgcheck
```

Choose the narrowest verification that proves the changed behavior. For a
source change, identify the affected harness or harnesses and run them with
`deno task verify --filter <name>`; it builds `porydaw_checks` first. Exercise
the actual changed behavior too when a harness alone cannot establish it.

Run unfiltered `deno task verify` only for a cross-cutting change, after a
failure that makes broader fallout plausible, when targeted checks leave
material unresolved risk, or when the user explicitly requests full coverage.
Do not broaden or repeat checks merely by default.

`--no-build` is an optimization, not the default: use it only when the
existing `build/` demonstrably includes the changed source and configuration.
Otherwise omit it so `deno task verify` rebuilds. `deno task checks <binary>`
is the raw runner; only use it when the binary is not
`build/porydaw_checks` (CI's ASAN job does this).

### Instruction-only changes

Do not build the app or run harnesses automatically for documentation,
skill, or instruction-only edits. Instead, validate the relevant Markdown or
front-matter syntax, metadata, and changed link targets using the
repository-provided check where one exists; otherwise inspect those affected
elements directly. Run application verification only if the edit changes an
executable contract or introduces unresolved risk that requires it.

Do not:

- run `./build/porydaw --vgcheck` / `--viewcheck` / other `--*check` flags
- copy a decomp tree to `/tmp` or `/tmp/scratch`
- call `tools/run_checks.sh`

Harnesses live in `src/checks/` and run from `porydaw_checks`. The Deno
runner asks that binary for `--manifest`, gives each harness a private
scratch path, and stages only the fixture files declared in the C++
registry. Optional corpus: `PORYDAW_SAMPLE_CORPUS`.

New coverage belongs in `src/checks/` (`*check.cpp` or a sibling file
registered there). Do not stand up a scratch CMake project that compiles
widgets out of tree.

## Format

```bash
deno task format --check
deno task format [files...]
```

## ASAN

Memory bugs can pass silently in a normal build. CI's `asan-checks` job
configures `build-asan` with `-DPORYDAW_ASAN=ON` and runs
`deno task checks build-asan/porydaw_checks`.

The current `deno task` CLI cannot configure that tree: it hardcodes
`build/` + `CMAKE_BUILD_TYPE=Release`. Do not invent a local ASAN cmake
line unless the user asks. If `build-asan/porydaw_checks` already exists:

```bash
deno task checks build-asan/porydaw_checks --filter <name>
```
