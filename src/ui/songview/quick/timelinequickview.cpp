#include "ui/songview/quick/timelinequickview.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/quickpopupsession.h"

#include "ui/songview/quick/playheadquick.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/theme/themeruntime.h"
#include <QColor>
#include <QGuiApplication>
#include <QStyleHints>
#include <QVariant>
#include <QtQml>
#include <algorithm>
#include <array>
#include <chrono>
#include <mutex>
#include <utility>

namespace songview {

namespace {

// Wheel deltas to a signed DIP scroll step for one scrollbar axis. Pixel
// deltas are consumed one-to-one as DIPs; rotary notches use the GUI style
// hints' wheelScrollLines() lines of one DIP each — the legacy widgets'
// line step. The bar's own axis wins and the other axis still
// scrolls a wheel that carries only it. The returned value negates the
// delta so a conventional wheel-up (positive delta) scrolls toward the
// bar's minimum, and the platform's natural-scroll sign travels inside the
// delivered deltas — `inverted` must never flip it a second time.
qreal scrollbarWheelDips(bool preferX, qreal pixelX, qreal pixelY, qreal angleX, qreal angleY)
{
    const qreal pixel =
        preferX ? (pixelX != 0.0 ? pixelX : pixelY) : (pixelY != 0.0 ? pixelY : pixelX);
    if (pixel != 0.0)
        return -pixel;
    const qreal angle =
        preferX ? (angleX != 0.0 ? angleX : angleY) : (angleY != 0.0 ? angleY : angleX);
    return -angle * QGuiApplication::styleHints()->wheelScrollLines() / 120.0;
}

} // namespace

void TimelineQuickView::registerQuickTypes()
{
    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<TimelineChromeItem>("Porydaw.Ui", 1, 0, "TimelineChromeItem");
        qmlRegisterType<TimelineInputItem>("Porydaw.Ui", 1, 0, "TimelineInputItem");
        // TimelineGestureScrollbar inherits activeFocusOnTab from QQuickItem,
        // introduced at the QtQuick 2.1 base meta-object revision.
        qmlRegisterRevision<QQuickItem, 1>("Porydaw.Ui", 1, 0);
        qmlRegisterType<TimelineGestureScrollbar>("Porydaw.Ui", 1, 0, "TimelineGestureScrollbar");
        qmlRegisterType<TimelinePlayheadItem>("Porydaw.Ui", 1, 0, "TimelinePlayheadItem");
        qmlRegisterType<TimelineQuickItem>("Porydaw.Ui", 1, 0, "TimelineQuickItem");
    });
}

TimelineQuickView::TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                                     AutomationPage &automation, VelocityArea &velocity,
                                     VoiceChangeArea &voiceChanges, DrawerChrome &drawerChrome,
                                     TrackHeaderModel &trackHeaders, EventListController &eventList,
                                     SongView &songView)
    : QObject(&songView)
    , m_ruler(&ruler)
    , m_trackHeaders(&trackHeaders)
    , m_roll(&roll)
    , m_otherEvents(&otherEvents)
    , m_automation(&automation)
    , m_velocity(&velocity)
    , m_voiceChanges(&voiceChanges)
    , m_drawerChrome(&drawerChrome)
    , m_songView(&songView)
    , m_eventList(&eventList)
    , m_camera(songView.camera())
    , m_playheadColor(themes::color(themes::Role::song_view_playhead))
{
    m_layoutTimer.setSingleShot(true);
    m_layoutTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_layoutTimer, &QTimer::timeout, this, &TimelineQuickView::publishTimelineBandLayout);
    m_flushTimer.setSingleShot(true);
    m_flushTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_flushTimer, &QTimer::timeout, this, &TimelineQuickView::flushUpdate);
    // Drawer chrome repaints through the QML bindings to the chrome context
    // object directly; scroll changes only repaint the automation layers.
    connect(m_drawerChrome, &DrawerChrome::scrollChanged, this,
            [this] { requestAutomationUpdate(AutomationRefresh::All); });

    setObjectName(QStringLiteral("timelineQuickCanvas"));

    // The QML scene model is domain state created once: it outlives every
    // attachment, and attachScene() publishes it into the host engine.
    m_scene = new TimelineQuickScene(this);
}

