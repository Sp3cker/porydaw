---
name: verify
description: Build porydaw and run in-repo harnesses through deno task. Use when verifying a change, running checks, or choosing a build/checks command.
---

# Verifying porydaw changes

Agents MUST use `deno task`. Do not invoke `cmake` / `cmake --build` directly.
There is no `deno task build`.

## Build

```bash
deno task build:app       # porydaw app only, in build/debug
deno task build:checks    # app + porydaw_checks + mid2agb, in build/debug
deno task build:app --release  # same, in build/release
```

Debug and Release are separate trees (`build/debug`, `build/release`). Prefer
`build:checks` when you will run harnesses.

A failed build prints the failing step, its errors, and
`build/<config>/build.log`. Read that log for more detail; rebuilding prints
nothing new.

## Run harnesses

```bash
# Normal source change: builds checks, then runs the affected harnesses.
deno task checks --filter rollcheck
```

Choose the narrowest verification that proves the changed behavior. For a
source change, identify the affected harness or harnesses and run them with
`deno task checks --filter <name>`; it builds `porydaw_checks` first. Exercise
the actual changed behavior too when a harness alone cannot establish it.

Run unfiltered `deno task checks` only for a cross-cutting change, after a
failure that makes broader fallout plausible, when targeted checks leave
material unresolved risk, or when the user explicitly requests full coverage.
Do not broaden or repeat checks merely by default. A failing harness prints its
complete output; do not rerun it with `--verbose` to see more.

### Instruction-only changes

Do not build the app or run harnesses automatically for documentation,
skill, or instruction-only edits. Instead, validate the relevant Markdown or
front-matter syntax, metadata, and changed link targets using the
repository-provided check where one exists; otherwise inspect those affected
elements directly. Run application verification only if the edit changes an
executable contract or introduces unresolved risk that requires it.

Do not:

- run `./build/debug/porydaw --vgcheck` / `--viewcheck` / other `--*check` flags
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
deno task format            # swift-format on uncommitted Swift changes, deno fmt on tools/
deno task format --check    # what the pre-commit hook runs
```

## ASAN

Memory bugs can pass silently in a normal build. CI's `asan-checks` job
configures `build-asan` with `-DPORYDAW_ASAN=ON` and runs the raw runner,
`tools/run_checks.ts build-asan/porydaw_checks`, directly.

`deno task` cannot configure that tree. Do not invent a local ASAN cmake
line unless the user asks. If `build-asan/porydaw_checks` already exists:

```bash
deno run --allow-read --allow-write --allow-run \
  --allow-env=ASAN_OPTIONS,DISPLAY,PORYDAW_SAMPLE_CORPUS \
  tools/run_checks.ts build-asan/porydaw_checks --filter <name>
```
