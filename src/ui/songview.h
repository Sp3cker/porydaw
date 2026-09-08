#pragma once

#include <QColor>
#include <QFlags>
#include <QHash>
#include <QList>
#include <QMetaObject>
#include <QPointer>
#include <QRectF>
#include <QSet>
#include <QVariantMap>
#include <QWidget>
#include <cstdint>
#include <functional>
#include <memory>
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
#include "ui/songview/clip.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/grid.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/scalecontroller.h"
#include "ui/songview/timeaxis.h"
#include "ui/songview/timecamera.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songviewmodel.h"
#include "ui/velocitygesturemodel.h"

extern "C" {
#include "voicegroup_loader.h"
}

class EventListController;
class QKeyEvent;
class QEvent;
class QSpacerItem;
class QStackedWidget;
class SongDocument;
class AutomationPage;
class EditorDrawer;
class VelocityArea;
struct DocNote;
struct NoteVelocity;
struct TrackRemap;

namespace songview {
class TimeRuler;
class TrackHeaderModel;
class EditorSelectionModel;
class PianoRoll;
class TimelineQuickView;
class PlayheadOverlay;
class OtherStrip;
class VoicePicker;
class QuickMenuHost;
class QuickMenuModel;
class QuickPopupSession;
struct QuickMenuItem;
enum class PianoRollQuickDirty : quint32;
enum class TimelineQuickDirty : quint16;
using TimelineQuickDirtySet = QFlags<TimelineQuickDirty>;
enum class AutomationRefresh : quint8;
using AutomationRefreshSet = QFlags<AutomationRefresh>;
enum class TimelineQuickHoverOwner : quint8;
using PianoRollQuickDirtySet = QFlags<PianoRollQuickDirty>;

// Perceptually mixes a color toward its backdrop. Timeline surfaces use this
// shared shade for receding track-colored details.
QColor mixTowardOklab(const QColor &color, const QColor &backdrop, double t);

// Note-name labels: with the View toggle on, each active-track note carries
// its pitch name unless the velocity shortcut is held. The label face is
// fixed, and it hides — never shrinks — whenever its padded height misses
// the row; this floor is only a cheap pre-gate that no padded face ever
// fits under.
constexpr int kNoteNameMinKeyH = 12;
// Frame weights for note borders and the selection ring, in physical
// pixels for the given display ratio. The resolver scales their DIP widths
// with the editor font; painting still lands on whole physical pixels so
// fractional scale factors cannot open seams. Exposed so roll checks assert
// the same math the paint code uses.
int noteBorderPixels(qreal dpr);
int selectionRingPixels(qreal dpr);

// Shared time-selection context menu actions (roll + drawer). The ints are
// the stable ids the typed menu rows carry through QuickMenuModel::activated.
enum class TimeSelectionAction : int {
    Copy = 1,
    Cut = 2,
    Delete = 3,
    InsertBlank = 4,
    Duplicate = 5,
    RemoveContents = 6,
    Paste = 7,
    Clear = 8,
};

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

    Q_PROPERTY(int insertTimePromptInitialBars READ insertTimePromptInitialBars NOTIFY
                   insertTimePromptChanged FINAL)
    Q_PROPERTY(int insertTimePromptInitialBeats READ insertTimePromptInitialBeats NOTIFY
                   insertTimePromptChanged FINAL)
    Q_PROPERTY(int insertTimePromptInitialBeatFractions READ insertTimePromptInitialBeatFractions
                   NOTIFY insertTimePromptChanged FINAL)
    Q_PROPERTY(int insertTimePromptMinimumBars READ insertTimePromptMinimumBars CONSTANT FINAL)
    Q_PROPERTY(int insertTimePromptMaximumBars READ insertTimePromptMaximumBars CONSTANT FINAL)
    Q_PROPERTY(int insertTimePromptMinimumBeats READ insertTimePromptMinimumBeats CONSTANT FINAL)
    Q_PROPERTY(int insertTimePromptMaximumBeats READ insertTimePromptMaximumBeats NOTIFY
                   insertTimePromptChanged FINAL)
    Q_PROPERTY(int insertTimePromptMinimumBeatFractions READ insertTimePromptMinimumBeatFractions
                   CONSTANT FINAL)
    Q_PROPERTY(int insertTimePromptMaximumBeatFractions READ insertTimePromptMaximumBeatFractions
                   CONSTANT FINAL)
    Q_PROPERTY(QString insertTimePromptTitle READ insertTimePromptTitle NOTIFY
                   insertTimePromptChanged FINAL)
    Q_PROPERTY(QVariantMap insertTimePromptAppearance READ insertTimePromptAppearance NOTIFY
                   insertTimePromptChanged FINAL)

