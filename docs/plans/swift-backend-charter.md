# Swift backend charter — guiding rules for the production conversion

Status: normative. Every wave spec, task brief, and review under the Swift
backend track inherits this document. Where a spec and this charter
disagree, the charter wins and the spec is a defect. Successor wave specs
(document seam, surfaces) must name this file in their Global Constraints.

Current planning precedence: this charter and the
[QtBridge integration contract](qtbridge-integration-contract.md) govern the
[Swift core rewrite plan](swift-core-rewrite/plan.md). The earlier
[ownership design](swift-ownership-cutover/design.md) and its M1/M2 proposals
are historical; their reverse-adapter and two-consumer sequence is superseded.
Earlier wave documents remain behavioral references, not dispatch authority.

## Approved incremental rewrite scope (2026-09-19)

The user explicitly permits unmigrated editors to be absent from the rewrite
application: not rendered, instantiated, or compiled into it. Preserve their
song data and core editing semantics, not their availability in this build.
Do not implement a reverse legacy-client adapter to keep those editors alive.
The current plan converts `src/core/*` to native Swift, converts the existing
piano grid into its first direct document consumer, then stops. No additional
QML features or other consumer conversions belong to that plan.

This approval supersedes earlier requirements that every old editor remain
usable through the authority cutover. Source and behavioral checks for absent
surfaces may remain unbuilt references; report their coverage as deferred,
never passing. The replacement's own checks exercise real Swift code.

The optimization criterion is less code and fewer concepts for future work,
not a transliteration of C++ interfaces. Verify ordinary editing, saving,
loading and playback, plus real external-file errors. Do not expand this
rewrite into stress testing internal states normal application use cannot
produce. Preserve required behavior without inventing defensive frameworks.

## Prime directive

This is not a prototype. The Swift backend track converts production
surfaces. Production implementations and interfaces are designed to stay:

- No temporary workarounds. A workaround here means what it means in
  AGENTS.md: stop, name the root cause, recommend the root-cause fix, and
  request approval. Accommodating a broken invariant with a guard or
  fallback is not an option.
- Destination Swift modules and QML views are production implementations,
  not scaffolds written for another rewrite. Existing legacy application
  code and adapters retire under the taxonomy and gates below; that planned
  retirement is not permission to add new per-surface seams or workarounds.
  Any proposed new shared legacy-client adapter requires explicit design
  approval with its scope, callers and retirement gate.
- No parallel implementations kept "until later." Widget twins inside the
  song tab are cut over and deleted at their named retirement gate, not
  maintained beside their successors indefinitely.
- Production focus applies to checks too: a check that only passes in the
  sandbox proves nothing about production.

## Swift implementation policy

- Use the verified Swift toolchain recorded in the integration contract.
  Prefer current language features when they reduce code or improve concrete
  ownership/performance; a compiler upgrade is not a rewrite prerequisite.
- Prefer spans for scoped borrowed access where supported. Verify concrete
  APIs and deployment availability; do not invent compatibility fallbacks.
- Raw pointer access is acceptable when bounds, initialization and lifetime
  are proven. A view into a callback's buffers must not escape that callback.
- Retained document state needs owned storage. Copy accepted input into that
  storage once; avoid intermediate arrays, redundant mapping, boxing and
  avoidable copy-on-write detachment. Reject stale snapshots before copying.
- Review these properties in every Swift task. Use modern features for a
  concrete benefit, not feature-count churn or unrelated rewrites.
- Declarations before implementation: every Swift file opens with its
  public surface — types, enums, protocol conformances, and entry points —
  before private helpers and bodies. Swift has no headers; this ordering is
  what preserves C++'s one interface-read advantage. An agent must be able
  to learn a file's contract from its top without loading implementation.

## Compatibility and retirement decision (2026-09-18)

Required user behavior and explicitly permanent host interfaces create
compatibility obligations; migration-only machinery creates **none**.
Demo APIs, fixture loaders, sandbox checks, and parity adapters are not
public contracts merely because code or tests call them. Preserve the
behavior they help prove, not their implementation shape or entry points.
INV-1/INV-2 preserve one keymap and arbitration authority. INV-3 preserves
the host/band division of responsibility, not a permanent C++ class or ABI.

The table records verification and staged-mount retirement obligations.
The interop taxonomy below additionally governs existing legacy application
adapters. Each retirement requires replacement evidence and migrated callers;
no document-ownership milestone automatically retires host input delivery.
Destination Swift logic must be built to stay. Historical feed layouts and
presenter interfaces are not permanent contracts.

