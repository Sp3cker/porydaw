# uv/Python harness cutover

Base: `4e20bd87`. Controller writes Python; m1 (Claude Opus 5.5) proposes and judges every file. User priorities: agent ergonomics, build attribution and environment download cost, then removing accumulated complexity. Clean cutover, no Deno shims. External `poryaaaa` is outside the migration.

## Shared contract

One root uv project, lockfile, editable `porydaw_dev` package under `tools/`, console command `dev`. Python 3.13 pinned by `.python-version`, floor 3.13. uv 0.13.0 is the bootstrap version. Default dependencies: pinned Ninja; default dev group: pinned Ruff; optional `qt` group: aqtinstall at the existing exact git revision required by Qt 6.11 on Windows. Host prerequisites: Git, CMake >=3.24, C/C++ compiler/SDK, Swift >=6.4. No automatic privileged host installs, second Python environment, npm, task-runner dependency or type-checker runtime.

Provision: `uv sync --locked`. Warm: `uv run --no-sync dev <command>`. Qt setup explicitly syncs `--locked --group qt` only when Qt must be downloaded, then runs aqt with the current interpreter. This work is attributed as environment provisioning, not native build time. A root guard compares cwd's Git toplevel with the package's owning repository before any mutation; subdirectories within that repository are accepted. Lazy command imports avoid loading checks/profiling on help/build paths.

Run `uv sync --locked` once in each new worktree and after edits to `pyproject.toml` or `uv.lock`; warm `--no-sync` commands intentionally do not repair missing environments. Python 3.13 is security-maintained; the pin favors its smaller/faster harness runtime over new language features.

Command names retain the meaningful existing lane names. `setup:check` becomes `tools:check`; add `checks:run <binary>` and `qt:patch <prefix>` for prebuilt CI consumers. Bare `dev` prints the command index successfully; remove the misleading bare `build` alias. Baseline writes exist only as distinct baseline commands, not flags on read-only checks. Remove obsolete `--reporter`, `--no-build` special diagnostics and `--dry-run`. Checks default to incremental build; preserve platform lanes, fixtures, serial native-window execution, offscreen pooling, opt-in selection, terminal Qt payload and nonzero empty-selection/failure outcomes.

Build attribution: elapsed environment preparation, dependency validation, configure, Swift-object reconciliation and native build phases. Persist full streamed output and per-command native durations in `build/<config>/build.log`; concise actionable stdout/stderr. Ninja records are grouped by `(start, end, command hash)`, not timestamps alone. Native command durations overlap and must not be represented as a wall-time partition. Snapshot comparison must not accidentally report historical edges as current work. Setup reports provisioning separately. Do not invent wire-byte measurements: distinguish compressed release/wheel sizes, uv's reported downloads and installed disk footprint.

Keep the Swift compile-directive SHA stamp semantics and pre/post-build reconciliation, including reconfiguration inside `cmake --build`. Support `.o` and `.obj` outputs. Existing trees retain cached Qt; an explicit setup Qt selection forces reconfiguration when changed. macOS swiftly pin/in-use checks, ASAN compiler pairing and bundle paths remain. Windows VsDevCmd and Swift runtime/SDK setup remain; unsupported Windows ASAN is rejected. No native application behavior changes; obsolete harness comments may change in Swift/CMake.

Approved prerequisite repair: reproduce the main checkout's macOS header-policy fix in this worktree. Set `CMAKE_NO_SYSTEM_FROM_IMPORTED` before Qt discovery; remove the redundant interface-system helper and per-target overrides. The first native build reproduced `/usr/local/include/QtCore` shadowing Qt 6.11; the user explicitly requested reapplying the fix here.

Tests exercise consumer behavior and failure boundaries, not help wording, wiring, literal argument copies or incidental defaults. Use stdlib unittest. Preserve baseline findings/count semantics without re-pinning. Verification is controller-owned after a batch settles; m1 is read-only and does not build/lint/test/format. Each batch includes CLI/runtime smoke, not tests alone. Review fixes remain within the same task. Checkpoint accepted batches before later tasks reuse their files; push every commit.

