# Context
R14: verify the relocated QtBridge patch and its batched rectangle rendering contract before the authorized integration checkpoint. Route: SDD-track, Qt-heavy Implement mode, SHARED_TREE. Base: `86c88903661ee6d44a77da505bf4b9fef777f6e0`. Read plan.md Global constraints and linked spec.md. The existing dirty patch relocation/rendering work is an explicitly required predecessor; preserve its behavior rather than replacing the bridge.

# Exact write set
- cmake/patches/qtbridge/qtbridge-object-return.patch
- src/ui/songview/quick/swiftroll/TimelineQuickItem.qml
- src/checks/editorqml/tst_ShellChromeVisuals.qml
- src/checks/rollqml/tst_SwiftRollPlots.qml

Inspect but do not edit `cmake/QtBridge.cmake`, `cmake/patches/qtbridge/PatchQtBridge.cmake`, and the deleted old paths under `src/ui/songview/quick/swiftroll/`. The controller includes both sides of the relocation in the review/checkpoint. Do not edit fetched dependencies or the root/check CMake files owned by task 10. No prior accepted task wrote this exact write set; earlier task 2's allowed files are listed in its brief, and task 8's canvas/contrast files remain frozen.

# Contract
Preserve object-return/optional bridging, QListModel row moves, proxy ownership, the engine-access seam, pinned QtBridge revision, GUI-thread model snapshot publication, render-thread node ownership, draw order, premultiplied alpha, opacity/transforms, clipping, and software-backend rendering. Rendering primitives are a generic Qt boundary, not new C++ application behavior. No new C++ feature, fallback, private bridge mirror or rendering redesign.

`primitiveCount` currently exists only for check bookkeeping; it counts published rectangles, not rendered pixels. `test_pianoRectLayersUseBatchedGeometry` pins implementation flags and nonempty counts. Remove that incidental test rather than re-pin it. The shell chrome check already measures natural/accidental lane colors, keyboard colors, aligned separators, alpha-composited bar/beat lines, camera scroll and hover placement; preserve those outcome predicates.

# Steps
1. Inspect the complete relocated patch and application script for ownership, model notifications, geometry lifetime and atomic relocation/build behavior. Report any substantive defect before widening the write set. The controller has observed the current patch reverse-check succeed against `build/_deps/qtbridge-src`; builds passed before this cleanup.
2. Delete the implementation-only batching test and shell chrome's `primitiveCount` helper/readiness predicates. Keep the real raster/input assertions. Use the existing rendering-readiness primitive if necessary, not another count proxy.
3. Remove the now-unused `primitiveCount` property/signal/getter from the QML wrapper and patched native rectangle item. Remove its count-notification bookkeeping; preserve snapshot/update behavior. Update patch hunk lengths accurately. Scoped search found no other consumers in `src` or the patch.
4. Preserve all remaining bridge changes and native/QML interfaces. Remove obsolete comments only in touched constructs; add no comments. Report the exact permitted declarations removed versus those preserved.

# Acceptance
Controller serially runs after both writers freeze:
- `deno task build:app`: relocated patch applies and the production app links.
- `deno task verify:shell --filter shell-chrome-visuals --verbose`: actual raster colors, alpha, separator alignment and hover behavior.
- `deno task verify:qml-roll --verbose`: roll rendering/input/scroll and scene lifetime.
- `deno task verify:qml --verbose`: shared primitive consumer compatibility.
- `deno task proof check`: no existing anchor lost. Scoped search found no proof anchors for the deleted bookkeeping predicates; do not edit ledgers unless the controller establishes a concrete affected site.
- Native production app launch/capture with `QSG_INFO=1`: controller records the graphics backend and observes the loaded roll, then closes cleanly. No performance or Linux qualification claim from a software/offscreen pass.

No new permanent test merely proving wiring, a count, or forwarding. Do not remove real pixel or input assertions. The user's completed-oracle retirement policy applies only to fully validated surfaces; no whole proof file is identified for retirement in this task.

# Shared-tree execution
Skip builds/tests/lint/formatters during implementation; report `DEFERRED_TO_CONTROLLER`. Perform the prescribed read-only local inspection. No commits, scratch reports, dependency checkout edits or unrelated cleanup. Qt pack self-review plus controller build evidence supplies the quality verdict; a task reviewer still gates spec compliance.

# Accepted result
App build passed (80.68s); check build passed (105.71s). Shell chrome raster lane passed (1.00s), roll lane passed (23.61s), and all four drawer DPR/font profiles passed (36.29s). Final proof structure passed with all current anchors resolved; format check passed. The production app loaded fixture mus_route101 on the Metal backend (Apple M4 Pro, threaded render loop), displayed primary/ghost notes, keyboard and lane geometry, and exited 0 after Cmd-Q. This is no performance or Linux/Windows qualification claim. Qt-pack quality and independent task spec review approved. Both deleted old paths and their new replacements must remain one atomic checkpoint.
