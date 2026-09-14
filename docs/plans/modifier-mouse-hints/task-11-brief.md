# Context

Cover the Drawer voice-change rows without changing picker or marker behavior. Read [Global Constraints](plan.md#global-constraints) and the linked specification/inventory.

# Exact write set

- `src/ui/editordrawer/voicechangearea/voicechangearea.h`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`

# Prerequisites

Tasks 4 and 15 (accepted atomic host cutover), Task 17 (live view integration)

# Interface contract

VoiceChangeArea::updateHover/clearHover/pointerMove retain marker identity and drag phase ownership. Private hint refresh may share that classification, but clearing visual hover during a drag must not accidentally clear the retained description.

# Implementation steps

1. Publish Alt fine-time left-drag only on a real marker; publish Shift-wheel horizontal scroll on the plot, not the gutter.
2. Do not add a modifier variant to picker double-click or derive availability from marker movability, track state or current voice.
3. Publish through the emitting host's setMouseHint and explicitly use empty for the gutter. Preserve the originating drag profile when visual clearHover runs; bands never clear ownership. Task 4 owns physical leave/release/hide/detach.

# Acceptance predicate

Marker/background/gutter transitions distinguish fine-placement from ordinary plot scrolling while voice edits and picker interaction remain unchanged. NAMED CHECKS: `deno task verify --filter editor-drawer --filter selectionkey --verbose` (controller), plus voice-marker Native acceptance.

# Task-specific constraints

The shared visual clearHover function runs when marker dragging becomes active; preserve the hint in that case rather than mechanically clearing on every call.
