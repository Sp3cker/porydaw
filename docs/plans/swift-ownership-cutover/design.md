# Swift ownership design and cutover gates

Status: proposed, not dispatched. Corrected after source inspection at
`bc24c98d` on 2026-09-19. This is an ownership design, not executable task
briefs. Documentation corrections authorize no source changes, new adapters,
feature removals, or milestone dispatch.

Governing documents: [current charter](../swift-backend-charter.md) and
[QtBridge integration contract](../qtbridge-integration-contract.md).
All integration scenarios remain Unverified until evidence is recorded.
The old Wave 4 dispatch plan is historical; `fe1ff4df` closed only the
re-scoped grid milestone. Its leading-edge resize limitation remains open.

## 1. Current ownership versus destination

Currently C++ `SongDocument` and `SongHistory` own production document edits
and history; `SongView` owns session/selection state. Swift presenters receive
snapshots and submit commands through legacy adapters. `SwiftRollMount`
constructs the document/session feeds and executor. There is no production
Swift-owned document merely because a Swift session receives these values.

Target ownership:

- Swift document module: full-fidelity musical state and editing semantics.
- Swift history: one transaction/history authority, including ordering and
  confirmation/conflict behavior for shared voice-bank edits.
- Swift session: selection, active track and view state. `DocumentSession`
  is the per-open-song composition/lifecycle owner, not a monolithic type
  implementing document algorithms, history, presenters and workspace policy.
- Swift presenters: grid, headers and later surfaces; exposed through
  QtBridge. Domain operations use native Swift types, not C transport layouts.
- QML: views, delegates and visual input items. Preserve user-visible
  interaction behavior, not the old presenter property names or class types.
- Native services: retained audio/DSP and necessary platform integration.
- Legacy application integration: existing document, input and mounting
  adapters remain only until their individual replacement gates pass.

The document scope includes notes and overlap rules; tracks/channel/chunk
mapping; signatures and tempo; controllers, pitch bend, voice changes and
XCMD; raw MIDI/meta/SysEx events; markers/loops; time/range operations;
configuration/export; revisions, save-state identity and playback projection.
It is not the note/signature subset of `sgd_`.

## 2. M0 — Evidence baseline and ownership decisions

Before broad relocation or presenter work, record the contract's actual
Qt/Swift/QtBridge/application revisions, build configuration, local patch
purposes/upstream status, and concrete lifetime table. Assign creators,
retaining references, GUI-thread/Swift isolation, detachment and release
conditions. A table skeleton alone does not satisfy ownership verification.

Use the smallest real-QML probe for presenter updates, in-place row changes,
replacement and release. Observe QML delegates and lifetime outcomes, not
only Swift fields. This establishes bridge capability, not production header
parity, document ownership, or authorization to remove the old presenter.
Do not count a fixture-backed bridge probe as production cutover acceptance.

M0 also resolves the dependency and legacy-editor choices below before M1/M2
briefs are frozen. No implementer is delegated an unstated architectural choice.

## 3. M1 — Two-consumer integration and header retirement gate

Grid and headers should consume native Swift-facing session interfaces with
one lifecycle owner for legacy subscriptions. Neither presenter independently
constructs its own feed/executor registrations. During any pre-M2 integration,
C++ remains the sole edit/history authority; shared Swift projections are not
an additional writable domain model. Command submission to that authority
must have an explicit owner, even when the presenters call Swift methods.

The existing `sgd_`/`sgs_` pair is insufficient for full production headers.
`document_feed.h` carries notes, signatures and counts, not track names or
voice metadata. The preserved `TrackHeaders.swift` used `sgth_push_track`
for additional row data. It is still listed in the production CMake target;
'unreferenced presenter' does not mean uncompiled or transport-free code.

Before a production header brief is dispatchable, complete this inventory:

| Dependency | Current source to inspect | Required decision |
| --- | --- | --- |
| Track names, voice/program labels, add-track eligibility | `trackheadermodel.cpp`, `TrackHeaders.swift` row pushes | Authoritative source and complete delivery path; do not invent another per-header feed. |
| Selection, mute/solo, track edit commands | session feed, intent executor, `SongView` track operations | Single subscription/command owner; stable target identity after reorder/undo. |
| Appearance, geometry, typography | current header model and theme/typography integration | Shared Swift/QML interface with production behavior preserved. |
| Activity meters | header model and `src/ui/activity/` | Retained audio-service observation, not placeholder values. |
| Rename, voice actions, menus and popup lifetime | `trackheadermenu.cpp`, Quick menu/popup owners | Complete actions, stale-target handling and local-input behavior. |
| Pointer/key/cancel delivery | `TrackHeaderBand.qml`, `TimelineInputItem`, band interface | Replacement event delivery respecting the one host authority. |

