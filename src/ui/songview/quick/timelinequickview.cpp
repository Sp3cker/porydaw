#include "ui/songview/quick/timelinequickview.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timeruler.h"
#include <QColor>
#include <QPoint>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickView>
#include <QRegion>
#include <QSurfaceFormat>
#include <QUrl>
#include <QVariant>
#include <QtQml>
#include <algorithm>
#include <array>
#include <chrono>
#include <mutex>
#include <utility>
#ifdef Q_OS_MACOS
void installMacAutomationHoverPassThrough(AutomationCanvas &canvas, QObject &owner);
#endif

namespace songview {

struct TimelineBandQmlProperties {
    TimelineBand band;
    const char *rect;
    const char *visible;
};

constexpr std::array kTimelineBandQmlProperties{
    TimelineBandQmlProperties{TimelineBand::Ruler, "rulerBandRect", "rulerBandVisible"},
    TimelineBandQmlProperties{TimelineBand::Roll, "rollBandRect", "rollBandVisible"},
    TimelineBandQmlProperties{TimelineBand::OtherEvents, "otherEventsBandRect",
                              "otherEventsBandVisible"},
    TimelineBandQmlProperties{TimelineBand::Automation, "automationBandRect",
                              "automationBandVisible"},
    TimelineBandQmlProperties{TimelineBand::Velocity, "velocityBandRect", "velocityBandVisible"},
    TimelineBandQmlProperties{TimelineBand::VoiceChanges, "voiceChangesBandRect",
                              "voiceChangesBandVisible"},
};
static_assert(kTimelineBandQmlProperties.size() == timelineBandIndex(TimelineBand::Count));

TimelineQuickView::TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                                     AutomationPage &automation, VelocityArea &velocity,
                                     VoiceChangeArea &voiceChanges, SongView &songView)
    : QWidget(&songView)
    , m_ruler(&ruler)
    , m_roll(&roll)
    , m_otherEvents(&otherEvents)
    , m_automation(&automation)
    , m_velocity(&velocity)
    , m_voiceChanges(&voiceChanges)
    , m_songView(&songView)
{
    m_layoutTimer.setSingleShot(true);
    m_layoutTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_layoutTimer, &QTimer::timeout, this, &TimelineQuickView::publishTimelineBandLayout);
    m_flushTimer.setSingleShot(true);
    m_flushTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_flushTimer, &QTimer::timeout, this, &TimelineQuickView::flushUpdate);

    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<TimelineChromeItem>("Porydaw.Ui", 1, 0, "TimelineChromeItem");
        qmlRegisterType<TimelineInputItem>("Porydaw.Ui", 1, 0, "TimelineInputItem");
        qmlRegisterType<TimelineQuickItem>("Porydaw.Ui", 1, 0, "TimelineQuickItem");
    });

    setObjectName(QStringLiteral("timelineQuickCanvas"));
    setFocusPolicy(Qt::NoFocus);

    m_quickView = new QQuickView;
    QSurfaceFormat surfaceFormat = m_quickView->format();
    surfaceFormat.setAlphaBufferSize(8);
    m_quickView->setFormat(surfaceFormat);
    m_quickView->setColor(Qt::transparent);
    m_quickView->setResizeMode(QQuickView::SizeRootObjectToView);
    m_quickContainer = QWidget::createWindowContainer(m_quickView, this);
    m_quickContainer->setFocusPolicy(Qt::NoFocus);
    m_quickView->installEventFilter(this);
    m_quickContainer->setGeometry(rect());

    m_scene = new TimelineQuickScene(this);
    m_quickView->rootContext()->setContextProperty(QStringLiteral("timelineQuickView"), this);
    m_quickView->rootContext()->setContextProperty(QStringLiteral("timelineScene"), m_scene);
    m_quickView->setSource(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/TimelineCanvas.qml")));
    if (m_quickView->status() != QQuickView::Ready) {
        for (const QQmlError &error : m_quickView->errors())
            qCritical().noquote() << error.toString();
        qFatal("Qt Quick timeline QML failed to load");
    }

    QObject *root = rootObject();
    if (!root)
        qFatal("Qt Quick timeline QML has no root object");

    static constexpr std::array layers = {
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
        std::pair{TimelineQuickLayer::OtherEventsChrome, "timelineQuickOtherEventsChrome"},
        std::pair{TimelineQuickLayer::OtherEventsMarkers, "timelineQuickOtherEventsMarkers"},
        std::pair{TimelineQuickLayer::VelocityChrome, "timelineQuickVelocityChrome"},
        std::pair{TimelineQuickLayer::VelocityAxis, "timelineQuickVelocityAxis"},
        std::pair{TimelineQuickLayer::VelocityGrid, "timelineQuickVelocityGrid"},
        std::pair{TimelineQuickLayer::VelocityBands, "timelineQuickVelocityBands"},
        std::pair{TimelineQuickLayer::VelocityStems, "timelineQuickVelocityStems"},
        std::pair{TimelineQuickLayer::VelocityNodes, "timelineQuickVelocityNodes"},
        std::pair{TimelineQuickLayer::VelocityTransient, "timelineQuickVelocityTransient"},
        std::pair{TimelineQuickLayer::VoiceChangesChrome, "timelineQuickVoiceChangesChrome"},
        std::pair{TimelineQuickLayer::VoiceChangesGrid, "timelineQuickVoiceChangesGrid"},
        std::pair{TimelineQuickLayer::VoiceChangesSpans, "timelineQuickVoiceChangesSpans"},
        std::pair{TimelineQuickLayer::VoiceChangesMarkers, "timelineQuickVoiceChangesMarkers"},
        std::pair{TimelineQuickLayer::VoiceChangesTransient, "timelineQuickVoiceChangesTransient"},
        std::pair{TimelineQuickLayer::VoiceChangesHover, "timelineQuickVoiceChangesHover"},
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
    }

    // Converted bands attach through their matching input items; the
    // automation band deliberately remains without an entry until its phase.
    TimelineInputItem *const rulerInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    if (!rulerInput)
        qFatal("Qt Quick timeline QML has no input item 'timelineRulerInput'");
    rulerInput->setInteraction(m_ruler);
    m_inputItems[timelineBandIndex(TimelineBand::Ruler)] = rulerInput;
    TimelineInputItem *const velocityInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineVelocityInput"));
    if (!velocityInput)
        qFatal("Qt Quick timeline QML has no input item 'timelineVelocityInput'");
    velocityInput->setInteraction(m_velocity.data());
    m_inputItems[timelineBandIndex(TimelineBand::Velocity)] = velocityInput;
    TimelineInputItem *const voiceChangesInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineVoiceChangesInput"));
    if (!voiceChangesInput)
        qFatal("Qt Quick timeline QML has no input item 'timelineVoiceChangesInput'");
    voiceChangesInput->setInteraction(m_voiceChanges.data());
    m_inputItems[timelineBandIndex(TimelineBand::VoiceChanges)] = voiceChangesInput;
    TimelineInputItem *const otherEventsInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineOtherEventsInput"));
    if (!otherEventsInput)
        qFatal("Qt Quick timeline QML has no input item 'timelineOtherEventsInput'");
    otherEventsInput->setInteraction(m_otherEvents.data());
    m_inputItems[timelineBandIndex(TimelineBand::OtherEvents)] = otherEventsInput;
    TimelineInputItem *const rollInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    if (!rollInput)
        qFatal("Qt Quick timeline QML has no input item 'timelineRollInput'");
    rollInput->setInteraction(m_roll.data());
    m_inputItems[timelineBandIndex(TimelineBand::Roll)] = rollInput;

    QWidget *const rulerControls = m_songView->findChild<QWidget *>(
        QStringLiteral("timeRulerControls"), Qt::FindDirectChildrenOnly);
    if (!rulerControls)
        qFatal("Timeline Quick host cannot find native ruler controls");
    m_nativeChrome[0] = rulerControls;

    static constexpr std::array nativeChromeNames = {
        "velocityResizeHandle", "voiceChangesResizeHandle", "automationResizeHandle",
        "automationDrawerBar",  "velocityDetentToggle",
    };
    QWidget *const drawerSections =
        m_songView->findChild<QWidget *>(QStringLiteral("drawerSections"));
    for (std::size_t index = 0; index < nativeChromeNames.size(); ++index) {
        QWidget *const chrome = drawerSections ? drawerSections->findChild<QWidget *>(
                                                     QString::fromLatin1(nativeChromeNames[index]),
                                                     Qt::FindDirectChildrenOnly)
                                               : nullptr;
        if (!chrome)
            qFatal("Timeline Quick host cannot find drawer chrome '%s'", nativeChromeNames[index]);
        m_nativeChrome[index + 1] = chrome;
    }
#ifdef Q_OS_MACOS
    if (AutomationCanvas *const canvas = automation.canvas())
        installMacAutomationHoverPassThrough(*canvas, *this);
#endif
    syncAppearance();
}

