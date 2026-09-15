# T12 — Prove shared-scene and popup lifetime behavior

## Context

Gate A's behavioral proof: the host check files must exercise the real
shared-scene contracts from [spec.md](spec.md) S8 — two scenes in one
engine/window, detached updates, viewport offsets, real custom popup lifetime
and release swallowing — rather than repinning per-song-window assertions.
Consumes the frozen interfaces of tasks 1–10 and the migrated fixtures from task
11; final workspace-level tab behavior belongs to tasks 19/20, not here.

## Exact write set

- `src/checks/host/tst_hostseams.cpp`
- `src/checks/host/tst_hostadapter.cpp`
- `src/checks/host/tst_hostintegration.cpp`

## Prerequisites

Tasks 1–11 — consume their interfaces only: S3 attach/detach/eligibility (1),
viewport geometry (2), provider scoping (3), popup session/canvas scope (4),
`QuickWindowInput` (5), sink conversions (6), playhead mapping (7), scoped key
routing (8), retargeted adapter (9), `checks::QuickSceneHost` (10), migrated
fixtures/registration (11).

## Interface contract

Produces no production interface. Test changes per spec S8:

- Remove assertions that assume per-song window destruction, window transfer or
  QWidget identity; preserve the real ownership invariants (scene borrows retire
  before domain resources; destroying a page never destroys the shared
  window/engine).
- Add actual cases: two song scenes in one engine/one window with provider
  isolation; detached mutations followed by reattachment rendering current data;
  viewport offset/smaller-than-window geometry; a real `QuickPopupSession`
  custom popup (form/menu/pitchbend path, not `Controls.Popup` and not a direct
  controller-call substitute) across a page switch and owner close;
  dismissal-press → owner-close → swallowed release → next full click edits the
  survivor; no-focus produces no editor dispatch.
- Use real input and native scopes; no manual refocus after a tested transition.
  Tests may directly assemble two scoped pages via `QuickSceneHost` for scene
  checks. Inline QObject test classes already exist — no new catalog harness.

## Implementation steps

1. Migrate existing host assumptions to the S3/S8 API and delete obsolete
   window-transfer/destroy assertions.
2. Add the two-scene shared-engine lifetime and provider cases plus
   detached-update/reattach and viewport-offset cases.
3. Add the real custom popup switch/owner-close, release-swallow and no-focus
   cases through real input.

## Acceptance predicate

Milestone-A scenarios exercise actual source, including custom popups — not just
`Controls.Popup`; named checks `host-seams`, `host-adapter` and
`host-integration` pass under the gate-A run below. Local structural inspection
is not a behavioral pass.

## Task-specific constraints

- No semantic rewrites of domain assertions belonging to other harnesses; no
  field-copy, wiring or source-text assertions substituted for behavior (plan.md
  Global Constraints).
- Do not assert final workspace tab behavior; that is tasks 19/20.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
