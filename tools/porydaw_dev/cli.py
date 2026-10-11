"""One discoverable entry point; command implementations load only when used."""

import argparse
import math
import os
import re
import subprocess
import sys
from pathlib import Path

CHECK_LANES = {
    "checks": ("porydaw_checks", "native logic and production startup"),
    "checks:qml": ("editor_qml_tests", "QML drawer"),
    "checks:qml-roll": ("roll_qml_tests", "production Swift roll"),
    "checks:shell": ("shell_qml_tests", "production shell"),
}


def _config(parser: argparse.ArgumentParser) -> None:
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument("--release", action="store_true")
    choice.add_argument("--asan", action="store_true")


def _qt_version(value: str) -> str:
    if not re.fullmatch(r"6\.11\.\d+", value):
        raise argparse.ArgumentTypeError("Qt version must be 6.11.<patch>")
    return value


def _worktree_name(value: str) -> str:
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", value):
        raise argparse.ArgumentTypeError("worktree name must be lowercase kebab-case")
    return value


def _nonempty(value: str) -> str:
    if not value:
        raise argparse.ArgumentTypeError("requires a nonempty value")
    return value


def _pool(value: str) -> int:
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "pool must be an integer from 1 to 64"
        ) from error
    if not 1 <= number <= 64:
        raise argparse.ArgumentTypeError("pool must be an integer from 1 to 64")
    return number


def _positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("requires a positive integer")
    return number


def _positive_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("requires a positive finite number")
    return number


def _binary_pair(value: str):
    label, separator, binary = value.partition("=")
    if not separator or not label or label.startswith("-") or not binary:
        raise argparse.ArgumentTypeError("binary must be label=executable")
    return label, Path(binary).resolve()


def _format_file(value: str) -> Path:
    path = Path(value).resolve()
    if path.suffix not in (".swift", ".py"):
        raise argparse.ArgumentTypeError("format accepts only .swift and .py files")
    return path


