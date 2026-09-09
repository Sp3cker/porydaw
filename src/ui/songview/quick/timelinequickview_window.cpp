#include "ui/songview/quick/timelinequickview.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"

#include <QKeyEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QUrl>
#include <QVariant>
#include <qqml.h>
#include <utility>

namespace songview {

namespace {

// The canvas QML's per-band rect/visibility/plot-rect property names, in
// canonical band order. attachScene() validates them after QML creation;
// publishTimelineBandLayout() writes them on every band-layout flush.
struct TimelineBandQmlProperties {
    TimelineBand band;
    const char *rect;
    const char *visible;
    const char *plotRect;
};

constexpr std::array kTimelineBandQmlProperties{
    TimelineBandQmlProperties{TimelineBand::Ruler, "rulerBandRect", "rulerBandVisible",
                              "rulerBandPlotRect"},
    TimelineBandQmlProperties{TimelineBand::Roll, "rollBandRect", "rollBandVisible",
                              "rollBandPlotRect"},
    TimelineBandQmlProperties{TimelineBand::OtherEvents, "otherEventsBandRect",
                              "otherEventsBandVisible", "otherEventsBandPlotRect"},
    TimelineBandQmlProperties{TimelineBand::Automation, "automationBandRect",
                              "automationBandVisible", "automationBandPlotRect"},
    TimelineBandQmlProperties{TimelineBand::Velocity, "velocityBandRect", "velocityBandVisible",
                              "velocityBandPlotRect"},
    TimelineBandQmlProperties{TimelineBand::VoiceChanges, "voiceChangesBandRect",
                              "voiceChangesBandVisible", "voiceChangesBandPlotRect"},
    TimelineBandQmlProperties{TimelineBand::TrackHeaders, "trackHeadersBandRect",
                              "trackHeadersBandVisible", "trackHeadersBandPlotRect"},
};
static_assert(kTimelineBandQmlProperties.size() == timelineBandIndex(TimelineBand::Count));

// The five drawer-chrome input items, in drawer-stack order.
struct DrawerChromeInputQmlProperties {
    DrawerChromeTarget target;
    const char *objectName;
};

constexpr std::array kDrawerChromeInputQmlProperties{
    DrawerChromeInputQmlProperties{DrawerChromeTarget::VoiceChangesHandle,
                                   "drawerVoiceChangesHandleInput"},
    DrawerChromeInputQmlProperties{DrawerChromeTarget::VelocityHandle, "drawerVelocityHandleInput"},
    DrawerChromeInputQmlProperties{DrawerChromeTarget::AutomationHandle,
                                   "drawerAutomationHandleInput"},
    DrawerChromeInputQmlProperties{DrawerChromeTarget::Bar, "drawerBarInput"},
    DrawerChromeInputQmlProperties{DrawerChromeTarget::Detent, "drawerDetentInput"},
};
static_assert(kDrawerChromeInputQmlProperties.size() == 5);

// True when any ancestor of the item clips; QQuickItem exposes only the
// local flag, so the effective clipping walks the chain.
bool ancestorClipActive(const QQuickItem &item)
{
    for (const QQuickItem *current = item.parentItem(); current; current = current->parentItem()) {
        if (current->clip())
            return true;
    }
    return false;
}

} // namespace
// True when the item lives inside this page's canvas subtree: the boundary

// for this page's grab release and any other subtree-scoped input action.
bool TimelineQuickView::isPageSubtreeItem(const QQuickItem &item) const
{
    if (!m_root)
        return false;
    for (const QQuickItem *current = &item; current; current = current->parentItem()) {
        if (current == m_root.data())
            return true;
    }
    return false;
}

TimelineQuickView::~TimelineQuickView()
{
    detachScene();
}

void TimelineQuickView::publishTimelineBandLayout()
{
    if (!m_songView)
        return;
    if (!m_root || !m_root->window())
        return; // detached or orphaned canvas: nothing left to publish to
    QObject *root = rootObject();

    // Band rects arrive already visible in canonical canvas coordinates,
    // so they publish directly without a window-sized override.
    for (const TimelineBandQmlProperties &properties : kTimelineBandQmlProperties) {
        const std::optional<TimelineBandGeometry> &band = m_bandLayout.geometry(properties.band);
        const QRectF bandRect = band ? QRectF{band->rect} : QRectF{};
        // Empty plot rects (TrackHeaders) stay empty.
        const QRectF bandPlotRect = band ? QRectF{band->plotRect} : QRectF{};
        if (!root->setProperty(properties.rect, QVariant::fromValue(bandRect)) ||
            !root->setProperty(properties.visible, QVariant::fromValue(band.has_value())) ||
            !root->setProperty(properties.plotRect, QVariant::fromValue(bandPlotRect))) {
            qFatal("Qt Quick timeline QML has incomplete band properties");
        }
    }

    // The event page replaces the roll band in EventList mode; its canonical
    // rectangle publishes like every band's.
    const QRect eventListRect = m_songView->eventListRect();
    const QRectF publishedEventListRect =
        eventListRect.isEmpty() ? QRectF{} : QRectF{eventListRect};
    if (!root->setProperty("eventListBandRect", QVariant::fromValue(publishedEventListRect)) ||
        !root->setProperty("eventListBandVisible", QVariant::fromValue(!eventListRect.isEmpty()))) {
        qFatal("Qt Quick timeline QML has incomplete event-list properties");
    }

    // Scrollbar lanes publish their canonical rectangles directly; empty
    // lanes stay empty.
    const QRect horizontalScrollbar = m_songView->horizontalScrollbarRect();
    const QRect verticalScrollbar = m_songView->verticalScrollbarRect();
    const QRectF publishedHorizontalScrollbar =
        horizontalScrollbar.isEmpty() ? QRectF{} : QRectF{horizontalScrollbar};
    const QRectF publishedVerticalScrollbar =
        verticalScrollbar.isEmpty() ? QRectF{} : QRectF{verticalScrollbar};

    const qreal publishedRulerPlotOrigin = m_songView->timelineSplitX();
    if (std::exchange(m_publishedRulerPlotOrigin, publishedRulerPlotOrigin) !=
        publishedRulerPlotOrigin)
        emit rulerPlotOriginChanged();
    const bool horizontalScrollbarChanged =
        std::exchange(m_publishedHorizontalScrollbarRect, publishedHorizontalScrollbar) !=
        publishedHorizontalScrollbar;
    const bool verticalScrollbarChanged =
        std::exchange(m_publishedVerticalScrollbarRect, publishedVerticalScrollbar) !=
        publishedVerticalScrollbar;
    if (horizontalScrollbarChanged || verticalScrollbarChanged)
        emit scrollbarRectsChanged();
}

void TimelineQuickView::attachToPage(QQuickItem *viewport)
{
    if (!viewport)
        qFatal("TimelineQuickView QML attachment requires a page viewport");
    if (!viewport->window())
        qFatal("TimelineQuickView QML attachment requires a window-associated page viewport");
    QQmlEngine *const engine = qmlEngine(viewport);
    if (!engine)
        qFatal("TimelineQuickView QML attachment requires an engine-backed page viewport");
    attachScene(*engine, *viewport);
}

void TimelineQuickView::attachScene(QQmlEngine &engine, QQuickItem &viewport)
{
    // Attachment is one-shot; every later call is a contract violation.
    if (m_hasAttached)
        qFatal("TimelineQuickView scene attached twice");
    m_hasAttached = true;
    // Defensive re-assertion: hosts register before constructing their
    // engine; the once-flag makes the repeat free.
    registerQuickTypes();
    if (m_sceneContext || m_root)
        qFatal("TimelineQuickView scene attached twice");
    // The popup session and the window event ports need a live window; the
    // window identity binds here and never moves afterwards.
    QQuickWindow *const window = viewport.window();
    if (!window)
        qFatal("TimelineQuickView scene attached to a viewport with no window");
    m_viewport = &viewport;
    m_view = window;
    m_engine = &engine;
    // Engine destruction terminally unbinds the coordinator.
    m_engineDestroyed = connect(&engine, &QObject::destroyed, this,
                                [this, &engine] { handleEngineDestroyed(engine); });

    // Per-scene context, parented to this coordinator and based on the
    // engine root context: page data never enters the engine root context.
    m_sceneContext = new QQmlContext(engine.rootContext(), this);
    m_sceneContext->setContextProperty(QStringLiteral("timelineQuickView"), this);
    m_sceneContext->setContextProperty(QStringLiteral("timelineScene"), m_scene);
    m_sceneContext->setContextProperty(QStringLiteral("drawerChrome"), m_drawerChrome.data());
    m_sceneContext->setContextProperty(QStringLiteral("trackHeaderModel"), m_trackHeaders.data());
    m_sceneContext->setContextProperty(QStringLiteral("timeRuler"), m_ruler);
    m_sceneContext->setContextProperty(QStringLiteral("otherStrip"), m_otherEvents.data());
    m_sceneContext->setContextProperty(QStringLiteral("eventListController"), m_eventList.data());

    // The icon provider must resolve before the QML creates its image
    // sources; detachScene() releases it after the consumers die.
    if (m_drawerChrome)
        m_drawerChrome->attachIconProvider(engine);

    observeWindow(*window);

    // QML anchors the coordinator-owned canvas to this borrowed viewport.
    QQmlComponent component(&engine,
                            QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/TimelineCanvas.qml")));
    QQuickItem *const root = qobject_cast<QQuickItem *>(component.create(m_sceneContext));
    if (!root || component.isError()) {
        for (const QQmlError &error : component.errors())
            qCritical().noquote() << error.toString();
        qFatal("Qt Quick timeline QML failed to load");
    }
    // QObject ownership stays with the coordinator across viewport teardown.
    root->setParentItem(&viewport);
    root->setParent(this);
    m_root = root;
    // Bind page-scoped keyboard and popup borrows after canvas creation.
    if (m_automation)
        m_automation->setInputPage(root);
    retargetPopupSession(window);

    const auto canvasResized = [this] {
        if (m_detaching)
            return;
        emit viewportChanged();
        scheduleTimelineBandLayoutPublication();
    };
    connect(root, &QQuickItem::widthChanged, this, canvasResized);
    connect(root, &QQuickItem::heightChanged, this, canvasResized);

    static constexpr std::array layers = {
        std::pair{TimelineQuickLayer::RulerGutterChrome, "timelineQuickRulerGutterChrome"},
        std::pair{TimelineQuickLayer::RulerChrome, "timelineQuickRulerChrome"},
        std::pair{TimelineQuickLayer::RulerMarks, "timelineQuickRulerMarks"},
        std::pair{TimelineQuickLayer::PianoGrid, "timelineQuickPianoGrid"},
        std::pair{TimelineQuickLayer::PianoNoteFills, "timelineQuickPianoNoteFills"},
        std::pair{TimelineQuickLayer::PianoDrawPreviewFill, "timelineQuickPianoDrawPreviewFill"},
        std::pair{TimelineQuickLayer::PianoNoteBordersAndSelection,
                  "timelineQuickPianoNoteBordersAndSelection"},
        std::pair{TimelineQuickLayer::PianoOverlay, "timelineQuickPianoOverlay"},
        std::pair{TimelineQuickLayer::PianoKeyboardKeys, "timelineQuickPianoKeyboardKeys"},
        std::pair{TimelineQuickLayer::PianoKeyboardHighlights,
                  "timelineQuickPianoKeyboardHighlights"},
        std::pair{TimelineQuickLayer::OtherEventsGutterChrome,
                  "timelineQuickOtherEventsGutterChrome"},
        std::pair{TimelineQuickLayer::OtherEventsChrome, "timelineQuickOtherEventsChrome"},
        std::pair{TimelineQuickLayer::OtherEventsMarkers, "timelineQuickOtherEventsMarkers"},
        std::pair{TimelineQuickLayer::VelocityGutterChrome, "timelineQuickVelocityGutterChrome"},
        std::pair{TimelineQuickLayer::VelocityChrome, "timelineQuickVelocityChrome"},
        std::pair{TimelineQuickLayer::VelocityAxis, "timelineQuickVelocityAxis"},
        std::pair{TimelineQuickLayer::VelocityGrid, "timelineQuickVelocityGrid"},
        std::pair{TimelineQuickLayer::VelocityBands, "timelineQuickVelocityBands"},
        std::pair{TimelineQuickLayer::VelocityStems, "timelineQuickVelocityStems"},
        std::pair{TimelineQuickLayer::VelocityNodes, "timelineQuickVelocityNodes"},
        std::pair{TimelineQuickLayer::VelocityTransient, "timelineQuickVelocityTransient"},
        std::pair{TimelineQuickLayer::VoiceChangesGutterChrome,
                  "timelineQuickVoiceChangesGutterChrome"},
        std::pair{TimelineQuickLayer::VoiceChangesChrome, "timelineQuickVoiceChangesChrome"},
        std::pair{TimelineQuickLayer::VoiceChangesGrid, "timelineQuickVoiceChangesGrid"},
        std::pair{TimelineQuickLayer::VoiceChangesSpans, "timelineQuickVoiceChangesSpans"},
        std::pair{TimelineQuickLayer::VoiceChangesMarkers, "timelineQuickVoiceChangesMarkers"},
        std::pair{TimelineQuickLayer::VoiceChangesTransient, "timelineQuickVoiceChangesTransient"},
        std::pair{TimelineQuickLayer::VoiceChangesHover, "timelineQuickVoiceChangesHover"},
        std::pair{TimelineQuickLayer::AutomationGutterChrome,
                  "timelineQuickAutomationGutterChrome"},
        std::pair{TimelineQuickLayer::AutomationGrid, "timelineQuickAutomationGrid"},
        std::pair{TimelineQuickLayer::AutomationCurves, "timelineQuickAutomationCurves"},
        std::pair{TimelineQuickLayer::AutomationNodes, "timelineQuickAutomationNodes"},
        std::pair{TimelineQuickLayer::AutomationSelection, "timelineQuickAutomationSelection"},
        std::pair{TimelineQuickLayer::AutomationTransient, "timelineQuickAutomationTransient"},
        std::pair{TimelineQuickLayer::AutomationHover, "timelineQuickAutomationHover"},
    };
    static_assert(layers.size() == static_cast<std::size_t>(TimelineQuickLayer::Count));
    for (const auto &[layer, name] : layers) {
        auto *item = root->findChild<TimelineQuickItem *>(QString::fromLatin1(name));
        if (!item)
            qFatal("Qt Quick timeline QML has no item '%s' for scene layer %d", name,
                   static_cast<int>(layer));
        if (item->sceneLayer() != layer)
            qFatal("Qt Quick timeline item '%s' declares scene layer %d, expected %d", name,
                   static_cast<int>(item->sceneLayer()), static_cast<int>(layer));
        item->setScene(m_scene);
        m_items[static_cast<std::size_t>(layer)] = item;
    }

    static constexpr std::array chromeItems = {
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickRulerHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickRulerEditChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickRollHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickRollEditChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickAutomationHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickAutomationEditChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickVelocityHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickVelocityEditChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickVoiceChangesHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickVoiceChangesEditChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickOtherEventsHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickOtherEventsEditChrome"},
    };
    static_assert(chromeItems.size() == 12);
    for (std::size_t index = 0; index < chromeItems.size(); ++index) {
        const auto &[kind, name] = chromeItems[index];
        auto *item = root->findChild<TimelineChromeItem *>(QString::fromLatin1(name));
        if (!item)
            qFatal("Qt Quick timeline QML has no chrome item '%s'", name);
        if (item->kind() != kind) {
            qFatal("Qt Quick timeline chrome item '%s' declares kind %d, expected %d", name,
                   static_cast<int>(item->kind()), static_cast<int>(kind));
        }
        m_chromeItems[index] = item;
    }
    for (const TimelineBandQmlProperties &properties : kTimelineBandQmlProperties) {
        if (!root->property(properties.rect).isValid())
            qFatal("Qt Quick timeline QML has no band property '%s'", properties.rect);
        if (!root->property(properties.visible).isValid())
            qFatal("Qt Quick timeline QML has no band property '%s'", properties.visible);
        if (!root->property(properties.plotRect).isValid())
            qFatal("Qt Quick timeline QML has no band property '%s'", properties.plotRect);
    }

    const auto bindInput = [&root](QPointer<TimelineInputItem> &destination,
                                   TimelineBandInteraction *interaction, const char *objectName,
                                   TimelineInputSurface surface, bool attachHost) {
        TimelineInputItem *const input =
            root->findChild<TimelineInputItem *>(QString::fromLatin1(objectName));
        if (!input)
            qFatal("Qt Quick timeline QML has no input item '%s'", objectName);
        input->setInteraction(interaction, surface, attachHost);
        destination = input;
    };

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::Ruler)], m_ruler, "timelineRulerInput",
              TimelineInputSurface::Plot, true);
    bindInput(m_gutterInputItems[timelineBandIndex(TimelineBand::Ruler)], m_ruler,
              "timelineRulerGutterInput", TimelineInputSurface::Gutter, false);

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::Roll)], m_roll.data(),
              "timelineRollInput", TimelineInputSurface::Plot, true);
    bindInput(m_gutterInputItems[timelineBandIndex(TimelineBand::Roll)], m_roll.data(),
              "timelineRollGutterInput", TimelineInputSurface::Gutter, false);

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::OtherEvents)], m_otherEvents.data(),
              "timelineOtherEventsInput", TimelineInputSurface::Plot, true);
    bindInput(m_gutterInputItems[timelineBandIndex(TimelineBand::OtherEvents)],
              m_otherEvents.data(), "timelineOtherEventsGutterInput", TimelineInputSurface::Gutter,
              false);

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::Automation)], m_automation->canvas(),
              "timelineAutomationInput", TimelineInputSurface::Plot, true);
    bindInput(m_gutterInputItems[timelineBandIndex(TimelineBand::Automation)],
              m_automation->canvas(), "timelineAutomationGutterInput", TimelineInputSurface::Gutter,
              false);

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::Velocity)], m_velocity.data(),
              "timelineVelocityInput", TimelineInputSurface::Plot, true);
    bindInput(m_gutterInputItems[timelineBandIndex(TimelineBand::Velocity)], m_velocity.data(),
              "timelineVelocityGutterInput", TimelineInputSurface::Gutter, false);

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::VoiceChanges)], m_voiceChanges.data(),
              "timelineVoiceChangesInput", TimelineInputSurface::Plot, true);
    bindInput(m_gutterInputItems[timelineBandIndex(TimelineBand::VoiceChanges)],
              m_voiceChanges.data(), "timelineVoiceChangesGutterInput",
              TimelineInputSurface::Gutter, false);

    bindInput(m_inputItems[timelineBandIndex(TimelineBand::TrackHeaders)], m_trackHeaders.data(),
              "timelineTrackHeadersInput", TimelineInputSurface::Gutter, true);
    // EventList mode: the page's input item joins the shared key-policy
    // chain; its interaction owns only the row-local commands. The item
    // exists whenever the scene exists, independent of page visibility.
    m_eventListInteraction = std::make_unique<EventListInteraction>(*m_eventList);
    bindInput(m_eventListInput, m_eventListInteraction.get(), "timelineEventListInput",
              TimelineInputSurface::Plot, true);

    for (std::size_t index = 0; index < kDrawerChromeInputQmlProperties.size(); ++index) {
        const DrawerChromeInputQmlProperties &properties = kDrawerChromeInputQmlProperties[index];
        TimelineInputItem *const input =
            root->findChild<TimelineInputItem *>(QString::fromLatin1(properties.objectName));
        if (!input) {
            qFatal("Qt Quick timeline QML has no drawer chrome input '%s'", properties.objectName);
        }
        input->setInteraction(&m_drawerChrome->interaction(properties.target));
        m_drawerChromeInputs[index] = input;
    }
    // Discover typed scrollbars once from the live canvas.
    discoverGestureScrollbars(*root);

    // Route declined local input through SongView's shared key policy.
    installKeyPolicyHandlers();

    // Seed one local focus target; QML retains it when the page is reselected.
    const auto drawerFocusTarget = [this](EditorDrawerPage page) -> TimelineInputItem * {
        switch (page) {
        case EditorDrawerPage::VoiceChanges:
            return m_inputItems[timelineBandIndex(TimelineBand::VoiceChanges)];
        case EditorDrawerPage::Velocity:
            return m_inputItems[timelineBandIndex(TimelineBand::Velocity)];
        case EditorDrawerPage::Automations:
            return m_inputItems[timelineBandIndex(TimelineBand::Automation)];
        }
        Q_UNREACHABLE();
        return nullptr;
    };
    TimelineInputItem *initialFocusTarget = nullptr;
    if (m_songView && m_songView->hasVisibleDrawerSection()) {
        const EditorDrawerPage activePage = m_songView->drawerActivePage();
        if (m_songView->drawerSectionVisible(activePage))
            initialFocusTarget = drawerFocusTarget(activePage);
        for (const EditorDrawerPage page :
             {EditorDrawerPage::VoiceChanges, EditorDrawerPage::Velocity,
              EditorDrawerPage::Automations}) {
            if (!initialFocusTarget && m_songView->drawerSectionVisible(page))
                initialFocusTarget = drawerFocusTarget(page);
        }
    } else if (m_songView && m_songView->eventListVisible()) {
        initialFocusTarget = m_eventListInput;
    } else {
        initialFocusTarget = m_inputItems[timelineBandIndex(TimelineBand::Roll)];
    }
    if (initialFocusTarget)
        initialFocusTarget->setFocus(true);

    // Begin mapping reports and page eligibility after attachment.
    watchSceneMapping();
    updateInputEligibility();

    // Publish the complete scene before notifying SongView.
    publishTimelineBandLayout();
    syncAppearance();
    emit viewportChanged();
}

