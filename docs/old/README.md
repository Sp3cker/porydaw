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
| Timeline and rendering | `qt-quick-timeline-column-plan.md`, `qt-quick-timeline-input-plan.md`, `qt-quick-piano-roll-optimization-plan.md`, `qt-quick-track-headers-plan.md`, `time-camera-plan.md`, `pianoroll-gesture-refactor-plan.md` | Quick-host ownership, input cutover, piano-roll behavior, camera rules, and gesture history. Some earlier renderer details are historical. |
| Drawer and lanes | `automationcanvas-refactor-plan.md`, `automation-trailing-hold-cap-plan.md`, `drawer-hover-guide-line-plan.md`, `tempo-slot-plan.md`, `tempo-slot-minutes.md`, `tempo-cc-duality-consensus.md`, `time-ruler-loading-plan.md`, `voice-change-drawer-page-plan.md`, `xcmd-cc-refactor-plan.md` | Lane ownership, editing rules, timeline geometry, and retained design choices. |
| Project and session | `project-io-thread-plan.md`, `projectio-dress-down-contract.md`, `projectio-dress-down-plan.md`, `view-sidecar-removal-plan.md`, `selftest-null-audio-plan.md` | Project I/O contracts, startup and sidecar decisions, and real-versus-null audio test behavior. The Project I/O contract and plan remain paired because one fixes interfaces and the other orders the work. |
| Application-wide UI | `remove-fonts-plan.md`, `agent-reorg-plan.md` | The fixed-font decision and historical agent/workflow direction. |
| Sample editor | `sample-editor/CONTEXT.md`, `sample-editor/DSP.md`, `sample-editor/FORMATS.md`, `sample-editor/PLAN.md` | The connected product, DSP, format, and delivery record. Read as a set. |

## Archive rule

Keep one strong record per finished feature. Keep a paired contract and plan
only when each has a distinct job. Remove handoffs, dispatch notes, and drafts
once a retained record absorbs their useful conclusions. Move unstarted ideas
to `docs/ideas/`, not here.
