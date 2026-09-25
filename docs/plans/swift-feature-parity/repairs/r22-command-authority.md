# Context

R22: shell availability/activation must funnel through the existing command authority — `ShellPresenter.actionEnabled(id:)` (lines 183-213) and `ShellPresenter.activate(id:)` (lines 216-271, which re-gates on `actionEnabled` like `QAction::triggered`). Today `TransportBar.qml` buttons recompute actionable state and dispatch around the authority, and `ShellWindow.qml` carries checked-state/startup logic (C1) plus direct startup calls (S1) that bypass it. This bypass falsifies the current ledger claim that `actionEnabled` is "the same gate as QAction::triggered": `proof.clipboardchecks.txt` A011–A014/A026 and `proof.gesturechecks.txt` A073/A074/A080/A093 are MATCHED on that premise. Consolidation repairs the premise, then re-points the cited rows at the new parity predicates. Read plan.md Global constraints and verification.md.

# Exact write set

- `src/swift/app/shell/ShellPresenter.swift`
- `src/ui/shell/ShellWindow.qml`
- `src/ui/shell/TransportBar.qml`
- `src/checks/editorqml/tst_ShellTransport.qml`
- `src/checks/swiftrollgated/proof.clipboardchecks.txt` (rows A011–A014, A026 only)
- `src/checks/swiftrollgated/proof.gesturechecks.txt` (rows A073, A074, A080, A093 only — shared file; R17 touches A065–A068 first, this task lands after it)

# Prerequisites

R17 accepted and checkpointed — its `proof.gesturechecks.txt` edit set is disjoint (A065–A068) but the file is shared, so order after it. The authority exists: `KeybindingRegistry` owns binding data (scope/sequences/labels); `ApplicationSession`'s `EditorCommandRouter` facades (`gridCommandAvailable`, `performGridCommand`, `routeGridKey`, `routeEventListCommand`, `performEventListCommand`, `gridCommandAvailabilityChanged`) own mechanism — R22 does not alter those facades, only calls them.

# Interface contract

- `ShellPresenter.actionEnabled(id:)` remains the only availability computation; `activate(id:)` the only dispatch entry. TransportBar buttons bind `actionable`/`enabled` to `shell.actionEnabled(transport.*)` and dispatch through `shell.activate(id)` — no local enablement logic.
- `checked`/checkable state joins the same authority: add `ShellPresenter.actionChecked(id:)` (view-only projection of the tracked properties the QML switch currently reads — velocity colors, note names, follow, loop, drawer toggles) and rebind `ShellWindow.qml`'s checked-state computation plus its startup initialization to it. QML retains zero policy.
- Any action id `activate` lacks (e.g. transport resonance/suppression parity gaps) is added inside `activate`, not as a second caller path.
- The displayed command result is unchanged: menus, Shortcuts, context menu and transport buttons dispatch identically for the same id.

# Implementation steps

1. Audit `TransportBar.qml` + `TransportButton.qml`: replace local enablement/dispatch with `shell.actionEnabled`/`shell.activate` bindings; identify the exact ids the buttons invoke and verify each is inside `activate`'s switch — add missing ids there (not in the buttons).
2. Add `actionChecked(id:)` to `ShellPresenter` covering the checkable action set; replace `ShellWindow.qml`'s checked-state switch and startup direct calls with authority calls. Preserve `checked` binding direction (tracked property → menu item), never a second write path.
3. Extend `tst_ShellTransport.qml` with transport-button-vs-menu parity predicates: for each transport command, assert `actionEnabled` agrees with the rendered button's actionable state and that both dispatch paths produce identical document/audio effects. Message anchors required.
4. Ledger repairs in this commit: re-point `proof.clipboardchecks.txt` A011–A014/A026 and `proof.gesturechecks.txt` A073/A074/A080/A093 at the new parity predicates where they execute the cited clause; any clause still resting only on the gate-as-proof premise drops to PARTIAL with a one-line reason. No mass edits beyond the named rows.

# Acceptance predicate

One availability computation and one dispatch entry serve every activation surface; mounted parity predicates prove menu/shortcut/button equivalence; the cited ledger rows cite executed evidence or drop honestly.

Controller-run named checks after the writer freezes:
- `deno task verify:shell --filter shell-transport --verbose` — new parity predicates + regression.
- `deno task verify:shell --filter shell-menus --verbose` and `--filter shell-clipboard --verbose` and `--filter shell-grid-input --verbose` — enablement/activation regressions across menu/clipboard/key surfaces.
- `deno task verify --filter swiftcore --verbose` — command-router regression.
- `deno task proof check --executed` and `deno task proof check --strict-mappings`.

# Task-specific constraints

Runs after R17 (shared `proof.gesturechecks.txt`). Do not edit `ApplicationSession.swift` facades, `KeybindingRegistry` data, or `EditCommands`/`EditKeyArbiter` policy — the authority structure exists; this task closes the bypasses around it. No new menu items, no shortcut remapping, no dead-action mounts. If an action legitimately cannot route through `activate` (e.g. needs a target parameter the authority cannot supply), report it instead of building a second dispatcher.
