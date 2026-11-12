"""Format changed Swift hunks and the Python harness; whole files require opt-in."""

import ast
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from .build import swift_bin_dir

Ranges = list[tuple[int, int]] | None
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def git(args: list[str]) -> str:
    result = subprocess.run(
        ["git", "-c", "core.quotePath=false", *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"git {args[0]} failed: {result.stderr.strip()}")
    return result.stdout


def swift_ranges(diff: str) -> dict[Path, Ranges]:
    changed: dict[Path, Ranges] = {}
    ranges: list[tuple[int, int]] | None = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            filename = line[4:].split("\t", 1)[0]
            if filename.startswith('"'):
                filename = ast.literal_eval(filename)
            if not filename.startswith("b/"):
                raise RuntimeError(f"unexpected Git diff destination: {filename}")
            ranges = []
            changed[Path(filename[2:]).resolve()] = ranges
        elif ranges is not None and (hunk := HUNK.match(line)):
            start = int(hunk[1])
            count = int(hunk[2]) if hunk[2] is not None else 1
            if count:
                ranges.append((start, start + count - 1))
    return changed


def changed_swift(base: str) -> dict[Path, Ranges]:
    since = "HEAD" if base == "HEAD" else git(["merge-base", base, "HEAD"]).strip()
    changed = swift_ranges(
        git(
            [
                "diff",
                "--unified=0",
                "--no-color",
                "--no-ext-diff",
                "--src-prefix=a/",
                "--dst-prefix=b/",
                "--diff-filter=AMR",
                since,
                "--",
                "*.swift",
            ]
        )
    )
    for filename in git(
        ["ls-files", "--others", "--exclude-standard", "-z", "--", "*.swift"]
    ).split("\0"):
        if filename:
            changed[Path(filename).resolve()] = None
    return {path: spans for path, spans in changed.items() if spans is None or spans}


def run(check: bool, base: str, files: list[Path], whole: bool) -> int:
    root = Path.cwd()
    named = [path.resolve() for path in files]
    for path in named:
        if not path.is_relative_to(root):
            raise ValueError(f"format target is outside this worktree: {path}")
    python_files = [str(path) for path in named if path.suffix == ".py"]
    if not named or python_files:
        result = subprocess.run(
            [
                "ruff",
                "format",
                *(["--check"] if check else ["--quiet"]),
                *(
                    python_files
                    or ["tools/porydaw_dev", "tools/tests", "tools/gen_swift_compdb.py"]
                ),
            ],
            check=False,
        )
        if result.returncode:
            return result.returncode
    swift_files = {path for path in named if path.suffix == ".swift"}
    if whole:
        targets: dict[Path, Ranges] = dict.fromkeys(swift_files)
    else:
        targets = changed_swift(base) if not named or swift_files else {}
        if named:
            targets = {
                path: spans for path, spans in targets.items() if path in swift_files
            }
    if not targets:
        return 0
    return check_swift(targets, check, root)


def check_swift(targets: dict[Path, Ranges], check: bool, root: Path) -> int:
    if not targets:
        return 0
    selected = swift_bin_dir()
    driver = (
        str(selected / ("swift.exe" if sys.platform == "win32" else "swift"))
        if selected
        else "swift"
    )
    changed = []
    for path, spans in sorted(targets.items()):
        before = path.read_bytes()
        args = [driver, "format", *([] if check else ["-i"])]
        if spans is not None:
            for start, end in spans:
                args.extend(["--lines", f"{start}:{end}"])
        result = subprocess.run([*args, str(path)], capture_output=True, check=False)
        if result.returncode:
            raise RuntimeError(
                f"{path}: {result.stderr.decode('utf-8', errors='replace').strip()}"
            )
        after = result.stdout if check else path.read_bytes()
        if after != before:
            changed.append(str(path.relative_to(root)))
    if changed:
        if check:
            print(
                "format: changed Swift lines need formatting; rerun format without --check, preserving --base and file arguments",
                file=sys.stderr,
            )
        else:
            print("format: reformatted " + ", ".join(changed))
        if check:
            for path in changed:
                print(f"  {path}", file=sys.stderr)
            return 1
    return 0


def run_staged() -> int:
    root = Path.cwd()
    targets = swift_ranges(
        git(
            [
                "diff",
                "--cached",
                "--unified=0",
                "--no-color",
                "--no-ext-diff",
                "--src-prefix=a/",
                "--dst-prefix=b/",
                "--diff-filter=ACMR",
                "--",
                "*.swift",
            ]
        )
    )
    targets = {path: spans for path, spans in targets.items() if spans}
    python = [
        Path(path)
        for path in git(
            [
                "diff",
                "--cached",
                "--name-only",
                "--diff-filter=ACMR",
                "-z",
                "--",
                "*.py",
            ]
        ).split("\0")
        if path
    ]
    if not targets and not python:
        return 0
    configs = [
        Path(path)
        for path in git(
            [
                "ls-files",
                "--cached",
                "-z",
                "--",
                ".swift-format",
                "*/.swift-format",
                "pyproject.toml",
                "*/pyproject.toml",
                "ruff.toml",
                "*/ruff.toml",
                ".ruff.toml",
                "*/.ruff.toml",
            ]
        ).split("\0")
        if path
    ]
    sources = {*configs, *python, *(path.relative_to(root) for path in targets)}
    with tempfile.TemporaryDirectory(prefix="porydaw-format-index-") as temp:
        snapshot = Path(temp)
        for path in sorted(sources):
            result = subprocess.run(
                ["git", "show", f":{path.as_posix()}"],
                capture_output=True,
                check=False,
            )
            if result.returncode:
                raise RuntimeError(
                    f"cannot read staged {path}: {result.stderr.decode()}"
                )
            destination = snapshot / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(result.stdout)
        if python:
            result = subprocess.run(
                [
                    "ruff",
                    "format",
                    "--check",
                    *(str(snapshot / path) for path in python),
                ],
                cwd=snapshot,
                check=False,
            )
            if result.returncode:
                return result.returncode
        return check_swift(
            {
                snapshot / path.relative_to(root): spans
                for path, spans in targets.items()
            },
            True,
            snapshot,
        )
