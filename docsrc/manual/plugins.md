# Plugins

Porydaw can be extended with small JavaScript plugins. A plugin can add
commands with their own keyboard shortcuts, entries in the **Plugins** menu
and in the piano roll's right-click menus, panels next to the Songs and
Voicegroup docks, drawings over the piano roll, and dialogs of its own. It
can read and edit the song (every edit is one Undo step), follow playback
in real time, and render the song to a WAV file.

## Installing a plugin

1. Open **Edit → Settings… → Plugins**. The page shows the plugins folder
   and a button to open it.
2. Copy the plugin's folder into it. A plugin is one folder holding a
   `plugin.json` and a `main.js` (the folder name must match the id in
   `plugin.json`).
3. The plugin loads right away and on every start. Untick it on the same
   page to switch it off without deleting it; the page also shows why a
   plugin failed to load, if it did.

Plugins reload themselves when their files change, so editing one while
Porydaw runs is fine.

!!! tip "Where the folder is"
    By default the plugins folder lives in Porydaw's application-data
    directory. **Change…** on the Settings page points Porydaw at any
    folder you like (the choice is remembered, and plugins reload from the
    new folder right away); **Use Default** goes back. Setting the
    `PORYDAW_PLUGINS_DIR` environment variable overrides the saved folder
    for that run only. The Settings page says when that is the case.

## Bundled examples

Porydaw ships example plugins in its `plugins/examples` folder. Copy any of
them into your plugins folder to try them:

| Plugin | What it adds |
|---|---|
| Select Same Pitch | a shortcut that selects every note with the selected note's pitch |
| Note Tools | Legato, Insert chord, Humanize, Strum and Quantize commands |
| VU Meter, Spectrum, Dancer | panels that follow the audio and the beat |
| Song Report | **Plugins → Song Report**: a text summary of the song, and a WAV render |
| Range Tools | right-click a time selection: duplicate it after itself, echo it with fading copies, reverse its notes |
| Scale Guide | shades the piano-roll rows outside a scale you pick per song |
| Project Tools | **Plugins → Project Tools**: registers every song whose registration files miss a line, and applies one envelope to all sample voices of the song's voicegroup |

## Shortcuts, menus and panels

- Plugin commands appear in **Settings → Keyboard Shortcuts** under the
  plugin's name and can be rebound like any other command. A plugin's
  default shortcut is dropped if it collides with an existing one.
- Plugin panels are listed under **View → Plugin Panels**; closing one is
  remembered.
- **View → Script Console** shows what plugins print and any errors, and
  offers a small console for trying API calls.

## Safety

Plugins run inside Porydaw with the same access to your project as Porydaw
itself, so only install plugins you trust. A plugin that hangs is stopped
after a few seconds and disabled until you reload it. File access from a
plugin is limited to its own folder, the open project, and files you pick in
a dialog it shows.

## Writing your own

The [Scripting API reference](../reference/scripting.md) documents
everything a plugin can do; type declarations in
[`docs/scripting/porydaw.d.ts`](https://github.com/huderlem/porydaw/blob/main/docs/scripting/porydaw.d.ts)
give editor completion. The bundled examples are the quickest way in.