TimelineQuickView::~TimelineQuickView()
{
    for (TimelineInputItem *item : m_inputItems) {
        if (item)
            item->setInteraction(nullptr);
    }
    m_quickView->setSource(QUrl{});
}

void TimelineQuickView::detachInputInteraction(TimelineBand band)
{
    if (TimelineInputItem *const item = m_inputItems[timelineBandIndex(band)])
        item->setInteraction(nullptr);
}

qreal TimelineQuickView::quickDevicePixelRatio() const
{
    return m_quickView ? m_quickView->effectiveDevicePixelRatio() : devicePixelRatioF();
}

qreal TimelineQuickView::hoverRootContentX() const noexcept
{
    return m_hoverSongViewContentX ? quickRootXForSongViewX(*m_hoverSongViewContentX) : 0.0;
}

bool TimelineQuickView::hoverVisible() const noexcept
{
    return m_hoverSongViewContentX.has_value();
}

qreal TimelineQuickView::editRootContentX() const noexcept
{
    return m_editSongViewContentX ? quickRootXForSongViewX(*m_editSongViewContentX) : 0.0;
}

bool TimelineQuickView::editVisible() const noexcept
{
    return m_editSongViewContentX.has_value();
}

void TimelineQuickView::synchronizeGuides(qreal songViewTimelineOriginX,
                                          std::optional<qreal> editSongViewContentX)
{
    setEditChrome(editSongViewContentX);
    if (m_hoverOwner != TimelineQuickHoverOwner::None && m_songView)
        setHoverChrome(songViewTimelineOriginX + m_songView->contentX(m_hoverTick));
}

