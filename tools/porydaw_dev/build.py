"""Ninja configuration, Swift invalidation and actionable build attribution."""

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from functools import cache
from pathlib import Path, PureWindowsPath

from . import poryaaaa, qt
from .build_output import summarize


def build_dir(config: str) -> Path:
    return Path("build") / config


def artifact(directory: Path, target: str) -> Path:
    if sys.platform == "win32":
        return directory / f"{target}.exe"
    if sys.platform == "darwin" and target == "porydaw":
        return directory / "porydaw.app/Contents/MacOS/porydaw"
    return directory / target


def swift_bin_dir() -> Path | None:
    version = Path(".swift-version").read_text(encoding="utf-8").strip()
    if sys.platform == "darwin":
        config = Path.home() / ".swiftly/config.json"
        if config.exists():
            selected = json.loads(config.read_text(encoding="utf-8")).get("inUse")
            if selected is not None and selected != version:
                raise RuntimeError(
                    f"swiftly in-use toolchain {selected} differs from .swift-version {version}; run: swiftly use {version}"
                )
        directory = Path.home() / ".swiftly/bin"
        return directory if (directory / "swiftc").is_file() else None
    if sys.platform == "win32":
        return (
            Path(os.environ["LOCALAPPDATA"])
            / f"Programs/Swift/Toolchains/{version}+Asserts/usr/bin"
        )
    return None


