# Task 93 brief — painted note frames and pre-roll/ruler raster

# Context

Own the actual painted roll: tiny-note faces, selected borders, ghost edges,
minimum-zoom outlines, and the pre-roll pad/tick-zero ruler stem. Scene values
alone do not prove these raster laws. Task 97 later consumes the accepted
`GridScene+Notes.swift` and resize ledger; it owns pointer outcomes, not this
painted surface. Custom left/right cursor images are deliberately not selected.

Verified selection: **41 open rows (23 GAP + 18 PARTIAL)**:

- `src/checks/rollcheck/proof.note_rendering.txt`: 25 — A001–A019, A035,
  A037, A047–A050 (13 GAP + 12 PARTIAL).
- `src/checks/rollcheck/proof.resize.txt`: 3 — A022–A024 (GAP).
- `src/checks/rollcheck/static/proof.camera.txt`: 6 — A092, A094–A098
  (PARTIAL). A093 is already closed and is not selected.
- `src/checks/rollcheck/static/proof.geometry.txt`: 7 — A020–A026 (GAP).

Oracle: `fceecd88:src/checks/rollcheck/note_rendering.cpp`, `resize.cpp`,
`static/camera.cpp` and `static/geometry.cpp`; retain each ledger's pinned
revision for exact assertion provenance. `preRollRulerShade` and
`fallbackRulerStemAndBars` are also present at geometry's pin
`85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`. Current seams are
`checkNoteBorders`, `checkGhostNotes`, `GridScene.rebuildNotes`, and
`tst_ShellNoteVisuals.qml`'s mounted image probes, including its existing DPR2
small-font child registered by `ShellQmlTests.swift`.

# Exact write set

- `src/swift/app/roll/GridScene+Notes.swift` — conditional note-paint repair.
- `src/swift/app/roll/GridScene+Primitives.swift` — conditional frame/pad primitive repair.
- `src/swift/app/roll/GridScene+Rebuild.swift` — conditional ruler/pad publication repair.
- `src/checks/rollcheck/note_rendering_borders.swift`
- `src/checks/rollcheck/note_rendering_ghosts.swift`
- `src/checks/editorqml/tst_ShellNoteVisuals.qml`
- `src/checks/rollcheck/proof.note_rendering.txt` — selected 25 rows only.
- `src/checks/rollcheck/proof.resize.txt` — A022–A024 only.
- `src/checks/rollcheck/static/proof.camera.txt` — selected six rows only.
- `src/checks/rollcheck/static/proof.geometry.txt` — A020–A026 only.

No camera-domain, pointer-dispatch, cursor asset, palette redesign, fixture
content or harness registration edits. Palette comparisons use the mounted
palette; do not add a second paint implementation or screenshot baselines.

# Prerequisites

Start after 84/86/87/89 and 90 are accepted. Rebase the camera/geometry ledgers
over 90. Reread 84's workspace/session restoration, 86's `EditorSurface.qml`
focus changes, 87's `tst_ShellWindow.qml` keyboard contract and 89's
`DocumentSession.swift` binding changes; none is writable here. Keep task 82's
content-space scene/camera contract. Group A has one scene writer.

# Interface contract

- Keep the scene primitive models and `rebuildNotes`/camera APIs intact.
  At fractional key height, the selected ring is contiguous, stops at its
  display-scaled weight, and contains an inset dark border on each of its
  four sides. The unselected bottom border terminates the face correctly.
  Tiny notes thin the border instead of dropping it or swallowing the face.
- A ghost edge matches its adjacent interior pixel: no plain-note border or
  selected ring is introduced by this task. At minimum zoom a narrow note
  still paints, has an outline distinct from its face, and retains a visible
  face instead of becoming a dark bar. These are separate raster predicates.
- Painting/probing and fixture unwind preserve exact original song bytes.
  Keep the existing note-name and velocity-value behavior intact while
  retiring only their obsolete native probe-construction obligations below.
- Natural and accidental rows have identical pre-roll pad pixels, while the
  pad differs from the natural-key plot. The ruler pad's upper/lower samples
  differ by at most two channel units and differ from the adjacent chrome.
  Tick zero has the fork's visible upper stem (at least 70% of its sampled
  upper region), and there is no placeholder caption before tick zero.
  Derive all sample coordinates from the real rendered item, font and DPR;
  do not hard-code the old window dimensions.
- Planned dispositions: **24 MATCHED, 17 RETIRED-REPRESENTATION**.
  Retire note-rendering A001, A006, A016, A019, A035, A037, A047–A050
  (native seed/free-cell/frame-free probe construction), camera A092,
  A094–A096 (native band/raster/DPR/key-row probe prerequisites), and geometry
  A020, A023, A025 (native capture/room prerequisites). Their substantive
  sibling raster laws execute on the same mounted surface. Never retire
  a color, border, face, byte-restoration or pad/stem outcome as setup.

# Implementation steps

1. Extend the existing note-frame and ghost check functions only where a
   selected semantic/byte-restoration clause lacks its own anchor. Preserve
   existing messages, including aggregate messages; add distinct predicates
   rather than relabeling them as new evidence.
2. Extend `tst_ShellNoteVisuals.qml` with mounted image sampling for each edge,
   tiny/minimum-zoom face, pad shade and tick-zero stem/caption law. Use the
   real staged project and existing frame/DPR helpers, including the small-font
   DPR2 child. Raster samples, not a nonempty image check, are the deliverable.
3. Repair only demonstrated scene paint divergences. **RED may be absent if
   production already matches; then the check is the deliverable.** No new
   production observation seam is permitted.
4. Update the 24 behavior rows from fresh evidence and retire only the 17
   specified native prerequisites in this same painted-surface change.

# Acceptance predicate

Controller-run after Group A settles. `runNoteRenderingChecks` executes in
`swiftcore-projectsession`; `shell-note-visuals` executes actual mounted raster
probes and its existing DPR2 child. Both are required. Offscreen captures
prove rendered pixels, not physical-monitor cursor/DPR behavior.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-note-visuals --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Every verification process must finish within 180 s (175 s alarm after the
serialized lock). Full shell means all 26 lanes (~40 s warm); full verify is
also mandatory (~10 s warm). Require fresh `swiftcore-projectsession.json`
and `shell-note-visuals.json` in `build/proof-evidence`, including raster
function evidence. Unselected geometry, camera and custom-cursor rows stay open.

# Task-specific constraints

Follow sprint-3 §10: no new C++; Swift 6.4 on touched Swift; comments ≤2 lines;
base-font sizing; WCAG AA takes precedence over pixel parity. Preserve one
keyboard authority, with no second dispatcher, synthetic forwarding, focus
memory or bare-Space chrome capture. No `Qt.callLater` coalescing or new
idempotence guards. One message-anchored predicate per fork clause, old
messages verbatim, real fixtures and no test-only seams. Preferences setup
uses CFPreferences/UserDefaults, not plist bytes. No fixture-content changes;
any approved expansion must list every exact-content consumer first.
Workarounds need user approval. Parked areas, deferred menus and savecore
A016–A026 remain outside this task.
