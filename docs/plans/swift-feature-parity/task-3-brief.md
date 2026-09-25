# Existing ruler selection, chip and seek parity

Route: SDD-track, shared tree. Base `1096534c7d3e97c17a785625a93a215459c39d6e`.

## Surface and spec

Current EditorSurface ruler. Pinned C++ `rollcheck` keyboard, ruler_loop_menu and timemenu proofs define modifier sweep scope, exact chip ticks, preservation of inside-selection context and outside-selection seek. Recover original QML input handlers from the pinned revision or pre-widget-deletion `b28f082758e63ef3cd2868f9205b96acfffb94f5`; adapt, do not design a new ruler or controls.

## Write set

- src/swift/app/timeline/RulerMenuPresenter.swift
- src/swift/app/ApplicationSession.swift
- src/ui/songview/quick/swiftroll/EditorSurface.qml
- src/checks/rollcheck/ruler_loop_menu.swift
- src/checks/rollcheck/timemenu.swift
- src/checks/editorqml/tst_ShellTransport.qml

The first five form one cohesive input/policy/integration/check slice. The transport QML check was approved after native desktop verification exposed stale paused playhead presentation. Other paths require controller approval. Ghost lane owns keyboard.swift and consumes existing automation time-selection/selectedTracks. Proof files are later ledger-agent-only.

## Contract

Use existing selection/history/audio authorities. Preserve exact legacy modifier semantics, sounding-note intersection and half-open endpoints. Plain sweep selects primary scope; additive scope is limited to original-check expectations. Preserve inside-selection cursor, exact chip target tick, outside selection background snap/seek, playback lifetime and gesture cancellation. Keep existing context menu/display behavior and newly integrated shell features. No new control, QML file, production C++, fallback dispatcher or code comment.

Seek ruling from pinned `a1244957` mainwindow.cpp: stopped ruler clicks move the edit cursor but do not seek transport; paused clicks request the target sample and immediately re-present the paused playhead. Playing clicks seek through the engine. Preserve the existing single SharedPlayhead authority rather than adding a second clock or pending-state model. The new mounted-shell regression must observe the actual paused result, not only a callback echo.

Add actual behavior predicates to existing registered owned checks. Identify original QML provenance and exact supported A sites/final Swift predicates. Leave unrelated/native-only rows untouched rather than claiming related tests prove them.

## Acceptance and inspection

Controller: `deno task verify --filter swiftcore --verbose`; `deno task verify:qml-roll --verbose`; `deno task verify:shell --filter shell-transport --verbose`; shown cocoa production ruler modifier sweep/context/seek interactions, including paused seek.

Shared builds/tests/formatters deferred to controller. Follow `rule://sdd-execution-loop` local inspection: baseline/final file-local symbols and diagnostics where supported, full construct reads, references before exported-signature changes, allowed versus actual scope comparison; stale/unavailable tooling is not passing evidence. Return full result contract, proof handoff and no scratch reports/commits. Freeze checks after controller verification, then ledger-only update and code/check/proof task review.
