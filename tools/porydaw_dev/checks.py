"""Run manifest-declared checks with private fixtures and owned child lifetimes."""

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath

from .process import cancel_on_signals

DIAGNOSTIC = re.compile(
    r"^(?:QWARN|QCRITICAL|QFATAL)\s*:|^(?:file:|qrc:)|\b(?:Reference|Type)Error:",
)


class UsageError(ValueError):
    """A check invocation cannot select or execute a valid manifest."""


@dataclass(frozen=True, slots=True)
class Options:
    filters: tuple[str, ...] = ()
    exclusions: tuple[str, ...] = ()
    all: bool = False
    no_windowing: bool = False
    verbose: bool = False
    pool: int = min(12, os.cpu_count() or 1)
    qt: tuple[str, ...] | None = None


@dataclass(frozen=True, slots=True)
class Check:
    name: str
    argv: tuple[str, ...]
    binary: str
    windowing: str
    framework: str
    opt_in: bool
    platforms: tuple[str, ...] | None
    environment: dict[str, str]
    optional_environment: dict[str, str]
    scratch_kind: str
    fixture_kind: str
    fixture_files: tuple[str, ...]


def _strings(value: object, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise UsageError(f"manifest {field} must be an array of strings")
    return tuple(value)


def _environment(value: object, field: str) -> dict[str, str]:
    if not isinstance(value, dict) or any(
        not isinstance(key, str) or not isinstance(item, str)
        for key, item in value.items()
    ):
        raise UsageError(f"manifest {field} must map strings to strings")
    return value


def parse_manifest(document: object) -> list[Check]:
    if not isinstance(document, dict) or not isinstance(document.get("checks"), list):
        raise UsageError("unsupported check manifest; expected checks array")
    checks = []
    names = set()
    classifications = {
        "binary": ("application", "checks"),
        "windowing": ("offscreen", "window-system"),
        "framework": ("qt-test", "process"),
        "scratchKind": ("existing-directory", "must-not-exist-path", "unused"),
        "fixtureRootKind": ("decomp-project", "songs-mk-project", "none"),
    }
    for entry in document["checks"]:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("name"), str)
            or not entry["name"]
        ):
            raise UsageError("manifest check must have a nonempty name")
        name = entry["name"]
        if name in names:
            raise UsageError(f"duplicate manifest check name: {name}")
        names.add(name)
        for field, supported in classifications.items():
            if entry.get(field) not in supported:
                raise UsageError(f"{name}: unsupported {field}: {entry.get(field)!r}")
        if not isinstance(entry.get("optIn"), bool):
            raise UsageError(f"{name}: missing opt-in classification")
        platforms = (
            None
            if "platforms" not in entry
            else _strings(entry["platforms"], "platforms")
        )
        if platforms is not None and any(
            item not in ("macos", "windows", "linux") for item in platforms
        ):
            raise UsageError(f"{name}: unsupported platform")
        fixture_files = _strings(entry.get("fixtureFiles"), "fixtureFiles")
        for filename in fixture_files:
            posix, windows = PurePosixPath(filename), PureWindowsPath(filename)
            if (
                not filename
                or posix.is_absolute()
                or windows.drive
                or windows.root
                or ".." in posix.parts
                or ".." in windows.parts
            ):
                raise UsageError(
                    f"{name}: fixture must be a relative in-root path: {filename!r}"
                )
        if fixture_files and (
            entry["fixtureRootKind"] == "none"
            or entry["scratchKind"] != "existing-directory"
        ):
            raise UsageError(
                f"{name}: fixtures require a declared root and existing-directory scratch"
            )
        environment = _environment(entry.get("environment", {}), "environment")
        if "QT_QPA_PLATFORM" in environment:
            raise UsageError(
                f"{name}: declare windowing instead of setting QT_QPA_PLATFORM"
            )
        checks.append(
            Check(
                name,
                _strings(entry.get("argv"), "argv"),
                entry["binary"],
                entry["windowing"],
                entry["framework"],
                entry["optIn"],
                platforms,
                environment,
                _environment(
                    entry.get("optionalArgumentEnvironment", {}),
                    "optionalArgumentEnvironment",
                ),
                entry["scratchKind"],
                entry["fixtureRootKind"],
                fixture_files,
            )
        )
    return checks


def host() -> str:
    return {"darwin": "macos", "win32": "windows"}.get(sys.platform, sys.platform)


