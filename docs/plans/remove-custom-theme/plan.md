# Remove custom theme implementation plan

> **Execution:** Porydaw's local rules `rule://sdd-triage-gate` →
> `rule://sdd-execution-loop`, laid out per `sdd-plan-writing` (`spec.md` +
> per-task briefs; routes stated here only — briefs carry requirements
> only). Dispatch one brief to a fresh brief-first implementer, then apply
> the task-scoped spec/quality review gate. Implementers never commit or run
> project-wide validation.

**Goal:** Reduce the application to exactly the three fixed preset themes (Vanilla, Dark Neutral High, Immaterial). Delete the Custom theme mode, its OKLCh color picker, the hex/swatch editor, all color-derivation policy code, and every check that exists to prove the custom picker works.

**Architecture:** `themes::ThemeSelection` becomes `{ ThemeMode mode, int gridLineContrast }`; `ThemeMode` loses its `Custom` member and `ColorPair` disappears. `themeresolver` keeps only the fixed preset tables plus the small helpers `withGridLineContrast` still needs. The theme dialog keeps three mode radio buttons, the grid-line-contrast slider, and Apply/Close; the preview/commit controller flow is unchanged. Stored settings `theme/mode == "custom"` migrates to Vanilla on restore. Behavior details and the verified removal inventory: [spec.md](spec.md).

**Technology:** C++20, Qt 6, existing QtTest harnesses, Deno build/verify/format tasks. No new files except this plan directory.

## Global Constraints

1. Clean cutover: no `ThemeMode::Custom`, no `customColors`, no `ColorPair`, no `isValidColorPair`, no `derive()`, no `OklchPicker`. Deleted code is deleted, not stubbed or commented out.
2. Grid-line-contrast slider and its live preview survive untouched. They are shared preset UI, not custom-theme UI.
3. Settings contract: `theme/mode` values `vanilla`, `dark-neutral-high`, `immaterial` parse as today. Any other stored value (including legacy `custom`) restores Vanilla with the stored grid-line contrast. Legacy orphaned keys `theme/primary` and `theme/accent` are removed once on restore.
4. `lsp references` before deleting every public or cross-file symbol. Color-math functions with runtime consumers stay; only `shiftOklabLightness` and `oklabLightness` (derive-only) go. See the verified removal inventory in [spec.md](spec.md).
5. No dialog UX redesign beyond removing the custom editor: mode buttons preview on click, Apply commits, Close/reject rolls back — exactly today's preset behavior.
6. Checks change only where they assert custom-theme behavior. Preset coverage (`themeCompleteness`, `gridContrast`, dialog geometry, font, dark-base, scale) is kept. Add one migration row: stored `custom` mode restores Vanilla.
7. Use deno task only. Verification policy (stated once, here): writers skip format/build/lint/tests; the controller runs `deno task verify --filter themelayout --verbose` at every task boundary, `deno task format` + `deno task build:app` + `deno task build:checks` + full `deno task verify` at the end. Acceptance predicates in briefs name the checks; who runs them is decided by this line. Any failing check is reported and resolved before handoff.
8. Source line numbers in the briefs are navigation evidence, never patch anchors.
9. Every check file a task breaks is owned by that task, not deferred: task 1 owns `themeDialogGeometry` and the scale-test picker removal; task 2 owns all of `tst_themelayout_settings.cpp`; task 3 owns `tst_themelayout_color.cpp` + `tst_themelayout.h` and verifies chrome/settings are clean. Shared files (e.g. `tst_themelayout.h`) may be edited by earlier tasks for their own deletions — ownership means responsibility for leaving the file's suite green, not exclusive edit rights.

## Tasks

