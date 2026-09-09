#!/usr/bin/env python3
"""Generate the user manual's Scripting API page from docs/scripting/API.md.

docs/scripting/API.md is the reference porydaw's developers maintain next to
the code (docs/scripting/PLAN.md §6). The manual (docsrc/, MkDocs) republishes
it as reference/scripting.md so plugin authors find it with the rest of the
documentation. This script is that republishing step:

  - a banner marks the page as generated,
  - the title becomes the manual's ("Scripting API"),
  - a note links the manual's own Plugins page for installing plugins,
  - relative links to repository files become GitHub links (the manual is
    served from a different tree),
  - everything else is copied verbatim.

Usage:  tools/gen_scripting_docs.py          rewrite docsrc/reference/scripting.md
        tools/gen_scripting_docs.py --check  exit 1 when the page is out of date
                                             (tools/run_checks.sh and CI run this)
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "docs", "scripting", "API.md")
TARGET = os.path.join(ROOT, "docsrc", "reference", "scripting.md")
GITHUB = "https://github.com/huderlem/porydaw/blob/main/"

BANNER = (
    "<!-- GENERATED FILE: do not edit. Source: docs/scripting/API.md;\n"
    "     regenerate with tools/gen_scripting_docs.py. -->\n"
)

INTRO = """# Scripting API

!!! note
    This page is for people writing their own plugins. For installing plugins and
    porydaw's examples, see [Plugins](../manual/plugins.md). 
"""

LINK = re.compile(r"(?<!!)\[([^\]]+)\]\(([^)\s]+)\)")


def rewrite_link(match, source_dir):
    text, target = match.group(1), match.group(2)
    if re.match(r"^[a-z]+:", target) or target.startswith("#"):
        return match.group(0)
    path, _, fragment = target.partition("#")
    resolved = os.path.normpath(os.path.join(source_dir, path))
    rel = os.path.relpath(resolved, ROOT).replace(os.sep, "/")
    if rel.startswith("docsrc/"):
        # A page of the manual itself: keep it relative to reference/.
        rel = os.path.relpath(resolved, os.path.dirname(TARGET)).replace(os.sep, "/")
        return "[%s](%s%s)" % (text, rel, ("#" + fragment) if fragment else "")
    return "[%s](%s%s%s)" % (text, GITHUB, rel, ("#" + fragment) if fragment else "")


def generate():
    with open(SOURCE, encoding="utf-8") as f:
        lines = f.read().split("\n")
    # Drop the source's own title: the manual page carries its own.
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
    body = "\n".join(lines).lstrip("\n")
    source_dir = os.path.dirname(SOURCE)
    body = LINK.sub(lambda m: rewrite_link(m, source_dir), body)
    return BANNER + "\n" + INTRO.format(github=GITHUB) + "\n" + body


def main(argv):
    page = generate()
    if "--check" in argv:
        try:
            with open(TARGET, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current != page:
            sys.stderr.write(
                "gen_scripting_docs: %s is out of date — run tools/gen_scripting_docs.py\n"
                % os.path.relpath(TARGET, ROOT)
            )
            return 1
        print("gen_scripting_docs: %s is up to date" % os.path.relpath(TARGET, ROOT))
        return 0
    with open(TARGET, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print("gen_scripting_docs: wrote %s" % os.path.relpath(TARGET, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
