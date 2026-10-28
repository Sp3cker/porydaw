#!/usr/bin/env python3
"""Index current Ninja Swift compile jobs without changing real build outputs."""

import argparse
import json
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from porydaw_dev.build import read_cache

REMAP_KEYS = {"object", "swift-dependencies", "dependencies", "diagnostics"}


@dataclass(frozen=True)
class CompileJob:
    directory: Path
    tokens: list[str]
    sources: tuple[Path, ...]

    @property
    def name(self) -> str:
        return self.tokens[self.tokens.index("-module-name") + 1]


def compile_jobs(build: Path) -> list[CompileJob]:
    ninja = read_cache(build)["CMAKE_MAKE_PROGRAM"]
    result = subprocess.run(
        [ninja, "-t", "compdb", "-x"],
        cwd=build,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    jobs = []
    for entry in json.loads(result.stdout):
        tokens = shlex.split(entry["command"])
        if not tokens or Path(tokens[0]).name not in {"swiftc", "swiftc.exe"}:
            continue
        if "-c" not in tokens:
            continue
        directory = Path(entry["directory"]).resolve()
        sources = tuple(
            (directory / token).resolve()
            for token in tokens[1:]
            if token.endswith(".swift")
        )
        if sources:
            jobs.append(CompileJob(directory, tokens, sources))
    if not jobs:
        raise RuntimeError(
            f"no Swift compile commands in {build / 'build.ninja'}; build the Debug app first"
        )
    return jobs


def compiler_version(job: CompileJob) -> str:
    result = subprocess.run(
        [job.tokens[0], "--version"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return result.stdout.splitlines()[0].strip()


def index_command(job: CompileJob, store: Path) -> list[str]:
    scratch = store / "objs" / job.name
    scratch.mkdir(parents=True, exist_ok=True)
    result = []
    tokens = iter(job.tokens)
    for token in tokens:
        if token == "-emit-module-path":
            result += [token, str(scratch / Path(next(tokens)).name)]
        elif token == "-output-file-map":
            original = job.directory / next(tokens)
            data = json.loads(original.read_text(encoding="utf-8"))
            for entry in data.values():
                for key in REMAP_KEYS & entry.keys():
                    entry[key] = str(scratch / Path(entry[key]).name)
            remapped = scratch / "output-file-map.json"
            remapped.write_text(json.dumps(data), encoding="utf-8")
            result += [token, str(remapped)]
        else:
            result.append("-Onone" if token == "-O" else token)
    return result + ["-index-store-path", str(store), "-index-ignore-system-modules"]


def check_fresh(build: Path, jobs: list[CompileJob]) -> bool:
    stamp = build / "indexstore/swiftc-stamp.txt"
    if not stamp.exists():
        print("no Swift index store; run: uv run --no-sync dev lsp:swift")
        return False
    if stamp.read_text(encoding="utf-8").strip() != compiler_version(jobs[0]):
        print("Swift toolchain changed; run: uv run --no-sync dev lsp:swift")
        return False
    inputs = [build / "build.ninja", build / "compile_commands.json", Path(__file__)]
    inputs += [source for job in jobs for source in job.sources]
    stale = [
        str(path) for path in inputs if path.stat().st_mtime > stamp.stat().st_mtime
    ]
    if stale:
        print(
            f"stale Swift index ({len(stale)} newer inputs); run: uv run --no-sync dev lsp:swift"
        )
        return False
    print(f"Swift index fresh ({sum(len(job.sources) for job in jobs)} files)")
    return True


def run(build: Path, indexing: bool, checking: bool) -> int:
    jobs = compile_jobs(build)
    if checking:
        return 0 if check_fresh(build, jobs) else 1
    store = build / "indexstore"
    compdb = build / "compile_commands.json"
    entries = json.loads(compdb.read_text(encoding="utf-8"))
    replacements = {}
    for job in jobs:
        tokens = job.tokens
        if indexing:
            tokens = tokens + [
                "-index-store-path",
                str(store),
                "-index-ignore-system-modules",
            ]
        for source in job.sources:
            replacements[str(source)] = {
                "directory": str(job.directory),
                "command": shlex.join(tokens),
                "file": str(source),
            }
    updated = []
    for entry in entries:
        source = str((Path(entry["directory"]) / entry["file"]).resolve())
        if entry["file"].endswith(".swift"):
            if replacement := replacements.pop(source, None):
                updated.append({**entry, **replacement})
        else:
            updated.append(entry)
    updated.extend(replacements.values())
    compdb.write_text(json.dumps(updated, indent=2) + "\n", encoding="utf-8")
    fixed = sum(len(job.sources) for job in jobs)
    print(f"fixed {fixed} Swift entries in {compdb}")
    if not indexing:
        return 0
    failures = []
    for job in jobs:
        print(f"indexing {job.name} ...", flush=True)
        result = subprocess.run(
            index_command(job, store),
            cwd=job.directory,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if result.returncode:
            failures.append(job.name)
            print(f"FAILED {job.name}:\n{result.stderr[-3000:]}", file=sys.stderr)
    print(f"indexed {len(jobs) - len(failures)}/{len(jobs)} targets -> {store}")
    if failures:
        return 1
    (store / "swiftc-stamp.txt").write_text(
        compiler_version(jobs[0]) + "\n", encoding="utf-8"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "build_dir",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "build/debug",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--index", action="store_true")
    mode.add_argument("--check", action="store_true")
    options = parser.parse_args()
    try:
        return run(options.build_dir.resolve(), options.index, options.check)
    except (
        OSError,
        RuntimeError,
        ValueError,
        KeyError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"Swift index: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
