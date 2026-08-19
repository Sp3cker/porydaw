# Unbounded editor tracks and first-class tempo lane plan

## Summary

Separate three concepts that are currently collapsed into an integer named track: an Editor Track in the document, an Engine Slot in the 16-slot m4a playback projection, and the Tempo Lane in the conductor/seq stream. Phase 1 removes tempo’s -1 sentinel and establishes the final typed vocabulary while deliberately retaining the 16-editor-track limit. Later phases make document and UI track collections grow dynamically, centralize the mapping of at most 16 editor tracks to m4a slots, keep the audible in-game prefix driven by MusicPlayer::trackCount / SongDocument::trackBudget, and preserve extra tracks in the editable SMF while warning and omitting them from m4a-backed exports.

## Decision

1. **Tempo is a conductor/seq LaneTarget, never a track.** LaneTarget::tempo() has no EditorTrackId and no EngineSlot. It is stored as tempo meta events in SMF chunk 0 because mid2agb reads seq events from the first MTrk chunk (src/core/songdocument.h:17-24). The current ClipLane track = -1, RangeEdit LaneWrite engineTrack = -1, lane-scope pair {-1, DOC_CC_TEMPO}, and drawer conversion are removed (src/ui/songview.h:450-458; src/core/songdocument.h:191-218,262-263; src/ui/editordrawer/automationrows.cpp:215-231).

2. **Editor tracks have no porydaw product cap.** Store them in vectors and let the SMF format and available resources provide the real limits. The SMF header has a 16-bit MTrk count, so a saved file can contain at most 65,535 chunks including the conductor chunk; porydaw must reject an attempted overflow rather than wrap the current uint16_t cast (src/core/smf.cpp:289-296). Do not add a soft cap such as 256, and do not preserve a 32-track cap merely to keep uint32_t masks. SmfFile already owns a vector of tracks (src/core/smf.h:78-92).

3. **Engine playback remains exactly 16 slots.** EngineSlot is the typed 0-15 identifier. MidiTimeline, TimelinePlayer, AudioEngine, poryaaaa MAX_TRACKS, and activity telemetry remain fixed-size engine modules (src/core/miditimeline.h:17-23,74-90; src/core/timelineplayer.cpp:35-58; src/audio/trackactivitylevel.h:7-15; src/audio/audioengine.h:21-23). No editor code infers playability with editorIndex < 16; it asks PlaybackTrackMap.

4. **Default mapping is the first 16 editor tracks in editor order.** Reordering therefore deliberately changes the preview/export set. PlaybackTrackMap is the sole owner of EditorTrackId to optional EngineSlot and reverse mapping. Deleting that module should force the first-16 and player-budget rules to reappear in many callers; if deletion only removes pass-through code, the module is too shallow.

5. **The in-game audible set is data, not a guessed constant.** DecompProject::trackBudgetFor resolves MusicPlayer::trackCount and defaults to 16 only when the player/table is unknown (src/project/decompproject.h:25-33,72-78; src/project/decompproject.cpp:56-63). For a given song, an editor track is audible in-game only when it maps to an EngineSlot and that slot is below SongDocument::trackBudget. Never hardcode 10 or 12.

6. **Extra-track policy is preserve, disclose, and project.** Save/reopen and editor operations preserve every editor track. m4a preview, meters, and WAV/game export cannot render tracks without an EngineSlot. The UI marks those tracks as unavailable to m4a preview. Export presents the exact omitted count and, after acknowledgement, drops only unmapped tracks from a temporary export projection; it never deletes or rewrites them in the editor document. Tracks that are within the 16-slot projection but beyond the selected player budget remain in export and are separately marked silent in-game.

7. **The previous questionnaire’s EngineTrack = uint8_t 0-15 decision is superseded.** That representation is correct only for EngineSlot. Editing and LaneTarget APIs use EditorTrackId, whose range is the document’s dynamic track count. This plan retains the questionnaire’s no implicit integer conversion, optional absence, typed LaneTarget, and parse-once Qt-edge decisions, but not the assumption that an editable track is an engine slot (docs/enginetrack-lanetarget-questionnaire.md:25-73,107-160,183-204).

## Ubiquitous language

Propose these updates for CONTEXT.md only after product review; this plan does not edit it.

| Term | Canonical meaning | Avoid |
|---|---|---|
| Editor Track | One ordered, channel-bearing editable song track. It owns notes, voice changes, and track automation and maps to one SMF chunk. It may have no Engine Slot. | Engine track, MIDI channel, slot, MTrk |
| Primary Track | The active Editor Track. Note Selection is interpreted on it. It is optional only when the document has no Editor Tracks. | Selected slot, current engine track |
| Track Scope | The non-empty set of Editor Tracks selected through track headers; it contains Primary Track whenever one exists. | Track mask, engine mask |
| Engine Slot | One of the 16 m4a playback slots, identified by EngineSlot 0-15. It exists only in playback/export projection. | Editor track, MIDI channel |
| Player Budget | The number of Engine Slots the song’s MusicPlayer starts in-game, obtained from MusicPlayer::trackCount and exposed as trackBudget. Unknown means the 16-slot engine ceiling. | 10-track limit, 12-track limit, editor limit |
| Tempo Lane | The global tempo value stream in the conductor/seq chunk. Its identity is LaneTarget::tempo() and contains no track index. | Track -1, track 16, tempo track, tempo CC |
| Lane Target | A tagged identity: Tempo, Voice on an Editor Track, or Control Change on an Editor Track. | Pair of track and CC, negative track sentinel |
| SMF Chunk | One MTrk record in the file. Chunk 0 is also the conductor/seq chunk; chunks with no channel events are not Editor Tracks. | Editor track when discussing raw file structure |
| Playback Projection | The mapping from ordered Editor Tracks to at most 16 Engine Slots plus the Player Budget classification. | Track clipping, first-16 checks |
| Unmapped Track | An Editor Track with no Engine Slot. It remains editable and saved but is unavailable to m4a preview/export. | Dropped track, silent track |
| Silent-in-game Track | A mapped Editor Track whose Engine Slot is at or beyond Player Budget. It can be edited and exported but the selected game player does not start it. | Dropped track, unmapped track |

