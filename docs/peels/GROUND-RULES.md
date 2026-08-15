# Ground rules for every peel (read this first)

You are porting ONE feature from the branch `specker/cleanup/psg-velocity-history-pr`
into porydaw's `main`. Each peel is executed and reviewed independently; do not pull
in sibling features.

## The peel method

- **Re-implement, don't cherry-pick.** The source branch is built on a ~12k-line
  "editor drawer" rewrite (`src/ui/editordrawer/`) that main does not have and will
  not adopt wholesale. Except where a brief explicitly says a commit cherry-picks
  cleanly, treat the branch as a *behavioral spec*: read its code, port the behavior
  onto main's existing architecture.
- Read branch code with `git show specker/cleanup/psg-velocity-history-pr:<path>`
  (fetch the `specker` remote first if the ref is missing). Never check out or merge
  the branch. Line refs in the briefs point into branch blobs (or into main at the
  time of writing) — re-locate by symbol name if lines have drifted.
- **Precedent:** the Pencil Mode peel — main commits `e5a5393`, `ad7ec32`, `6d48df5`
  ("Add a Pencil Mode for the automation lanes on the B key" and follow-ups). Study
  those commits as the model for scope, commit style, comments, and test approach.
- Work on a new branch off `main`, named after the brief (e.g. `peel/eventlist-robustness`).
  Leave it unmerged; the user merges after their own review and manual test.
  **Never push** — a classifier blocks pushes to main; the user pushes.

## Build & test ritual (non-negotiable)

- Local Qt is 6.2 (CI is 6.9). Builds: `build/` (normal), `build-asan/`
  (`-DPORYDAW_ASAN=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo`). Never verify a change
  through grep-filtered build output — check the build's exit code.
- Harnesses run offscreen against a FRESH scratch copy of a decomp project:
  `QT_QPA_PLATFORM=offscreen ./porydaw --<check> <scratch> [args...]`.
  Copy `~/pokeemerald` (it has a built `tools/mid2agb`) minus `.git` for each run.
  A `--*check` flag missing any of its args does NOT error — it silently launches
  the full GUI and hangs forever under offscreen.
- **Every new test assertion must be negative-tested**: temporarily break the
  behavior in the code, confirm the exact probe fails, then restore. Do this once
  per distinct probe.
- Geometry/mouse probes must pass at `QT_SCALE_FACTOR=1`, `1.5`, and `2`.
- Before declaring done: `tools/format.sh` (clang-format 22), then the full ASAN
  sweep `tools/run_checks.sh build-asan/porydaw ~/pokeemerald ~/teamaqua-pokeemerald`
  (all harnesses must pass) and `ctest` in `build-asan/`.
- Never regenerate samplecheck fixtures (bytes drift).

## Conventions

- Comments state constraints the code can't show; match the file's density and voice.
- Keyboard commands go through `keymap::Registry` (`src/ui/keymap.cpp` Def table) so
  they're rebindable and conflict-checked; plain-letter keys dispatch via
  `SongView::handleEditKey` from focused-widget keyPressEvent (the M/S/B pattern),
  NOT window-level shortcuts — that's what keeps typing in text fields safe.
- User-facing changes get a `CHANGELOG.md` Unreleased entry and a `SPEC.md` update.
- Commit messages: sentence-case imperative subject, body explaining the why;
  mention the source branch.
- MIDI parse layer must stay byte-faithful to mid2agb — never reject data bytes ≥ 0x80.

## Deliverable

A branch with clean commits, all validation green (state exactly what you ran),
plus a written summary: what was ported, what was deliberately excluded and why,
and any open questions for the user's manual test.
