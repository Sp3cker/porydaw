#include "ui/songview/quick/timelinequickview.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
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

TimelineQuickView::TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                                     AutomationPage &automation, VelocityArea &velocity,
                                     VoiceChangeArea &voiceChanges, SongView &songView)
    : QWidget(&songView)
    , m_ruler(&ruler)
    , m_roll(&roll)
    , m_otherEvents(&otherEvents)
    , m_automation(&automation)
    , m_automationScrollViewport(automation.scrollViewport())
    , m_velocity(&velocity)
    , m_voiceChanges(&voiceChanges)
    , m_songView(&songView)
{
    m_layoutTimer.setSingleShot(true);
    m_layoutTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_layoutTimer, &QTimer::timeout, this,
            &TimelineQuickView::synchronizeHostGeometryAndVisibility);
    m_flushTimer.setSingleShot(true);
    m_flushTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_flushTimer, &QTimer::timeout, this, &TimelineQuickView::flushUpdate);

    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<TimelineChromeItem>("Porydaw.Ui", 1, 0, "TimelineChromeItem");
        qmlRegisterType<TimelineQuickItem>("Porydaw.Ui", 1, 0, "TimelineQuickItem");
    });

    setObjectName(QStringLiteral("timelineQuickCanvas"));
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setFocusPolicy(Qt::NoFocus);

    m_quickView = new QQuickView;
    QSurfaceFormat surfaceFormat = m_quickView->format();
    surfaceFormat.setAlphaBufferSize(8);
    m_quickView->setFormat(surfaceFormat);
    m_quickView->setColor(Qt::transparent);
    m_quickView->setFlag(Qt::WindowTransparentForInput);
    m_quickView->setFlag(Qt::WindowDoesNotAcceptFocus);
    m_quickView->setResizeMode(QQuickView::SizeRootObjectToView);
    m_quickContainer = QWidget::createWindowContainer(m_quickView, this);
    m_quickContainer->setAttribute(Qt::WA_TransparentForMouseEvents);
    m_quickContainer->setFocusPolicy(Qt::NoFocus);
    m_quickContainer->installEventFilter(this);
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

    m_ruler->installEventFilter(this);
    m_roll->installEventFilter(this);
    m_otherEvents->installEventFilter(this);
    m_velocity->installEventFilter(this);
    m_voiceChanges->installEventFilter(this);
    m_automation->installEventFilter(this);
    if (m_automationScrollViewport)
        m_automationScrollViewport->installEventFilter(this);
    static constexpr std::array nativeChromeNames = {
        "velocityResizeHandle", "voiceChangesResizeHandle", "automationResizeHandle",
        "automationDrawerBar",  "velocityDetentToggle",
    };
    QWidget *const drawerSections = m_velocity->parentWidget();
    for (std::size_t index = 0; index < nativeChromeNames.size(); ++index) {
        QWidget *const chrome = drawerSections ? drawerSections->findChild<QWidget *>(
                                                     QString::fromLatin1(nativeChromeNames[index]),
                                                     Qt::FindDirectChildrenOnly)
                                               : nullptr;
        if (!chrome)
            qFatal("Timeline Quick host cannot find drawer chrome '%s'", nativeChromeNames[index]);
        chrome->installEventFilter(this);
        m_nativeChrome[index] = chrome;
    }
#ifdef Q_OS_MACOS
    if (AutomationCanvas *const canvas = automation.canvas())
        installMacAutomationHoverPassThrough(*canvas, *this);
#endif
    synchronizeHostGeometryAndVisibility();
    syncAppearance();
}

TimelineQuickView::~TimelineQuickView()
{
    if (m_ruler)
        m_ruler->removeEventFilter(this);
    if (m_roll)
        m_roll->removeEventFilter(this);
    if (m_otherEvents)
        m_otherEvents->removeEventFilter(this);
    if (m_velocity)
        m_velocity->removeEventFilter(this);
    if (m_voiceChanges)
        m_voiceChanges->removeEventFilter(this);
    if (m_automation)
        m_automation->removeEventFilter(this);
    if (m_automationScrollViewport)
        m_automationScrollViewport->removeEventFilter(this);
    for (QWidget *chrome : m_nativeChrome) {
        if (chrome)
            chrome->removeEventFilter(this);
    }
    if (m_quickContainer)
        m_quickContainer->removeEventFilter(this);
    m_quickView->setSource(QUrl{});
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
    if (watched == m_quickContainer && event->type() == QEvent::FocusIn) {
        if (m_songView)
            m_songView->focusActiveSurface();
        return true;
    }
    const bool watchedBand = watched == m_ruler.data() || watched == m_roll.data() ||
                             watched == m_otherEvents.data() || watched == m_automation.data() ||
                             watched == m_automationScrollViewport.data() ||
                             watched == m_velocity.data() || watched == m_voiceChanges.data();
    const bool watchedNativeChrome = std::any_of(
        m_nativeChrome.cbegin(), m_nativeChrome.cend(),
        [watched](const QPointer<QWidget> &chrome) { return chrome.data() == watched; });
    if (watchedBand || watchedNativeChrome) {
        switch (event->type()) {
        case QEvent::Show:
        case QEvent::Hide:
        case QEvent::ParentChange:
        case QEvent::Move:
        case QEvent::Resize:
            scheduleHostGeometryAndVisibilitySync();
            break;
        default:
            break;
        }
    }
    return QWidget::eventFilter(watched, event);
}

