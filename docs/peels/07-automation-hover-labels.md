# Peel 07 — Automation hover & gesture value chips

Read `docs/peels/GROUND-RULES.md` first. Target: main's `AutomationArea` hover
readout (`hoverReadoutGeometry`/`paintHoverReadout` in `src/ui/songview.cpp`).
Source: branch `automationhover.{h,cpp}` (esp. `:51-98`, `:125-290`, `:292-349`),
`automationpaint.cpp:223-258`. This is UI polish — moderate effort, zero document-
layer changes. The branch class drags four drawer types through every call; do NOT
port the class — re-express the behaviors inside main's existing hover machinery.

## Behaviors to port

1. **Hover ring on the node under the cursor** (branch `automationpaint.cpp:223-236`)
   — main's readout marks the curve value at the cursor tick but doesn't
   distinguish "you are on this point".
2. **Voice-row hover readout**: hovering the voice row shows `→ NNN name` for the
   voice in effect at the cursor tick, suppressed when directly over a voice
   marker (branch `automationhover.cpp:82-98`). Main's voice row has no hover
   readout at all.
3. **Gesture preview chip with background**: during any drag (point move, sweep,
   line — and pencil), the committed-value readout renders as a filled chip
   (background + text) clamped inside the row plot, instead of main's bare text
   that can collide with the curve (branch `automationhover.cpp:292-349` placement
   + `automationpaint.cpp:243-258` chip). In a group drag (if Peel 04 landed) the
   chip follows the grabbed node.
4. **Invalidation hygiene**: chip/readout invalidation on font change and row
   rebuild (branch `automationarea.cpp:190-199`, `:205-215`) — main already does
   region-union dirty rects for the idle readout; extend the same pattern, don't
   invent a cache. High-DPI text bounds need the DirectWrite overdraw padding
   main's readout already applies (see the `textBounds ... adjusted(-3,-3,3,3)`
   comment) — reuse it.

## Explicitly exclude

- The branch's `AutomationHoverState` class shape and its Page/Projection/Rows
  parameters — drawer architecture.
- `nodeMarkersVisible` DPI-scaled threshold (branch `automationprojection.cpp:157`)
  — optional nicety; if you adopt it (replacing main's hardcoded `pxPerBeat >= 24`),
  make it its own commit with its own probes, and keep the drawing-only gating
  (do not add pencil-mode hit-test gating here).

## Tests

- rollcheck probes: hover exactly on a dot → ring painted (pixel probe at the
  ring radius, NoAntialias-safe — see the themecheck ink-scan lesson: force
  predictable rasterization or probe state, not antialiased pixels); voice-row
  hover → readout text present, suppressed over a marker; during a point drag the
  chip stays inside the row rect even at row edges (drag to top/bottom edge);
  no stale-trail regressions (move hover fast, assert old regions repainted —
  the existing hover-restore probes cover the pattern; extend them).
- Negative-test each probe; SF 1/1.5/2 (chip clamping is geometry-sensitive);
  ASAN sweep + ctest; CHANGELOG (SPEC.md only if behavior, not just paint, changed).
