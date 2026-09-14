# Context

One cohesive reusable policy is justified by repeated ownership/scope/grab behavior, not a one-line wrapper per target. Read [Global Constraints](plan.md#global-constraints), [spec.md](spec.md) and [inventory.md](inventory.md).

# Exact write set

- `src/ui/songview/quick/HoverHint.qml`
- `CMakeLists.txt`

# Prerequisites

Task 2 accepted; its CMake edit is the second reuse boundary.

# Interface contract

Implement the HoverHint contract in spec.md: required Item source, text, gestureOwning, actual releaseInside; existing root-context mouseHints and quickPopupSession. Preserve default nonblocking HoverHandler behavior and source-specific clear.

# Implementation steps

1. Create one sync path using actual session.isOpen/owns(source), effective source lifetime and hover. No static popup ownership exemption or independent popup state.
2. Re-sync on hover/profile changes, both session transitions and native scopeRefresh even when hovered is unchanged. A suppressed source must not claim empty.
3. Retain the originating profile during the existing group's grab and settle actual releaseInside on completion; hide/detach/scope loss overrides retention. Document smallest-group placement and no independently publishing child/ancestor.
4. Register HoverHint in both the CMake QML alias list and QML_FILES. Preserve the existing module/import pattern.

# Acceptance predicate

The Quick module compiles, and a controller-owned throwaway QML probe outside the repository imports this real component and demonstrates one-group child/parent transitions, ongoing scope rejection, retained-membership stationary close and release outside; composed/lost-membership proof is 5+17 and consumers 8/12/18/20. Controller: deno task build:checks, then named consumer suites once their wave settles. Remove the probe after evidence capture; do not add a permanent forwarding/plumbing test.

# Task-specific constraints

No generic UI action model or new input handling. CMake registration is a declared serialized reuse, not a hidden concurrent edit.
