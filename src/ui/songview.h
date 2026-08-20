#pragma once

#include <QColor>
#include <QHash>
#include <QList>
#include <QRectF>
#include <QSet>
#include <QWidget>
#include <cstdint>
#include <functional>
#include <optional>
#include <span>
#include <utility>
#include <vector>

#include "audio/trackactivitylevel.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "porydaw_scale.h"
#include "ui/activity/trackactivity.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/pitchprojection.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/pitchenvelopecoordination.h"
#include "ui/songviewmodel.h"
#include "ui/timelinesurface.h"
#include "ui/velocitygesturemodel.h"

extern "C" {
#include "voicegroup_loader.h"
}

class EventListView;
class QKeyEvent;
class QEvent;
class QHBoxLayout;
class QScrollArea;
class QScrollBar;
class QSpacerItem;
class QStackedWidget;
class QWheelEvent;
class QPainter;
class SongDocument;
class AutomationPage;
class EditorDrawer;
class VelocityArea;
struct DocNote;
struct NoteVelocity;
struct TrackRemap;

namespace songview {
class TimeRuler;
class EditorSelectionModel;
class PianoRoll;
class OtherStrip;
class PlayheadOverlay;
class TrackHeaderPanel;
class TrackHeaderRow;

class PitchEnvelopeHost;
// Perceptually mixes a color toward its backdrop. Timeline surfaces use this
// shared shade for receding track-colored details.
QColor mixTowardOklab(const QColor &color, const QColor &backdrop, double t);

// Note-name labels: with the View toggle on, each active-track note carries
// its pitch name unless the velocity shortcut is held. The label face is
// fixed, and it hides — never shrinks — whenever its padded height misses
// the row; this floor is only a cheap pre-gate that no padded face ever
// fits under.
constexpr int kNoteNameMinKeyH = 12;
// The velocity bar's rect inside a note rect; painted by the roll and,
// from the resolved velocity-handle threshold up, the grab target for velocity drags. Exposed
// for roll interaction checks. The default DPR keeps integer-DIP callers
// compatible while the roll supplies its actual display scale.
QRectF velBarRect(const QRectF &noteRect, int velocity, qreal dpr = layout::singlePixel());
// Frame weights for note borders and the selection ring, in physical
// pixels for the given display ratio. The resolver scales their DIP widths
// with the editor font; painting still lands on whole physical pixels so
// fractional scale factors cannot open seams. Exposed so roll checks assert
// the same math the paint code uses.
int noteBorderPixels(qreal dpr);
int selectionRingPixels(qreal dpr);
} // namespace songview

// Song view: time ruler, multi-track piano roll (selected track in full
// color, others ghosted), per-track automation lanes with m4a names, an
// "other events" strip, and track headers with instrument names from the
// loaded voicegroup. Read-only over a MidiTimeline (M1); when a SongDocument
// is attached (M2) the selected track is editable: note draw/move/resize/
// velocity/delete in the roll, point editing in the lanes, loop-marker
// dragging in the ruler. The MidiTimeline and LoadedVoiceGroup must outlive
// the view or be cleared with setSong(nullptr, nullptr) first.
class SongView : public QWidget
{
    Q_OBJECT

  public:
    explicit SongView(QWidget *parent = nullptr);

    void setSong(const MidiTimeline *timeline, const LoadedVoiceGroup *voicegroup);
    // Timeline swap after a document edit: keeps zoom, scroll, track
    // selection, mute/solo, and re-resolves the note selection.
    void updateSong(const MidiTimeline *timeline);
    void setPlayheadSample(uint64_t samplePos, bool playing);
    bool advanceTrackActivity(const TrackActivityLevels &levels, float elapsedSeconds,
                              bool playing);

    // Editing is enabled while a document is attached (may be null).
    void setDocument(SongDocument *document);
    SongDocument *document() const { return m_document; }

    // Voicegroup swap after a -G settings change (labels only; may be null
    // while the audio engine frees the old one).
    void setVoicegroup(const LoadedVoiceGroup *voicegroup);

