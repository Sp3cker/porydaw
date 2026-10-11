"""Explicit, checkout-local provisioning; host package managers are never run."""

import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from . import build, poryaaaa, qt


def check_host_tools() -> list[str]:
    problems = []
    hints = {
        "darwin": "Install Xcode command-line tools and CMake: xcode-select --install; brew install cmake",
        "linux": "Install a C/C++ toolchain and CMake with your distribution package manager (Debian/Ubuntu: sudo apt-get install build-essential cmake)",
        "win32": "Install CMake and Visual Studio C++ Build Tools: winget install Kitware.CMake; winget install Microsoft.VisualStudio.2022.BuildTools",
    }
    if sys.platform == "win32":
        build.prepare_windows_env()
    sdk_ready = True
    if sys.platform == "darwin":
        selected = subprocess.run(
            ["/usr/bin/xcode-select", "-p"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        sdk_ready = selected.returncode == 0
        if not sdk_ready:
            problems.append(f"Xcode command-line tools are missing. {hints['darwin']}")
    for program in (
        ["git", "cmake"] if sys.platform == "win32" else ["git", "cmake", "cc", "c++"]
    ):
        if not shutil.which(program):
            problems.append(f"{program} is missing. {hints.get(sys.platform, '')}")
        elif program in {"cc", "c++"} and sdk_ready:
            result = subprocess.run(
                [program, "--version"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            if result.returncode:
                problems.append(
                    f"{program} cannot run: {result.stderr.strip()}. {hints.get(sys.platform, '')}"
                )
    if shutil.which("cmake"):
        result = subprocess.run(
            ["cmake", "--version"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        version = re.search(r"cmake version (\d+)\.(\d+)", result.stdout)
        if (
            result.returncode
            or not version
            or tuple(map(int, version.groups())) < (3, 24)
        ):
            problems.append(
                f"CMake >=3.24 required; detected {(result.stdout + result.stderr).strip()}"
            )
    directory = build.swift_bin_dir()
    suffix = ".exe" if sys.platform == "win32" else ""
    compiler = str(directory / f"swiftc{suffix}") if directory else f"swiftc{suffix}"
    driver = str(directory / f"swift{suffix}") if directory else f"swift{suffix}"
    for args in ([compiler, "--version"], [driver, "format", "--version"]):
        try:
            result = subprocess.run(
                args,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
        except FileNotFoundError:
            problems.append(
                f"{args[0]} is missing. Install Swift >=6.4: https://www.swift.org/install/"
            )
            continue
        output = (result.stdout + result.stderr).strip()
        if result.returncode:
            problems.append(f"{' '.join(args)} cannot run: {output}")
        elif args[0] == compiler:
            version = re.search(r"Swift version (\d+)\.(\d+)", output)
            if not version or tuple(map(int, version.groups())) < (6, 4):
                problems.append(
                    f"Swift >=6.4 required; detected {output}. https://www.swift.org/install/"
                )
    return problems


def run(version: str | None = None) -> None:
    started = time.perf_counter()
    current = "host tools"

    def stage(number, label, action):
        nonlocal current
        current = label
        start = time.perf_counter()
        print(f"setup: [{number}/4] {label}", flush=True)
        result = action()
        print(
            f"setup: [{number}/4] {label} - ok ({time.perf_counter() - start:.2f}s)",
            flush=True,
        )
        return result

    def host():
        problems = check_host_tools()
        if problems:
            raise RuntimeError(
                "host prerequisites:\n"
                + "\n".join(f"  {problem}" for problem in problems)
            )

    def install_qt():
        configured = build.read_cache(Path("build/release")).get("Qt6_DIR")
        prefix = qt.local_prefix(Path.cwd(), version, configured)
        if prefix is None:
            environment_started = time.perf_counter()
            subprocess.run(
                [os.environ.get("UV", "uv"), "sync", "--locked", "--group", "qt"],
                check=True,
            )
            print(
                f"setup: Qt Python environment {time.perf_counter() - environment_started:.2f}s",
                flush=True,
            )
            host, architecture, _ = qt.installation()
            installer_dir = Path.cwd() / ".cache/setup"
            installer_dir.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "aqt",
                    "install-qt",
                    "--outputdir",
                    str(qt.install_root(Path.cwd())),
                    host,
                    "desktop",
                    version or qt.QT_MINOR,
                    architecture,
                ],
                check=True,
                cwd=installer_dir,
            )
            prefix = qt.local_prefix(Path.cwd(), version)
            if prefix is None:
                raise RuntimeError("Qt install did not provide Qt6Config.cmake")
        else:
            print(f"setup: reuse Qt {prefix}", flush=True)
        if sys.platform == "win32":
            qt.patch_version_number(prefix)
        return prefix

    try:
        stage(1, "host tools", host)
        stage(2, "shared poryaaaa", lambda: poryaaaa.ensure_initialized(Path.cwd()))
        prefix = stage(3, "Qt", install_qt)
        stage(
            4,
            "build",
            lambda: build.run_build(
                ["porydaw"], "release", checks=True, qt_prefix=prefix
            ),
        )
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise RuntimeError(f"{current}: {error}") from error
    launch = (
        "open build/release/porydaw.app"
        if sys.platform == "darwin"
        else ".\\build\\release\\porydaw.exe"
        if sys.platform == "win32"
        else "./build/release/porydaw"
    )
    print(f"setup: ready in {time.perf_counter() - started:.2f}s; launch: {launch}")