def select(
    checks: list[Check], options: Options, platform: str, visual_baselines: bool
) -> list[Check]:
    known = {check.name for check in checks}
    unknown = set(options.exclusions) - known
    if unknown:
        raise UsageError("no harness matches exclusion: " + ", ".join(sorted(unknown)))

    def matches(check: Check) -> bool:
        return not options.filters or any(
            value in check.name for value in options.filters
        )

    selected = [
        check
        for check in checks
        if (check.platforms is None or platform in check.platforms)
        and (not options.no_windowing or check.windowing == "offscreen")
        and (not check.opt_in or options.all or options.filters)
        and matches(check)
        and check.name not in options.exclusions
    ]
    if (
        not options.all
        and not options.no_windowing
        and not options.filters
        and not visual_baselines
    ):
        selected = [check for check in selected if not check.name.startswith("visual-")]
    if not selected:
        unsupported = [
            check
            for check in checks
            if matches(check)
            and check.platforms is not None
            and platform not in check.platforms
        ]
        if unsupported:
            raise UsageError(
                f"{len(unsupported)} check(s) registered but none runnable on {platform}"
            )
        raise UsageError(
            "selection resolved to zero runnable checks"
            + (": " + ", ".join(options.filters) if options.filters else "")
        )
    if options.qt is not None:
        if not options.qt:
            raise UsageError("--qt requires a nonempty terminal Qt payload")
        if len(selected) != 1 or selected[0].framework != "qt-test":
            raise UsageError(
                "--qt requires exactly one qt-test harness; selected: "
                + ", ".join(check.name for check in selected)
            )
    return selected


def arguments(
    check: Check, scratch: Path, mid2agb: Path, options: Options, qml: bool
) -> list[str]:
    args = []
    for argument in check.argv:
        if argument == "{scratch}":
            args.append(str(scratch))
        elif argument == "{mid2agb}":
            args.append(str(mid2agb))
        elif argument in check.optional_environment:
            if value := os.environ.get(check.optional_environment[argument]):
                args.append(value)
        else:
            args.append(argument)
    if options.qt is not None:
        args.extend(["--qt", *options.qt])
        if not any(
            token == "-maxwarnings" or token.startswith("-maxwarnings=")
            for token in options.qt
        ):
            args.extend(["-maxwarnings", "0"])
    elif check.framework == "qt-test" and check.binary != "application":
        args.extend(["--qt", *(["-v2"] if qml else []), "-maxwarnings", "0"])
    return args


def environment(check: Check) -> dict[str, str]:
    platform = "offscreen"
    if check.windowing == "window-system":
        if sys.platform == "linux" and not os.environ.get("DISPLAY"):
            raise RuntimeError(
                f"{check.name} requires a window system, but DISPLAY is unset"
            )
        platform = {"darwin": "cocoa", "win32": "windows", "linux": "xcb"}.get(
            sys.platform
        )
        if platform is None:
            raise RuntimeError(f"window system unsupported on {sys.platform}")
    result = {
        **os.environ,
        "ASAN_OPTIONS": os.environ.get("ASAN_OPTIONS", "detect_leaks=0"),
        "PORYDAW_AUDIO_BACKEND": "null",
        "QT_FORCE_STDERR_LOGGING": "1",
        **check.environment,
        "QT_QPA_PLATFORM": platform,
    }
    if platform == "offscreen":
        result["QT_QPA_PLATFORMTHEME"] = ""
    return result


@dataclass(frozen=True, slots=True)
class Result:
    code: int
    output: str
    duration: float
    timed_out: bool = False


class Processes:
    def __init__(self, timeout: float = 90, grace: float = 5):
        self.timeout, self.grace = timeout, grace
        self.lock = threading.Lock()
        self.stopped = False
        self.children: set[subprocess.Popen] = set()

    @staticmethod
    def signal(child: subprocess.Popen, force: bool = False) -> None:
        if child.poll() is not None and not (force and os.name == "posix"):
            return
        try:
            if os.name == "posix":
                os.killpg(child.pid, signal.SIGKILL if force else signal.SIGTERM)
            elif force:
                child.kill()
            else:
                child.terminate()
        except ProcessLookupError:
            pass

    def cancel(self) -> None:
        with self.lock:
            self.stopped = True
            children = tuple(self.children)
        for child in children:
            self.signal(child)
        deadline = time.monotonic() + self.grace
        for child in children:
            try:
                child.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                pass
            self.signal(child, force=True)

    def run(
        self, binary: Path, args: list[str], env: dict[str, str], output_path: Path
    ) -> Result:
        started = time.monotonic()
        timed_out = False
        with output_path.open("wb") as output:
            with self.lock:
                if self.stopped:
                    return Result(130, "cancelled", 0)
                child = subprocess.Popen(
                    [str(binary), *args],
                    env=env,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    start_new_session=os.name == "posix",
                )
                self.children.add(child)
            try:
                try:
                    child.wait(timeout=self.timeout)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    self.signal(child)
                    try:
                        child.wait(timeout=self.grace)
                    except subprocess.TimeoutExpired:
                        self.signal(child, force=True)
                        child.wait()
            finally:
                if child.poll() is None:
                    self.signal(child, force=True)
                    child.wait()
                elif os.name == "posix":
                    self.signal(child, force=True)
                with self.lock:
                    self.children.discard(child)
        return Result(
            child.returncode,
            output_path.read_text(encoding="utf-8", errors="replace"),
            time.monotonic() - started,
            timed_out,
        )


