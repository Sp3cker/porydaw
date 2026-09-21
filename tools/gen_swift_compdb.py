#!/usr/bin/env python3
"""Regenerate Swift entries in <build>/compile_commands.json from ninja.

CMake's Ninja generator emits `command: ":"` for Swift objects, which leaves
sourcekit-lsp with no build settings ("no input files": no hover, no
references, no diagnostics). This script replaces those placeholder entries
with each target's real whole-module swiftc invocation, extracted via
`ninja -t commands` (printed, never executed).

Background indexing is SwiftPM-only upstream, so compilation-database
workspaces get no global index (no find-references, no workspace symbols).
`--index` closes that gap without touching CMake: it emits each Swift
target to scratch paths with `-index-store-path` into <build>/indexstore
and records that path in the compdb entries, so sourcekit-lsp reads the
build-produced index. Rerun `--index` after editing Swift sources; the
index goes stale otherwise. `--check` exits 0 when the index is fresh,
1 when `--index` needs rerunning (also on toolchain change).

Usage:  python3 tools/gen_swift_compdb.py [build-dir] [--index] [--check]
Rerun whenever CMake reconfigures (it rewrites compile_commands.json).
Safe: <build>/ is gitignored; C++ entries are passed through untouched.
"""
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

ARGS = sys.argv[1:]
DO_INDEX = "--index" in ARGS
DO_CHECK = "--check" in ARGS
ARGS = [a for a in ARGS if a not in ("--index", "--check")]
ROOT = Path(__file__).resolve().parent.parent
BUILD = Path(ARGS[0]).resolve() if ARGS else ROOT / "build"
NINJA_FILE = BUILD / "build.ninja"
COMPDB = BUILD / "compile_commands.json"
INDEXSTORE = BUILD / "indexstore"
STAMP = INDEXSTORE / "swiftc-stamp.txt"

# `-output-file-map` is remapped, not dropped: `-wmo` multi-output index
# units require per-file outputs, so object/dependency paths are rewritten
# into the store's scratch dir instead of the real build tree.
REMAP_KEYS = {"object", "swift-dependencies", "dependencies", "diagnostics"}


def swift_edges():
    """Yield (lib_output, [abs swift sources]) for each Swift link edge."""
    text = NINJA_FILE.read_text()
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^build (\S+) .*Swift_STATIC_LIBRARY_LINKER", lines[i])
        if m:
            lib, sources, i = m.group(1), [], i + 1
            while i < len(lines) and lines[i].startswith("  "):
                kv = re.match(r"^  SWIFT_SOURCES = (.*)$", lines[i])
                if kv:
                    sources = [s for s in kv.group(1).split()
                               if s.endswith(".swift") and s.startswith("/")]
                i += 1
            if sources:
                yield lib, sources
        else:
            i += 1


def swiftc_command(lib):
    """Expanded swiftc invocation for a link target (query only).

    `ninja -t commands` also lists transitive deps, so select the edge
    whose `-o` output is this lib; slice from the swiftc executable token
    to drop `cd`/`:`/`&&` prefixes and skip cmake configure lines that
    merely mention a swiftc path.
    """
    out = subprocess.run(["ninja", "-t", "commands", lib],
                         capture_output=True, text=True, cwd=BUILD).stdout
    for line in out.splitlines():
        if "swiftc" not in line or ".swift" not in line:
            continue
        try:
            toks = shlex.split(line)
        except ValueError:
            continue
        for k, tok in enumerate(toks):
            if "=" in tok or ":" in tok:
                continue
            if tok != "swiftc" and not tok.endswith("/swiftc"):
                continue
            rest = toks[k + 1:]
            if ("-o" in rest and rest[rest.index("-o") + 1] == lib
                    and any(t.endswith(".swift") for t in rest)):
                return " ".join(shlex.quote(t) for t in toks[k:])
    return None

def remap_filemap(path_value, lib):
    """Rewrite a whole-module output file map into the store scratch dir."""
    data = json.loads((BUILD / path_value).read_text())
    out = {}
    for srcfile, m in data.items():
        entry = dict(m)
        for k in REMAP_KEYS:
            if k in entry:
                entry[k] = str(INDEXSTORE / "objs" / Path(entry[k]).name)
        out[srcfile] = entry
    dest = INDEXSTORE / "objs" / (lib.replace("/", "_") + "-output.json")
    dest.write_text(json.dumps(out))
    return str(dest)