If frozen legacy interfaces cannot supply a dependency, stop at this design
gate. Re-sequence the production header cutover with the relevant Swift
ownership work, or obtain explicit approval for a bounded shared integration
change. This document does not authorize new feeds, mirrors, hidden
placeholders, or a second production implementation.

The QtBridge contract ledger proves integration semantics. Full production
header retirement additionally requires the dependency inventory, existing
header/selection behavior, and all production/test callers to be migrated.
Only then delete `trackheadermodel.{h,cpp}`, its replaced wiring and the
Swift header's surface-specific C callback layer. M1 proof alone does not
promise or authorize that deletion. Record any revised milestone assignment
before dispatch; do not quietly narrow header functionality.

## 4. M2 — Authority cutover: unresolved legacy-client gate

Move the full document, transactions and authoritative history to Swift once.
Preserve one transaction per gesture (including leading-edge resize), keyboard
edit merging, shared voice-bank ordering/confirmation/conflicts and selection
reconciliation. No synchronized writable C++/Swift document twins or competing
undo authorities may exist.

Remaining C++ editors are not read-only views. For example:

- Ruler: `timeruler_interaction.cpp` calls `moveTimeSig` and `setLoopTick`.
- Controller lanes: `cclanes.cpp` calls `writeLanePoints`.
- Automation gestures: `automationcanvas_gesture.cpp` calls `applyRangeEdit`.
- Event table/list, range editing and song settings also submit document edits.

Before M2 dispatch, inventory every mutating caller and settle one explicit
migration strategy: migrate those callers with the authority, or approve a
bounded shared legacy-client adapter that submits operations to Swift. Such
an adapter is a proposal requiring approval, not permission granted here.
Do not recreate each surface's C ABI or silently retain a full C++ domain
implementation under a new facade name. Request submission is distinct from
mutation authority: a legacy editor may request an edit without owning state.
Making these editors read-only would remove features and is not approved.

The selected strategy must specify query/invalidation delivery, transaction
submission/results, lifetime, retirement and every remaining caller. Without
that decision, M2 is not an executable plan.

Save/playback acceptance must cover:

- Canonical export of full song data/configuration and compatible reopen/build.
- Async save completion after newer edits or document replacement: an old save
  must not mark new state clean (`captureSaveSnapshot`/`didSave` behavior).
- Shared voice-bank and song history transitions, including pending/conflicting
  worker results, not only sequential note undo.
- Immutable timeline publication to native audio, with construction/conversion
  outside the audio callback; playback of edited state and safe teardown.
- Multi-surface observation, track remap, tab switching/closure and stale actions.

Input/window authority need not change language in M2. Its delivery machinery
cannot be deleted until a replacement actually delivers commands, pointer
input, cancellation and mounting behavior under that same single authority.

## 5. Retirement by responsibility, not prefix

| Responsibility | Retirement prerequisite |
| --- | --- |
| C++ document/history authority | Complete Swift state/operations/history/save contract plus migrated legacy edit/query callers; no writable twin. |
| `sgd_`/`sgc_`/`sgs_`, executor and Swift transport mirrors | Replacement state and command interfaces are exercised by every caller; remove obsolete registrations and conversion together. |
| `sgk_`/`sgb_`, `SwiftRollBand`, input-related enum mirrors | Replacement host-to-Swift input delivery passes command priority, pointer, wheel, cancellation and gesture-state behavior. Not automatically tied to document ownership. |
| Overlay-only mount/rollout path | Production Swift mounting and complete roll behavior pass; remove obsolete overlay machinery and old roll path together. Preserve required mounting until replaced. |
| C++ header presenter and `sgth_` layer | Complete production header gate in section 3. |
| Parity/oracle adapters | Final applicable comparison and replacement acceptance pass; retain useful independent behavioral tests, not duplicate implementations. |
| Other surface implementations | Their complete production replacement and caller migration pass. |

## 6. Organization before parallel presenter work

Naming note (post-rehome): `swiftroll/` is the production Swift home
(presenters, domain math, QML, native helpers, QtBridge patch);
`swiftgrid/` (adjacent) is the C++ seam/adapter directory
(`sg*` feeds, executor, band, mount). The names are close by design lineage,
not by function — check which side of the boundary you are editing.

After the baseline, define one closed, behavior-preserving organization task:
choose the production Swift home, isolate legacy/native/Qt integration, and
separate production code from remaining demo/reference paths. Directory and
file boundaries follow cohesive ownership, not arbitrary line-count limits.
Do not create empty module scaffolds or rename opportunistically during M1.

