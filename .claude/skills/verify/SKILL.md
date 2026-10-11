---
name: verify
description: Build Porydaw and run in-repo harnesses through uv/Python. Use when verifying changes or choosing build/check commands.
---

# Verifying Porydaw changes

Agents use `uv run --no-sync dev`; never invoke CMake or Ninja directly. Provision each checkout/worktree with `uv sync --locked`, and repeat sync only after project/lock changes. Use `dev --help` to discover commands. CI's artifact jobs are the documented direct-CMake exception.

## Build

```bash
uv run --no-sync dev build:app
uv run --no-sync dev build:checks
uv run --no-sync dev build:app --release
```

Debug, Release and ASAN use separate `build/debug`, `build/release`, `build/asan` trees. All use standard Ninja. Prefer `build:checks` before native harnesses. A failed build prints the failing phase, actionable errors and `build/<config>/build.log`; read that log rather than rerunning for details. Phase times and slowest new Ninja commands provide build attribution; parallel command durations are not a wall-time partition.

## Run harnesses

```bash
uv run --no-sync dev checks --filter <name>
uv run --no-sync dev checks:shell --filter <name>
uv run --no-sync dev checks:qml --filter <name>
uv run --no-sync dev checks:qml-roll --filter <name>
```

Choose the narrowest lane that proves the behavior. Exercise the changed path too when a harness cannot establish it. Run unfiltered checks for cross-cutting changes, plausible broader fallout or an explicit request, not by default. Failures print complete output; no verbose rerun is necessary.

`tools/porydaw_dev/checks.py` reads each binary's `--manifest`, stages only its declared fixtures in a private scratch path and removes that path afterward. Do not manually copy decomp trees or invoke retired application `--*check` flags. Optional sample corpus: `PORYDAW_SAMPLE_CORPUS`. Coverage belongs with the Swift/QML owner under `src/checks/`; follow AGENTS.md's native-boundary rules.

```bash
# Prebuilt CI binary; no configure/build.
uv run --no-sync dev checks:run /path/to/porydaw_checks --filter <name>
# Python harness behavior and Ruff.
uv run --no-sync dev tools:check
# Standalone Swift backup storage, no app/Qt build.
uv run --no-sync dev checks:backups
```

## Format and ASAN

```bash
uv run --no-sync dev format        # changed Swift lines via swift format; Python via Ruff
uv run --no-sync dev format --check
uv run --no-sync dev checks --asan --filter <name>
```

ASAN is unavailable on Windows. Local ASAN uses `build/asan`; CI may pass its externally built ASAN binary to `checks:run`. Do not invent a direct-CMake command.

## Instruction-only changes

Do not build or run application harnesses for docs/skill-only changes. Inspect changed Markdown, metadata, links and executable examples; use an existing syntax check when available. Run application verification only if the edit changes an executable contract or leaves material runtime risk.
