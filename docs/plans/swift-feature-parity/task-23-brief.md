# Context

Voice short-name parity (user direction: surfaces must look like the fork-main
QWidget app). The side-by-side capture (`/tmp/porydaw-swift-ref/a-main-window.png`
vs `/tmp/porydaw-qwidget-ref/a-main-window.png`) shows track headers and the
voice lane reading `000 DirectSoundWaveData_fixture_loop (Sample)` where the
original reads `000 fixture_loop (Sample)`.

Root cause (verified): every Swift consumer — track-header subtitles
(src/swift/app/headers/TrackHeadersGeometry.swift:257), voice-lane labels and
picker rows (src/swift/app/drawer/voicechanges/VoiceChangesScene.swift:218,
VoiceChangesProjection.swift:344, 418, 478), polyphony panel rows
(src/swift/app/audio/PolyphonyPanelPresenter.swift:99) — goes through
`VoiceLanePolicy.label(slot:view:)`
(src/swift/app/drawer/voicechanges/VoiceLanePolicy.swift:123-135), which uses
the raw macro symbol `voice.symbol`. The original `SongView::voiceShortName`
(`git show fceecd88:src/ui/songview/trackvoiceops.cpp` lines 201-212) uses the
loaded voicegroup's `voiceNames[program]`, which poryaaaa fills with
`set_voice_display_name`
(external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.c:300-322): strip
one leading `DirectSoundWaveData_`, `ProgrammableWaveData_` or `voicegroup_`
prefix only when characters follow it, then truncate to
`VG_VOICE_NAME_LEN - 1` = 47 bytes (voicegroup_loader.h:11), trimmed. The
format is `"<name> (<type>)"`, or the type alone when the name is empty, or
`"Voice"` when both are empty; the lane prefixes `%03d `.

No proof ledger row pins these strings (existing label checks use
`VoiceLanePolicy.label` itself as the oracle); this is visual parity verified
by checks against the original rule plus capture comparison.

# Exact write set

- `src/swift/app/drawer/voicechanges/VoiceLanePolicy.swift` — `label(slot:view:)`
  derives the short name with the poryaaaa display-name rule. Implement the rule
  once as a small pure function in this file (or reuse an existing Swift
  equivalent if one exists: `VoiceListSemantics.voiceColumnText` strips only
  `DirectSoundWave`/`Data_`, which is NOT the same rule — do not reuse it as-is
  and do not change the voice list, whose column the capture shows already
  matching the original).
- `src/checks/drawerpresentation/voice_projection.swift` — replace the
  tautological oracle assertions with fixed expected strings:
  `000 fixture_loop (Sample)`, `002 fixture_bass (Sample (fixed pitch))`,
  `003 fixture_drum (Sample (reverse))`, a programmable-wave slot
  `NNN fixture_pulse (<its type name>)`, a CGB slot without symbol
  `NNN Square 1`, blank slot `NNN`, plus a pure-function case table for the
  rule's edges: exact-prefix-only symbol kept as-is (`DirectSoundWaveData_`
  → unchanged), `voicegroup_x` → `x`, no prefix unchanged, 60-character name
  truncated to 47. Use fixture `fixture_rich` (src/checks/fixtures/decompproject/sound/voicegroups/fixture_rich.inc).
- `src/checks/editorqml/tst_ShellTrackHeaders*.qml` or the roll track-header
  lane that already reads header subtitles (find it with
  `grep -rln "subtitle" src/checks/editorqml src/checks/rollqml`) — one mounted
  assertion that the first track header reads `000 fixture_loop (Sample)`.

# Prerequisites

HEAD at or after `c47e83d2`; task 22 edits event-list files only (disjoint).

# Interface contract

- `VoiceLanePolicy.label` keeps its signature and callers; only the name
  derivation changes. `pickerLabel`/`hoverLabel` inherit the change.
- Name bytes: truncate on a UTF-8 boundary at ≤ 47 bytes (poryaaaa truncates
  bytes; fixture names are ASCII, so assert ASCII truncation only).

# Implementation steps

1. Write the failing checks (fixed strings); record RED.
2. Change `label` to use the display-name rule.
3. Run the lanes; report GREEN with message strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --verbose` (split with `--filter` per lane if over
  180 s) and `deno task verify:qml-roll --verbose`
- `deno task verify:bridge`
- Controller visual acceptance: relaunch per skill
  `porydaw-qwidget-reference-capture`; track headers and voice lane read the
  short names.

# Visual parity

Counterpart: fork-main `fceecd88` `SongView::voiceShortName` and the poryaaaa
loader's display names; reference `/tmp/porydaw-qwidget-ref/a-main-window.png`
(track headers `000 fixture_loop (Sample)`, voice lane
`000 fixture_loop (Sample)`).

# Task-specific constraints

- No new UI, no new C++, no code comments, no pixel constants, no ledger edits.
- Do not read names from a second voicegroup lookup; derive from the existing
  `BankSlotView.voice.symbol` with the loader's rule.