void TimelineQuickView::publishHover(TimelineQuickHoverOwner owner, uint64_t tick,
                                     qreal songViewContentX)
{
    if (owner == TimelineQuickHoverOwner::None)
        return;
    m_hoverOwner = owner;
    m_hoverTick = tick;
    setHoverChrome(songViewContentX);
}

QQuickItem *TimelineQuickView::rootObject() const
{
    return m_quickView->rootObject();
}

QQuickWindow *TimelineQuickView::quickWindow() const
{
    return m_quickView;
}

void TimelineQuickView::clearHover(TimelineQuickHoverOwner owner)
{
    if (m_hoverOwner != owner)
        return;
    m_hoverOwner = TimelineQuickHoverOwner::None;
    setHoverChrome(std::nullopt);
}

qreal TimelineQuickView::quickRootXForSongViewX(qreal songViewX) const noexcept
{
    return songViewX - geometry().x();
}

std::optional<qreal> TimelineQuickView::guideSongViewContentXAtOrAfterStart(
    std::optional<qreal> songViewContentX) const noexcept
{
    if (!songViewContentX || !m_songView)
        return std::nullopt;
    const qreal songStartX = m_songView->timelinePlotOrigin() + m_songView->contentX(0.0);
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

bool TimelineQuickView::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_quickView && event->type() == QEvent::FocusIn) {
        // QWindowContainer's internal filter retargets this focus onto the
        // container widget, stealing it from native content. Only let it
        // through when a converted input item actually holds the Quick focus
        // selection, i.e. a programmatic focusBand() activated this window.
        const auto itemHasFocus = [](const TimelineInputItem *item) {
            return item && item->hasFocus();
        };
        if (std::any_of(m_inputItems.begin(), m_inputItems.end(), itemHasFocus))
            return QWidget::eventFilter(watched, event);
        if (m_songView) {
            m_songView->focusActiveSurface();
            return true;
        }
    }
    if (watched == m_quickView && event->type() == QEvent::WindowDeactivate) {
        for (TimelineInputItem *item : m_inputItems) {
            if (item && item->interaction())
                item->interaction()->inputCancelled(TimelineInputCancelReason::WindowDeactivated);
        }
    }
    return QWidget::eventFilter(watched, event);
}