void TimelineQuickView::observeWindow(QQuickWindow &window)
{
    window.installEventFilter(this);
    connect(&window, &QWindow::screenChanged, this, &TimelineQuickView::viewportChanged);
    // Visibility signals sample the final window state after Show/Hide events.
    connect(&window, &QWindow::visibleChanged, this, [this](bool) {
        if (!m_detaching)
            updateInputEligibility();
    });
}

void TimelineQuickView::retargetPopupSession(QQuickWindow *window)
{
    // Create the bound window's sole popup session once at attach time.
    if (m_popupSession) {
        m_popupSession->cancel(false);
        setPopupSessionBindings(nullptr);
        delete m_popupSession;
        m_popupSession = nullptr;
    }
    if (!window || !m_sceneContext || !m_root)
        return;
    m_popupSession = new QuickPopupSession(*window, *m_sceneContext, this);
    setPopupSessionBindings(m_popupSession);
    m_popupSession->setPageRoot(m_root.data());
    connect(this, &TimelineQuickView::viewportChanged, m_popupSession,
            &QuickPopupSession::handlePageGeometryChanged);
}

void TimelineQuickView::setPopupSessionBindings(QuickPopupSession *session)
{
    if (m_eventList)
        m_eventList->setPopupSession(session);
    if (m_roll)
        m_roll->setPopupSession(session);
    if (m_trackHeaders)
        m_trackHeaders->setPopupSession(session);
    if (m_automation && m_automation->canvas())
        m_automation->canvas()->setPopupSession(session);
    if (m_voiceChanges)
        m_voiceChanges->setPopupSession(session);
}

