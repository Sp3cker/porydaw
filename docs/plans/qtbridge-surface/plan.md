# QtBridge surface cleanup — plan

Kill the working-memory tax of the Swift↔QML bridge: make QML-visibility a
mechanical fact (guard + convention), then delete the dead surface that agents
currently pay to reason around. Evidence: [audit.md](audit.md) (findings A–J)
re-verified by three read-only scouts plus a persisted deletion-safety pass
([evidence/deletion-safety.md](evidence/deletion-safety.md), whose
load-bearing items were controller-re-checked — see its header caveat)
(2026-09-24, this worktree at `1096534c`); normative target:
[spec.md](spec.md). Briefs live in
`briefs/NN-<slug>.md` (deliberate deviation from the flat `task-N-brief.md`
house style; dispatch quotes these paths).

## Success criteria

1. `deno task verify:bridge` exists, runs before every `verify*` lane's build
   (`tools/cli.ts` `runVerify()`), and passes with an **empty baseline** at
   plan end.
2. The silently-invisible members are resolved and the redundant annotations
   are gone; corrected populations and their derivation live in
   [amendments.md](amendments.md) (78 `@QtTracked` strips, 155 `@QtIgnored`
   strips, 24 exposure dispositions, 8 sugar-optional rewrites);
   `deno task build:checks` and the QML lanes stay green.
3. ~2,010 dead QML lines are deleted (5 unregistered files ≈1,238L + duplicate
   `quick/TrackHeaderBand.qml` 772L); the editorqml `track-headers` pane
   names the production file; `deno task verify:qml --verbose` green.
4. Seven dead `@QtSignal`s (+ their forwarding plumbing and the
   `informationRequested` handler) and the unused context-property seam are
   deleted; shell/roll/editor lanes green.
5. Unreachable ramp presentation machinery is deleted while the sweep-gesture
   `.ramp` math and its checks stay green.
6. `.omp/rules/qtbridge-surface.md` exists (agent-loaded) and
   `docs/plans/qtbridge-integration-contract.md` carries a historical-scope
   header pointing at it.

## Owner's economics (prioritization lens)

1. Bridge = working-memory tax first: nothing today answers "is this member
   QML-visible?" (no compile-time manifest — scout-verified: the macro plugin
   writes no sidecar; `QMetaObjectBuilder.propertyNames` is `internal`).
   → the guard (02) and the convention (01, spec) outrank everything.
2. C/C++ seam tax second: the one unused seam (08) is cheap to delete.
3. Agent reasoning cost: dead code is read and ruled out again by every
   agent; deleting ~2.8k lines of dead QML/Swift (05-07) is near-zero risk
   with the guard proving reachability.

## Audit deltas (re-verified facts that correct audit.md)

| Audit claim | Re-verified | Evidence |
|---|---|---|
| 24 invisible public members (A) | **6 non-private** (3 public, 3 internal); 18 were `private` (invisible by design) | scout sweep; `AutomationHandles.swift:83`, `EventListPresenter.swift:14-15`, `AutomationPage.swift:330,332,336` |
| 72 redundant `@QtTracked` | **65 redundant** + 13 class-typed (required) + 7 inferred-class (required, need annotations) | macro: explicit `@QtTracked` on a supported type is a strict expansion-level no-op (`QtBridgeableMacro.swift:395-438`) |
| Bridged-class properties are auto-exposable (§0.1) | **Never auto-exposed** — `@QtTracked` required (`Extensions.swift:119-121`) | pinned macro source |
| 56 QML files / 49 registered | 57 files; 50 module entries + `PorydawApplication.qml`; exactly 6 unreachable | `CMakeLists.txt:211-268`; `find src/ui -name '*.qml'` |
| `Qt.labs.qmlmodels` import is a nit (F) | **Used**: `TableModel`/`TableModelColumn` | `EventListPage.qml:984-993` |
| `quick/TrackHeaderBand.qml` "survives as fixture" | Fixture `component:` string is **metadata-only** (identity comparison, never loads a path); captures already come from the swiftroll copy via `EditorSurface.qml:150` | `EditorQmlTests.swift:629-679,371-447` |
| `interpolation` might round-trip (G) | App-internal, never persisted; only read at the projection branch | `AutomationParameter.swift:165,195` |

