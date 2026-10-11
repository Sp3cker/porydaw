"""Check the owned Swift/QML bridge surface against its pinned baseline."""

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

BASELINE = Path("tools/qtbridge_surface_baseline.json")
PIN_FILE = Path("cmake/QtBridge.cmake")
SUPPORTED_PIN = "407714006dd21107b70db6547ce75e43df0c8a75"
SUPPORTED_TYPES = {
    "Int",
    "UInt",
    "Double",
    "Float",
    "String",
    "Bool",
    "QmlColor",
    "QmlFont",
}


def _balanced(text: str, start: int, opening: str, closing: str) -> int:
    depth, index = 1, start + 1
    while index < len(text):
        end = _skip(text, index)
        if end is not None:
            index = end
            continue
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if not depth:
                return index + 1
        index += 1
    return len(text)


def _skip(text: str, start: int) -> int | None:
    if text.startswith("//", start):
        end = text.find("\n", start + 2)
        return len(text) if end < 0 else end
    if text.startswith("/*", start):
        depth, index = 1, start + 2
        while index < len(text):
            if text.startswith("/*", index):
                depth += 1
                index += 2
            elif text.startswith("*/", index):
                depth -= 1
                index += 2
                if not depth:
                    return index
            else:
                index += 1
        return len(text)
    index = start
    while text.startswith("#", index):
        index += 1
    hashes = text[start:index]
    if hashes and not text.startswith('"', index):
        return None
    char = text[index : index + 1]
    if char not in ('"', "'", "`"):
        return None
    triple = char == '"' and text.startswith('"""', index)
    delimiter = '"""' if triple else char
    closer = delimiter + hashes
    index += len(delimiter)
    while index < len(text):
        if char == '"' and text.startswith("\\" + hashes + "(", index):
            index = _balanced(text, index + 1 + len(hashes), "(", ")")
        elif not hashes and text[index] == "\\":
            index += 2
        elif char == "`" and text.startswith("${", index):
            index = _balanced(text, index + 1, "{", "}")
        elif text.startswith(closer, index):
            return index + len(closer)
        elif text[index] == "\n" and not hashes and not triple and char != "`":
            return index
        else:
            index += 1
    return len(text)


def code_only(text: str) -> str:
    characters = list(text)
    index = 0
    while index < len(text):
        end = _skip(text, index)
        if end is None:
            index += 1
        else:
            for position in range(index, end):
                if characters[position] != "\n":
                    characters[position] = " "
            index = end
    return "".join(characters)