void TimelineQuickView::handleEngineDestroyed(const QQmlEngine &engine)
{
    if (m_detaching || m_engine != &engine)
        return;
    // Unexpected engine loss terminally unbinds borrowed scene objects.
    // Remaining coordinator-owned inert objects finish teardown in detachScene().
    m_detaching = true;
    m_engine = nullptr;
    if (m_engineDestroyed)
        disconnect(m_engineDestroyed);
    m_engineDestroyed = {};
    if (QQuickWindow *const window = m_view.data()) {
        window->removeEventFilter(this);
        disconnect(window, nullptr, this, nullptr);
    }
    if (m_viewport)
        disconnect(m_viewport.data(), nullptr, this, nullptr);
    disconnectSceneMappingWatch();
    if (m_popupSession)
        m_popupSession->cancel(false);
    unbindSceneInputs();
    delete m_root.data();
    m_root.clear();
    m_detaching = false;
    updateInputEligibility();
}

void TimelineQuickView::detachScene()
{
    // Teardown is idempotent and never destroys host-owned objects.
    // Re-entry during windowAboutToDetach is inert.
    if (m_detaching)
        return;
    if (!m_sceneContext && !m_popupSession)
        return;
    m_detaching = true;

    m_layoutTimer.stop();
    m_flushTimer.stop();
    // The engine-loss observation is a live-attachment concern only.
    if (m_engineDestroyed)
        disconnect(m_engineDestroyed);
    m_engineDestroyed = {};
    m_engine = nullptr;

    // Transient Quick-scene state cancels while every input item still
    // exists; the wiring then detaches exactly once per item.
    if (m_popupSession)
        m_popupSession->cancel(false);
    cancelActiveGestures();

    // Native attachments clear while the window is still valid.
    if (m_view)
        emit windowAboutToDetach();

    // Stop surveillance before destroying the scene subtree.
    if (m_view) {
        m_view->removeEventFilter(this);
        disconnect(m_view.data(), nullptr, this, nullptr);
    }
    if (m_viewport)
        disconnect(m_viewport.data(), nullptr, this, nullptr);
    m_view.clear();
    m_viewport.clear();

    disconnectSceneMappingWatch();

    // Unbind every interaction while its domain model remains alive.
    unbindSceneInputs();
    delete m_root.data();
    m_root.clear();

    // The overlay consumers are gone; the session (created in the scene
    // context) goes next, then the context, then the icon provider.
    delete m_popupSession;
    m_popupSession = nullptr;
    delete m_sceneContext;
    m_sceneContext = nullptr;
    if (m_drawerChrome)
        m_drawerChrome->detachIconProvider();

    m_detaching = false;
    updateInputEligibility();
}