  public:
    explicit SongView(QWidget *parent = nullptr);
    ~SongView() override;

    void setSong(const MidiTimeline *timeline, const LoadedVoiceGroup *voicegroup);
    // Timeline swap after a document edit: keeps zoom, scroll, track
    // selection, mute/solo, and re-resolves the note selection.
    void updateSong(const MidiTimeline *timeline);
    void setPlayheadSample(uint64_t samplePos, bool playing);
    bool advanceTrackActivity(const TrackActivityLevels &levels, float elapsedSeconds,
                              bool playing);

    // Editing is enabled while a document is attached (may be null).
    void setDocument(SongDocument *document);
    void prepareForSongReplacement();
    // Cancels only ephemeral user input after a readiness drop; it never
    // changes persistent view or document state.
    void cancelTransientInput();
    SongDocument *document() const { return m_document; }
    // Voicegroup swap after a -G settings change (labels only; may be null
    // while the audio engine frees the old one).
    void setVoicegroup(const LoadedVoiceGroup *voicegroup);

    // Transient per-tab camera, selection, grid, and event-list state. It is
    // never persisted or propagated between tabs.
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

    // Complete application-wide drawer and automation-lane projection.
    EditorViewState editorViewState() const;
    // Silent projection used by the application-wide hub.
    void applyEditorViewState(const EditorViewState &state);
    // Origin commit used by drawer/page/lane mutations.
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
    // The Quick host of the migrated timeline bands; created unconditionally
    // in the constructor — production callers use quickView() instead of
    // findChild by object name (checks/harnesses may still look it up).
    // Out-of-line: TimelineQuickView is forward-declared here, so the
    // QPointer conversion needs the complete type in songview.cpp.
    songview::TimelineQuickView *quickView() const noexcept;
    // The Quick event-list controller; created unconditionally in the
    // constructor and registered on the timeline Quick window's root
    // context as "eventListController".
    EventListController *eventListController() const noexcept;
    // Canonical SongView-local timeline band geometry: one parent-owned
    // value drives Quick/QML band placement and native playhead clipping.
    // Hidden bands hold nullopt.
    const songview::TimelineBandLayout &timelineBandLayout() const noexcept
    {
        return m_timelineBandLayout;
    }

    // Canonical SongView-local rectangles of the two QML scrollbar lanes:
    // the horizontal timeline row right of the split, and the column
    // directly right of the canonical roll band (drawer-clipped height;
    // empty in EventList mode). TimelineQuickView unions them into the
    // Quick window envelope and republishes them Quick-root-local.
    QRect horizontalScrollbarRect() const;
    QRect verticalScrollbarRect() const;

    // EventList mode: the Quick event page replaces the roll band in the
    // same screen space. This canonical SongView-local rectangle keeps the
    // Quick window envelope covering the page; empty while hidden.
    QRect eventListRect() const;
    // User-added automation lanes with no events yet (SPEC §6.1 "addable from
    // the m4a parameter list). They live in the application-wide editor
    // projection — the model derives lanes from events — and survive document
    // rebuilds and song swaps; once the lane gets its first point the model
    // carries it.
    void addEmptyLane(int track, uint8_t cc);
    void removeEmptyLane(int track, uint8_t cc);

    // Display max for a CC lane's value axis (0 = auto-fit): the lane
    // menu's "Value range" choice, exposed for the harnesses. View state
    // only — lane values themselves are untouched.
    void setLaneDisplayRange(int track, uint8_t cc, int maxValue);

    // Raw MIDI event list: an alternative to the piano roll in the same
    // screen space (the ruler, headers, and automation lanes stay). Per-tab
    // transient view state; toggled from the View menu.
    bool eventListVisible() const;
    void setEventListVisible(bool visible);

