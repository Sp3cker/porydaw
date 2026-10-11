"""Create a worktree without duplicating the canonical poryaaaa checkout."""

import subprocess
from pathlib import Path

from . import poryaaaa


def create(name: str, base: str) -> None:
    main = poryaaaa.main_root(Path.cwd())
    poryaaaa.git(main, "check-ref-format", "--branch", base)
    poryaaaa.git(main, "show-ref", "--verify", f"refs/heads/{base}")
    branch = f"feature/{name}"
    path = main / ".worktrees" / name
    branch_exists = (
        subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"],
            cwd=main,
            check=False,
        ).returncode
        == 0
    )
    if branch_exists or path.exists():
        raise RuntimeError(f"worktree branch or path already exists: {branch}, {path}")
    package = poryaaaa.ensure_initialized(main)
    commit = poryaaaa.recorded_commit(main)
    subprocess.run(
        [
            "git",
            "-c",
            "submodule.recurse=false",
            "worktree",
            "add",
            "-b",
            branch,
            str(path),
            f"refs/heads/{base}",
        ],
        cwd=main,
        check=True,
    )
    subprocess.run(
        ["git", "update-index", "--cacheinfo", f"160000,{commit},external/poryaaaa"],
        cwd=path,
        check=True,
    )
    print(f"worktree: adopted canonical poryaaaa {commit} in new index")
    print(f"worktree: created {path}")
    print(f"worktree: branch {branch} from {base}")
    print(f"worktree: builds use shared submodule {package}")
    print(
        f"worktree: provision its Python environment once: cd {path}; uv sync --locked"
    )
