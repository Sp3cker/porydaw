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
deno task verify                              # builds checks, then all harnesses
deno task verify --filter rollcheck --verbose
deno task verify --no-build --filter vgcheck  # reuse an existing build/
```

`deno task verify` is the default. `deno task checks <binary>` is the raw
runner; only use it when the binary is not `build/porydaw_checks` (CI's
ASAN job does this).

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
