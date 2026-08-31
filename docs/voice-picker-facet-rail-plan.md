# Facet-Rail Voice Picker — Implementation Plan

## Goal

Replace the voice picker's search-and-list layout with the approved facet-rail browse pattern (prototype variant A) from [`voicepicker-filter-prototype.html`](voicepicker-filter-prototype.html).

The left facet rail contains:

- **Instrument family** — exclusive selection: All families plus Sample, Square 1, Square 2, Wave, Noise, Drumkit, and Synth; each row shows a color swatch, name, and static count.
- **Availability** — independent checkboxes for **Used in this song** and **Named voices only**, each with a static global count.

The right panel shows a results header (**N matching voices** plus **Clear filters**) above the filtered 128-slot list. Text search is removed. Whole-row press-and-hold audition, double-click acceptance, and the dialog's font-scaled geometry behavior are preserved.

Approved-reference deltas from the audit (deliberate, not drift): the used row tag reads **Used in this song**, family tags are contrast-safe, the prototype's per-row ▶ audition affordance is not carried over, and geometry is font-scaled rather than fixed-pixel. The prototype's facet-variant label is synced to match; its variant switcher and state bar are exploration scaffolding and are not part of the product.

## Steps

1. **`src/ui/m4asemantics.h` / `src/ui/m4asemantics.cpp`** — shared family classification
   - Direct include closure: the header adds `#include "voicegroup/voicegroup_types.h"` (bare style, as `songview.h` already includes `"voicegroup_loader.h"`). `ToneData` is an anonymous C typedef and cannot be forward-declared as `struct ToneData`; the header today defines no `ToneData`.
   - Declare:
     ```cpp
     enum class VoiceFamily { Sample, Square1, Square2, Wave, Noise, Drumkit, Synth };
     VoiceFamily m4aVoiceFamily(const ToneData &tone);
     ```
   - Implement `m4aVoiceFamily` with this precedence:
     - **Synth** when `(tone.type & ~0x18) == 0 && tone.wav && tone.wav->size == 0 && tone.wav->data` — a zero-sized DirectSound descriptor. This is the predicate currently local to `voicegroupbrowser.cpp` as `toneIsSynth`.
     - **Drumkit** when `tone.type == VOICE_KEYSPLIT_ALL`.
     - Otherwise switch on `tone.type & VOICE_TYPE_CGB_MASK`:
       - `VOICE_SQUARE_1` → `Square1`
       - `VOICE_SQUARE_2` → `Square2`
       - `VOICE_PROGRAMMABLE_WAVE` → `Wave`
       - `VOICE_NOISE` → `Noise`
     - The alt variants (`0x9`–`0xC`) fall through the same mask cases. All other types — DirectSound plain/fixed/reverse, keysplit, cry tones — map to `Sample`.
   - Precedence safety: keysplit/drumkit types (`0x40`/`0x80`) never satisfy the synth predicate, so the short-circuit order is safe for all 128 loaded slots; the CGB-mask mapping mirrors `m4aVoiceTypeName`.

2. **`src/ui/voicegroupbrowser.cpp`** — single source of truth for synth classification
   - Route-through is mandatory: `toneIsSynth` becomes `return m4aVoiceFamily(td) == VoiceFamily::Synth;`, or the helper is deleted and that expression used at its call sites. Two independent synth classifications would drift.

3. **`src/ui/songview.h` / `src/ui/songview/trackvoiceops.cpp`** — display metadata beside `voiceShortName`
   - `songview.h` includes `"ui/m4asemantics.h"` so the `VoiceFamily` return type is complete; `trackvoiceops.cpp` keeps its direct `m4asemantics.h` include.
   - Add:
     ```cpp
     QString voiceDisplayName(uint8_t program) const;
     VoiceFamily voiceFamily(uint8_t program) const;
     ```
   - Both mirror `voiceShortName`'s guard exactly, with the total fallback documented in the header — `uint8_t` admits 128..255 and the guard prevents reads beyond the 128-entry `LoadedVoiceGroup`:
     ```cpp
     if (!m_voicegroup || program >= VOICEGROUP_SIZE)
         return QString();            // voiceFamily returns VoiceFamily::Sample here
     return QString::fromUtf8(m_voicegroup->voiceNames[program]).trimmed();
     // voiceFamily: return m4aVoiceFamily(m_voicegroup->voices[program]);
     ```

