# Song Settings

<!-- The midi.cfg flags as friendly controls. One section per setting:
what it does, audible effect, sensible defaults, in-game consequences. -->

## Opening Song Settings

Open **Edit → Song Settings** for the selected song. Controls edit a draft:
**Apply** commits it without closing, **OK** commits and closes on success,
and **Cancel** discards changes made since the last Apply. Song edits are
undoable and reach the project only when you use the normal Save command.

## Voicegroup

<!-- TODO: Which instrument bank the song uses; changing it re-voices the
whole song; link to Instruments & Voicegroups. -->

## Reverb

<!-- TODO: The GBA's echo effect; slider range; "game default" vs. song
override behavior; audible examples of low vs. high. -->

## Master volume

<!-- TODO: The song's own volume in-game (distinct from the transport's
listening volume — cross-link the disambiguation in Playing Songs). -->

## Master tuning

Below the song flags, use the **Master tuning (TUNE)** dial or type a nominal
**A4 Hz** frequency, such as `450`. The dial supports pointer input and
keyboard arrow keys; each step is one TUNE unit, or **1/64 semitone
(1.5625 cents)**. Applying **Reset to 440** removes all TUNE commands and the
master-setting marker; the engine's neutral default needs neither.

The readout shows the quantized nominal A4 frequency, cents relative to 440 Hz,
and integer units. The conversion rounds to the nearest unit using
`440 × 2^(units / 768)`, so entering 450 Hz does not promise exactly 450 Hz.
The supported master range is always **−64…+63 units**, regardless of existing
TUNE values.

**Warning: applying a master-tuning edit replaces all tracks' Fine tune / TUNE
(MIDI CC24) automation with the chosen uniform starting tune, or removes it
entirely at 440 Hz. Undo restores the original automation.** Notes retain
their identities; pitch bends, programs, event order, and timing are preserved.

The overwrite warning appears only after a master-tuning edit and only when
any track already contains TUNE commands. It clears after successful Apply or Cancel.

Moving the dial, typing an A4 reference, or choosing **Reset to 440** requests
this replacement when you press **Apply** or **OK**. Typing the current
reference or resetting an already-zero master still counts: it can clear
imported TUNE automation. Opening Settings or applying only unrelated settings
does not replace TUNE. After a successful application, repeating Apply without
another tuning edit does not replace it again. Cancel discards pending tuning
intent. Invalid frequencies or units outside the supported range stay visible
as errors and apply no other settings.

A failed voicegroup load leaves TUNE and the other song flags unchanged.
The requested voicegroup itself remains an undoable edit; correct it and
retry Apply.

Undo and Redo restore the master setting and its TUNE replacement together.
Reopening Settings or saved MIDI does not apply tuning twice.
Normal Save writes effective MIDI CC24 values and non-neutral master-setting
metadata; an ordinary game converter exports those CC24 values as **TUNE**
commands without a converter patch or flag. Resetting to 440 Hz exports no TUNE commands.
There is no automatic source save when you turn the dial or press Apply.

The A4 reference is nominal. Fixed-rate PCM and noise/PSG voices do not
necessarily follow an acoustically exact reference frequency.

## Priority

<!-- TODO: What song priority resolves in-game (music vs. fanfares vs. SE
stealing channels); when to raise/lower it. -->

## Exact gate

<!-- TODO: The exact-note-length flag in plain words: when off, note ends
quantize coarsely (the classic mid2agb behavior); when on, lengths are
preserved exactly. When it matters (staccato, tight rhythms). -->
