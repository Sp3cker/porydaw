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
    ui/songview.{h,cpp}           # 6676L god file — needs splitting (see BACKLOG)
    ui/editordrawer/              # well-factored example: one concept per file
    ui/theme/                     # color roles, resolver, runtime, picker
    ui/activity/                  # track activity meters
    ui/*.cpp                      # other widgets (transportbar, voicegroupbrowser, etc.)
  checks/     — in-binary harnesses (42 files: *check.cpp + automationgesturecheck/)
tools/        — run_checks.sh, format.sh, porydaw_render_cli
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
4. `read file:50-120` — range reads, never whole 3000L+ files hoping.

Scopes by concern:
- Piano roll / notes / velocity: `src/ui/songview.cpp; src/ui/editordrawer; src/core`
- Voicegroup / samples: `src/project; src/ui/voicegroupbrowser.cpp; src/ui/samplepicker.cpp`
- Playback / engine: `src/audio; src/core/timelineplayer.cpp; src/core/miditimeline.cpp`
- Theme / layout: `src/ui/theme; src/ui/layout.cpp; src/ui/typography.cpp`
- Harnesses: `src/checks` — only when touching a harness (e.g. `grep pattern="editcheck" path="src/checks"`).

Also: prefer `lsp` over `grep` for renames/references. Don't do cross-file `ast_edit` renames when `lsp rename` exists.

## File-size discipline

- Target 200–400L per file, 600L ceiling. The current outliers (`songview.cpp:6676`, `mainwindow.cpp:3351`, `songdocument.cpp:2289`) are tech debt — see `BACKLOG.md`.
- One concept per file. `ui/editordrawer/` is the model.
- Don't create 80L fragments — 40 tiny files in one feature is also undiscoverable.

## Build & verify

```bash
cmake --build build -j"$(nproc)"          # fast incremental
tools/run_checks.sh build/porydaw          # self-contained full harness sweep
build/porydaw --smfstresscheck           # direct opt-in bounded SMF stress check
tools/format.sh --check                   # CI format gate (clang-format 22)
```

Project-backed harnesses use checked-in fixtures. `tools/run_checks.sh` gives each
harness a fresh private copy because several checks write into the project.

## Conventions

- C++17, Qt6, `clang-format` is law. No speculative abstractions.
- Follow `~/.claude/CLAUDE.md` (Think Before Coding, Simplicity First, Surgical Changes).
- Don't copy `../../hearth-test` to `/tmp` — see `.omp/rules/no-temporary-hearth-test-copies.md`.