## Decisions on the audit's open questions

- **(a) Ramp machinery: delete the presentation path, keep the math.**
  `interpolation` is app-internal and always `.step`
  (`AutomationParameter.swift:195`), so `ramps` is provably always empty; the
  QML reads are unreachable and already hid one invisibility bug (audit A).
  `AutomationInterpolation.ramp.value(at:from:to:)` has live consumers
  (`AutomationDrawingTransactions.swift:108`,
  `tst_automationdomain.swift:218`) and stays. Git preserves the rest; nothing
  is persisted, so there is no data-compat surface.
- **(b) `@QtTracked`: macro-minimal.** Auto-attach and explicit `@QtTracked`
  produce identical expansion (`QtBridgeableMacro.swift:395-438`), so
  annotation noise buys nothing; the convention is: explicit supported type →
  auto; class/custom type → `@QtTracked`; non-QML → `@QtIgnored` (spec R1-R3).
  Explicit-everywhere was rejected: ~765 annotations of pure noise, and it
  would *hide* the required-vs-redundant distinction the guard needs to check.
- **(c) Delete the ~1,238 dead lines (+ the 772L duplicate).** Membership in
  the module list verified; name sweep found zero live references (the only
  ones are inside other dead files, proof-ledger prose, and the metadata-only
  fixture string). `macdeployqt` scanning (`release.yml:87,162`) only loses
  files it never needed.
- **(d) Guard: Deno script under `tools/`, extending `tools/proof_anchor.ts`'s
  existing Swift/QML scanner, wired as `verify:bridge` + a pre-build hook in
  `runVerify()`.** The exposure rule is purely syntactic in the macro, so a
  text guard is exact at this pin; a `porydaw_checks` runtime-dump harness
  would be exact across pin bumps but costs a bridge patch hunk + harness +
  manifest staging — recorded as the revisit path on any pin change (spec §4).

## Findings dispositions

| Finding | Call | Leverage / where |
|---|---|---|
| A exposure drift | **act** | 03 (6 members) + guard B1 makes the class of bug impossible |
| B dead channels | **act** | 05; guard B2 keeps it dead |
| C variant maps | **defer** | 93 sites, needs bridged value types the pin lacks; equality-gate pattern already mitigates; revisit on pin bump (spec §6) |
| D dead QML | **act** | 06; guard B0 keeps it dead |
| E geometry/contrast | **split** | act: `#D88985` literal (D1); defer: settings lattice, `SongTabs.qml:64-70` extents (documented parity constants), `columnWidths` "dupe" (null-controller bootstrap fallback only — `EventListPage.qml:140-145`) |
| F typing nits | **reject/defer** | labs import is load-bearing (see deltas); `property var` sweep is churn — convention only |
| G ramp machinery | **act** | 07 (decision a) |
| H unused seam | **act** | 08 |
| I doc placement | **act** | 01; AGENTS.md itself is not edited (human permission required) |
| J clean axes | **keep** | recorded in spec §3 Q4 |

## Tasks

All SDD-track via `sdd-implementer` (each has judgment or deletion-surgery
review surface; none is Qt-heavy C++ — 08 is a dead-code deletion, not
ownership work). One Direct task (D1) inline below. Over-cap write sets are
named per the triage rule's mechanical-batch/single-behavior exemption: 04
(guard-enumerated repo-wide strips), 05 (6 files), 06 (6 deletions + 2
edits), 07 (9 files, one ramp path) — each is one behavior with one
verification surface; do not split them.