    // Detached camera/grid sidecar snapshot. Drawer chrome is application-wide;
    // automation-lane cosmetics live in EditorViewState.
    struct ViewState {
        ViewState();
        bool valid = false;
        double pxPerBeat = 0.0;
        double keyHeight = 0.0;
        double scrollPx = 0.0;
        double scrollY = 0.0;
        int selectedTrack = 0;
        uint64_t editCursorTick = 0;
        int gridMinDenom = 0;     // drawn-grid floor as a note denominator
                                  // (4/8/16/32); 0 = down to the clock grid
        bool gridTriplet = false; // triplet vs straight beat subdivisions
        bool eventList = false;   // raw MIDI event list instead of the roll
    };
    ViewState viewState() const;
    // Call after setSong (and setDocument); a default-constructed (invalid)
    // state is a no-op.
    void applyViewState(const ViewState &state);

    // Detached typed automation-lane snapshot. Runtime selection, camera,
    // document, timeline, and voice state deliberately remain live in SongView.
    EditorViewState editorViewState() const;
    void applyEditorViewState(const EditorViewState &state);
    // Applies application-wide drawer chrome while preserving this song's lane state.
    void applyEditorDrawerState(const EditorDrawerState &state);
    // One-way sink used by drawer and page caches when their cosmetic state changes.
    void setEditorViewState(const EditorViewState &state);

    void toggleDrawerSection(EditorDrawerPage page);
    void setDrawerSectionVisible(EditorDrawerPage page, bool visible);
    bool drawerSectionVisible(EditorDrawerPage page) const;
    void setDrawerSectionHeight(EditorDrawerPage page, std::optional<int> height);
    int drawerSectionHeight(EditorDrawerPage page) const;
    void setDrawerActivePage(EditorDrawerPage page);
    EditorDrawerPage drawerActivePage() const;
    bool hasVisibleDrawerSection() const;
    EditorDrawer *editorDrawer() const noexcept { return m_editorDrawer; }

    // User-added automation lanes with no events yet (SPEC §6.1 "addable from
    // the m4a parameter list"). They live in view state — the model derives
    // lanes from events — and survive document rebuilds until the song is
    // swapped; once the lane gets its first point the model carries it.
    void addEmptyLane(int track, uint8_t cc);
    void removeEmptyLane(int track, uint8_t cc);

    // Display max for a CC lane's value axis (0 = auto-fit): the lane
    // menu's "Value range" choice, exposed for the harnesses. View state
    // only — lane values themselves are untouched.
    void setLaneDisplayRange(int track, uint8_t cc, int maxValue);

    // Raw MIDI event list: an alternative to the piano roll in the same
    // screen space (the ruler, headers, and automation lanes stay). Per-song
    // view state; toggled from the View menu.
    bool eventListVisible() const;
    void setEventListVisible(bool visible);

    // --- shared state for the child widgets ---
    songview::EditorSelectionModel &selectionModel() { return m_selectionModel; }
    const songview::EditorSelectionModel &selectionModel() const { return m_selectionModel; }
    const MidiTimeline *timeline() const { return m_timeline; }
    const SongViewModel &model() const { return m_model; }
    const LoadedVoiceGroup *voicegroup() const { return m_voicegroup; }
    std::vector<songview::TimelineBand> timelineBands() noexcept;

    qreal contentX(double tick) const { return qreal(tick * m_pxPerTick - m_scrollX); }
    double tickAtContentX(qreal x) const { return (double(x) + m_scrollX) / m_pxPerTick; }
    // Camera dead space before tick 0: the horizontal scroll floor is
    // -leadPadPx(), so the song start can rest inside the viewport instead
    // of pinned to its left edge (zooming near the start clamps here, which
    // keeps tick 0 on screen).
    double leadPadPx() const;
    qreal displayX(double tick, qreal origin, qreal dpr) const;
    double pxPerTick() const { return m_pxPerTick; }
    double pxPerBeat() const;
    double scrollY() const { return m_scrollY; }
    double keyHeight() const { return m_keyHeight; }
    const songview::PitchProjection &pitchProjection() const { return m_projection; }

