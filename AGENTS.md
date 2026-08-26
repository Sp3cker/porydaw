# AGENTS.md — Porydaw agent guide

This file is for AI agents working in this repo. Humans can ignore it.

## Project map

```
src/
  main.cpp + mainwindow.{h,cpp}   # app shell, tab/session lifecycle, engine wiring
  songsession.h                   # per-tab SongDocument + undo + view state
  core/       — SongDocument, MidiTimeline, Smf, midiimport, scale, mid2agb LUTs
  project/    — DecompProject, SongRegistry, VoicegroupSource, SampleReg, sidecars
  audio/      — AudioEngine, resonance_suppressor, sample DSP/import, poryaaaa compat
  ui/         — all Qt widgets
    ui/songview.{h,cpp}
    ui/editordrawer/              # well-factored example: one concept per file
    ui/theme/                     # color roles, resolver, runtime, picker
    ui/activity/                  # track activity meters
    ui/*.cpp                      # other widgets (transportbar, voicegroupbrowser, etc.)
  checks/     — test-only harnesses and their C++ registry
tools/        — Deno check/format runners, porydaw_render_cli
external/     — poryaaaa (submodule), dr_libs, stb
docs/ docsrc/ — spec, plans, manual
```

Harness root is `src/checks/` — never add a new `*check.cpp` to `src/` top-level.

## Search discipline — REQUIRED

**Never `grep` without `path`.** Root scans hit 34 harnesses + `external/` + `build-*/` and time out.

```
# BAD
grep pattern="velocity"

# GOOD
grep pattern="velocity" path="src/ui/songview.cpp"
grep pattern="SongDocument" path="src/core"
grep pattern="voicegroup" path="src/project"
ast_grep pat="SongDocument::$FUNC" path="src/core"
lsp references file="src/core/songdocument.h" line=91 symbol="SongDocument"
```

Workflow:
1. `glob path="src/ui/editordrawer"` or `read` the directory listing to discover files.
2. `grep`/`ast_grep` scoped to that folder.
3. `lsp definition/references` for symbols — follows re-exports that text search misses.
4. range reads, never whole 3000L+ files hoping.

Scopes by concern:
- Piano roll / notes / velocity: `src/ui/songview.cpp; src/ui/editordrawer; src/core`
- Voicegroup / samples: `src/project; src/ui/voicegroupbrowser.cpp; src/ui/samplepicker.cpp`
- Playback / engine: `src/audio; src/core/timelineplayer.cpp; src/core/miditimeline.cpp`
- Theme / layout: `src/ui/theme; src/ui/layout.cpp; src/ui/typography.cpp`
- Harnesses: `src/checks` — only when touching a harness (e.g. `grep pattern="editcheck" path="src/checks"`).

Also: prefer `lsp` over `grep` for renames/references. Don't do cross-file `ast_edit` renames when `lsp rename` exists.

## File-size discipline

- Target 200–400L per file, review cohesion above 600L
- One concept per file. `ui/editordrawer/` is the model.
- Don't create 80L fragments — 40 tiny files in one feature is also undiscoverable.
- See `rule://keep-files-small` for enforcement.

## Build & verify

Agents MUST use `deno task`. Do not invoke `cmake` / `cmake --build` directly;
the tasks configure and compile.

```bash
deno task build:app                          # porydaw app only
deno task build:checks                       # app + checks + mid2agb
deno task verify                             # all harnesses (builds first)
deno task verify --filter rollcheck --verbose
deno task format [--check] [files...]
```

There is no `deno task build`. Pick `build:app` or `build:checks`.
`deno task checks` is the raw harness runner; prefer `verify`.

Any failing assertion or check MUST be brought to the user's attention and resolved before
handoff. Never hand off work with failing assertions or checks.

Project-backed harnesses use checked-in fixtures. The Deno runner gives each
harness a private scratch path and stages only the files declared in
the test-only C++ registry exposed by `porydaw_checks --manifest`.

## Conventions

- C++20, Qt6, `clang-format`. Use C++20 library types. `std::span` is the
  non-owning view; do not add pointer+length pairs or homemade span aliases.
- All widget geometry is `layout::` font primitives. Size, pad, hit-test, and
  stroke with `layout::fontPx` / `layout::fontPxF`, `layout::space`, and
  `layout::singlePixel`. Hard-coded pixel constants in widgets are a bug.
- Checks use fixture files locally from repo. All copying and setup is handled by `tools/run_checks.ts`