| Migration-only machinery | Read-only production mount obligation | Removal gate |
| --- | --- | --- |
| Standalone demo entry point and demo fixture setup | Exclude the standalone app entry point and selftest drivers from the production library. Production content comes from the real document feed, not demo fixture initialization. Keep the standalone lane and fixtures still required by this wave's acceptance. | Remove the standalone lane and demo-only fixture hooks when production acceptance exercises all required behavior they still verify, including editable behavior. Delete a fixture only when no retained acceptance check needs it; production regression fixtures are not disposable merely because the demo also used them. |
| Duplicate local undo (`GridUndo` in the demo) | Read-only production mode records no local edits or undo entries. Keep demo undo for still-required editable sandbox acceptance; it is not a second production undo authority. | At editable cutover, connect Swift edits to the authoritative document undo path and prove production mutation/undo/redo behavior before deleting duplicate local undo and its demo callers in the same cutover. This does not authorize a rewrite of production undo in the read-only wave. |
| Rollout flag, read-only overlay mounting, and old C++ rendering path | Preserve the existing gated path until complete replacement acceptance. The re-scoped writable milestone is not full default cutover; its leading-resize limitation remains explicit. | At default editable cutover, production rendering, editing, focus/key arbitration, cancellation, and undo acceptance must pass on Swift-backed surfaces. Remove the rollout flag, obsolete overlay-only machinery and replaced C++ rendering path together; preserve required mounting and host behavior through their replacements. Windows deferral cannot extend this gate. |
| Duplicate sandbox behavioral checks | Retain rows still required by prototype regression; a read-only mount cannot replace editable, keyboard, menu, or cancellation acceptance. | Delete each `cutover-disposable` row when its required behavior is covered and passing on the actual production replacement surface. Retire the duplicate harness when its last such row retires; never keep a parallel behavioral acceptance suite after cutover. |
| Callable parity adapters and dual-run oracle plumbing | Keep adapters needed by live parity sweeps; distinguish oracle/test adapters from production transport even when colocated or similarly named. | At the corresponding oracle retirement gate, pass the final comparison and replacement production acceptance, then remove oracle-only adapters with the retired implementation. Document transport and host input delivery have separate caller/replacement gates, not the oracle's gate. |

These gates permit existing verification, mounting and legacy integration
to survive only until their replacements are proven. They do not authorize
workarounds or new compatibility facades. C++ remains the production
document/history authority until the approved authority cutover; Swift
projections do not create another writable authority.

## The three migration invariants

These predate every wave. A plan that violates one is rejected at triage.

**INV-1 — One keymap source.** `keymap::Registry` is the current single
definition of window-tier bindings. Persistent surfaces must not introduce
handwritten competing shortcut maps. A future implementation-language change
migrates the definitions and their consumers together under INV-2; it does
not authorize a second keymap.


**INV-2 — Arbitration moves wholesale or not at all.** Window-tier key
arbitration lives in exactly one tier. Mixed tiers — some surfaces
dispatching through `QAction`s, others through QML dispatch — are forbidden.
When arbitration migrates, the `selectionkey` suites are re-pointed at the
new tier and green before the old tier is deleted: one atomic cutover, never
two live authorities.

**INV-3 — One host authority; bands are not window dispatchers.** Swift
band/presenter logic receives normalized input and named cancel reasons.
Window-tier arbitration, focus chains, pointer grabs, popup stacking and
platform events belong to one host authority. No band installs a competing
dispatcher. Host implementation may migrate wholesale under INV-2, including
Swift-owned application policy with Qt/QML event delivery; this does not
require raw window events in Swift domain code or a permanent QWidget shell.

## Platform decision (2026-09-18): Windows deferred, MinGW incidental

The rewrite proceeds macOS-first. Windows is **deferred, not dropped**:
existing users are frozen on the last C++ release until Windows returns.
MinGW was never a decision — it is an incidental toolchain fact and binds
nothing. Binding consequences:

- No MinGW accommodations, loader workarounds, or check tolerances are
  added or maintained anywhere in this track.
- No dual implementations to preserve Windows: the C++ roll band's
  retirement is unconditional. Windows returns **on the Swift codebase** —
  its own later wave covering toolchain selection (MSVC or otherwise),
  packaging, and CI — never by keeping C++ surfaces alive.
- Repo de-Windows-ification (Windows CI/release jobs, AGENTS.md toolchain
  section, windeployqt packaging, MinGW check handling) is one mechanical
  plan executed after the current wave; nothing blocks on it and no new
  work depends on it.

## Seam rules

**S-1 — Preserve the behavioral oracle.** During parity verification, do not
alter reference behavior or expectations to conceal a port mismatch.
"Read-only oracle" describes that review discipline, not a read-only runtime
document: the current C++ authority still executes production edits.
An approved cutover may migrate callers and remove reference implementations
after replacement acceptance; the old write sets do not freeze the codebase.

**S-2 — Confine native transport to adapters.** Existing legacy C feeds
exchange copied values, not borrowed `SongDocument*`, `MidiTimeline*` or Qt
objects into domain code. Preserve their callback buffer lifetimes and
document-identity/revision guards while retained. Native Swift-to-Swift
interfaces do not serialize through C. QtBridge object/proxy lifetime and
retained native-service interfaces follow their own explicit contracts;
legacy value-feed layout rules do not define the Swift domain model.