    // --- shared state for the child widgets ---
    songview::EditorSelectionModel &selectionModel() { return m_selectionModel; }
    const songview::EditorSelectionModel &selectionModel() const { return m_selectionModel; }
    const MidiTimeline *timeline() const { return m_timeline; }
    // The always-valid musical axis (fallback before any song binds);
    // painters read signatures and loop markers here instead of the
    // optional timeline.
    const songview::TimeAxis &timeAxis() const { return m_timeAxis; }
    const SongViewModel &model() const { return m_model; }
    const LoadedVoiceGroup *voicegroup() const { return m_voicegroup; }
    int trackHeaderWidth() const noexcept { return m_geometry.trackHeaderWidth; }
    int pianoKeyboardWidth() const noexcept { return m_geometry.pianoKeyboardWidth; }
    int timelineSplitX() const noexcept { return m_geometry.timelineSplitX; }
    void publishTimelineQuickHover(songview::TimelineQuickHoverOwner owner, uint64_t tick);
    void clearTimelineQuickHover(songview::TimelineQuickHoverOwner owner);
    // Widget-owned migrated bands route retained-scene invalidation through this seam.
    void requestTimelineQuickUpdate(songview::TimelineQuickDirtySet dirty);
    // Retained automation scenes repaint through the dedicated refresh channel.
    void requestAutomationQuickUpdate(songview::AutomationRefreshSet refresh);

    const songview::TimeCamera &camera() const noexcept { return m_camera; }
    const songview::Grid &grid() const noexcept { return m_grid; }

    // Derived from the canonical beat scale: a resolution change can only
    // move this quotient, never the beat positions it produces.
    double pxPerTick() const noexcept { return m_camera.pxPerTick(); }
    double pxPerBeat() const { return m_camera.pxPerBeat(); }
    double scrollY() const { return m_camera.scrollY(); }
    double keyHeight() const { return m_camera.keyHeight(); }
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
    void resetScrollPosition();

    void selectTrack(int track);

    // Scale controls are independent per-tab runtime toggles; neither is
    // persisted with a song or propagated between tabs. State and classification
    // live in the ScaleController component; SongView is the only surface
    // that mutates it, and the UI side effects (signals, roll repaint, the
    // anchored rebuild) are driven directly here.
    bool scaleHighlight() const { return m_scaleController.scaleHighlight(); }
    void setScaleHighlight(bool enabled);
    bool scaleFold() const { return m_scaleController.scaleFold(); }
    void setScaleFold(bool enabled);
    int scaleRoot() const { return m_scaleController.scaleRoot(); } // 0-11 (C=0)
    void setScaleRoot(int root);
    porydaw_scale::ScaleId scaleId() const { return m_scaleController.scaleId(); }
    void setScaleId(porydaw_scale::ScaleId id);
    // Fold state, classification, and row math for the roll's commands and
    // draw checks (the component's fold math routes through the facade).
    bool isScalePitch(int midiPitch) const { return m_scaleController.isScalePitch(midiPitch); }
    int nextScalePitch(int midiPitch, int steps) const
    {
        return m_scaleController.nextScalePitch(midiPitch, steps);
    }
    bool resolveFoldDestinations(std::vector<DocNote> &notes, int degreeDelta,
                                 std::vector<uint8_t> &destinations) const
    {
        return m_scaleController.resolveFoldDestinations(notes, degreeDelta, destinations);
    }
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
    // Quick header's voice line and context menu, and the event list's
    // program-change rows.
    void revealVoice(int program);
    void revealTrackVoice(int track);
    // Every program the song references: each track's first program plus
    // all voice changes. Feeds the dock's used-row highlighting.
    QSet<int> usedVoices() const;

    // Opens the shared canvas Quick popup asynchronously. The context,
    // current document identity, and document revision must still match at
    // acceptance; otherwise accepted is not called.
    void requestVoicePicker(const QString &title, int initialVoice, QObject *context,
                            std::function<void(int)> accepted, songview::TimelineBand origin);
    void cancelVoicePicker(bool restoreFocus);
    // Context-scoped hard cancellation: ends only a picker whose staged
    // context is this caller, leaving a foreign owner's picker untouched.
    void cancelVoicePickerFor(QObject &context);
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
    // Inline rename: opens the Quick header's edit field (double-click and
    // the context menu land here). commitTrackRename applies the typed name
    // queued, since the edit rebuilds the header model while its input is
    // still active — and refuses names mid2agb would read as loop/label
    // markers, with a status message.
    void renameTrack(int track);
    void commitTrackRename(int track, const QString &name);
    // Focus the current editing surface (roll or event list), e.g. after an
    // inline editor closes.
    void focusContent();

