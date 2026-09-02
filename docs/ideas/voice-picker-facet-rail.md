# Facet-rail voice picker

Status: **idea** — not implemented in the app. The shipping picker
(`src/ui/songview/voicepicker.cpp`) is still the search-and-list layout
(`QLineEdit` text filter). Only the shared family-classification helper
`src/ui/m4asemantics.{h,cpp}` landed on `fork-main`; the facet UI itself
was implemented on `origin/feature/voice-picker-improvements`
(`528c59f` "Implement live-preview facet voice picker", 2026-08-31,
1 ahead / 30 behind — predates the Qt Quick input port) but never merged.

## Idea

Replace the voice picker's search-and-list layout with a facet-rail browse
pattern. The picker must narrow `VoicePickerDialog`'s 128 voicegroup
entries when the reliable data is slot, name, m4a family, and whether the
song uses the slot.

Left facet rail:

- **Instrument family** — exclusive selection: All families plus Sample,
  Square 1, Square 2, Wave, Noise, Drumkit, Synth; each row shows a color
  swatch, name, and static count. Family classification comes from
  `m4aVoiceFamily` (`m4asemantics`, already on `fork-main`): synth
  predicate first, then drumkit keysplit, then the CGB-type mask; alt
  variants and DirectSound fall through to Sample.
- **Availability** — independent checkboxes for **Used in this song** and
  **Named voices only**, each with a static global count.

Right panel: results header (**N matching voices** plus **Clear filters**)
above the filtered 128-slot list. Text search is removed.

Preserved behaviors: whole-row press-and-hold audition, double-click
acceptance, font-scaled geometry (`layout::` primitives).

Reference deltas (deliberate, from the approved prototype variant):
the used row tag reads **Used in this song**, family tags are
contrast-safe, the per-row ▶ audition affordance is not carried over,
and the variant switcher / state bar were exploration scaffolding only.

Interaction with `voice-picker-live-change-plan.md` (still in `docs/`):
that plan's branch implements live preview on top of this facet picker;
the two ideas merge together or the live-change plan waits for this one.
