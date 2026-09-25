#!/usr/bin/env python3
import argparse
import json
import os
import plistlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "build/porydaw.app/Contents/MacOS/porydaw"
PROBE_SOURCE = Path(__file__).with_name("probe.cpp")
CACHE = Path.home() / "Library/Caches/porydaw-startup-bench"
PROBE = CACHE / "probe.dylib"
SEED = CACHE / "seed.plist"
PROJECT = Path("/Users/spencer/dev/hearth-test")
DOMAINS = ("com.sp3cker.porydaw", "com.sp3cker.porydaw.porydaw")
SONG = "mus_hanabi"
QT_FRAMEWORKS = "/opt/homebrew/lib"


def build_probe():
    if PROBE.exists() and PROBE.stat().st_mtime >= PROBE_SOURCE.stat().st_mtime:
        return
    CACHE.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["clang++", "-std=c++20", "-O2", "-dynamiclib", "-F", QT_FRAMEWORKS,
         "-I/opt/homebrew/include",
         "-framework", "QtCore", "-framework", "QtGui", "-framework", "QtQuick",
         "-framework", "QtQml", str(PROBE_SOURCE), "-o", str(PROBE)],
        check=True)


def export_domain(domain, path):
    result = subprocess.run(["defaults", "export", domain, str(path)], capture_output=True)
    return result.returncode == 0


def import_domain(domain, path):
    subprocess.run(["defaults", "import", domain, str(path)], check=True)


def clear_domain(domain):
    subprocess.run(["defaults", "delete", domain], capture_output=True)


def ensure_seed():
    if SEED.exists():
        return
    with tempfile.NamedTemporaryFile(suffix=".plist") as exported:
        data = {}
        if export_domain(DOMAINS[0], exported.name):
            with open(exported.name, "rb") as handle:
                data = plistlib.load(handle)
    for key in ("windowGeometry", "windowState", "NSOSPLastRootDirectory"):
        data.pop(key, None)
    data["lastProjectDir"] = str(PROJECT)
    data["lastOpenSongs"] = [SONG]
    data["lastSongLabel"] = SONG
    with open(SEED, "wb") as handle:
        plistlib.dump(data, handle, fmt=plistlib.FMT_BINARY)


def launch(scratch, count_allocations):
    output = scratch / "probe.json"
    output.unlink(missing_ok=True)
    env = dict(os.environ)
    env["DYLD_INSERT_LIBRARIES"] = str(PROBE)
    env["PORYDAW_STARTUP_PROBE_OUT"] = str(output)
    env["PORYDAW_STARTUP_PROBE_SETTLE_MS"] = "1000"
    env.pop("PORYDAW_STARTUP_PROBE_COUNT_ALLOCATIONS", None)
    if count_allocations:
        env["PORYDAW_STARTUP_PROBE_COUNT_ALLOCATIONS"] = "1"
    import_domain(DOMAINS[0], SEED)
    clear_domain(DOMAINS[1])
    started = time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
    process = subprocess.Popen([str(APP)], env=env, cwd=scratch,
                               stdout=subprocess.DEVNULL, stderr=scratch.joinpath("stderr.log").open("w"))
    try:
        process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise RuntimeError("porydaw did not exit")
    if not output.exists():
        log = scratch.joinpath("stderr.log").read_text(errors="replace")[-4000:]
        raise RuntimeError(f"probe wrote nothing (exit {process.returncode})\n{log}")
    report = json.loads(output.read_text())
    if report["status"] != "ok" or not report["song_open_frame_ns"]:
        raise RuntimeError(f"startup incomplete: {report}")

    def since_start(key):
        return (report[key] - started) / 1e6

    return {
        "song_ready_ms": since_start("settled_frame_ns"),
        "song_open_ms": since_start("song_open_frame_ns"),
        "first_frame_ms": since_start("first_frame_ns"),
        "qapp_ms": since_start("application_ns"),
        "dyld_ms": since_start("constructor_ns"),
        "cpu_ms": report["cpu_ms"],
        "footprint_mb": report["footprint_bytes"] / 2**20,
        "maxrss_mb": report["maxrss_bytes"] / 2**20,
        "allocations_k": report["allocations"] / 1e3,
        "allocated_mb": report["allocated_bytes"] / 2**20,
        "frames": report["frames"],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--warmup", type=int, default=1)
    arguments = parser.parse_args()
    if not APP.exists():
        sys.exit(f"missing {APP}")
    build_probe()
    if not PROJECT.exists():
        sys.exit(f"missing project {PROJECT}")
    ensure_seed()
    scratch = Path(tempfile.mkdtemp(prefix="porydaw-startup-"))
    backups = {}
    for domain in DOMAINS:
        path = scratch / f"{domain}.backup.plist"
        backups[domain] = path if export_domain(domain, path) else None
    try:
        for _ in range(arguments.warmup):
            launch(scratch, False)
        samples = [launch(scratch, False) for _ in range(arguments.runs)]
        allocation = launch(scratch, True)
    finally:
        for domain, path in backups.items():
            clear_domain(domain)
            if path:
                import_domain(domain, path)
        shutil.rmtree(scratch, ignore_errors=True)
    timing_keys = ("song_ready_ms", "song_open_ms", "first_frame_ms", "qapp_ms", "dyld_ms",
                   "cpu_ms", "footprint_mb", "maxrss_mb")
    for key in timing_keys:
        values = [sample[key] for sample in samples]
        print(f"# {key}: " + " ".join(f"{value:.1f}" for value in values), file=sys.stderr)
        print(f"METRIC {key}={statistics.median(values):.2f}")
    print(f"METRIC allocations_k={allocation['allocations_k']:.1f}")
    print(f"METRIC allocated_mb={allocation['allocated_mb']:.1f}")
    spread = [sample["song_ready_ms"] for sample in samples]
    print(f"ASI song_ready_spread_ms={max(spread) - min(spread):.1f}")


if __name__ == "__main__":
    main()