No proof ledgers exist at this base. Retire reader/anchor/tool-command instructions; any retained ledger guidance applies only if a surface has an actual ledger.

## File-by-file adjudication

All source paths below are relative to `tools/`; Python owners are relative to `tools/porydaw_dev/`.

| TypeScript file | Controller decision on m1 proposal | Python owner / deletion |
|---|---|---|
| cli.ts | Agree on console dispatcher, lazy imports, root guard, lane orchestration; disagree on implicit uv sync during warm execution | cli.py |
| build.ts | Agree on merged configuration and streamed log; fix attribution grouping and include Windows .obj outputs | build.py |
| build_output.ts | Agree; preserve actionable compiler/linker/CMake diagnostics and project-warning filtering | build_output.py |
| checks_options.ts | Agree; argparse and terminal Qt split; remove redundant flags | checks.py + cli.py |
| checks_reporter.ts | Agree; fold reporter into runner, remove obsolete CI-grep line | checks.py |
| checks_walls.ts | Agree on deletion; disagree on introducing a persistent duration cache | Delete; manifest order within scheduling classes |
| run_checks.ts | Agree on merged runner and threads; disagree on removing classification validation that can lead to false success; ensure child cleanup on interruption | checks.py |
| format.ts | Agree; changed Swift hunks, whole-file opt-in, Ruff for Python; no compiler-command quoting machinery | format.py |
| local_build_environment.ts | Agree; split Qt ownership from build policy; uv replaces venv marker paths | qt.py + build.py |
| native_build_tool_installers.ts | Agree; privileged/interactive installs become explicit host-prerequisite instructions | Delete |
| native_build_tools.ts | Agree; uv owns Python/Ninja, configure owns compile/link probes | setup.py |
| poryaaaa_source.ts | Agree; shared canonical checkout validation remains, simplify redundant wrapping | poryaaaa.py |
| qml_aot.ts | Agree; retain ratchet semantics and separate baseline command | qml_aot.py |
| qt_version_number_patch.ts | Agree; retain narrowly scoped idempotent Windows importer patch | qt.py |
| qtbridge_surface.ts | Agree; faithful lexer/model and finding-key semantics; no proof tooling | bridge_surface.py |
| setup.ts | Agree on shared build path and four high-level stages; disagree on nested implicitly syncing uv run; explicitly time Qt environment sync | setup.py |
| setup_reporter.ts | Agree; fold stage reporting into setup, remove heartbeat machinery | setup.py |
| setup_swift_test.ts | Agree; removed quoting/installer behavior needs no re-pinned tests | Delete |
| setup_test.ts | Agree on deletion; retain only meaningful Qt selection behavior tests | tools/tests/test_qt.py |
| startup_ab.ts | Agree on alternating launches and stdlib statistics; handle one-sample quartiles explicitly | bench.py |
| startup_bench.ts | Agree on shared measurement; remove compatibility budget default; require --budget-ms with --check; reject nonfinite deadlines/budgets | bench.py |
| swift_toolchain.ts | Agree; CMake owns SWIFTC parsing, retain selected driver paths and pinned Swift validation | build.py + setup.py |
| worktree.ts | Agree; same canonical dependency policy, no stale sync hints or redundant URL override | worktree.py |
| xctrace.ts | Agree; argparse command front end, same JSON metrics and schema semantics | xctrace/cli.py |
| xctrace/compare.ts | Disagree with mixed analysis module; retain separately named comparison concern | xctrace/compare.py |
| xctrace/inline.ts | Disagree with mixed analysis module; retain separately named inline-call concern | xctrace/inline.py |
| xctrace/summarize.ts | Disagree with mixed analysis module; retain separately named summary concern | xctrace/summarize.py |
| xctrace/tables.ts | Agree; merge native export decoding into one owned module; ensure identity cache cannot alias recycled objects | xctrace/export.py |
| xctrace/toc.ts | Agree; merge export metadata, schema precedence and dates into export owner | xctrace/export.py |
| xctrace/xml.ts | Agree; stdlib expat, streamed rows, id/ref identity, unresolved-ref failure and process reap | xctrace/export.py |
| lib/exec.ts | Agree; direct subprocess calls replace shallow wrapper | Delete |