    // Focus the visible drawer page, or the main editing surface when the
    // drawer is hidden.
    void focusActiveSurface();

    // Focus bridge to the shared Quick timeline input items. Only converted
    // bands accept focus; focusTimelineBand reports false while the band's
    // input item does not exist yet, and focusedTimelineBand reads the live
    // active-focus band of those items. The event page is deliberately not a
    // TimelineBand: while it holds focus focusedTimelineBand reports
    // nullopt, and eventListSurfaceFocused distinguishes that from "nothing
    // focused".
    bool focusTimelineBand(songview::TimelineBand band, Qt::FocusReason reason);
    std::optional<songview::TimelineBand> focusedTimelineBand() const;
    bool eventListSurfaceFocused() const;

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
    void setGridFeel(songview::GridFeel feel);
    void setGridMinDenom(int denom); // 4/8/16/32; anything else means 0

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

    // Canonical Copy command (defined in src/ui/songview/editkeyrouting.cpp
    // beside the dispatch): an active time selection owns the command;
    // otherwise the selected notes are copied.
    void copySelection();
    // Range operations on the time selection. Copy captures notes plus every
    // editable lane (including voice changes) of the scoped tracks — or just
    // the scoped lanes — with ticks relative to the range start. Paste
    // merges at the edit cursor: notes are additive, and only exact-tick
    // lane/tempo conflicts are replaced. A single-source-track clip retargets
    // to the selected track. Each non-empty operation is one undoable command.
    void copyTimeSelection();
    void deleteTimeSelection();
    // "Remove contents": the selected span vanishes and everything after it
    // shifts left to close the gap. Selecting every track cuts the whole song
    // (tempo, time signatures, loop markers and track ends close too); a
    // partial scope shifts only its own tracks or lanes so the rest of the
    // song keeps its alignment.
    void removeTimeSelectionContents();
    // Global Insert Time command: asks for bars, beats, and quarter-beat
    // fractions, then inserts that much whole-song time at the live playhead
    // or the edit cursor while stopped.
    void insertTimeAtPlaybackCursor();
    // Typed Quick-modal bridge for Insert Time. The SongView retains the
    // guarded document/cursor snapshot; QML owns only its numeric drafts.
    Q_INVOKABLE void acceptInsertTimePrompt(int bars, int beats, int fractions);
    Q_INVOKABLE void cancelInsertTimePrompt();
    int insertTimePromptInitialBars() const noexcept;
    int insertTimePromptInitialBeats() const noexcept;
    int insertTimePromptInitialBeatFractions() const noexcept;
    static constexpr int insertTimePromptMinimumBars() noexcept { return 0; }
    static constexpr int insertTimePromptMaximumBars() noexcept { return 9999; }
    static constexpr int insertTimePromptMinimumBeats() noexcept { return 0; }
    int insertTimePromptMaximumBeats() const noexcept;
    static constexpr int insertTimePromptMinimumBeatFractions() noexcept { return 0; }
    static constexpr int insertTimePromptMaximumBeatFractions() noexcept { return 3; }
    QString insertTimePromptTitle() const;
    QVariantMap insertTimePromptAppearance() const;
    // Insert and duplicate operate only on an active half-open time selection.
    void insertBlankTime();
    void duplicateTimeSelection();
    void pasteRangeAtEditCursor(const songview::Clip &clip);
    // Single paste entry from every surface (roll keys, drawer-canvas keys,
    // the time-selection menu): reads the clipboard clip, dispatches a plain
    // note clip (span 0) to an additive primary-track paste at the edit
    // cursor and a range clip to pasteRangeAtEditCursor, announcing like the
    // per-surface paths did.
    void pasteFromClipboard();
    // Transpose selection (Up/Down / Shift+Up/Down): transpose every covered note
    // (all scoped tracks at once). Same all-or-nothing rule as the roll's note
    // selection — if any note would clamp at the key range, nothing moves.
    void transposeTimeSelection(int dKey);
    // Nudge selection (Left/Right): the selection start moves to the previous/next
    // ruler grid line and the covered contents (notes and automation
    // points) move with it; the band follows.
    void nudgeTimeSelection(bool right);
    // Which surface routed the key to the shared policy: Timeline — the
    // roll-page bands and Quick surfaces whose note canvas is the live
    // editing target — or EventList, the Quick event page whose input item
    // owns the row-local table commands.
    enum class EditKeyOrigin { Timeline, EventList };
    enum class SharedShortcutOwner { SongView, Window };
    // Shared command policy entry (src/ui/songview/editkeyrouting.cpp):
    // resolves shared keymap commands — note, range, and selection edits —
    // against the live selection. Returns true only when a target consumes
    // the command; unavailable targets deliberately decline it.
    bool handleEditKey(const songview::TimelineKeyInput &input,
                       EditKeyOrigin origin = EditKeyOrigin::Timeline);
    // Release tail of the shared policy: finishes the keyboard transpose
    // audition from whichever surface the chord came up on. It reports
    // whether that release actually stopped an audition.
    bool handleEditKeyRelease(const songview::TimelineKeyInput &input);
    void setSharedShortcutOwner(SharedShortcutOwner owner);
    // Shared Copy/Cut/Delete/Insert-blank/Duplicate/Remove-contents/Paste/
    // Clear context menu on the active selection, rendered through the
    // timeline Quick popup session. scenePos is a Quick-window scene
    // position; the menu is unavailable (silent no-op) while the Quick
    // canvas is missing.
    void openTimeSelectionMenu(const QPointF &scenePos);

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
    // Public observation of live pointer ownership. Follow-scroll state and
    // popup focus deliberately remain separate from command ownership.
    bool userGestureActive() const;
    // Child-widget request to toggle transport from a specific song tick.
    void requestPlayPauseFrom(uint64_t tick) { emit playPauseFromRequested(tick); }