Continue using Note Selection, Time Selection, Lane Scope, Selection Projection, and Transient Selection Preview as defined in CONTEXT.md:15-36. Change only their references from engine track to Editor Track or Lane Target. In particular, Lane Scope becomes a collection of LaneTarget values rather than pairs.

## Module seams and ownership

### 1. Track identity seam

Add src/core/trackidentity.h. It owns EditorTrackId, EngineSlot, and LaneTarget: the vocabulary and invariants, not document storage or playback policy. Follow NoteId’s explicit wrapper/comparison pattern (src/core/noteid.h:7-19), but do not copy NoteId’s in-band zero-means-empty convention. Use std::optional for no Primary Track, deleted remap result, or no Engine Slot.

Qt signals and QVariant restoration may stay int. Convert once with EditorTrackId::fromInt, then validate membership against SongDocument. Audio/engine integers convert once with EngineSlot::fromInt. Invalid edge values are ignored or reported at that edge; typed internal functions do not repeat negative/range guards.

### 2. Editable document seam

SongDocument owns ordered Editor Tracks and the mapping EditorTrackId to SMF chunk/channel. Rename m_engineToSmf / m_engineChannel and all editing-oriented engineTrack names to editor equivalents; current storage and its fixed cap are at src/core/songdocument.h:114-117,491-493 and src/core/songdocument.cpp:402-413. TrackRemap becomes an editor-track remap. Its vector<int> with -1 = deleted may remain temporarily as the questionnaire permits, but tempo never enters that table.

SongDocument also owns tempo points as conductor/seq data. Its public lane interface accepts LaneTarget, resolves LaneTarget::tempo() to chunk 0 internally, and keeps DOC_CC_TEMPO private to the SMF adapter until it can be removed. Current public and mutation paths branch on the pseudo-CC at src/core/songdocument.cpp:681-684,1317-1344,1390-1413,1558-1561. The UI must not include DOC_CC_TEMPO after Phase 1.

### 3. Playback projection seam

Add src/core/playbacktrackmap.h and src/core/playbacktrackmap.cpp. PlaybackTrackMap owns:

- ordered assignment of the first 16 Editor Tracks to EngineSlot 0-15;
- reverse lookup from EngineSlot to EditorTrackId;
- classification as mapped, unmapped, or silent in-game using the supplied Player Budget;
- projection of editor mute/solo bytes to the 16-bit engine mask;
- counts used by import/export warnings.

MidiTimeline::build consumes this map rather than independently rebuilding first-16 logic. Today it builds smfToEngine, increments droppedTracks, and skips events after slot 15 (src/core/miditimeline.cpp:221-261). Import analysis and SongDocument currently duplicate the same mapping rule (src/core/midiimport.cpp:11-32; src/core/songdocument.cpp:402-413). These callers must use the seam, not reproduce index comparisons.

Keep TimelineEvent.track, TimelineTrack[16], TimelinePlayer’s arrays, AudioEngine’s atomic masks, and TrackActivityLevels fixed to EngineSlot. They are engine implementation details, not evidence for an editor limit (src/core/miditimeline.h:17-23,82-90; src/audio/audioengine.h:179-181,287-289; src/audio/trackactivitylevel.h:7-15).

### 4. Editor selection and mute seam

EditorSelectionModel owns Primary Track, Track Scope, Note Selection, and Time Selection in EditorTrackId/LaneTarget terms. Replace kTrackMask, uint32_t track scope, usedTrackMask arguments, bit shifts, and 0-15 guards with a sorted unique std::vector<EditorTrackId> or equivalent vector-backed set. Current constraints are concentrated at src/ui/songview/editorselectionmodel.h:48-58,72-84 and src/ui/songview/editorselectionmodel.cpp:15-52,137-168,286-307.

SongView continues to own editor mute/solo intent, but stores one byte per editor track in std::vector<uint8_t> mute and solo arrays. This is the recommended boring growable mask: clear indexing, no vector<bool> proxy semantics, and O(1) row queries. Resizes/remaps follow TrackRemap. SongView emits a semantic state-changed notification rather than exposing uint32_t editor masks. PlaybackTrackMap projects those bytes into the AudioEngine’s fixed 16-bit mask. Current unsafe shifts and 16-bit remap are at src/ui/songview.h:233-240,651-653 and src/ui/songview/trackvoiceops.cpp:82-130,381-415.

Solo projection rule: if any editor track is soloed, mapped soloed tracks are audible subject to mute and Player Budget; all other mapped slots are muted. Soloing only unmapped tracks produces silence, which is honest. An unmapped track cannot become audible by soloing it.

### 5. Drawer/view-state seam

