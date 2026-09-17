# The Main Window

## Overview

Porydaw has several main panels. They are all resizable and can even be repositioned by dragging on each of their header areas.

1. **Song list**: All the songs are listed here. You can filter and order it.
2. **Voicegroup editor**: Displays all of the instruments used in the current song's voicegroup. Also allows editing!
3. **Piano roll**: View and edit the MIDI notes.
4. **Voice changes**: View and edit the voice changes (program changes) of the focused track.
5. **Automation lanes**: View and edit the tempo lane and the "effects" (MIDI CC) lanes.

![Porydaw Panels](../img/quick-start-littleroot-panels.png)

## The song list

![Porydaw Panels](../img/main-window-song-list.png)

All of the project's songs are listed in the song list. This includes sound effects. It supports filtering by prefix, as well as ordering by ID or alphabetical. Use `Ctrl+F` to type and search for song names.

To open a song, double-click on an item.

The right-click menu allows:

- `Open Song`
- `Open Song in New Tab`
    - You can have multiple songs open in different Porydaw tabs!
- `Register Song` (writes any missing file changes to the decomp project)
- `Delete Song`
    - This deletes the song from the standard locations, but it doesn't fully delete all references to the song from e.g. scripts or C code.

## Track headers

Track headers appear to the left of the piano roll. They display the track name, its current instrument/voice, mute and solo buttons. Click on a track to focus it. When focused, its notes and MIDI events can be edited in the piano roll area.

See [Working with Tracks](tracks.md) for more details.

## The piano roll

<!-- TODO: Explain the timeline, grid, loop markers, edit cursor, playhead, and note-editing link. -->

## The transport bar

<!-- TODO: Explain transport controls, position and tempo displays, master volume, and the polyphony meter. -->

## Voice changes

<!-- TODO: Explain Voice Changes editing, visibility, resizing, and its independent drawer page. -->

## Automation lanes

<!-- TODO: Describe the Automations drawer parameter selector and shared plot, then link to Automation. -->

## The voicegroup dock

<!-- TODO: Explain the current song's instrument list, auditioning, and the Voicegroups link. -->

## Working with multiple songs (tabs)

<!-- TODO: Explain opening, switching, dirty state, and closing for song tabs. -->

## Navigation cheat-sheet

<!-- TODO: Explain scroll and zoom gestures, playhead navigation, playback following, and the shortcuts link. -->