    // Interaction from children.
    void zoomTimelineAtWheel(const songview::TimelineWheelInput &wheel, qreal anchorContentX);
    void zoomAroundContentX(double factor, qreal anchorContentX);
    // Vertical roll zoom (key height) from Ctrl+wheel, pinning the key under
    // the cursor. The normalized wheel input supplies continuous deltas.
    void zoomKeyHeight(const songview::TimelineWheelInput &input);
    void scrollByPx(double dx);
    void scrollRollBy(double dy);

    // Camera setters behind the QML scrollbar controls' value requests:
    // each clamps through TimeCamera and fans the sync tail (scrollbar
    // notification + redraw) out.
    void setHScroll(double px);
    void setVScroll(double y);
    // Fractional-DIP viewport the camera is bound to; the QML scrollbars'
    // page steps read the same values updateScrollbars() pushes.
    int viewportWidth() const;
    int rollViewportHeight() const;

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
    // Ruler, strip, playhead, and roll refresh; the roll repaint is limited
    // to the caller's semantic dirty set (see PianoRollQuickDirty). Every
    // caller names the narrowest set its change justifies.
    void refreshTimelineViews(songview::PianoRollQuickDirtySet dirty);
    // Refresh every concrete drawer page from the current live SongView state.
    // Public refresh seam for the standalone drawer pages after they commit a
    // document edit. This endpoint does not proactively cancel interaction.
    void refreshAllDrawerPages();

  signals:
    void muteMaskChanged(uint32_t mask);
    void soloMaskChanged(uint32_t mask);
    void selectedTrackChanged(int track);
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
    void insertTimePromptChanged();
    // Edit cursor committed to a new position (click released); the main
    // window seeks playback here when not stopped.
    void editCursorMoved(uint64_t tick);
    // Popup/editor audition: start from tick when stopped or paused; when
    // playing, pause and return the transport to tick for the next audition.
    void playPauseFromRequested(uint64_t tick);
    // Roll/event-list swap (user toggle or applyViewState); the main window
    // mirrors it into the View-menu checkbox.
    void eventListVisibilityChanged(bool visible);
    // Jump-from-context voice navigation: the main window raises the
    // voicegroup dock and selects this slot.
    void revealVoiceRequested(int program);
    // Complete application-wide editor state changed in this view.
    void editorViewStateChanged(const EditorViewState &state);