**S-3 — Undoability is existential.** Every undoable musical gesture commits
one transaction to the single authoritative history. That authority is C++
today and Swift after its approved cutover. Non-undoable musical mutation or
competing histories fail acceptance, including shared voice-bank ordering.
Session changes remain non-document edits where existing behavior requires.
The historical leading-resize deviation is not permission to weaken the
destination transaction contract.

**S-4 — The four cancel reasons are contract.** `FocusLost`,
`PointerUngrabbed`, `Hidden`, `WindowDeactivate` arrive as distinct named
reasons with per-band teardown semantics, mirroring
`TimelineInputCancelReason`. Collapsing, substituting, or inferring reasons
inside Swift is forbidden; the host names the reason. (Worked example: a
`hide()`-driven proof of `onVisibleChanged` proves `Hidden`; it can never
stand in for `WindowDeactivate`, whose defining predicate is that the window
remains visible.)

**S-5 — Compute, don't freeze.** Every expected value ported from a
production check carries a live dual-run sweep counterpart against the
production oracle (the `sgm_*` pattern), or a written justification of why
the value is not callable. Frozen literals name their source check in
brackets; a sweep mismatch names both sides loudly.
This dual-run obligation lasts until the corresponding oracle retirement
gate in the retirement table is satisfied.

## Verification rules

**V-1 — Observable behavior is the contract.** At cutover, retained production
behavior assertions exercise the actual Swift-backed replacement. Drivers,
imports and implementation-specific access may change when concrete C++
types retire. Do not keep a dead presenter solely to compile an old driver,
or delete meaningful coverage merely because its implementation changes.
Remove obsolete implementation-pinning assertions rather than re-pin them.
Bridge probes establish capability; they do not alone prove production parity.

**V-2 — Copied checks verify nothing but their copy.** Production checks are
never rewritten against sandbox surfaces as acceptance evidence. Parity for
callable values is proven by dual-run sweeps; behavior parity is proven by
the production suites at cutover.

**V-3 — Sandbox scenarios are cutover-disposable.** Smoke scenarios that
mirror production behavior (key priority, menu behavior, transport) are
tagged `cutover-disposable` and retire at the table's behavioral-coverage
gate. Merely mounting a read-only production surface does not satisfy it.
A permanent parallel suite is a defect.

## End-state architecture (amended 2026-09-19)

The destination is a Swift-native application with QML views: Swift owns
application and domain logic — document state, editing operations,
transactions and history, session state, and presenters — as native Swift
modules; QML owns views and delegates. Handwritten C++ Qt application code
is minimized to what QtBridge cannot cover and what retained native services
justify. Preserve user-visible behavior, not old C++ presenter interfaces;
QML interfaces may change to fit Swift presenters.

### Interop taxonomy

Native integration has three classes. Each milestone names obsolete code
and the specific replacement/caller gate that allows its deletion:

1. **Legacy application integration**, with separate retirement obligations:
   document/session/command transport (`sgd_`, `sgc_`, `sgs_`) retires when
   Swift authority and migrated callers replace it; input delivery (`sgk_`,
   `sgb_`, `SwiftRollBand`) retires when its event-delivery replacement passes;
   mount plumbing retires when production mounting replaces it; parity
   adapters retire with their corresponding oracle. Prefixes are not
   ownership categories. No new per-surface adapters may be created. An
  authority cutover must account for legacy callers: migrate them or exclude
  their surfaces under the approved scope above, without a replacement facade.
2. **Retained native-service adapters** — audio/DSP and necessary platform
   integration, kept behind a narrow service interface. C++ here is a
   decision, not a debt: do not rewrite native audio merely to eliminate
   the language.
3. **QML exposure** — Swift presenters and collections exposed to QML
   directly through QtBridge (`docs/plans/qtbridge-integration-contract.md`
   is the integration contract and acceptance gate; its scenarios are
   Unverified until runtime evidence is recorded there). No new handwritten
   per-surface C++ presenter mirrors or per-surface push/pull feeds.

Swift domain types are not designed around C ABI layouts. Imported C
structs, pointer/count buffers, raw opcode conversion, and callback handles
stay inside the narrowly scoped adapters above. Swift-to-Swift calls never
serialize through C. Fixed-width numeric types are fine where musical
arithmetic or identity requires them; ABI requirements do not dictate the
domain model. Consolidating the existing C feeds is not "Swift owns the
model" — the authority cutover is.

### Ownership invariants (unchanged in force, restated for the pivot)

INV-1/INV-2 preserve one keymap and arbitration authority across host
technology changes. INV-3 separates band logic from host arbitration.
S-3 preserves one writable document and authoritative history, including
shared voice-bank behavior. The approved plan distinguishes converted callers
from explicitly excluded surfaces; neither creates a second writable model.

### Ordering (amended)

The baseline/probe and production-Swift rehome inform the current plan.
Next convert the full core and its necessary native-service boundary, then
the existing piano grid as one direct Swift consumer. Stop at that acceptance
gate. Headers and all other surfaces require a separate later plan.
Input/mount replacement must preserve actual delivery on the retained grid;
removing document transport alone does not prove that delivery.
