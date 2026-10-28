"""Ratchet production QML codegen and dependency-only revision reads."""

import json
import re
import shlex
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

BASELINE = Path("tools/qml_aot_baseline.json")
STRING = r""""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"""
TOKENS = re.compile(STRING + r"|//[^\n]*|/\*[\s\S]*?\*/")
STRINGS = re.compile(STRING)
IDENTIFIER = r"[A-Za-z_$][\w$]*"
REVISION = rf"(?:{IDENTIFIER})?(?:Revision|revision)"
MEMBER = rf"(?:{IDENTIFIER}\s*\.\s*)*{REVISION}"
REVISION_TOKEN = re.compile(rf"(?<![\w$]){REVISION}(?![\w$])", re.ASCII)
BARE_READ = re.compile(rf"^\s*{MEMBER}\s*;?\s*$", re.ASCII)
COMMA_READ = re.compile(rf"\(\s*{MEMBER}\s*,", re.ASCII)
DECLARATION = re.compile(
    rf"\b(?:const|let|var)\s+({IDENTIFIER})\s*=\s*([^;\n]+)", re.ASCII
)


def blank(text: str) -> str:
    return re.sub(r"[^\n]", " ", text)


def without_comments(text: str) -> str:
    return TOKENS.sub(
        lambda match: (
            blank(match[0]) if match[0].startswith(("//", "/*")) else match[0]
        ),
        text,
    )


def revision_dependency_lines(code: str) -> list[int]:
    sites = set()
    offset = 0
    for number, line in enumerate(code.split("\n"), 1):
        if BARE_READ.fullmatch(line) or COMMA_READ.search(line):
            sites.add(number)
        for declaration in DECLARATION.finditer(line):
            if REVISION_TOKEN.search(declaration[2]):
                use = re.compile(
                    rf"(?<![\w$]){re.escape(declaration[1])}(?![\w$])", re.ASCII
                )
                if use.search(code, offset + declaration.end()) is None:
                    sites.add(number)
        offset += len(line) + 1
    return sorted(sites)


@dataclass(slots=True)
class Baseline:
    rejected: int
    total: int
    files: dict[str, int]
    property_var_count: int
    revision_dependency_reads: int
    pragma_allowlist: list[str]

    def json(self) -> dict:
        return {
            "rejected": self.rejected,
            "total": self.total,
            "files": self.files,
            "propertyVarCount": self.property_var_count,
            "revisionDependencyReads": self.revision_dependency_reads,
            "pragmaAllowlist": self.pragma_allowlist,
        }


def read_baseline(path: Path) -> Baseline:
    value = json.loads(path.read_text(encoding="utf-8"))

    def count(number: object) -> bool:
        return type(number) is int and 0 <= number <= 2**53 - 1

    if (
        not isinstance(value, dict)
        or not all(
            count(value.get(key))
            for key in (
                "rejected",
                "total",
                "propertyVarCount",
                "revisionDependencyReads",
            )
        )
        or not isinstance(value.get("files"), dict)
        or not all(
            isinstance(key, str) and count(number)
            for key, number in value["files"].items()
        )
        or not isinstance(value.get("pragmaAllowlist"), list)
        or not all(isinstance(item, str) for item in value["pragmaAllowlist"])
    ):
        raise RuntimeError(
            f"invalid {path}: expected nonnegative counts and a pragma allowlist"
        )
    return Baseline(
        value["rejected"],
        value["total"],
        value["files"],
        value["propertyVarCount"],
        value["revisionDependencyReads"],
        value["pragmaAllowlist"],
    )


@dataclass(slots=True)
class Report:
    current: Baseline
    per_file: dict[str, tuple[int, int]]
    messages: Counter[str]
    revision_sites: list[str]
    banned: list[str]


def analyze(repo: Path, directory: Path) -> Report:
    repo = repo.resolve()
    ui = repo / "src/ui"
    source_files = sorted(path for path in ui.rglob("*") if path.is_file())
    existing = {path.resolve() for path in source_files}
    stats_paths = sorted(directory.glob("module_*.aotstats"))
    if not stats_paths:
        raise RuntimeError(
            f"missing or empty AOT statistics in {directory}; run uv run --no-sync dev checks:qml-aot"
        )
    per_file = {}
    messages = Counter()
    for path in stats_paths:
        stats = json.loads(path.read_text(encoding="utf-8"))
        try:
            for module in stats["modules"]:
                for file in module["moduleFiles"]:
                    absolute = (repo / file["filePath"]).resolve()
                    if absolute not in existing or not absolute.is_relative_to(ui):
                        continue
                    name = absolute.relative_to(repo).as_posix()
                    if name in per_file:
                        raise RuntimeError(f"duplicate AOT statistics for {name}")
                    rejected = 0
                    for entry in file["entries"]:
                        if type(entry["codegenResult"]) is not int:
                            raise RuntimeError(f"invalid codegenResult in {path}")
                        if entry["codegenResult"] != 0:
                            rejected += 1
                            messages[
                                entry.get("message") or "(no rejection message)"
                            ] += 1
                    per_file[name] = (len(file["entries"]), rejected)
        except (KeyError, TypeError) as error:
            raise RuntimeError(f"invalid AOT statistics in {path}: {error}") from error
    per_file = dict(sorted(per_file.items()))
    current = Baseline(
        sum(rejected for _, rejected in per_file.values()),
        sum(total for total, _ in per_file.values()),
        {name: rejected for name, (_, rejected) in per_file.items()},
        0,
        0,
        [],
    )
    if not current.total:
        raise RuntimeError(f"no production QML entries found in {directory}")
    banned, revisions = [], []
    for path in source_files:
        name = path.relative_to(repo).as_posix()
        if path.suffix == ".js":
            banned.append(f"JavaScript file: {name}")
        if path.suffix != ".qml":
            continue
        code = without_comments(path.read_text(encoding="utf-8"))
        structure = STRINGS.sub(lambda match: blank(match[0]), code)
        current.property_var_count += len(
            re.findall(rf"\bproperty\s+var\s+{IDENTIFIER}", structure, re.ASCII)
        )
        revisions.extend(
            f"{name}:{number}" for number in revision_dependency_lines(structure)
        )
        if not re.search(
            r"^\s*pragma\s+ComponentBehavior\s*:\s*Bound\b",
            structure,
            re.MULTILINE | re.ASCII,
        ):
            current.pragma_allowlist.append(name)
        if re.search(r"""^\s*import\s+["'][^"'\n]*\.js["']""", code, re.MULTILINE):
            banned.append(f"JavaScript import: {name}")
    current.pragma_allowlist.sort()
    current.revision_dependency_reads = len(revisions)
    return Report(current, per_file, messages, revisions, banned)


