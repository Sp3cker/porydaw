#include "songview.h"
#include "core/songdocument.h"
#include "layout.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview/editactions.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/retirehostmenu.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/songview/voicepicker.h"
#include "ui/typography.h"
#include <QEvent>
#include <QFontMetrics>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>

#include <algorithm>
#include <cstdint>
#include <span>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

// ------------------------------------------------------------------ SongView

using namespace songview;

namespace {

int resolveOtherEventsRowHeight()
{
    const QFont body = *typography::bodyFont();
    return QFontMetrics(body).height() + lyt::space(Space::Two);
}

// Fixed height of the QML horizontal scrollbar lane row.
int hbarRowHeight()
{
    return lyt::space(Space::Two);
}

} // namespace

SongView::Geometry SongView::Geometry::resolve()
{
    const int trackHeaderWidth = lyt::fontPx(17.5);
    const int pianoKeyboardWidth = lyt::fontPx(13.0 / 3.0);
    return {trackHeaderWidth,
            pianoKeyboardWidth,
            trackHeaderWidth + pianoKeyboardWidth,
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
            lyt::fontPx(25.0 / 3.0),
            TimeRuler::rowHeight(),
            resolveOtherEventsRowHeight()};
}

SongView::ViewState::ViewState()
{
    const Geometry geometry = Geometry::resolve();
    pxPerBeat = geometry.editorDefaultPixelsPerBeat;
    keyHeight = geometry.pianoRollDefaultKeyHeight;
}

void SongView::pushCameraGeometryLimits()
{
    m_camera.setLimits({double(m_geometry.timelineMinimumPixelsPerBeat),
                        double(m_geometry.timelineMaximumPixelsPerBeat),
                        double(m_geometry.pianoRollMinimumKeyHeight),
                        double(m_geometry.pianoRollMaximumKeyHeight),
                        m_geometry.timelineRevealViewportFraction});
}

void SongView::pushGridGeometryThresholds()
{
    m_grid.setThresholds(m_geometry.timelineDetailMinimumPixelsPerBeat,
                         m_geometry.automationGridMinimumCellWidth);
}

// Canonical band geometry, resolved only from the analytic viewport layout
// and the EditorDrawer's body rectangles: every published rect is the
// visible viewport-local band rectangle, so consumers (PlayheadOverlay)
// intersect the viewport alone and no widget walking is needed. The Quick
// window is the full canonical viewport, so no host translation happens
// here — TimelineQuickView publishes the rects as-is. Hidden bands stay
// nullopt.
TimelineBandLayout SongView::resolveTimelineBandLayout() const
{
    const ViewportGeometry viewport = resolveViewportGeometry();
    TimelineBandLayout layout;
    const auto publishBand = [&layout](TimelineBand band, const QRect &rect,
                                       const QRect &plotRect) {
        if (!rect.isEmpty())
            layout.geometry(band) = {rect, plotRect};
    };
    // Every time plot starts at the canonical split; only each band owner's
    // right edge (scrollbar, drawer viewport) differs.
    const auto plotFromSplit = [this](const QRect &rect) {
        return QRect(m_geometry.timelineSplitX, rect.y(),
                     std::max(0, rect.right() + 1 - m_geometry.timelineSplitX), rect.height());
    };
    // Shared breadth of the Quick-drawn scrollbar rows and columns.
    const int scrollbarBreadth = lyt::space(Space::Two);
    if (m_ruler)
        publishBand(TimelineBand::Ruler, viewport.ruler, plotFromSplit(viewport.ruler));
    // Fixed chrome: track headers carry no time plot.
    const QRect headerRect(0, viewport.rollPane.y(), m_geometry.trackHeaderWidth,
                           viewport.rollPane.height());
    publishBand(TimelineBand::TrackHeaders, headerRect, QRect());
    // The roll band is the roll pane's stack column minus the Quick-drawn
    // vertical scrollbar column and the drawer overlay. The overlay owns its
    // body and chrome, so the canonical roll ends immediately above it.
    // Nullopt while the event list replaces the roll page.
    if (!m_eventListVisible) {
        QRect rollRect = viewport.rollStack;
        rollRect.setWidth(std::max(0, rollRect.width() - scrollbarBreadth));
        if (m_editorDrawer) {
            const QRect overlay = m_editorDrawer->overlayRect();
            if (!overlay.isEmpty())
                rollRect.setBottom(std::min(rollRect.bottom(), overlay.top() - 1));
        }
        publishBand(TimelineBand::Roll, rollRect, plotFromSplit(rollRect));
    }
    publishBand(TimelineBand::OtherEvents, viewport.otherEvents,
                plotFromSplit(viewport.otherEvents));
    if (const std::optional<QRect> body = m_editorDrawer->bodyRect(EditorDrawerPage::Automations)) {
        // The band is the lane viewport: the drawer body minus the left
        // scrollbar column; the canvas plot origin drops the same column, so
        // the Quick plot stays aligned with the piano grid.
        const int bandWidth = std::max(0, body->width() - scrollbarBreadth);
        const QRect band(body->x() + scrollbarBreadth, body->y(), bandWidth, body->height());
        publishBand(TimelineBand::Automation, band, plotFromSplit(band));
    }
    if (const std::optional<QRect> body = m_editorDrawer->bodyRect(EditorDrawerPage::Velocity))
        publishBand(TimelineBand::Velocity, *body, plotFromSplit(*body));
    if (const std::optional<QRect> body = m_editorDrawer->bodyRect(EditorDrawerPage::VoiceChanges))
        publishBand(TimelineBand::VoiceChanges, *body, plotFromSplit(*body));
    return layout;
}

