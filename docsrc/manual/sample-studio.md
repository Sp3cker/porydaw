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

When editing an existing project sample via **Edit…**, the window title shows
**Edit Sample — \<name\>**, the sample name is read-only, and the commit button
reads **Save Sample**. When importing a new sound, the commit button reads
**Add to Project**.

Press **Cmd+W** on macOS or **Ctrl+W** on Windows/Linux or click **Cancel** in
the footer to close Sample Studio without committing its edits. The song tab
stays open.

## Sample library

Click the **+** button in the Library header to bookmark a folder. The library
remembers saved folders between sessions and lists supported audio files in the
selected folder. In the folder list, use Up and Down to navigate, Right to
expand a folder, and Left to collapse it or move to its parent. You can also use
the disclosure arrows (▾/▸) to expand folders and click a folder to browse it.
Opening a branch reveals its children below the parent without jumping the tree
back to the selected folder.

Expand **Advanced** and click **Remove Folder from List** to remove the
highlighted bookmark, not any files on disk. The library browser does not show
hover tooltips.

Click an audio file to preview it; pressing Enter or Space while the file list
has focus toggles the preview. Moving through the list with arrow keys only
changes the selection. Double-click a file to load it into the editor as the
active source (there are no separate Preview or Load buttons). Click
**Open File…** to open the file picker directly, including for SoundFont `.sf2`
files and zones. If a file cannot be loaded, the current edit, name, and undo
history stay intact; the library shows the error without replacing the source.

Source preparation runs in the background. The current waveform stays visible
until a replacement is ready. Rapid selections keep only the latest request;
stopping a pending preview or closing the studio prevents it from starting later.

## Editor layout

Sample Studio is divided into three areas plus a footer:

- **Sample library** (left): Browse bookmarked folders, preview audio files,
  and load sources.
- **Waveform and audition bar** (centre):
  - Top toolbar with **Undo** (↶) and **Redo** (↷) buttons (also **Cmd+Z** /
    **Ctrl+Z** and **Cmd+Shift+Z** / **Ctrl+Shift+Z**), and zoom controls
    (**−**, **+**, **Fit**).
  - Waveform display with draggable crop and loop handles.
  - Listen bar below the waveform: **Listen** / **Stop** button, **Audition
    key** field, and **Use voice ADSR** checkbox (visible when a destination
    voice exists).
- **Inspector** (right): Collapsible control groups for **Sample**, **Trim**,
  **Loop**, **Pitch**, **Sample rate**, and **Advanced** settings.
- **Footer**: Displays the loaded source file name on the left, a **Cancel**
  button, and **Add to Project** (or **Save Sample** when re-editing).

## Editing your sample

All edits in Sample Studio are non-destructive on your original source file.

### Sample name

The **Name** field under **Sample** sets the symbol name used for the sample in
the decomp project. It defaults to a sanitized version of the audio file name.
If a name is not a valid symbol, duplicates another sample, or matches an
existing project sample, the field shows a red outline and the sample cannot be
committed. When editing an existing project sample, the name is read-only.

### Cropping

Under **Trim**, the **Crop range** fields (start and end frames) set the portion
of audio to keep in the rendered sample. You can adjust the range using the
spinboxes or by dragging the crop boundary handles directly on the waveform.

### Loop points

Under **Loop**, check **On** to enable sustain looping:

- Set loop boundaries using the **Start** and **End** frame spinboxes or by
  dragging the loop handles on the waveform.
- **Seam**: Shows a verdict on the loop seam quality: **Clean**, **Fair**, or
  **Clicks**, based on amplitude and slope continuity at the seam.
- **Try Another Loop**: Automatically searches the audio for alternative
  zero-crossing loop points.
- **Refine**: Nudges loop endpoints to the closest zero-crossing alignment.
- **Smooth seam**: Check this box to crossfade the loop seam, eliminating
  residual clicks.

### Tuning

Under **Pitch**, the **Base key** specifies the root note where the sample plays
at its original pitch (accepts note names like `C4` or MIDI numbers like `60`).

Pitch analysis runs in the background and does not change the base key
automatically. If it finds a stable pitch that differs from the current tuning,
click **Use detected pitch** to apply the suggestion.

### Resampling & normalizing

Under **Sample rate**:

- **File**: Readout showing the original file sample rate.
- **Saved at**: Dropdown allowing you to choose or type a target GBA sample
  rate.
- **ROM**: Readout showing the estimated ROM byte size required by the sample.

Under the collapsible **Advanced** section:

- **Fine tune**: Adjusts tuning in cents (-50 to +50 cents).
- **Normalize**: Select a normalization mode (**Auto**, **Looped (−9 dBFS loop
  RMS)**, **One-shot (peak)**, or **Off**).
- **Applied gain**: Readout showing the gain adjustment applied in decibels (dB).

## Auditioning

Click **Listen** (or press **Space**) in the audition bar below the waveform to
start playback through the game audio engine; click **Stop** (or press **Space**)
to stop.

Change the **Audition key** field to hear the sample pitched up or down across
the keyboard. When editing a sample assigned to a destination voice, check
**Use voice ADSR** to hear the sample auditioned through that voice's envelope.

What you audition in the editor is bit-identical to what the built ROM plays.

## Committing to the project

Click **Add to Project** (when importing a new sound) or **Save Sample** (when
editing an existing sound):

- Writes the rendered 8-bit unsigned PCM `.wav` into
  `sound/direct_sound_samples/`.
- Registers the sample in `sound/direct_sound_data.inc`.
- If opened from the voicegroup dock, assigns the sample to the destination voice.

This write is immediate and modifies project files directly.

## Re-editing later

<!-- TODO: "Edit…" reopens your original hi-res source exactly where you
left off (source record kept in Porydaw's preferences, not the project); what
happens if the source file moved or changed (falls back to the committed .wav,
still editable). -->

## Requirements & limitations

<!-- TODO: Needs the standard wav2agb pipeline (vanilla decomp projects have
it); the actionable messages you get if a project doesn't. -->
