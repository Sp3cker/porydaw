# Peel 13 — Windows harness-sweep determinism (clean cherry-pick)

> **STATUS 2026-08-11: DONE, MERGED to main** (ff to `3784b6d`) — cherry-pick
> `b3889ac` + review fixes `3784b6d` (uname-gated .exe probe, set -u array guard,
> runDeleteActionCheck filter clear, f.close() why-comment). Windows benefit
> unverified until the user's next Windows sweep (run from git-bash/MSYS).

Read `docs/peels/GROUND-RULES.md` first. Source: branch commit `18c8723`
("test(windows): make harness sweep deterministic"). **This is the one peel that
cherry-picks as-is**: main HEAD is identical to the merge-base for all three
touched files, and the diff has no drawer coupling. Verify that claim first
(`git diff main specker/cleanup/psg-velocity-history-pr -- src/exportcheck.cpp
src/onboardcheck.cpp tools/run_checks.sh` should show exactly three hunks); if
main has drifted, port by hand instead.

## The three hunks

1. `src/exportcheck.cpp:124-126` — explicit `f.close()` after `f.readAll()`. On
   Windows the still-open handle blocks scratch-tree teardown / re-render of the
   same WAV path in the `exportcheck-loop` sweep.
2. `src/onboardcheck.cpp:1851` — `m_songList->restoreFilters(QString(), 0,
   QString());` before `openProjectDir`. Native-format QSettings hits the Windows
   registry, so the harness's `QSettings::setPath()` isolation doesn't apply and
   a song filter persisted from a previous REAL app run leaks into the check,
   hiding the fixture's list item. Cross-run nondeterminism.
3. `tools/run_checks.sh:60-66,94-99` — resolve `$SRC/tools/mid2agb/mid2agb` with
   an `.exe` fallback into a `mid2agb_args` array passed to `roundtrip`,
   `savecheck`, and `onboardcheck`; without it those harnesses silently take a
   degraded path on Windows.

## Procedure

- `git cherry-pick 18c8723` onto a branch off main (rewrite the commit message to
  the repo's style: sentence-case imperative, mention the source branch).
- `tools/format.sh` (the branch predates nothing format-wise, but confirm no
  drift), then the full ASAN sweep on Linux — all three touched harnesses
  (exportcheck ×2 configs, onboardcheck, roundtrip, savecheck) must stay green.
- No new assertions are introduced, so no negative-testing is required; the
  Windows-side benefit can only be confirmed by the user's next Windows sweep —
  say so in the summary.
- No CHANGELOG entry (test tooling, not user-facing). No SPEC.md change.