// One cohesive hostless input-unbinding path shared by detachScene() and the
// engine-loss observation (the corrective-review carry): detaches every
// interaction, key policy, and session binding while the domain models are
// alive, and clears the raw QML borrows so the QML tree deletion that
// follows finds inert items. Callers cancel transients first; this never
// touches host-owned resources and is safe even with the borrowed window
// already dying.
void TimelineQuickView::unbindSceneInputs()
{
    clearKeyPolicyHandlers();
    m_gestureScrollbars.clear();
    for (TimelineInputItem *item : m_drawerChromeInputs) {
        if (item)
            item->setInteraction(nullptr);
    }
    for (TimelineInputItem *item : m_gutterInputItems) {
        if (item)
            item->setInteraction(nullptr);
    }
    for (TimelineInputItem *item : m_inputItems) {
        if (item)
            item->setInteraction(nullptr);
    }
    if (m_eventListInput) {
        m_eventListInput->clearKeyPolicy();
        m_eventListInput->setInteraction(nullptr);
    }
    m_eventListInteraction.reset();
    // The automation page's borrowed page root and the popup session's page
    // root go with the canvas they borrow into.
    if (m_automation)
        m_automation->setInputPage(nullptr);
    if (m_popupSession)
        m_popupSession->setPageRoot(nullptr);
    setPopupSessionBindings(nullptr);
    m_items.fill(nullptr);
    m_chromeItems.fill(nullptr);
    m_inputItems.fill(nullptr);
    m_gutterInputItems.fill(nullptr);
    m_drawerChromeInputs.fill(nullptr);
    m_eventListInput.clear();
}