| # | Route (triage signal) | Brief | Scope |
| --- | --- | --- | --- |
| 1 | SDD-track — multi-file with an interface between steps (dialog shape is task 2's input), mid-flight verification (signals 1, 4). Seat `sdd-implementer`: removal-only widget surgery, no QObject-ownership/threading/model-contract judgment, so `qt-cpp-reviewer` is not seated. | [task-1-brief.md](task-1-brief.md) | De-customize `ThemeDialog`; delete `oklchpicker`; fix `tst_themelayout_scale` + `themeDialogGeometry` |
| 2 | SDD-track — `ThemeSelection` shape change consumed across files; settings migration contract needs cross-task context (signals 1, 5). Seat `sdd-implementer`. | [task-2-brief.md](task-2-brief.md) | `ThemeController`: remove Custom/ColorPair/custom persistence + settings migration; rework `tst_themelayout_settings` |
| 3 | SDD-track — six-file public-API deletion, every symbol gated on `lsp references` (signals 1, 4). Borderline Direct (the inventory is caller-verified and the steps are decided), but over the Direct file cap with one shared verification surface. Seat `sdd-implementer`. | [task-3-brief.md](task-3-brief.md) | Delete `derive()`, derive-only helpers, `isValidColorPair`; rework `tst_themelayout_color`; verify chrome/settings clean |
| 4 | Direct — mechanical, reversible, single predicate (full suite green). Inline below; no brief file. | — | Leftover sweep, comment touch-ups, manual note, status line |

Tasks are strictly sequential: each removes a compile boundary the next depends on (dialog → controller → resolver).

### Task 4 (Direct, inline)

**Target:** `src/ui/theme/presetcolors.h`, `src/ui/theme/themeruntime.cpp` (comments only), `docsrc/manual/appearance.md`, `docs/plans/remove-custom-theme/plan.md` (status line); leftover references anywhere in `src/`, `docs/`, `docsrc/`.

**Change:**
1. Sweeps (all `grep` with explicit narrow paths per repo search discipline): `ThemeMode::Custom|customColors|ColorPair|isValidColorPair` over `src` → zero hits; `oklchpicker|OklchPicker` over `src; docsrc; docs` (build files included) → zero hits; `derive\(` over `src/ui/theme` → zero hits; `-i "custom"` over `src/ui/theme; src/checks/themelayout` → only legitimate non-theme hits, rewrite stale comments.
2. `presetcolors.h`: reword the "walked toward black by the same policy Custom themes use" comments (`:337-347`) so the policy reads as the preset palette's own documented rule. No color values change.
3. `themeruntime.cpp`: `:599-600` "custom-painted timeline widgets" means custom-*painted*, unrelated to the deleted Custom *theme* — reword only if it now misleads.
4. `docsrc/manual/appearance.md`: replace the TODO stub with a short factual note — three built-in themes (Vanilla, Dark Neutral High, Immaterial) in View → Theme, plus the grid-line contrast slider.
5. Add a **Status** line to this plan stating tasks 1–4 landed with the verification evidence.

**Acceptance:** the task-4 sweeps above all return the stated results; `deno task format` clean on touched files; `deno task build:checks` passes; `deno task verify --filter themelayout --verbose` passes (custom-picker tests absent, migration row present); full `deno task verify` passes. Any failure: `git stash` the edits, re-run that harness once for a baseline per AGENTS.md, then reason from the output and bring persistent failures to the user.

## Acceptance (final)

- `deno task build:app` and `deno task build:checks` pass.
- `deno task verify --filter themelayout --verbose` passes with custom-picker tests gone and the migration row present.
- `themeDialogGeometry` asserts 3 mode buttons; `settingsRepair` covers legacy custom → Vanilla with a non-default contrast honored; `themePersistence` round-trips all three presets including vanilla.
- `grep -i "custom|oklchpicker|derive"` over `src/ui/theme` returns only `presetcolors.h` policy comments rewritten in task 4 and no `ThemeMode::Custom`.
- No dangling CMake/registry references to `oklchpicker`.

**Status:** tasks 1–4 landed 2026-09-11 on `feature/remove-custom-theme` — `deno task format` clean, `build:app` + `build:checks` pass, `verify --filter theme` passes (geometry asserts 3 buttons, migration row custom→Vanilla @80 present), full `deno task verify` 90/91 ok with 1 skipped (one transient `trackheaderquickcheck` failure passed on isolated re-run and a clean full re-run). Thermo-nuclear review then blocked on: missing `Q_UNREACHABLE()` in `resolve()`, dead `previewDraft`/`updateUi`/`Draft`-vs-`ThemeSelection` wrappers in the dialog, a split anonymous namespace + dead include in the resolver, plus advisories (legacy-key extraction, loud unknown-name fallback, comment grammar) — all applied in a fix-up pass; final `format` clean, full `verify` 90/91 ok, 1 skipped.
