# QtBridge integration contract and acceptance gate

Status: proposed integration requirements, recorded 2026-09-19 at the user's request. Runtime guarantees below are NOT yet verified by this assessment. This document preserves the architecture discussion; it does not close Wave 4, authorize implementation dispatch, or silently amend the existing charter. The roadmap pivot must reconcile the charter explicitly.

## Purpose and ownership direction

Target: Swift application/domain logic and QML views, with minimal handwritten C++ Qt application code. Preserve user behavior, not old C++ presenter interfaces. Use direct QtBridge presenters and collections rather than per-surface C++ mirrors. Grid and headers are the first two consumers proving the shared integration.

Keep two distinct interoperability seams: QML-to-Swift presentation, and Swift-to-retained native services such as audio. Do not make one universal dispatcher. One authoritative document/history and one command arbitration authority remain required.

Swift domain types must not be designed around C ABI layouts. Imported C structs, pointer/count buffers, callback contexts and raw enum conversion belong inside native integration adapters. Use Swift-native domain types and operations internally. Fixed-width numeric types are appropriate where musical ranges, identities or arithmetic require them; they are not themselves evidence of an undesirable C interface. Retire the legacy document feeds and command transport when their C++ authority and callers retire. Do not add a wrapper for every surface.

## Dependency baseline

Source evidence, not a runtime certification:

- `cmake/QtBridge.cmake` pins QtBridge to `407714006dd21107b70db6547ce75e43df0c8a75` and requires Qt 6.10 CorePrivate.
- Local patch: `src/ui/songview/quick/swift-grid-prototype/qtbridge-object-return.patch`.
- Patch scope observed during assessment: object-return macro support, optional bridged-object conversion, public QML element registration, and macro build configuration.
- `PianoGrid.swift` uses direct QtBridge exposure; `GridScene.swift` exposes Swift `QListModel` collections.
- Upstream: https://github.com/qt/qtbridge-swift (early-preview dependency).

Before accepting this integration, record actual Qt and Swift versions, bridge and application revisions, build configuration, patch-by-patch purpose/upstream status, relevant pinned-source anchors, exact executed commands, and results. No runtime/toolchain baseline was collected for this document. Changing the dependency or relevant patch invalidates affected verification evidence until rerun.

## Lifetime contract

Before implementation acceptance, fill an ownership table for the application/workspace, document/session, Swift presenter, collection, row objects, Qt proxies, and observer/callback registrations. For each name: creator, lifecycle owner, other retaining references, isolation context, invalidation event, release condition, and teardown ordering. Do not substitute 'Qt manages it' for an owner.

Required invariants:

- Presentation/model mutations execute on the designated GUI-thread/Swift isolation context. Establish how those contexts coincide; an annotation alone is not proof.
- A presenter receives no document callbacks after session detachment.
- Closing one tab cannot invalidate another tab's objects.
- Removed rows cannot remain valid editing targets merely because delegates retain references. Actions resolve stable domain identity, not a stale list position.
- Tab/application closure causes neither use-after-free nor indefinitely retained document graphs.
- QML visibility is not treated as destruction, and proxy destruction is not assumed to release every Swift reference immediately.
- Initial binding, detachment and teardown have an explicit ordered protocol. Identify when new actions stop, pending delivery is invalidated, observers disconnect, and references release. Test the actual protocol rather than assuming a universal deletion order.

## Observable model-update contract

| Operation | Required observable behavior |
| --- | --- |
| Presenter property mutation | Existing QML bindings observe the new value. |
| In-place row property mutation | Relevant existing delegates update without an unrelated refresh. Verify separately from replacing the row. |
| Row replacement | Delegates observe the replacement; stale references cannot edit the new row accidentally. |
| Row insertion/removal | Contents and order update; surviving rows preserve domain identities. |
| Reorder | Selection and actions still address the intended track/note, not its former index. |
| Collection reset/document replacement | Stale delegates and callbacks cannot mutate the replacement document. |
| Editing transaction | Grid and headers observe coherent committed state. Specify whether intermediate notifications are hidden or explicitly safe; do not leave batch semantics implicit. |

Select supported update operations based on pinned-source inspection and runtime proof. Do not claim that a collection wrapper automatically propagates changes to objects contained inside it.

## Evidence ledger

Every guarantee needs: requirement, pinned implementation/source anchor, reproduction scenario, exact command, tested revisions/toolchain, observed result, and status (`Unverified`, `Verified`, or `Unsupported`). Source inspection establishes mechanism; runtime execution establishes evidence. Never silently promote one into the other.

Initial status for all following scenarios: **Unverified by this assessment**.

- Rename a visible track in place without replacing its row; observe actual delegate text.
- Insert/remove/reorder tracks; act on the same stable identity afterward.
- Commit an edit and undo/redo; observe grid and headers from the same session.
- Replace/reset the collection while a transient editor/menu references an old row; stale action must not mutate the replacement.
- Close a tab with a pending notification and open transient UI; verify no post-detachment delivery and observe release/bounded retention.
- Keep another tab open during closure; verify its model and actions remain functional.
- Reopen a document and close the application; verify safe teardown and no retained document graph.

Use focused in-repo scenarios under `src/checks/` that exercise real QML bindings/delegates and the actual integration owner. Pure Swift field assertions do not prove QML propagation. 'Did not crash' alone does not prove release. Keep regressions for plausible lifetime, identity and notification bugs; avoid tests pinning incidental signal counts or internal field forwarding.

An implementing task must register the covering checks and record exact `deno task` verification commands here before marking any row verified. There is no newly implemented harness or runnable new filter claimed by this document.

## Acceptance and maintenance

Direct Swift-to-QML integration is accepted only after the two-consumer scenarios pass with recorded evidence. The header cutover must remove the handwritten C++ header presenter and surface-specific push/pull transport, not merely rename them. Existing legacy document integration retires at its separately specified ownership cutover.

Bridge defects belong in the shared integration and have a focused regression scenario. Do not compensate with surface-specific C++ presenter mirrors. A proposed workaround requires approval under repository rules. Keep any necessary bridge fixes cohesive and central; record upstream disposition and retest on upgrades.

Reference this document from the revised charter/task briefs instead of duplicating its requirements. Preserve single-authority keyboard, popup, text-entry, cancellation, undo and save behavior throughout the pivot.