@cache
def prepare_windows_env() -> None:
    if sys.platform != "win32":
        return
    vswhere = (
        Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
        / "Microsoft Visual Studio/Installer/vswhere.exe"
    )
    hint = "Visual Studio C++ tools are required; install Microsoft.VisualStudio.2022.BuildTools"
    if not vswhere.is_file():
        raise RuntimeError(hint)
    result = subprocess.run(
        [
            str(vswhere),
            "-utf8",
            "-latest",
            "-products",
            "*",
            "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-property",
            "installationPath",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"{hint}; vswhere failed: {result.stderr.strip()}")
    found = result.stdout.strip()
    if not found:
        raise RuntimeError(hint)
    command = f'call "{found}\\Common7\\Tools\\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul && set'
    result = subprocess.run(
        f'cmd.exe /d /u /s /c "{command}"', capture_output=True, check=False
    )
    if result.returncode:
        detail = result.stderr.decode("utf-16-le", errors="replace").strip()
        raise RuntimeError(f"VsDevCmd failed ({result.returncode}): {detail}. {hint}")
    for line in result.stdout.decode("utf-16-le").splitlines():
        key, separator, value = line.partition("=")
        if separator and key:
            os.environ[key] = value
    version = Path(".swift-version").read_text(encoding="utf-8").strip()
    root = Path(os.environ["LOCALAPPDATA"]) / "Programs/Swift"
    compiler = swift_bin_dir()
    runtime = root / f"Runtimes/{version}/usr/bin"
    sdk = root / f"Platforms/{version}/Windows.platform/Developer/SDKs/Windows.sdk"
    if (
        compiler is None
        or not (compiler / "swiftc.exe").is_file()
        or not runtime.is_dir()
        or not sdk.is_dir()
    ):
        raise RuntimeError(
            f"Swift {version} toolchain, runtime and SDK are required under {root}"
        )
    os.environ["SDKROOT"] = str(sdk)
    os.environ["PATH"] = f"{compiler};{runtime};{os.environ['PATH']}"


def read_cache(directory: Path) -> dict[str, str]:
    path = directory / "CMakeCache.txt"
    if not path.exists():
        return {}
    cache = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(("#", "//")):
            continue
        key, separator, value = line.partition("=")
        if separator and ":" in key:
            cache[key.split(":", 1)[0]] = value
    return cache


def configure_args(
    directory: Path,
    config: str,
    package: Path,
    checks: bool | None,
    cache: dict[str, str],
    prefix: Path | None,
) -> list[str]:
    args = [
        "cmake",
        "-S",
        ".",
        "-B",
        str(directory),
        "-G",
        "Ninja",
        f"-DCMAKE_BUILD_TYPE={'Release' if config == 'release' else 'Debug'}",
        f"-DPORYDAW_ASAN={'ON' if config == 'asan' else 'OFF'}",
        f"-DPORYAAAA_DIR={package}",
    ]
    if checks is not None:
        args.append(f"-DPORYDAW_BUILD_CHECKS={'ON' if checks else 'OFF'}")
    configured = cache.get("Qt6_DIR", "")
    usable = configured and not configured.endswith("-NOTFOUND")
    if prefix is None and not usable:
        prefix = qt.local_prefix(Path.cwd())
    if prefix is not None:
        args.extend(
            [
                "-UQt6*_DIR",
                f"-DCMAKE_PREFIX_PATH={prefix}",
                f"-DQt6_DIR:PATH={prefix / 'lib/cmake/Qt6'}",
            ]
        )
    elif usable:
        args.append(f"-DQt6_DIR:PATH={configured}")
        if "CMAKE_PREFIX_PATH" in cache:
            args.append(f"-DCMAKE_PREFIX_PATH={cache['CMAKE_PREFIX_PATH']}")
    compiler = swift_bin_dir()
    if compiler is not None:
        args.append(
            f"-DCMAKE_Swift_COMPILER={compiler / ('swiftc.exe' if sys.platform == 'win32' else 'swiftc')}"
        )
        if config == "asan" and sys.platform == "darwin":
            args.extend(
                f"-DCMAKE_{language}_COMPILER={compiler / program}"
                for language, program in (
                    ("C", "clang"),
                    ("CXX", "clang++"),
                    ("OBJCXX", "clang++"),
                )
            )
    return args


def needs_configure(
    directory: Path, cache: dict[str, str], args: list[str]
) -> tuple[bool, bool]:
    requested = {}
    for arg in args:
        if arg.startswith("-D"):
            key, _, value = arg[2:].partition("=")
            requested[key.split(":", 1)[0]] = value
    compilers = {
        key: value
        for key, value in requested.items()
        if re.fullmatch(r"CMAKE_(C|CXX|OBJCXX|Swift)_COMPILER", key)
    }

    def matches(key: str, value: str) -> bool:
        actual = cache.get(key)
        if actual is None:
            return False
        if key in compilers or key in {"PORYAAAA_DIR", "Qt6_DIR"}:
            path_type = PureWindowsPath if sys.platform == "win32" else Path
            return path_type(actual) == path_type(value)
        return actual == value

    compiler_changed = bool(cache) and any(
        not matches(key, value) for key, value in compilers.items()
    )
    relevant = {
        key: value
        for key, value in requested.items()
        if key not in {"CMAKE_PREFIX_PATH"} and key not in compilers
    }
    needed = (
        not (directory / "build.ninja").is_file()
        or compiler_changed
        or any(not matches(key, value) for key, value in relevant.items())
    )
    return needed, compiler_changed


def swift_edges(directory: Path) -> list[tuple[str, list[Path], str]]:
    path = directory / "build.ninja"
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    edges = []
    marker = ": Swift_COMPILER__"
    for index, line in enumerate(lines):
        if not line.startswith("build ") or marker not in line:
            continue
        outputs, rule = line[6:].split(marker, 1)
        directives = []
        cursor = index + 1
        while cursor < len(lines) and lines[cursor].startswith("  "):
            directive = lines[cursor][2:]
            if re.match(r"(?:FLAGS|INCLUDES|DEFINES|CONFIG) = ", directive):
                directives.append(directive)
            cursor += 1
        objects = [
            directory / name
            for name in outputs.split()
            if name.endswith((".o", ".obj"))
        ]
        edges.append((rule.split()[0], objects, "\n".join(directives)))
    return edges


def reconcile_swift_objects(directory: Path) -> bool:
    edges = swift_edges(directory)
    if not edges:
        return False
    stamp = directory / ".porydaw-swift-commands.json"
    try:
        recorded = json.loads(stamp.read_text(encoding="utf-8"))
    except (FileNotFoundError, UnicodeDecodeError, json.JSONDecodeError):
        recorded = {}
    if not isinstance(recorded, dict):
        recorded = {}
    signatures = {}
    dropped = False
    for rule, objects, command in edges:
        signatures[rule] = hashlib.sha256(command.encode()).hexdigest()
        if recorded.get(rule) == signatures[rule]:
            continue
        for path in objects:
            if path.exists():
                path.unlink()
                dropped = True
    if recorded == signatures:
        return dropped
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=directory,
            prefix=".swift-commands-",
            delete=False,
        ) as output:
            temporary = Path(output.name)
            output.write(json.dumps(signatures, indent=2) + "\n")
        os.replace(temporary, stamp)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return dropped


def ninja_snapshot(directory: Path) -> dict[str, tuple[int, int, str, str]]:
    path = directory / ".ninja_log"
    if not path.exists():
        return {}
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        start, end, mtime, output, digest = line.split("\t")
        result[output] = int(start), int(end), mtime, digest
    return result


def changed_edges(before: dict, after: dict) -> list[tuple[int, list[str]]]:
    groups: dict[tuple[int, int, str], list[str]] = {}
    for output, record in after.items():
        if before.get(output) == record:
            continue
        start, end, _, digest = record
        groups.setdefault((start, end, digest), []).append(output)
    return sorted(
        ((end - start, sorted(outputs)) for (start, end, _), outputs in groups.items()),
        key=lambda entry: (-entry[0], entry[1]),
    )