// Canonical scrollbar lanes for the QML controls: the horizontal row is the
// fixed bottom lane right of the split, and the vertical column sits
// directly right of the canonical (drawer-clipped) roll band. Empty means
// the lane is absent.
QRect SongView::horizontalScrollbarRect() const
{
    const ViewportGeometry viewport = resolveViewportGeometry();
    return {m_geometry.timelineSplitX, viewport.hbarRow.y(),
            std::max(0, viewport.width - m_geometry.timelineSplitX), viewport.hbarRow.height()};
}

QRect SongView::verticalScrollbarRect() const
{
    const std::optional<songview::TimelineBandGeometry> &roll =
        m_timelineBandLayout.geometry(songview::TimelineBand::Roll);
    if (!roll)
        return {};
    return {roll->rect.right() + 1, roll->rect.top(), lyt::space(Space::Two), roll->rect.height()};
}

// EventList mode replaces the roll band with the Quick event page in the
// same screen space. This canonical viewport rectangle is the roll pane's
// stack column; empty while hidden.
QRect SongView::eventListRect() const
{
    if (!m_eventListVisible)
        return {};
    return resolveViewportGeometry().rollStack;
}

// Fixed resolve → compare → store → push sequence for the canonical band
// layout. A private, synchronous, SongView-owned handoff: no Qt signal, and
// an unchanged value publishes nothing.
void SongView::synchronizeTimelineBandLayout()
{
    const TimelineBandLayout layout = resolveTimelineBandLayout();
    if (layout == m_timelineBandLayout)
        return;
    m_timelineBandLayout = layout;
    if (m_quickView)
        m_quickView->setBandLayout(m_timelineBandLayout);
    if (m_playheadOverlay)
        m_playheadOverlay->updateBands(m_timelineBandLayout);
}

// Analytic viewport layout: fixed font-metric rows pin the top and bottom
// and the stretch roll pane fills the middle. The Quick window IS the
// canonical viewport, so its live size resolves every former spacer/stack
// rectangle directly; a not-yet-framed window yields empty rows and no
// bands.
SongView::ViewportGeometry SongView::resolveViewportGeometry() const
{
    ViewportGeometry viewport;
    const QQuickWindow *window = m_quickView ? m_quickView->quickWindow() : nullptr;
    if (!window)
        return viewport;
    const int viewportWidth = window->width();
    const int viewportHeight = window->height();
    const int hbarH = hbarRowHeight();
    const int rollPaneTop = m_geometry.rulerHeight;
    const int rollPaneHeight =
        std::max(0, viewportHeight - rollPaneTop - m_geometry.otherEventsHeight - hbarH);
    viewport.width = viewportWidth;
    viewport.ruler = {0, 0, viewportWidth, rollPaneTop};
    viewport.rollPane = {0, rollPaneTop, viewportWidth, rollPaneHeight};
    viewport.rollStack = {m_geometry.trackHeaderWidth, rollPaneTop,
                          std::max(0, viewportWidth - m_geometry.trackHeaderWidth), rollPaneHeight};
    const int otherEventsTop = rollPaneTop + rollPaneHeight;
    viewport.otherEvents = {0, otherEventsTop, viewportWidth, m_geometry.otherEventsHeight};
    viewport.hbarRow = {0, otherEventsTop + m_geometry.otherEventsHeight, viewportWidth, hbarH};
    return viewport;
}

// Pushes the analytic roll-pane rectangle to the drawer host bounds; the
// drawer arranges its sections and re-synchronizes the band layout from it.
void SongView::layoutViewport()
{
    if (m_editorDrawer)
        m_editorDrawer->setHostBounds(resolveViewportGeometry().rollPane);
}

// One choreography for every Quick viewport change (resize, DPR, screen):
// the former resizeEvent plus the former Show/WinIdChange/DPR republish.
// The canonical refresh stays resolve/compare/store/push; both consumers
// then republish unconditionally so equal values still land after a
// surface swap.
void SongView::refreshViewportLayout()
{
    layoutViewport();
    updateScrollbars();
    refreshDrawerPages();
    syncTimelineIndicators();
    synchronizeTimelineBandLayout();
    if (m_quickView)
        m_quickView->refreshBandLayout();
    if (m_playheadOverlay)
        m_playheadOverlay->updateBands(m_timelineBandLayout);
}

