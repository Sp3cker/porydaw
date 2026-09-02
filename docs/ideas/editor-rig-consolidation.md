# Editor-rig consolidation — one assembly for editor checks

Status: idea (pilot already landed 2026-09-02). Not scheduled.

## Problem

App plumbing moves force broad check churn. Measured on the Qt Quick input
migration:

| commit | app files | check files |
|---|---|---|
| 0adc0dd | 19 | 31 |
| 07cba07 | 15 | 26 |
| 081ca87 | 13 | 19 |
| b8ef8e8 | 10 | 11 |
| cfcbb31 | 7 | 9 |
| 4e7fae2 | 6 | 5 |

Check diffs matched or exceeded app diffs for plumbing-only commits.

Root causes (suite-wide counts):

1. **Every family hand-rolls the assembly.** ~20 check entry points
   privately re-implement the 15-step wiring (timeline → view →
   setDocument → setSong → drawer sections → show → pump → fish →
   zoom/cursor → pump). `automationgesturecheck/rig.{h,cpp}`,
   `rollcheckvoicechange.cpp` `AreaFixture`, `support/songfixture.cpp`
   `SongViewRig`, and the `rollcheck*` satellites each keep a copy.
2. **Object-tree fishing.** 289 `findChild` sites; 24 dig
   `timelineQuickCanvas` → `rootObject()` → input item. Each check holds
   private knowledge of object names and hierarchy shape.
3. **Include fan-in.** 45 of 131 check TUs include 5+ app headers
   (worst: 18). Fishing needs the full types, so checks depend on
   sparse modules directly.

Net effect: one seam move rewrites the same knowledge N times.

## The idea

`checks::support::EditorRig` (pilot exists: `src/checks/support/editorrig.{h,cpp}`)
is the one canonical document-driven assembly:

- builds the timeline, wires the view in SongTab production order
  (`setDocument` → `setSong`), applies drawer/zoom/cursor setup from an
  explicit `EditorRigConfig`;
- resolves the Quick scene/root/input items once — typed accessors
  `view() / timeline() / voicegroup() / voiceInput() / quickScene() /
  quickRoot()` — so checks never fish;
- document and voicegroup are borrowed; destruction clears the view's
  borrows first.

Checks shrink to data + config + scenarios. Understanding a check means
reading it plus one 87-line rig header.

## Pilot evidence (editor-drawer / rollcheckvoicechange)

- 25-line imperative assembly + fishing → 9-line declarative config.
- `AreaFixture` slimmed to `dir + document + voicegroup + rig`.
- 118 call sites moved to accessors; zero assertion edits.
- Two includes dropped from the check.
- LOC: +205 rig, −15 check. Suite 63/63 after.
- Gesture-rig projection: only ~150–200 of its ~990 lines collapse; the
  rest (input host, geometry helpers, event injection, page choreography)
  is legitimately check-specific. **The win is single-sourcing, not LOC.**

## Migration waves (each independently verifiable, abortable)

1. `automationgesturecheck` — rig becomes `EditorRig + AutomationInputHost
   + automation geometry helpers`. Sequencing note: lane points are seeded
   before timeline build; document mutation must precede `EditorRig::create`.
   ~150–200 LOC net. *(Implementation: `task` subagent; verify with
   `deno task verify --filter automation-gestures`.)*
2. `rollcheck*` satellites (`rollcheckpsgvelocity`, `rollcheckautomation*`,
   `rollcheckdrawer`, `rollcheckplayhead`) — each drops its embedded
   assembly block; the mega-TUs get easier to split afterwards (follow-up,
   not part of this idea). *(Mechanical sweeps: `sonic`; review `reviewer`.)*
3. `hostcheck`, `pitchbendcheck` — fishing sites move to rig accessors;
   focus/popup assertions stay as-is.
4. Fold `SongViewRig` (`support/songfixture.cpp`) onto `EditorRig` so its
   ~11 consumers share the same assembly. Preserve its exact behavior
   (non-native window check, setSong-before-setDocument order, no resize).

Each wave: migrate, `deno task build:checks`, full `deno task verify`
(63/63 required), `deno task format`. Assertions are never rewritten
during migration — same test strength, less plumbing.

## Non-goals (explicit)

- **No app-code changes** (a later, separate tiny change could name the
  `fontPx(13.0/3.0)` / `17.5 + 13.0/3.0` layout constants once — six
  production files plus checks re-derive them today).
- **No assertion rewrites.** Implementation-state asserts
  (`windowType() == Qt::Tool`, focus bookkeeping, exact rect equality)
  still break on behavior-preserving refactors; fixing those is
  per-assertion judgment, not structure.
- **MainWindow/session-level checks** (`tabcheck`, `mainwindowroutingcheck`,
  selftests) sit on the SongTab lifecycle seam — out of scope; they would
  need their own equivalent or stay as-is.
- **Window-system flakiness** (`rollcheck`, `automation-gestures` under
  full-suite load) is unrelated.

## Decision checkpoint

Migrate one more satellite (e.g. `rollcheckautomation_popup`, ~8 lines of
fishing) and observe the next Qt Quick seam-move commit: check-file count
should drop from ~26 toward the number of checks whose *asserted behavior*
actually changed. Judge the remaining waves on that.