void TimelineQuickView::detachInputInteraction(TimelineBand band)
{
    const std::size_t index = timelineBandIndex(band);
    // Clear first so a band being destroyed cannot retain a route to this
    // host while its input detaches.
    if (TimelineInputItem *const gutterItem = m_gutterInputItems[index]) {
        gutterItem->clearKeyPolicy();
        gutterItem->setInteraction(nullptr);
    }
    if (TimelineInputItem *const primaryItem = m_inputItems[index]) {
        primaryItem->clearKeyPolicy();
        primaryItem->setInteraction(nullptr);
    }
}

qreal TimelineQuickView::hoverRootContentX() const noexcept
{
    return m_hoverSongViewContentX.value_or(0.0);
}

bool TimelineQuickView::hoverVisible() const noexcept
{
    return m_hoverSongViewContentX.has_value();
}

qreal TimelineQuickView::editRootContentX() const noexcept
{
    return m_editSongViewContentX.value_or(0.0);
}

bool TimelineQuickView::editVisible() const noexcept
{
    return m_editSongViewContentX.has_value();
}

qreal TimelineQuickView::playheadLocalX() const noexcept
{
    return m_playheadLocalX;
}

bool TimelineQuickView::playheadVisible() const noexcept
{
    return m_playheadEffectiveVisible;
}

bool TimelineQuickView::playheadPlaying() const noexcept
{
    return m_playheadPlaying;
}

QColor TimelineQuickView::playheadColor() const
{
    return m_playheadColor;
}

bool TimelineQuickView::playheadTrianglePointsUp() const noexcept
{
    return m_playheadTrianglePointsUp;
}

qreal TimelineQuickView::playheadGlowLeft() const noexcept
{
    return songview::playheadGlowLeftExtent(m_playheadPlaying);
}

qreal TimelineQuickView::playheadGlowRight() const noexcept
{
    return songview::playheadGlowRightExtent(m_playheadPlaying);
}

qreal TimelineQuickView::playheadPeakAlpha() const noexcept
{
    return songview::playheadPeakAlpha(m_playheadPlaying);
}

qreal TimelineQuickView::playheadLineWidthPx() const noexcept
{
    return songview::playheadLineWidth();
}

int TimelineQuickView::playheadTriangleHalfWidthPx() const noexcept
{
    return songview::playheadTriangleHalfWidth();
}

int TimelineQuickView::playheadTriangleHeightPx() const noexcept
{
    return songview::playheadTriangleHeight();
}

void TimelineQuickView::setPlayhead(qreal localX, bool effectiveVisible, bool playing,
                                    bool trianglePointsUp)
{
    const bool xChanged = m_playheadLocalX != localX;
    const bool appearanceChanged = m_playheadEffectiveVisible != effectiveVisible ||
                                   m_playheadPlaying != playing ||
                                   m_playheadTrianglePointsUp != trianglePointsUp;
    if (!xChanged && !appearanceChanged)
        return;
    m_playheadLocalX = localX;
    m_playheadEffectiveVisible = effectiveVisible;
    m_playheadPlaying = playing;
    m_playheadTrianglePointsUp = trianglePointsUp;
    if (xChanged)
        emit playheadXChanged();
    if (appearanceChanged)
        emit playheadChanged();
}

void TimelineQuickView::setPlayheadColor(const QColor &color)
{
    if (m_playheadColor == color)
        return;
    m_playheadColor = color;
    emit playheadChanged();
}

qreal TimelineQuickView::rulerPlotOrigin() const noexcept
{
    return m_publishedRulerPlotOrigin;
}