// Effective visibility of the canvas through every ancestor item up to the
// window: QQuickItem::isVisible() reads only the local flag.
bool TimelineQuickView::sceneEffectivelyVisible() const
{
    if (!m_root)
        return false;
    for (const QQuickItem *item = m_root.data(); item; item = item->parentItem()) {
        if (!item->isVisible())
            return false;
    }
    return true;
}

// Recomputes page-scoped input eligibility and applies its observable
// edges: the canvas subtree enables or disables as a whole — never the
// shared window or any sibling page — and losing eligibility cancels this
// page's outgoing pointer/key transients, popup, and audition without
// focus restoration. The grab release inside cancellation stays bounded to
// this page's subtree.
void TimelineQuickView::updateInputEligibility()
{
    const bool eligible = m_pageSelected && m_inputReady && m_root && m_view &&
                          sceneEffectivelyVisible() && m_view->isVisible();
    if (m_root && m_root->isEnabled() != eligible)
        m_root->setEnabled(eligible);
    if (eligible == m_inputEligible)
        return;
    m_inputEligible = eligible;
    emit inputEligibleChanged();
    // The cancellation edge is semantic and runs only while a live scene
    // can still own transients: the teardown paths already cancelled
    // exactly once, so the final post-teardown flip publishes truthfully
    // without re-entering cancellation.
    if (!eligible && m_root && m_view && !m_detaching) {
        cancelActiveGestures();
        if (m_popupSession)
            m_popupSession->cancel(false);
    }
}

