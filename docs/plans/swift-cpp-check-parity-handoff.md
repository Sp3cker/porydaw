# C++ check parity through Swift — handoff

Updated: 2026-09-21.

> Historical task log: the build blocker and dirty-tree instructions below were
> superseded by integration commit
> `682095474e862b90227de941d9a0a5b29ad5926c`. The integrated registered suite
> passes 24/24 and Swift indexing passes 6/6. Use
> `docs/plans/swift-cpp-check-parity-audit.md` for the current parity queue and
> `docs/plans/editor-drawer-swift-refactor-handoff.md` for the next Editor Drawer
> refactor. The remaining sections preserve the earlier investigation and must
> not be treated as current checkout instructions.
>
> Steps 5 and 7 under "Immediate next steps" are superseded by
> `.omp/rules/proof-ledger-workflow.md`: no standalone reconciliation or
> gap-closing passes; ledger rows change only with the surface work that
> proves them.

## Checkout and scope

- Worktree: `/Users/spencer/dev/cProjects/porydaw/.worktrees/swift-qml-grid`
- Branch: `feature/swift-qml-grid`
- HEAD observed at handoff: `d1b7aaf9d55968b677352ff14ad80e7be94ef1a2`
- Pinned C++ behavioral reference: `f3069ef693542bdb63564b80a29773e2f5b2a360`
- Many original C++ sources have been deleted from the current tree. Retrieve them with `git show <reference>:<path>`; do not infer their assertions from Swift test names.
- Large pre-existing staged migration changes coexist with our unstaged additions and unrelated concurrent edits. No commits were made by this task. Do not stage or commit the whole worktree blindly.
- HEAD and build tooling changed concurrently during this task. Reinspect status before continuing; this document is a snapshot, not ownership of every dirty path.

## Latest user decisions — authoritative

1. Focus on passing original C++ behavioral assertions with the production Swift implementation. Pair `<stem>.swift` and `proof.<stem>.txt` with the corresponding C++ check location.
2. Migration-only checks are no longer acceptance criteria. In particular, stop chasing the editorqml DPR image-capture failures. Existing checks were not deleted or weakened to implement this scope change.
3. All numeric inputs must yield Space to the application, but keyboard-shortcut/focus work is deferred. Do not overinvest in recreating C++ host arbitration now; do not mark deferred assertions satisfied.
4. Keep builds **Debug** for iteration speed. Do not switch to Release to evade the current compiler failure.
5. Fix real assertion gaps; production Swift and QML fixes are allowed. Preserve and adapt original QML rather than creating replacement QML files that duplicate existing C++-backed views.
6. Use subagents where useful. Run the requested OMP thermonuclear review and address sound findings.
7. No architectural workarounds, new C++ presenter/test bridges, redundant dispatchers, or production test-only APIs. Preserve unrelated work.

## Immediate next steps

1. **Revert the unsuccessful one-line diagnostic probe** in `src/swift/app/drawer/voicechanges/VoiceChangesProjection.swift:17`. It currently reads:

   ```swift
   public var labelRect: [String: QVariantSettable] = ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0]
   ```

   Restore the original initializer only:

   ```swift
   public var labelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
   ```

   The probe did **not** fix Debug compilation. It was left in place only because the user interrupted to request this handoff. Do not present it as a production fix.

2. Resolve the Debug compiler failure below without adding redundant protocol conformances or switching optimization modes.
3. Run `deno task verify --filter swiftcore --verbose` on the final source state. This executes the paired Swift checks, not the retired C++ implementation.
4. Fix any new assertion failure against the pinned C++ fixture/sequence, not against migration-only expectations.
5. Reconcile proof dispositions with actual passing execution. Some new mappings are structurally equivalent but still await runtime evidence.
6. Run `deno task lsp:swift` after the build/Swift edits, as required by AGENTS.md. Run `git diff --check` and review the final delta.
7. Continue remaining original C++ assertion gaps. A passing presenter check does not prove original rendered-row clicks, popup ownership, native focus, or key delivery.

## Current Debug build blocker

Commands attempted:

```sh
deno task verify --filter swiftcore --verbose
deno task build:app
```

Both now reach Swift compilation and fail at:

```text
src/swift/app/drawer/voicechanges/VoiceChangesPage.swift:161:25:
error: type 'VoiceMarkerHandle' does not conform to protocol 'QVariantGettable'
public var markers: QListModel<VoiceMarkerHandle> = QListModel()
```

Confirmed cache settings: `CMAKE_BUILD_TYPE=Debug`, `CMAKE_Swift_FLAGS_DEBUG=-Onone -g -incremental`.

Evidence and probes:

- `VoiceMarkerHandle` in `VoiceChangesProjection.swift` imports QtBridge and has `@QtBridgeable`.
- The macro declares/emits `QObjectBuildable` conformance; that protocol inherits `QVariantGettable`. The marker source is included in the failing compiler invocation. There is no missing-file/import/macro diagnostic establishing a simple omitted conformance.
- A Debug non-whole-module macro/type-check dependency was suspected, **not established**.
- Moving the generated incremental record `build/src/swift/app/CMakeFiles/PorydawApp.dir/Debug/PorydawApp.priors` aside did not fix the error. Its recoverable backup is `/tmp/porydaw-swift-debug-cache.pDlX1W/PorydawApp.priors`. This was not a full clean build.
- Replacing the self-referencing rectangle initializer with an equivalent literal also did not fix it. Revert that probe as described above.
- Do not add manual `QVariantGettable` conformance or type-erase the model merely to silence this error.
- Current logs: `/tmp/drawer-debug-app.log` and `/tmp/drawer-cpp-parity-current.log`. These are local diagnostics, not durable acceptance evidence.

### Build setup issues already addressed

- Verification tasks initially failed before configuration because the toolchain selector reads `HOME` but Deno did not allow it. This task added only `HOME` to the existing environment allowlists for `checks`, `verify`, and `verify:qml` in `deno.json`.
- A concurrently edited QtBridge patch initially failed parsing; it later parsed cleanly without our changing repository patch source.
- The generated dependency checkout still had the previous CMake patch applied (`BUILD_ALWAYS TRUE`), preventing the changed patch from applying. We removed only the four old added lines from generated `build/_deps/qtbridge-src/CMakeLists.txt`; the normal Deno build reapplied the repository patch successfully. No repository patch source was changed by this cleanup.
- Concurrent changes to `tools/cli.ts`, `tools/local_build_environment.ts`, `tools/setup.ts`, the QtBridge patch, and related docs are not ours. Preserve them. They introduce Debug defaults and build-cache distinctions; the user explicitly wants Debug retained.

## Paired check work completed in source

### Automation menus

Files: `src/checks/automation/automationmenus.swift`, `proof.automationmenus.txt`, and wiring in `src/checks/swiftcore/AutomationPageChecks.swift`.

- `drawerAutomationOriginalClearMenus` is new in the latest turn. It reproduces `AutomationEditingTest::contextMenuActionsApplyEffects`: tempo120 BPM and CC10=64 at tick48; Clear tempo, switch away/back, Clear CC10, switch away/back. Checks published Clear rows, accepted actions, menu closure, empty written points, and continued parameter selection.
- `drawerAutomationOriginalRangeMenu` reproduces controller21/LFO value96 at tick48, selects range64, checks menu closure/range/document/history, reopens, checks the selected range, dismisses, and proves no inserted history entry by undoing the preceding lane write.
- Latest addition strengthens the reopened Value range row assertion.
- Proof inventories 15 Clear-method sites and 17 range-method sites. Original native pointer/rendering requirements remain PARTIAL/GAP; Escape is deferred.
- Some proof entries currently say MATCHED while the header says the new run is pending. They describe predicate correspondence, **not a passing latest execution**. Normalize these to pending until the gate passes; do not use them as retirement evidence.

### Voice menus

Files: `src/checks/drawerpresentation/voicemenus.swift`, `proof.voicemenus.txt`, `src/checks/swiftcore/VoiceChangesPageChecks.swift`.

- Added `drawerVoiceOriginalMenuTransactions`, now an explicit top-level suite call.
- Exact original fixture: division24; conductor500000us; channel0 program0/note60 velocity100 ending48; channel1 program5/note48 velocity100 ending48; all endTick384.
- Setup inserts program3 at48 as an **undoable edit before the baseline**.
- Original transaction sequence at empty tick144: insert program7, change to3, delete, then three undos.
- Added 29 original source-site predicates, including exact serialized checkpoint bytes and history identity after each corresponding single undo. These prove history boundaries without exposing obsolete C++ undo-stack internals.
- Original rendered-row click sites112/135/154 and other native assertions remain unproven, not replaced by presenter-state claims.
- This latest sequence has not executed successfully yet because of the Debug compile blocker.

### Earlier drawer additions retained

