# Files Porydaw Reads & Writes

<!-- The trust page — hack developers want to know exactly what touches
their repo, and it makes Porydaw's writes reviewable in git. Mirror
porymap's "Project Files" page style: a table per operation. -->

## What Porydaw reads

<!-- TODO: Table: songs (sound/songs/**.mid + midi.cfg), voicegroups,
direct sound samples + .inc registrations, the registration files
(song constants, song table, Makefile lists...), engine settings
(maxChans etc.). "Read" means read — Porydaw never rewrites files you
didn't edit. -->

## What saving a song writes

<!-- TODO: The song's .mid + its midi.cfg line + its voicegroup file.
One document, one save. CRLF/format details only if user-visible in
diffs. -->

## What creating/registering/deleting a song writes

<!-- TODO: The per-file list of one-line registrations New Song adds
(and Delete Song removes); good practice: commit before bulk
operations, review the diff after. -->

## What a sample import writes

<!-- TODO: sound/direct_sound_samples/<name>.wav +
sound/direct_sound_data.inc entry; immediate (not undoable). -->

## Porydaw's own files

<!-- TODO: The .porydaw/ sidecar directory (view state, sample provenance)
— safe to gitignore or commit?; where app settings live per-platform
(QSettings paths). -->

## Round-trip guarantee

<!-- TODO: Opening and saving a song you didn't edit produces no diff;
Porydaw never "cleans up" files behind your back. -->
