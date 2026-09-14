# Context

The real adapter owns identity, no-hint claims, input lifetime and scoped idle reacquisition. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/songview/quick/timelineinputitem.h`
- `src/ui/songview/quick/timelineinputitem.cpp`

# Prerequisites

Task 1; dispatch atomically with Direct Task 15. Neither half builds or is accepted alone.

# Interface contract

Implement setMouseHint/refreshMouseHint overrides; public setHintMuted(bool) and resyncMouseHint(); passive HoverEnter; a guarded service borrow and actual hovered state. Follow spec.md exactly: resync reacquires through setMouseHint, whereas refreshMouseHint cannot take ownership. Do not change TimelineBandInteraction or input structs.

# Implementation steps

1. Add both real host overrides and the view-facing mute/resync methods. Suppress even empty publication while muted; clearing is always source-checked. Never recreate the singleton during teardown.
2. Add first idle HoverEnter forwarding with the existing gestureActive guard and preserve current HoverMove/event acceptance. Pure no-hint interactions must claim empty, without empty-then-text churn on every move.
3. Centralize leave, hide, detach/rebind and guarded destruction. During an own grab retain the source; normal and cancelled/stolen ungrab use actual cursor containment. FocusLost alone does not clear.
4. Implement resync as current-position idle recomputation only for visible/windowed, unmuted, still-hovered, in-scope sources with no exclusive grab and no active domain gesture. Do not restore cached text or force lower-item membership.
5. Leave domain cancellation and key/wheel/mouse acceptance unchanged; inspect all early-return/teardown paths and compile all three concrete hosts with Task 15.

# Acceptance predicate

The atomic 4+15 cutover builds all real and test hosts; actual idle entry, plot/gutter identity and release-inside/outside preserve existing input behavior. Controller: deno task verify --filter automation-presentation --filter automation-raster --filter host-seams --filter selectionkey --verbose; first composed view/scope proof follows in 5+17, retained regression in 14.

# Task-specific constraints

No per-band clearing, raw retained gutter host, no-op production override or synthetic Qt input. Shared build/test and formatter/linter runs wait for both cutover writers; required read-only local inspection remains implementer-owned.
