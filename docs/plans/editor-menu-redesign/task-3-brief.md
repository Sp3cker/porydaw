# Task 3 — Active-effect-first MIDI Effects refinement

Continuation/fix pass of the existing accepted menu redesign. User approved all four Impeccable findings. No ownership transfer or Git checkpoint is authorized; preserve the existing uncommitted menus, defaults and stopped-audition work. Captured branch BASE remains 290d15671db8d3e8f2e49d63ecc9579e1ea2d5a0. This task's review compares only its incoming-to-final changes.

## Target
- src/ui/songview/quick/MidiEffectsPanel.qml
- src/swift/app/miditools/MidiEffectsPresenter.swift
- src/checks/editorqml/tst_ShellMidiEffects.qml
- src/checks/editorqml/tst_ShellEffectOutput.qml
- src/checks/editorqml/tst_TextContrast.qml
- src/checks/miditools/MidiEffectsPresenterChecks.swift (existing caller migration; no proof ledger in this directory)
- Controller-owned plan.md and this brief.

One cohesive UI/interaction contract; exception to three-file dispatch default: production presenter/view and all existing consumer checks must cut over together. Implementation stays inline; independent reviews cover behavior and quality after verification.

## Change
1. Show the active effect's document-owned name, canonical controller Live on/off state, editor state/action before other content. These remain available when the catalog entry is offscreen or missing. Scope pacing and pre-roll under Render settings, separate from Input. Live is a state indicator here; the existing Effect Output control remains its single action owner.
2. Show the library only for an empty track or after Change Plug-in. Keep Rescan and folders reachable there. Subsequent user amendment: do not show skipped VSTs. Filter the presenter list to unblocked MIDI producers; remove the obsolete skipped-row role, details/expand/retry controls and presenter retry slot. The scanner retains its canonical blocked catalog and Rescan can re-probe it; do not delete scanner diagnostics or alter its failure policy.
3. Row activation stages a candidate only. Explicit Add Plug-in / Replace Plug-in commits it. Cancel chooser or close changes no effect, input, Live state or history. Candidate identity is presenter-owned and stable across catalog reordering; missing/blocked candidates are invalidated. Do not leave a second immediate-selection public API or stale-index apply route.
4. Preserve PromptOverlay ownership, visible focus, Enter/Return and AX actions, Escape, Space-to-transport priority, scalable metrics, palette pairs, reload/crash/status handling, and all existing objectNames needed by consumers. Empty chooser opens automatically; existing effects open in the active view. On short windows content scrolls, footer stays reachable.
5. Update affected tests to explicit apply; add behavioral assertions for browsing/cancel without document/history changes and explicit replacement. Extend existing contrast coverage to both views. No source-text/wiring/cosmetic-default tests.

## Acceptance
A user can open a loaded effect, identify its plugin and Live state without browsing, edit clearly scoped input/render settings, browse another available MIDI plugin without changing the current effect, cancel unchanged or explicitly replace. Skipped plugins never appear in the chooser. Existing output, lifecycle, transport and contrast checks continue passing.

## Constraints
The task-specific scope supersedes the original plan's no-Swift/no-behavior-change limits only for the presenter candidate/apply contract, two state/name publications, production view and necessary caller checks. No audio, SDK/native, thread, new timers, dependencies, focus manager, generic design system, palette tokens, animations or unrelated changes. Comments at most two lines. No proof ledgers are affected by these QML checks.

## Verification (controller, after sources settle)
- uv run --no-sync dev build:checks
- uv run --no-sync dev checks --filter swiftcore-projectsession --no-windowing-checks --pool=1 (registered suite containing the presenter checks)
- uv run --no-sync dev checks:shell --filter shell-midieffects --filter shell-effect-output --filter shell-text-contrast --no-windowing-checks --pool=3
- uv run --no-sync dev checks:bridge (update baseline only for intentional new/removed exposed properties and slots if required)
- uv run --no-sync dev checks:qml-aot (no new rejected entries)
- uv run --no-sync dev format --check <changed Swift path>
- uv run --no-sync dev lsp:swift
- Observe compiled production surface via native screenshots/AX, using the harness or a safe second app instance; never discard/restart the user's modified song without permission.
Each build/check command has a hard 180-second deadline. Build failure: inspect emitted build.log; do not rerun for details. Record unavailable LSP semantics honestly and use compiled, scoped caller and declaration evidence.