  protected:
    void resizeEvent(QResizeEvent *event) override;
    bool event(QEvent *event) override;

  private:
    friend class EditorDrawer;
    friend class songview::PianoRoll;
    friend class songview::TrackHeaderModel;
    friend class songview::VoicePicker;
    struct Geometry {
        int trackHeaderWidth;
        int pianoKeyboardWidth;
        int timelineSplitX;
        int editorDefaultPixelsPerBeat;
        int pianoRollInitialViewportHeight;
        int timelineMinimumPixelsPerBeat;
        int timelineMaximumPixelsPerBeat;
        int pianoRollMinimumKeyHeight;
        int pianoRollMaximumKeyHeight;
        int pianoRollDefaultKeyHeight;
        int timelineDetailMinimumPixelsPerBeat;
        int gridLineStrokeWidth;
        int automationGridMinimumCellWidth;
        qreal timelineRevealViewportFraction;
        int timelineViewportMinimumWidth;
        int timelineContentTailWidth;
        // Fixed heights of the SongView-owned ruler and other-events layout
        // rows.
        int rulerHeight;
        int otherEventsHeight;

        static Geometry resolve();
    };

    // Feeds the camera the geometry-derived zoom clamp bounds; call after
    // Geometry::resolve().
    void pushCameraGeometryLimits();
    // Feeds the grid the geometry-derived visible-grid detail floors; call
    // after Geometry::resolve().
    void pushGridGeometryThresholds();
    // Canonical band layout: resolve from parent-owned rectangles, compare,
    // store, then push synchronously to the Quick host and playhead overlay.
    songview::TimelineBandLayout resolveTimelineBandLayout() const;
    void synchronizeTimelineBandLayout();
    // Positions retained band chrome over parent-owned spacer rows.
    void positionBandWidgets();
    // Document remap handler: re-addresses all SongView-owned track state
    // before the following documentChanged rebuild.
    void onTracksRemapped(const TrackRemap &remap);
    // One path for all selection changes. Remapping an engine slot while it
    // still represents the same logical track is not a track transition.
    void transitionSelectedTrack(int newTrack);
    void transitionSelectedTrack(int newTrack, bool trackIdentityChanged);
    void updateScaleProjection();
    void buildOccupancySet(std::span<bool, 128> out) const;
    void rebuildProjectionWithAnchoring();
    // Fold-relevant model change (song swap, track switch): rebuild now, or
    // defer while a pointer gesture holds the projection lock.
    void requestProjectionRebuild();
    // Live pointer ownership across the QWidget ruler, roll interaction, and
    // every Quick timeline surface. Popup editing and follow-scroll pauses
    // deliberately are not pointer ownership.
    bool timelinePointerGestureActive() const;
    void syncTimelineIndicators();
    // Guards construction and teardown windows around the SongView-owned host.
    void requestPianoRollQuickUpdate(songview::PianoRollQuickDirtySet dirty);
    void syncTimelineQuickAppearance();

