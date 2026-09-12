# Tick width

## Decision

Canonical musical **position** is `Tick`.

```cpp
using Tick = uint32_t; // src/core/timedefaults.h, global (same footing as NoteId)
namespace CoreTimeDefaults {
inline constexpr Tick kNoTick = std::numeric_limits<Tick>::max(); // UINT32_MAX
inline constexpr Tick kMaxTick = Tick(kNoTick - 1);
}
```

Not a strong type: ticks mix with `uint32_t` durations, `int64_t` deltas, `start + duration` sums, QCOMPARE, and QML. A struct would invent operators and still need a second type for ends that overflow `Tick`. The alias is vocabulary: every position is `Tick`, including already-32-bit fields. Durations stay `uint32_t`.

Do not widen `TimelineEvent` / `ViewNote` storage. At 120 BPM / 24 tpqn, `kMaxTick` is ~2.84 years. SMF VLQ deltas are 28-bit; `SmfFile::write` already emits `uint32_t` deltas.

## Bound (Task 1)

`parseTrack` keeps a uint64 accumulator. After `tick += delta`, if the absolute tick is `>= kNoTick` (`UINT32_MAX` before the alias exists), `SmfFile::read` fails:

`Track %1: tick position exceeds 32-bit tick range`

No clamp, no truncated load. A tick of `kMaxTick` still parses. `kNoTick` is reserved as the absent-loop sentinel.

## Widths

| Domain | Type |
| --- | --- |
| Musical position (`tick`, `startTick`, `endTick` storage, `lengthTicks`, loop ticks, clip span, grid segment start/next) | `Tick` |
| Duration, beat length, beats-per-bar, `ticksPerBeat` | `uint32_t` |
| `ViewNote::endTick()`, `noteEndTick`, any `start + duration` computed end | `uint64_t` |
| Sample position / length / loop samples | `uint64_t` (`UINT64_MAX` absent) |
| `xcmd` raw `index` / `sourceIndex` / `removeEvents` | `uint64_t` |
| `SongDocument::revision` | `uint64_t` |
| `setLoopTick` argument | `int64_t` (`-1` = remove) |
| Tick deltas | `int64_t` |
| Parse / rescale / `scaleTick` multiply-before-divide locals | `uint64_t` |

Already-`uint32_t` **positions** (`TimelineEvent::tick`, `ViewNote::startTick`, `LanePoint::tick`, `VoiceChange::tick`, `ClipNote::relTick`) become `Tick` (same width). Durations stay `uint32_t`.

`setLoopTick` keeps `-1` = remove. `loopTick` returns `kNoTick` when absent. The conversion lives in `setLoopTick`'s body.

## Sentinels

Public fields keep a sentinel. Do not switch to `std::optional<Tick>`.

- Tick-domain absent: `kNoTick`. `SongDocument::loopTick` returns `Tick`.
- Sample-domain absent: `UINT64_MAX` (unchanged). `MidiTimeline::hasLoop()` stays sample-based.
- A field and every tick-domain `UINT64_MAX` / `numeric_limits<uint64_t>::max()` site that observes it flip in the **same** task. After narrowing, `field == UINT64_MAX` compiles and is always false — so the same task also owns the named behavioral pin, not only the grep.
- Time-editor overflow guards that today compare against `UINT64_MAX` compare against `kMaxTick` (a `Tick > UINT64_MAX - span` promote is always false).
- `writeLanePoints` / `replaceSpan` “to end of song” arguments take `kNoTick`.
- `clipmime::scaleTick` clamp argument is `kMaxTick`, not `UINT64_MAX`.

## `rescaleDivision`

```cpp
bool rescaleDivision(SmfFile *smf, uint16_t newDivision, QString *error);
```

Preflight: if `uint64_t(maxTick) * newDivision / oldDivision > kMaxTick`, return false, **no mutation**, error

`Tick rescale to division %1 exceeds 32-bit tick range`

Else rescale with a uint64 intermediate (`Tick(uint64_t(tick) * newDivision / oldDivision)`). Reject, never clamp. `newDivision == 0` / `division == 0` / same division: return true, no-op (today’s early return, now bool).

```cpp
bool NewSongWizard::songFile(SmfFile *out, QString *error) const;
```

On success `*out` is the song to write. On failure `*out` is untouched and `error` is set when non-null. Blank-song mode always succeeds. Import mode: `removeRedundantSetterEvents`, then if rescale is selected and `rescaleDivision` fails, return false (do not leave the caller with source division). `WorkspaceUi::submitCreateSong` shows `QMessageBox::warning` titled `Import MIDI` (same as `SmfFile::readFile` failure) and does not create the song.

## Width fences (keep-order only)

No member reorders. No `#pragma pack`. `static_assert` sizeof only where narrowing without reorder is the size:

| Type | Size | Task |
| --- | --- | --- |
| `TempoPoint` | 8 | 2 |
| `TimeSigPoint` | 8 | 2 |
| `LaneMovePoint` | 8 | 3 |
| `PendingOff` | 16 | 4 |
| `GridSegment` | 16 | 5 |
| `NodePoint` | 8 | 6 |

Not on anything containing `QString` / `QByteArray`. Leave order, no size chase: `SmfEvent`, `SmfTrack`, `DocNote` (stays 48), `TimelineEvent`, `ViewNote`, `TempoMapPoint`, `OtherEvent`, `xcmd::Event` / `Point`.

## Event list / checks

`EventTableModel::setData` on a tick column (`handleRawTick`, `handleTempoTick`, `handleEndTick`): after converting the edit value to an integer, if it is `> kMaxTick`, return false and do not queue an edit. Do not add a new parse-failure detector; non-numeric conversion stays today’s `toULongLong` behavior.

`src/checks/eventviews/edits.cpp`:

- Keep `tick64BitExact` (`3000000000ULL`, `< kMaxTick`).
- `tickHighBitExact`: `setData` accepts digits of `kMaxTick` (`4294967294`); document tick is `kMaxTick`. `setData` with digits of `kNoTick` (`4294967295`) returns false and does not push undo. Delete the 2^53 comments.
- `tickHighBitThroughEditor`: type `4294967294` into the rendered editor; document tick and `TickStringRole` are those digits.

## Non-goals

- Strong `struct Tick`
- `typedef`-then-flip through `uint64_t`
- PortSMF
- Packing, sub-32 ticks
- Member reorders / padding program (`TempoMapPoint` 24, `OtherEvent` shuffle, `xcmd::Event` / `Point` regrouping). Sequel after this plan.
- Changing playback of files that already parse (except rescale overflow now fails closed)
- `ViewNote` duration / unterminated (already landed)
