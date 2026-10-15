# Splitting Drumkits and Key Splits

Choose **Tools → Split Studio…** to open Split Studio. It needs an open project
(no song required). There is one Split Studio window for the whole app. It
always starts from an empty kit and never reads or changes any song. The title
bar shows **Split Studio**, with a `•` while the window has unsaved changes.

Press **Cmd+S** on macOS or **Ctrl+S** on Windows/Linux to save the voicegroup.
Press **Cmd+Z** on macOS or **Ctrl+Z** on Windows/Linux to undo an edit, and
**Cmd+Shift+Z** on macOS or **Ctrl+Shift+Z** / **Ctrl+Y** on Windows/Linux to redo
it. Window undo stays within the window. Press **Cmd+W** on macOS or **Ctrl+W**
on Windows/Linux or click **Close** in the footer to close the window.

## Layout

Split Studio is organized into three resizable panels, plus a top context bar and
a bottom footer:

- **Context bar**: Switches the layout between **Drumkit** and **Keysplit**.
- **Sample library** (left): Browse bookmarked folders and audio files to preview
  or load them. Click **+** (or the dashed folder box shown while the library is
  empty) to add a folder, or drag folders in from Finder; click **Open File…** to
  pick a file directly; expand **Advanced** to access **Remove Folder from List**.
- **Centre editor**:
  - File tabs along the top for loaded audio sources.
  - Toolbar with zoom out and zoom in buttons (magnifier icons) and **Fit**.
  - Waveform display showing slices and draggable slice markers.
  - **Snap to zero** toggle.
  - Slice table listing every slice in the kit, across all loaded files, with its
    grip handle, number, name, Play button, and Remove button.
  - Keyboard zone editor with an audition stop button (**■ Stop**), zoom out and
    zoom in buttons (magnifier icons), and 128 keys showing assigned slice badges
    and zone boundaries.
- **Inspector** (right): Parameters for the selected key, including **Sample
  rate** (**File**, **Saved at**), **Selected key** (note name, MIDI number,
  **Slice**), **Pitch** (**Plays at**), **Pan** (Drumkit only), **Envelope**
  (**Attack**, **Decay**, **Sustain**, **Release**), and **Remove from Key**.
- **Footer**: Window **Undo** and **Redo** buttons, a slice count and ROM size
  readout (for example `1 slice · 3.6 KB ROM`), the **Voicegroup** name field, **Close**,
  and **Save Voicegroup** (**Cmd/Ctrl+S**).

Split Studio remembers its window size, library width, and keyboard height
between sessions. Drag the divider beside the library or above the keyboard to
resize them.

## Drumkit and Keysplit layouts

The buttons in the context bar switch between the two kit layouts:

- **Drumkit**: Each mapped slice occupies a single key. Stereo **Pan** can be
  adjusted per key from -64 (hard left) to +63 (hard right).
- **Keysplit**: Slices can span multi-key ranges (zones). Keysplit voices are
  always pitched by the sound engine from the incoming key, so pan is disabled.

Both layouts maintain their edits while the window is open, so you can switch
between them as you work. The layout active when you click **Save Voicegroup**
determines what is written to the project.

## Slicing audio files

Each audio source loaded into Split Studio gets its own tab above the waveform
and tracks its own markers, slices, and sample rate:

- **Loading files**: Click an audio file in the sample library to preview it
  once; the strip under the file list shows its waveform and playhead.
  Double-click a file or click **Open File…** to load it into a new file tab. To
  close a file tab, click its **×** button; closing a tab automatically clears any
  keyboard keys mapped to its slices.
- **Adding one-shots**: Drag audio files from the sample library or from Finder
  onto the slice table. Each file loads in a new tab as a single slice and goes
  on the next free key from C2. While the table is empty it shows a dashed drop
  box; click it to pick a file instead. The table outlines in the accent colour
  while a drop would be accepted, and in red when the drag holds anything other
  than supported audio files (WAV, AIFF, MP3, FLAC, Ogg Vorbis); a red drop does
  nothing.
- **Selecting slices**: Click a row to select its slice; the waveform switches to
  that slice's file.
- **Adding markers**: Click anywhere on the waveform to add a slice marker.
- **Moving markers**: Drag a marker along the waveform to reposition the slice
  boundary.
- **Deleting markers**: Double-click a marker to delete it, or click a marker and
  press **Delete** or **Backspace**. Removing a marker merges the two neighboring
  slices.
- **Waveform navigation**: Turn the mouse wheel to zoom the waveform, or click the
  zoom buttons. Click **Fit** to view the entire audio file. Drag an empty part
  of the waveform (or middle-drag anywhere) to pan horizontally.

When **Snap to zero** is checked, adding or dragging markers automatically snaps
to the nearest zero-crossing point in the audio within about 3 ms.

Every slice keeps a short fade-out baked into its end to prevent clicks. There
are no per-slice fade controls.

### Slice names and numbers

Each slice is numbered consecutively. The slice number appears in the slice table,
on its waveform region, and as a badge on any keyboard key mapped to it.

Each slice receives a default name (`<source>_NN`), automatically skipping names
already taken in the project. To rename a slice, click its name in the slice
table. Press **Enter** to apply the new name or **Escape** to cancel. If a name is
not a valid symbol, duplicates another slice in the kit, or belongs to a project
sample that this Split Studio window did not save, the text box shows a red outline
and the rename is not applied.