QRectF TimelineQuickView::horizontalScrollbarRect() const noexcept
{
    return m_publishedHorizontalScrollbarRect;
}

QRectF TimelineQuickView::verticalScrollbarRect() const noexcept
{
    return m_publishedVerticalScrollbarRect;
}

qreal TimelineQuickView::horizontalScrollValue() const
{
    return m_camera.scrollX();
}

qreal TimelineQuickView::horizontalScrollMinimum() const
{
    return m_camera.minHScroll();
}

qreal TimelineQuickView::horizontalScrollMaximum() const
{
    return m_camera.maxHScroll();
}

qreal TimelineQuickView::horizontalScrollPageStep() const
{
    return m_songView ? m_songView->viewportWidth() : 0.0;
}

qreal TimelineQuickView::verticalScrollValue() const
{
    return m_camera.scrollY();
}

qreal TimelineQuickView::verticalScrollMaximum() const
{
    return m_camera.maxRollScroll();
}

qreal TimelineQuickView::verticalScrollPageStep() const
{
    return m_songView ? m_songView->rollViewportHeight() : 0.0;
}

void TimelineQuickView::setHorizontalScroll(qreal value)
{
    // SongView owns the camera; its sync tail re-notifies
    // scrollbarStateChanged with the clamped outcome.
    if (m_songView)
        m_songView->setHScroll(value);
}

void TimelineQuickView::setVerticalScroll(qreal value)
{
    if (m_songView)
        m_songView->setVScroll(value);
}

void TimelineQuickView::scrollHorizontalByWheel(qreal pixelX, qreal pixelY, qreal angleX,
                                                qreal angleY, bool inverted)
{
    Q_UNUSED(inverted); // the delivered deltas already carry the natural-scroll sign
    if (m_songView)
        m_songView->scrollByPx(scrollbarWheelDips(true, pixelX, pixelY, angleX, angleY));
}

void TimelineQuickView::scrollVerticalByWheel(qreal pixelX, qreal pixelY, qreal angleX,
                                              qreal angleY, bool inverted)
{
    Q_UNUSED(inverted);
    if (m_songView)
        m_songView->scrollRollBy(scrollbarWheelDips(false, pixelX, pixelY, angleX, angleY));
}

void TimelineQuickView::notifyScrollbarsChanged()
{
    emit scrollbarStateChanged();
}

void TimelineQuickView::synchronizeGuides(qreal songViewSplitX,
                                          std::optional<qreal> editSongViewContentX)
{
    setEditChrome(editSongViewContentX);
    if (m_hoverOwner != TimelineQuickHoverOwner::None && m_songView)
        setHoverChrome(songViewSplitX + m_camera.contentX(m_hoverTick));
}

void TimelineQuickView::publishHover(TimelineQuickHoverOwner owner, uint64_t tick,
                                     qreal songViewContentX)
{
    if (owner == TimelineQuickHoverOwner::None)
        return;
    const std::optional<qreal> visibleContentX =
        guideSongViewContentXAtOrAfterStart(songViewContentX);
    if (!visibleContentX) {
        clearHover(owner);
        return;
    }
    m_hoverOwner = owner;
    m_hoverTick = tick;
    setHoverChrome(visibleContentX);
}

void TimelineQuickView::clearHover(TimelineQuickHoverOwner owner)
{
    if (m_hoverOwner != owner)
        return;
    m_hoverOwner = TimelineQuickHoverOwner::None;
    setHoverChrome(std::nullopt);
}

std::optional<qreal> TimelineQuickView::guideSongViewContentXAtOrAfterStart(
    std::optional<qreal> songViewContentX) const noexcept
{
    if (!songViewContentX || !m_songView)
        return std::nullopt;
    const qreal songStartX = m_songView->timelineSplitX() + m_camera.contentX(0.0);
    return *songViewContentX >= songStartX ? songViewContentX : std::nullopt;
}

