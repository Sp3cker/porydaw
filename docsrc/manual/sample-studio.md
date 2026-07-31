# Importing Custom Samples

<!-- The "bring your own sounds" page. Emphasize the guarantee: what you
audition in the editor is bit-identical to what the built ROM plays. -->

## What you can import

<!-- TODO: .wav, .aif, .mp3, .flac, .ogg files, and zones from .sf2
SoundFonts. Where to legally find sounds could be a nice tip box. -->

## Opening the sample editor

<!-- TODO: Tools → Import Sample, or "New… / Edit…" next to the sample
picker in the voicegroup dock (the latter auto-assigns the result to the
voice you started from). -->

## Editing your sample

<!-- TODO: Tour of the editor, one subsection per control group. All edits
are non-destructive on the original file. -->

### Cropping

### Loop points

<!-- TODO: What a sustain loop is and why GBA instruments need one; loop
auto-suggestion; the seam-click meter for finding a clean loop. -->

### Tuning

<!-- TODO: Pitch-detect prefill; retune without resampling (no quality
loss); why tuning matters (middle C should be middle C). -->

### Resampling & normalizing

<!-- TODO: GBA rates and the size/quality tradeoff; normalize. -->

## Auditioning

<!-- TODO: Keyboard audition inside the editor; the "what you hear is what
the ROM gets" guarantee, stated plainly. -->

## Committing to the project

<!-- TODO: What gets written: the 8-bit .wav into
sound/direct_sound_samples/ plus its registration in
sound/direct_sound_data.inc. This write is immediate (not undoable) —
say so clearly. ROM size note: samples cost space. -->

## Re-editing later

<!-- TODO: "Edit…" reopens your original hi-res source exactly where you
left off (provenance sidecar); what happens if the source file moved or
changed (falls back to the committed .wav, still editable). -->

## Requirements & limitations

<!-- TODO: Needs the standard wav2agb pipeline (vanilla decomp projects have
it); the actionable messages you get if a project doesn't. -->
