#include "songview.h"
#include "core/songdocument.h"
#include "layout.h"
#include "songview/detail.h"
#include "theme/themeruntime.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/eventlistview.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheaderpanel.h"

#include <QEvent>
#include <QFrame>
#include <QHBoxLayout>
#include <QKeyEvent>
#include <QResizeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QSizePolicy>
#include <QSpacerItem>
#include <QStackedWidget>
#include <QVBoxLayout>

#include <algorithm>
#include <cstdint>
#include <span>
#include <utility>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;
} // namespace songview

// ------------------------------------------------------------------ SongView

using namespace songview;

SongView::Geometry SongView::Geometry::resolve()
{
    const int trackHeaderWidth = lyt::fontPx(17.5);
    const int pianoKeyboardWidth = lyt::fontPx(13.0 / 3.0);
    return {trackHeaderWidth,
            pianoKeyboardWidth,
            lyt::fontPx(17.5 + 13.0 / 3.0),
            lyt::fontPx(8.0 / 3.0),
            lyt::fontPx(50.0 / 3.0),
            lyt::fontPx(1.0 / 3.0),
            lyt::fontPx(160.0 / 3.0),
            lyt::fontPx(1.0 / 3.0),
            lyt::fontPx(8.0 / 3.0),
            lyt::fontPx(1.0),
            lyt::fontPx(5.0 / 6.0),
            lyt::fontPx(1.0 / 6.0),
            lyt::fontPx(4.0 / 3.0),
            1.0 / 3.0,
            lyt::fontPx(25.0 / 6.0),
            lyt::fontPx(25.0 / 3.0)};
}

SongView::ViewState::ViewState()
{
    const Geometry geometry = Geometry::resolve();
    pxPerBeat = geometry.editorDefaultPixelsPerBeat;
    keyHeight = geometry.velocityHandleMinimumKeyHeight;
}

void SongView::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    m_keyHeight = std::clamp(m_keyHeight, double(m_geometry.pianoRollMinimumKeyHeight),
                             double(m_geometry.pianoRollMaximumKeyHeight));
    if (m_headerScroll)
        m_headerScroll->setFixedWidth(m_geometry.trackHeaderWidth);
    if (m_hbarGutter) {
        m_hbarGutter->changeSize(m_geometry.plotOrigin, lyt::space(Space::Zero), QSizePolicy::Fixed,
                                 QSizePolicy::Minimum);
        m_hbarRow->invalidate();
    }
    if (m_playheadOverlay) {
        delete m_playheadOverlay;
        auto bands = timelineBands();
        for (const songview::TimelineBand &band : bands)
            themes::registerGridLineRefreshTarget(band.widget);
        m_playheadOverlay = new PlayheadOverlay(this, std::move(bands));
    }
    updateScrollbars();
    refreshTimelineViews();
    refreshDrawerPages();
}

std::vector<songview::TimelineBand> SongView::timelineBands() noexcept
{
    return {
        {*m_ruler, m_geometry.plotOrigin},
        {*m_roll, m_geometry.pianoKeyboardWidth},
        {*m_editorDrawer->automationPage()->canvas(), m_geometry.plotOrigin},
        {*m_editorDrawer->velocityArea(), m_editorDrawer->velocityArea()->plotOrigin()},
        {*m_strip, m_geometry.plotOrigin},
    };
}

