# Task 4 — Compact Effects access and actionable header Live

User request: investigate slow VST opening; make the track-header Live control toggle the existing effect on/off; shorten the MIDI Effects button to Effects and make it compact. This brief owns only the header controls. Opening-latency investigation is independent and controller-owned; do not change editor/helper startup for this brief.

## Target and ownership
Implementer write set:
- src/ui/songview/quick/swiftroll/TrackHeaderRows.qml
- src/ui/songview/quick/swiftroll/TrackHeaderBand.qml (verified native text-metric caller)
- src/swift/app/headers/TrackHeaders.swift
- src/swift/app/headers/TrackHeadersGeometry.swift
- src/swift/app/headers/TrackHeadersInput.swift
- src/swift/app/miditools/TrackEffectsController.swift only for a minimal canonical Live command entry point if the current throwing API cannot be safely reused directly; no editor/load/lifecycle refactor
- Existing src/checks/trackheaders/TrackHeadersChecks.swift and TrackHeadersInputChecks.swift; inspect affected proof ledgers before changes and report any required ledger handoff, never reconcile them yourself.
- src/checks/trackheaders/headerfixture.swift and headerinputfixture.swift for the clean-cutover text-metric signature
Controller owns docs, src/checks/editorqml/tst_ShellMidiEffects.qml, the metric migration in MidiEffectsPresenterChecks.swift, render/Live ordering regression in TrackEffectsControllerChecks.swift, builds/index/format/checks/native UI/reviews. Do not edit previously changed menu/presenter/voice/stopped-audition files or controller-owned checks. Over-three-file exception: model geometry, hit targets, row bridge, actual QML and their established checks are one indivisible header contract, not independent tasks.

## Change
1. Split the existing combined effects area into true independent hit/accessibility controls. The rack-opening control says Effects (no ellipsis), remains below voice, and is content-sized with existing font-derived padding rather than filling the header. Keep active plugin identity visible without turning a long plugin name into a wide button (unboxed secondary name if needed).
2. For a track with an effect, show an operable Live toggle in both on and off states. Pointer, Return/Enter, and accessibility press all toggle that exact existing effect via TrackEffectsController.setLive or its minimal canonical command wrapper; do not open the rack. State comes only from the controller. Do not create another Live state machine, runtime registry, dispatcher, timer, swallowing-failure fallback or synthetic key forwarding. Preserve visible stopped/crashed indication and reachability of existing reload recovery without accidental rearming a retired instance.
3. Swift owns every actual hit rectangle and relevant font-derived width policy. QML may report native FontMetrics measurements but must not invent a second geometry/hit-test policy. Hover/press/drag/cancel/right-click routing must target the correct independent control. Retain current objectNames needed by existing consumers, or explicitly report intentional migrations. Bare Space still belongs to window transport, even with Live focused; no selection/voice/reorder/history/content change from toggling Live.
4. Resolve the target effect and current document safely before async work; detach/reorder/delete/session switch must not redirect a queued toggle to another effect. Use the existing lifecycle/control serialization and failure publication, not a duplicate owner. Avoid loading/unloading/recreating the effect merely to turn it off/on.
5. Extend only existing plausible behavior coverage for independent hits/cancel/no reorder and stale targets; delete obsolete implementation/wording pins rather than re-pin. Controller adds production QML on/off/keyboard/Space checks to the existing MIDI Effects journey after source freeze. Comments at most two lines; explicit Swift closure parameter types; no new palette tokens/hard-coded presenter pixels. Cohesion beats line limits.

Render-order ruling: header Live is unavailable while `renderOwner` is held. Render preparation joins pending header commands until none remain, then claims ownership synchronously; owner release republishes availability. This closes the lazy-load and successor-command races without changing public setLive or deviceDidRebind policy, a competing queue, or a second Live-state boolean.

## Acceptance
A loaded track has a compact Effects rack button and a separate accessible Live toggle. The Live control toggles off then on without opening the rack, modifying song/history, or reloading the plugin; pointer cancellation/stale targets cannot affect another track. Crash indication and recovery remain. New and empty tracks retain direct Effects access. All geometry scales with font and all theme text/control pairs remain AA.

## Execution and gates
No build/tests/lint/format/index/native/Git commands mid-flight. Use read-only LSP before exported changes; semantic references are currently failing with connectionInterrupted, declarations/diagnostics work. Capture before/after declaration scopes and report fallback evidence honestly. Do not spawn agents or commit. Freeze sources, report exact changed files/new bridge API, test consumers needing controller migration, proof status and final predicate locations.

Controller verification (hard 180s per command):
- uv run --no-sync dev build:checks
- uv run --no-sync dev checks:shell --filter shell-midieffects --filter shell-effect-output --filter shell-text-contrast-song --no-windowing-checks --pool=3
- native manifest slice containing track-header checks (resolve exact registration; do not run broad suites)
- PORYDAW_ROLL_QML_SUITE=tst_SwiftRollTrackHeaderMenu.qml uv run --no-sync dev checks:qml-roll --filter swiftroll-window --no-windowing-checks --pool=3
- uv run --no-sync dev checks:bridge
- uv run --no-sync dev checks:qml-aot
- uv run --no-sync dev format --check <changed Swift files>
- uv run --no-sync dev lsp:swift
- Actual production rendered fixture/native surface inspection; preserve the user's song and plugin parameters.

Same menu-refinement continuation; no commit/push/merge or ownership transfer of earlier uncommitted files is authorized. Incoming accepted edits remain untouched. BASE for historical context only: 290d15671db8d3e8f2e49d63ecc9579e1ea2d5a0; task review uses its own incoming-to-final source snapshot.
