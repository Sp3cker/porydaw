# Porydaw Editor Context

Porydaw edits m4a-native song data through coordinated timeline surfaces. These terms cover the selection model and the automation lane family shared by those surfaces.

## Language

**Primary Track**:
The active editable engine track. A Note Selection is interpreted only on this track.
_Avoid_: Current track, selected track, active lane

**Track Scope**:
The non-empty set of engine tracks selected through the track headers for multi-track operations. It always contains the Primary Track.
_Avoid_: Multi-selection, selected tracks, track mask

**Note Selection**:
The ordered set of opaque note identities selected on the Primary Track.
_Avoid_: Selected notes, note range, highlighted notes

**Time Selection**:
An active half-open musical interval `[startTick, endTick)` with either Track Scope or Lane Scope. It may contain no musical events and is distinct from Note Selection.
_Avoid_: Loop region, note selection, range highlight

**Lane Scope**:
The explicit automation-lane identities (`LaneHandle`) stored inside an active lane-scoped Time Selection.
_Avoid_: Selected rows, automation selection, track scope

**Selection Projection**:
A surface-specific visual interpretation of canonical selection, such as rings around notes that overlap a Time Selection. It is not an additional selection state.
_Avoid_: Mirrored selection, copied selection, local selection

**Transient Selection Preview**:
Gesture-local selection feedback that has not become canonical selection, such as a piano-roll rubber band before release.
_Avoid_: Selection, temporary selection model, local selection

**Automation**:
The editor drawer's umbrella page and editing family across Tempo, Voice Change, and CC, rendered by `AutomationCanvas`. The family name — never a synonym for one kind.
_Avoid_: Automation lane (as a kind name), auto lane

**Node Lane**:
The point-editing lane kind spanning Tempo or CC only. Voice Change is explicitly non-node.
_Avoid_: Automation row, row

**CC Lane**:
A per-track, controller-backed node lane owned by `CCLanes`, such as volume, pan, expression, or bend. Its points hold MIDI controller values.
_Avoid_: Automation lane, controller lane, parameter lane

**Tempo Lane**:
The single global tempo node lane owned by `TempoLane`. It belongs to the song, not to any track.
_Avoid_: Tempo track, tempo row

**Voice Change Lane**:
The per-track, non-node lane of voice changes owned by `VoiceChangeLane`. Its value is a voice slot in the track's voicegroup.
_Avoid_: Voice row, program lane, voice node lane