def run_build(
    targets: list[str],
    config: str,
    checks: bool | None = None,
    qt_prefix: Path | None = None,
) -> Path:
    if config == "asan" and sys.platform == "win32":
        raise RuntimeError("ASAN builds are not supported on Windows")
    directory = build_dir(config)
    cache = read_cache(directory)
    if cache and cache.get("CMAKE_GENERATOR") != "Ninja":
        raise RuntimeError(
            f"{directory} uses {cache.get('CMAKE_GENERATOR', 'an unknown generator')}; only Ninja is supported. Remove that build tree and rerun."
        )
    directory.mkdir(parents=True, exist_ok=True)
    log_path = directory / "build.log"
    started = time.perf_counter()
    phases: dict[str, float] = {}
    phase = "environment"

    def timed(name, action):
        nonlocal phase
        phase = name
        start = time.perf_counter()
        try:
            return action()
        finally:
            phases[name] = phases.get(name, 0.0) + time.perf_counter() - start

    with log_path.open("w", encoding="utf-8") as log:

        def command(args):
            log.write(f"\n>>> {shlex.join(args)}\n")
            log.flush()
            subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, check=True)

        try:
            timed("environment", prepare_windows_env)
            package = timed("poryaaaa", lambda: poryaaaa.package_dir(Path.cwd()))
            args = configure_args(directory, config, package, checks, cache, qt_prefix)
            needed, fresh = needs_configure(directory, cache, args)
            if needed:
                timed(
                    "configure-explicit",
                    lambda: command(args + (["--fresh"] if fresh else [])),
                )
            else:
                phases["configure-explicit"] = 0.0
            build_args = [
                "cmake",
                "--build",
                str(directory),
                "-j",
                str(os.cpu_count() or 1),
            ]
            if targets:
                build_args.extend(["--target", *targets])
            timed("reconcile", lambda: reconcile_swift_objects(directory))
            before = ninja_snapshot(directory)
            timed("ninja", lambda: command(build_args))
            after = ninja_snapshot(directory)
            edges = changed_edges(before, after)
            if timed("reconcile", lambda: reconcile_swift_objects(directory)):
                timed("ninja", lambda: command(build_args))
                edges.extend(changed_edges(after, ninja_snapshot(directory)))
            edges.sort(key=lambda entry: (-entry[0], entry[1]))
        except subprocess.CalledProcessError as error:
            log.flush()
            output = log_path.read_text(encoding="utf-8", errors="replace")
            summary = summarize(output, Path.cwd(), directory.resolve())
            failed = (
                f": {', '.join(summary.failed_steps)}" if summary.failed_steps else ""
            )
            print(
                f"build: {phase} failed ({config}, {time.perf_counter() - started:.1f}s){failed}",
                file=sys.stderr,
            )
            for detail in (
                summary.errors
                or [line for line in output.splitlines() if line.strip()][-15:]
            )[:20]:
                print(f"  {detail}", file=sys.stderr)
            print(
                f"  full log: {log_path} (read it; rebuilding adds no detail)",
                file=sys.stderr,
            )
            raise SystemExit(error.returncode or 1) from error
        finally:
            log.write(
                "\nBuild phases (seconds): "
                + ", ".join(f"{name}={seconds:.3f}" for name, seconds in phases.items())
                + "\n"
            )
        log.flush()
        summary = summarize(
            log_path.read_text(encoding="utf-8", errors="replace"),
            Path.cwd(),
            directory.resolve(),
        )
        log.write(
            "\nNative commands changed during this invocation (overlapping durations, not wall-time):\n"
        )
        for duration, outputs in edges:
            log.write(f"{duration} ms\t{', '.join(outputs)}\n")
    state = "up to date" if summary.steps == 0 else f"ok ({summary.steps} steps)"
    target = f" {artifact(directory, targets[0])}" if targets else ""
    print(f"build: {state} ({config}, {time.perf_counter() - started:.1f}s){target}")
    print(
        "build: phases "
        + ", ".join(f"{name} {seconds:.3f}s" for name, seconds in phases.items())
    )
    if edges:
        print(
            "build: slowest commands "
            + "; ".join(f"{duration}ms {outputs[0]}" for duration, outputs in edges[:3])
        )
    if summary.warnings:
        print(
            f"build: {len(summary.warnings)} warning(s) in project sources",
            file=sys.stderr,
        )
        for warning in summary.warnings[:20]:
            print(f"  {warning}", file=sys.stderr)
        if len(summary.warnings) > 20:
            print(f"  {len(summary.warnings) - 20} more in {log_path}", file=sys.stderr)
    return directory