    // Fold projection updates wait for a pointer gesture to commit, so the
    // row geometry remains stable while its note edit is in progress.
    void setProjectionLocked(bool locked);
    void flushProjectionIfDirty();
    double playheadTick() const { return m_playheadTick; }

    // Edit cursor (Reaper-style): placed by clicking the ruler or empty
    // roll space (with a document, dragging or double-clicking there draws
    // a note instead), distinct from the moving playback cursor. Playback
    // starts here, and paste anchors here.
    uint64_t editCursorTick() const { return m_editCursorTick; }
    // Visual placement only (ruler drag preview); commit emits
    // editCursorMoved so playback can follow.
    void setEditCursorTick(uint64_t tick);
    void commitEditCursor(uint64_t tick);
    // Transport "go to start": edit cursor to tick 0 and scroll home.
    void goToStart();

    void selectTrack(int track);
    // Track-wide pitch-envelope chrome belongs to the view, not its rebuilt
    // header rows. At most the selected track can be open.
    std::optional<int> pitchEnvelopeTrack() const { return m_pitchEnvelopeState.openTrack(); }
    void setPitchEnvelopeVisible(int track, bool visible);
    // Stable track eligibility across its initial program and every program
    // change; this never follows playback or note selection.
    bool trackHasPitchEnvelopeVoice(int track) const;
    // Track-wide authoring is available whenever the selected track contains
    // at least one note that starts in an eligible PSG voice span.
    bool pitchEnvelopeCreationEnabled(int track) const;

    // Scale controls are independent per-tab runtime toggles; neither is
    // persisted with the song or its view sidecar.
    bool scaleHighlight() const { return m_scaleHighlight; }
    void setScaleHighlight(bool enabled);
    bool scaleFold() const { return m_scaleFold; }
    void setScaleFold(bool enabled);
    int scaleRoot() const { return m_scaleRoot; } // 0-11 (C=0)
    void setScaleRoot(int root);
    porydaw_scale::ScaleId scaleId() const { return m_scaleId; }
    void setScaleId(porydaw_scale::ScaleId id);
    void foldTransposeSelection(int degreeDelta);
    // Reveal a polyphony-overflow event's note: select its track, select the
    // last note on (track, key) starting at or before tick — the lost note (a
    // dropped note starts exactly there, a stolen one spans it, a cut tail
    // ended just before) — and scroll the key into view. Returns whether a
    // note was found and selected (the track selection sticks either way).
    bool revealNote(int track, uint8_t key, uint64_t tick);
    void trackHeaderClicked(int track, Qt::KeyboardModifiers modifiers);
    bool trackMuted(int track) const { return m_muteMask & (1u << track); }
    bool trackSoloed(int track) const { return m_soloMask & (1u << track); }
    // Full masks, for re-applying to the audio engine on a tab switch.
    uint32_t muteMask() const { return m_muteMask; }
    uint32_t soloMask() const { return m_soloMask; }
    void setTrackMute(int track, bool on);
    void setTrackSolo(int track, bool on);
    // Keyboard face of the header buttons, over the multi-track scope:
    // mixed state resolves toward on (mute/solo everything in the scope),
    // a second press turns it back off.
    void toggleMuteOnSelectedTracks();
    void toggleSoloOnSelectedTracks();

    static QColor trackColor(int track);
    static QColor noteColor(int track, int velocity);
    // Velocity-hue display mode (View menu, app-wide): the active track's
    // note fills take their hue from velocity — purple (1) sweeping the long
    // way around the wheel to red (127) — instead of the track identity.
    // Ghost notes and every other identity-colored surface are unchanged.
    static QColor velocityNoteColor(int velocity);
    bool velocityColorMode() const { return m_velocityColorMode; }
    void setVelocityColorMode(bool on);
    // Note-name display mode (View menu, app-wide): from kNoteNameMinKeyH of
    // vertical zoom up, each visible active-track note independently carries
    // its pitch name when its face fits the complete name plus two trailing
    // spaces. Ghost notes are never labeled.
    bool noteNameMode() const { return m_noteNameMode; }
    void setNoteNameMode(bool on);
    // App-wide Follow Playhead toggle (transport bar / View menu): off, the
    // playback follow-scroll — the roll's and the event list's — is
    // suppressed and the camera stays where the user put it.
    void setFollowPlayhead(bool on);
    // The active-track note fill under the current display mode.
    QColor noteFillColor(int track, int velocity) const;
    // The track's program at the display position — the playhead while
    // playing, the edit cursor otherwise — so the header label follows the
    // song's voice changes. Before the first change it stays firstProgram
    // (which is what primes the engine), -1 if the track has none.
    int currentProgram(int track) const;
    QString instrumentLabel(int track) const; // "042 name (type)" from the voicegroup
    QString voiceShortName(uint8_t program) const;