## Tasks and review milestones

1. **Foundation and build** — SDD-track: package/root contract, canonical dependency ownership, platform build correctness and attribution. Write `pyproject.toml`, `.python-version`, lockfile, package init, CLI foundation, `build.py`, `build_output.py`, `qt.py`, `poryaaaa.py`, `setup.py`, `worktree.py`, corresponding meaningful tests. Verify locked sync, root isolation, real debug build/no-op, Swift flag invalidation, Qt selection/patch boundaries and attribution. m1 judges every new file and every source disposition. Checkpoint before adding further CLI commands.
2. **Checks and source guards** — SDD-track: harness process lifetime, fixture isolation, concurrent scheduling and static source lexing. Add checks, formatter, bridge and QML AOT owners; complete their CLI commands. Verify native suite, shell/drawer/roll lanes, bridge/AOT parity, failure/empty/Qt payload selection and formatter changed-hunk behavior. m1 per-file review; checkpoint before further CLI reuse.
3. **Benchmark and Instruments** — SDD-track: subprocess cleanup, deadline correctness, XML identity and weighted aggregation. Add bench and xctrace owners and commands. Verify real native submitted-frame launches and a real trace against the original TS JSON analysis before deleting originals; edge tests for refs, interruption/deadlines and statistical boundaries. m1 per-file review; checkpoint.
4. **Cutover and integration** — Direct mechanical callers plus SDD integration gate: remove all 31 TS files and deno.json/lock; update workflows, hooks, active docs, authorized AGENTS guidance and obsolete proof-command references. Preserve archived docs/plans and external submodule. Verify tools:check, formatting, bridge/AOT, native and QML lanes, isolated environment provisioning, warm offline execution and active-reference sweep. m1 file-by-file integration review, final commit and push.

Source-guard/profiling preservation is judged against original source and actual outputs, not blanket API compatibility. Where an acceptance command uses a transient source or header change, restore that exact task-owned change after observing the result. No user-owned edits are present in this worktree at the base.

## Primary-source references

- uv locking/sync: https://docs.astral.sh/uv/concepts/projects/sync/
- uv entry points: https://docs.astral.sh/uv/concepts/projects/config/#entry-points
- uv build backend: https://docs.astral.sh/uv/concepts/build-backend/
- dependency groups: https://docs.astral.sh/uv/concepts/projects/dependencies/#default-groups
- Python expat: https://docs.python.org/3/library/pyexpat.html

Measured uv bootstrap on this host: verified 0.13.0 ARM64 archive, 14,692,549 downloaded bytes in 0.778226 s. Not a full environment measurement.

## Foundation checkpoint evidence

m1 accepted all 17 foundation files and all 14 foundation TS dispositions after one fix round. Ruff lint/format and 13 behavioral tests passed. Actual Debug build completed, native Swift flag edit/restore rebuilt selectively, and Release setup reused Qt 6.11.2 without a root installer log. A real `Qt6_DIR-NOTFOUND` cache recovered its prior kit; the next build spent 0 s in explicit configure and 0.040 s in Ninja with no compilation. Console smoke distinguished argument failure (2) from corrupt runtime configuration (1); Qt patch smoke preserved CRLF/UTF-8 and was byte-stable on repeat/unrelated headers.

Locked optional-Qt sync completed in 0.15 s from cache. Cold Qt installation was observed separately; its first post-download lookup failed because aqt now uses the `macos` kit directory, then the corrected setup built Release successfully. Windows environment quoting/encoding is source-reviewed only, not executed on this Mac. Keep strict UTF-16LE environment decoding: malformed environment data should fail rather than inject replacement characters into paths.