def _run_checks(options: argparse.Namespace, qt: tuple[str, ...] | None) -> int:
    from . import bridge_surface, checks, qml_aot
    from .build import artifact, run_build

    selection = checks.Options(
        tuple(options.filter),
        tuple(options.exclude),
        options.all,
        options.no_windowing_checks,
        options.verbose,
        options.pool,
        qt,
    )
    try:
        if options.command == "checks:run":
            return checks.run(options.binary, selection)
        if bridge_surface.run(quiet=True):
            return 1
        config = (
            "asan"
            if options.asan
            else "release"
            if options.release or sys.platform == "win32"
            else "debug"
        )
        binary = CHECK_LANES[options.command][0]
        targets = [binary, "mid2agb"]
        if options.command == "checks":
            targets.append("all_aotstats")
            if "production-startup" not in selection.exclusions and (
                not selection.filters
                or any(value in "production-startup" for value in selection.filters)
            ):
                targets.insert(0, "porydaw")
        directory = run_build(targets, config, checks=True)
        if options.command == "checks" and qml_aot.run(config, options.verbose):
            return 1
        return checks.run(artifact(directory, binary), selection)
    except checks.UsageError as error:
        print(f"{options.command}: {error}", file=sys.stderr)
        return 2


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="uv run --no-sync dev",
        description="Porydaw development harness. Provision with uv sync --locked before first use, in each new worktree, and after project/lockfile changes.",
        allow_abbrev=False,
    )
    commands = root.add_subparsers(dest="command")
    for name, description in (
        ("build:app", "build application"),
        ("build:checks", "build application, checks and mid2agb"),
    ):
        command = commands.add_parser(name, help=description, allow_abbrev=False)
        _config(command)
    for name, (_, description) in {
        **CHECK_LANES,
        "checks:run": ("", "prebuilt checks binary without building"),
    }.items():
        command = commands.add_parser(
            name, help="run " + description, allow_abbrev=False
        )
        if name == "checks:run":
            command.add_argument("binary", type=lambda value: Path(value).absolute())
        else:
            _config(command)
        command.add_argument(
            "--filter",
            action="append",
            type=_nonempty,
            default=[],
            help="repeatable substring; includes opt-in checks",
        )
        command.add_argument(
            "--exclude",
            action="append",
            type=_nonempty,
            default=[],
            help="repeatable exact harness name",
        )
        selection = command.add_mutually_exclusive_group()
        selection.add_argument(
            "--all", action="store_true", help="include opt-in checks"
        )
        selection.add_argument("--no-windowing-checks", action="store_true")
        command.add_argument(
            "--verbose",
            "-v",
            action="store_true",
            help="print passing checks' raw output",
        )
        command.add_argument("--pool", type=_pool, default=min(12, os.cpu_count() or 1))
        command.epilog = "Terminal --qt <args...> forwards opaque Qt arguments to exactly one selected qt-test harness."
    for name, description in (
        ("checks:bridge", "check Swift/QML bridge surface (read-only)"),
        ("bridge:baseline", "record current bridge findings"),
        ("checks:qml-aot", "build and ratchet production QML AOT"),
        ("qml-aot:baseline", "build and record current AOT baseline"),
    ):
        command = commands.add_parser(name, help=description, allow_abbrev=False)
        if name in ("checks:qml-aot", "qml-aot:baseline"):
            _config(command)
            command.add_argument("--verbose", "-v", action="store_true")
    command = commands.add_parser(
        "format",
        help="format changed Swift hunks and Python; --whole requires named files",
        allow_abbrev=False,
    )
    command.add_argument("--check", action="store_true")
    command.add_argument("--base", type=_nonempty, default="HEAD")
    command.add_argument("--whole", action="store_true")
    command.add_argument("files", nargs="*", type=_format_file)
    command = commands.add_parser(
        "setup",
        help="provision checkout-local Qt and build Release; never run host package managers",
        allow_abbrev=False,
    )
    command.add_argument("--qt-version", type=_qt_version)
    command = commands.add_parser(
        "worktree:create",
        help="create a linked worktree using shared poryaaaa",
        allow_abbrev=False,
    )
    command.add_argument("name", type=_worktree_name)
    command.add_argument("--base", default="fork-main")
    command = commands.add_parser(
        "qt:patch",
        help="patch a Windows Qt kit for the Swift importer",
        allow_abbrev=False,
    )
    command.add_argument("prefix", type=lambda value: Path(value).resolve())
    commands.add_parser(
        "checks:backups",
        help="run standalone Swift backup package tests without Qt",
        allow_abbrev=False,
    )
    commands.add_parser(
        "lsp:swift",
        help="refresh the Swift compile database and index",
        allow_abbrev=False,
    )
    commands.add_parser(
        "tools:check",
        help="lint, format-check and test the Python harness",
        allow_abbrev=False,
    )
    for name in ("bench:startup", "bench:startup:ab"):
        command = commands.add_parser(
            name, help="measure native submitted-frame receipts", allow_abbrev=False
        )
        command.add_argument("--runs", type=_positive_int, default=11)
        command.add_argument(
            "--until",
            choices=("first-frame", "chrome-frame", "workspace-frame", "editor-frame"),
            default="first-frame",
        )
        command.add_argument("--project", type=lambda value: Path(value).resolve())
        command.add_argument("--song", type=_nonempty)
        command.add_argument("--timeout-ms", type=_positive_float, default=10000)
        if name == "bench:startup":
            command.add_argument("--binary", type=lambda value: Path(value).resolve())
            command.add_argument("--budget-ms", type=_positive_float)
            command.add_argument("--check", action="store_true")
        else:
            command.add_argument("--stages", action="store_true")
            command.add_argument("binaries", nargs="+", type=_binary_pair)
        command.epilog = "Requires an existing Release executable. Stops only its spawned apps. Frame receipts do not prove physical display or audio readiness."
    command = commands.add_parser(
        "xctrace",
        help="Instruments record / summarize / compare / inline",
        allow_abbrev=False,
    )
    command.add_argument(
        "mode", nargs="?", choices=("record", "summarize", "compare", "inline")
    )
    command.add_argument("args", nargs=argparse.REMAINDER)
    return root