SongView::SongView(QWidget *parent)
    : QWidget(parent)
    , m_geometry(Geometry::resolve())
    , m_keyHeight(m_geometry.velocityHandleMinimumKeyHeight)
{
    // Prime the default C-major classification (the previous controller
    // constructor did this); touch no widgets.
    updateScaleProjection();

    auto *vbox = new QVBoxLayout(this);
    vbox->setContentsMargins(lyt::space(Space::Zero), lyt::space(Space::Zero),
                             lyt::space(Space::Zero), lyt::space(Space::Zero));
    vbox->setSpacing(lyt::space(Space::Zero));

    m_ruler = new TimeRuler(this);
    vbox->addWidget(m_ruler);

    auto *rollPane = new QWidget(this);
    auto *mid = new QHBoxLayout(rollPane);
    mid->setContentsMargins(lyt::space(Space::Zero), lyt::space(Space::Zero),
                            lyt::space(Space::Zero), lyt::space(Space::Zero));
    mid->setSpacing(lyt::space(Space::Zero));
    m_headerScroll = new QScrollArea(rollPane);
    m_headerScroll->setFixedWidth(m_geometry.trackHeaderWidth);
    m_headerScroll->setFrameShape(QFrame::NoFrame);
    m_headerScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_headerScroll->setWidgetResizable(true);
    m_headerScroll->setFocusPolicy(Qt::NoFocus);
    m_headers = new TrackHeaderPanel(this);
    m_headerScroll->setWidget(m_headers);
    mid->addWidget(m_headerScroll);

    m_rollStack = new QStackedWidget(rollPane);
    auto *rollPage = new QWidget(m_rollStack);
    auto *rollBox = new QHBoxLayout(rollPage);
    rollBox->setContentsMargins(lyt::space(Space::Zero), lyt::space(Space::Zero),
                                lyt::space(Space::Zero), lyt::space(Space::Zero));
    rollBox->setSpacing(lyt::space(Space::Zero));
    m_roll = new PianoRoll(this);
    rollBox->addWidget(m_roll, 1);
    m_vbar = new QScrollBar(Qt::Vertical, rollPage);
    ::layout::configureListPositionIndicator(*m_vbar);
    m_vbar->setSingleStep(kScrollUnitsPerDip);
    rollBox->addWidget(m_vbar);
    m_rollStack->addWidget(rollPage);
    m_events = new EventListView(this);
    m_rollStack->addWidget(m_events);
    mid->addWidget(m_rollStack, 1);
    vbox->addWidget(rollPane, 1);

    m_strip = new OtherStrip(this);
    vbox->addWidget(m_strip);
    m_hbar = new QScrollBar(Qt::Horizontal, this);
    m_hbar->setSingleStep(kScrollUnitsPerDip);
    m_hbarRow = new QHBoxLayout;
    m_hbarGutter = new QSpacerItem(m_geometry.plotOrigin, lyt::space(Space::Zero),
                                   QSizePolicy::Fixed, QSizePolicy::Minimum);
    m_hbarRow->addItem(m_hbarGutter);
    m_hbarRow->addWidget(m_hbar);
    vbox->addLayout(m_hbarRow);

    m_editorDrawer = new EditorDrawer(*this, rollPane, m_editorViewState);
    m_selectionModel.setObserver(
        [this](const songview::EditorSelectionModel::SelectionTransition &transition) {
            coordinateSelectionChange(transition);
        });

    auto bands = timelineBands();
    for (const songview::TimelineBand &band : bands)
        themes::registerGridLineRefreshTarget(band.widget);
    m_playheadOverlay = new PlayheadOverlay(this, std::move(bands));

    connect(m_hbar, &QScrollBar::valueChanged, this,
            [this](int value) { setHScroll(scrollDips(value)); });
    connect(m_vbar, &QScrollBar::valueChanged, this,
            [this](int value) { setVScroll(scrollDips(value)); });
}
bool SongView::advanceTrackActivity(const TrackActivityLevels &levels, float elapsedSeconds,
                                    bool playing)
{
    const bool activityAnimating = m_trackActivity.advance(levels, elapsedSeconds, playing);
    m_headers->syncActivity(m_trackActivity, playing);
    return activityAnimating;
}

void SongView::setSong(const MidiTimeline *timeline, const LoadedVoiceGroup *voicegroup)
{
    if (m_roll)
        m_roll->cancelPitchBendPopup();
    cancelActiveInteractions();
    if (timeline)
        m_trackActivity.resetPaused();
    else
        m_trackActivity.reset();
    m_timeline = timeline;
    m_voicegroup = voicegroup;
    m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
    m_editorViewState = {};
    m_muteMask = 0;
    m_soloMask = 0;
    emit muteMaskChanged(0);
    emit soloMaskChanged(0);
    m_playheadTick = 0.0;
    m_editCursorTick = 0;
    m_playing = false;
    // Fresh songs open at the camera's home position, pre-roll pad showing.
    m_scrollX = minHScroll();
    m_events->setPlayheadTick(-1.0, false); // another song's ticks are stale
    // Song attachment resets lane cosmetics. MainWindow reapplies the
    // application-wide drawer chrome after loading any sidecar.
    m_gridFeel = GridFeel::Straight;
    m_gridMinDenom = 0;
    m_ruler->syncGridControls();

    int firstUsedTrack = 0;
    if (timeline) {
        for (int track = 0; track < 16; ++track) {
            if (timeline->tracks[track].used) {
                firstUsedTrack = track;
                break;
            }
        }
    }
    m_selectionModel.resetForSongSwap(firstUsedTrack);
    if (m_editorDrawer)
        m_editorDrawer->setViewState(m_editorViewState);
    updateScaleProjection();

    rebuildAfterSongChange();
    m_headers->syncActivity(m_trackActivity, false);
}