void TimelineQuickView::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_quickContainer->setGeometry(rect());
}

void TimelineQuickView::scheduleHostGeometryAndVisibilitySync()
{
    m_layoutTimer.start();
}

void TimelineQuickView::synchronizeHostGeometryAndVisibility()
{
    QWidget *const songView = m_songView.data();
    if (!songView)
        return;

    static constexpr std::size_t bandCount = static_cast<std::size_t>(Band::Count);
    const std::array<QWidget *, bandCount> bandWidgets = {
        m_ruler.data(),       m_roll.data(),
        m_otherEvents.data(), m_automationScrollViewport.data(),
        m_velocity.data(),    m_voiceChanges.data(),
    };
    PublishedLayout layout;
    for (std::size_t index = 0; index < bandWidgets.size(); ++index) {
        QWidget *const band = bandWidgets[index];
        if (!band || !band->isVisibleTo(songView))
            continue;
        const QRect localRect = band->rect();
        layout[index] = QRect{band->mapTo(songView, localRect.topLeft()), localRect.size()};
    }

    std::optional<QRect> hostRect;
    for (const std::optional<QRect> &bandRect : layout) {
        if (!bandRect)
            continue;
        hostRect = hostRect ? hostRect->united(*bandRect) : *bandRect;
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

    static constexpr std::array bandRectProperties = {
        "rulerBandRect",      "rollBandRect",     "otherEventsBandRect",
        "automationBandRect", "velocityBandRect", "voiceChangesBandRect",
    };
    static constexpr std::array bandVisibleProperties = {
        "rulerBandVisible",      "rollBandVisible",     "otherEventsBandVisible",
        "automationBandVisible", "velocityBandVisible", "voiceChangesBandVisible",
    };
    static_assert(bandRectProperties.size() == bandCount);
    static_assert(bandVisibleProperties.size() == bandCount);

    const auto localBandRect = [&publishedHostRect](const std::optional<QRect> &bandRect) {
        return bandRect ? QRectF{bandRect->translated(-publishedHostRect.topLeft())} : QRectF{};
    };
    for (std::size_t index = 0; index < layout.size(); ++index) {
        if (!root->setProperty(bandRectProperties[index],
                               QVariant::fromValue(localBandRect(layout[index]))) ||
            !root->setProperty(bandVisibleProperties[index],
                               QVariant::fromValue(layout[index].has_value()))) {
            qFatal("Qt Quick timeline QML has incomplete band properties");
        }
    }
    QRegion quickMask(QRect(QPoint{}, publishedHostRect.size()));
    for (QWidget *chrome : m_nativeChrome) {
        if (!chrome || !chrome->isVisibleTo(songView))
            continue;
        const QRect songViewRect(chrome->mapTo(songView, chrome->rect().topLeft()), chrome->size());
        quickMask -= songViewRect.translated(-publishedHostRect.topLeft());
    }
    m_quickView->setMask(quickMask);

    const auto indexOf = [](Band band) { return static_cast<std::size_t>(band); };
    const auto becameVisibleOrChangedSize = [this, &layout, &indexOf](Band band) {
        const std::size_t index = indexOf(band);
        const std::optional<QRect> &published = m_publishedLayout[index];
        const std::optional<QRect> &current = layout[index];
        return current && (!published || published->size() != current->size());
    };

    if (becameVisibleOrChangedSize(Band::Ruler))
        requestTimelineUpdate(TimelineQuickDirty::Ruler);
    if (becameVisibleOrChangedSize(Band::Roll)) {
        const std::optional<QRect> &published = m_publishedLayout[indexOf(Band::Roll)];
        const std::optional<QRect> &current = layout[indexOf(Band::Roll)];
        const bool widthOnly = published && published->height() == current->height();
        requestUpdate(widthOnly ? cPlotAndLoadingDirty : PianoRollQuickDirty::All);
    }
    if (becameVisibleOrChangedSize(Band::OtherEvents))
        requestTimelineUpdate(TimelineQuickDirty::OtherEvents);
    if (becameVisibleOrChangedSize(Band::Automation))
        requestTimelineUpdate(cAutomationMask);
    if (becameVisibleOrChangedSize(Band::Velocity))
        requestTimelineUpdate(TimelineQuickDirty::Velocity);
    if (becameVisibleOrChangedSize(Band::VoiceChanges))
        requestTimelineUpdate(TimelineQuickDirty::VoiceChanges);

    m_publishedLayout = std::move(layout);
    if (hostXChanged) {
        if (m_hoverSongViewContentX)
            emit hoverChromeChanged();
        if (m_editSongViewContentX)
            emit editChromeChanged();
    }
}

void TimelineQuickView::syncAppearance()
{
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
