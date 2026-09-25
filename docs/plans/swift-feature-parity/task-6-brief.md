# Context
Repair R10/R11: the ghost projection expanded noteSummary to all tracks, but old QML checks still assume primary-only notes; the shell exact command-count assertion also pins the old implementation. These failures were already observed; do not rerun them to confirm. Read plan.md Global constraints and spec.md.

# Exact write set
- src/checks/editorqml/tst_EditorDrawer.qml
- src/checks/editorqml/tst_ShellClipboard.qml
- src/checks/editorqml/tst_ShellWindow.qml

# Prerequisites
Existing production noteSummary includes ghost, track and selected fields. Ghosts are visible but intentionally noneditable.

# Interface contract
Check helpers explicitly distinguish editable primary notes from whole-document projections. Velocity assertions compare primary note identities and values, clipboard pointer fixtures select editable notes, expanding paste verifies both target tracks and cursor/history effects. Remove incidental exact menu-count assertion; retain meaningful required mounted commands and their behavior, not a new count pin.

# Implementation steps
1. Read complete affected tests and all helper consumers.
2. Migrate ghost-sensitive helpers without hiding genuine cross-track paste, undo, remap or source-preservation defects.
3. Assert expanding paste against primary/outer tracks explicitly; keep real pointer/key routes.
4. Delete wording/count-only assertions rather than repinning them; preserve consumer-visible required menu actions.
5. Remove stale comments in affected constructs; no unrelated restyling.

# Acceptance predicate
The complete drawer lane and shell clipboard/window lanes pass without weakening behavior coverage: controller runs `deno task verify:qml --verbose` and `deno task verify:shell --filter shell-clipboard --filter shellwindow --verbose`.

# Task-specific constraints
SHARED_TREE. Skip gates, tests, lint, formatters, commits and scratch reports. No production edits. Report any actual production bug with precise evidence rather than accommodating it.