void SongView::rebuildAfterSongChange()
{
    double initialScrollY = 0.0;
    if (m_timeline) {
        // Default zoom uses the resolved editor scale, scrolled so the notes'
        // pitch range is centered in the roll.
        m_pxPerTick = m_geometry.editorDefaultPixelsPerBeat / double(m_timeline->ticksPerBeat);
        const int midKey = m_model.minNoteKey <= m_model.maxNoteKey
                               ? (m_model.minNoteKey + m_model.maxNoteKey) / 2
                               : 60;
        const int centerPitch = m_projection.nearestVisiblePitch(midKey);
        const int centerRow = m_projection.rowForPitch(centerPitch);
        if (centerRow != songview::PitchProjection::cHiddenRow) {
            initialScrollY = std::max(
                0.0, centerRow * m_keyHeight -
                         std::max(m_geometry.pianoRollInitialViewportHeight, rollViewportHeight()) /
                             2.0);
        }
    } else {
        m_pxPerTick = 1.0;
    }
    m_headers->rebuild();
    notifyDrawerSongChanged();
    updateScrollbars();
    setVScroll(initialScrollY);
    refreshTimelineViews();
}

void SongView::updateSong(const MidiTimeline *timeline)
{
    cancelActiveInteractions();
    m_timeline = timeline;
    m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
    // The concrete automation page owns cosmetic empty lanes; the projection
    // remains solely the timeline model.

    if (timeline && !timeline->tracks[m_selectionModel.primaryTrack()].used) {
        // The edited track disappeared (e.g. undo of its only events).
        int fallback = 0;
        for (int track = 0; track < 16; ++track) {
            if (timeline->tracks[track].used) {
                fallback = track;
                break;
            }
        }
        transitionSelectedTrack(fallback);
    }

    // Keep only opaque identities still projected on the selected track.
    std::vector<NoteId> validIds;
    for (const ViewNote &note : m_model.notes) {
        if (note.track == m_selectionModel.primaryTrack() && note.noteId.isAssigned())
            validIds.push_back(note.noteId);
    }
    m_selectionModel.reconcileNoteSelection(std::span<const NoteId>(validIds));
    m_headers->rebuild();
    notifyDrawerSongChanged();
    if (m_scaleController.scaleFold()) {
        requestProjectionRebuild();
    } else {
        updateScrollbars();
    }
    refreshTimelineViews();
}

void SongView::setDocument(SongDocument *document)
{
    if (m_document != document) {
        if (m_roll)
            m_roll->cancelPitchBendPopup();
        cancelActiveInteractions();
        if (m_document) {
            disconnect(m_document, &SongDocument::tracksRemapped, this, nullptr);
            disconnect(m_document, &SongDocument::documentChanged, this, nullptr);
        }
        if (document) {
            connect(document, &SongDocument::tracksRemapped, this, &SongView::onTracksRemapped);
            connect(document, &SongDocument::documentChanged, this, [this] {
                // Any document edit invalidates a preview captured at the
                // previous revision before the normal page refresh.
                cancelActiveInteractions();
                m_editorDrawer->automationPage()->documentChanged();
                m_editorDrawer->velocityArea()->documentChanged();
                refreshDrawerPages();
            });
        }
    }
    m_document = document;
    m_events->setDocument(document);
    m_selectionModel.clearNoteSelection();
    m_headers->rebuild();
    notifyDrawerSongChanged();
}

bool SongView::eventListVisible() const
{
    return m_rollStack->currentIndex() == 1;
}

void SongView::setEventListVisible(bool visible)
{
    if (eventListVisible() == visible)
        return;
    m_rollStack->setCurrentIndex(visible ? 1 : 0);
    if (visible) {
        // The list skips refreshes while hidden; catch up when shown.
        m_events->refresh();
        m_events->syncTrackSelection();
    }
    focusContent();
    emit eventListVisibilityChanged(visible);
}

void SongView::focusContent()
{
    if (eventListVisible())
        m_events->setFocus();
    else
        m_roll->setFocus();
}

void SongView::focusActiveSurface()
{
    if (hasVisibleDrawerSection())
        m_editorDrawer->focusVisiblePage();
    else
        focusContent();
}

void SongView::setFollowScrollPaused(bool paused)
{
    m_followScrollPaused = paused;
}

