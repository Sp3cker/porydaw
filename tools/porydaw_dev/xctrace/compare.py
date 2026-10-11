"""Compare like-unit trace pairs, retaining raw values and undefined reductions."""

import statistics
from dataclasses import replace

from . import summarize

METRICS = ("processTotal", "mainThread", "binarySelf", "metric")


def reduction(before: float, after: float) -> float | None:
    return ((before - after) / before) * 100 if before else (0 if after == 0 else None)


def metric_weight(summary: dict, query: str):
    lowered = query.lower()
    for section, name, field in (
        ("threads", "name", "weight"),
        ("binaries", "name", "self"),
        ("symbols", "sym", "self"),
    ):
        values = summary[section]
        match = next(
            (
                item
                for item in values
                if (
                    item[name].lower() == lowered
                    if section == "threads"
                    else item[name] == query
                )
            ),
            None,
        )
        if match is None:
            match = next(
                (item for item in values if lowered in item[name].lower()), None
            )
        if match is not None:
            kind = {"threads": "thread", "binaries": "binary", "symbols": "symbol"}[
                section
            ]
            label = f'{kind} "{match[name]}"'
            if section == "symbols":
                label += f" [{match['binary']}]"
            return label, match[field]
    return None


def _endpoint(summary: dict):
    interval = summary["interval"]
    return {
        "trace": summary["trace"],
        "interval": summarize.interval_label(interval),
        "source": interval["source"] if interval is not None else "whole-run",
    }


def pair(before: dict, after: dict, binary=None, metric=None):
    if before["schema"] != after["schema"]:
        raise ValueError(
            f"schema/weight-unit mismatch: {before['schema']} vs {after['schema']}"
        )
    metrics = {}

    def row(name, b, a):
        metrics[name] = {"before": b, "after": a, "reductionPct": reduction(b, a)}

    label = None
    if before["schema"] == "os-signpost":
        row(
            "processTotal",
            round(sum(group["totalMs"] for group in before["groups"]), 2),
            round(sum(group["totalMs"] for group in after["groups"]), 2),
        )
    else:
        row("processTotal", before["total"], after["total"])
        row(
            "mainThread",
            sum(item["weight"] for item in before["threads"] if item["main"]),
            sum(item["weight"] for item in after["threads"] if item["main"]),
        )
        if binary:
            row(
                "binarySelf",
                next(
                    (
                        item["self"]
                        for item in before["binaries"]
                        if item["name"] == binary
                    ),
                    0,
                ),
                next(
                    (
                        item["self"]
                        for item in after["binaries"]
                        if item["name"] == binary
                    ),
                    0,
                ),
            )
        if metric:
            b, a = metric_weight(before, metric), metric_weight(after, metric)
            label = b[0] if b else a[0] if a else f'"{metric}" (not found)'
            row("metric", b[1] if b else 0, a[1] if a else 0)
    return {
        "before": _endpoint(before),
        "after": _endpoint(after),
        "metrics": metrics,
    }, label


def load(
    befores: list[str], afters: list[str], options: summarize.Options, metric=None
):
    if not befores or len(befores) != len(afters):
        raise ValueError(
            f"compare needs equal before/after counts ({len(befores)} vs {len(afters)})"
        )
    pairs = []
    labels = []
    units = []
    for b, a in zip(befores, afters, strict=True):
        before = summarize.load(b, replace(options, binary=None))
        after = summarize.load(a, replace(options, binary=None))
        result, label = pair(before, after, options.binary, metric)
        pairs.append(result)
        labels.append(label)
        units.append(before.get("unit", "ms"))
    medians = {}
    dropped = 0
    for name in METRICS:
        values = [
            item["metrics"][name]["reductionPct"]
            for item in pairs
            if name in item["metrics"]
        ]
        if not values:
            continue
        valid = [value for value in values if value is not None]
        dropped += len(values) - len(valid)
        medians[name] = statistics.median(valid) if valid else None
    return {"pairs": pairs, "medians": medians, "dropped": dropped}, labels, units


def render(result: dict, labels, units) -> list[str]:
    lines = []
    for number, (item, label, unit) in enumerate(
        zip(result["pairs"], labels, units, strict=True), 1
    ):
        lines += [
            f"pair {number}: {item['before']['trace']} vs {item['after']['trace']}",
            f"  before interval: {item['before']['interval']}",
            f"  after interval: {item['after']['interval']}",
        ]
        for name, values in item["metrics"].items():
            reduction = values["reductionPct"]
            change = "n/a" if reduction is None else f"{reduction:.1f}%"
            lines.append(
                f"  {label if name == 'metric' else name}: {values['before']:g} -> {values['after']:g} {unit}; reduction {change}"
            )
    lines.append(f"median reduction over {len(result['pairs'])} pair(s):")
    for name, value in result["medians"].items():
        lines.append(f"  {name}: {'n/a' if value is None else f'{value:.1f}%'}")
    if result["dropped"]:
        lines.append(
            f"  undefined zero-baseline reductions dropped: {result['dropped']}"
        )
    return lines