bool TimelineQuickView::inputEligible() const noexcept
{
    return m_inputEligible;
}

void TimelineQuickView::setInputReady(bool ready)
{
    // Standalone domain views default ready; hosts and SongTab project the
    // real readiness here. Readiness loss cancels outgoing transients
    // through the eligibility edge below.
    if (m_inputReady == ready)
        return;
    m_inputReady = ready;
    updateInputEligibility();
}

void TimelineQuickView::setPageSelected(bool selected)
{
    // Hosts select explicitly; this flag alone never touches the window
    // arbiter's routing. Deselection cancels outgoing transients through
    // the eligibility edge below.
    if (m_pageSelected == selected)
        return;
    m_pageSelected = selected;
    updateInputEligibility();
}

QRectF clippedSceneRect(const QQuickItem &item, const QRectF &localRect)
{
    QRectF sceneRect = item.mapRectToScene(localRect);
    for (const QQuickItem *ancestor = &item; ancestor && !sceneRect.isEmpty();
         ancestor = ancestor->parentItem()) {
        if (ancestor->clip())
            sceneRect &= ancestor->mapRectToScene(ancestor->boundingRect());
    }
    return sceneRect;
}

// Watches the canvas's ancestor chain so viewportChanged also reports scene
// mapping (the canvas rect mapped through every ancestor), effective
// visibility, effective ancestor clipping, and the clipped intersection —
// native overlays and popups retarget from that signal without a window
// resize. The watch is built when the scene attaches and torn down with
// it.
void TimelineQuickView::watchSceneMapping()
{
    disconnectSceneMappingWatch();
    if (!m_root)
        return;
    const auto report = [this] {
        if (m_detaching || !m_root)
            return;
        const QRectF sceneRect =
            m_root->mapRectToScene(QRectF{0.0, 0.0, m_root->width(), m_root->height()});
        const bool visible = sceneEffectivelyVisible();
        const bool clipped = ancestorClipActive(*m_root);
        const QRectF clipRect = clippedSceneRect(*m_root, m_root->boundingRect());
        if (sceneRect == m_reportedSceneRect && visible == m_reportedSceneVisible &&
            clipped == m_reportedSceneClipped && clipRect == m_reportedClipRect)
            return;
        m_reportedSceneRect = sceneRect;
        m_reportedSceneVisible = visible;
        m_reportedSceneClipped = clipped;
        m_reportedClipRect = clipRect;
        updateInputEligibility();
        emit viewportChanged();
    };
    // The root's own width/height keep their single publisher: the
    // canvasResized connection above (viewportChanged + band-layout
    // republish). The watch adds root position/visibility/clipping and —
    // with size signals, since a clip/translate ancestor resize changes the
    // intersection without moving the root — the full signal set on every
    // ancestor.
    for (QQuickItem *item = m_root.data(); item; item = item->parentItem()) {
        const bool isRoot = item == m_root.data();
        m_sceneMappingWatch.push_back(connect(item, &QQuickItem::xChanged, this, report));
        m_sceneMappingWatch.push_back(connect(item, &QQuickItem::yChanged, this, report));
        if (!isRoot) {
            m_sceneMappingWatch.push_back(connect(item, &QQuickItem::widthChanged, this, report));
            m_sceneMappingWatch.push_back(connect(item, &QQuickItem::heightChanged, this, report));
        }
        m_sceneMappingWatch.push_back(connect(item, &QQuickItem::visibleChanged, this, report));
        m_sceneMappingWatch.push_back(connect(item, &QQuickItem::clipChanged, this, report));
    }
    m_reportedSceneRect =
        m_root->mapRectToScene(QRectF{0.0, 0.0, m_root->width(), m_root->height()});
    m_reportedSceneVisible = sceneEffectivelyVisible();
    m_reportedSceneClipped = ancestorClipActive(*m_root);
    m_reportedClipRect = clippedSceneRect(*m_root, m_root->boundingRect());
    updateInputEligibility();
}