4. **`src/ui/songview/voicepicker.h` / `src/ui/songview/voicepicker.cpp`** — rebuild the dialog body
   - Header include closure: `voicepicker.h` adds `"ui/m4asemantics.h"` (VoiceFamily), `"voicegroup_loader.h"` (VOICEGROUP_SIZE), `<QSet>`, `<QStringList>`, `<array>`, `<optional>`, and `<cstdint>`; it currently includes only `QDialog` and `<functional>`.
   - Replace the root `QVBoxLayout` with a `QHBoxLayout`: facet rail left, list right.
   - Remove `QLineEdit`, its `textChanged` connect block, and the `QLineEdit` include. Give the list initial keyboard focus (`m_list->setFocus()` replaces `searchField->setFocus()`).
   - Facet rail (`QWidget` + `QVBoxLayout`, themed background, right border from `song_view_separator`):
     - heading **Instrument family**;
     - checkable exclusive `QToolButton`s for **All families** and the seven families; each row shows a color swatch, name, and count pill;
     - heading **Availability**;
     - `QCheckBox` **Used in this song** with count;
     - `QCheckBox` **Named voices only** with count.
   - Results header above the list: a live **`N matching voices`** label and a **Clear filters** text button.
   - Keep the existing `QListWidget` on the right and keep its selection/audition wiring.

