# Programmable-wave velocity levels

This note describes how porydaw maps stored MIDI velocity 1–127 to intrinsic GBA Channel 3 volume graduations. Live mixer attenuation is separate from this editing scale.

“Level” means the hardware attenuation class represented by a graduation. It does not mean equal perceived loudness: Channel 3 applies lossy scaling to 4-bit waveform samples, so the waveform values still affect the result.

## Result

GBA Channel 3 has **four audible output levels plus mute**:

- mute
- 25%
- 50%
- 75%
- 100%

The intrinsic editor mapping is:

| Stored MIDI velocity | Effective mid2agb velocities | Intrinsic CGB level | Channel 3 output | porydaw representative label |
|---|---|---:|---:|---:|
| 1–16 | 4, 8, 12, 16 | 0–1 | mute | 1 |
| 17–48 | 20, 24, 28, 32, 36, 40, 44, 48 | 2–5 | 25% | 32 |
| 49–80 | 52, 56, 60, 64, 68, 72, 76, 80 | 6–9 | 50% | 64 |
| 81–112 | 84, 88, 92, 96, 100, 104, 108, 112 | 10–13 | 75% | 96 |
| 113–127 | 116, 120, 124, 127 | 14–15 | 100% | 127 |

The representative is the default edit target, not the only valid stored velocity. For example, stored velocity **95** becomes effective velocity **96**, maps to intrinsic level **11**, and belongs to the same **75%** hardware class as stored velocities 81–112. That row normally uses representative **96**. While a note storing 95 is selected, porydaw instead displays 95 as the row’s return graduation and preserves it if the gesture leaves and returns to that row.

## Calculation

### 1. mid2agb velocity quantization

For stored velocity $s$:

```text
E = min(ceil(s / 4) * 4, 127)
```

Thus 1–4 become 4, each subsequent four-value group rounds up to its multiple of four, and 125–127 become 127. This matches `g_noteVelocityLUT` in mid2agb and `mid2agbEffectiveVelocity()` in porydaw.

### 2. Intrinsic CGB level

Porydaw derives a mixer-independent 4-bit level:

```text
G = floor((E - 1) / 8)
```

This produces levels 0–15. Square 1, Square 2, and Noise use those 16 levels directly. Programmable Wave groups them into its five output states below. CC7, song master volume, pan, rhythm pan, and modulation affect playback, but do not change these note-editing graduations.

### 3. Live mixer context

During playback, m4a additionally applies track volume, song master volume, pan, rhythm pan, modulation, and hard-pan routing before selecting the actual envelope goal. Those controls can attenuate a note or make a louder output state unreachable at that moment. That playback result is deliberately not the Velocity pane’s scale: changing mixer automation must not change the meaning or position of note-velocity graduations.

### 4. Software envelope goal to hardware output

m4a uses a 16-entry `gCgb3Vol` table; porydaw uses the same grouping for intrinsic level `G`:

```text
G 0–1   -> 0x00 -> mute
G 2–5   -> 0x60 -> NR32 code 3 -> 25%
G 6–9   -> 0x40 -> NR32 code 2 -> 50%
G 10–13 -> 0x80 -> GBA force-volume -> 75%
G 14–15 -> 0x20 -> NR32 code 1 -> 100%
```

This is why the intrinsic scale has 16 CGB levels while programmable-wave playback has only five output states. The voice ADSR can move the live `envelopeVolume` through these states after note-on; note velocity contributes to its peak and sustain.

## Implications for the editor

- Store MIDI velocity exactly. Do not replace every value with the representative.
- Derive the fixed hardware-level rows only from the resolved voice type.
- Treat all stored values in one row as one intrinsic hardware class.
- When a selected note differs from its row’s representative, display its exact value as that row’s graduation. Freeze it for the gesture so leaving and returning restores the exact value.
- Moves to other rows use their representatives; typed values and Undo data remain exact.
- Recalculate detents only when the resolved voice changes.

## Sources

Repository sources:

- `src/core/mid2agbtables.h`, `mid2agbEffectiveVelocity()`
- `src/core/psgvelocitymodel.cpp`, `makePsgVelocityContext()`, `psgVelocityLevel()`, and `representativeVelocity()`
- `external/poryaaaa/plugin/m4a_engine.c`, `m4a_track_vol_pit_set()` and `cgb_chn_vol_set()`
- `external/poryaaaa/plugin/m4a_channel.c`, `m4a_cgb_mod_vol()` and `m4a_cgb_channel_render()`
- `external/poryaaaa/plugin/m4a_tables.c`, `gCgb3Vol`
- pokeemerald-expansion `tools/mid2agb/tables.cpp`, `g_noteVelocityLUT`
- pokeemerald-expansion `src/m4a.c`, `CgbModVol()` and the Channel 3 hardware-register write
- pokeemerald-expansion `src/m4a_tables.c`, `gCgb3Vol`

Hardware reference:

- [GBATEK: GBA Sound Channel 3 — Wave Output](https://problemkaputt.de/gbatek.htm#gbasoundchannel3waveoutput): `SOUND3CNT_H` volume codes 0=mute, 1=100%, 2=50%, 3=25%, with the GBA force-volume bit selecting 75%.