SongView::SongView(QObject *parent)
    : QObject(parent)
    , m_geometry(Geometry::resolve())
    , m_camera(m_timeAxis, m_projection)
    , m_grid(m_timeAxis, m_camera)
{
    pushCameraGeometryLimits();
    pushGridGeometryThresholds();
    m_camera.setTimeZoom(m_geometry.editorDefaultPixelsPerBeat);
    m_camera.setKeyHeight(m_geometry.pianoRollDefaultKeyHeight);

    // Prime the default C-major classification (the previous controller
    // constructor did this); no UI exists yet.
    updateScaleProjection();

    m_ruler = std::make_unique<TimeRuler>(*this);
    m_headers = new TrackHeaderModel(*this, this);
    m_roll = new PianoRoll(this);
    m_strip = new OtherStrip(*this);

    m_editorDrawer = new EditorDrawer(*this, m_editorViewState);
    m_events = new EventListController(this, this);
    // Event-list row interactions surface through SongView's continuations:
    // status-bar announcements and jump-from-context voice reveal.
    connect(m_events, &EventListController::announce, this, &SongView::announce);
    connect(m_events, &EventListController::revealVoice, this, &SongView::revealVoice);
    m_quickView =
        new TimelineQuickView(*m_ruler, *m_roll, *m_strip, *m_editorDrawer->automationPage(),
                              *m_editorDrawer->velocityArea(), *m_editorDrawer->voiceChangeArea(),
                              m_editorDrawer->chrome(), *m_headers, *m_events, *this);
    // The pencil-shortcut guard identifies Quick input targets through the
    // shared host's window; injected before any timeline input can arrive.
    m_editorDrawer->automationPage()->setInputWindow(m_quickView->quickWindow());
    // Reparenting converted interactions after the Quick host keeps them
    // alive while its destructor detaches their input items. The roll
    // interaction joins the same tail as a plain QObject attached to
    // timelineRollInput; the automation page is its only scroll store.
    m_editorDrawer->automationPage()->setParent(this);
    m_editorDrawer->velocityArea()->setParent(this);
    m_editorDrawer->voiceChangeArea()->setParent(this);
    m_editorDrawer->chrome().setParent(this);
    m_strip->setParent(this);
    m_roll->setParent(this);
    // Shared time-selection context menu (roll + drawer): a typed host over
    // the canvas popup session, bound lazily on first open. Every row is an
    // action projection triggered through the host, so activation arrives as
    // actionActivated() — used only for terminal focus completion, and only
    // when no follow-on popup already owns the session.
    m_timeSelectionMenuHost = new songview::QuickMenuHost(this);
    m_timeSelectionMenuModel = new songview::QuickMenuModel(this);
    connect(m_timeSelectionMenuHost, &songview::QuickMenuHost::actionActivated, this,
            [this](QAction *) {
                songview::restoreFocusUnlessFormOpen(*this, [this] { focusActiveSurface(); });
            });
    // Selection/document/cursor transitions retire only this menu: the open
    // session must belong to this host AND be rooted at the time-selection
    // model, so foreign forms sharing the session keep their independent
    // lifetimes.
    connect(this, &SongView::contextMenusInvalidated, this, [this](bool restoreFocus) {
        songview::TimelineQuickView *const quick = quickView();
        songview::retireHostMenu(quick ? quick->popupSession() : nullptr, m_timeSelectionMenuHost,
                                 m_timeSelectionMenuModel, restoreFocus);
    });
    m_playheadOverlay = new PlayheadOverlay(*this, timelineBandLayout());
    m_selectionModel.setObserver(
        [this](const songview::EditorSelectionModel::SelectionTransition &transition) {
            coordinateSelectionChange(transition);
        });

    // Application-scoped appearance events drive the former QWidget
    // palette/style/theme fan-out; the Quick window's own changes arrive as
    // viewportChanged. Run the layout choreography once now so a
    // pre-framed window publishes its first canonical layout immediately.
    QGuiApplication::instance()->installEventFilter(this);
    connect(m_quickView, &TimelineQuickView::viewportChanged, this,
            &SongView::refreshViewportLayout);
    refreshViewportLayout();

    // The unbound axis's provisional camera rests at the pre-roll home;
    // updateScrollbars() keeps re-homing it as resize resolves the lead pad
    // until a song binds.
    m_camera.setHScroll(m_camera.minHScroll());
}

SongView::~SongView()
{
    if (m_editActions)
        m_editActions->rebind(nullptr);
    if (QGuiApplication::instance())
        QGuiApplication::instance()->removeEventFilter(this);
    // Detach FIRST: unload QML and cancel window-level popup/gesture state
    // while every model and QML context below is still alive. Essential on
    // the unhosted rig path, where no host container tears the window down
    // first. Every subsequent cleanup tolerates a detached Quick
    // coordinator (null quickView()/popupSession()) — each gates the
    // session through ownsSession and only resets domain state otherwise.
    if (m_quickView)
        m_quickView->detachWindow();
    if (m_roll)
        m_roll->cancelVelocityPromptWithoutFocus();
    if (m_ruler)
        m_ruler->cancelTimeSigPromptWithoutFocus();
    cancelVoicePicker(/*restoreFocus=*/false);
    cancelInsertTimePromptWithoutFocus();
    cancelTimeSelectionMenuWithoutFocus();
}

const songview::EditActions *SongView::editActions() const noexcept
{
    return m_editActions.data();
}

songview::TimelineQuickView *SongView::quickView() const noexcept
{
    return m_quickView;
}