Use LaneTarget as the one lane identity across EditorViewState, AutomationRows, AutomationLaneEdit, clipboard lanes, TimeSelection, SongDocument::TimeScope, and RangeEdit. Do not retain EditorAutomationRowId as a second tagged dialect. The drawer already has Tempo/Voice/ControlChange but currently stores its track in uint8_t, creates tempo with dummy track 0, then flattens tempo to {-1, DOC_CC_TEMPO} (src/ui/editorviewstate.h:13-28; src/ui/editordrawer/automationrows.cpp:15-28,215-231). EditorViewState::remapEngineTracks already preserves Tempo specially; convert it to remapEditorTracks over LaneTarget instead (src/ui/editorviewstate.cpp:36-78).

Track header construction must use SongDocument’s editor-track snapshot, not MidiTimeline::tracks[16]. It currently loops exactly 16 playable timeline rows (src/ui/songview/trackheaderpanel.cpp:89-113). This is the UI seam that makes unmapped tracks editable.

### 6. Export seam

Ordinary SongDocument::save remains lossless and writes the full SmfFile; today it directly calls SmfFile::writeFile (src/core/songdocument.cpp:378-390). Add an explicit export projection/preflight module adjacent to PlaybackTrackMap rather than changing the document before export. It returns a projected SmfFile or MidiTimeline plus an ExportExtras report containing total editor tracks, mapped count, omitted count, and player-silent count.

WAV export already consumes a MidiTimeline and a private M4AEngine (src/audio/wavexport.h:20-50; src/audio/wavexport.cpp:48-75), so its caller must display the extras report before writing. The game/mid2agb export path uses the same projected first-16 SMF. Acknowledge-and-export drops unmapped channel chunks only in that temporary projection and preserves conductor/seq events and non-channel metadata according to the existing chunk-0 rules.

## Type sketch

The final names and signatures should remain this small. The sketch shows intent, not an instruction to expose storage fields.

~~~cpp
// src/core/trackidentity.h
class EditorTrackId final
{
  public:
    static std::optional<EditorTrackId> fromInt(int value) noexcept;
    static consteval EditorTrackId literal(std::size_t value);

    constexpr std::size_t index() const noexcept;
    friend constexpr auto operator<=>(EditorTrackId, EditorTrackId) = default;

  private:
    explicit constexpr EditorTrackId(std::size_t value) noexcept;
    std::size_t m_value;
};

class EngineSlot final
{
  public:
    static constexpr std::size_t kCount = 16;
    static std::optional<EngineSlot> fromInt(int value) noexcept;
    static consteval EngineSlot literal(uint8_t value); // compile error for value >= kCount

    constexpr uint8_t index() const noexcept;
    friend constexpr auto operator<=>(EngineSlot, EngineSlot) = default;

  private:
    explicit constexpr EngineSlot(uint8_t value) noexcept;
    uint8_t m_value;
};

class LaneTarget final
{
  public:
    enum class Kind : uint8_t { Tempo, Voice, ControlChange };

    static constexpr LaneTarget tempo() noexcept;
    static constexpr LaneTarget voice(EditorTrackId track) noexcept;
    static constexpr LaneTarget controlChange(EditorTrackId track, uint8_t cc) noexcept;

    constexpr Kind kind() const noexcept;
    constexpr bool isTempo() const noexcept;
    constexpr std::optional<EditorTrackId> editorTrack() const noexcept;
    constexpr std::optional<uint8_t> controller() const noexcept;
    friend constexpr auto operator<=>(const LaneTarget &, const LaneTarget &) = default;
};

// src/core/playbacktrackmap.h
class PlaybackTrackMap final
{
  public:
    static PlaybackTrackMap build(std::size_t editorTrackCount, int playerBudget);

    std::optional<EngineSlot> engineSlot(EditorTrackId) const noexcept;
    std::optional<EditorTrackId> editorTrack(EngineSlot) const noexcept;
    bool audibleInGame(EditorTrackId) const noexcept;
    std::size_t unmappedCount() const noexcept;
    uint16_t projectMuteSolo(std::span<const uint8_t> muted,
                             std::span<const uint8_t> soloed) const noexcept;
};
~~~

EditorTrackId::fromInt only rejects negative/unrepresentable input; SongDocument validates that the ID exists in that document. No default constructors create fake track 0. LaneTarget::tempo is the only target with no EditorTrackId. Voice has no dummy controller, and Tempo has neither a dummy track nor DOC_CC_TEMPO in its interface.

## Extras policy

| Surface | Tracks mapped to Engine Slots | Editor tracks beyond slot 15 |
|---|---|---|
| Edit/save/reopen | All are editable and serialized. Player Budget does not gate editing. | Kept losslessly. No destructive warning on ordinary Save; the header/status indicates export limitations. |
| Editor playback | First 16 in editor order. Slots at or beyond Player Budget are forcibly muted as today. | No m4a playback. Header says unavailable in m4a preview; transport does not claim they sound. |
| Activity meter | Reverse-map engine telemetry to its EditorTrackId. Player-silent rows retain the existing receded treatment. | No meter animation; show the unavailable state rather than a fake active meter. Engine activity remains a 16-element array. |
| Mute/solo | Editor state exists for every track and follows reorder/delete/undo. Playback receives a projected 16-bit mask. | State is retained. Soloing only extras yields silence; moving an extra into the first 16 applies its retained state. |
| External MIDI import | Every channel-bearing MTrk becomes an Editor Track; conductor/non-channel chunks remain preserved metadata. | Kept. Replace droppedTracks wording with kept-but-unavailable preview/export wording. |
| Player-budget warning | Count tracks at or beyond the selected MusicPlayer::trackCount, using default 16 only when unknown. | They are also silent in-game, but do not conflate this with the 16-slot export omission. |
| WAV export | Render the mapped first 16 through m4a, still applying Player Budget. | Warn with exact omitted count before export; omit from the render. |
| Game/mid2agb export | Export a temporary projection of the first 16 Editor Tracks plus conductor/seq data. Do not drop mapped tracks merely because current Player Budget is smaller. | Warn with exact omitted count and require acknowledgement; omit only from the temporary export. Never mutate the document. |