SongView::ViewState SongView::viewState() const
{
    ViewState state;
    if (!m_timeline)
        return state;
    state.valid = true;
    state.pxPerBeat = m_pxPerTick * double(m_timeline->ticksPerBeat);
    state.keyHeight = m_keyHeight;
    state.scrollPx = m_scrollX;
    state.scrollY = m_scrollY;
    state.selectedTrack = m_selectionModel.primaryTrack();
    state.editCursorTick = m_editCursorTick;
    state.gridMinDenom = m_gridMinDenom;
    state.gridTriplet = m_gridFeel == GridFeel::Triplet;
    state.eventList = eventListVisible();
    return state;
}

void SongView::applyViewState(const ViewState &state)
{
    if (!state.valid || !m_timeline)
        return;
    const int gridMinDenom = state.gridMinDenom == 4 || state.gridMinDenom == 8 ||
                                     state.gridMinDenom == 16 || state.gridMinDenom == 32
                                 ? state.gridMinDenom
                                 : 0;
    const GridFeel gridFeel = state.gridTriplet ? GridFeel::Triplet : GridFeel::Straight;
    const double pxPerTick =
        std::clamp(state.pxPerBeat, double(m_geometry.timelineMinimumPixelsPerBeat),
                   double(m_geometry.timelineMaximumPixelsPerBeat)) /
        double(m_timeline->ticksPerBeat);
    if ((pxPerTick != m_pxPerTick || gridMinDenom != m_gridMinDenom || gridFeel != m_gridFeel) &&
        m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    m_pxPerTick = pxPerTick;
    m_keyHeight = std::clamp(state.keyHeight, double(m_geometry.pianoRollMinimumKeyHeight),
                             double(m_geometry.pianoRollMaximumKeyHeight));
    m_roll->refreshTextLayout();
    setGridMinDenom(state.gridMinDenom); // setter validates the denominator
    setGridFeel(state.gridTriplet ? GridFeel::Triplet : GridFeel::Straight);
    m_editCursorTick = std::min<uint64_t>(state.editCursorTick, m_timeline->lengthTicks);
    if (state.selectedTrack >= 0 && state.selectedTrack < 16 &&
        m_timeline->tracks[state.selectedTrack].used)
        selectTrack(state.selectedTrack);
    updateScrollbars();
    setHScroll(state.scrollPx); // setHScroll clamps to the camera's range
    setVScroll(state.scrollY);
    setEventListVisible(state.eventList);
    refreshTimelineViews();
}

void SongView::setVoicegroup(const LoadedVoiceGroup *voicegroup)
{
    if (m_voicegroup == voicegroup)
        return;
    cancelActiveInteractions();
    m_voicegroup = voicegroup;
    m_headers->rebuild();
    notifyDrawerSongChanged();
    refreshTimelineViews();
}

void SongView::coordinateSelectionChange(
    const songview::EditorSelectionModel::SelectionTransition &transition)
{
    const uint32_t bits = static_cast<uint32_t>(transition.changes);
    const auto changed = [bits](songview::EditorSelectionModel::SelectionChange category) {
        return (bits & static_cast<uint32_t>(category)) != 0;
    };
    const bool primaryChanged =
        changed(songview::EditorSelectionModel::SelectionChange::PrimaryTrack);
    const bool trackScopeChanged =
        changed(songview::EditorSelectionModel::SelectionChange::TrackScope);
    const bool noteSelectionChanged =
        changed(songview::EditorSelectionModel::SelectionChange::NoteSelection);
    const bool timeSelectionChanged =
        changed(songview::EditorSelectionModel::SelectionChange::TimeSelection);
    bool rollFullyInvalidated = false;
    bool timelineViewsRefreshed = false;
    if (primaryChanged) {
        m_headers->syncSelection();
        if (m_roll)
            m_roll->setFocus();
        if (m_scaleController.scaleFold()) {
            rebuildProjectionWithAnchoring();
        } else {
            m_roll->invalidateContent();
        }
        rollFullyInvalidated = true;
        emit selectedTrackChanged(m_selectionModel.primaryTrack());
    } else if (trackScopeChanged) {
        m_headers->syncSelection();
        refreshTimelineViews();
        rollFullyInvalidated = true;
        timelineViewsRefreshed = true;
    }
    if (noteSelectionChanged) {
        if (!rollFullyInvalidated) {
            m_roll->invalidateContent();
            rollFullyInvalidated = true;
        }
        refreshVelocityPage();
    }
    if (timeSelectionChanged) {
        if (!timelineViewsRefreshed) {
            m_ruler->update();
            if (!rollFullyInvalidated) {
                const uint32_t usedTracks = usedTrackMask(m_timeline);
                const uint32_t previousTracks =
                    transition.previousTrackTime.trackScope & usedTracks;
                const uint32_t tracks = transition.trackTime.trackScope & usedTracks;
                m_roll->invalidateTimeSelection(
                    {transition.previousTrackTime.startTick, transition.previousTrackTime.endTick},
                    previousTracks, {transition.trackTime.startTick, transition.trackTime.endTick},
                    tracks);
            }
            m_strip->invalidateContent();
            syncPlayheadOverlay();
        }
        refreshAutomationPage();
    }
    if (primaryChanged || trackScopeChanged)
        refreshDrawerPages();
}

bool SongView::event(QEvent *event)
{
    const bool shown = event->type() == QEvent::Show;
    if (event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate ||
        event->type() == QEvent::UngrabMouse) {
        cancelActiveInteractions();
    } else if (event->type() == QEvent::KeyPress) {
        auto *keyEvent = static_cast<QKeyEvent *>(event);
        if (keyEvent->key() == Qt::Key_Escape)
            cancelActiveInteractions();
        // Drawer canvases pass unclaimed keys up to their SongView parent.
        if (handleEditKey(keyEvent))
            return true;
    }
    const bool handled = QWidget::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}
void SongView::copySelection()
{
    if (m_selectionModel.timeSelection().active())
        copyTimeSelection();
    else
        m_roll->copySelectedNotes();
}

void SongView::setPlayheadSample(uint64_t samplePos, bool playing)
{
    if (!m_timeline)
        return;
    const bool drawerVisible = hasVisibleDrawerSection();
    const auto visibleDrawerContext = [this] {
        const uint64_t tick = m_playing ? static_cast<uint64_t>(std::max(0.0, m_playheadTick) + 0.5)
                                        : m_editCursorTick;
        return voiceContext(tick);
    };
    const DrawerPageVoiceContext contextBefore =
        drawerVisible ? visibleDrawerContext() : DrawerPageVoiceContext{};
    m_playheadTick = m_timeline->tickForSample(samplePos);
    m_playing = playing;
    const DrawerPageVoiceContext contextAfter =
        drawerVisible ? visibleDrawerContext() : DrawerPageVoiceContext{};
    // Follow the playhead — unless following is switched off (transport
    // bar), and never while the user is mid-gesture (panning, dragging notes
    // or selections, sweeping automation): yanking the view out from under a
    // held mouse button is disorienting.
    if (playing && m_followPlayhead && !m_followScrollPaused && !userGestureActive()) {
        const qreal px = contentX(m_playheadTick);
        const qreal vw = viewportWidth();
        if (px < 0.0 || px > vw * 85.0 / 100.0)
            setHScroll(m_playheadTick * m_pxPerTick - vw / 10.0);
    }
    m_events->setPlayheadTick(m_playheadTick, playing);
    m_headers->syncVoices();
    if (drawerVisible && (contextBefore.voice != contextAfter.voice ||
                          contextBefore.voiceSlot != contextAfter.voiceSlot)) {
        refreshDrawerPages();
    }
    if (m_editorDrawer->pageVisible(EditorDrawerPage::Velocity))
        m_editorDrawer->velocityArea()->presentPlayhead(m_playheadTick);
    syncPlayheadOverlay();
}

bool SongView::userGestureActive() const
{
    return m_followScrollPaused || (m_ruler && m_ruler->gestureActive()) ||
           (m_roll && m_roll->gestureActive());
}

void SongView::syncPlayheadOverlay()
{
    if (m_playheadOverlay) {
        m_playheadOverlay->setPlayhead(contentX(m_playheadTick), m_timeline != nullptr, m_playing);
    }
}

void SongView::setEditCursorTick(uint64_t tick)
{
    if (m_editCursorTick == tick)
        return;
    m_editCursorTick = tick;
    m_headers->syncVoices();
    refreshTimelineViews();
    refreshDrawerPages();
}

void SongView::commitEditCursor(uint64_t tick)
{
    setEditCursorTick(tick);
    emit editCursorMoved(tick);
}

void SongView::goToStart()
{
    // Home shows the pre-roll pad so tick 0 sits inside the viewport, not
    // flush against its edge.
    setHScroll(minHScroll());
    commitEditCursor(0);
}

void SongView::refreshTimelineViews()
{
    m_ruler->update();
    m_roll->invalidateContent();
    m_strip->invalidateContent();
    syncPlayheadOverlay();
}

void SongView::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    updateScrollbars();
    refreshDrawerPages();
}
