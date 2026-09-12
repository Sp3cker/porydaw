## 1. Context

Remediation brief R5 fixes signed-off thermo-nuclear findings E-B1 (three parallel command catalogues) and E-B2 (two key recognizers over two catalogues), both SIGN OFF by `QtSignoffFindings`. Today one command edit touches seven coordinated sites: the 21-value `SongView::EditCommand` enum (songview.h:522-544), `editactions.cpp:34-56` kCommandCatalogue, `editkeyrouting.cpp:42-64` kSharedBindings with flipped field order and no drift assert, size-only asserts, the objectName chain (editactions.cpp:82-89), and Task 31's later storage deletion. The two recognizers (`editactions.cpp:123-135` filtering `shortcutContext()==WidgetShortcut`; `editkeyrouting.cpp:68-79` with no filter) answer the same question with two loops, two tables and two filters, with no seam pinning them.

## 2. Exact write set

- `src/ui/songview/editactions.h`
- `src/ui/songview/editactions.cpp`
- `src/ui/songview/editkeyrouting.cpp`

## 3. Prerequisites

- The T22R thermo-nuclear review gate (plan amendment; review of tasks up to 22).
- Ownership serialization: this task's write set precedes [Task R6](task-R6-brief.md), which extends the same three files.

## 4. Interface contract

One canonical table `{EditCommand, keymap id, checkable, windowObjectName, delivery class}` in the songview module (not in keymap — Registry must stay SongView-agnostic), iterated by construction, both recognizers and `installWindowShortcuts`. It replaces kCommandCatalogue, kSharedBindings and the objectName if-chain; both size-only asserts are deleted. Per-command **position identity** is pinned by `static_assert`, not a size assert: the Nth enum value maps to the Nth row. The single recognizer is **delivery-class parameterized**: recognize(key, modifiers, deliveryClass). Without this parameter the remedy is unsafe — the ShortcutOverride path may claim only `EditorRouted`-class keys (otherwise it steals window-scoped keys from real QAction delivery), while the raw key path resolves all classes and then applies window-owner policy (the Copy/SoloTracks declines, preserved by Task R6 as policy data). A naive filter-less unification breaks shortcut arbitration and can double-fire the manually-delivered EditorRouted actions (see the Qt-signoff missed-item "WidgetShortcut-context actions are inert by construction"). With the parameter, `SongView::editorCommandForKey` becomes a forwarder and editkeyrouting's `target()==this` check evaporates — an unbound view has no recognition interest.

## 5. Implementation steps

1. Build the canonical table as internal to editactions.cpp (header exposes only the existing public surface; the table must not leak into keymap or any widget header). One row per shell value of `EditCommand`, field order `{command, keymap id, checkable, windowObjectName, deliveryClass}`.
2. Add `static_assert`s asserting per-position identity (e.g. `row[N].command == EditCommand::…` for every N and a `consistentMax == enumSize`) so kSharedBindings-style drift is a compile error, not a runtime silence. Delete both size-only asserts.
3. Add the delivery-class parameter to recognition. `EditActions::editorCommandForKey` forwards with `EditorRouted` only; the raw-key path (`handleEditKey` via `resolveEditCommand`) calls with the full class set. Remove kSharedBindings and the debt-narrating comment at editkeyrouting.cpp:32-33.
4. Retarget construction, `installWindowShortcuts`, and the objectName back-channel (editactions.cpp:82-89) to single table iteration; the objectName if-chain (E-m8) dissolves.
5. Keep existing reset paths untouched; if the R7 ownership decision has landed as direct membership, do not re-derive related destructor/membership protocol here — R7's shape governs.

## 6. Acceptance predicate

Adding one command to the enum compiles only when the table row (id/checkable/objectName/deliveryClass) is supplied; both recognition paths agree on the same single table; the ShortcutOverride path recognizes only EditorRouted-class commands; no construction/class changes are visible to callers. Named checks: `deno task verify --filter selectionkey --filter rollcheck --filter mainwindow-routing --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. **Spec amendments this brief lands:** spec.md#implementation-contracts bullet "One enum-to-catalogue-ID association serves construction, Window installation and cached Editor recognition" (line "One enum-to-catalogue-ID…") becomes the delivery-class/table identity wording above; the `editorCommandForKey` API row in the EditActions interface table gains the deliveryClass parameter and the ShortcutOverride-claims-EditorRouted-only caveat. Mechanical exception: the table reaches editkeyrouting.cpp, making this a three-file change — no further files may be touched. The Task 31 unreachable-storage deletion still owns removing dead enum-era storage afterwards.