Recommended warning copy: “This song has N editor tracks. The m4a engine can preview and export the first 16; export will omit M tracks. The omitted tracks stay in the editor and in the saved MIDI file.” Keep the existing separate player-specific message for slots at or beyond trackBudget; its current source already names the selected player and count (src/core/midiimport.cpp:119-130; src/checks/onboardcheck/import.cpp:50-64).

The existing header treatment for Player Budget is reusable but must remain semantically distinct: TrackHeaderRow calls a track silent in-game when its index is at or beyond SongDocument::trackBudget and explains the music_player_table allocation (src/ui/songview/trackheaderrow.cpp:145-150,188-200,232-234,284-291). Add a different label/icon/tooltip for Unmapped Track.

## Changes

### Core files

- **New src/core/trackidentity.h:** define EditorTrackId, EngineSlot, LaneTarget, comparisons, consteval literals, and optional parsing. Keep it header-only only if the implementation remains small.
- **New src/core/playbacktrackmap.h / .cpp:** implement the sole first-16, reverse-map, Player Budget, classification, and mask-projection rules.
- **src/core/songdocument.h / .cpp:** rename editor-facing engine-track vocabulary; use typed IDs; rename mapping members; make the editor-to-SMF map dynamic; use LaneTarget for lane reads/writes/moves and RangeEdit; make TrackRemap editor-oriented; replace canAddTrack’s 16 check. Preserve chunk-0 conductor behavior. Current cap and channel allocation are at src/core/songdocument.cpp:402-413,1861-1889.
- **src/core/songdocument_time.cpp:** replace LaneIdentity {int, cc}, m_tempoLaneScope, and DOC_CC_TEMPO checks with LaneTarget. Current sentinel conversion is at src/core/songdocument_time.cpp:23-25,55-60,142-183.
- **src/core/midiimport.h / .cpp:** analyze all channel-bearing chunks; rename mappedTracks/droppedTracks to editorTracks/unmappedForPlayback (or equally explicit names); keep all ImportTrackInfo records; generate separate m4a-unmapped and Player Budget warnings. Current truncation and warning are at src/core/midiimport.h:31-43 and src/core/midiimport.cpp:11-32,113-130.
- **src/core/miditimeline.h / .cpp:** retain fixed EngineSlot storage; consume PlaybackTrackMap; replace droppedTracks with an extras report that says unmapped rather than lost; carry reverse mapping for UI/activity. Current independent map is at src/core/miditimeline.cpp:221-261.
- **src/core/smf.h / .cpp:** retain vector storage; validate tracks.size() <= 65,535 before writing the 16-bit header instead of narrowing silently (src/core/smf.cpp:289-296).
- **src/core/noteid.h:** no behavior change; use only as the explicit typed-ID style reference (src/core/noteid.h:7-19).

### Project/audio files

- **src/project/decompproject.h / .cpp:** no new limit; retain MusicPlayer::trackCount and unknown-player fallback 16. Consider a typed Player Budget only if it reduces conversions without widening interfaces (src/project/decompproject.h:25-33,72-78; src/project/decompproject.cpp:56-63).
- **src/audio/audioengine.h / .cpp:** keep fixed engine masks/atomics and trackBudgetMuteMask. Accept only projected engine masks; never accept editor masks. Existing final mask combines mute, solo, and budget and clamps to 16 bits (src/audio/audioengine.cpp:511-516).
- **src/audio/trackactivitylevel.h:** no size change; its 16 entries are EngineSlot telemetry (src/audio/trackactivitylevel.h:7-15).
- **src/audio/wavexport.h / .cpp and its caller:** accept/display ExportExtras before rendering. Rendering remains m4a and therefore 16-slot.

### UI files