void TimelineQuickView::setHoverChrome(std::optional<qreal> songViewContentX)
{
    songViewContentX = guideSongViewContentXAtOrAfterStart(songViewContentX);
    if (m_hoverSongViewContentX == songViewContentX)
        return;
    m_hoverSongViewContentX = songViewContentX;
    emit hoverChromeChanged();
}

void TimelineQuickView::setEditChrome(std::optional<qreal> songViewContentX)
{
    songViewContentX = guideSongViewContentXAtOrAfterStart(songViewContentX);
    if (m_editSongViewContentX == songViewContentX)
        return;
    m_editSongViewContentX = songViewContentX;
    emit editChromeChanged();
}

void TimelineQuickView::scheduleTimelineBandLayoutPublication()
{
    m_layoutTimer.start();
}

void TimelineQuickView::setBandLayout(TimelineBandLayout layout)
{
    if (m_bandLayout == layout)
        return;

    const auto becameVisibleOrChangedSize = [](const TimelineBandLayout &published,
                                               const TimelineBandLayout &current,
                                               TimelineBand band) {
        const std::optional<TimelineBandGeometry> &before = published.geometry(band);
        const std::optional<TimelineBandGeometry> &after = current.geometry(band);
        // Plot pixels also depend on the plot rectangle: a split or scrollbar
        // change can resize the plot while the row rectangle stays put.
        return after && (!before || before->rect.size() != after->rect.size() ||
                         before->plotRect.size() != after->plotRect.size());
    };

    PianoRollQuickDirtySet pianoDirty = PianoRollQuickDirty::None;
    TimelineQuickDirtySet timelineDirty = TimelineQuickDirty::None;
    AutomationRefreshSet automationRefresh = AutomationRefresh::None;

    // Accumulate the size-dependent dirty domains first so the zero-timeout
    // publication below is scheduled before any zero-timeout dirty flush; a
    // scene rebuild must never run against stale band geometry.
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::Ruler))
        timelineDirty |= TimelineQuickDirty::Ruler;
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::Roll)) {
        const std::optional<TimelineBandGeometry> &before =
            m_bandLayout.geometry(TimelineBand::Roll);
        const std::optional<TimelineBandGeometry> &after = layout.geometry(TimelineBand::Roll);
        const bool widthOnly = before && before->rect.height() == after->rect.height();
        pianoDirty |= widthOnly ? cPlotAndLoadingDirty : PianoRollQuickDirty::All;
    }
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::OtherEvents))
        timelineDirty |= TimelineQuickDirty::OtherEvents;
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::Automation))
        automationRefresh |= AutomationRefresh::All;
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::Velocity))
        timelineDirty |= TimelineQuickDirty::Velocity;
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::VoiceChanges))
        timelineDirty |= TimelineQuickDirty::VoiceChanges;

    m_bandLayout = std::move(layout);
    scheduleTimelineBandLayoutPublication();
    requestUpdate(pianoDirty);
    requestTimelineUpdate(timelineDirty);
    requestAutomationUpdate(automationRefresh);
}

void TimelineQuickView::refreshBandLayout()
{
    // Canvas resizes and Quick-window lifecycle events can drop published
    // QML geometry; republish the stored layout as-is, without changing the
    // canonical value or queueing dirty domains.
    scheduleTimelineBandLayoutPublication();
}

bool TimelineQuickView::focusBand(TimelineBand band, Qt::FocusReason reason)
{
    TimelineInputItem *const item = m_inputItems[timelineBandIndex(band)];
    if (!item)
        return false;
    // The shared workspace window resolves this request through its ordinary
    // Quick focus chain. TimelineInputItem preserves native window activation
    // at the actual input-acquisition seam; focusedBand() stays the live
    // active-focus truth.
    item->requestFocus(reason);
    return true;
}