def index_command(cmd, lib):
    """Whole-module emit command -> index-only emit to scratch paths.

    Faithful redirect of the real build invocation: same mode and flags
    (minus `-O`), outputs (.a/.swiftmodule/.o/.d) rewritten under the
    store scratch dir so the real build tree is untouched. `-typecheck`
    and `-emit-object` variants were tried: the former writes records
    without units, the latter rejects `-wmo` multi-output file maps.
    """
    tag = lib.replace("/", "_")
    redir = {
        "-o": str(INDEXSTORE / "objs" / (tag + ".a")),
        "-emit-module-path": str(INDEXSTORE / "objs" / (tag + ".swiftmodule")),
    }
    toks, out = shlex.split(cmd), []
    i = 0
    while i < len(toks):
        tok = toks[i]
        if tok in ("&&", ":"):
            i += 1
            continue
        if tok in redir:
            out += [tok, redir[tok]]
            i += 2
            continue
        if tok == "-output-file-map":
            out += [tok, remap_filemap(toks[i + 1], lib)]
            i += 2
            continue
        out.append("-Onone" if tok == "-O" else tok)
        i += 1
    return (["swiftc"] + out[1:]
            + ["-index-store-path", str(INDEXSTORE),
               "-index-ignore-system-modules"])


def swiftc_version():
    """First line of `swiftc --version`; index stamp for toolchain drift."""
    r = subprocess.run(["swiftc", "--version"],
                       capture_output=True, text=True)
    return (r.stdout.splitlines() or ["unknown"])[0].strip()


def check_fresh():
    """True when the index store matches toolchain and all inputs."""
    if not STAMP.exists():
        print("no Swift index store; run: deno task lsp:swift")
        return False
    if STAMP.read_text().strip() != swiftc_version():
        print("swiftc toolchain changed; run: deno task lsp:swift")
        return False
    mtime = STAMP.stat().st_mtime
    stale = [str(p) for p in (NINJA_FILE, COMPDB, Path(__file__))
             if p.exists() and p.stat().st_mtime > mtime]
    try:
        entries = json.loads(COMPDB.read_text())
        sources = [e["file"] for e in entries
                   if e.get("file", "").endswith(".swift")]
    except Exception:
        sources = []
    stale += [f for f in sources
              if Path(f).exists() and Path(f).stat().st_mtime > mtime]
    if stale:
        print(f"stale Swift index ({len(stale)} newer inputs);"
              " run: deno task lsp:swift")
        for f in stale[:10]:
            print(f"  {f}")
        return False
    print(f"Swift index fresh ({len(sources)} files)")
    return True


def main():
    if DO_CHECK:
        sys.exit(0 if check_fresh() else 1)
    if DO_INDEX:
        (INDEXSTORE / "objs").mkdir(parents=True, exist_ok=True)
    compdb = json.loads(COMPDB.read_text())
    indexed_cmds, fixed, missing, failed = [], 0, [], []
    for lib, sources in swift_edges():
        cmd = swiftc_command(lib)
        if not cmd:
            missing.append(lib)
            continue
        if DO_INDEX:
            indexed_cmds.append((lib, index_command(cmd, lib)))
            cmd += f" -index-store-path {INDEXSTORE} -index-ignore-system-modules"
        entry = {"directory": str(BUILD), "command": cmd}
        by_file = {e["file"]: e for e in compdb}
        for src in sources:
            if src in by_file:
                by_file[src].update(entry)
            else:
                compdb.append({"file": src, **entry})
            fixed += 1
    COMPDB.write_text(json.dumps(compdb, indent=2))
    print(f"fixed {fixed} Swift entries in {COMPDB}")
    for lib in missing:
        print(f"WARNING: no swiftc command for {lib}", file=sys.stderr)
    if DO_INDEX:
        for lib, tokens in indexed_cmds:
            print(f"indexing {lib} ...", flush=True)
            r = subprocess.run(tokens, cwd=BUILD, capture_output=True, text=True)
            if r.returncode != 0:
                failed.append(lib)
                print(f"FAILED {lib}:\n{r.stderr[-3000:]}", file=sys.stderr)
        STAMP.write_text(swiftc_version() + "\n")
        print(f"indexed {len(indexed_cmds) - len(failed)}/{len(indexed_cmds)}"
              f" targets -> {INDEXSTORE}")
        sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