- **src/ui/editorviewstate.h / .cpp:** key lane heights/ranges/empty/hidden lanes by LaneTarget; rename remapEngineTracks to remapEditorTracks and preserve LaneTarget::tempo without special numeric values (src/ui/editorviewstate.h:13-28,55-74; src/ui/editorviewstate.cpp:36-78).
- **src/ui/songview/editorselectionmodel.h / .cpp:** use EditorTrackId, optional Primary Track, vector-backed Track Scope, and vector<LaneTarget> Lane Scope; remove kTrackMask and all 16/bit-shift logic (src/ui/songview/editorselectionmodel.h:15-25,48-58,72-84; src/ui/songview/editorselectionmodel.cpp:15-52,137-168,286-307).
- **src/ui/songview.h / songview.cpp:** type clipboard tracks/lanes, replace editor mute/solo integers with byte vectors, and stop exposing uint32_t editor masks (src/ui/songview.h:233-240,450-463,528-531,651-653; src/ui/songview.cpp:204-208).
- **src/ui/songview/rangeedit.cpp:** use LaneTarget so copy/paste retargets only track-owned lanes and always leaves Tempo global; remove every negative-track branch (src/ui/songview/rangeedit.cpp:103-105,145-149,252-255,353-366).
- **src/ui/songview/trackvoiceops.cpp:** type editing operations, remap vectors dynamically, retain editor mute/solo state, and project it through PlaybackTrackMap. Remove 0-15 guards from editor operations; current assumptions are at src/ui/songview/trackvoiceops.cpp:48-70,82-130,250-358,381-430.
- **src/ui/songview/trackheaderpanel.cpp / trackheaderrow.cpp:** build rows from the document’s Editor Tracks, support dynamic counts/scrolling, use semantic mute/solo notifications, and display separate unmapped versus silent-in-game states. Current panel construction and bit bindings are at src/ui/songview/trackheaderpanel.cpp:89-113 and src/ui/songview/trackheaderrow.cpp:90-110.
- **src/ui/songview/viewstate.cpp:** replace uint8_t track storage and 0-15 guards with LaneTarget (src/ui/songview/viewstate.cpp:207-228).
- **src/ui/editordrawer/automationrows.h / .cpp, automationlaneedit.h, automationgesture.h, automationarea.cpp, automationhover.cpp:** pass LaneTarget end to end. Tempo remains the first row but never gets a dummy primary track (src/ui/editordrawer/automationrows.cpp:15-28,60-66,215-231; src/ui/editordrawer/automationlaneedit.h:10-18; src/ui/editordrawer/automationgesture.h:43-51).
- **src/ui/activity/trackactivity.h / .cpp:** keep engine-slot intensities fixed, but query through PlaybackTrackMap/reverse mapping at the SongView edge. Current direct int indexing is at src/ui/activity/trackactivity.cpp:84-88.

## Sequence and phased work

Each phase is a separately reviewable change with no long-lived old/new dialect inside its completed scope. Agents listed below are implementation roles, not additional product phases.

### Phase 1 — First-class tempo and final identifiers; editor remains capped at 16

**Explorer agent**

- Enumerate every parameter/field whose meaning is Editor Track, Engine Slot, or Lane Target in the scoped core/audio/UI paths.
- Classify negative values: tempo sentinel (must be removed now), deleted/lookup return (may remain per questionnaire pile 3), or invalid Qt input (parse at edge).
- Produce a call-site checklist before edits, including RangeEdit, TimeScope, clipboard, drawer row identity, EditorViewState, activity/audition, and Qt signals.

**Task agent: core identity and document**

- Add trackidentity.h with final EditorTrackId, EngineSlot, and LaneTarget. Do not introduce a temporary uint8_t EngineTrack type.
- Convert SongDocument editing parameters to EditorTrackId and lane parameters to LaneTarget. Keep the existing rebuildTrackMap cap and canAddTrack limit in this phase, so no 17th Editor Track can be created or imported.
- Convert RangeEdit::LaneWrite, LanePointMove, TimeScope, and SongDocument::TimeEditor to LaneTarget. Keep remap-table -1 only for deleted mappings.
- Route LaneTarget::tempo internally to chunk 0; keep chunk-0 rescue on delete/reorder.

**Task agent: selection/drawer/UI**

- Replace ClipLane, TimeSelection::lanes, EditorAutomationRowId, AutomationRows rowTarget/rowIdentity, AutomationLaneEdit::Target, and gesture target fields with LaneTarget.
- Parse Qt int edges once; delete dead negative checks after typed conversion.
- Keep editor collection/mute masks bounded in this phase, but ensure Tempo never occupies a mask bit or remap entry.

**Reviewer agent**

- Reject any remaining UI/core editor encoding of tempo as -1, EditorTrackId{16} used as tempo, DOC_CC_TEMPO outside the SMF adapter, or an implicit int conversion.
- Confirm no path can retarget tempo to Primary Track during single-track paste or remap it during track deletion.
- Confirm add/import/header behavior still stops at 16 in this phase.

**Observable end state:** tempo copy, paste, nudge, duplicate-time, ripple, drawer selection, track reorder, delete, undo, and redo all use LaneTarget::tempo with no sentinel. Existing songs remain limited to 16 Editor Tracks and beyond-16 imports still use the old warning until the later unlock phase. This is intentionally not the unbounded-track release.

### Phase 2 — Dynamic document storage and centralized playback projection; UI unlock remains off

**Explorer agent**

- Trace every independent first-16 calculation in SongDocument, MidiTimeline, import analysis, AudioEngine handoff, and activity. Define one PlaybackTrackMap contract and enumerate callers that must stop comparing editor indices with 16.
- Inspect add/duplicate channel assignment and confirm that separate MTrk chunks remain separate mid2agb tracks even when they reuse a MIDI channel.

**Task agent: document model**

- Rename engine-to-SMF storage to editor-to-SMF and lift the cap in rebuildTrackMap.
- Change canAddTrack to check only serializability/resources, not 16 free channels. For a new track after all MIDI channels have owners, choose the least-used MIDI channel, ties to the lowest channel. Duplicate preserves the source channel. Each chunk remains internally single-channel.
- Make add/duplicate/delete/move/remap and view-state remap work over arbitrary vector lengths. Add the explicit 65,535-chunk save preflight.

**Task agent: projection**

- Implement PlaybackTrackMap and make MidiTimeline consume it. Keep MidiTimeline and TimelinePlayer arrays at 16.
- Preserve the first-16-in-editor-order behavior for existing songs and Player Budget masking. Expose reverse mapping and extras counts.
- Do not yet enable UI creation/import of a 17th track; use synthetic document fixtures to prove the model and projection before the visible unlock.

**Reviewer agent**

