"""Fresh process measurements through native submitted-frame receipts."""

import codecs
import json
import os
import queue
import statistics
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from .process import cancel_on_signals, stop_child

MARKER = "PORYDAW_STARTUP_TRACE "


@dataclass(slots=True)
class Outcome:
    ms: float | None = None
    stages: dict[str, float] = field(default_factory=dict)
    message: str = ""


def _read_stderr(stream, events: queue.Queue) -> None:
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    pending = ""
    try:
        while chunk := stream.read(65536):
            pending += decoder.decode(chunk)
            while "\n" in pending:
                line, pending = pending.split("\n", 1)
                events.put((line.rstrip("\r"), time.perf_counter()))
        pending += decoder.decode(b"", final=True)
        if pending:
            events.put((pending.rstrip("\r"), time.perf_counter()))
    except (OSError, ValueError) as error:
        events.put((f"stderr read failed: {error}", time.perf_counter()))
    finally:
        events.put((None, time.perf_counter()))


def measure(binary: Path, options, run_number: int) -> Outcome:
    args = [str(binary)]
    if options.project is not None:
        args += ["--project", str(options.project)]
    if options.song is not None:
        args += ["--song", options.song]
    events = queue.Queue()
    stages = {}
    diagnostics = []
    started = time.perf_counter()
    try:
        child = subprocess.Popen(
            args,
            env={**os.environ, "PORYDAW_STARTUP_TRACE": "1"},
            stdin=subprocess.DEVNULL,
            stdout=None,
            stderr=subprocess.PIPE,
            bufsize=0,
            start_new_session=os.name == "posix",
        )
    except OSError as error:
        return Outcome(message=f"LAUNCH failure: {error}")
    reader = threading.Thread(
        target=_read_stderr, args=(child.stderr, events), daemon=True
    )
    deadline = started + options.timeout_ms / 1000
    outcome = Outcome(stages=stages)
    exit_deadline = None
    try:
        reader.start()
        while True:
            try:
                line, received = events.get_nowait()
            except queue.Empty:
                now = time.perf_counter()
                remaining = min(deadline, exit_deadline or deadline) - now
                if remaining <= 0:
                    outcome.message = (
                        f"EXIT before {options.until}: code {child.returncode}"
                        if exit_deadline is not None and exit_deadline < deadline
                        else f"TIMEOUT: no {options.until} within {options.timeout_ms:g} ms"
                    )
                    break
                try:
                    line, received = events.get(timeout=min(remaining, 0.05))
                except queue.Empty:
                    if exit_deadline is None and child.poll() is not None:
                        exit_deadline = min(deadline, time.perf_counter() + 0.25)
                    continue
            if received >= deadline:
                outcome.message = (
                    f"TIMEOUT: no {options.until} within {options.timeout_ms:g} ms"
                )
                break
            if line is None:
                outcome.message = (
                    f"EXIT/closed stderr before {options.until}: code {child.poll()}"
                )
                break
            if not line.startswith(MARKER):
                diagnostics.append(line)
                continue
            stage = line[len(MARKER) :]
            ms = (received - started) * 1000
            stages[stage] = ms
            if stage == options.until:
                outcome.ms = ms
                break
    finally:
        try:
            stop_child(child)
        finally:
            if reader.ident is not None:
                reader.join(timeout=0.25)
            child.stderr.close()
            while not events.empty():
                line, _ = events.get_nowait()
                if line is not None and not line.startswith(MARKER):
                    diagnostics.append(line)
            if diagnostics:
                print(f"--- run {run_number} app stderr ---", file=sys.stderr)
                print("\n".join(diagnostics), file=sys.stderr)
    return outcome


def distribution(samples: list[float]) -> tuple[float, float, float]:
    if len(samples) == 1:
        return samples[0], samples[0], samples[0]
    quartiles = statistics.quantiles(samples, n=4, method="inclusive")
    return quartiles[0], statistics.median(samples), quartiles[2]


