"""Record with xcrun; analyze exports locally without third-party XML packages."""

import argparse
import json
import math
import os
import signal
import subprocess
import sys
from pathlib import Path

from ..process import cancel_on_signals, stop_child
from . import compare, export, inline, summarize


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("requires a positive integer")
    return number


def positive_float(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("requires a positive finite number")
    return number


def interval(value):
    try:
        start, end = map(float, value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "interval requires startEpoch,endEpoch"
        ) from error
    if not math.isfinite(start) or not math.isfinite(end) or start >= end:
        raise argparse.ArgumentTypeError("interval requires finite start before end")
    return start, end


def parser():
    root = argparse.ArgumentParser(
        prog="uv run --no-sync dev xctrace", allow_abbrev=False
    )
    commands = root.add_subparsers(dest="command")
    record = commands.add_parser(
        "record", help="record Instruments data using xcrun", allow_abbrev=False
    )
    record.add_argument("--template", required=True)
    target = record.add_mutually_exclusive_group(required=True)
    target.add_argument("--attach", type=positive_int)
    target.add_argument("--launch", type=lambda value: Path(value).resolve())
    record.add_argument(
        "--output", type=lambda value: Path(value).resolve(), required=True
    )
    record.add_argument("--time-limit", type=positive_float)
    record.add_argument("launch_args", nargs=argparse.REMAINDER)
    for name in ("summarize", "compare", "inline"):
        command = commands.add_parser(
            name, help=f"{name} trace exports", allow_abbrev=False
        )
        command.add_argument("traces", nargs="+" if name == "compare" else None)
        if name == "compare":
            command.add_argument("--against", nargs="+", required=True)
            command.add_argument("--metric")
        command.add_argument("--schema", choices=export.SCHEMAS)
        command.add_argument("--run", type=positive_int, default=1)
        command.add_argument("--interval", type=interval)
        command.add_argument("--binary", required=name == "inline")
        command.add_argument("--thread")
        command.add_argument("--top", type=positive_int, default=20)
        command.add_argument("--json", action="store_true")
    return root


def record(options) -> int:
    trailing = options.launch_args
    if trailing and trailing[0] == "--":
        trailing = trailing[1:]
    if options.attach is not None and trailing:
        raise ValueError("--attach does not accept launch arguments")
    args = [
        "xcrun",
        "xctrace",
        "record",
        "--no-prompt",
        "--template",
        options.template,
        "--output",
        str(options.output),
    ]
    if options.time_limit is not None:
        args += ["--time-limit", f"{options.time_limit:g}s"]
    if options.attach is not None:
        args += ["--attach", str(options.attach)]
    else:
        args += ["--launch", "--", str(options.launch), *trailing]
    child = subprocess.Popen(args, start_new_session=True)
    try:
        code = child.wait()
    except KeyboardInterrupt:
        try:
            os.killpg(child.pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            stop_child(child)
        raise
    finally:
        stop_child(child)
    if code == 0:
        print(f"trace: {options.output}")
        print(f"pid: {options.attach if options.attach is not None else 'unknown'}")
    return code


@cancel_on_signals()
def run(args: list[str]) -> int:
    root = parser()
    options = root.parse_args(args)
    if options.command is None:
        root.print_help()
        return 0
    if sys.platform != "darwin":
        raise RuntimeError("xctrace requires macOS and Xcode's xcrun")
    if (
        options.command == "record"
        and options.launch_args
        and options.launch_args[0] != "--"
    ):
        root.error("launch arguments must follow a bare -- delimiter")
    if options.command == "record":
        if options.attach is not None and options.launch_args:
            root.error("--attach does not accept launch arguments")
        return record(options)
    filters = summarize.Options(
        options.run, options.schema, options.interval, options.binary, options.thread
    )
    if options.command == "compare":
        if len(options.traces) != len(options.against):
            root.error("compare requires equal before/after trace counts")
        result, labels, units = compare.load(
            options.traces, options.against, filters, options.metric
        )
        lines = compare.render(result, labels, units) if not options.json else None
    elif options.command == "inline":
        result = inline.load(options.traces, filters)
        result["calls"] = result["calls"][: options.top]
        lines = inline.render(result, options.top) if not options.json else None
    else:
        result = summarize.load(options.traces, filters)
        lines = summarize.render(result, options.top) if not options.json else None
    print(
        json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
        if options.json
        else "\n".join(lines)
    )
    return 0