- Search for duplicate first-16 checks outside EngineSlot implementation and low-level engine loops.
- Verify all fixed arrays are genuinely EngineSlot arrays, while all editable collections are vectors.
- Verify no narrowing of EditorTrackId into uint8_t in document/UI state.

**Observable end state:** a synthetic document with more than 16 channel-bearing chunks round-trips all tracks, document operations/remaps address them, and PlaybackTrackMap deterministically exposes only the first 16 as EngineSlots. Existing user-facing add/import behavior remains capped until Phase 3, avoiding a half-editable UI.

### Phase 3 — Unlock unbounded editor UI and import; honest preview/meter behavior

**Explorer agent**

- Trace all UI row construction, selection scope, mute/solo, clipboard, cosmetics, restore, and activity lookups that still consume MidiTimeline::tracks or uint32_t masks.
- Identify any layout assumptions that require row virtualization or scroll-area changes for hundreds of tracks; do not add a product cap to avoid UI work.

**Task agent: import and document UI**

- Make import retain every channel-bearing chunk and return all ImportTrackInfo entries. Replace “Porydaw will not import” with kept/unmapped wording.
- Build track headers and editing surfaces from SongDocument editor tracks, not the 16-slot timeline array. Enable add/duplicate beyond 16.
- Show separate status for Unmapped Track and Silent-in-game Track. Preserve all imported extras on Save/reopen.

**Task agent: dynamic editor state and playback bridge**

- Replace EditorSelectionModel masks with vector-backed EditorTrackId sets and SongView mute/solo masks with vector<uint8_t>.
- Remap Primary Track, Track Scope, lane cosmetics, clipboard, mute, and solo across arbitrary insert/delete/reorder/undo/redo operations.
- Project mute/solo through PlaybackTrackMap, reverse-map activity meters, and implement honest unmapped-track solo behavior.
- Keep Player Budget sourced from SongDocument/DecompProject. Never use 10 or 12 in UI or tests except as arbitrary test inputs to the generic budget function.

**Reviewer agent**

- Exercise track 16, 17, 31, 32, and a much larger index to catch bit shifts, uint8_t narrowing, and 32-track assumptions.
- Verify track reorder across the 15/16 seam transfers which tracks are previewable without losing mute/solo, selection, clipboard, or drawer state.
- Verify unknown player budget defaults to 16 and a known budget B marks slots B through 15 silent-in-game.

**Observable end state:** a user can import or add a 17th and later Editor Track, edit it, select it, mute/solo it, reorder/delete/undo it, and save/reopen it. Only the first 16 preview through m4a; extra rows clearly say they are unavailable in m4a preview and show no false activity. The selected MusicPlayer budget, not a hardcoded guess, determines the in-game audible prefix.

### Phase 4 — Export projection and warnings

**Explorer agent**

- Trace every WAV and game/mid2agb export entry point and record where user acknowledgement can occur before file creation. Confirm the canonical SongDocument save path remains separate from temporary export artifacts.

**Task agent: shared export preflight**

- Add ExportExtras/report generation beside PlaybackTrackMap and a temporary SMF projection that preserves conductor/seq data while excluding unmapped channel chunks.
- Keep ordinary Save lossless. Make WAV and game export show the exact total/mapped/omitted/player-silent counts and require acknowledgement when omittedCount > 0.
- Apply Player Budget to m4a rendering but do not drop mapped budget-silent tracks from game export.

**Reviewer agent**

- Compare the document before/after accepted and cancelled exports byte-for-byte or structurally to prove export does not mutate it.
- Confirm tempo/time signatures/loop markers survive export even when chunk 0 also owns a channel track or the first Editor Track was reordered.
- Confirm cancellation writes no partial output and warning counts are derived from PlaybackTrackMap.

**Observable end state:** ordinary Save preserves every Editor Track. WAV/game export warns once with exact counts, then exports only the first 16 editor tracks through the m4a-compatible projection after acknowledgement. Cancelling leaves both document and destination unchanged; accepting never deletes extras from the editor.

## Edge cases and error conditions

1. **Zero Editor Tracks:** Primary Track is std::optional<EditorTrackId>; Track Scope can be empty only in that state. Tempo remains editable because it does not require a Primary Track. Do not invent EditorTrackId zero as an empty value.
2. **Exactly 16 versus 17:** track 15 maps to EngineSlot 15; track 16 is the first unmapped track. Test both sides of the seam without shifts by 32 or narrowing.
3. **Player Budget 0, B, 16, unknown:** zero mutes all mapped slots; B mutes mapped slots B through 15; 16 mutes none for budget; unknown resolves to 16 (src/audio/audioengine.h:40-47; src/project/decompproject.cpp:56-63).
4. **Solo only on unmapped tracks:** output is silent. Solo on mapped plus unmapped tracks plays only mapped solo tracks subject to mute/budget.
5. **Reorder across slot 15/16:** projection changes immediately; retained editor mute/solo and activity ownership follow EditorTrackId remap. Stale engine activity must not appear on the new editor owner after rebuild.
6. **Delete/reorder chunk 0:** tempo, time signatures, and loop markers remain in the first MTrk as current document contracts require (src/core/songdocument.h:346-363). LaneTarget::tempo never enters TrackRemap.
7. **Conductor-only/name-only chunks:** preserve them in SmfFile but do not count them as Editor Tracks or consume EngineSlots. Current mapping detects channel-bearing chunks (src/core/midiimport.cpp:16-31; src/core/miditimeline.h:65-72).
8. **Shared MIDI channels after 16 tracks:** separate chunks remain separate Editor Tracks. New-track assignment is least-used channel; duplicate keeps source channel. Note pairing remains per chunk/channel and the existing 16 x 256 key table is a MIDI-channel/key table, not an editor-track cap.
9. **SMF limit:** refuse a mutation/import/save that would exceed 65,535 total chunks with a clear error. Never wrap tracks.size() through uint16_t (src/core/smf.cpp:289-296).
10. **Large documents:** vector growth failures/import resource exhaustion report failure without partial mutation. Header construction must remain scrollable; optimize/virtualize based on measurement, not by imposing a 256-track policy.
11. **Foreign metadata and mixed chunks:** import/export projection preserves non-channel events, end ticks, Channel Prefix behavior, and conductor globals. Dropping an unmapped track from an export projection must not drop a winning loop marker or other seq event that needs rescue.
12. **Tempo paste/remap:** a single-track clip can retarget Voice/CC lanes to Primary Track, but Tempo remains global. Deleted track remaps remove its Voice/CC targets and leave Tempo untouched.
13. **Qt int edges:** negative, out-of-document, and overflowed values fail conversion once. Internal typed functions do not turn invalid values into track 0.
14. **Player change after import:** recompute silent-in-game classifications and warnings from the selected MusicPlayer budget without changing editor track count or EngineSlot assignment.
15. **Save versus export:** Save is lossless and should not ask permission to discard data because it discards none. Only m4a-backed export asks to omit extras. Never overwrite the canonical .mid with the temporary first-16 projection.