    // Jump-from-context: surface the program in the voicegroup dock (the
    // main window raises it and selects the slot via revealVoiceRequested).
    // revealTrackVoice resolves the track's program at the display position
    // (what currentProgram shows in the header) first. Entry points: the
    // header row's voice line and context menu, and the event list's
    // program-change rows.
    void revealVoice(int program);
    void revealTrackVoice(int track);
    // Every program the song references: each track's first program plus
    // all voice changes. Feeds the dock's used-row highlighting.
    QSet<int> usedVoices() const;

    // Modal voicegroup-entry picker with press-and-hold audition. Returns
    // false on cancel; otherwise *outVoice is the chosen entry (0-127).
    bool pickVoice(const QString &title, int initialVoice, int *outVoice);
    // Track-header entry point: re-pick the voice governing the track (its
    // first program change), inserting one at tick 0 if the track has none.
    void editTrackVoice(int track);

    // Track create/duplicate/delete/reorder entry points. The complete
    // TrackRemap supplied by SongDocument re-addresses every persistent
    // track owner on apply, undo, and redo.
    void addTrack();
    void duplicateTrack(int track);
    void deleteTrack(int track);
    void moveTrack(int from, int to);
    // Inline rename: opens a line editor on the track's header row
    // (double-click and the context menu land here). commitTrackRename
    // applies the typed name — queued, since the edit rebuilds the header
    // panel out from under the editor's own signal — and refuses names
    // mid2agb would read as loop/label markers, with a status message.
    void renameTrack(int track);
    void commitTrackRename(int track, const QString &name);
    // Focus the current editing surface (roll or event list), e.g. after an
    // inline editor closes.
    void focusContent();

    // Focus the visible drawer page, or the main editing surface when the
    // drawer is hidden.
    void focusActiveSurface();

