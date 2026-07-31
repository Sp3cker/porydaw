# The MIDI Event List

<!-- Power-user page. Open with "you may never need this" so beginners
don't feel obligated. -->

## What it's for

<!-- TODO: View → MIDI Event List swaps the piano roll for a table of every
raw event in the track: exact bytes, meta events, engine-specific commands
the roll doesn't visualize. When you'd want it: debugging an import,
hand-placing an engine command, inspecting a vanilla song. -->

## Reading the table

<!-- TODO: Columns (tick, type, channel, data, decoded summary); category
filters; the end-of-track row; the playhead row highlight. -->

## Editing events

<!-- TODO: In-cell edits (shared undo stack with the roll); inserting and
deleting events; deleting vs. the roll's note delete. -->

## Event order within a tick

<!-- TODO: Why same-tick order matters on the GBA (setup must precede the
notes it affects); the canonical order Porydaw maintains; reordering
within a tick by drag, Alt+Up/Down, or the context menu — and why you
can't drag across a tick boundary (edit the Tick cell instead). -->

## Engine-specific events

<!-- TODO: Friendly table of the m4a specials a curious user will meet:
the loop Label ([ / ]), MEMACC, XCMD, marker/text metas. One line each on
what they do and whether to touch them. -->
