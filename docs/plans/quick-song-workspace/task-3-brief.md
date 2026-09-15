# T03 — Make drawer image resources attachment scoped

## Context

`DrawerChrome::releaseIconProvider()` is a one-shot handoff tied to the per-song
window. Under a shared engine, each scene attachment needs its own image
provider and URL prefix per [spec.md](spec.md) S6, so two pages sharing one
engine never contaminate each other's icons. Produces the
`createIconProvider`/`clearIconProvider`/`iconUrlPrefix` contract that task 1's
attach/detach calls to register and remove the provider.

## Exact write set

- `src/ui/editordrawer/drawerchrome.h`
- `src/ui/editordrawer/drawerchrome.cpp`
- `src/ui/songview/quick/DrawerChromeLayer.qml`

## Prerequisites

None — frozen spec only. Task 1 is the consumer of this interface; within gate A
both write against the frozen S6 contract without waiting on each other's
acceptance.

## Interface contract

Per spec S6, `DrawerChrome` replaces `releaseIconProvider()` with:

- `QQuickImageProvider *createIconProvider()` — creates and initializes the
  provider from current appearance on each attachment, using the existing icon
  generation/revision behavior; the engine owns the returned provider.
- `void clearIconProvider()` — clears the retained borrow before the coordinator
  removes the provider; detached updates must not dereference it.
- `QString iconUrlPrefix` property with setter and change notification — the
  coordinator sets the full `image://drawerchrome_<n>/` prefix before canvas
  creation.

Provider naming is a fresh monotonic GUI-thread-generated `drawerchrome_<n>` per
attachment — never pointer-address identity, never reused within an engine/cache
lifetime. `DrawerChromeLayer.qml`'s two `Image` sources (toggle icons and the
detent image) consume `iconUrlPrefix` plus the existing icon name/revision
instead of the hardcoded `image://drawerchrome/` prefix.

## Implementation steps

1. Replace `releaseIconProvider`/`m_iconProviderReleased` with the
   create/clear/prefix members above; keep `m_icons` as a cleared-before-removal
   borrow only.
2. Guard every icon update path so detached updates never dereference the
   provider; preserve existing icon generation and revision behavior verbatim.
3. Update both `Image.source` bindings in `DrawerChromeLayer.qml` to the prefix
   property.

## Acceptance predicate

Two pages share one engine without icon contamination, and closing/re-attaching
one preserves the other; named checks `host-integration` and `editor-drawer`
pass under the gate-A run below. Local structural inspection is not a behavioral
pass.

## Task-specific constraints

- No icon cache registry, duplicated icon state, asynchronous provider mode or
  threading change.
- Provider removal happens only after that attachment's image-consuming QML is
  destroyed (task 1's detach ordering); reattaching a page must not retrieve
  cached images from an earlier provider incarnation.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