    // Bar/beat grid over [tickBegin, tickEnd): calls fn(tick, isBarStart,
    // barNumber, beatNumber) for every beat, honoring the song's time
    // signature changes.
    void forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                         const std::function<void(uint64_t, bool, int, int)> &fn) const;

    // --- editing support for the child widgets ---
    // Grid feel and floor (the ruler's grid controls): the zoom-adaptive
    // grid subdivides beats by powers of two (straight) or by threes
    // (triplet), and the minimum subdivision — a note denominator, quarter =
    // one beat — stops the DRAWN grid from refining past the note value the
    // user cares about (display only; snapping still steps one rung finer).
    // 0 keeps the default clock-grid floor. Per-song view state.
    enum class GridFeel { Straight, Triplet };
    GridFeel gridFeel() const { return m_gridFeel; }
    void setGridFeel(GridFeel feel);
    int gridMinDenom() const { return m_gridMinDenom; }
    void setGridMinDenom(int denom); // 4/8/16/32; anything else means 0

    // Time-signature segment governing a tick. The grid — beats, snap
    // positions, sub-beat lines — restarts at every signature change and
    // scales the beat by the signature's denominator, exactly like
    // forEachGridLine; a signature placed mid-measure must still leave the
    // drawn lines snappable.
    struct GridSeg {
        uint64_t start = 0;         // governing signature's tick (0 = song start)
        uint64_t next = UINT64_MAX; // next signature's tick; the grid restarts there
        uint64_t beatTicks = 24;    // denominator-scaled beat length in ticks
        uint64_t beatsPerBar = 4;   // numerator, matching forEachGridLine()
    };
    GridSeg gridSegAt(uint64_t tick) const;
    // One painted visible-grid cell. Cells are half-open [start, end): a
    // tick exactly at an end belongs to the next cell.
    struct GridCell {
        uint64_t start = 0;
        uint64_t end = 0;
    };
    // Visible-grid cell queries follow the painted grid, rather than the
    // finer edit snap grid, and restart at time-signature changes.
    uint64_t visibleGridTickDown(uint64_t tick) const;
    uint64_t visibleGridTickUp(uint64_t tick) const;
    GridCell visibleGridCellContaining(uint64_t tick) const;

    // Zoom-adaptive subdivision selected for the grid before drawGrid
    // suppresses sub-beat or beat lines at low detail.
    // It is not the painted-cell spacing; use visibleGridCellContaining().
    // The subdivision follows the governing segment's beat at the current
    // feel, floored at the minimum and never finer than the clock base.
    uint64_t gridTicksAt(uint64_t tick) const;
    // Visible grid at an explicit pixels-per-tick scale, using the
    // time-signature segment governing tick.
    uint64_t gridTicksAtScale(uint64_t tick, double pixelsPerTick) const;
    // Snap grid in ticks at a position: one feel-ladder step finer than the
    // visible grid, so edits can land halfway between drawn lines (thirds
    // stepping from beats in triplet feel). The minimum subdivision is a
    // display floor only — snapping steps past it — but the clock base
    // still bounds it, and it always divides the visible grid.
    uint64_t snapTicksAt(uint64_t tick) const;
    // Fine placement (Alt-drag in the lanes): the mid2agb clock grid — the
    // document's real resolution — regardless of the zoom-dependent grid.
    uint64_t fineGridTicks() const;
    // Nearest / previous snap-grid position, anchored at the governing
    // time-signature segment (fine snap stays on the absolute clock grid).
    uint64_t snapTick(double tick, bool fine = false) const;
    uint64_t snapTickDown(double tick) const;
    uint64_t snapTickUp(double tick) const;
    DrawerPageGridState gridState(uint64_t tick, bool fineMode) const;
    bool paintGrid(QPainter &, const QRect &, qreal origin) const;

    DrawerPageVoiceContext voiceContext(uint64_t tick) const;
    // Shared deferred velocity gesture; document mutation happens only when
    // commitVelocityGesture() accepts the captured revision.
    enum class VelocityCommitResult { NoGesture, Unchanged, Committed, Rejected };
    bool beginVelocityGesture(const std::vector<DocNote> &notes);
    bool updateVelocityGesture(const std::vector<NoteVelocity> &updates);
    bool updateVelocityGestureByDelta(int delta);
    void cancelVelocityGesture();
    VelocityCommitResult commitVelocityGesture();
    std::optional<uint8_t> previewVelocity(NoteId noteId) const;

    // "Time selection: 8 beats · 3 tracks" status-bar line; children call it
    // when a selection gesture commits.
    void announceTimeSelection();

    // Range operations on the time selection. Copy captures notes plus every
    // editable lane (including voice changes) of the scoped tracks — or just
    // the scoped lanes — with ticks relative to the range start. Paste
    // anchors at the edit cursor and REPLACES the covered span: pasted
    // "silence" clears, and a single-source-track clip retargets to the
    // selected track. All one undoable command each.
    void copyTimeSelection();
    void deleteTimeSelection();
    // "Remove contents": the selected span vanishes and everything after it
    // shifts left to close the gap. Selecting every track cuts the whole song
    // (tempo, time signatures, loop markers and track ends close too); a
    // partial scope shifts only its own tracks or lanes so the rest of the
    // song keeps its alignment.
    void removeTimeSelectionContents();
    // Insert and duplicate operate only on an active half-open time selection.
    void insertBlankTime();
    void duplicateTimeSelection();
    void pasteRangeAtEditCursor();
    // Ctrl+Up/Down on the selection: transpose every covered note (all
    // scoped tracks at once). Same all-or-nothing rule as the roll's note
    // selection — if any note would clamp at the key range, nothing moves.
    void transposeTimeSelection(int dKey);
    // Ctrl+Left/Right: the selection start moves to the previous/next
    // ruler grid line and the covered contents (notes and automation
    // points) move with it; the band follows.
    void nudgeTimeSelection(bool right);
    // Shared shortcut handling for the roll and the lanes area: range
    // copy/cut/delete while a time selection is active, paste of range
    // clips, and transpose/nudge of the selection (keymap commands).
    // Returns true when consumed.
    bool handleEditKey(QKeyEvent *event);
    // Semitone step for the transpose command the event matches (0 if none);
    // shared by the note- and time-selection key paths.
    int transposeStepFor(const QKeyEvent *event) const;
    // Copy/Cut/Delete/Paste/Clear context menu on the active selection.
    void showTimeSelectionMenu(const QPoint &globalPos);

    // App-internal clipboard. A plain note copy (roll selection) has span 0
    // and pastes additively; a range copy carries span > 0 plus lane
    // segments and pastes with replace semantics. Ticks are offsets from
    // the copied block's start so paste can re-anchor at the edit cursor.
    // Survives track switches and document rebuilds; cleared on song swap
    // (another song's ticks-per-beat may differ).
    struct ClipNote {
        uint32_t relTick;
        uint8_t key;
        uint32_t duration;
        uint8_t velocity;
    };
    struct ClipTrack {
        int track; // source engine track
        std::vector<ClipNote> notes;
    };
    struct ClipLane {
        int track; // source engine track
        uint8_t cc;
        std::vector<std::pair<uint32_t, int>> points; // (relTick, value)
    };
    struct Clip {
        uint64_t span = 0;      // ticks covered; 0 = plain note clip
        bool wholeLane = false; // gutter "Copy lane" (paste-lane anchor is 0)
        std::vector<ClipTrack> tracks;
        std::vector<ClipLane> lanes;
        std::vector<TempoPoint> tempo; // relative ticks, microseconds

        bool empty() const { return tracks.empty() && lanes.empty() && tempo.empty(); }
    };
    Clip &clipboard() { return m_clip; }

    // "velocity 93 → plays 96 · length 25 → 24 clocks" for the status bar.
    void announceNote(const ViewNote &note);

    // Child-widget entry point for the auditionNote signal.
    void audition(int track, int key, int velocity) { emit auditionNote(track, key, velocity); }

    // Fixed-length audition for the band-sweep chord preview: the note's tick
    // span converts to samples through the display timeline, so the preview
    // lasts at most as long as the note does in the song (tempo changes
    // included).
    void auditionTimed(int track, int key, int velocity, uint64_t startTick, uint64_t endTick);

    // Early release for a timed audition (the band no longer covers the
    // note); the velocity-0 form of the same signal.
    void auditionTimedOff(int track, int key) { emit auditionNoteTimed(track, key, 0, 0); }

    // Child-widget entry point for the statusMessage signal.
    void announce(const QString &text) { emit statusMessage(text); }
    void setEditorHorizontalScroll(double px);
    void setEditorTimeZoom(double pxPerBeat);
    void setFollowScrollPaused(bool paused);
    void showDrawerPageTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request);
    void showDrawerPageNoteStatus(std::optional<DrawerPageNoteStatus> status);
    void requestDrawerPageUndo();
    void requestDrawerPageRedo();
    DrawerPageLiveState drawerPageLiveState() const;
    void cancelActiveInteractions();
    // A mouse gesture is live in the ruler, roll, or lanes (pan, drag,
    // sweep); playhead follow-scroll pauses while one runs.
    bool userGestureActive() const;
    // Child-widget request to toggle transport from a specific song tick.
    void requestPlayPauseFrom(uint64_t tick) { emit playPauseFromRequested(tick); }

    // Interaction from children.
    void zoomTimelineAtWheel(const QWheelEvent *event, qreal anchorContentX);
    void zoomAroundContentX(double factor, qreal anchorContentX);
    // Vertical roll zoom (key height) from Ctrl+wheel, pinning the key under
    // the cursor. The wheel event supplies continuous deltas.
    void zoomKeyHeight(const QWheelEvent *event);
    void scrollByPx(double dx);
    void scrollRollBy(double dy);
    // Scrolls horizontally so the tick sits a third of the way into the
    // viewport if it is currently off-screen; on-screen ticks are left
    // alone. Pastes anchor at the edit cursor, which can be scrolled out
    // of view — without this the paste looks like a no-op.
    void ensureTickVisible(uint64_t tick);
    // Minimal-scroll companion for the keyboard transpose/nudge moves:
    // shifts the view just enough to bring the tick span back inside,
    // instead of ensureTickVisible's jump-to-a-third anchoring. A span
    // wider than the viewport keeps the edge the move headed toward
    // (the end when preferEnd, else the start).
    void ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd);
    // Vertical counterpart: scrolls the roll just enough for the key's
    // row to be fully visible.
    void ensureKeyVisible(int key);
    void refreshTimelineViews();
    // Refresh both concrete drawer pages from the current live SongView state.
    // This endpoint does not proactively cancel interaction.
    void refreshAllDrawerPages();

  signals:
    void muteMaskChanged(uint32_t mask);
    void soloMaskChanged(uint32_t mask);
    void selectedTrackChanged(int track);
    void pitchEnvelopeVisibilityChanged();

    void scaleHighlightChanged();
    void scaleFoldChanged();
    void scaleRootChanged();
    void scaleIdChanged();
    // Audition request (velocity 0 releases); forwarded to the audio engine.
    void auditionNote(int track, int key, int velocity);
    // Self-releasing audition (band-sweep chord preview); forwarded to
    // AudioEngine::previewNoteTimed, which sends the note-off itself.
    // velocity 0 releases the track+key's preview early.
    void auditionNoteTimed(int track, int key, int velocity, quint32 durationSamples);
    // Voicegroup-entry audition from the voice picker; routed to
    // AudioEngine::previewVoice like the voicegroup browser's signal.
    void auditionVoice(int voice, int key, int velocity);
    void statusMessage(const QString &text);
    // Edit cursor committed to a new position (click released); the main
    // window seeks playback here when not stopped.
    void editCursorMoved(uint64_t tick);
    // Popup/editor audition: start from tick when stopped or paused, or pause
    // the currently playing transport.
    void playPauseFromRequested(uint64_t tick);
    // Roll/event-list swap (user toggle or applyViewState); the main window
    // mirrors it into the View-menu checkbox.
    void eventListVisibilityChanged(bool visible);
    // Jump-from-context voice navigation: the main window raises the
    // voicegroup dock and selects this slot.
    void revealVoiceRequested(int program);
    // Application-wide drawer chrome changed in this view.
    void editorDrawerStateChanged(const EditorDrawerState &state);

  protected:
    void resizeEvent(QResizeEvent *event) override;
    bool event(QEvent *event) override;

  private:
    friend class EditorDrawer;
    friend class songview::PianoRoll;
    friend class songview::TrackHeaderRow;
    struct Geometry {
        int trackHeaderWidth;
        int pianoKeyboardWidth;
        int plotOrigin;
        int editorDefaultPixelsPerBeat;
        int pianoRollInitialViewportHeight;
        int timelineMinimumPixelsPerBeat;
        int timelineMaximumPixelsPerBeat;
        int pianoRollMinimumKeyHeight;
        int pianoRollMaximumKeyHeight;
        int velocityHandleMinimumKeyHeight;
        int timelineDetailMinimumPixelsPerBeat;
        int gridLineStrokeWidth;
        int automationGridMinimumCellWidth;
        qreal timelineRevealViewportFraction;
        int timelineViewportMinimumWidth;
        int timelineContentTailWidth;

        static Geometry resolve();
    };

    void refreshGeometry();
    uint64_t gridTicksIn(const GridSeg &seg, double pixelsPerTick, bool snap = false) const;
    // Document remap handler: re-addresses all SongView-owned track state
    // before the following documentChanged rebuild.
    void onTracksRemapped(const TrackRemap &remap);
    // One path for all selection changes. Remapping an engine slot while it
    // still represents the same logical track is not a track transition.
    void transitionSelectedTrack(int newTrack);
    void transitionSelectedTrack(int newTrack, bool trackIdentityChanged);
    void updateScaleProjection();
    void updateScaleMembership();
    void buildOccupancySet(std::span<bool, 128> out) const;
    void rebuildProjectionWithAnchoring();
    void syncPlayheadOverlay();
    void refreshPitchEnvelopeState();

    void notifyDrawerSongChanged();
    void notifyVelocityGestureChanged();
    void refreshDrawerPages();
    void refreshAutomationPage();
    void refreshVelocityPage();
    int viewportWidth() const;
    int rollViewportHeight() const;
    void setHScroll(double px);
    double minHScroll() const;
    double maxHScroll() const;
    void setVScroll(double y);
    double maxRollScroll() const;
    void updateScrollbars();
    void rebuildAfterSongChange();
    struct TimeScopeResolution {
        SongDocument::TimeScope scope;
        QString label;
    };
    void coordinateSelectionChange(songview::EditorSelectionModel::SelectionChange change);
    std::optional<TimeScopeResolution> resolveTimeSelectionScope() const;
    // Engine tracks a track-scoped time selection resolves to (used and
    // document-mapped), and the copyable lane identities of one track (its
    // model lanes plus the voice changes).
    std::vector<int> timeSelectionTracks() const;
    std::vector<uint8_t> trackCcs(int track) const;

    const MidiTimeline *m_timeline = nullptr;
    const LoadedVoiceGroup *m_voicegroup = nullptr;
    SongDocument *m_document = nullptr;
    SongViewModel m_model;
    songview::EditorSelectionModel m_selectionModel;
    Geometry m_geometry;
    songview::PitchProjection m_projection;
    bool m_projectionDirty = false;
    bool m_projectionLocked = false;

    double m_pxPerTick = 1.0;
    double m_scrollX = 0.0;
    double m_scrollY = 0.0;
    double m_keyHeight = 0.0;
    bool m_scaleHighlight = false;
    bool m_scaleFold = false;
    int m_scaleRoot = 0; // C
    porydaw_scale::ScaleId m_scaleId = porydaw_scale::ScaleId::major;
    double m_playheadTick = 0.0;
    uint64_t m_editCursorTick = 0;
    songview::PitchEnvelopeUiState m_pitchEnvelopeState;
    bool m_playing = false;
    uint32_t m_muteMask = 0;
    uint32_t m_soloMask = 0;
    Clip m_clip;
    GridFeel m_gridFeel = GridFeel::Straight;
    int m_gridMinDenom = 0;           // note denominator; 0 = clock-grid floor
    bool m_velocityColorMode = false; // velocityNoteColor fills (View menu)
    bool m_noteNameMode = false;      // pitch labels on notes (View menu)
    bool m_followPlayhead = true;     // playback follow-scroll (transport bar)
    TrackActivity m_trackActivity;

    EditorViewState m_editorViewState;
    EditorDrawer *m_editorDrawer = nullptr;
    bool m_followScrollPaused = false;
    VelocityGestureModel m_velocityGesture;
    songview::TimeRuler *m_ruler = nullptr;
    songview::TrackHeaderPanel *m_headers = nullptr;
    songview::PianoRoll *m_roll = nullptr;
    QStackedWidget *m_rollStack = nullptr; // page 0: roll (+vbar), page 1: event list
    songview::PitchEnvelopeHost *m_pitchEnvelopeHost = nullptr;
    EventListView *m_events = nullptr;
    songview::OtherStrip *m_strip = nullptr;
    songview::PlayheadOverlay *m_playheadOverlay = nullptr;
    QScrollBar *m_hbar = nullptr;
    QScrollArea *m_headerScroll = nullptr;
    QHBoxLayout *m_hbarRow = nullptr;
    QSpacerItem *m_hbarGutter = nullptr;
    QScrollBar *m_vbar = nullptr;
};
