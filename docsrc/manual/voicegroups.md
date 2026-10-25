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

Voice parameters belong to the voicegroup, not to the song. Changing ADSR,
tuning, sample selection, or voice type marks the voicegroup unsaved without
marking the song tab unsaved. All songs using that group hear the changes.

The voicegroup editor has its own undo history. Undo/Redo while editing a
voice operates on the shared group's history; Undo/Redo in the piano roll
operates on the song. Changing the song's assigned voicegroup remains a song
edit and does not undo parameters inside either group.

Use **Save Voicegroup** in the menu or dock to save the group without
rewriting song MIDI. **Save Song** saves only the song; **Save All** saves
dirty songs and voicegroups. The standard **Save** shortcut targets the
current editing surface.

Closing a song tab leaves unsaved voicegroup edits available in the dock,
even after the last song closes. Closing the project or quitting waits for
in-progress group edits, then prompts separately for each unsaved voicegroup.
**Discard** restores the group for
every song using it; **Cancel** stops closing.

With no song tabs open, the dock's group selector switches between loaded
voicegroups. Saved groups stay available with their own undo history.

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

Click **+** beside the voicegroup name in the dock to create a voicegroup.
Enter a name, choose a copy of the current bank or an empty template, then
click **Create**. The new group is written under `sound/voicegroups/` and
assigned to the current song.