- `drawerpresentation/voice.swift`: original picker transactions and selected program behavior; additional navigation-boundary checks are explicitly supplemental.
- `drawerpresentation/velocity.swift`: resolved program0 → unresolved blank127 disables prompt/drag → awaited undo restores eligibility. Supplemental, not an invented original C++ assertion.
- `automation/domain/gestures.swift`: exact observed Pan two-sweep sequence and successive undo restoration. Supplemental diagnostic coverage.
- `trackheaders/trackheaderraster.swift`: program127 header completion and awaited undo/redo state/subtitle restoration. Supplemental; old raster check did not assert this undo sequence.
- `selectionkey/localinputtier_text.swift`: original numeric-prompt fixture (CC10 rows48=32,96=64; selected note24/key60/duration24; insertion prompt144 initial64), draft12, no document mutation, preserved selection, cancellation. It does not simulate keyboard delivery.
- Corrected `proof.localinputtier_text.txt`: historical `velocityPromptOwnsKeys` **does** assert Space transport activation at original lines555/566. `numericPromptOwnsKeys` does not. Earlier introductory text incorrectly said neither did.

## Review corrections just applied — not revalidated

OMP report: `/tmp/drawer-cpp-parity-omp.log`. It reviewed tracked unstaged hunks and full untracked files, excluding staged-only changes. It included unrelated concurrent build changes; do not claim its scope was only this task.

- F2: promoted original picker/menu scenarios to explicit calls in `VoiceChangesPageChecks.swift`, removing hidden tail-calls from other scenarios. Kept distinct fixture setup histories; blindly consolidating them would erase the menu fixture's undoable setup.
- F3: moved awaited Pan/header regression calls out of `SessionChecks` and into `AutomationPageChecks` / `TrackHeadersChecks`. The header owner now has a private RunLoop-pumping helper matching the existing test idiom; inspect this new helper during final review.
- F4: extracted the velocity context-invalidation tail into `drawerVelocityVoiceContextInvalidation`, explicitly called after the projection-refresh case in `VelocityPageChecks`.
- F5: moved `drawerOriginalNumericPromptTransaction` out of the automation runner into `SessionChecks` beside the other cross-surface checks. Kept fixture reuse without introducing another abstraction. Removed misleading comment claiming editorqml proved the original keyboard delivery.
- F6: moved supplemental Pan/header functions to file ends; corresponding proof mappings now use function/predicate anchors, refreshed hashes, and stable commands rather than relying on `/tmp` evidence.
- F1 was **incorrect**: OMP claimed QML TestCase `verify()` returns after failure. Installed `/opt/homebrew/share/qt/qml/QtTest/TestCase.qml:527` explicitly throws `Error("QtQuickTest::fail")`. No redundant null guard was added. The affected profile check is also outside the latest acceptance scope.
- F7 (duplicate cache reads in concurrently edited `tools/cli.ts`) was not changed: outside this task's owned changes.
- The suggested further split of supplemental voice navigation checks was not done; keyboard/navigation work remains deferred.

Latest `git diff --check` passed before handoff. No final post-correction build, full suite, or LSP index refresh has passed.

## Historical verification — do not confuse with latest tree

Before the latest Clear-menu / exact voice-menu additions and review restructuring:

- `deno task verify --filter swiftcore --verbose`: PASS, 1 selected harness, 23 unselected; check runtime1.92s. Local log `/tmp/drawer-cpp-proxy-swift.log`.
- Earlier full `editorqml-drawer`: 36 passed, 4 failed, 11 skipped. Two were numeric-Space rows (deferred); two menu lookup failures were subsequently fixed.
- Targeted automation range / voice pointer-menu QML cases then both passed. The enclosing runner still failed DPR2/font12 and DPR2/font16 voice-picker captures. Those capture checks are migration-only and no longer block this task.
- No current all-green app/check result exists after the concurrent Debug build-tool changes.

Earlier drawer failure diagnosis: header undo was asynchronous and the bare Qt test loop did not drain the Swift run loop. Its uncompleted program127 change left exact velocity context unresolved, cascading into later tests. The check driver now uses the existing awaited/pumping bootstrap undo. Menu lookup also needed to follow the existing full-window modal host rather than the old visual subtree. These were test-driver fixes, not evidence of a Swift history bug.

## Subagents and process state

- `/root/drawer_pairs`: source/proof changes complete and holding; no builds or commits.
- `/root/grid_pairs`: ownership/proof changes complete and holding; no builds or commits.
- `/root/core_pairs`: read-only Debug conformance diagnosis complete; no source changes.
- No running build or OMP process was found in the handoff process check.
- The latest user request is to create this handoff, not to continue implementation in this turn.

## Completion standard

Keep original assertions, fixture values, sequence, and transaction boundaries traceable. Record exact production predicates and actual execution. Preserve explicit native-input/rendering and deferred-keyboard gaps. A proof file existing, or a related Swift test passing, does not make the entire C++ file safe to delete. Do not claim the broad audio/core/grid/drawer pairing effort complete from this bounded drawer work.
