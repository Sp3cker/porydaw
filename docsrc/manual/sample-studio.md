# Importing Custom Samples

<!-- The "bring your own sounds" page. Emphasize the guarantee: what you
audition in the editor is bit-identical to what the built ROM plays. -->

## What you can import

<!-- TODO: .wav, .aif, .mp3, .flac, .ogg files, and zones from .sf2
SoundFonts. Where to legally find sounds could be a nice tip box. -->

## Opening the sample editor

Use Tools → Import Sample for a general import, or "New…" next to the
sample picker in the voicegroup dock to import into the voice you started
from. The slot flow opens a library-first editor: pick a folder on the
Library panel, preview files with a single click, and double-click to
load one for editing.

## Editing your sample

All edits are non-destructive on the original file. The Library panel
stays available while you edit: loading another file resets the editor
(fresh parameters, cleared undo, re-detected pitch) without touching the
project until you commit.

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

Single-clicking a library file previews it at the current audition key with
the default envelope, loop disabled and no edits from the current document.
The editor's Play button auditions the processed render that will be committed.

## Committing to the project

Committing writes the 8-bit `.wav` into `sound/direct_sound_samples/` plus
its registration in `sound/direct_sound_data.inc`. File registration is immediate
and cannot be undone. A destination voice assignment can be undone separately.
After a commit the refreshed sample set is preloaded so the new sample
is immediately usable.

## Re-editing later

"Edit…" reopens your original hi-res source exactly where you left off
(provenance sidecar); if the source file moved or changed it falls back
to the committed .wav, still editable. "Save as New" registers the
current render under a new name instead: the original sample's bytes,
history and voice slot stay exactly as they were.

## Requirements & limitations

Import requires a standard `wav2agb` build rule. Library previews decode
synchronously; large files can briefly pause the interface. Saved folders remain
listed if they move or become unavailable, with a notice instead of stale contents.