## Risks and non-goals

### Risks

- Track identity currently means mutable ordinal. Insert/delete/reorder remaps touch selection, clipboard, mute/solo, drawer cosmetics, restore state, and activity at once; incomplete remap is the largest data-association risk (src/ui/songview/trackvoiceops.cpp:381-440).
- SongDocument, MidiTimeline, and import analysis currently derive parallel first-16 maps. A partial migration creates disagreement about which editor track owns an EngineSlot (src/core/songdocument.cpp:402-413; src/core/miditimeline.cpp:221-261; src/core/midiimport.cpp:11-32).
- Tempo has both a tagged drawer kind and flattened negative identity today. Leaving either dialect creates paste/delete bugs (src/ui/editorviewstate.h:13-28; src/ui/editordrawer/automationrows.cpp:215-231).
- UI performance for thousands of headers is unknown. The correct response is measurement and row virtualization, not a product cap.
- Exporting a temporary reduced SMF must preserve seq globals and chunk order. Reusing destructive document operations for projection would risk data loss.

### Non-goals

- A second synth or non-m4a preview engine for tracks 16 and above.
- Changing poryaaaa MAX_TRACKS, MidiTimeline’s 16 EngineSlots, or GBA engine behavior.
- Making Player Budget an editor-track limit or assuming it is 10 or 12.
- Splitting one song into multiple game songs during export.
- Keeping uint32_t editor masks, adding a 32-track cap, or using std::vector<bool>.
- Replacing every pile-3 -1 lookup/deletion sentinel in Phase 1. Remap tables, smfTrackFor, previewTrack, firstProgram, and freeChannel may migrate later where they represent absence, but tempo cannot use them.
- Editing CONTEXT.md before the language is accepted.
- Changing SMF format support beyond the existing format-0-to-format-1 normalization.

## Recommended defaults for remaining product choices

No product question must block implementation if these defaults are accepted:

- **Limitless policy:** no porydaw soft cap; vector-backed Editor Tracks, with the SMF 65,535-chunk serialization limit and clear resource errors.
- **Playable subset:** first 16 Editor Tracks in current editor order. Reordering is the explicit way to choose a different preview/export subset.
- **Channel for track 17+:** least-used MIDI channel, lowest channel on ties; duplicate retains the source channel.
- **Editor mute/solo storage:** std::vector<uint8_t>, one byte per track per flag; Track Scope is a sorted unique vector of EditorTrackId.
- **Unmapped solo:** silence unless at least one mapped track is also soloed.
- **Save policy:** always preserve all editor tracks.
- **Export policy:** warn with exact counts and omit unmapped tracks from a temporary projection after acknowledgement; never mutate the document.
- **Player-silent export tracks:** keep them in game export and warn separately because changing MusicPlayer::trackCount can make them audible later.
- **UI wording:** “unavailable in m4a preview/export” for no EngineSlot; “silent in-game” for beyond Player Budget. Never call retained tracks dropped.

## Verification

Do not run project-wide suites. Extend and run the existing focused harnesses by phase.

### Phase 1 verification

- **Range-edit tempo paste/nudge/ripple:** extend src/checks/editcheck.cpp around the existing tempo duplicate, RangeEdit tempo write, whole-song ripple, and track reorder cases (src/checks/editcheck.cpp:1111-1126,1391-1407,1419-1422,1960-1964,2131-2139). Run the configured executable with --editcheck <scratch>. Assert LaneTarget::tempo survives copy/paste, never retargets, and undo/redo is one command.
- **Lane/track selection:** update src/checks/selectioncheck.cpp time-scope and remap cases (src/checks/selectioncheck.cpp:190-245,335-422). Run --selectioncheck. Assert explicit Tempo Lane coverage without {-1, DOC_CC_TEMPO}, plus track-delete remap/dedup.
- **Drawer identity:** update src/checks/rollcheckautomation.cpp tempo-first and automation time-selection cases (src/checks/rollcheckautomation.cpp:477-488,1080-1178,1255-1369). Run --check-automation <scratch> mus_route101. Assert tempo row carries LaneTarget::tempo and requires no Primary Track.
- **Whole SongView remap:** update src/checks/rollcheck.cpp track owner/remap fixtures (src/checks/rollcheck.cpp:506-535,633-691,765-810). Run --rollcheck <scratch> mus_route101. Assert tempo is untouched by delete/reorder while track-owned clipboard/cosmetic state remaps.

