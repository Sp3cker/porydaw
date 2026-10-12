# Importing Custom Samples

<!-- The "bring your own sounds" page. Emphasize the guarantee: what you
audition in the editor is bit-identical to what the built ROM plays. -->

## What you can import

<!-- TODO: .wav, .aif, .mp3, .flac, .ogg files, and zones from .sf2
SoundFonts. Where to legally find sounds could be a nice tip box. -->

## Opening the sample editor

Choose **Tools → Import Sample** to open Sample Studio with its sample library
and a file picker. Canceling the picker leaves the studio open so you can
browse the library instead. You can also use **New…** or **Edit…** beside the
sample picker in the voicegroup dock; a sample committed from there is
assigned to that voice.

## Sample library

Choose **Add Folder…** to bookmark a folder. The library remembers saved
folders between sessions and lists supported audio files in the selected
folder. In the folder list, use Up and Down to navigate, Right to expand a
folder, and Left to collapse it or move to its parent. You can also use the
disclosure arrows to expand folders and click a folder to browse it.
**Remove from Library** removes the selected bookmark, not any files on disk.

Click an audio file to preview it; pressing Enter or Space while the file list
has focus toggles the preview. Moving through the list with arrow keys only
changes the selection. Double-click a file or choose **Load** to replace the
current editor source. **Open File…** opens the file picker, including for
SoundFont zones. If a file cannot be loaded, the current edit, name, and undo
history stay intact; the library shows the error without replacing the source.

Source preparation runs in the background. The current waveform stays visible
until a replacement is ready. Rapid selections keep only the latest request;
stopping a pending preview or closing the studio prevents it from starting later.

## Editing your sample

<!-- TODO: Tour of the editor, one subsection per control group. All edits
are non-destructive on the original file. -->

### Cropping

### Loop points

<!-- TODO: What a sustain loop is and why GBA instruments need one; loop
auto-suggestion; the seam-click meter for finding a clean loop. -->

### Tuning

Pitch analysis also runs in the background and does not change the base key
automatically. If it finds a stable pitch that differs from the current tuning,
choose **Use detected pitch** to apply the suggestion.

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
left off (source record kept in Porydaw's preferences, not the project); what
happens if the source file moved or changed (falls back to the committed .wav,
still editable). -->

## Requirements & limitations

<!-- TODO: Needs the standard wav2agb pipeline (vanilla decomp projects have
it); the actionable messages you get if a project doesn't. -->
