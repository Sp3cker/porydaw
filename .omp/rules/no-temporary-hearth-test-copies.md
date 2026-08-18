---
name: no-temporary-decomp-copies
description: "Never create ad hoc temporary copies or worktrees of a decomp project"
condition: "(?i)(?:cp\\s+[^\\n]*(?:-[A-Za-z]*[rRa][A-Za-z]*|--recursive|--archive)[^\\n]*(?:/tmp|\\$TMPDIR|mktemp)|rsync\\s+[^\\n]*(?:/tmp|\\$TMPDIR|mktemp)|ditto\\s+[^\\n]*(?:/tmp|\\$TMPDIR|mktemp)|git\\s+[^\\n]*(?:clone|worktree\\s+add)[^\\n]*(?:/tmp|\\$TMPDIR|mktemp)|tar\\s+[^\\n]*(?:hearth-test|pokemon-hearth|pokeemerald|emerald-imperium)[^\\n]*(?:/tmp|\\$TMPDIR|mktemp))"
scope: "tool"
---

Do not create an ad hoc temporary copy, clone, archive extraction, rsync mirror, or worktree of a decomp project. This includes `hearth-test`, `pokemon-hearth`, `pokeemerald`, `pokeemerald-expansion`, and `emerald-imperium`.

For the full sweep, use `tools/run_checks.sh`; isolation belongs in that script, not in agent commands. Run read-only checks directly against the existing checkout. For a mutating check, use the runner's managed scratch path. If neither route supports the task, ask before creating any project-sized fixture.