void SongView::requestVoicePicker(const QString &title, int initialVoice, QObject *context,
                                  std::function<void(int)> accepted, TimelineBand origin)
{
    songview::TimelineQuickView *const quick = quickView();
    songview::QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    if (!m_document || !context || !accepted || !session)
        return;

    // The replacement cancellation below cascades synchronously: it can swap
    // the document, replace the quick view or its session, or end this
    // SongView. Everything the gate after it judges is pinned first.
    const QPointer<SongDocument> document = m_document;
    const uint64_t documentRevision = document->revision();
    const QPointer<songview::TimelineQuickView> liveQuick(quick);
    const QPointer<songview::QuickPopupSession> liveSession(session);
    const QPointer<QObject> liveContext(context);
    QPointer<SongView> self(this);
    // Replacement ends its owner before this guarded callback becomes live.
    // If this picker owns the session, cancellation synchronously clears its
    // bridge; another form's owner receives the same cancellation contract.
    if (m_pendingVoicePicker)
        cancelVoicePicker(/*restoreFocus=*/false);
    else
        session->cancel(/*restoreFocus=*/false);
    // The request stages only against the world it snapshotted: same quick
    // view and session still current, document unchanged, no newer
    // publication, and every pinned object alive.
    if (!self || !liveQuick || !liveSession || !liveContext || !document ||
        quickView() != liveQuick || liveQuick->popupSession() != liveSession ||
        m_document != document || document->revision() != documentRevision ||
        liveSession->isOpen()) {
        return;
    }

    PendingVoicePicker pending;
    pending.context = context;
    pending.session = session;
    pending.document = document;
    pending.documentRevision = documentRevision;
    pending.accepted = std::move(accepted);
    pending.origin = origin;
    m_pendingVoicePicker = std::move(pending);

    auto *picker = new songview::VoicePicker(*this, title, initialVoice, this);
    m_voicePicker = picker;
    QObject::disconnect(m_voicePickerCancellation);
    m_voicePickerCancellation =
        connect(session, &songview::QuickPopupSession::cancelled, this,
                [this](bool restoreFocus) { clearVoicePicker(restoreFocus); });
    connect(picker, &songview::VoicePicker::rejected, this, [this, picker] {
        if (m_voicePicker == picker)
            cancelVoicePicker(/*restoreFocus=*/true);
    });
    connect(picker, &songview::VoicePicker::accepted, this, [this, picker](int program) {
        if (m_voicePicker != picker || !m_pendingVoicePicker)
            return;
        const PendingVoicePicker pending = std::move(*m_pendingVoicePicker);
        // Pinned before the clear: its release callbacks can rebind the
        // bridge, republish the session, or end this SongView.
        QPointer<SongView> self(this);
        const QPointer<songview::VoicePicker> livePicker(picker);
        const QPointer<songview::TimelineQuickView> liveQuick(quickView());
        clearVoicePicker(/*restoreFocus=*/false);
        if (!self)
            return;
        // Re-judged after the clear: a dead picker, a dead session, or a
        // displaced current session means the acceptance is stale.
        if (!livePicker || !pending.session || !liveQuick || quickView() != liveQuick ||
            liveQuick->popupSession() != pending.session)
            return;
        if (pending.session->owns(picker))
            pending.session->close();
        if (!self)
            return;
        // A newer publication wins: no focus theft.
        if (!liveQuick || !pending.session || m_pendingVoicePicker || quickView() != liveQuick ||
            liveQuick->popupSession() != pending.session || pending.session->isOpen())
            return;
        focusTimelineBand(pending.origin, Qt::OtherFocusReason);
        // Re-judged after the focus swap, before the callback.
        if (!self || !liveQuick || !pending.session || m_pendingVoicePicker || !pending.context ||
            !pending.document || quickView() != liveQuick ||
            liveQuick->popupSession() != pending.session || pending.session->isOpen() ||
            m_document != pending.document ||
            pending.document->revision() != pending.documentRevision) {
            return;
        }
        pending.accepted(program);
    });
    const QPointer<songview::VoicePicker> livePicker(picker);
    const bool opened = session->openForm(
        QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/VoicePickerPrompt.qml")), picker);
    // The open's synchronous callbacks can end this SongView or stage a
    // newer publication; only the same picker/pending/session is cleared.
    if (opened || !self || !m_pendingVoicePicker || m_voicePicker != livePicker ||
        m_pendingVoicePicker->session != session)
        return;
    clearVoicePicker(/*restoreFocus=*/true);
}

void SongView::cancelVoicePicker(bool restoreFocus)
{
    if (!m_pendingVoicePicker)
        return;

    // Dispose against the pinned owner: a current-session lookup could
    // already be a replacement and must never cancel this old form or touch
    // a newer foreign form.
    const QPointer<songview::QuickPopupSession> session = m_pendingVoicePicker->session;
    const QPointer<songview::VoicePicker> picker = m_voicePicker;
    const bool ownsSession = session && picker && session->owns(picker);
    if (ownsSession) {
        QPointer<SongView> self(this);
        session->cancel(restoreFocus);
        // The cascade can end this SongView; the continuation must not follow.
        if (!self)
            return;
    }
    // Consume only what was pinned: the cascade may already have cleared
    // this pending or staged a newer publication that must survive.
    if (m_pendingVoicePicker && m_voicePicker == picker && m_pendingVoicePicker->session == session)
        clearVoicePicker(restoreFocus);
}

void SongView::clearVoicePicker(bool restoreFocus)
{
    if (!m_pendingVoicePicker)
        return;

    // Pinned before any callback: the teardown judges the world it started
    // with, never the one its release callbacks create.
    const TimelineBand origin = m_pendingVoicePicker->origin;
    const QPointer<songview::QuickPopupSession> session = m_pendingVoicePicker->session;
    m_pendingVoicePicker.reset();
    QObject::disconnect(m_voicePickerCancellation);
    m_voicePickerCancellation = {};
    QPointer<SongView> self(this);
    if (m_voicePicker) {
        // Consume the bridge slot before releaseHeld: its callbacks must
        // observe an idle bridge, and a publication opened from within them
        // must survive this teardown.
        const QPointer<songview::VoicePicker> picker = m_voicePicker;
        m_voicePicker = nullptr;
        picker->releaseHeld();
        // A release callback can end this SongView — its destructor already
        // deleted the picker.
        if (self && picker)
            picker->deleteLater();
    }
    // A newer picker staged during the release callbacks owns the focus.
    if (!self || m_pendingVoicePicker)
        return;
    // Focus returns only when the original surface is still current: the
    // pinned session must be alive and still the quick view's session, and
    // must not host a newer popup.
    songview::TimelineQuickView *const currentQuick = quickView();
    if (!session || !currentQuick || currentQuick->popupSession() != session || session->isOpen())
        return;
    if (restoreFocus)
        focusTimelineBand(origin, Qt::OtherFocusReason);
}

void SongView::cancelVoicePickerFor(QObject &context)
{
    if (!m_pendingVoicePicker || m_pendingVoicePicker->context != &context)
        return;
    cancelVoicePicker(/*restoreFocus=*/false);
}

EventListController *SongView::eventListController() const noexcept
{
    return m_events;
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
    if (m_roll) {
        m_roll->cancelVelocityPromptWithoutFocus();
        m_roll->cancelPitchBendPopup();
    }
    if (m_ruler)
        m_ruler->cancelTimeSigPromptWithoutFocus();
    cancelInsertTimePromptWithoutFocus();
    cancelActiveInteractions();
    if (timeline)
        m_trackActivity.resetPaused();
    else
        m_trackActivity.reset();
    m_timeline = timeline;
    m_voicegroup = voicegroup;
    m_timeAxis.bind(timeline);
    m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
    // Song attachment preserves the complete global editor projection and
    // rebuilds all drawer/page caches from that already-applied value.
    m_muteMask = 0;
    m_soloMask = 0;
    emit muteMaskChanged(0);
    emit soloMaskChanged(0);
    m_playheadTick = 0.0;
    m_editCursorTick = 0;
    m_playing = false;
    // Fresh songs open at the camera's home position, pre-roll pad showing.
    m_events->setPlayheadTick(-1.0, false); // another song's ticks are stale
    // Song attachment resets transient grid controls; editor cosmetics remain
    // global and are rebuilt above.
    m_grid.setTicksPerClock(m_document ? m_document->ticksPerClock() : 0);
    m_grid.setFeel(GridFeel::Straight);
    m_grid.setMinDenom(0);
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

double SongView::defaultVerticalScroll() const
{
    if (!m_timeline)
        return 0.0;
    const int midKey = m_model.minNoteKey <= m_model.maxNoteKey
                           ? (m_model.minNoteKey + m_model.maxNoteKey) / 2
                           : 60;
    const int centerPitch = m_projection.nearestVisiblePitch(midKey);
    const int centerRow = m_projection.rowForPitch(centerPitch);
    if (centerRow == songview::PitchProjection::cHiddenRow)
        return 0.0;
    return std::max(
        0.0, centerRow * keyHeight() -
                 std::max(m_geometry.pianoRollInitialViewportHeight, rollViewportHeight()) / 2.0);
}

void SongView::resetScrollPosition()
{
    setHScroll(minHScroll());
    setVScroll(defaultVerticalScroll());
}

void SongView::rebuildAfterSongChange()
{
    // The canonical beat scale is never derived from the timeline: binding
    // a song only changes the derived tick scale (pxPerTick()'s quotient).
    m_headers->rebuild(m_trackActivity, m_playing);
    notifyDrawerSongChanged();
    updateScrollbars();
    resetScrollPosition();
    // Full song rebuild: every roll domain may differ.
    refreshTimelineViews(PianoRollQuickDirty::All);
}

SongView::DocumentSwapHintScope::DocumentSwapHintScope(SongView &owner,
                                                       PianoRollQuickDirtySet dirty)
    : m_owner(owner)
{
    // The scope brackets exactly one document call; an open bracket is a
    // caller bug, caught in debug builds. The destructor keeps release
    // builds correct: any hint dies with its scope.
    Q_ASSERT(!owner.m_documentSwapHint.has_value());
    owner.m_documentSwapHint = dirty;
}

SongView::DocumentSwapHintScope::~DocumentSwapHintScope()
{
    // Consumed hints are already empty; a no-emission document call (or an
    // early return before one) clears here, so no stale hint reaches a
    // later updateSong.
    m_owner.m_documentSwapHint.reset();
}

// Generic document/model replacement union for an unclassified updateSong
// handoff (undo/redo, non-roll edits): every roll plot domain plus the
// text models. Keyboard domains differ only when the scale-fold projection
// rebuilds, and that path requests All itself.
PianoRollQuickDirtySet SongView::takeDocumentSwapHint()
{
    const PianoRollQuickDirtySet dirty = m_documentSwapHint.value_or(cPlotAndLoadingDirty);
    m_documentSwapHint.reset();
    return dirty;
}

void SongView::updateSong(const MidiTimeline *timeline)
{
    // Classify this handoff before rebuilding state: a committed roll
    // mutation names its exact domains; anything else is the generic
    // document/model replacement.
    const PianoRollQuickDirtySet swapDirty = takeDocumentSwapHint();
    cancelActiveInteractions();
    m_timeline = timeline;
    m_timeAxis.bind(timeline);
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
    m_headers->rebuild(m_trackActivity, m_playing);
    notifyDrawerSongChanged();
    if (m_scaleController.scaleFold()) {
        requestProjectionRebuild();
    } else {
        updateScrollbars();
    }
    // A fold rebuild above queued All; otherwise only the swap's domains
    // may differ.
    refreshTimelineViews(swapDirty);
}

void SongView::disconnectDocument()
{
    if (m_document) {
        disconnect(m_document, &SongDocument::tracksRemapped, this, nullptr);
        disconnect(m_document, &SongDocument::documentChanged, this, nullptr);
    }
    m_document = nullptr;
    m_grid.setTicksPerClock(0);
    m_events->setDocument(nullptr);
}

void SongView::prepareForSongReplacement()
{
    if (m_roll) {
        m_roll->cancelVelocityPromptWithoutFocus();
        m_roll->cancelPitchBendPopup();
    }
    if (m_ruler) {
        m_ruler->cancelTimeSigPromptWithoutFocus();
        m_ruler->closePopups();
    }
    cancelInsertTimePromptWithoutFocus();
    cancelTimeSelectionMenuWithoutFocus();
    cancelActiveInteractions();
    m_headers->cancelTransientState();
    disconnectDocument();
}

void SongView::cancelTransientInput()
{
    ++m_transientInputGeneration;
    // The shared Quick popup dies with every readiness/document reset: one
    // blanket cancellation covers every menu/form owner with no per-owner
    // list. Per-owner cleanup below then only resets domain state.
    if (m_quickView) {
        if (songview::QuickPopupSession *const session = m_quickView->popupSession();
            session && session->isOpen())
            session->cancel(/*restoreFocus=*/false);
    }
    // First cancel pointer state through the canonical traversal. Strong
    // document/readiness cleanup then applies its separate popup policy.
    cancelActiveInteractions();
    cancelInsertTimePromptWithoutFocus();
    if (m_roll) {
        m_roll->cancelVelocityPromptWithoutFocus();
        m_roll->cancelPitchBendPopupWithoutFocus();
    }
    cancelTimeSelectionMenuWithoutFocus();
    if (m_ruler) {
        m_ruler->cancelTimeSigPromptWithoutFocus();
        m_ruler->closePopups();
    }
    if (m_headers)
        m_headers->cancelTransientState();
}

void SongView::setDocument(SongDocument *document)
{
    const bool documentChanged = m_document != document;
    if (documentChanged) {
        if (m_roll) {
            m_roll->cancelVelocityPromptWithoutFocus();
            m_roll->cancelPitchBendPopup();
        }
        if (m_ruler)
            m_ruler->cancelTimeSigPromptWithoutFocus();
        cancelInsertTimePromptWithoutFocus();
        cancelActiveInteractions();
        disconnectDocument();
        if (document) {
            connect(document, &SongDocument::tracksRemapped, this, &SongView::onTracksRemapped);
            connect(document, &SongDocument::documentChanged, this, [this] {
                // Any document edit invalidates a preview captured at the
                // previous revision before the normal page refresh.
                invalidateContextMenus(/*restoreFocus=*/true);
                cancelActiveInteractions();
                cancelInsertTimePromptWithoutFocus();
                if (m_ruler)
                    m_ruler->cancelTimeSigPromptWithoutFocus();
                m_editorDrawer->automationPage()->documentChanged();
                m_editorDrawer->velocityArea()->documentChanged();
                m_editorDrawer->voiceChangeArea()->documentChanged();
                refreshDrawerPages();
            });
        }
    }
    m_document = document;
    m_grid.setTicksPerClock(document ? document->ticksPerClock() : 0);
    m_events->setDocument(document);
    m_selectionModel.clearNoteSelection();
    m_headers->rebuild(m_trackActivity, m_playing);
    notifyDrawerSongChanged();
    if (documentChanged) {
        if (m_editActions)
            m_editActions->rebind(this);
        else
            invalidateContextMenus(/*restoreFocus=*/false);
    }
}

bool SongView::eventListVisible() const
{
    return m_eventListVisible;
}
void SongView::setEventListVisible(bool visible)
{
    if (m_eventListVisible == visible)
        return;
    m_eventListVisible = visible;
    // The roll band exists only while the event page is hidden; resync
    // immediately so the swap cannot leave a stale canonical Roll entry.
    synchronizeTimelineBandLayout();
    m_events->setVisible(visible);
    focusContent();
    emit eventListVisibilityChanged(visible);
}

void SongView::focusContent()
{
    if (eventListVisible()) {
        // The event list owns the roll band's screen space; its Quick input
        // item is the editing surface and the row-command focus owner.
        if (m_quickView)
            m_quickView->focusEventListInput(Qt::OtherFocusReason);
    } else {
        focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason);
    }
}
void SongView::focusActiveSurface()
{
    if (hasVisibleDrawerSection())
        m_editorDrawer->focusVisiblePage();
    else
        focusContent();
}

bool SongView::focusTimelineBand(songview::TimelineBand band, Qt::FocusReason reason)
{
    return m_quickView && m_quickView->focusBand(band, reason);
}

std::optional<songview::TimelineBand> SongView::focusedTimelineBand() const
{
    return m_quickView ? m_quickView->focusedBand() : std::nullopt;
}

bool SongView::eventListSurfaceFocused() const
{
    return m_quickView && m_quickView->eventListSurfaceFocused();
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
    state.pxPerBeat = m_camera.pxPerBeat();
    state.keyHeight = m_camera.keyHeight();
    state.scrollPx = m_camera.scrollX();
    state.scrollY = m_camera.scrollY();
    state.selectedTrack = m_selectionModel.primaryTrack();
    state.editCursorTick = m_editCursorTick;
    state.gridMinDenom = m_grid.minDenom();
    state.gridTriplet = m_grid.feel() == GridFeel::Triplet;
    state.eventList = eventListVisible();
    return state;
}

void SongView::applyViewState(const ViewState &state)
{
    if (!state.valid || !m_timeline)
        return;
    const int gridMinDenom = songview::Grid::normalizeMinDenom(state.gridMinDenom);
    const GridFeel gridFeel = state.gridTriplet ? GridFeel::Triplet : GridFeel::Straight;
    const double pxPerBeat =
        std::clamp(state.pxPerBeat, double(m_geometry.timelineMinimumPixelsPerBeat),
                   double(m_geometry.timelineMaximumPixelsPerBeat));
    const bool zoomChanged = m_camera.setTimeZoom(pxPerBeat);
    const bool gridChanged = gridMinDenom != m_grid.minDenom() || gridFeel != m_grid.feel();
    if ((zoomChanged || gridChanged) && m_editorDrawer)
        m_editorDrawer->cancelVisiblePageInteraction();
    (void)m_camera.setKeyHeight(state.keyHeight); // clamps internally
    m_roll->refreshTextLayout();
    setGridMinDenom(gridMinDenom);
    setGridFeel(state.gridTriplet ? GridFeel::Triplet : GridFeel::Straight);
    if (state.selectedTrack >= 0 && state.selectedTrack < 16 &&
        m_timeline->tracks[state.selectedTrack].used)
        selectTrack(state.selectedTrack);
    updateScrollbars();
    setHScroll(state.scrollPx); // setHScroll clamps to the camera's range
    setVScroll(state.scrollY);
    setEventListVisible(state.eventList);
    m_editCursorTick = std::min<Tick>(state.editCursorTick, m_timeline->lengthTicks);
    // Whole view-state applied: every roll domain may differ.
    refreshTimelineViews(PianoRollQuickDirty::All);
}

void SongView::setVoicegroup(const LoadedVoiceGroup *voicegroup)
{
    if (m_voicegroup == voicegroup)
        return;
    cancelActiveInteractions();
    m_voicegroup = voicegroup;
    m_headers->rebuild(m_trackActivity, m_playing);
    notifyDrawerSongChanged();
    // Voicegroup replacement can change any roll domain.
    refreshTimelineViews(PianoRollQuickDirty::All);
}

void SongView::invalidateContextMenus(bool restoreFocus)
{
    emit contextMenusInvalidated(restoreFocus);
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
    if (primaryChanged || trackScopeChanged || noteSelectionChanged || timeSelectionChanged) {
        invalidateContextMenus(/*restoreFocus=*/true);
        emit selectionContextChanged();
    }
    // Roll layers already requested in this transition; later branches only
    // request the missing union members (a projection rebuild covers All).
    PianoRollQuickDirtySet rollDirty = PianoRollQuickDirty::None;
    const auto requestRoll = [this, &rollDirty](PianoRollQuickDirtySet dirty) {
        if (const PianoRollQuickDirtySet missing = dirty & ~rollDirty;
            missing != PianoRollQuickDirty::None) {
            m_roll->requestQuickUpdate(missing);
            rollDirty |= missing;
        }
    };
    bool timelineViewsRefreshed = false;
    if (primaryChanged) {
        m_headers->syncSelection();
        if (m_scaleController.scaleFold()) {
            rebuildProjectionWithAnchoring();
            rollDirty = PianoRollQuickDirty::All;
        } else {
            requestRoll(PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::DrawPreviewFill |
                        PianoRollQuickDirty::NoteBordersAndSelection |
                        PianoRollQuickDirty::NoteText);
        }
        emit selectedTrackChanged(m_selectionModel.primaryTrack());
    } else if (trackScopeChanged) {
        m_headers->syncSelection();
        requestTimelineQuickUpdate(TimelineQuickDirty::Ruler);
        requestRoll(PianoRollQuickDirty::NoteBordersAndSelection | PianoRollQuickDirty::Overlay);
        requestTimelineQuickUpdate(TimelineQuickDirty::OtherEvents);
        syncTimelineIndicators();
        timelineViewsRefreshed = true;
    }
    if (noteSelectionChanged) {
        requestRoll(PianoRollQuickDirty::NoteBordersAndSelection);
        refreshVelocityPage();
    }
    if (timeSelectionChanged) {
        if (!timelineViewsRefreshed) {
            requestTimelineQuickUpdate(TimelineQuickDirty::Ruler);
            requestRoll(PianoRollQuickDirty::NoteBordersAndSelection |
                        PianoRollQuickDirty::Overlay);
            syncTimelineIndicators();
        }
        refreshAutomationPage();
    }
    if (primaryChanged || trackScopeChanged)
        refreshDrawerPages();
}

// Application-scoped appearance path (theme apply, palette or application
// font/style change): the former QWidget palette/style/theme fan-out. DPR
// and screen changes ride the Quick coordinator's viewportChanged instead.
bool SongView::eventFilter(QObject *watched, QEvent *event)
{
    // The manual key route owns Quick-scene keys only: claim the override
    // while a QQuick focus object (band input, scene root, popup field) will
    // deliver the press through TimelineQuickView into handleEditKey. A native
    // QWidget focus stays with Qt delivery, where the installed window actions
    // own Window commands and the widget owns its local keys; claiming those
    // would stand Qt's shortcut matching down with no manual follow-through.
    // (The application filter observes every receiver; watched is the focused
    // object here, not just qApp itself.)
    if (event->type() == QEvent::ShortcutOverride && watched == QGuiApplication::focusObject()) {
        QObject *const focus = QGuiApplication::focusObject();
        const bool quickFocus =
            focus != nullptr && (qobject_cast<QQuickItem *>(focus) != nullptr ||
                                 qobject_cast<QQuickWindow *>(focus) != nullptr);
        if (quickFocus) {
            const auto *const keyEvent = static_cast<const QKeyEvent *>(event);
            if (const songview::EditActions *const actions = editActions();
                actions && actions->target() == this &&
                actions->editorCommandForKey(keyEvent->key(), keyEvent->modifiers())) {
                event->accept();
                return true;
            }
        }
    }

    if (watched == QGuiApplication::instance()) {
        switch (event->type()) {
        case QEvent::ApplicationPaletteChange:
        case QEvent::PaletteChange:
        case QEvent::ApplicationFontChange:
        case QEvent::StyleChange:
        case QEvent::ThemeChange:
            if (m_editorDrawer)
                m_editorDrawer->refreshAppearance(QGuiApplication::palette());
            syncTimelineQuickAppearance();
            if (m_playheadOverlay)
                m_playheadOverlay->syncAppearance();
            break;
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}

void SongView::setPlayheadSample(uint64_t samplePos, bool playing)
{
    if (!m_timeline)
        return;
    const bool velocityPageVisible = m_editorDrawer->pageVisible(EditorDrawerPage::Velocity);
    const bool voiceChangesPageVisible =
        m_editorDrawer->pageVisible(EditorDrawerPage::VoiceChanges);
    const bool voiceContextVisible = velocityPageVisible || voiceChangesPageVisible;
    const auto visibleDrawerContext = [this] {
        const uint64_t tick = m_playing ? static_cast<uint64_t>(std::max(0.0, m_playheadTick) + 0.5)
                                        : m_editCursorTick;
        return voiceContext(tick);
    };
    const DrawerPageVoiceContext contextBefore =
        voiceContextVisible ? visibleDrawerContext() : DrawerPageVoiceContext{};
    m_playheadTick = m_timeline->tickForSample(samplePos);
    m_playing = playing;
    const DrawerPageVoiceContext contextAfter =
        voiceContextVisible ? visibleDrawerContext() : DrawerPageVoiceContext{};
    // Follow the playhead — unless following is switched off (transport
    // bar), and never while the user is mid-gesture (panning, dragging notes
    // or selections, sweeping automation): yanking the view out from under a
    // held mouse button is disorienting.
    if (playing && m_followPlayhead && !m_followScrollPaused && !userGestureActive()) {
        const qreal px = m_camera.contentX(m_playheadTick);
        const qreal vw = viewportWidth();
        if (px < 0.0 || px > vw * 85.0 / 100.0)
            setHScroll(m_playheadTick * pxPerTick() - vw / 10.0);
    }
    m_events->setPlayheadTick(m_playheadTick, playing);
    m_headers->syncVoices();
    if (voiceContextVisible && (contextBefore.voice != contextAfter.voice ||
                                contextBefore.voiceSlot != contextAfter.voiceSlot)) {
        if (velocityPageVisible)
            refreshVelocityPage();
        if (voiceChangesPageVisible)
            refreshVoiceChangePage();
    }
    if (velocityPageVisible)
        m_editorDrawer->velocityArea()->presentPlayhead(m_playheadTick);
    if (voiceChangesPageVisible)
        m_editorDrawer->voiceChangeArea()->presentPlayhead(m_playheadTick);
    syncTimelineIndicators();
}

bool SongView::timelinePointerGestureActive() const
{
    // Once the converted scene exists it owns the complete timeline pointer
    // aggregate, including ruler and velocity; do not fold stale native
    // queries into that authoritative result.
    if (m_quickView)
        return m_quickView->gestureActive();
    return (m_ruler && m_ruler->gestureActive()) || (m_roll && m_roll->gestureActive());
}

bool SongView::userGestureActive() const
{
    return timelinePointerGestureActive();
}

void SongView::requestPianoRollQuickUpdate(PianoRollQuickDirtySet dirty)
{
    if (dirty != PianoRollQuickDirty::None && m_quickView)
        m_quickView->requestUpdate(dirty);
}

void SongView::requestTimelineQuickUpdate(TimelineQuickDirtySet dirty)
{
    if (dirty != TimelineQuickDirty::None && m_quickView)
        m_quickView->requestTimelineUpdate(dirty);
}

void SongView::requestAutomationQuickUpdate(songview::AutomationRefreshSet refresh)
{
    if (refresh != AutomationRefresh::None && m_quickView)
        m_quickView->requestAutomationUpdate(refresh);
}

void SongView::syncTimelineQuickAppearance()
{
    if (m_quickView)
        m_quickView->syncAppearance();
    // The event page's theme map and menu-host styles ride the same
    // appearance republish as every other Quick surface.
    m_events->syncAppearance();
}

void SongView::publishTimelineQuickHover(songview::TimelineQuickHoverOwner owner, Tick tick)
{
    if (m_quickView && m_timeline)
        m_quickView->publishHover(owner, tick, timelineSplitX() + m_camera.contentX(tick));
}

void SongView::clearTimelineQuickHover(songview::TimelineQuickHoverOwner owner)
{
    if (m_quickView)
        m_quickView->clearHover(owner);
}

void SongView::syncTimelineIndicators()
{
    const qreal rootOriginX = timelineSplitX();
    std::optional<qreal> editRootContentX;
    if (m_timeline)
        editRootContentX = rootOriginX + m_camera.contentX(m_editCursorTick);

    if (m_playheadOverlay)
        m_playheadOverlay->setPlayhead(m_camera.contentX(m_playheadTick), m_timeline != nullptr,
                                       m_playing);
    if (m_quickView) {
        m_quickView->synchronizeGuides(rootOriginX, editRootContentX);
    }
}

void SongView::setEditCursorTick(Tick tick)
{
    if (m_editCursorTick == tick)
        return;
    m_editCursorTick = tick;
    m_headers->syncVoices();
    syncTimelineIndicators();
    refreshDrawerPages();
}

void SongView::commitEditCursor(Tick tick)
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

void SongView::refreshTimelineViews(PianoRollQuickDirtySet dirty)
{
    requestTimelineQuickUpdate(TimelineQuickDirty::All);
    requestAutomationQuickUpdate(songview::AutomationRefresh::All);
    m_roll->requestQuickUpdate(dirty);
    syncTimelineIndicators();
}
