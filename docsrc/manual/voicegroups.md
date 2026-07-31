# Instruments & Voicegroups

<!-- Likely the most-needed conceptual page after polyphony. Assume the
reader has never heard the word "voicegroup". -->

## What's a voicegroup?

<!-- TODO: The song's instrument bank — a numbered list of up to 128 voices;
a track's "instrument" setting is just an index into this list. Songs can
share voicegroups (edits affect every song using it — warn!). -->

## The voice types

<!-- TODO: Friendly table:
- Sampled (DirectSound) — a recording played at different pitches
- Square 1 / Square 2 — classic chiptune pulse channels
- Programmable wave — drawable waveform channel
- Noise — percussion/hiss channel
- Keysplit — different voices per key range (how drum kits work)
- Percussion — the every-key-is-a-different-sound variant
Which are "the GBA's built-in channels" vs. sampled — link to
[Polyphony](polyphony.md). -->

## Browsing and auditioning voices

<!-- TODO: The voicegroup dock; type icons, ADSR summary; click to audition;
used-by-this-song highlighting; "Show voice in voicegroup" from a note. -->

## Editing a voice

<!-- TODO: The editable fields per type; all edits undoable and saved with
the song (one document, one save). -->

### ADSR envelopes

<!-- TODO: Attack/Decay/Sustain/Release in plain words with a picture;
the GBA's quantized envelope steps; PSG channels have coarser volume
levels than sampled voices. -->

### Choosing a sample or wave

<!-- TODO: The picker button: search filter, keysplit/sample/wave sections,
loop badges with rate/length details, audition-on-highlight through the
voice's own envelope; typing a symbol the scan didn't find still works. -->

## Assigning instruments to tracks

<!-- TODO: How a track picks its voice (program change / instrument
automation); changing instrument mid-song. -->

## Creating and registering voicegroups

<!-- TODO: When you need a new voicegroup vs. editing an existing one;
how New Song / MIDI Import can create one; where the files land. -->
