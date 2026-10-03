# Task 255 brief — Sample picker parity: per-row loop badges and the fork detail line

# Context

Ruling 10 includes the sample picker. `SamplePicker.qml` (`src/ui/songview/quick/docks/`)
already ports the fork `SamplePickerButton` popup (sections, search, typed-symbol row,
audition on highlight, 2 s audition-off timer), but its information differs from the fork:
the fork marks every looped sample row with "∞" (tooltip "Loops") and shows a detail line
"<Loops|One-shot> · <rate> Hz · <seconds> s" from committed sample data for the highlighted
row ("Keysplit instrument" for keysplits, "Unlisted symbol" for the typed row, empty when
unknown) — `git show fceecd88:src/ui/samplepicker.cpp` 216–245 (`rebuildList`), 325–349
(`updateDetail`); info source `workspaceui_voicegroup.cpp` 260–271 (`samplePickInfoFor`:
known when data and size > 0; looped = `status & 0x4000`; `rateHz = freq / 1024`; seconds =
size / rateHz). Swift today shows "N samples · F Hz" and a single footer "Loop" label, set only
as a side effect of the highlight audition (`ApplicationSession+Audio.swift` 62–106).

Surface: VoiceEditor sample picker popup.
Ledger spec: `src/checks/visual/proof.browsers.txt` samplePickerPopup A013, A014, A015, A017
GAP → MATCHED (picker trigger exists for the DirectSound slot; opening yields the popup;
popup visible; popup closes when its editor is hidden). Blocked rows left untouched: A018
(frozen baseline compare — standing exclusion), PARTIAL A007/A009/A011 (voicegroup-browser
pixel/profile residues — standing exclusion).
Verify lane: `shell-voicegroup-picker`.

# Exact write set

- `src/swift/project/ProjectStore+Picker.swift` — `pickerSampleInfo() -> [String:
  PickerSampleInfo]` from the existing `PickerSampleCache` (built on demand exactly as
  `pickerSound` builds it); `public struct PickerSampleInfo: Sendable, Equatable { looped,
  rateHz: Int, seconds: Double }`.
- `src/swift/app/ProjectService+Picker.swift` — NEW: `pickerSampleInfo() async ->
  [String: PickerSampleInfo]`.
- `src/swift/app/CMakeLists.txt` — add the file (hot).
- `src/swift/app/voicelist/VoiceListController.swift` — replace `pickerSampleDetail`/
  `pickerSampleLoop` with `@QtIgnored pickerSampleInfo`, `@QtTracked pickerInfoRevision`,
  `onPickerSampleInfoRequested` callback, `requestPickerSampleInfo()`,
  `pickerRowLoops(symbol:) -> Bool`, `pickerDetail(symbol:keysplit:typed:) -> String`
  (fork `updateDetail` text; seconds with 2 decimals).
- `src/swift/app/ApplicationSession+Audio.swift` — drop the detail/loop side effects from the
  audition callbacks; wire `onPickerSampleInfoRequested` (load via the service, install on the
  controller, bump `pickerInfoRevision`; stale project/service results dropped like the
  audition revision guard).
- `src/ui/songview/quick/docks/SamplePicker.qml` — request info when the popup opens; per-row
  "∞" badge column (`vgSamplePickerLoopBadge`, tooltip "Loops") for looped non-keysplit rows;
  detail label bound to `pickerDetail`; remove the footer `vgSamplePickerLoop` label.
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline`.
- `src/checks/editorqml/tst_ShellVoicegroupPicker.qml` — replace the old detail/loop pins
  (lines 110–111, 159–169) with the fork-text predicates; add the A013–A015/A017 predicates.
- Ledger `proof.browsers.txt` A013–A015, A017.

Shared: `VoiceListController.swift` and `ApplicationSession+Audio.swift` (253/254 do not edit
them; other tracks: flag before dispatch), `src/swift/app/CMakeLists.txt`.

# Prerequisites

None in P4 (runs in the first wave with 240).

# Interface contract

As listed in the write set; badge text "∞" and tooltip "Loops"; detail strings exactly the
fork's. Rows for unknown symbols (no data) show no badge and an empty detail. The popup
requests info on every open; the store answers from its picker cache (rebuilt after a project
open or 248's cache reset), so a newly committed sample gains its badge on the next open.

# Implementation steps

1. Store/service info API; controller properties and callback; session wiring.
2. QML badge column + detail binding + request on open.
3. Picker journeys on `mus_route101` + the fixture bank (`fixture_loop` looped, a one-shot
   fixture): badges on exactly the looped rows; highlight detail "Loops · <rate> Hz · <s> s"
   with values computed in the check from the fixture `.bin` headers it reads independently;
   keysplit and typed-row details; trigger/open/visible/close-on-hide (hide the voice editor
   dock) predicates for A013–A015/A017.
4. `deno task bridge:baseline`; ledger edits.

# Acceptance predicate

The mounted picker badges looped samples and shows the fork detail line for sample, keysplit
and typed rows, and its popup opens from the DirectSound slot's trigger and closes when the
editor hides.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-voicegroup-picker --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-text-contrast --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

# Task-specific constraints

Badge/detail text colors from palette pairs valid on the popup surface (`windowText` on rows,
`secondaryText` for the detail on `windowBackground`; selected rows use `selectionText`). The
picker's existing audition behavior is unchanged except for losing the detail side effect.
Delete superseded pins rather than re-pinning them.