def main() -> int:
    root_parser = parser()
    raw = sys.argv[1:]
    qt = None
    if raw and raw[0] in (*CHECK_LANES, "checks:run") and "--qt" in raw:
        separator = raw.index("--qt")
        qt, raw = tuple(raw[separator + 1 :]), raw[:separator]
        if not qt:
            root_parser.error("--qt requires a nonempty terminal payload")
    options = root_parser.parse_args(raw)
    if getattr(options, "asan", False) and sys.platform == "win32":
        root_parser.error("--asan is not supported on Windows")
    if options.command == "format" and options.whole and not options.files:
        root_parser.error("--whole requires named files")
    if (
        options.command == "bench:startup"
        and options.check
        and options.budget_ms is None
    ):
        root_parser.error("--check requires an explicit positive --budget-ms")
    if options.command == "bench:startup:ab":
        labels = [label for label, _ in options.binaries]
        if len(labels) < 2 or len(set(labels)) != len(labels):
            root_parser.error("A/B requires at least two binaries with distinct labels")
    if options.command is None:
        root_parser.print_help()
        return 0
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(errors="replace")
    caller = Path.cwd()
    repo = Path(__file__).resolve().parents[2]
    try:
        if options.command not in {"bench:startup", "bench:startup:ab", "xctrace"}:
            actual = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=True,
            ).stdout.strip()
            if Path(actual).resolve() != repo:
                raise RuntimeError(
                    f"harness belongs to {repo}, not cwd's repository {actual}; sync and run the owning worktree's environment"
                )
        os.chdir(repo)
        if options.command in (*CHECK_LANES, "checks:run"):
            return _run_checks(options, qt)
        match options.command:
            case "bench:startup" | "bench:startup:ab":
                from .bench import run

                return run(options)
            case "xctrace":
                from .xctrace.cli import run

                os.chdir(caller)
                return run([options.mode, *options.args] if options.mode else [])
            case "build:app" | "build:checks":
                from .build import run_build

                targets = (
                    ["porydaw"]
                    if options.command == "build:app"
                    else ["porydaw", "porydaw_checks", "mid2agb"]
                )
                run_build(
                    targets,
                    "asan"
                    if options.asan
                    else "release"
                    if options.release
                    else "debug",
                    checks=True if options.command == "build:checks" else None,
                )
            case "checks:bridge" | "bridge:baseline":
                from .bridge_surface import run

                return run(update=options.command == "bridge:baseline")
            case "checks:qml-aot" | "qml-aot:baseline":
                from .build import run_build
                from .qml_aot import run

                config = (
                    "asan"
                    if options.asan
                    else "release"
                    if options.release
                    else "debug"
                )
                run_build(["porydaw", "all_aotstats"], config)
                return run(
                    config,
                    options.verbose,
                    update=options.command == "qml-aot:baseline",
                )
            case "format":
                from .format import run

                return run(options.check, options.base, options.files, options.whole)
            case "setup":
                from .setup import run

                run(options.qt_version)
            case "worktree:create":
                from .worktree import create

                create(options.name, options.base)
            case "qt:patch":
                from .qt import patch_version_number

                patch_version_number(options.prefix)
            case "checks:backups":
                return subprocess.run(
                    [
                        "swift",
                        "test",
                        "--package-path",
                        "src/swift/backups",
                        "--scratch-path",
                        "build/backups",
                    ],
                    check=False,
                ).returncode
            case "lsp:swift":
                return subprocess.run(
                    [sys.executable, "tools/gen_swift_compdb.py", "--index"],
                    check=False,
                ).returncode
            case "tools:check":
                for args in (
                    [
                        "ruff",
                        "check",
                        "tools/porydaw_dev",
                        "tools/tests",
                        "tools/gen_swift_compdb.py",
                    ],
                    [
                        "ruff",
                        "format",
                        "--check",
                        "tools/porydaw_dev",
                        "tools/tests",
                        "tools/gen_swift_compdb.py",
                    ],
                    [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests"],
                ):
                    result = subprocess.run(args, check=False)
                    if result.returncode:
                        return result.returncode
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"{options.command}: {error}", file=sys.stderr)
        return 2 if options.command in ("bench:startup", "bench:startup:ab") else 1
    except KeyboardInterrupt:
        print(f"{options.command}: interrupted", file=sys.stderr)
        return 130
    return 0
