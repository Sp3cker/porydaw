# Porydaw Editor Context

Porydaw edits m4a-native song data through coordinated timeline surfaces. These are spoken terms for humans and agents. Code identifiers are not speech.

## Selection

**Selected Track**:
The bold filled track-header row. Notes edit this track.
_Code_: `primaryTrack`
_Avoid_: primary track (speech), active lane

**Multi-selected Tracks**:
Only the shift-clicked extra headers. Never includes the selected track.
_Code_: extras inside `Track Scope` / `TrackMask` (the mask also contains the selected track)
_Avoid_: Track Scope (speech), selected tracks

**Note Selection**:
The ordered set of opaque note identities selected on the selected track.
_Avoid_: note range, highlighted notes

**Time Selection**:
An active half-open musical interval `[startTick, endTick)`. It may contain no musical events and is distinct from Note Selection. A piano-roll or ruler time selection covers every automation on the scoped tracks; outlines on inactive automation labels are still this, not a second object.
_Avoid_: loop region, range (menu leftover), lane scope (speech)

**Selection Projection**:
A surface-specific visual interpretation of canonical selection, such as rings around notes that overlap a Time Selection, or an outline on an automation label. It is not additional selection state.
_Avoid_: mirrored selection, copied selection, local selection, lane scope

**Transient Selection Preview**:
Gesture-local selection feedback that has not become canonical selection, such as a piano-roll rubber band before release.
_Avoid_: selection, temporary selection model, local selection

## Automation

**Automation**:
One of the nine catalog identities, named by the short label: Modulation, Volume, Pan, Bend range, LFO speed, Echo volume, Echo length, Pitch bend, Tempo. `(VOL)` / `(BPM)` are prompt chrome, not the name.
_Code_: `activeParameter`, `parameterLabels`, `activateParameter`, `parameterRow`
_Avoid_: parameter (speech), CC lane, Volume lane, Tempo lane, tab

**Automation Label** (also: **Automation Button**):
The exclusive clickable cell that activates an automation. Synonyms for the same cell, not two objects.
_Code_: `Controls.TabButton`, `automationParameterTabN`, `automationParameterTabs`
_Avoid_: tab, toggle, lane header

**Automation Lane**:
The one shared plot where nodes are drawn. Switching automations retargets this same lane. Never “the Volume lane”.
_Code_: QML plot, `laneBody`
_Avoid_: Volume lane, automation lanes (stacked), plot (speech)

**Label Gutter** (also: **Label Area**):
The left column of the automation drawer that holds the automation labels.
_Code_: automation band `gutterRect`
_Avoid_: gutter (bare — also the piano keyboard and Grid controls), header

**Automation Drawer**:
The whole surface: label gutter plus automation lane. Shown with A.
_Code_: `EditorDrawerPage::Automations`
_Avoid_: Automation Lanes

Do not rename the `parameter*` API. Search `parameterLabels` / `activeParameter` / `automationParameterTab`, not a repo-wide `automation` grep.

**Lane Scope**, **LaneHandle**, **NodeLane**, **CCLanes**, **TempoLane** are code. Do not use them in speech.

## Other drawers

**Velocity Drawer** (also: **Velocity Pane**):
The velocity page. Shown with V.
_Code_: `EditorDrawerPage::Velocity`
_Avoid_: velocity lane

**Voice-change Drawer** (also: **Voice-change Pane**):
The page of voice-change markers. Shown with P.
_Code_: `EditorDrawerPage::VoiceChanges`
_Avoid_: Voice Changes (speech for the page), voice change lane

**Voice Change**:
One per-track, non-node timeline event that switches the track's voice until the next change. Stored as `DOC_CC_VOICE`. Edited on the voice-change drawer — never as an automation.
_Avoid_: Voice Change lane, Voice row, program lane, voice node lane

## Other surfaces

**Song Tab**:
One open song in the central `QTabWidget`. This is the only spoken “tab”.
_Avoid_: calling an automation label a tab
