# Task 3 — `sgk_` key seam + `SwiftRollBand` adapter

## Context

The Swift roll graduates from overlay to band: a C++ adapter implements
`TimelineBandInteraction` and forwards input through typed seams; keys
arrive as registry-matched command ids. Qt-contract heavy — ownership,
grabbing, fallback order. Contracts FIXED in [spec.md §4–5](spec.md).

## Exact write set

- `src/ui/songview/quick/swiftgrid/key_feed.{h,cpp}` (new) — C ABI:
  `SgcKeyDeliveryFn` (command id, modifiers, autoRepeat, surface facts)
  returning handled/not-handled; `SwiftGridKeyRouter` bridging the host
  path to it.
- `src/ui/songview/quick/swiftgrid/swift_roll_band.{h,cpp}` (new) —
  `SwiftRollBand : TimelineBandInteraction`: pointer press/move/release/
  double-click/wheel/leave forwarded as plain values; gesture-active
  reported from the Swift surface; `inputCancelled(reason)` delivered as
  the four named reasons via the existing `sgw_` filter.
- `src/ui/songview/quick/timelinequickview.{h,cpp}` — band registration
  under `PORYDAW_SWIFT_ROLL` (the Wave 3 mount block gains the adapter;
  overlay absorption replaced).
- `src/ui/songview/quick/swift-grid-prototype/SgcKeys.swift` (new) —
  Swift sink: eligibility via `sgp_` mirror + `sgs_` state; bool answer.
- Harness `src/checks/swiftbandkeys/` (new) + registrations.

## Prerequisites

Tasks 1–2 (state + intents exist for eligibility answers).

## Interface contract

- Host matching is untouched: window-tier QActions first, then the
  `handleEditKey` successor delivers surviving editor-routed commands
  into the band path exactly as for C++ bands. The adapter is a peer
  band, not a new tier (INV-2).
- Unhandled keys return to the existing band fallback order
  (`timelinequickview_keyrouting`); Swift must answer synchronously.
- Pointer events cross as plain values (position in band-local ticks/keys
  computed C++-side via the Wave-1 math functions where the C++ bands do).
- Gesture-active gating: commands consumed as no-ops while a Swift
  gesture is live, per `survivesPointerGesture` — Swift answers from
  `sgp_`, the host honors it.

## Implementation steps

1. ABI per spec §4; Swift sink with eligibility.
2. Adapter implementing the full band contract; registration in the
   Wave 3 mount block; teardown idempotent with `detachWindow()`.
3. Harness `swiftbandkeys`: boot flag-on workspace; deliver keys via the
   real window; assert command-id arrival (not QKeyEvents), eligibility
   gating with/without selection (`sgs_`), gesture-active blocking,
   autoRepeat consumption, fallback when unhandled, cancel-reason
   delivery mid-gesture.

## Acceptance predicate

- `deno task verify --filter swiftbandkeys --verbose` green.
- `deno task verify --filter selectionkey-core --verbose` green
  (flag-off and flag-on both — flag-on must not change window-tier rows).
- `deno task build:app` green.

## Task-specific constraints

- Do not modify `timelineinput.h`, the QML chrome key handling, or any
  C++ band. The adapter is additive; fallback order untouched.
- If the band contract cannot be honored additively, escalate — this is
  the INV-2 wholesale-move boundary; partial tiers are forbidden.
