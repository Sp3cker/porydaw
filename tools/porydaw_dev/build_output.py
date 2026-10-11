"""Reduce native tool output; the complete log remains the source of detail."""

import os
import re
from dataclasses import dataclass, field
from pathlib import Path

ESCAPE = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]")
GROUP_TAG = re.compile(r"\s*\[#[\w-]+\]\s*$", re.ASCII)
STEP = re.compile(r"^\[\d+/\d+\] (.*)$", re.ASCII)
LOCATED = re.compile(
    r"^(.+?):(\d+)(?::(\d+))?: (fatal error|error|warning): (.*)$", re.ASCII
)
MSVC = re.compile(
    r"^(.+?)\((\d+)(?:,(\d+))?\)\s*: (fatal error|error|warning) ([A-Z]+\d+): (.*)$",
    re.ASCII,
)
TOOL = re.compile(r"^(Error|Warning): (?:(.+?):(\d+):(?:(\d+):)? )?(.*)$", re.ASCII)
BARE = re.compile(
    r"^(?:<unknown>:0: )?(?:[\w.+-]+: )?(fatal error|error|warning): (.*)$", re.ASCII
)
CMAKE = re.compile(
    r"^CMake (Error|Warning)( \(dev\))?(?: at (.+?):(\d+) \((\w+)\))?:\s*(.*)$",
    re.ASCII,
)
LINKER = re.compile(
    r'^Undefined symbols for architecture |^\s*"[^"]+", referenced from:$|^ld: |^duplicate symbol |undefined reference to |multiple definition of '
)
DRIVER_FAILURE = re.compile(r"command failed|failed with exit code|subcommand failed")


@dataclass(frozen=True)
class Summary:
    failed_steps: list[str]
    errors: list[str]
    warnings: list[str]
    steps: int


@dataclass
class Step:
    description: str = ""
    lines: list[str] = field(default_factory=list)
    failed: bool = False


def _repo_path(path: str, repo: Path, base: Path) -> str:
    absolute = Path(path) if Path(path).is_absolute() else base / path
    try:
        relative = os.path.relpath(absolute, repo)
    except ValueError:
        return str(absolute)
    return (
        str(absolute)
        if relative == ".." or relative.startswith(f"..{os.sep}")
        else relative
    )


def _owned(path: str) -> bool:
    if Path(path).is_absolute():
        return False
    parts = re.split(r"[/\\]", path)
    return (
        not parts[0].startswith("build")
        and parts[0] not in {"external", ".cache"}
        and "_deps" not in parts
    )


def _diagnostic(line: str) -> tuple[str | None, str, str] | None:
    match = MSVC.match(line)
    if match:
        path, row, column, severity, code, message = match.groups()
        message = f"{code}: {message}"
    else:
        match = LOCATED.match(line)
        if match:
            path, row, column, severity, message = match.groups()
        else:
            match = TOOL.match(line)
            if match:
                severity, path, row, column, message = match.groups()
                severity = severity.lower()
                if path is None:
                    return None, severity, line
            else:
                match = BARE.match(line)
                if match:
                    severity, _ = match.groups()
                    return (
                        None,
                        "warning" if severity == "warning" else "error",
                        GROUP_TAG.sub("", line),
                    )
                return None
    text = f"{row}{':' + column if column else ''}: {severity}: {GROUP_TAG.sub('', message)}"
    return path, "warning" if severity == "warning" else "error", text


def _render(
    diagnostic: tuple[str | None, str, str], repo: Path, base: Path
) -> tuple[str, bool]:
    path, _, text = diagnostic
    if path is None:
        return text, False
    if re.search(r"^<|\s@", path):
        return f"{path}:{text}", False
    path = _repo_path(path, repo, base)
    return f"{path}:{text}", _owned(path)


def summarize(output: str, repo: Path, build: Path) -> Summary:
    lines = ESCAPE.sub("", output).splitlines()
    steps = [Step()]
    count = 0
    skip_command = False
    for line in lines:
        match = STEP.match(line)
        if match:
            count += 1
            steps.append(Step(match[1]))
            continue
        if line.startswith("FAILED: "):
            steps[-1].failed = True
            skip_command = True
            continue
        if skip_command:
            skip_command = False
            continue
        if not line.startswith("ninja: "):
            steps[-1].lines.append(line)
    errors: list[str] = []
    warnings: list[str] = []
    index = 0
    while index < len(lines):
        match = CMAKE.match(lines[index])
        index += 1
        if not match:
            continue
        kind, dev, path, row, command, inline = match.groups()
        body = [inline] if inline else []
        while index < len(lines) and (not lines[index] or lines[index][0].isspace()):
            if lines[index].strip():
                body.append(lines[index].strip())
            index += 1
        where = _repo_path(path, repo, repo) if path else None
        message = f"CMake {kind}{f' at {where}:{row} ({command})' if where else ''}:"
        message += "".join(f"\n  {line}" for line in body[:8])
        if kind == "Error":
            errors.append(message)
        elif not dev and (where is None or _owned(where)):
            warnings.append(message)
    cmake_failed = bool(errors)
    failed = [step for step in steps if step.failed]
    for step in failed:
        primary: list[str] = []
        driver: list[str] = []
        for line in step.lines:
            if LINKER.search(line):
                primary.append(line.strip())
                continue
            diagnostic = _diagnostic(line)
            if diagnostic and diagnostic[1] == "error":
                text, _ = _render(diagnostic, repo, build)
                (driver if DRIVER_FAILURE.search(text) else primary).append(text)
        errors.extend(
            primary
            or driver
            or (
                []
                if cmake_failed
                else [line.rstrip() for line in step.lines if line.strip()][-15:]
            )
        )
    for line in lines:
        diagnostic = _diagnostic(line)
        if diagnostic and diagnostic[1] == "warning":
            text, owned = _render(diagnostic, repo, build)
            if owned:
                warnings.append(text)
    return Summary(
        [step.description or "configure" for step in failed],
        list(dict.fromkeys(errors)),
        list(dict.fromkeys(warnings)),
        count,
    )