def _file(path: Path, description: str) -> Path:
    if not path.is_file():
        raise UsageError(f"missing {description}: {path}")
    return path.resolve()


def _beside(directory: Path, candidates: tuple[str, ...], description: str) -> Path:
    for filename in candidates:
        if (directory / filename).is_file():
            return (directory / filename).resolve()
    raise UsageError(f"missing {description} beside the build: {directory}")


@cancel_on_signals()
def run(binary: Path, options: Options) -> int:
    build_root = binary.absolute().parent.resolve()
    qml = binary.name.endswith("_qml_tests") or binary.name.endswith("_qml_tests.exe")
    binary = _file(binary, "checks binary")
    try:
        manifest = subprocess.run(
            [str(binary), "--manifest"],
            env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
            capture_output=True,
            timeout=90,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{binary} --manifest timed out after 90s") from error
    if manifest.returncode:
        raise UsageError(
            "checks --manifest failed: "
            + manifest.stderr.decode("utf-8", errors="replace").strip()
        )
    try:
        checks = parse_manifest(json.loads(manifest.stdout))
    except ValueError as error:
        raise UsageError(f"invalid check manifest: {error}") from error
    root = Path(__file__).resolve().parents[2]
    visual = root / "src/checks/fixtures/visual"
    has_baselines = visual.is_dir() and any(
        path.is_dir() and path.name.startswith(host() + "-")
        for path in visual.iterdir()
    )
    selected = select(checks, options, host(), has_baselines)
    mid2agb = _beside(build_root, ("mid2agb", "mid2agb.exe"), "in-tree mid2agb")
    app = (
        _beside(
            build_root,
            ("porydaw", "porydaw.exe", "porydaw.app/Contents/MacOS/porydaw"),
            "production application",
        )
        if any(check.binary == "application" for check in selected)
        else None
    )
    if (
        not options.all
        and not options.no_windowing
        and not options.filters
        and not has_baselines
    ):
        print(
            f"checks: no reviewed {host()} visual baselines; skipping visual-* (use --filter visual)"
        )
    started = time.monotonic()
    processes = Processes()
    failures = []
    print(
        f"checks: {len(selected)}/{len(checks)} registered harnesses selected on {host()}"
    )
    with tempfile.TemporaryDirectory(prefix="porydaw-checks-") as temporary:
        temp = Path(temporary)

        def execute(index: int, check: Check) -> Result:
            scratch = temp / f"scratch-{index}"
            try:
                if check.scratch_kind == "existing-directory":
                    scratch.mkdir()
                fixture = {
                    "decomp-project": "decompproject",
                    "songs-mk-project": "songsmkproject",
                }.get(check.fixture_kind)
                for filename in check.fixture_files:
                    source = _file(
                        root / "src/checks/fixtures" / fixture / filename,
                        f"{check.name} fixture",
                    )
                    destination = scratch / filename
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, destination)
                executable = app if check.binary == "application" else binary
                return processes.run(
                    executable,
                    arguments(check, scratch, mid2agb, options, qml),
                    environment(check),
                    temp / f"output-{index}.log",
                )
            except (OSError, RuntimeError, UsageError) as error:
                return Result(1, str(error), 0)

        for windowing, pool in (("offscreen", options.pool), ("window-system", 1)):
            executor = ThreadPoolExecutor(max_workers=pool)
            try:
                futures = {
                    executor.submit(execute, index, check): check
                    for index, check in enumerate(selected)
                    if check.windowing == windowing
                }
                for future in as_completed(futures):
                    check = futures[future]
                    result = future.result()
                    failed = result.code != 0 or result.timed_out
                    if failed:
                        failures.append(check.name)
                        reason = (
                            "timeout" if result.timed_out else f"exit {result.code}"
                        )
                        print(
                            f"FAIL {check.name} ({result.duration:.2f}s, {reason})",
                            file=sys.stderr,
                        )
                        print(
                            result.output,
                            end="" if result.output.endswith("\n") else "\n",
                            file=sys.stderr,
                        )
                    else:
                        if options.verbose or options.qt is not None:
                            print(
                                result.output,
                                end="" if result.output.endswith("\n") else "\n",
                            )
                            print(f"PASS {check.name} ({result.duration:.2f}s)")
                        else:
                            for line in result.output.splitlines():
                                if DIAGNOSTIC.search(line):
                                    print(line)
            except BaseException:
                processes.cancel()
                raise
            finally:
                executor.shutdown(wait=True, cancel_futures=True)
    print(
        f"checks: {len(selected) - len(failures)} passed, {len(failures)} failed ({time.monotonic() - started:.2f}s)"
    )
    if failures:
        print("checks: failed: " + ", ".join(sorted(failures)), file=sys.stderr)
    return 1 if failures else 0
