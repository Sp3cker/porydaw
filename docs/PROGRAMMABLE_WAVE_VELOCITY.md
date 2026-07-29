# Programmable-wave velocity levels

This note describes the porydaw/m4a Channel 3 path from stored MIDI velocity 1–127 to the GBA programmable-wave output level.

“Level” means the hardware attenuation selected by m4a. It does not mean equal perceived loudness: Channel 3 applies lossy scaling to 4-bit waveform samples, so the waveform values still affect the result.

## Result

GBA Channel 3 has **four audible output levels plus mute**:

- mute
- 25%
- 50%
- 75%
- 100%

Under the default full-volume, centered-pan context—track volume/CC7 127, song master volume 127, pan/CC10 64, and no rhythm pan—the stored MIDI velocity ranges are:

| Stored MIDI velocity | Effective mid2agb velocities | m4a `envelopeGoal` | Channel 3 output | porydaw representative label |
|---|---|---:|---:|---:|
| 1–16 | 4, 8, 12, 16 | 0–1 | mute | 1 |
| 17–48 | 20, 24, 28, 32, 36, 40, 44, 48 | 2–5 | 25% | 32 |
| 49–80 | 52, 56, 60, 64, 68, 72, 76, 80 | 6–9 | 50% | 64 |
| 81–112 | 84, 88, 92, 96, 100, 104, 108, 112 | 10–13 | 75% | 96 |
| 113–127 | 116, 120, 124, 127 | 14–15 | 100% | 127 |

The representative is an edit target, not the only valid stored velocity. For example, stored velocity **95** becomes effective velocity **96**, produces `envelopeGoal` **11**, and plays at the same **75%** hardware level as stored velocities 81–112. Porydaw labels that default equivalence class with representative **96** while preserving the stored 95.

## Calculation

### 1. mid2agb velocity quantization

For stored velocity $s$:

```text
E = min(ceil(s / 4) * 4, 127)
```

Thus 1–4 become 4, each subsequent four-value group rounds up to its multiple of four, and 125–127 become 127. This matches `g_noteVelocityLUT` in mid2agb and `mid2agbEffectiveVelocity()` in porydaw.

### 2. Mixer context

Porydaw builds the CGB volume context as follows. All divisions and shifts truncate.

```text
V       = floor(clamp(CC7, 0, 127) * clamp(songMaster, 0, 127) / 127)
X       = (V * 64) >> 5
P       = clamp(2 * (clamp(CC10, 0, 127) - 64), -128, 127)
volMR   = ((P + 128) * X) >> 8
volML   = ((127 - P) * X) >> 8
R       = min(((128 + rhythmPan) * E * volMR) >> 14, 255)
L       = min(((127 - rhythmPan) * E * volML) >> 14, 255)
G       = floor((R + L) / 16)
```

For the default context, `X = 254`, `volMR = 127`, and `volML = 126`.

The live engine has the same core calculation, but also supports `track.volX`, `track.panX`, volume/pan modulation, and hard-pan routing. Hard pan clamps `G` to 15. Therefore the default table is not universal: track volume, song master volume, pan, rhythm pan, and modulation can move the velocity boundaries or make louder levels unreachable.

### 3. Software envelope goal to hardware output

m4a uses a 16-entry `gCgb3Vol` table:

```text
G 0–1   -> 0x00 -> mute
G 2–5   -> 0x60 -> NR32 code 3 -> 25%
G 6–9   -> 0x40 -> NR32 code 2 -> 50%
G 10–13 -> 0x80 -> GBA force-volume -> 75%
G 14–15 -> 0x20 -> NR32 code 1 -> 100%
```

This is why the software has 16 possible envelope goals but programmable-wave playback has only five output states. The voice ADSR can move `envelopeVolume` through these states after note-on; note velocity sets the peak `envelopeGoal`, and sustain is derived from it.

## Implications for the editor

- Store MIDI velocity exactly. Do not replace every value with the representative.
- Use the current voice and mixer context to calculate graduations.
- Treat all stored values in one row as one audible hardware class.
- Snap level-oriented gestures to the representative, but keep exact typed values and Undo data exact.
- Recalculate detents when CC7, song master volume, pan, rhythm pan, or the resolved voice changes.

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