    void disconnectDocument();
    void notifyDrawerSongChanged();
    void notifyVelocityGestureChanged();
    void refreshDrawerPages();
    void refreshAutomationPage();
    void refreshVelocityPage();
    void refreshVoiceChangePage();
    void applyEditorViewStateToWidgets(bool drawerChanged);
    double minHScroll() const { return m_camera.minHScroll(); }
    double maxHScroll() const { return m_camera.maxHScroll(); }
    // Camera-tail fan-out (QML scrollbar notification + redraw) shared by
    // the scroll wrappers and paths that mutate the camera directly.
    void syncHorizontalCamera(bool cameraChanged);
    void syncVerticalCamera(bool cameraChanged);
    double maxRollScroll() const { return m_camera.maxRollScroll(); }
    double defaultVerticalScroll() const;
    void updateScrollbars();
    void rebuildAfterSongChange();
    // Captures the input epoch at the originating header event. Cancellation
    // advances it, dropping stale document mutations without reordering live ones.
    template <typename Mutation>
    void queueHeaderMutation(Mutation &&mutation)
    {
        const uint64_t generation = m_transientInputGeneration;
        QMetaObject::invokeMethod(
            this,
            [this, generation, mutation = std::forward<Mutation>(mutation)] {
                if (generation == m_transientInputGeneration)
                    mutation();
            },
            Qt::QueuedConnection);
    }
    // RAII bracket for one committed roll mutation: construction installs
    // the dirty classification for the mutation's synchronous
    // documentChanged -> updateSong handoff, asserting no bracket is open;
    // destruction clears any hint the mutation did not consume, so an
    // early return or a no-emission document call cannot leak a stale hint
    // into a later updateSong. Not an update request — undo/redo and
    // non-roll edits open no bracket and get the generic replacement union.
    class DocumentSwapHintScope
    {
      public:
        DocumentSwapHintScope(SongView &owner, songview::PianoRollQuickDirtySet dirty);
        ~DocumentSwapHintScope();
        Q_DISABLE_COPY_MOVE(DocumentSwapHintScope)

      private:
        SongView &m_owner;
    };
    // Taken exactly once by updateSong; installed by DocumentSwapHintScope.
    songview::PianoRollQuickDirtySet takeDocumentSwapHint();
    struct TimeScopeResolution {
        SongDocument::TimeScope scope;
        QString label;
    };
    void coordinateSelectionChange(
        const songview::EditorSelectionModel::SelectionTransition &transition);
    std::optional<TimeScopeResolution> resolveTimeSelectionScope() const;
    // Engine tracks a track-scoped time selection resolves to (used and
    // document-mapped), and the copyable lane identities of one track (its
    // model lanes plus the voice changes).
    std::vector<int> timeSelectionTracks() const;
    std::vector<uint8_t> trackCcs(int track) const;
    // The TimeScope a range command gathers over: the selection's lane list
    // for a Lanes selection, or the scoped tracks with their full per-track
    // lane list (model lanes + voice) for a Tracks selection, with the tempo
    // row gated exactly as the copy/delete/nudge commands always gated it.
    // Nullopt when the selection resolves to nothing (no lanes/tempo, or no
    // document-mapped tracks).
    std::optional<SongDocument::TimeScope> timeSelectionScope() const;
    struct PendingInsertTimePrompt {
        QPointer<SongDocument> document;
        uint64_t documentRevision = 0;
        uint64_t cursorTick = 0;
        uint64_t beatTicks = 1;
        uint64_t beatsPerBar = 4;
        int initialBars = 1;
        int initialBeats = 0;
        int initialBeatFractions = 0;
    };
    void openInsertTimePrompt(uint64_t cursorTick, const songview::Grid::Segment &segment);
    void clearInsertTimePrompt(bool restoreFocus);
    void cancelInsertTimePromptWithoutFocus();
    struct PendingVoicePicker {
        QPointer<QObject> context;
        // The session this picker's form lives on; disposal always targets
        // this pinned owner, never the session current at dispose time.
        QPointer<songview::QuickPopupSession> session;
        QPointer<SongDocument> document;
        uint64_t documentRevision = 0;
        std::function<void(int)> accepted;
        songview::TimelineBand origin = songview::TimelineBand::Roll;
    };
    void clearVoicePicker(bool restoreFocus);
    bool isCurrentVoicePicker(const songview::VoicePicker *picker) const
    {
        return m_voicePicker == picker;
    }
    std::optional<PendingVoicePicker> m_pendingVoicePicker;
    QMetaObject::Connection m_voicePickerCancellation;
    songview::VoicePicker *m_voicePicker = nullptr;
    std::optional<songview::Clip> readClipboardClip();