void TimelineQuickView::disconnectSceneMappingWatch()
{
    for (const QMetaObject::Connection &connection : m_sceneMappingWatch)
        disconnect(connection);
    m_sceneMappingWatch.clear();
}

QQuickItem *TimelineQuickView::rootObject() const
{
    return m_root.data();
}

QQuickWindow *TimelineQuickView::quickWindow() const
{
    return m_view.data();
}

QuickPopupSession *TimelineQuickView::popupSession() const noexcept
{
    return m_popupSession;
}

qreal TimelineQuickView::quickDevicePixelRatio() const
{
    return m_view ? m_view->effectiveDevicePixelRatio() : 1.0;
}

bool TimelineQuickView::eventFilter(QObject *watched, QEvent *event)
{
    QQuickWindow *const window = m_view.data();
    if (watched != window)
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::Resize:
        // The viewport is the canonical viewport: surface resizes reframe the
        // camera and the band layout, so SongView updates its geometry
        // while this view republishes its stored layout.
        emit viewportChanged();
        scheduleTimelineBandLayoutPublication();
        break;
    case QEvent::DevicePixelRatioChange:
        // Fractional scale changes move quickDevicePixelRatio(); the same
        // publication keeps physical-pixel math converged. Screen moves
        // arrive through the screenChanged connection.
        emit viewportChanged();
        scheduleTimelineBandLayoutPublication();
        break;
    // No FocusIn handling by design: Qt clears the scene's activeFocusItem
    // while the window is inactive, so any retarget here fires with a null
    // focus item and steals from scoped editors (rename, value prompts) that
    // Qt restores itself on activation. Explicit focusBand() and
    // focusActiveSurface() callers remain the only focus drivers.
    case QEvent::Hide:
    case QEvent::WindowDeactivate:
        // A hidden or deactivated surface
        // cancels every live Quick interaction exactly once. Per-item
        // mouseUngrabEvent() already covers window ungrabs, and the
        // eligibility edge cancels popups and auditions too.
        cancelActiveGestures();
        updateInputEligibility();
        break;
    case QEvent::Show:
        // Re-exposure: window visibility gates eligibility.
        updateInputEligibility();
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

} // namespace songview