def growth(current: Baseline, baseline: Baseline) -> list[str]:
    failures = []
    if current.rejected > baseline.rejected:
        failures.append(f"Global rejected: {current.rejected} > {baseline.rejected}")
    for path, rejected in current.files.items():
        limit = baseline.files.get(path, 0)
        if rejected > limit:
            failures.append(f"{path}: rejected {rejected} > {limit}")
    if current.property_var_count > baseline.property_var_count:
        failures.append(
            f"property var: {current.property_var_count} > {baseline.property_var_count}"
        )
    if current.revision_dependency_reads > baseline.revision_dependency_reads:
        failures.append(
            f"Dependency-only revision reads: {current.revision_dependency_reads} > {baseline.revision_dependency_reads}"
        )
    allowed = set(baseline.pragma_allowlist)
    failures.extend(
        f"{path}: missing pragma ComponentBehavior: Bound"
        for path in current.pragma_allowlist
        if path not in allowed
    )
    return failures


def run(config: str, verbose: bool, update: bool = False) -> int:
    report = analyze(Path.cwd(), Path("build") / config / ".rcc/qmlcache")
    current = report.current
    compiled = current.total - current.rejected
    print(
        f"QML AOT: {compiled}/{current.total} compiled ({100 * compiled / current.total:.1f}%); {current.rejected} rejected"
    )
    if verbose:
        for path, (total, rejected) in sorted(
            report.per_file.items(), key=lambda item: (-item[1][1], item[0])
        ):
            print(f"{path}: {total - rejected}/{total} compiled; {rejected} rejected")
        for message, count in sorted(
            report.messages.items(), key=lambda item: (-item[1], item[0])
        ):
            print(f"{count} × {message}")
        for site in report.revision_sites:
            print(f"{site}: dependency-only revision read")
    failures = list(report.banned)
    if not update:
        if not BASELINE.is_file():
            raise RuntimeError(
                f"missing {BASELINE}; generate it with uv run --no-sync dev qml-aot:baseline"
            )
        failures.extend(growth(current, read_baseline(BASELINE)))
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    if update:
        BASELINE.write_text(
            json.dumps(current.json(), indent=2) + "\n", encoding="utf-8", newline="\n"
        )
        print(f"updated {BASELINE}")
    return 0


def qmlcachegen_commands(ninja: Path) -> dict[Path, list[str]]:
    """Maps each QML source to the build's exact qmlcachegen argv."""
    commands = {}
    for line in ninja.read_text(encoding="utf-8").splitlines():
        if not line.startswith("  COMMAND = ") or "qmlcachegen --bare " not in line:
            continue
        argv = shlex.split(line.removeprefix("  COMMAND = ").split(" && ")[-1])
        commands[Path(argv[-1]).resolve()] = argv
    return commands


def check_files(config: str, files: list[str]) -> int:
    """Compiles each file with its build command into a scratch directory and lists AOT rejections."""
    build = Path("build") / config
    ninja = build / "build.ninja"
    if not ninja.is_file():
        raise RuntimeError(f"missing {ninja}; run uv run --no-sync dev build:app first")
    commands = qmlcachegen_commands(ninja)
    failed = False
    with tempfile.TemporaryDirectory() as scratch:
        for name in files:
            argv = commands.get(Path(name).resolve())
            if argv is None:
                print(f"{name}: not a production QML file in {ninja}", file=sys.stderr)
                failed = True
                continue
            output = Path(scratch) / "file_qml.cpp"
            argv = list(argv)
            argv[argv.index("-o") + 1] = str(output)
            result = subprocess.run(
                argv, cwd=build, capture_output=True, text=True, check=False
            )
            if result.returncode != 0:
                print(
                    f"{name}: qmlcachegen failed\n{result.stdout}{result.stderr}",
                    file=sys.stderr,
                )
                failed = True
                continue
            stats = json.loads(Path(f"{output}.aotstats").read_text(encoding="utf-8"))
            rejected = sorted(
                (
                    entry["line"],
                    entry["column"],
                    entry["functionName"],
                    entry["message"],
                )
                for module in stats["modules"]
                for file in module["moduleFiles"]
                for entry in file["entries"]
                if entry["codegenResult"] != 0
            )
            print(f"{name}: {len(rejected)} rejected")
            for line, column, function, message in rejected:
                print(f"  {line}:{column} {function}: {message}")
    return 1 if failed else 0