## Mapping keys

Slices can be mapped across the 128-key keyboard (keys 0–127):

- **Automatic placement**: Every new slice is placed automatically on the next
  free key from C2 upward in both layouts.
- **Clearing keys**: When a slice disappears (by deleting a marker to merge
  slices, clicking the slice row's **✕** button, or closing its file tab), its
  assigned keys are automatically cleared.
- **Moving keys**: Drag a mapped key on the keyboard to move its slice to another
  key.
- **Drag-and-drop mapping**: Drag the grip handle (`⋮⋮`) of any row in the slice
  table onto a key, or drag an audio file from the sample library or Finder onto
  a key to load and map it there. The key under the pointer is outlined and
  labelled with its note name; it turns red, and the drop does nothing, if the
  drag holds unsupported files.
- **Resizing key ranges** (Keysplit only): Drag the left or right edge handles of
  a selected key zone to adjust the key range that triggers that slice. Zones
  never overlap.
- **Removing a mapping**: Click a mapped key to select it, then click **Remove from Key**
  in the inspector.

## Key parameters

Selecting a key on the keyboard displays its settings in the inspector on the
right:

- **Sample rate**: Shows the source file's original rate under **File**, and the
  downsampled export rate under **Saved at**. Choose from standard GBA rates in
  the dropdown.
- **Selected key**: Displays the note name, MIDI key number, and the mapped
  **Slice** name.
- **Pitch**: In the **Plays at** field, enter the root key where the sample plays
  at its original pitch (accepts note names like `C4` or MIDI numbers like `60`).
- **Pan** (Drumkit only): Adjusts stereo position from -64 (hard left) to +63
  (hard right), centered at 0.
- **Envelope**: Sliders for **Attack**, **Decay**, **Sustain**, and **Release**
  (each 0–255) control the sound envelope applied by the GBA sound hardware.

## Auditioning

You can audition sounds directly inside Split Studio:

- Click the play button (**▶**) beside any slice in the slice table to audition
  that slice. A mapped slice plays at its key's pitch with that key's envelope
  (pan is not applied); an unmapped slice plays as recorded. With the waveform
  focused, **Space** starts or stops the selected slice, or the first slice when
  none is selected. While a slice plays, a playhead like the main window's moves
  across the waveform.
- Click any key on the keyboard to audition it through the game audio engine
  with its pitch, pan, and envelope applied. Press an empty key and drag across
  the keyboard to audition each key you pass; dragging a mapped key moves it
  instead. Scroll sideways over the keyboard to pan it.
- Click **■ Stop** above the keyboard or press **Space** to stop playback.

Split Studio does not take live MIDI input.

## Saving voicegroups

The **Voicegroup** name field in the footer suggests `<first file>_kit` using the
next free name in the project. If the name is not a valid identifier or names a
voicegroup that this Split Studio window did not create, the field shows a red
outline. **Save Voicegroup** is disabled until at least one key is mapped and the
name is valid.

Click **Save Voicegroup** or press **Cmd+S** on macOS / **Ctrl+S** on
Windows/Linux to save the kit:

- Writes the slice samples (new 8-bit `.wav` files in `sound/direct_sound_samples/`
  and their registrations in `sound/direct_sound_data.inc`).
- Creates a new voicegroup file at `sound/voicegroups/<name>.inc` containing the
  drumkit or keysplit definition.
- Adds an `#include` line for the voicegroup in `sound/voice_groups.inc`.
- In Keysplit layout, writes the keysplit routing table into the voicegroup file.

Split Studio never changes any song or song voicegroup. To use your new
voicegroup in a song, assign it to a voice on a track in the main window.

### Overwriting saved samples

Saving again in the same Split Studio window rewrites that voicegroup and the
samples it created. Unchanged slice audio is not rewritten.

If a saved sample's audio changed (for example, if you moved slice markers or
changed its **Saved at** rate) and you click **Save Voicegroup**, Split Studio
prompts: `Overwrite N saved samples?` listing the modified files. Confirming
proceeds with the save; canceling aborts it. Samples created elsewhere are never
overwritten.

## Closing and unsaved changes

If you close Split Studio with unsaved changes — via the window close button,
**Cmd+W** on macOS / **Ctrl+W** on Windows/Linux, closing the project, or
quitting the app — a dialog asks **Save Voicegroup** / **Discard** / **Cancel**.
Saving completes the write before closing; Discard closes without saving; Cancel
aborts the close.

Closing a song tab never prompts or waits on Split Studio, because Split Studio
is independent of any song.

## Cleaning up unused slices

If you create slice files in Split Studio during an app session that end up not
referenced by any voicegroup (for example, if you slice samples and discard the
window, or rename slices after saving), Porydaw offers an orphan cleanup dialog
when you close a song tab, close the project, or quit the app.

A saved Split Studio voicegroup counts as an active reference, so its samples are
not treated as orphans. For unreferenced files created during the session, the
cleanup dialog presents a checklist with all items selected:

- **Delete**: Removes the `.wav` files and their registrations from the project.
- **Keep**: Retains the files on disk.

A file that gained a reference since the list was built is kept automatically, and
a status message names the preserved files.