At the inspected checkpoint, `GridFixture.swift`, `GridUndo.swift` and
`TrackHeaders.swift` remain in CMake, and `PianoGrid` retains local undo,
`resetDemo` and no-command-pipe branches despite standalone-lane retirement.
Inspect callers and acceptance coverage, then retire obsolete paths or record
why retained ones are still needed. The organization brief must name exact
symbols to remove/preserve and update build/resource/module-map/doc paths.

Use native Swift names on application interfaces; keep necessary `sg*_` C
exports internal to adapters until retirement. Do not cosmetically rename a
legacy command pipe into the final document module. Do not move or split code
solely to meet a file-size target.

## 7. Verification handoff and dispatch status

Existing source-registered covering commands:

- `deno task verify --filter trackheader --verbose` selects
  `trackheaderquickcheck` (surface/menu/input behavior) and `trackheader-model`
  (reorder/undo/reconciliation). The old `trackheaders` filter matches nothing.
- `deno task verify --filter swiftrollgated --verbose` covers the gated
  production Swift roll, including current lifecycle and editing scenarios.
- `deno task verify --filter selectionkey --verbose` covers four keyboard
  routing/local-input/window/gesture suites. State the enabled surface flags
  and actual replacement path exercised in each implementation brief.

Production behavior assertions stay intact; drivers/imports may be migrated
when their implementation types retire (charter V-1). Do not preserve a dead
C++ presenter simply to compile an old driver, or delete meaningful coverage.

`swiftqtml` and `swiftdoccore` are prospective harness names, not registered
commands or passing evidence. Before dispatch, a brief must specify its
closed write set, exact registered/new checks and runtime prerequisites,
including desktop access where needed. Reuse the contract ledger rather than
creating one mechanically duplicated test per bullet. Record executed
commands, source/toolchain revisions and observed outcomes there.

M2's final acceptance includes `deno task verify` with the retired authority
excluded from the build, plus explicitly covering full-data save/reopen,
playback, stale-save completion, shared-bank history and lifetime scenarios.
A green generic corpus does not substitute for named coverage gaps.

### Mandatory thermo-nuclear quality gates

This is the single plan-wide quality-review policy. Task briefs reference
this section, not copies of it. When an executable `plan.md` is introduced,
move this policy into its Global Constraints and replace this section with
a link; do not maintain two versions.

The orchestrator dispatches `thermo-nuclear-reviewer` using the
`thermo-nuclear-code-quality-review` skill. The reviewer is independent of
the implementation author and read-only; author self-review does not satisfy
the gate.

Required reviews cover:

1. M0's bridge integration/proof implementation.
2. The production Swift organization and obsolete-code retirement stage.
3. Each independently verifiable ownership or production-surface cutover.
4. Cumulative milestone integration, from the recorded milestone-start
   revision through the complete settled change set.

Within a larger stage, review a settled increment before dependent work
consumes materially changed ownership/lifetime, shared interfaces, native
adapters, transport representations, transaction/history semantics, or a new
mode, fallback, dispatcher or abstraction layer. Do not review every
mechanical edit or repeatedly audit an unchanged diff. A stage review may
also satisfy milestone review when the scope is identical.

Each dispatch supplies the exact base revision and reviewed snapshot/change
set (including relevant uncommitted work), governing documents/task brief,
ownership and deletion contracts, verification results and known gaps.
Writers must not mutate the reviewed scope while review is running;
independent reviews may run concurrently over stable, disjoint scopes.

Review structural simplicity as well as correctness: C ABI leakage into
Swift domain code, per-surface adapters, duplicate state, unclear lifetime
ownership, dead migration paths, unnecessary wrappers and conditional-mode
growth. Judge cohesion and meaningful ownership seams, never arbitrary file
sizes or opportunities to split code merely to reduce line counts.

Dependent tasks must not build on a shared interface before its gate passes.
No stage or milestone is accepted with unresolved material findings. For
each finding, fix it and rerun affected verification, or reject it with
concrete source/contract evidence recorded in the review disposition.
Material fixes require reviewer recheck. After two unsuccessful repair
cycles, stop dependent dispatch and escalate the design issue rather than
layering on more patches or declaring the gate passed.

Reviewers do not run shared builds, formatters or test suites; the
orchestrator runs covering validation after writers settle. Read-only source
inspection remains part of review. Record scope, verdict and finding
dispositions with existing stage evidence, not another tracking system.
Thermo review supplements behavioral verification, task/spec review and
Qt-specific correctness review where applicable; it replaces none of them.

### Dispatch status

Next eligible design work: M0 evidence and the unresolved dependency/client
inventory. Organization, production M1 and M2 require approved bounded briefs;
M2 additionally requires the legacy-client decision. Subsequent surfaces use
Swift-native interfaces once their required ownership is available. No gate
is satisfied by this document's status or by the old Wave 4 checks.