def _summary(label: str, outcomes: list[Outcome], options) -> bool:
    values = [outcome.ms for outcome in outcomes if outcome.ms is not None]
    failures = len(outcomes) - len(values)
    if values:
        print(
            f"{label}: {len(values)}/{len(outcomes)} {options.until}; median {statistics.median(values):.2f} ms, min {min(values):.2f} ms, max {max(values):.2f} ms"
        )
    else:
        print(f"{label}: no {options.until} samples ({len(outcomes)} runs)")
    misses = (
        sum(value >= options.budget_ms for value in values)
        if options.budget_ms is not None
        else 0
    )
    if options.budget_ms is not None:
        print(
            f"  Budget <{options.budget_ms:g} ms: {misses} misses; {failures} failed launches"
        )
    return bool(outcomes) and failures == 0 and misses == 0


@cancel_on_signals()
def run(options) -> int:
    from .build import artifact

    if options.command == "bench:startup:ab":
        binaries = options.binaries
    else:
        binaries = [
            (
                "app",
                options.binary
                or artifact(
                    Path(__file__).resolve().parents[2] / "build/release", "porydaw"
                ),
            )
        ]
    for label, binary in binaries:
        if not binary.is_file():
            raise ValueError(
                f"{label}: executable unavailable: {binary}; build first with uv run --no-sync dev build:app --release"
            )
    print(
        f"Metric: spawn to {options.until} native frameSwapped receipt (queued presentation, not display scanout or audio readiness)"
    )
    print(
        "App selection:",
        json.dumps(
            {
                "project": str(options.project) if options.project else None,
                "song": options.song,
            }
        ),
    )
    if options.command == "bench:startup:ab":
        outcomes = {label: [] for label, _ in binaries}
        for round_number in range(1, options.runs + 1):
            order = binaries if round_number % 2 else reversed(binaries)
            for label, binary in order:
                outcome = measure(binary, options, round_number)
                outcomes[label].append(outcome)
                print(
                    f"run {round_number} {label}: {outcome.ms:.2f} ms"
                    if outcome.ms is not None
                    else f"run {round_number} {label}: {outcome.message}"
                )
                time.sleep(0.4)
        for label, _ in binaries:
            values = [item.ms for item in outcomes[label] if item.ms is not None]
            if values:
                p25, median, p75 = distribution(values)
                print(
                    f"{label}: n={len(values)} median {median:.2f}, p25 {p25:.2f}, p75 {p75:.2f}, min {min(values):.2f}, max {max(values):.2f} ms; failed {len(outcomes[label]) - len(values)}"
                )
            else:
                print(f"{label}: no samples; failed {len(outcomes[label])}")
        if options.stages:
            stage_names = dict.fromkeys(
                stage
                for items in outcomes.values()
                for item in items
                for stage in item.stages
            )
            print("Median ms since spawn by native stage:")
            for stage in stage_names:
                cells = []
                for label, _ in binaries:
                    values = [
                        item.stages[stage]
                        for item in outcomes[label]
                        if stage in item.stages
                    ]
                    cells.append(
                        f"{label}={statistics.median(values):.2f}"
                        if values
                        else f"{label}=—"
                    )
                print(f"  {stage}: " + ", ".join(cells))
        return (
            2
            if any(item.ms is None for items in outcomes.values() for item in items)
            else 0
        )
    outcomes = []
    for number in range(1, options.runs + 1):
        outcome = measure(binaries[0][1], options, number)
        outcomes.append(outcome)
        print(
            f"Run {number} ({'first' if number == 1 else 'warm'}): {outcome.ms:.2f} ms"
            if outcome.ms is not None
            else f"Run {number}: {outcome.message}"
        )
    _summary("First run", outcomes[:1], options)
    if len(outcomes) > 1:
        _summary("Warm runs", outcomes[1:], options)
    passed = _summary("All runs (including first)", outcomes, options)
    if any(outcome.ms is None for outcome in outcomes):
        return 2
    return 1 if options.check and not passed else 0
