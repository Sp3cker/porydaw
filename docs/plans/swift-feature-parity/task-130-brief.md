# Task 130 brief — roll raster retains ruler columns and exact selection frames at DPR2

# Context

Finish the existing mounted roll's remaining ruler/selection raster conjuncts after task 122 and the split wave. These are concrete consumers, not new render layers or capture-success checks. Task 125 owns structural identity; this task observes ruler binding, time-scope rings, Highlight/Fold tint and the held draw frame in distinct files.

Verified planning selection: **9 open rows (0 GAP + 9 PARTIAL)** from sprint-3 §14.

- `src/checks/rollcheck/static/proof.geometry.txt` — A034, A040, A041.
- `src/checks/rollcheck/proof.keyboard.txt` — A029, A053.
- `src/checks/rollcheck/proof.scale_projection.txt` — A017, A025, A026.
- `src/checks/rollcheck/proof.selection.txt` — A025.

Oracle: `fceecd88`; source pins respectively `85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`, `a1244957bb05a59d62b8912e053d49b2a6f3d771`, `996c6446f2cbfaa5b88ed721df4fa831129bd7bc`, `a1244957bb05a59d62b8912e053d49b2a6f3d771`.

# Exact write set

- `src/swift/app/roll/GridScene+Rebuild.swift`
- `src/swift/app/roll/GridScene+Notes.swift`
- `src/ui/songview/quick/swiftroll/EditorRulerBand.qml`
- `src/checks/rollcheck/static/geometry.swift`
- `src/checks/rollcheck/keyboard_time_selection.swift`
- `src/checks/rollcheck/selection_editing.swift`
- `src/checks/editorqml/GatedVisualsProbe.swift`
- `src/checks/editorqml/ShellNoteVisualsSupport.qml`
- `src/checks/editorqml/tst_ShellNoteVisualsRuler.qml`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/editorqml/tst_ShellGridInputDraw.qml`
- `src/checks/rollqml/tst_SwiftRollPlots.qml`
- The four selected proof files, owned only by the separate ledger writer.

Closed list. Geometry and scale_projection are conditional whole-ledger closures. Keep keyboard A077–A080 and selection A009 open. No native unit is freed by this subset: miditimeline.cpp/h still has workspace/host/automation/routing blockers, and playheadrenderer_macos.mm still has nativegraphics/visual.quick blockers. None is a write target.

# Prerequisites

The accepted task-122 presentation baseline and the split suites. No new task-125 interface and no task-118/119 files, particularly no ShellQmlTests/ShellQmlEntries or shared drawer raster source.

# Interface contract

- Geometry A034 compares the same six actual bar columns before and after explicit 4/4 binding. A040 captures the actual ruler after a 48-TPB bind and checks every fork beat-stem position; A041 compares its bar columns to the pre-bind columns. Model geometry plus a different 24-TPB framebuffer is not evidence. GatedVisualsProbe may stage/restore the copied source's signature/division fixture; it must not supply expected ruler columns.
- Keyboard A029/A053 execute the existing mounted modified-ruler selection and Up journey at observed DPR 2: each covered ghost and the edited primary have the independently expected selection-ring pixels. Retain normal-DPR execution too. Use independent tick/pitch/camera equations and scene offsets for expected physical coordinates, and palette/oracle constants for expected ink, not the tested item's own border/color.
- Scale A017 searches the fixture for an actually unused C/C-sharp/D octave before probing Highlight. A025/A026 retain the occupied folded pitch and bring its real row fully inside the viewport, then prove the exact composite tint and untouched accidental/background samples. These guards belong to the raster consumer; do not add isolated nonempty/projectable/setup-success checks as replacement evidence.
- Selection A025 captures the entire same roll viewport before/after the actual note-name mode toggle while a draw is pending. After the menu has settled, frame dimensions and every pixel are identical; sampling only the face pixel is insufficient. Compare the complete canvas capture, not application chrome whose menu checkmark intentionally changes. Release commits the original pending note once, and an Escape/stale-release variant proves staged pixels never wrote early.
- Repair only demonstrated selected render/rebuild defects. Do not hide reticles, mutate tested item colors, broaden tolerances or add a fake ruler. Existing real input and published model contracts stay intact.

# Implementation steps

1. Extend the existing ruler fixture/rebind journey with exact six-column and 48-TPB raster comparisons.
2. Complete mounted ring, Highlight/Fold and full pending-frame consumers with independent coordinates and negative samples.
3. Run ordinary and environment-selected DPR2 lanes, asserting observed DPR and capture dimensions in the affected consumers; no runner registration change is needed.
4. Give the separate ledger writer the executed row-specific anchors; delete only geometry/scale_projection if their full inventories close.

# Acceptance predicate

Actual framebuffer predicates prove all nine clauses at their original boundaries; ring claims execute at physical framebuffer DPR 2, not only a Swift dpr argument. Full-frame equality and proper fixture occupancy remain part of the consuming predicates.

The implementer runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-note-visuals-ruler --filter shell-grid-input --verbose
QT_SCALE_FACTOR=2 /usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-note-visuals-ruler --filter shell-grid-input --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No session/camera authority, initializer, shell dispatcher, clipboard scope, custom-cursor or runner changes. Every code file stays at most 600 lines. The DPR2 environment is set before the lane process starts; offscreen framebuffer scaling is not a claim of native macOS host-window equivalence.