bool TimelineQuickView::focusEventListInput(Qt::FocusReason reason)
{
    if (!m_eventListInput)
        return false;
    // Event-list input follows the same shared Quick focus path.
    m_eventListInput->requestFocus(reason);
    return true;
}

void TimelineQuickView::syncAppearance()
{
    // SongView is a pure coordinator now: the app-level font and palette
    // every input item and chrome surface shares are the QGuiApplication
    // values.
    const QFont font = QGuiApplication::font();
    const QPalette palette = QGuiApplication::palette();
    for (TimelineInputItem *item : m_gutterInputItems) {
        if (item)
            item->setHostAppearance(font, palette);
    }
    for (TimelineInputItem *item : m_inputItems) {
        if (!item)
            continue;
        item->setHostAppearance(font, palette);
        if (item->interaction())
            item->notifyHostAppearanceChanged();
    }
    if (m_eventListInput) {
        m_eventListInput->setHostAppearance(font, palette);
        m_eventListInput->notifyHostAppearanceChanged();
    }
    for (TimelineChromeItem *item : m_chromeItems) {
        if (item)
            item->update();
    }
    requestUpdate(PianoRollQuickDirty::All);
    requestTimelineUpdate(TimelineQuickDirty::All);
    requestAutomationUpdate(AutomationRefresh::All);
}

bool TimelineQuickView::eventListSurfaceFocused() const
{
    return m_eventListInput && m_eventListInput->hasActiveFocus();
}

std::optional<TimelineBand> TimelineQuickView::focusedBand() const
{
    for (std::size_t index = 0; index < m_inputItems.size(); ++index) {
        if (m_inputItems[index] && m_inputItems[index]->hasActiveFocus())
            return static_cast<TimelineBand>(index);
    }
    return std::nullopt;
}

void TimelineQuickView::requestUpdate(PianoRollQuickDirtySet dirty)
{
    if (dirty == PianoRollQuickDirty::None)
        return;
    m_pendingDirty |= dirty;
    m_flushTimer.start();
}

void TimelineQuickView::requestTimelineUpdate(TimelineQuickDirtySet dirty)
{
    if (dirty == TimelineQuickDirty::None)
        return;
    m_pendingTimelineDirty |= dirty;
    m_flushTimer.start();
}

void TimelineQuickView::requestAutomationUpdate(AutomationRefreshSet dirty)
{
    if (dirty == AutomationRefresh::None)
        return;
    m_pendingAutomationRefresh |= dirty;
    m_flushTimer.start();
}

void TimelineQuickView::flushUpdate()
{
    if (!m_view || !m_root || !m_root->window())
        return; // detached or orphaned canvas: no live window surface to sync into

    // A flush queued before the latest setBandLayout()/refreshBandLayout() must
    // not rebuild scenes ahead of geometry publication: publish first.
    if (m_layoutTimer.isActive()) {
        m_layoutTimer.stop();
        publishTimelineBandLayout();
    }

    const PianoRollQuickDirtySet pianoDirty =
        std::exchange(m_pendingDirty, PianoRollQuickDirty::None);
    const TimelineQuickDirtySet timelineDirty =
        std::exchange(m_pendingTimelineDirty, TimelineQuickDirty::None);
    const AutomationRefreshSet automationRefresh =
        std::exchange(m_pendingAutomationRefresh, AutomationRefresh::None);
    if (pianoDirty != PianoRollQuickDirty::None)
        syncPianoRoll(pianoDirty);
    if (timelineDirty & TimelineQuickDirty::Ruler)
        syncRuler();
    if (timelineDirty & TimelineQuickDirty::OtherEvents)
        syncOtherEvents();
    if (automationRefresh != AutomationRefresh::None)
        syncAutomation(automationRefresh);
    if (timelineDirty & TimelineQuickDirty::Velocity)
        syncVelocity();
    if (timelineDirty & (TimelineQuickDirty::VoiceChanges | TimelineQuickDirty::VoiceChangesHover))
        syncVoiceChanges(timelineDirty);
}