| # | Brief | Prereqs | Parallel group |
|---|---|---|---|
| 01 | [briefs/01-qtbridge-rule.md](briefs/01-qtbridge-rule.md) | none | P0 (with 02; disjoint files) |
| 02 | [briefs/02-bridge-guard.md](briefs/02-bridge-guard.md) | none | P0 |
| 03 | [briefs/03-exposure-normalization.md](briefs/03-exposure-normalization.md) | 01, 02 | P1 (solo) |
| 04 | [briefs/04-annotation-hygiene.md](briefs/04-annotation-hygiene.md) | 03 | P1 (solo; shared files with 03) |
| 05 | [briefs/05-dead-signals.md](briefs/05-dead-signals.md) | 02, 04 | P2 (∥ 06/07/08; disjoint write sets) |
| 06 | [briefs/06-dead-qml-files.md](briefs/06-dead-qml-files.md) | 02, 04 | P2 |
| 07 | [briefs/07-ramp-machinery.md](briefs/07-ramp-machinery.md) | 02, 04 | P2 |
| 08 | [briefs/08-native-seam.md](briefs/08-native-seam.md) | 02 | P2 |

Serialization reasons: 03→04 share `src/swift/app/**` class bodies and 04's
edit list is enumerated from the guard baseline *after* 03's dispositions
land; 05-08 depend on 04 only to avoid re-editing stripped annotations in
deleted code. P2 briefs touch disjoint files (05: session/presenter/Editor+
ShellWindow QML; 06: dead QML + `EditorQmlTests.swift` + ledger anchors;
07: automation Swift/QML + `tst_EditorDrawer.qml`; 08: `QmlEngineAccess` +
`qml_engine_host.*`).

### Direct tasks (no brief file, per triage rule)

- **D1 PolyphonyPanel literal.** Target: `src/ui/shell/PolyphonyPanel.qml:212`
  (`color: flash ? "#D88985" : panel.colors.buttonBackground`) +
  the `GridPalette` role that owns it. Change: add a named flash-surface role
  to `GridPalette` (e.g. `polyphonyFlashBackground`, value `#D88985`), bind
  the rectangle to it; no literal remains in QML. Acceptance (controller):
  `deno task verify:shell --filter shell-text-contrast --verbose` green; grep
  shows no `#D88985` outside `GridPalette`.
- **D2 (deferred, not dispatched).** The `EventListPage` width dedupe was
  demoted at plan time: `EventListPage.qml:140-145` already prefers
  `controller.savedColumnWidth(column)`, and `defaultColumnWidths` only
  serves the null-controller bootstrap edge — any dedupe changes transient
  pre-mount geometry for no agent-tax win (spec §6 records the deferral).

## Global constraints (all tasks)

- Implementers read [spec.md](spec.md) + this section; briefs carry deltas
  only. Repository rules: `AGENTS.md` (build/verify, search discipline,
  file-size, no code comments), `.omp/rules/proof-ledger-workflow.md`,
  `STYLE_GUIDE.md`.
- **All `deno task` verification is controller-run** (SHARED_TREE): report
  `tests: DEFERRED_TO_CONTROLLER`. Implementers do read-only local inspection
  (LSP symbols/diagnostics, targeted reads) only. Reuse the briefs' recorded
  commands; report mismatches instead of silently narrowing.
- The guard baseline (`tools/qtbridge_surface_baseline.json`) is regenerated
  only by the controller (`deno task verify:bridge --update-baseline`) at
  checkpoints; implementers never hand-edit it.