void TimelineQuickView::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_quickContainer->setGeometry(rect());
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
        return after && (!before || before->rect.size() != after->rect.size());
    };

    PianoRollQuickDirtySet pianoDirty = PianoRollQuickDirty::None;
    TimelineQuickDirtySet timelineDirty = TimelineQuickDirty::None;

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
        timelineDirty |= cAutomationMask;
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::Velocity))
        timelineDirty |= TimelineQuickDirty::Velocity;
    if (becameVisibleOrChangedSize(m_bandLayout, layout, TimelineBand::VoiceChanges))
        timelineDirty |= TimelineQuickDirty::VoiceChanges;

    m_bandLayout = std::move(layout);
    m_layoutTimer.start();
    requestUpdate(pianoDirty);
    requestTimelineUpdate(timelineDirty);
}

void TimelineQuickView::refreshBandLayout()
{
    // Native-window lifecycle events (show, WinId, DPR) can drop the published
    // QML geometry and window mask; republish the stored layout as-is, without
    // changing the canonical value or queueing dirty domains.
    m_layoutTimer.start();
}

bool TimelineQuickView::focusBand(TimelineBand band, Qt::FocusReason reason)
{
    TimelineInputItem *const item = m_inputItems[timelineBandIndex(band)];
    if (!item)
        return false;
    // The container is the QWidget focus bridge: focusing it lets
    // QWindowContainer focus the embedded Quick window, after which the
    // item's forced focus resolves into live active focus. That FocusIn can
    // arrive asynchronously, so acceptance is not gated on hasActiveFocus();
    // focusedBand() remains the live active-focus truth.
    if (m_quickContainer)
        m_quickContainer->setFocus(reason);
    item->requestFocus(reason);
    return true;
}

std::optional<TimelineBand> TimelineQuickView::focusedBand() const
{
    for (std::size_t index = 0; index < m_inputItems.size(); ++index) {
        if (m_inputItems[index] && m_inputItems[index]->hasActiveFocus())
            return static_cast<TimelineBand>(index);
    }
    return std::nullopt;
}

void TimelineQuickView::publishTimelineBandLayout()
{
    QWidget *const songView = m_songView.data();
    if (!songView)
        return;

    // Band rects arrive already visible and SongView-local; consumers such as
    // PlayheadOverlay intersect only their owner's rect. Here they are
    // translated to this host's local origin for the QML scene and window mask.
    std::optional<QRect> hostRect;
    for (const std::optional<TimelineBandGeometry> &band : m_bandLayout.bands) {
        if (!band)
            continue;
        hostRect = hostRect ? hostRect->united(band->rect) : band->rect;
    }
    const QRect publishedHostRect = hostRect.value_or(QRect{});
    const bool hostXChanged = geometry().x() != publishedHostRect.x();
    if (geometry() != publishedHostRect)
        setGeometry(publishedHostRect);
    if (isVisible() != hostRect.has_value())
        setVisible(hostRect.has_value());

    QObject *root = rootObject();
    if (!root)
        qFatal("Qt Quick timeline QML has no root object");

    for (const TimelineBandQmlProperties &properties : kTimelineBandQmlProperties) {
        const std::optional<TimelineBandGeometry> &band = m_bandLayout.geometry(properties.band);
        const QRectF localBandRect =
            band ? QRectF{band->rect.translated(-publishedHostRect.topLeft())} : QRectF{};
        if (!root->setProperty(properties.rect, QVariant::fromValue(localBandRect)) ||
            !root->setProperty(properties.visible, QVariant::fromValue(band.has_value()))) {
            qFatal("Qt Quick timeline QML has incomplete band properties");
        }
    }

    // Quick now receives input, so the native-window mask admits only the
    // visible canonical band rectangles; retained native chrome is subtracted
    // so drawer controls keep receiving input through the holes.
    QRegion quickMask;
    for (const TimelineBandQmlProperties &properties : kTimelineBandQmlProperties) {
        const std::optional<TimelineBandGeometry> &band = m_bandLayout.geometry(properties.band);
        if (band)
            quickMask += band->rect;
    }
    for (QWidget *chrome : m_nativeChrome) {
        if (!chrome || !chrome->isVisibleTo(songView))
            continue;
        const QRect songViewRect(chrome->mapTo(songView, chrome->rect().topLeft()), chrome->size());
        quickMask -= songViewRect;
    }
    quickMask.translate(-publishedHostRect.topLeft());
    m_quickView->setMask(quickMask);

    if (hostXChanged) {
        if (m_hoverSongViewContentX)
            emit hoverChromeChanged();
        if (m_editSongViewContentX)
            emit editChromeChanged();
    }
}