5. **Counts and filter semantics — exactly the prototype's**
   - Family counts are static raw cardinalities computed once from `m_families`: each family row shows its own count; **All families** shows `VOICEGROUP_SIZE` (128). They never change with filters.
   - Availability counts are static global predicate counts: **Used in this song** = `m_usedSlots.size()`; **Named voices only** = number of non-empty display names. They never change with filters.
   - Only the results header is dynamic: the count of rows passing the composed AND filter.
   - **Clear filters** resets the family to All, unchecks both boxes, and refreshes.
   - Unnamed slots display the family label as fallback (the prototype's italic `.unnamed` treatment) in both the row and its accessible text.
   - All filters compose as AND terms.

6. **Dialog-owned snapshots**
   ```cpp
   std::array<VoiceFamily, VOICEGROUP_SIZE> m_families;
   QStringList m_displayNames;
   QSet<int> m_usedSlots;
   ```
   - Populated synchronously during dialog construction on the GUI thread from `sv->voiceDisplayName()` / `sv->voiceFamily()` / `sv->usedVoices()`; `m_usedSlots` is restricted to 0..127.
   - `refreshVisibility()` and all painting consume only these snapshots. Never reconsult `SongView` or `m_voicegroup` from paint; never store `ToneData`/`LoadedVoiceGroup` pointers — the raw voicegroup pointer can be replaced, possibly null while the old bank is freed, while the dialog is open. A bank swap during the dialog must not alter rendered rows.
   - Store `QPushButton *m_okButton` (from the `QDialogButtonBox`) and a `QLabel *m_emptyState` as members so `refreshVisibility()` owns the OK/empty state.

7. **Filter state and the zero-visible invariant**
   ```cpp
   std::optional<VoiceFamily> m_family; // nullopt = All
   bool m_usedOnly = false;
   bool m_namedOnly = false;
   ```
   `refreshVisibility()`:
   - One pass over all 128 items computing visibility and `firstVisible`.
   - If `firstVisible` is null: `m_list->setCurrentItem(nullptr)`, disable `m_okButton`, show `m_emptyState` with the prototype's wording ("No voices match this view. Clear a filter to return to the 128-slot voicegroup.", secondary text role), and return. Acceptance is impossible while OK is disabled, so `selectedVoice()` is never reached in that state.
   - Otherwise: enable `m_okButton`, hide `m_emptyState`, and select `firstVisible` whenever `currentItem()` is null or hidden.
   - Factor the visibility/next-selection decision into a testable free function (snapshots and filter in; visible set and next row out) so the step-11 check can exercise it without widgets.
   - `selectedVoice()` keeps its real semantics — `std::max(0, m_list->currentRow())`, not the raw `currentRow()` an earlier revision of this plan claimed. It is only meaningful once the invariant holds; assert the current row is in [0, 127].

8. **`VoiceRowDelegate : public QStyledItemDelegate`** in the translation unit's anonymous namespace
   - Non-copyable; constructor takes the three snapshot references plus parent: `new VoiceRowDelegate(m_families, m_displayNames, m_usedSlots, m_list)`, installed with `m_list->setItemDelegate(...)` — the repo's existing pattern (`eventlistview.cpp` parents its delegate to the view). A stack delegate would dangle after the constructor; a parentless heap delegate leaks.
   - Indexes the snapshots only by `QModelIndex::row()`; stores no view or voicegroup pointers.
   - Paint, contrast-safe:
     - slot number: monospace with tabular numerals, secondary text role;
     - display name: primary text role, ellipsized; blank name → italic family-label fallback in secondary text;
     - family tag: family color used as swatch/border/fill only with a contrast-selected foreground (theme primary text) — never family-colored text on the panel background, where the prototype's colored tags measure only ~2.4:1–3.3:1 at 11px;
     - **Used in this song** tag on used slots;
     - ordinary text from `song_view_primary_text` / `song_view_secondary_text`, row background from `song_view_piano_roll_background`, normal borders from `song_view_separator` (the existing dedicated outline role), and selected/focused state from `song_view_selection_fill` / `song_view_selection_edge` so keyboard focus is always visible;
     - accessible text per row: slot number + resolved visible name + family label, plus **Used in this song** when applicable, set as `Qt::AccessibleTextRole` on each item.
   - `sizeHint()` returns the row height and metrics from `Geometry::resolve()`.

9. **Geometry — font-scaled minimum dialog width** (decision: minimum width, not a responsive/scrolling rail)
   - Keep the `QEvent::FontChange` → `refreshGeometry()` mechanism; `event()` stays unchanged.
   - Revise `Geometry::resolve()` to derive every metric from `layout::fontPx` / `layout::fontPxF` / `layout::space` / `layout::singlePixel` — no hard-coded pixels:
     - facet-rail minimum width (prototype: 260px at the reference font);
     - result-column minimum width so slot/name/two-tag rows fit (prototype: 760px total dialog minimum);
     - row height (prototype: ~39px), tag metrics, panel margins, and spacing;
   - The dialog's minimum width becomes rail minimum + column minimum + margins — the font-scaled equivalent of the prototype's `min-width: 760px` — and `refreshGeometry()` updates `minimumWidth` as well as the resize.

10. **Preserved behavior and public result semantics**
    - `itemPressed` + `releaseVoice()` + the viewport `MouseButtonRelease` event filter + the destructor's `releaseVoice()` continue whole-row press-and-hold audition unchanged: start on press, stop on release anywhere, stop on every close path. The prototype's per-row ▶ affordance is deliberately not adopted.
    - `itemDoubleClicked` continues to accept.
    - `refreshGeometry()` and `event()` remain as today, extended only per step 9.
    - Live-change interplay: with text search gone, filter-driven `currentRowChanged` is the sole live-apply trigger. If the live-change plan lands, its row observer connects after the initial `setCurrentRow`/`scrollToItem` so opening the dialog never previews; without it, filter-driven moves only update the eventual selection.

## Product decisions

Resolved conservatively from the existing approved contract:

- **Audition affordance** — retain whole-row press-and-hold; no new per-row icon. (Closes the open F-09 decision.)
- **Narrow-width policy** — font-scaled minimum dialog width matching the prototype rail; not a responsive/scrolling rail. (Closes the open F-08 decision.)
- **Used filter naming** — "Used in this song" everywhere: checkbox, row tag, accessible text, and verification. The data source stays `SongView::usedVoices()`; a voicegroup-membership test would be tautologically all 128 rows. (F-07.)
- **Text search** — removed; the facet rail is the only narrowing surface.

## Critical files

- `docs/voicepicker-filter-prototype.html` — approved interaction and visual reference (variant A; its run instruction now points at `docs/`).
- `src/ui/m4asemantics.{h,cpp}` — shared family classification.
- `src/ui/voicegroupbrowser.cpp` — synth predicate routes through the shared classifier.
- `src/ui/songview.h` and `src/ui/songview/trackvoiceops.cpp` — bounds-guarded voice metadata accessors.
- `src/ui/songview/voicepicker.{h,cpp}` — facet controls, snapshots, filtering, delegate, geometry.
- `src/ui/theme/theme_roles.h` — role names consumed by the delegate.
- `src/checks/vgcheck.cpp` — family-classification coverage.

## Verification

- Build with `deno task build:checks`; run the suite with `deno task checks`.
- Deterministic check coverage:
  - A 128-slot classification table for `m4aVoiceFamily`: DirectSound plain/fixed/reverse, all CGB and alt variants, keysplit, keysplit-all → Drumkit, cry tones → Sample, synth (zero-size DirectSound descriptor), null `wav` (non-synth DirectSound), and the null-voicegroup accessor fallbacks (empty name, Sample).
  - A filter/selection helper test: AND composition, zero results (OK disabled, selection cleared, no hidden slot or slot 0 accepted), selected-row replacement when the current row is filtered out, restoration when filters clear, and the static-versus-dynamic count rules.
- Widget smoke pass: initial keyboard focus after search removal, tags and theme roles, press-and-hold start/stop, double-click acceptance, explicit empty state.
- Manual: there is no text-search field; family selection is exclusive and **All families** clears the restriction; both availability checkboxes compose as AND; zero-match combinations (e.g. **Named voices only** with no named entries, or no voicegroup at all) disable OK and clear the selection; counts match step 5; unnamed slots show the family fallback; keyboard focus is visible on every row; press-and-hold and double-click still work across a voicegroup swap and in the null-voicegroup state.
