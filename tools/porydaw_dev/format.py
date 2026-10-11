"""Format changed Swift hunks and the Python harness; whole files require opt-in."""

import ast
import re
import subprocess
import sys
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


def changed_swift(base: str) -> dict[Path, Ranges]:
    since = "HEAD" if base == "HEAD" else git(["merge-base", base, "HEAD"]).strip()
    diff = git(
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
    changed: dict[Path, Ranges] = {}
    ranges: list[tuple[int, int]] | None = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            filename = line[4:]
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
