"""Observed out-of-line edges, local/outside weight and distinct return sites."""

from . import summarize

COPY_PREFIXES = (
    "outlined ",
    "initializeWithCopy for ",
    "initializeWithTake for ",
    "assignWithCopy for ",
    "assignWithTake for ",
    "destroy for ",
)


def call_kind(callee: str) -> str:
    if callee.startswith("DYLD-STUB$$"):
        return "stub"
    if callee == "<deduplicated_symbol>":
        return "unnamed"
    if callee.startswith(COPY_PREFIXES):
        return "copy"
    if (
        "closure #" in callee
        or callee.startswith("partial apply for ")
        or "thunk for " in callee
    ):
        return "closure"
    return "call"


def aggregate(samples, binary: str) -> dict:
    calls = {}
    total = 0
    count = 0

    def call_for(caller, callee):
        return calls.setdefault(
            (caller, callee),
            {
                "caller": caller,
                "callee": callee,
                "kind": call_kind(callee),
                "local": 0,
                "outside": 0,
                "incl": 0,
                "addrs": set(),
            },
        )

    for sample in samples:
        count += 1
        total += sample.weight
        stack = sample.stack
        deepest = next(
            (index for index, frame in enumerate(stack) if frame.binary == binary), -1
        )
        above = deepest + 1
        while (
            deepest != -1
            and above < len(stack)
            and stack[above].sym == stack[deepest].sym
        ):
            above += 1
        if deepest != -1 and above < len(stack) and stack[above].binary == binary:
            call = call_for(stack[above].sym, stack[deepest].sym)
            call["local"] += sample.weight
            if deepest > 0:
                call["outside"] += sample.weight
        seen = set()
        for depth in range(max(deepest, 0), len(stack) - 1):
            callee, caller = stack[depth : depth + 2]
            if (
                callee.binary != binary
                or caller.binary != binary
                or caller.sym == callee.sym
            ):
                continue
            call = call_for(caller.sym, callee.sym)
            if caller.addr is not None:
                call["addrs"].add(caller.addr)
            key = (caller.sym, callee.sym)
            if key not in seen:
                call["incl"] += sample.weight
                seen.add(key)
    values = []
    for call in calls.values():
        addresses = call.pop("addrs")
        values.append({**call, "sites": len(addresses)})
    return {
        "sampleCount": count,
        "total": total,
        "calls": sorted(values, key=lambda call: (-call["local"], -call["incl"])),
    }


def load(trace: str, options: summarize.Options):
    opened = summarize.open_trace(trace, options)
    if opened.schema == "os-signpost":
        raise ValueError("inline needs a cpu-profile or time-profile table")
    return {
        "trace": trace,
        "run": {
            "number": opened.run.number,
            "template": opened.run.template,
            "startEpoch": opened.run.start,
            "endEpoch": opened.run.end,
            "durationSec": opened.run.duration,
            "schemas": list(opened.run.schemas),
        },
        "interval": {
            "start": opened.interval.start,
            "end": opened.interval.end,
            "source": opened.interval.source,
        },
        "binary": options.binary,
        "unit": "cycle-weight" if opened.schema == "cpu-profile" else "weight",
        **aggregate(summarize.kept_samples(opened, options.thread), options.binary),
    }


def render(report: dict, top: int) -> list[str]:
    interval = report["interval"]
    lines = [
        f"trace: {report['trace']}  run: {report['run']['number']}  interval: {summarize.interval_label(interval)}",
        f"unit: {report['unit']}  samples: {report['sampleCount']}  total: {report['total']:g}",
        f"out-of-line calls in {report['binary']}: local% / outside% / incl% / sites / kind / caller -> callee",
    ]
    for call in report["calls"][:top]:
        weights = [
            call[key] / report["total"] * 100 if report["total"] > 0 else 0
            for key in ("local", "outside", "incl")
        ]
        lines.append(
            f"  {weights[0]:7.2f} {weights[1]:7.2f} {weights[2]:7.2f} {call['sites']:5d} {call['kind']:7s} {call['caller']} -> {call['callee']}"
        )
    return lines
