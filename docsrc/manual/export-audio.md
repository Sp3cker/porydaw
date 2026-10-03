# Exporting Audio

## Exporting a WAV

Choose **File → Export WAV…** while a song is open. Choose a sample rate of
32,000, 44,100, or 48,000 Hz (48,000 Hz by default). Looping songs offer 1–99
loops (2 by default) and a 0–60 second fade-out (5 seconds by default);
nonlooping songs offer a 0–60 second tail (3 seconds by default). The duration
updates as you change these options. Select a destination in the save dialog
(a sheet attached to the main window on macOS). The first export starts in
the project's `sound/songs/midi` folder; later exports remember the selected
folder. The status bar reports the full output path when rendering finishes.

Export renders the current unsaved song and the currently applied voice bank
as heard, without saving or changing the song. Rendering blocks input to the
whole app until it finishes. The progress window's **Cancel** button (or
Escape) stops rendering and removes the incomplete file.

## What export is for

<!-- TODO: Sharing previews, video soundtracks, comparing mixes. Note it's
NOT how music gets into the game — saving the song is (the build does the
rest). -->