### Phase 2 verification

- Add a synthetic >16-track fixture to the existing edit/import-oriented harness rather than a new broad harness. Assert document editorTrackCount is the full count, save/reload preserves each chunk/event/end tick, add/duplicate/delete/reorder work beyond 16, and only 16 EngineSlots exist.
- Add PlaybackTrackMap boundary cases for 0, 1, 15, 16, 17, 32, and a large count. Assert forward/reverse bijection for mapped tracks, exact unmapped counts, Player Budget classifications, and dynamic flag projection.
- Re-run --editcheck <scratch> and --polycheck. The latter already verifies generic trackBudgetMuteMask behavior and engine rendering at src/checks/polycheck.cpp:309-342.

### Phase 3 verification

- **Import wizard warnings:** extend src/checks/onboardcheck/import.cpp around analysis and role-aware budget warnings (src/checks/onboardcheck/import.cpp:23-64,135-178). Run --onboardcheck <scratch> <mid2agb>. Import a >16-channel-chunk fixture; assert every track is in the document, warning says kept/unmapped rather than not imported, and changing player updates the separate budget warning.
- **Mute/solo and delete remap:** extend src/checks/rollcheck.cpp existing remap matrix (src/checks/rollcheck.cpp:633-691,765-810) with indices across 15/16 and 31/32. Assert byte-vector state follows reorder/delete/undo/redo and unmapped-only solo projects to all-silent engine output.
- **Selection:** extend src/checks/selectioncheck.cpp with Primary Track and Track Scope above 31, lane targets on extra tracks, deletion fallback, and tempo preservation (src/checks/selectioncheck.cpp:190-245,335-422).
- **Activity:** extend src/checks/trackactivitycheck.cpp existing invalid/boundary and isolated-slot checks (src/checks/trackactivitycheck.cpp:34-52). Run --trackactivitycheck. Assert reverse-mapped EngineSlot activity lights only its mapped Editor Track and unmapped rows stay unavailable/dark.
- **UI smoke:** launch the real editor with a >16-track fixture; add track 17, edit notes and automation, reorder it into slot 0, play, mute/solo, delete/undo, save/reopen, and observe both unmapped and player-silent header states.

### Phase 4 verification

- Add focused export cases beside the existing WAV harness: 16 tracks produces no extras prompt; 17+ reports exact counts; cancel leaves no output; accept renders only mapped tracks; document SmfFile is structurally unchanged; Tempo/time signatures/loop markers remain.
- Run the existing WAV-focused harness command discovered by the implementer plus --polycheck for budget masking. Do not claim tracks 16+ were rendered; prove they were omitted and disclosed.
- Export a known >16 fixture, then reopen the canonical .mid and confirm all editor tracks remain. Inspect the temporary/exported projection and confirm at most 16 channel-bearing chunks plus preserved conductor metadata.

## Critical files

The implementer must read these before changing code:

1. src/core/songdocument.h:17-24,35-46,88-124,180-218,252-280,334-363,400-493 — tempo encoding, editing interface, remap, track lifecycle, and fixed mapping storage.
2. src/core/songdocument.cpp:378-475,665-705,1290-1430,1540-1570,1840-1995 — save, map construction, tempo routing, range writes, channel allocation, add/duplicate/delete.
3. src/core/songdocument_time.cpp:1-70,130-190 — lane scope and tempo sentinel in time editing.
4. src/core/smf.h:40-120 and src/core/smf.cpp:289-329 — vector-backed tracks and 16-bit serialization field.
5. src/core/miditimeline.h:13-90 and src/core/miditimeline.cpp:221-273 — fixed EngineSlot timeline and current first-16 projection.
6. src/core/midiimport.h:26-50 and src/core/midiimport.cpp:11-32,35-135 — current truncating import analysis and warning copy.
7. src/project/decompproject.h:25-33,72-78 and src/project/decompproject.cpp:56-63 — authoritative per-song Player Budget and default 16.
8. src/audio/audioengine.h:21-47,179-181,287-289 and src/audio/audioengine.cpp:511-516 — engine ceiling and final fixed mask.
9. src/ui/songview/editorselectionmodel.h:15-84 and .cpp:15-52,137-180,286-315 — uint32_t selection ceiling and remap behavior.
10. src/ui/songview.h:233-240,450-463,528-531,651-653 and src/ui/songview/trackvoiceops.cpp:82-130,381-440 — editor masks, clipboard sentinel, and remap matrix.
11. src/ui/editordrawer/automationrows.cpp:15-28,60-66,215-231 and src/ui/editorviewstate.h:13-28,55-74 — tagged tempo flattened to a negative pair and uint8_t track storage.
12. src/ui/songview/trackheaderpanel.cpp:89-113 and src/ui/songview/trackheaderrow.cpp:145-150,188-200,232-234,284-291 — timeline-driven 16-row construction and existing Player Budget UX.
13. src/checks/editcheck.cpp, src/checks/selectioncheck.cpp, src/checks/rollcheck.cpp, src/checks/onboardcheck/import.cpp, src/checks/rollcheckautomation.cpp, src/checks/polycheck.cpp, and src/checks/trackactivitycheck.cpp at the ranges listed in Verification — existing contracts to extend rather than replace.