- Ledger discipline: edit `proof.*.txt` rows only as same-commit anchor
  repairs when a deletion breaks an `Anchor:` line (workflow's allowed case);
  no re-pinning, no disposition churn. Note: `.omp/rules/ledger-delegation.md`
  referenced by the assignment does not exist in this worktree (glob of
  `.omp/rules/` at plan time); `proof-ledger-workflow.md` governs instead.
- Do not edit `AGENTS.md` (human permission required). QML text changes obey
  `.omp/rules/text-contrast.md`. New sources never land in `src/` root
  (`keep-files-small.md`).

## Verification matrix (controller gates)

| Unit | Commands |
|---|---|
| 01 | review; `deno task format:check` |
| 02 | `deno check tools/qtbridge_surface.ts tools/cli.ts`; `deno task format:check`; `deno task verify:bridge`; negative probe (temp `public var zzGuardProbe = 1` in a bridged class → guard fails; revert); `deno task verify:qml --verbose` (pre-hook wiring) |
| 03 | `deno task build:checks`; `deno task verify:bridge`; `deno task verify --filter swiftqtml --verbose`; `deno task verify:qml --verbose` |
| 04 | `deno task build:checks`; `deno task verify:bridge`; `deno task verify --filter swiftqtml --verbose`; `deno task verify:qml --verbose`; `deno task verify:qml-roll --verbose` |
| 05 | `deno task build:checks`; `deno task verify:bridge`; `deno task verify:shell --verbose`; `deno task verify:qml-roll --verbose`; `deno task verify:qml --verbose` |
| 06 | `deno task build:checks`; `deno task verify:bridge`; `deno task verify:qml --verbose`; `deno task proof check` (anchors resolve) |
| 07 | `deno task build:checks`; `deno task verify:bridge`; `deno task verify:qml --verbose` |
| 08 | `deno task build:app`; `deno task build:checks`; `deno task format:check`; `deno task verify:shell --verbose` |
| D1 | `deno task verify:shell --filter shell-text-contrast --verbose`; no `#D88985` outside `GridPalette` |
| Final | all lanes above + `deno task verify:bridge` with **empty baseline** |

**Phase gates:** P0 done = guard runs green on a recorded baseline and the
rule file exists. P1 done = B1 baseline classes (`UNANNOTATED_MEMBER`,
`REDUNDANT_TRACKED`, `REDUNDANT_IGNORED`, `SUGAR_OPTIONAL_RETURN`) are empty.
P2 done = B0/B2 baseline classes empty (deletions landed). Final = baseline
file contains zero entries; full lane sweep green. Checkpoints (Git, batched):
after P1, after P2, at final handoff — controller regenerates the baseline
before each checkpoint commit.

## Risk register

- **R-1 guard false positives.** Mitigation: report only resolvable names
  (spec §4 false-positive policy); baseline escape hatch; `STALE_BASELINE`
  forces shrinkage so the baseline cannot become permanent wallpaper.
- **R-2 annotation strips change behavior.** Mitigated by macro-source proof
  of no-op equivalence (deltas table); `swiftqtml` + three QML lanes as
  runtime backstop.
- **R-3 QtBridge pin bump invalidates the syntactic model.** The
  supported-type constant records the pin hash; revisit = spec §4 dump-harness
  path. Trigger: any change to `cmake/QtBridge.cmake` or the patch.
- **R-4 TrackHeaderBand fixture repoint changes check meaning.** Verified
  metadata-only (`EditorQmlTests.swift:371-447` compares the string; captures
  already render the swiftroll copy). Residual risk: reviewer confirms the
  pane still captures `timelineQuickTrackHeaders`.
- **R-5 ramp deletion vs future feature.** Acceptable: nothing persisted,
  git revert is cheap; the alternative (maintaining unreachable machinery)
  is the tax this plan exists to remove.
- **R-6 hidden consumer of a deleted signal/seam.** Sweeps found zero
  (signals: no QML/Swift/C++ observers; seam: zero callers, `RewriteWindow`
  deleted). Backstop: builds + lanes.
- **R-7 parallel P2 briefs collide on the baseline.** Baseline edits are
  controller-only (Global constraints); implementers leave it untouched.
- **R-8 brief 04 scale (~260 mechanical sites).** Guard-enumerated per-file
  lists; one batch review; fix loop capped per `sdd-execution-loop`.

## Non-goals / do-not list

- No QML visual redesign: settings pixel lattice, `SongTabs` extents, theme
  work beyond D1's single role.
- No automation behavior change: the ramp deletion removes only unreachable
  code; sweep gestures and their checks are untouched.
- No C++ seam migration or new C++: 08 only deletes a dead ABI pair.
- No variant-map typing sweep (C), no `property var` sweep (F).
- No proof-ledger re-pinning, reconciliation, or disposition edits beyond
  same-commit anchor repairs.
- No edits to `AGENTS.md`, no QtBridge pin/patch changes, no new QML files,
  no guard B3 (QML-side role checking) in this plan.
