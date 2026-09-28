# Task 169 brief — grid contrast becomes a real setting in the mounted settings dialog

# Context

Users cannot adjust grid-line contrast: `ShellPresenter.gridLineContrast` is restored
from preferences at startup (`restoreAppearance`, `ShellPresenter.swift:576-588`) but
no surface writes it — the fork's theme dialog (slider → live repaint → Apply commits
`theme/grid-line-contrast` → close reverts to the committed value) has no Swift
counterpart, and `tst_Theme.qml` only seeds the stored value directly. The mounted
settings dialog already exists (`src/ui/shell/settings/SettingsDialog.qml`, opened via
`ShellWindow.qml:167`, with an `settingsApply` commit path and a registered
`shell-settings` lane), so the control lands on an existing surface.

Surface: a grid-contrast control in the mounted settings dialog with live preview and
committed persistence.
Ledger spec: `src/checks/nativegraphics/proof.tst_nativewindowing.txt` A047 (GAP) —
fork `NativeWindowingTest::gridContrastPreviewAndApply` at pinned revision `02dce75d`,
`src/checks/nativegraphics/tst_nativewindowing.cpp:290-306`: dragging contrast repains
the live grid; Apply writes `theme/grid-line-contrast` (100 in the fork case); moving
the control away afterwards previews again; close reverts to the committed value.
Verify lane: `deno task verify:shell --filter shell-settings --verbose`.
Blocked rows left untouched: A002/A008 (Win32 erase), A055–A078 (rendered
shrink/clear/reactivation outcomes needing stimulus current inputs do not produce),
and every other ledger.

# Exact write set

- `src/ui/shell/settings/SettingsDialog.qml` — the contrast control (bounded slider or stepper) with live apply-on-change and the existing Apply/commit semantics.
- `src/swift/app/shell/ShellPresenter.swift` — the contrast setter/commit functions only (`setGridLineContrast`-style action writing the store key through the existing commit path and reapplying `ShellAppearance.apply`).
- `src/checks/editorqml/tst_ShellSettings.qml` — the mounted preview/apply/revert journey.
- `src/checks/nativegraphics/proof.tst_nativewindowing.txt` — A047 only.

# Prerequisites

None. Disjoint from every sibling (only this task touches `ShellPresenter.swift` or
the settings dialog). Read sprint-3 §19.

# Interface contract

The control binds to the presenter's contrast state; changing it repaints the mounted
grid chromatically (observable through the applied palette/grid colors, with the
independent closed-form contrast expectations `tst_Theme.qml` already uses); Apply
persists `theme.grid-line-contrast` through the dialog's existing commit; Cancel/close
reverts to the committed value; reopening the dialog shows the committed value.
Independent literals for the persisted integer and the expected grid color direction.
WCAG AA still beats parity where they conflict.

# Implementation steps

1. Add the presenter contrast action (set + commit + reapply) on the existing store
   key; no new preference names.
2. Add the dialog control with live preview and Apply/Cancel semantics matching the
   dialog's other rows.
3. Drive the mounted journey: change → repaint observation → Apply → persisted store
   value → change away → close → committed value restored (A047).
4. Close A047 in the same commit. Compact form for closed rows: header + `Disposition`
   + one S-citing mapping line; no pasted code.

# Acceptance predicate

A user sets grid contrast in the settings dialog, sees the grid repaint live, and the
committed value persists and survives reopen/revert — the fork's preview/apply
contract on the Swift surface.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-settings --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-theme --verbose
deno task proof check --executed
```

# Task-specific constraints

No theme-dialog resurrection beyond this one control; no new palette math (consume
`ShellAppearance.apply`); hard-coded pixel constants stay out (font-relative sizing).
`restoreAppearance`'s normalization write-back behavior is preserved. Sibling files
and ledgers stay untouched.
