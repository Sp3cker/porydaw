"""Stream native XML exports, preserve reference identity, decode runs and rows."""

import math
import os
import re
import subprocess
import tempfile
import weakref
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from xml.parsers import expat

from ..process import stop_child

SCHEMAS = ("cpu-profile", "time-profile", "os-signpost")


@dataclass(eq=False, slots=True, weakref_slot=True)
class Element:
    name: str
    attrs: dict[str, str]
    children: list = field(default_factory=list)
    text: str = ""

    def child(self, name: str):
        return next((item for item in self.children if item.name == name), None)

    def children_named(self, name: str):
        return (item for item in self.children if item.name == name)


class Parser:
    def __init__(self, names):
        self.names = set(names)
        self.ids = {}
        self.open = []
        self.ready = deque()
        self.parser = expat.ParserCreate()
        self.parser.StartElementHandler = self.start
        self.parser.EndElementHandler = self.end
        self.parser.CharacterDataHandler = self.characters

    def start(self, name, attrs):
        self.open.append(Element(name, attrs))

    def characters(self, text):
        if self.open:
            self.open[-1].text += text

    def end(self, _name):
        element = self.open.pop()
        if "ref" in element.attrs:
            try:
                element = self.ids[element.attrs["ref"]]
            except KeyError as error:
                raise ValueError(f"unresolved ref {element.attrs['ref']}") from error
        elif "id" in element.attrs:
            self.ids[element.attrs["id"]] = element
        if element.name in self.names:
            self.ready.append(element)
        elif self.open:
            self.open[-1].children.append(element)

    def feed(self, chunk: bytes, *, final=False):
        try:
            self.parser.Parse(chunk, final)
        except (expat.ExpatError, ValueError) as error:
            raise ValueError(f"unparsable XML: {error}") from error
        while self.ready:
            yield self.ready.popleft()


def elements(args: list[str], names):
    parser = Parser(names)
    with tempfile.TemporaryFile() as errors:
        child = subprocess.Popen(
            ["xcrun", *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=errors,
            bufsize=0,
            start_new_session=os.name == "posix",
        )
        try:
            while chunk := child.stdout.read(65536):
                yield from parser.feed(chunk)
            code = child.wait()
            if code:
                errors.seek(0)
                message = errors.read().decode("utf-8", "replace").strip().splitlines()
                raise RuntimeError(
                    f"xcrun {args[0]} failed: {message[0] if message else f'code {code}'}"
                )
            yield from parser.feed(b"", final=True)
        finally:
            stop_child(child)
            child.stdout.close()


def text(element) -> str:
    return element.text.strip() if element is not None else ""


def attr(element, name: str) -> str:
    return element.attrs.get(name, "") if element is not None else ""


def child(element, name: str):
    return element.child(name) if element is not None else None


def number(element) -> float:
    try:
        value = float(text(element))
    except ValueError:
        return math.nan
    return value


@dataclass(frozen=True, slots=True)
class Run:
    number: int
    template: str
    start: float
    end: float
    duration: float
    schemas: tuple[str, ...]


def load_run(trace: str, run_number: int) -> Run:
    runs = []
    for node in elements(["xctrace", "export", "--input", trace, "--toc"], {"run"}):
        raw = attr(node, "number")
        if not re.fullmatch(r"\d+", raw):
            raise ValueError("unparsable TOC: run without an integer number")
        summary = child(child(node, "info"), "summary")
        start = datetime.fromisoformat(text(child(summary, "start-date"))).timestamp()
        end = datetime.fromisoformat(text(child(summary, "end-date"))).timestamp()
        duration = number(child(summary, "duration"))
        if not math.isfinite(duration) or duration < 0:
            raise ValueError("unparsable TOC duration")
        data = child(node, "data")
        schemas = (
            tuple(
                attr(item, "schema")
                for item in data.children_named("table")
                if attr(item, "schema")
            )
            if data is not None
            else ()
        )
        runs.append(
            Run(
                int(raw),
                text(child(summary, "template-name")) or "(unknown template)",
                start,
                end,
                duration,
                schemas,
            )
        )
    result = next((run for run in runs if run.number == run_number), None)
    if result is None:
        raise ValueError(
            f"run {run_number} missing in {trace}; available: {[run.number for run in runs]}"
        )
    return result


def infer_schema(run: Run) -> str:
    for schema in SCHEMAS:
        if schema in run.schemas:
            return schema
    raise ValueError(f"no supported profile or signpost table in run {run.number}")


def rows(trace: str, run: int, schema: str):
    nodes = 0
    source = elements(
        [
            "xctrace",
            "export",
            "--input",
            trace,
            "--xpath",
            f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"]',
        ],
        {"row", "node"},
    )
    try:
        for element in source:
            if element.name == "node":
                nodes += 1
            else:
                yield element
        if not nodes:
            raise ValueError(f"missing table: no {schema} table in run {run}")
    finally:
        source.close()


@dataclass(frozen=True, slots=True)
class Frame:
    sym: str
    binary: str
    addr: int | None


@dataclass(frozen=True, slots=True)
class Sample:
    time: float
    thread: str
    main: bool
    process: str
    weight: float
    stack: tuple[Frame, ...]


def _display(value: str, fallback: str) -> str:
    return value.split(" (0x", 1)[0] or fallback


def _frames(tagged) -> tuple[Frame, ...]:
    holder = child(tagged, "backtrace") or tagged
    if holder is None:
        return ()
    result = []
    for frame in holder.children_named("frame"):
        try:
            address = int(attr(frame, "addr"), 16)
        except ValueError:
            address = None
        result.append(
            Frame(
                attr(frame, "name") or attr(frame, "fmt") or "?",
                attr(child(frame, "binary"), "name") or "?",
                address,
            )
        )
    return tuple(result)


def samples(source):
    stacks = weakref.WeakKeyDictionary()
    try:
        for row in source:
            time = number(child(row, "sample-time"))
            weight = number(child(row, "cycle-weight") or child(row, "weight"))
            if not math.isfinite(time) or not math.isfinite(weight):
                continue
            thread = child(row, "thread")
            name = _display(
                attr(thread, "fmt"), f"tid {text(child(thread, 'tid')) or '?'}"
            )
            process = child(row, "process")
            process_name = (
                re.sub(r" \([0-9]+\)$", "", _display(attr(process, "fmt"), ""))
                or text(child(process, "pid"))
                or "?"
            )
            tagged = child(row, "tagged-backtrace")
            if tagged is None:
                stack = ()
            elif tagged in stacks:
                stack = stacks[tagged]
            else:
                stack = _frames(tagged)
                stacks[tagged] = stack
            yield Sample(
                time, name, name.lower() == "main thread", process_name, weight, stack
            )
    finally:
        source.close()


@dataclass(frozen=True, slots=True)
class Event:
    time: float
    type: str
    subsystem: str
    category: str
    name: str
    ident: str


def signposts(source):
    try:
        for row in source:
            time = number(child(row, "event-time"))
            if math.isfinite(time):
                yield Event(
                    time,
                    text(child(row, "event-type")) or "?",
                    text(child(row, "subsystem")),
                    text(child(row, "category")),
                    text(child(row, "signpost-name")),
                    text(child(row, "os-signpost-identifier")),
                )
    finally:
        source.close()
