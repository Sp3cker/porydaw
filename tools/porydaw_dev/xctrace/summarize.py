"""Profile weighting and signpost pairing with explicit interval attribution."""

import json
import math
import statistics
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from . import export


@dataclass(frozen=True, slots=True)
class Options:
    run: int = 1
    schema: str | None = None
    interval: tuple[float, float] | None = None
    binary: str | None = None
    thread: str | None = None


@dataclass(frozen=True, slots=True)
class Interval:
    start: float | None = None
    end: float | None = None
    source: str = "whole-run"

    def contains(self, epoch: float) -> bool:
        return self.start is None or self.start <= epoch <= self.end

    def json(self):
        return (
            None
            if self.start is None
            else {"start": self.start, "end": self.end, "source": self.source}
        )


def format_number(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def interval_label(interval: dict | None) -> str:
    if interval is None or interval["start"] is None:
        return "whole run"
    return f"{format_number(interval['start'])},{format_number(interval['end'])} ({interval['source']})"


def resolve_interval(trace: str, explicit=None) -> Interval:
    if explicit is not None:
        return Interval(*explicit, "flag")
    candidates = [Path(trace + ".json")]
    if trace.endswith(".trace"):
        candidates.append(Path(trace[:-6] + ".json"))
    for path in candidates:
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise ValueError(f"bad sidecar {path}: {error}") from error
        if not isinstance(data, dict):
            raise ValueError(f"bad sidecar {path}: expected epoch interval object")
        start, end = (
            data.get("startEpoch", data.get("start")),
            data.get("endEpoch", data.get("end")),
        )
        if (
            any(
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                for value in (start, end)
            )
            or start >= end
        ):
            raise ValueError(f"bad sidecar {path}: expected finite start before end")
        return Interval(start, end, "sidecar")
    return Interval()


@dataclass(frozen=True, slots=True)
class Opened:
    trace: str
    run: export.Run
    schema: str
    interval: Interval


def open_trace(trace: str, options: Options) -> Opened:
    run = export.load_run(trace, options.run)
    return Opened(
        trace,
        run,
        options.schema or export.infer_schema(run),
        resolve_interval(trace, options.interval),
    )


def kept_samples(opened: Opened, thread: str | None):
    query = thread.lower() if thread else None
    source = export.samples(export.rows(opened.trace, opened.run.number, opened.schema))
    try:
        for sample in source:
            keep_thread = not query or (
                sample.main if query == "main" else query in sample.thread.lower()
            )
            if keep_thread and opened.interval.contains(
                opened.run.start + sample.time / 1e9
            ):
                yield sample
    finally:
        source.close()


def profile(samples, binary: str | None = None) -> dict:
    total = 0
    count = 0
    processes = defaultdict(float)
    threads = {}
    binaries = defaultdict(float)
    symbols = {}
    for sample in samples:
        count += 1
        total += sample.weight
        processes[sample.process] += sample.weight
        thread = threads.setdefault(
            sample.thread, {"name": sample.thread, "weight": 0, "main": sample.main}
        )
        thread["weight"] += sample.weight
        if sample.stack:
            binaries[sample.stack[0].binary] += sample.weight
        seen = set()
        for depth, frame in enumerate(sample.stack):
            key = (frame.binary, frame.sym)
            if key in seen:
                continue
            seen.add(key)
            stat = symbols.setdefault(
                key,
                {
                    "sym": frame.sym,
                    "binary": frame.binary,
                    "self": 0,
                    "incl": 0,
                    "samples": 0,
                },
            )
            stat["incl"] += sample.weight
            if depth == 0:
                stat["self"] += sample.weight
                stat["samples"] += 1

    def pct(weight):
        return weight / total * 100 if total > 0 else 0

    return {
        "samples": count,
        "total": total,
        "processes": sorted(
            (
                {"name": name, "weight": weight, "pct": pct(weight)}
                for name, weight in processes.items()
            ),
            key=lambda item: -item["weight"],
        ),
        "threads": sorted(
            ({**entry, "pct": pct(entry["weight"])} for entry in threads.values()),
            key=lambda item: -item["weight"],
        ),
        "binaries": sorted(
            (
                {"name": name, "self": weight, "pct": pct(weight)}
                for name, weight in binaries.items()
            ),
            key=lambda item: -item["self"],
        ),
        "symbols": sorted(
            (
                entry
                for entry in symbols.values()
                if not binary or entry["binary"] == binary
            ),
            key=lambda item: -item["self"],
        ),
        "symbolScope": binary,
    }


def signpost(events, run: export.Run, interval: Interval) -> dict:
    events = sorted(events, key=lambda event: event.time)
    pending = defaultdict(list)
    durations = defaultdict(list)
    unpaired_ends = []
    for event in events:
        key = (event.subsystem, event.category, event.name, event.ident)
        if event.type == "Begin":
            pending[key].append(event.time)
        elif event.type == "End":
            if pending[key]:
                begin = pending[key].pop()
                if interval.contains(run.start + begin / 1e9):
                    durations[key[:3]].append((event.time - begin) / 1e6)
            else:
                unpaired_ends.append(event.time)
    groups = []
    for (subsystem, category, name), values in durations.items():
        groups.append(
            {
                "subsystem": subsystem,
                "category": category,
                "name": name,
                "count": len(values),
                "totalMs": sum(values),
                "minMs": min(values),
                "medianMs": statistics.median(values),
                "maxMs": max(values),
            }
        )
    return {
        "groups": sorted(groups, key=lambda group: -group["totalMs"]),
        "unpairedBegins": sum(
            interval.contains(run.start + begin / 1e9)
            for begins in pending.values()
            for begin in begins
        ),
        "unpairedEnds": sum(
            interval.contains(run.start + end / 1e9) for end in unpaired_ends
        ),
        "events": sum(
            event.type not in ("Begin", "End")
            and interval.contains(run.start + event.time / 1e9)
            for event in events
        ),
    }


def load(trace: str, options: Options) -> dict:
    opened = open_trace(trace, options)
    result = {
        "trace": trace,
        "run": opened.run.number,
        "template": opened.run.template,
        "durationSec": opened.run.duration,
        "interval": opened.interval.json(),
        "schema": opened.schema,
    }
    if opened.schema == "os-signpost":
        result.update(
            signpost(
                export.signposts(export.rows(trace, opened.run.number, opened.schema)),
                opened.run,
                opened.interval,
            )
        )
    else:
        result["unit"] = "cycle-weight" if opened.schema == "cpu-profile" else "weight"
        result.update(profile(kept_samples(opened, options.thread), options.binary))
    return result


def header(result: dict) -> list[str]:
    label = interval_label(result["interval"])
    return [
        f"trace: {result['trace']}",
        f"run: {result['run']}  template: {result['template']}  duration: {result['durationSec']:.3f} s",
        f"interval: {label}",
    ]


def render(result: dict, top: int) -> list[str]:
    lines = header(result)
    if result["schema"] == "os-signpost":
        lines.append(
            "signpost intervals: count / total / min / median / max ms; subsystem / category / name"
        )
        for group in result["groups"][:top]:
            lines.append(
                f"  {group['count']:5d} {group['totalMs']:10.2f} {group['minMs']:8.2f} {group['medianMs']:8.2f} {group['maxMs']:8.2f}  {group['subsystem']} / {group['category']} / {group['name']}"
            )
        lines.append(
            f"unpaired begins: {result['unpairedBegins']}  unpaired ends: {result['unpairedEnds']}  events: {result['events']}"
        )
        return lines

    def weight(value):
        return f"{value / 1e6:.2f} ms" if result["unit"] == "weight" else f"{value:.0f}"

    lines.append(f"unit: {result['unit']}  samples: {result['samples']}")
    for section, value_field in (
        ("processes", "weight"),
        ("threads", "weight"),
        ("binaries", "self"),
    ):
        lines.append(section + ":")
        for item in result[section][:top]:
            main = " [main]" if item.get("main") else ""
            lines.append(
                f"  {item['name']}{main}: {weight(item[value_field])} ({item['pct']:.1f}%)"
            )
    lines.append(
        f"symbol self / inclusive (scope {result['symbolScope'] or 'all binaries'}):"
    )
    for item in result["symbols"][:top]:
        lines.append(
            f"  {weight(item['self']):>12} {weight(item['incl']):>12} {item['samples']:7d}  {item['sym']} [{item['binary']}]"
        )
    return lines
