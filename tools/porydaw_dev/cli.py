"""One discoverable entry point; command implementations load only when used."""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


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


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="uv run --no-sync dev",
        description="Porydaw development harness. Provision with uv sync --locked before first use, in each new worktree, and after project/lockfile changes.",
    )
    commands = root.add_subparsers(dest="command")
    for name, description in (
        ("build:app", "build application"),
        ("build:checks", "build application, checks and mid2agb"),
    ):
        command = commands.add_parser(name, help=description)
        _config(command)
    command = commands.add_parser(
        "setup",
        help="provision checkout-local Qt and build Release; never run host package managers",
    )
    command.add_argument("--qt-version", type=_qt_version)
    command = commands.add_parser(
        "worktree:create", help="create a linked worktree using shared poryaaaa"
    )
    command.add_argument("name", type=_worktree_name)
    command.add_argument("--base", default="fork-main")
    command = commands.add_parser(
        "qt:patch", help="patch a Windows Qt kit for the Swift importer"
    )
    command.add_argument("prefix", type=lambda value: Path(value).resolve())
    commands.add_parser(
        "checks:backups", help="run standalone Swift backup package tests without Qt"
    )
    commands.add_parser(
        "lsp:swift", help="refresh the Swift compile database and index"
    )
    commands.add_parser(
        "tools:check", help="lint, format-check and test the Python harness"
    )
    return root


def main() -> int:
    root_parser = parser()
    options = root_parser.parse_args()
    if options.command is None:
        root_parser.print_help()
        return 0
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(errors="replace")
    repo = Path(__file__).resolve().parents[2]
    try:
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
        match options.command:
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
                    ["ruff", "check", "tools/porydaw_dev", "tools/tests"],
                    ["ruff", "format", "--check", "tools/porydaw_dev", "tools/tests"],
                    [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests"],
                ):
                    result = subprocess.run(args, check=False)
                    if result.returncode:
                        return result.returncode
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"{options.command}: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print(f"{options.command}: interrupted", file=sys.stderr)
        return 130
    return 0