def closing_brace(code: str, start: int) -> int:
    depth = 0
    for index in range(start, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if not depth:
                return index
    return len(code)


@dataclass(frozen=True, slots=True)
class Source:
    path: str
    text: str
    code: str

    @classmethod
    def from_text(cls, path: str, text: str) -> "Source":
        return cls(path, text, code_only(text))


@dataclass(frozen=True, slots=True)
class Finding:
    check: str
    path: str
    line: int
    detail: str

    def key(self) -> str:
        return f"{self.check} {self.path} {self.detail}"

    def format(self) -> str:
        return f"{self.check} {self.path}:{self.line} {self.detail}"


@dataclass(frozen=True, slots=True)
class Member:
    type: str
    tracked: bool
    ignored: bool


@dataclass(slots=True)
class Signal:
    name: str
    path: str
    line: int
    emitted: bool = False


@dataclass(slots=True)
class BridgeClass:
    name: str
    members: dict[str, Member] = field(default_factory=dict)
    signals: dict[str, Signal] = field(default_factory=dict)


def supported(type_name: str) -> bool:
    compact = re.sub(r"\s", "", type_name)
    return (
        compact in SUPPORTED_TYPES
        or compact
        in (
            "[String]",
            "Array<String>",
            "[String:QVariantSettable]",
            "Dictionary<String,QVariantSettable>",
        )
        or re.fullmatch(r"Q(?:List|Table)Model<.+>", compact) is not None
    )


def swift_model(
    sources: list[Source], findings: list[Finding]
) -> dict[str, BridgeClass]:
    classes = {}
    pattern = re.compile(
        r"@QtBridgeable\s+(?:(?:@\w+(?:\([^)]*\))?|public|final|open|internal|private|fileprivate|package|\s)+)?class\s+(\w+)[^{]*\{",
        re.ASCII,
    )
    declaration = re.compile(
        r"\b(var|let)\s+([A-Za-z_]\w*)\s*(?::\s*([^={\n]+))?", re.ASCII
    )
    function = re.compile(
        r"\bfunc\s+(\w+)\s*\([^)]*\)\s*(?:async\s*)?(?:throws\s*)?(?:->\s*(Optional<)?([A-Za-z_]\w*)(\?)?)?",
        re.ASCII,
    )
    for source in sources:
        for hit in pattern.finditer(source.code):
            opening, close = hit.end() - 1, closing_brace(source.code, hit.end() - 1)
            bridge = BridgeClass(hit[1])
            classes[bridge.name] = bridge
            lines = source.code[opening + 1 : close].split("\n")
            depth, attributes = 0, ""
            number = source.text.count("\n", 0, opening + 1) + 1
            for index, code in enumerate(lines):
                if depth == 0:
                    attribute = re.match(
                        r"\s*((?:@\w+(?:\([^)]*\))?\s*)+)", code, re.ASCII
                    )
                    if attribute:
                        attributes += " " + attribute[1]
                    member = declaration.search(code)
                    if member and not re.search(
                        r"\b(?:func|subscript|typealias)\b",
                        code[: member.start()],
                        re.ASCII,
                    ):
                        prefix = attributes + " " + code[: member.start()]
                        name, type_name = member[2], (member[3] or "").strip()
                        ignored = (
                            re.search(r"@QtIgnored\b", prefix, re.ASCII) is not None
                        )
                        tracked = (
                            re.search(r"@QtTracked\b", prefix, re.ASCII) is not None
                        )
                        private = (
                            re.search(r"\bprivate\b", prefix, re.ASCII) is not None
                        )
                        static = (
                            re.search(r"\b(?:static|class)\b", prefix, re.ASCII)
                            is not None
                        )
                        after = code[member.end() :]
                        computed = re.match(r"\s*\{", after) is not None or (
                            not after.strip()
                            and index + 1 < len(lines)
                            and re.match(r"\s*\{", lines[index + 1]) is not None
                        )
                        did_set = re.search(r"\bdidSet\b", code, re.ASCII) is not None
                        if not did_set:
                            property_depth = 0
                            for position in range(index + 1, len(lines)):
                                candidate = lines[position]
                                if property_depth == 0 and re.match(
                                    r"\s*(?:@|(?:public|private|internal|fileprivate|package|static|class|var|let|func)\b)",
                                    candidate,
                                    re.ASCII,
                                ):
                                    break
                                if re.search(r"\bdidSet\b", candidate, re.ASCII):
                                    did_set = True
                                property_depth += candidate.count(
                                    "{"
                                ) - candidate.count("}")
                                if property_depth < 0:
                                    break
                        if ignored and (private or static):
                            findings.append(
                                Finding("REDUNDANT_IGNORED", source.path, number, name)
                            )
                        if not private and not static and not computed and not did_set:
                            check = None
                            if not type_name and not tracked and not ignored:
                                check = "UNANNOTATED_MEMBER"
                            elif tracked and supported(type_name):
                                check = "REDUNDANT_TRACKED"
                            elif (
                                not tracked and not ignored and not supported(type_name)
                            ):
                                check = "UNTRACKED_CUSTOM_TYPE"
                            if check:
                                findings.append(
                                    Finding(check, source.path, number, name)
                                )
                            bridge.members[name] = Member(type_name, tracked, ignored)
                        attributes = ""
                    elif fn := function.search(code):
                        prefix = attributes + " " + code[: fn.start()]
                        if re.search(r"@QtSignal\b", prefix, re.ASCII):
                            bridge.signals[fn[1]] = Signal(fn[1], source.path, number)
                        if (
                            re.search(r"\bpublic\b", prefix, re.ASCII)
                            and fn[2] is None
                            and fn[4] == "?"
                        ):
                            findings.append(
                                Finding(
                                    "SUGAR_OPTIONAL_RETURN", source.path, number, fn[1]
                                )
                            )
                        attributes = ""
                    elif code.strip() and not re.match(r"\s*@", code):
                        attributes = ""
                depth += code.count("{") - code.count("}")
                number += 1
    for bridge in classes.values():
        for signal in bridge.signals.values():
            escaped = re.escape(signal.name)
            emit = re.compile(
                rf"\bemitSignal\s*\(\s*for:\s*\\(?:\w+)?\.{escaped}\b", re.ASCII
            )
            call = re.compile(rf"\b{escaped}\s*\(", re.ASCII)
            signal.emitted = any(
                emit.search(source.code)
                or any(
                    source.path != signal.path
                    or source.code.count("\n", 0, hit.start()) + 1 != signal.line
                    for hit in call.finditer(source.code)
                )
                for source in sources
            )
    return classes


def reachability(
    qml: list[Source], swift: list[Source], cmake: str, findings: list[Finding]
) -> None:
    ui = {source.path: source for source in qml if source.path.startswith("src/ui/")}
    modules = list(
        re.finditer(
            r"qt_add_qml_module\((\w+)\b[\s\S]*?\bQML_FILES\b([\s\S]*?)\n\s*\)",
            cmake,
            re.ASCII,
        )
    )
    if not any(module[1] == "porydaw_app" for module in modules):
        raise RuntimeError("porydaw_app QML_FILES block not found")
    reachable = {
        path
        for module in modules
        for path in re.findall(r"src/ui/[^\s)]+\.qml", module[2])
    }
    shell = re.search(r"set\(shell_qml\s+(src/ui/[^\s)]+\.qml)\s*\)", cmake)
    app_names = [
        hit[1]
        for source in swift
        for hit in re.finditer(r'\bqmlFileName\s*=\s*"(\w+)"', source.text, re.ASCII)
    ]
    if shell is None or Path(shell[1]).stem not in app_names:
        raise RuntimeError(
            f"CMakeLists.txt shell_qml ({shell[1] if shell else 'missing'}) does not match Swift qmlFileName ({', '.join(app_names) or 'missing'})"
        )
    reachable.add(shell[1])
    for source in swift:
        for hit in re.finditer(
            r'QmlEngineAccess\.moduleResourcePrefix\s*\+\s*"([^"\n]+\.qml)"',
            source.text,
        ):
            if source.code.startswith("QmlEngineAccess", hit.start()):
                reachable.add(hit[1].lstrip("/"))
    pending = list(reachable)
    index = 0
    while index < len(pending):
        path = pending[index]
        index += 1
        if path not in ui:
            continue
        source = ui[path]
        directory = path.rsplit("/", 1)[0]
        for hit in re.finditer(r"\b([A-Z][A-Za-z0-9_]*)\s*\{", source.code, re.ASCII):
            local = f"{directory}/{hit[1]}.qml"
            if local in ui and local not in reachable:
                reachable.add(local)
                pending.append(local)
        position = 0
        while position < len(source.text):
            end = _skip(source.text, position)
            if end is None:
                position += 1
                continue
            if source.text[position] == '"':
                literal = source.text[position + 1 : end - 1]
                if re.fullmatch(r"[A-Za-z_][\w/.-]*\.qml", literal, re.ASCII):
                    local = (
                        literal
                        if literal.startswith("src/ui/")
                        else f"{directory}/{literal}"
                    )
                    if local in ui and local not in reachable:
                        reachable.add(local)
                        pending.append(local)
            position = end
    findings.extend(
        Finding("UNREACHABLE_QML", path, 1, "unregistered")
        for path in ui
        if path not in reachable
    )


def resolve_type(
    chain: str, ids: dict[str, str], classes: dict[str, BridgeClass]
) -> str | None:
    names = chain.split(".")
    type_name, start = None, 1
    for length in range(len(names), 0, -1):
        if known := ids.get(".".join(names[:length])):
            type_name, start = known, length
            break
    for name in names[start:]:
        member = classes[type_name].members.get(name) if type_name in classes else None
        if (
            member is None
            or member.ignored
            or (not member.tracked and not supported(member.type))
        ):
            return None
        match = re.match(r"(?:Optional<)?(\w+)", member.type, re.ASCII)
        type_name = match[1] if match else None
    return type_name if type_name in classes else None


@dataclass(frozen=True, slots=True)
class Element:
    type: str
    id: str | None
    open: int
    end: int


def qml_ids(
    source: Source,
    roots: set[str],
    classes: dict[str, BridgeClass],
    elements: list[Element],
    opening: int,
) -> dict[str, str]:
    ids = {
        element.id: element.type
        for element in elements
        if element.id and element.type in roots
    }
    enclosing = [
        element for element in elements if element.open < opening < element.end
    ]
    for hit in re.finditer(r"\bproperty\s+(\w+)\s+(\w+)\b", source.code, re.ASCII):
        if hit[1] not in classes:
            continue
        owner = next(
            (
                element
                for element in reversed(elements)
                if element.open < hit.start() < element.end
            ),
            None,
        )
        if owner is None or owner not in enclosing:
            continue
        ids[hit[2]] = hit[1]
        if owner.id:
            ids[f"{owner.id}.{hit[2]}"] = hit[1]
    return ids


def signal_checks(
    qml: list[Source],
    swift: list[Source],
    classes: dict[str, BridgeClass],
    findings: list[Finding],
) -> None:
    handlers, roots = set(), set()
    for source in swift:
        for hit in re.finditer(
            r"instantiableTypes\s*:\s*\[[^\]]+\]\s*=\s*\[([^\]]+)\]", source.code
        ):
            roots.update(re.findall(r"\b(\w+)\.self\b", hit[1], re.ASCII))
    for source in qml:
        for hit in re.finditer(
            r"\b(?:function\s+on([A-Z]\w*)\s*\(|on([A-Z]\w*)\s*:)",
            source.code,
            re.ASCII,
        ):
            name = hit[1] or hit[2]
            handlers.add(name[0].lower() + name[1:])
        elements = []
        for hit in re.finditer(r"\b([A-Z]\w*)\s*\{", source.code, re.ASCII):
            opening = hit.end() - 1
            end = closing_brace(source.code, opening)
            identifier = re.match(
                r"\s*id\s*:\s*(\w+)", source.code[opening + 1 : end], re.ASCII
            )
            elements.append(
                Element(hit[1], identifier[1] if identifier else None, opening, end)
            )
        contexts = []
        for hit in re.finditer(r"\bConnections\s*\{", source.code, re.ASCII):
            opening, end = hit.end() - 1, closing_brace(source.code, hit.end() - 1)
            target = re.search(
                r"\btarget\s*:\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*(?=\n|$)",
                source.code[opening:end],
                re.MULTILINE | re.ASCII,
            )
            ids = qml_ids(source, roots, classes, elements, opening)
            contexts.append(
                (
                    resolve_type(target[1], ids, classes) if target else None,
                    opening,
                    end,
                )
            )
        for hit in re.finditer(
            r"\bfunction\s+on([A-Z]\w*)\s*\(", source.code, re.ASCII
        ):
            context = next(
                (
                    context
                    for context in contexts
                    if context[1] < hit.start() < context[2]
                ),
                None,
            )
            if context is None or context[0] is None:
                continue
            type_name = context[0]
            name = hit[1][0].lower() + hit[1][1:]
            bridge = classes[type_name]
            member = bridge.members.get(name[:-7]) if name.endswith("Changed") else None
            if (
                member
                and not member.ignored
                and (member.tracked or supported(member.type))
            ):
                continue
            signal = bridge.signals.get(name)
            if signal is None or not signal.emitted:
                findings.append(
                    Finding(
                        "HANDLER_NEVER_EMITTED",
                        source.path,
                        source.code.count("\n", 0, hit.start()) + 1,
                        f"{type_name}.{name}",
                    )
                )
    for bridge in classes.values():
        for signal in bridge.signals.values():
            if signal.name in handlers:
                continue
            connect = re.compile(
                rf"\b{re.escape(signal.name)}\s*\.\s*connect\s*\(", re.ASCII
            )
            assign = re.compile(
                rf"\b(\w+)\.on{signal.name[0].upper()}{re.escape(signal.name[1:])}\s*=",
                re.ASCII,
            )
            observed = any(
                connect.search(source.code)
                or any(
                    re.search(
                        rf"\b{re.escape(hit[1])}\s*:\s*{re.escape(bridge.name)}\b",
                        source.code,
                        re.ASCII,
                    )
                    for hit in assign.finditer(source.code)
                )
                for source in swift
            )
            if not observed:
                findings.append(
                    Finding(
                        "SIGNAL_NEVER_OBSERVED",
                        signal.path,
                        signal.line,
                        f"{bridge.name}.{signal.name}",
                    )
                )


def analyze(repo: Path) -> tuple[str, list[Finding]]:
    def sources(directory: str, suffix: str) -> list[Source]:
        scan_root = repo / directory
        if not scan_root.is_dir():
            raise RuntimeError(f"missing bridge scan root: {scan_root}")
        return [
            Source.from_text(
                path.relative_to(repo).as_posix(), path.read_text(encoding="utf-8")
            )
            for path in sorted(scan_root.rglob("*" + suffix))
            if path.is_file()
        ]

    swift = sources("src/swift", ".swift")
    check_swift = sources("src/checks", ".swift")
    qml = sources("src/ui", ".qml") + sources("src/checks", ".qml")
    hit = re.search(
        r"GIT_TAG\s+([0-9a-f]{40})", (repo / PIN_FILE).read_text(encoding="utf-8")
    )
    if hit is None or hit[1] != SUPPORTED_PIN:
        raise RuntimeError(
            f"QtBridge GIT_TAG in {PIN_FILE} must match supported-type pin {SUPPORTED_PIN}; revisit guard on pin bump"
        )
    findings = []
    classes = swift_model(swift + check_swift, findings)
    reachability(
        qml, swift, (repo / "CMakeLists.txt").read_text(encoding="utf-8"), findings
    )
    signal_checks(qml, swift + check_swift, classes, findings)
    findings.sort(
        key=lambda finding: (finding.path, finding.line, finding.check, finding.detail)
    )
    return hit[1], findings


def run(update: bool = False, quiet: bool = False) -> int:
    pin, findings = analyze(Path.cwd())
    keys = sorted({finding.key() for finding in findings})
    if update:
        BASELINE.write_text(
            json.dumps({"pin": pin, "findings": keys}, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        print(f"updated {BASELINE}: {len(keys)} findings")
        return 0
    if not BASELINE.is_file():
        raise RuntimeError(
            f"missing {BASELINE}; run uv run --no-sync dev bridge:baseline"
        )
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    if not isinstance(baseline, dict) or baseline.get("pin") != pin:
        raise RuntimeError(
            f"QtBridge pin in {PIN_FILE} differs from {BASELINE}; revisit guard on pin bump"
        )
    existing = baseline.get("findings")
    if not isinstance(existing, list) or any(
        not isinstance(item, str) for item in existing
    ):
        raise RuntimeError(f"invalid {BASELINE}: findings must be an array of strings")
    unexpected, stale = set(keys) - set(existing), set(existing) - set(keys)
    printed = set()
    for finding in findings:
        if finding.key() in unexpected and finding.format() not in printed:
            print(finding.format(), file=sys.stderr)
            printed.add(finding.format())
    for entry in sorted(stale):
        print(f"STALE_BASELINE {entry}", file=sys.stderr)
    if unexpected or stale:
        return 1
    if not quiet:
        print(f"Bridge surface: {len(keys)} baselined findings")
    return 0
