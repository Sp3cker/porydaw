"""The main checkout owns the single shared poryaaaa dependency."""

import re
import subprocess
from pathlib import Path


def git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "--no-optional-locks", *args],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git {args[0]} failed")
    return result.stdout.strip()


def main_root(repo: Path) -> Path:
    return Path(
        git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    ).parent


def recorded_commit(main: Path) -> str:
    entry = git(main, "ls-files", "--stage", "--", "external/poryaaaa")
    match = re.fullmatch(r"160000 ([0-9a-f]+) 0\texternal/poryaaaa", entry)
    if not match:
        raise RuntimeError("main checkout must record one resolved poryaaaa gitlink")
    return match[1]


def package_dir(repo: Path) -> Path:
    main = main_root(repo)
    checkout = main / "external/poryaaaa"
    package = checkout / "packages/poryaaaa"
    if (
        not (checkout / ".git").exists()
        or not (package / "plugin/porydaw/CMakeLists.txt").is_file()
    ):
        raise RuntimeError(
            f"initialize shared poryaaaa in {main}: git submodule update --init --recursive external/poryaaaa"
        )
    expected = recorded_commit(main)
    actual = git(checkout, "rev-parse", "HEAD")
    if actual != expected:
        raise RuntimeError(
            f"shared poryaaaa revision mismatch: main records {expected}, checkout has {actual}"
        )
    status = git(checkout, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        raise RuntimeError(f"shared poryaaaa checkout is dirty:\n{status}")
    return package.resolve()


def ensure_initialized(repo: Path) -> Path:
    main = main_root(repo)
    checkout = main / "external/poryaaaa"
    if not (checkout / ".git").exists():
        if checkout.exists() and any(checkout.iterdir()):
            raise RuntimeError(
                f"refusing to initialize nonempty dependency directory: {checkout}"
            )
        subprocess.run(
            [
                "git",
                "submodule",
                "update",
                "--init",
                "--recursive",
                "external/poryaaaa",
            ],
            cwd=main,
            check=True,
        )
    return package_dir(repo)
