# Task m1a — DocumentSession: two consumers, one native session object

Status: superseded; do not dispatch. The
[Swift core rewrite plan](../swift-core-rewrite/plan.md) replaces this
feed-owning two-consumer session proposal with native Swift core ownership
and one direct piano-grid consumer.

Where this fits: first M1 stage after m0-probe and swift-org land. Governing:
plan.md Global Constraints; integration contract (capability rows now
Verified; production-scenario rows stay Unverified until this task's
harness proves them).

## Design decisions (stated, not delegated)

- `DocumentSession` is a Swift class in the production Swift home
  (`swiftroll/`): the per-open-song composition/lifecycle owner of feed
  payloads. It owns the `sgd_`/`sgs_` receiver state (notes, signatures,
  selection snapshots), applies document-identity/revision guards on push,
  and exposes a native Swift session interface (no C layouts in its API).
- Ownership graph: `PianoGrid` constructs and owns the session
  (`@QtTracked let session: DocumentSession`); the grid's existing
  feed-receiver plumbing moves INTO the session. The headers presenter
  surface receives the session via QML property assignment — the patched
  object-return path (`makeRow`-style, Verified in the ledger) — so no C++
  construction point and no new C symbols exist. `SwiftRollMount` is
  untouched: it still binds feeds/executor exactly as today; the feeds now
  deliver into the session (the session registers the receiver callbacks the
  grid registered before).
- Editing path unchanged: gestures still submit through `SgcCommandPipe` →
  `sgc_` → executor. C++ remains the sole edit/history authority. The
  session is a projection owner, not a writable model (charter S-3).
- Headers consumption is probe-grade: the preserved `TrackHeadersPresenter`
  core binds to the session's track/selection view on a harness QML surface.
  NO production header replacement, no `TrackHeaderModel` changes, no
  `trackheader` suite changes.

## Change

1. `swiftroll/DocumentSession.swift` (new): declared surface first; owns
   document id/revision/track selection state received via the existing
   feeds; native-Swift read API for presenters (track list, note ranges by
   track, selection, signature map). Internally holds the existing
   `SgdDocument`/`SgsSession` payload types — they become session-internal
   storage, not presenter-facing types.
2. `PianoGrid.swift`: session property + object-return exposure
   (`var session: DocumentSession` readable from QML); feed receiver
   delegation moves to the session; all existing behavior identical
   (property names, revisions, gesture outcomes unchanged).
3. Harness `swiftqtml`-style new rows (extend `swiftqtml` or a sibling
   `swiftsession` check — implementer picks ONE, registers it, records the
   command in the contract ledger): mount the real `SwiftRollMount` path
   (swiftrollgated rig), then prove the two-consumer contract rows:
   - grid presenter and headers presenter both observe the same commit
     after a document edit (one `documentChanged` → one session push → both
     presenters updated, coherent revision);
   - track reorder preserves the editing target for BOTH consumers (stable
     domain identity, per the Verified insert/remove/reorder capability);
   - session detach (tab close rig) stops feed delivery to both presenters;
     no post-detachment callback (contract lifetime row).
   These rows promote the contract's production-scenario rows 1–3 partially:
   record exactly what was exercised; rows 4–7 (transient editors, tab close
   with pending UI, sibling tabs, reopen/app close) stay Unverified unless
   the rig covers them cheaply — do not fake coverage.

## Preservation contract

- Zero behavior change to the production grid: `swiftrollgated`,
  `swiftbandkeys`, `swiftcommands`, `swiftdocfeed`, `rollcheck`,
  `selectionkey` (4 suites flag-off + core flag-on) all green unmodified.
- No new `sg*` symbols; no changes to `src/ui/songview/quick/swiftgrid/`.
- `TrackHeaderModel` and the production header surface untouched; `trackheader`
  filter green unmodified.
- Feed payloads keep their C layouts (adapter-internal); the session's Swift
  API uses native types.

## Acceptance

- Two-consumer rows green with recorded commands in the contract ledger
  (exact `deno task verify --filter …` lines + observed output).
- Full regression gate green (controller-run, settled batch).
- Review: sdd-task-reviewer + thermo (plan.md quality gate).
