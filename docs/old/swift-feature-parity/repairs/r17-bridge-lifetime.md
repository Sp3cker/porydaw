# Context

R17: bridge lifetime has no executing observation of its release half. `verify:bridge` is a declaration guard only. The mounted close handshake exists (`bootstrap.hostClosing()` → `acknowledgeSceneRemoval()` → `ApplicationSession.hostClosing()`/`acknowledgeGridDetached()` in the `swiftroll-window` roll lane and `tst_EditorDrawer.qml:5738`), but nothing asserts what happens to the released proxies: `hasReleased`, `releaseDocumentPresentation`, idempotent double-ack, `pageReleased` → `tabPageReleased` workspace release, and `suspendCallbacks` blocking late camera/playback/document publication into released objects. `src/checks/swiftqtml/BridgeProbeCheck.swift` defines the QML-bindable probe types (`sqp_register_probe_types`) — `selectedReference` stale-holder and `lastReturnedRow` proxy-retention semantics — but registers no executing predicates (`proof.tst_swiftqtml.txt` lines 859-863). The native oracle `tst_swiftqtml.cpp` was deleted in `67544720`; that ledger is 78 GAP / 19 RETIRED, zero S rows. Read plan.md Global constraints and verification.md.

# Exact write set

- `src/checks/swiftqtml/BridgeProbeCheck.swift`
- `src/checks/rollqml/RollQmlTests.swift`
- `src/checks/rollqml/tst_SwiftRoll.qml`
- `src/checks/CMakeLists.txt`
- `src/checks/swiftqtml/proof.tst_swiftqtml.txt`

`src/checks/swiftrollgated/proof.gesturechecks.txt` rows A065–A068 only (QQuickView-replacement/DeferredDelete lifetime rows); the file is shared — touch no other rows.

# Prerequisites

None. Disposal surface exists: `ApplicationSession.hostClosing` (cancel reason hidden on every tab + `suspendCallbacks` + empty-drawer cancel, lines ~514-551), `acknowledgeGridDetached` (~514-517), `isDisposed`/`hasReleased` published flags, `ShellPresenter.beginClose`/`sceneDestroyed`→`closeReady`. The `swiftroll-window` roll entry already executes the handshake bootstrap.

# Interface contract

- New predicates observe the release half: after `acknowledgeGridDetached`/`acknowledgeSceneRemoval`, `hasReleased` is set, double-ack is a no-op, released workspaces go through `pageReleased`→`tabPageReleased`, and post-release publication attempts (camera/playback/document changes) do not reach released proxies (no crash, no model mutation, callbacks suspended).
- `BridgeProbeCheck.swift` gains executing retention predicates if its probe types can run presenter-level (QML-independent half only): a stale `selectedReference` and a `lastReturnedRow` proxy outliving the scene must not reactivate dead objects.
- If probes need a registered lane entry, add it through `src/checks/CMakeLists.txt` and the existing manifest mechanism (entry name + input file + fixtures), matching neighboring entries. Do not touch `src/checks/checkcatalog.cpp`/`checkregistry.cpp` (another owner).
- All new S anchors are message anchors. Rows retired must be representation-only (Qt widget/proxy internals of the deleted native harness), each with a one-line reason and evidence pointer.

# Implementation steps

1. Extend the `swiftroll-window` handshake case (RollQmlTests bootstrap + `tst_SwiftRoll.qml`) to assert the release half: post-detach `hasReleased`, idempotent second acknowledge, and that mutating document/camera after release does not propagate into released proxies or crash. Reuse the existing `hostClosing()`/`acknowledgeSceneRemoval()` bootstrap — do not add a second teardown path.
2. Add BridgeProbeCheck retention/teardown predicates and register them in `src/checks/CMakeLists.txt` if a lane entry is required (mirror the nearest registered Swift check entry). Presenter-level only; do not attempt QQuickView recreation offscreen.
3. In `proof.tst_swiftqtml.txt`, for the lifetime/disposal rows: rows the new predicates prove become MATCHED with message-anchored S entries; rows that pin deleted-native-harness representation become RETIRED-REPRESENTATION with a reason; behavior rows still unproven stay GAP. Fix the ledger's evidence pointer at lines 836-842 (it cites `docs/plans/qtbridge-integration-contract.md`, which does not exist — point it at the real artifact or remove the dangling reference as part of the touched rows).
4. In `proof.gesturechecks.txt`, rows A065–A068 only: where the mounted close/detach execution is real evidence for the QQuickView-replacement/DeferredDelete clause, cite it; keep unproven native-window clauses GAP/NATIVE. S058 remains the replacement-lifetime anchor — do not weaken it.

# Acceptance predicate

The release half of the dispose protocol has executing, message-anchored predicates; BridgeProbeCheck retention semantics run in a registered lane; ledger rows moved only with executed evidence or representation-only reasons.

Controller-run named checks after the writer freezes:
- `deno task verify:qml-roll --verbose` — extended handshake + roll lane regression.
- `deno task verify --verbose` — native runner incl. any new swiftqtml registration.
- `deno task verify:bridge` — declaration guard stays green.
- `deno task proof check --executed` and `deno task proof check --strict-mappings`.

# Task-specific constraints

No production edits (`ApplicationSession`, `ShellPresenter`, QtBridge glue untouched). Do not run builds/checks — controller owns them (SHARED_TREE). Do not adjudicate the non-lifetime `swiftqtml` GAP mass or `hostseams` GAP rows owned by other surfaces (A005–A028 list real surface owners). `QmlEngineAccess`/`qml_engine_host` seam is already removed — do not resurrect it.
