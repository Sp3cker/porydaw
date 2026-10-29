"""Qt kit locations and the narrowly scoped Windows importer patch."""

import platform
import re
import sys
from pathlib import Path

QT_MINOR = "6.12"


def installation() -> tuple[str, str, str]:
    machine = platform.machine().lower()
    if sys.platform == "darwin":
        return "mac", "clang_64", "macos"
    if sys.platform == "linux":
        if machine in {"x86_64", "amd64"}:
            return "linux", "linux_gcc_64", "gcc_64"
        if machine in {"aarch64", "arm64"}:
            return "linux_arm64", "linux_gcc_arm64", "gcc_arm64"
    if sys.platform == "win32" and machine in {"x86_64", "amd64"}:
        return "windows", "win64_msvc2022_64", "msvc2022_64"
    raise RuntimeError(f"unsupported Qt host: {sys.platform}/{machine}")


def install_root(repo: Path) -> Path:
    host, arch, _ = installation()
    return repo / ".cache/setup/qt" / f"{host}-{arch}"


def local_prefix(
    repo: Path,
    version: str | None = None,
    configured_dir: str | None = None,
) -> Path | None:
    root = install_root(repo)
    if not root.exists():
        return None
    _, _, kit = installation()
    prefixes = []
    for entry in root.iterdir():
        if not re.fullmatch(r"6\.12\.\d+", entry.name):
            continue
        if version is not None and entry.name != version:
            continue
        prefix = entry / kit
        if (prefix / "lib/cmake/Qt6/Qt6Config.cmake").is_file():
            prefixes.append(prefix)
    if version is None and configured_dir is not None:
        configured = Path(configured_dir).resolve()
        for prefix in prefixes:
            if (prefix / "lib/cmake/Qt6").resolve() == configured:
                return prefix
    return max(
        prefixes,
        key=lambda path: tuple(map(int, path.parent.name.split("."))),
        default=None,
    )


def patch_version_number(prefix: Path) -> None:
    header = prefix / "include/QtCore/qversionnumber.h"
    source = header.read_bytes()
    old = b"return compareThreeWay(lhs, rhs);"
    fixed = b"""const auto order = compareThreeWay(lhs, rhs);
            return order < 0 ? std::strong_ordering::less
                 : order > 0 ? std::strong_ordering::greater
                             : std::strong_ordering::equal;"""
    if old in source:
        newline = b"\r\n" if b"\r\n" in source else b"\n"
        header.write_bytes(source.replace(old, fixed.replace(b"\n", newline), 1))