void TimelineQuickView::updateLayer(TimelineQuickLayer layer)
{
    if (TimelineQuickItem *item = m_items[static_cast<std::size_t>(layer)])
        item->update();
}

void TimelineQuickView::syncRuler()
{
    if (!m_ruler)
        return;
    m_ruler->rebuildQuickScene(*m_scene);
    updateLayer(TimelineQuickLayer::RulerGutterChrome);
    updateLayer(TimelineQuickLayer::RulerChrome);
    updateLayer(TimelineQuickLayer::RulerMarks);
}

void TimelineQuickView::syncOtherEvents()
{
    if (!m_otherEvents)
        return;
    m_otherEvents->rebuildQuickScene(*m_scene);
    updateLayer(TimelineQuickLayer::OtherEventsGutterChrome);
    updateLayer(TimelineQuickLayer::OtherEventsChrome);
    updateLayer(TimelineQuickLayer::OtherEventsMarkers);
}

void TimelineQuickView::syncVelocity()
{
    if (!m_velocity)
        return;
    m_velocity->rebuildQuickScene(*m_scene);
    updateLayer(TimelineQuickLayer::VelocityGutterChrome);
    updateLayer(TimelineQuickLayer::VelocityChrome);
    updateLayer(TimelineQuickLayer::VelocityAxis);
    updateLayer(TimelineQuickLayer::VelocityGrid);
    updateLayer(TimelineQuickLayer::VelocityBands);
    updateLayer(TimelineQuickLayer::VelocityStems);
    updateLayer(TimelineQuickLayer::VelocityNodes);
    updateLayer(TimelineQuickLayer::VelocityTransient);
}

void TimelineQuickView::syncVoiceChanges(TimelineQuickDirtySet dirty)
{
    if (!m_voiceChanges)
        return;
    if (dirty & TimelineQuickDirty::VoiceChanges) {
        m_voiceChanges->rebuildQuickScene(*m_scene);
        updateLayer(TimelineQuickLayer::VoiceChangesGutterChrome);
        updateLayer(TimelineQuickLayer::VoiceChangesChrome);
        updateLayer(TimelineQuickLayer::VoiceChangesGrid);
        updateLayer(TimelineQuickLayer::VoiceChangesSpans);
        updateLayer(TimelineQuickLayer::VoiceChangesMarkers);
        updateLayer(TimelineQuickLayer::VoiceChangesTransient);
        if (m_voiceChanges->m_hoverActive)
            m_voiceChanges->rebuildQuickHover(*m_scene);
        updateLayer(TimelineQuickLayer::VoiceChangesHover);
    } else if (dirty & TimelineQuickDirty::VoiceChangesHover) {
        m_voiceChanges->rebuildQuickHover(*m_scene);
        updateLayer(TimelineQuickLayer::VoiceChangesHover);
    }
}

void TimelineQuickView::syncAutomation(AutomationRefreshSet refresh)
{
    if (refresh == AutomationRefresh::None || !m_automation || !m_automation->canvas())
        return;
    m_automation->canvas()->rebuildQuickScene(*m_scene, refresh);
    if (refresh.testFlag(AutomationRefresh::Content)) {
        updateLayer(TimelineQuickLayer::AutomationGutterChrome);
        updateLayer(TimelineQuickLayer::AutomationGrid);
        updateLayer(TimelineQuickLayer::AutomationCurves);
        updateLayer(TimelineQuickLayer::AutomationNodes);
        updateLayer(TimelineQuickLayer::AutomationSelection);
    }
    if (refresh.testFlag(AutomationRefresh::Transient))
        updateLayer(TimelineQuickLayer::AutomationTransient);
    if (refresh.testFlag(AutomationRefresh::Hover))
        updateLayer(TimelineQuickLayer::AutomationHover);
}

} // namespace songview
