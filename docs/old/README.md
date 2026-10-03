# Archived design records

`docs/old` preserves the small set of completed, superseded, or still-useful
design records that explain why the current code looks as it does. It is not
an active work queue. Current code and checks win when they disagree with an
archive record.

Use active `docs/` and `docs/ideas/` for new work. Read an archive record only
when you need its rationale, behavior contract, or a migration constraint.

## Index

| Area | Records | Use them for |
| --- | --- | --- |
| Timeline and rendering | `qt-quick-timeline-column-plan.md`, `qt-quick-timeline-input-plan.md`, `qt-quick-piano-roll-optimization-plan.md`, `qt-quick-track-headers-plan.md`, `time-camera-plan.md`, `pianoroll-gesture-refactor-plan.md`, `native-timeline-renderer/` (plan, `phase-*-briefs.md`, `task-4v1-brief.md`), `native-display-list/` (plan, inventory, `task-*-brief.md`), `qtabwidget-quick-alternative-plan-failed.md`, `songtab-quick-composition-plan-failed.md`, `quick-eventlist-local-plan.md` | Quick-host ownership, input cutover, piano-roll behavior, camera rules, and gesture history. `native-display-list/plan.md` is the executed Swift display-list boundary; `native-timeline-renderer/` is the renderer it superseded. Failed composition alternatives and the local Event List cutover remain historical references. |
| Drawer and lanes | `automationcanvas-refactor-plan.md`, `automation-trailing-hold-cap-plan.md`, `drawer-hover-guide-line-plan.md`, `qt-quick-editor-drawer-plan.md`, `tempo-slot-plan.md`, `tempo-slot-minutes.md`, `tempo-cc-duality-consensus.md`, `time-ruler-loading-plan.md`, `voice-change-drawer-page-plan.md`, `xcmd-cc-refactor-plan.md` | Lane ownership, editing rules, timeline geometry, and retained design choices. |
| Project and session | `project-io-thread-plan.md`, `projectio-dress-down-contract.md`, `projectio-dress-down-plan.md`, `view-sidecar-removal-plan.md`, `selftest-null-audio-plan.md`, `first-frame-audio-startup.md` | Project I/O contracts, startup and sidecar decisions, and real-versus-null audio test behavior. The Project I/O contract and plan remain paired because one fixes interfaces and the other orders the work. |
| QtBridge surface | `qtbridge-surface/spec.md` (normative; `deno task checks:bridge` cites it), `qtbridge-surface/plan.md`, `qtbridge-surface/amendments.md`, `qtbridge-surface/audit.md`, `qtbridge-surface/briefs/`, `qtbridge-surface/evidence/` | The Swift↔QML declaration contract behind `.omp/rules/qtbridge-surface.md`. The plan, briefs and evidence are the executed cleanup record. |
| Application-wide UI | `remove-fonts-plan.md`, `agent-reorg-plan.md` | The fixed-font decision and historical agent/workflow direction. |
| New Song | `new-song-blank-wizard/spec.md`, `new-song-blank-wizard/plan.md`, `new-song-blank-wizard/task-*-brief.md` | The blank-mode wizard behavior contract and creation transaction (PJ03, dialogs A017–A021). |
| Sample editor | `sample-editor/CONTEXT.md`, `sample-editor/DSP.md`, `sample-editor/FORMATS.md`, `sample-editor/PLAN.md`, `sample-editor/tools/make_fixtures.py` | The connected product, DSP, format, delivery, and fixture-generation record. Read as a set. |
| Swift migration and parity | `swift-migration-core.md`, `swift-migration-editors.md`, `swift-migration-project.md`, `swift-migration-shell.md`, `swift-feature-parity/task-*-brief.md`, `swift-feature-parity/sprint-3.md`, `swift-feature-parity/sprint-4.md`, `swift-feature-parity/split-600-wave.md`, `swift-feature-parity/proof-process-review-2026-09-28.md`, `swift-feature-parity/repairs/` | Accepted implementation briefs, completed or exhausted sprint execution, the merged 600-line split, dated evidence review, and superseded repair/delivery drafts. The unfinished roadmap, inventory, spec, verification policy and unresolved R26/R27 briefs remain under `docs/plans/swift-feature-parity/`. |
| Checks and tooling | `checks-health-plan.md`, `editor-rig-consolidation.md`, `windows-build-generator.md` | Historical check-health work, the retired C++ editor-rig proposal, and the Windows generator discrepancy resolved by the current Ninja default. Current build instructions are in `docs/windows-build.md`. |

## Archive rule

Keep one strong record per finished feature. Keep a paired contract and plan
only when each has a distinct job. Remove handoffs, dispatch notes, and drafts
once a retained record absorbs their useful conclusions. Move unstarted ideas
to `docs/ideas/`, not here.