    // The selection snapshot taken when the shared time-selection menu
    // opened, held through the session close until activation consumes it.
    // Document identity plus revision and exact selection equality make a
    // stale target a silent no-write.
    struct PendingTimeSelectionMenu {
        SongDocument *document = nullptr;
        uint64_t documentRevision = 0;
        songview::EditorSelectionModel::TimeSelection selection;
        songview::TrackMask trackScope = 0;
    };
    // Pure builder: rows, order, shortcut text, and build-time paste
    // enablement exactly as the former native menu.
    std::vector<songview::QuickMenuItem> buildTimeSelectionItems() const;
    // QuickMenuModel::activated() sink; consumes the pending target, runs
    // the owner command after the session already closed, then returns
    // focus to the active surface.
    void handleTimeSelectionAction(int actionId);
    // Binds the menu host and the dismissal-focus sink to the shared
    // canvas popup session (one session per view lifetime).
    void bindTimeSelectionMenuSession(songview::QuickPopupSession *session);
    // Song swap / readiness loss / teardown: dismiss without focus return.
    void cancelTimeSelectionMenuWithoutFocus();
    songview::QuickMenuHost *m_timeSelectionMenuHost = nullptr;
    songview::QuickMenuModel *m_timeSelectionMenuModel = nullptr;
    QPointer<songview::QuickPopupSession> m_timeSelectionMenuSession;
    std::optional<PendingTimeSelectionMenu> m_pendingTimeSelectionMenu;
    // Open flag owned by SongView alone: the host tears down before the
    // shared session's cancelled(restoreFocus) signal arrives, so ownership
    // of a dismissed session cannot be re-derived at signal time.
    bool m_timeSelectionMenuOpen = false;

    songview::TimeAxis m_timeAxis;            // musical time; fallback until a song binds
    const MidiTimeline *m_timeline = nullptr; // loaded content only
    const LoadedVoiceGroup *m_voicegroup = nullptr;
    SongDocument *m_document = nullptr;
    uint64_t m_transientInputGeneration = 0; // advanced only by cancelTransientInput()
    SongViewModel m_model;
    songview::EditorSelectionModel m_selectionModel;
    Geometry m_geometry;
    songview::PitchProjection m_projection;
    songview::ScaleController m_scaleController;
    bool m_projectionLocked = false; // pointer gesture holds fold row geometry stable
    bool m_projectionDirty = false;  // fold-relevant change deferred by the lock
    // Consumed by the next updateSong; installed by DocumentSwapHintScope.
    std::optional<songview::PianoRollQuickDirtySet> m_documentSwapHint;

    songview::TimeCamera m_camera; // zoom/scroll state over m_timeAxis + m_projection
    songview::Grid m_grid;         // zoom-adaptive grid state over m_timeAxis + m_camera
    double m_playheadTick = 0.0;
    uint64_t m_editCursorTick = 0;
    bool m_playing = false;
    std::optional<PendingInsertTimePrompt> m_pendingInsertTimePrompt;
    QMetaObject::Connection m_insertTimePromptCancellation;
    uint32_t m_muteMask = 0;
    uint32_t m_soloMask = 0;
    bool m_velocityColorMode = false; // velocityNoteColor fills (View menu)
    bool m_noteNameMode = false;      // pitch labels on notes (View menu)
    bool m_followPlayhead = true;     // playback follow-scroll (transport bar)
    TrackActivity m_trackActivity;

    EditorViewState m_editorViewState;
    EditorDrawer *m_editorDrawer = nullptr;
    SharedShortcutOwner m_sharedShortcutOwner = SharedShortcutOwner::SongView;
    bool m_followScrollPaused = false;
    VelocityGestureModel m_velocityGesture;
    std::unique_ptr<songview::TimeRuler> m_ruler;
    songview::TrackHeaderModel *m_headers = nullptr;
    songview::PianoRoll *m_roll = nullptr;
    QPointer<songview::TimelineQuickView> m_quickView;
    songview::PlayheadOverlay *m_playheadOverlay = nullptr;
    songview::TimelineBandLayout m_timelineBandLayout;
    QStackedWidget *m_rollStack = nullptr; // page 0: roll placeholder, page 1:
                                           // event-list placeholder (the list
                                           // renders through the Quick host)
    EventListController *m_events = nullptr;
    songview::OtherStrip *m_strip = nullptr;
    QSpacerItem *m_rulerSpacer = nullptr;  // owns the ruler row height
    QSpacerItem *m_headerSpacer = nullptr; // reserves the Quick header column
    QSpacerItem *m_stripSpacer = nullptr;  // owns the other-events row height
    QSpacerItem *m_hbarSpacer = nullptr;   // owns the QML scrollbar row height
};