void TimelineQuickView::syncAppearance()
{
    for (TimelineInputItem *item : m_inputItems) {
        if (!item)
            continue;
        if (m_songView)
            item->setHostAppearance(m_songView->font(), m_songView->palette());
        if (item->interaction())
            item->notifyHostAppearanceChanged();
    }
    for (TimelineChromeItem *item : m_chromeItems) {
        if (item)
            item->update();
    }
    requestUpdate(PianoRollQuickDirty::All);
    requestTimelineUpdate(TimelineQuickDirty::All);
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

void TimelineQuickView::flushUpdate()
{
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
    if (pianoDirty != PianoRollQuickDirty::None)
        synchronize(pianoDirty);
    if (timelineDirty != TimelineQuickDirty::None)
        synchronizeTimeline(timelineDirty);
}

void TimelineQuickView::synchronizeTimeline(TimelineQuickDirtySet dirty)
{
    const auto updateLayer = [this](TimelineQuickLayer layer) {
        if (TimelineQuickItem *item = m_items[static_cast<std::size_t>(layer)])
            item->update();
    };
    if ((dirty & TimelineQuickDirty::Ruler) && m_ruler) {
        m_ruler->rebuildQuickScene(*m_scene);
        updateLayer(TimelineQuickLayer::RulerChrome);
        updateLayer(TimelineQuickLayer::RulerMarks);
    }
    if ((dirty & TimelineQuickDirty::OtherEvents) && m_otherEvents) {
        m_otherEvents->rebuildQuickScene(*m_scene);
        updateLayer(TimelineQuickLayer::OtherEventsChrome);
        updateLayer(TimelineQuickLayer::OtherEventsMarkers);
    }
    if (const TimelineQuickDirtySet automationDirty = dirty & cAutomationMask;
        automationDirty != TimelineQuickDirty::None && m_automation && m_automation->canvas()) {
        m_automation->canvas()->rebuildQuickScene(*m_scene, automationDirty);
        if (automationDirty & TimelineQuickDirty::AutomationGrid)
            updateLayer(TimelineQuickLayer::AutomationGrid);
        if (automationDirty & TimelineQuickDirty::AutomationCurves)
            updateLayer(TimelineQuickLayer::AutomationCurves);
        if (automationDirty & TimelineQuickDirty::AutomationNodes)
            updateLayer(TimelineQuickLayer::AutomationNodes);
        if (automationDirty & TimelineQuickDirty::AutomationSelection)
            updateLayer(TimelineQuickLayer::AutomationSelection);
        if (automationDirty & TimelineQuickDirty::AutomationTransient)
            updateLayer(TimelineQuickLayer::AutomationTransient);
        if (automationDirty & TimelineQuickDirty::AutomationHover)
            updateLayer(TimelineQuickLayer::AutomationHover);
    }
    if ((dirty & TimelineQuickDirty::Velocity) && m_velocity) {
        m_velocity->rebuildQuickScene(*m_scene);
        updateLayer(TimelineQuickLayer::VelocityChrome);
        updateLayer(TimelineQuickLayer::VelocityAxis);
        updateLayer(TimelineQuickLayer::VelocityGrid);
        updateLayer(TimelineQuickLayer::VelocityBands);
        updateLayer(TimelineQuickLayer::VelocityStems);
        updateLayer(TimelineQuickLayer::VelocityNodes);
        updateLayer(TimelineQuickLayer::VelocityTransient);
    }
    if ((dirty & TimelineQuickDirty::VoiceChanges) && m_voiceChanges) {
        m_voiceChanges->rebuildQuickScene(*m_scene);
        updateLayer(TimelineQuickLayer::VoiceChangesChrome);
        updateLayer(TimelineQuickLayer::VoiceChangesGrid);
        updateLayer(TimelineQuickLayer::VoiceChangesSpans);
        updateLayer(TimelineQuickLayer::VoiceChangesMarkers);
        updateLayer(TimelineQuickLayer::VoiceChangesTransient);
        if (m_voiceChanges->m_hoverActive)
            m_voiceChanges->rebuildQuickHover(*m_scene);
        updateLayer(TimelineQuickLayer::VoiceChangesHover);
    } else if ((dirty & TimelineQuickDirty::VoiceChangesHover) && m_voiceChanges) {
        m_voiceChanges->rebuildQuickHover(*m_scene);
        updateLayer(TimelineQuickLayer::VoiceChangesHover);
    }
}

} // namespace songview
