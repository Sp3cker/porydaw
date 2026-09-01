#include "ui/songview/quick/timelinequickview.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/timeruler.h"
#include "ui/theme/themeruntime.h"

#include <QPoint>
#include <QQmlContext>
#include <QQmlEngine>
#include <QUrl>
#include <QVariant>
#include <QtQml>

#include <array>
#include <mutex>
#include <utility>

namespace songview {

TimelineQuickView::TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                                     AutomationPage &automation, VelocityArea &velocity,
                                     VoiceChangeArea &voiceChanges, SongView &songView)
    : QQuickWidget(&songView)
    , m_ruler(&ruler)
    , m_roll(&roll)
    , m_otherEvents(&otherEvents)
    , m_automation(&automation)
    , m_automationScrollViewport(automation.scrollViewport())
    , m_velocity(&velocity)
    , m_voiceChanges(&voiceChanges)
    , m_songView(&songView)
{
    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<TimelineChromeItem>("Porydaw.Ui", 1, 0, "TimelineChromeItem");
        qmlRegisterType<TimelineQuickItem>("Porydaw.Ui", 1, 0, "TimelineQuickItem");
    });

    setObjectName(QStringLiteral("timelineQuickCanvas"));
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_OpaquePaintEvent, true);
    setAttribute(Qt::WA_AlwaysStackOnTop, false);
    setFocusPolicy(Qt::NoFocus);
    setResizeMode(QQuickWidget::SizeRootObjectToView);

    m_scene = new TimelineQuickScene(this);
    rootContext()->setContextProperty(QStringLiteral("timelineQuickView"), this);
    rootContext()->setContextProperty(QStringLiteral("timelineScene"), m_scene);
    setSource(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/TimelineCanvas.qml")));
    if (status() != QQuickWidget::Ready) {
        for (const QQmlError &error : errors())
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
        std::pair{TimelineChromeItem::Kind::Playhead, "timelineQuickRulerPlayheadChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickRollHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickRollEditChrome"},
        std::pair{TimelineChromeItem::Kind::Playhead, "timelineQuickRollPlayheadChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickAutomationHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickAutomationEditChrome"},
        std::pair{TimelineChromeItem::Kind::Playhead, "timelineQuickAutomationPlayheadChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickVelocityHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickVelocityEditChrome"},
        std::pair{TimelineChromeItem::Kind::Playhead, "timelineQuickVelocityPlayheadChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickVoiceChangesHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickVoiceChangesEditChrome"},
        std::pair{TimelineChromeItem::Kind::Playhead, "timelineQuickVoiceChangesPlayheadChrome"},
        std::pair{TimelineChromeItem::Kind::Hover, "timelineQuickOtherEventsHoverChrome"},
        std::pair{TimelineChromeItem::Kind::Edit, "timelineQuickOtherEventsEditChrome"},
        std::pair{TimelineChromeItem::Kind::Playhead, "timelineQuickOtherEventsPlayheadChrome"},
    };
    static_assert(chromeItems.size() == 18);
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
}

qreal TimelineQuickView::hoverRootContentX() const noexcept
{
    return m_hoverChrome.rootContentX;
}

bool TimelineQuickView::hoverVisible() const noexcept
{
    return m_hoverChrome.visible;
}

qreal TimelineQuickView::editRootContentX() const noexcept
{
    return m_editChrome.rootContentX;
}

bool TimelineQuickView::editVisible() const noexcept
{
    return m_editChrome.visible;
}

qreal TimelineQuickView::playheadRootContentX() const noexcept
{
    return m_playheadChrome.rootContentX;
}

bool TimelineQuickView::playheadVisible() const noexcept
{
    return m_playheadChrome.visible;
}

bool TimelineQuickView::playheadPlaying() const noexcept
{
    return m_playheadChrome.playing;
}

void TimelineQuickView::synchronizeChrome(qreal rootOriginX, qreal editRootContentX,
                                          bool editVisible, qreal playheadRootContentX,
                                          bool playheadVisible, bool playheadPlaying)
{
    setEditChrome(editRootContentX, editVisible);
    setPlayheadChrome(playheadRootContentX, playheadVisible, playheadPlaying);
    if (m_hoverOwner != TimelineQuickHoverOwner::None && m_songView)
        setHoverChrome(rootOriginX + m_songView->contentX(m_hoverTick), true);
}

void TimelineQuickView::publishHover(TimelineQuickHoverOwner owner, uint64_t tick,
                                     qreal rootContentX)
{
    if (owner == TimelineQuickHoverOwner::None)
        return;
    m_hoverOwner = owner;
    m_hoverTick = tick;
    setHoverChrome(rootContentX, true);
}

void TimelineQuickView::clearHover(TimelineQuickHoverOwner owner)
{
    if (m_hoverOwner != owner)
        return;
    m_hoverOwner = TimelineQuickHoverOwner::None;
    setHoverChrome(m_hoverChrome.rootContentX, false);
}

void TimelineQuickView::setHoverChrome(qreal rootContentX, bool visible)
{
    if (m_hoverChrome.rootContentX == rootContentX && m_hoverChrome.visible == visible)
        return;
    m_hoverChrome = {.rootContentX = rootContentX, .visible = visible};
    emit hoverChromeChanged();
}

void TimelineQuickView::setEditChrome(qreal rootContentX, bool visible)
{
    if (m_editChrome.rootContentX == rootContentX && m_editChrome.visible == visible)
        return;
    m_editChrome = {.rootContentX = rootContentX, .visible = visible};
    emit editChromeChanged();
}

void TimelineQuickView::setPlayheadChrome(qreal rootContentX, bool visible, bool playing)
{
    if (m_playheadChrome.rootContentX == rootContentX && m_playheadChrome.visible == visible &&
        m_playheadChrome.playing == playing) {
        return;
    }
    m_playheadChrome = {
        .rootContentX = rootContentX,
        .visible = visible,
        .playing = playing,
    };
    emit playheadChromeChanged();
}

bool TimelineQuickView::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_ruler.data() || watched == m_roll.data() || watched == m_otherEvents.data() ||
        watched == m_automation.data() || watched == m_automationScrollViewport.data() ||
        watched == m_velocity.data() || watched == m_voiceChanges.data()) {
        switch (event->type()) {
        case QEvent::Show:
        case QEvent::Hide:
        case QEvent::ParentChange:
            scheduleHostGeometryAndVisibilitySync();
            break;
        case QEvent::Move:
        case QEvent::Resize:
            synchronizeHostGeometryAndVisibility();
            break;
        default:
            break;
        }
    }
    return QQuickWidget::eventFilter(watched, event);
}

void TimelineQuickView::scheduleHostGeometryAndVisibilitySync()
{
    if (m_hostSyncScheduled)
        return;
    m_hostSyncScheduled = true;
    QMetaObject::invokeMethod(
        this,
        [this] {
            m_hostSyncScheduled = false;
            synchronizeHostGeometryAndVisibility();
        },
        Qt::QueuedConnection);
}

void TimelineQuickView::synchronizeHostGeometryAndVisibility()
{
    if (!m_ruler || !m_roll || !m_otherEvents || !m_velocity || !m_voiceChanges || !m_songView)
        return;

    const auto bandRectInSongView = [songView = m_songView.data()](const QWidget &band) {
        const QRect localRect = band.rect();
        return QRect{band.mapTo(songView, localRect.topLeft()), localRect.size()};
    };
    const QRect rulerBandRect = bandRectInSongView(*m_ruler);
    const QRect rollBandRect = bandRectInSongView(*m_roll);
    const QRect otherEventsBandRect = bandRectInSongView(*m_otherEvents);
    const QRect velocityBandRect = bandRectInSongView(*m_velocity);
    const QRect voiceChangesBandRect = bandRectInSongView(*m_voiceChanges);
    QRect automationBandRect;
    if (m_automationScrollViewport)
        automationBandRect = bandRectInSongView(*m_automationScrollViewport);

    QRect hostRect = rulerBandRect.united(rollBandRect)
                         .united(otherEventsBandRect)
                         .united(velocityBandRect)
                         .united(voiceChangesBandRect);
    if (m_automationScrollViewport)
        hostRect = hostRect.united(automationBandRect);
    if (geometry() != hostRect)
        setGeometry(hostRect);

    QObject *root = rootObject();
    if (!root)
        qFatal("Qt Quick timeline QML has no root object");

    const auto localBandRect = [&hostRect](const QRect &bandRect) {
        return QRectF{bandRect.translated(-hostRect.topLeft())};
    };
    const bool rulerVisible = m_ruler->isVisibleTo(m_songView.data());
    const bool rollVisible = m_roll->isVisibleTo(m_songView.data());
    const bool otherEventsVisible = m_otherEvents->isVisibleTo(m_songView.data());
    const bool automationVisible =
        m_automationScrollViewport && m_automationScrollViewport->isVisibleTo(m_songView.data());
    const bool velocityVisible = m_velocity->isVisibleTo(m_songView.data());
    const bool voiceChangesVisible = m_voiceChanges->isVisibleTo(m_songView.data());
    const bool anyBandVisible = rulerVisible || rollVisible || otherEventsVisible ||
                                automationVisible || velocityVisible || voiceChangesVisible;
    if (isVisible() != anyBandVisible)
        setVisible(anyBandVisible);

    if (!root->setProperty("rulerBandRect", QVariant::fromValue(localBandRect(rulerBandRect))) ||
        !root->setProperty("rollBandRect", QVariant::fromValue(localBandRect(rollBandRect))) ||
        !root->setProperty("otherEventsBandRect",
                           QVariant::fromValue(localBandRect(otherEventsBandRect))) ||
        !root->setProperty("automationBandRect",
                           QVariant::fromValue(automationVisible ? localBandRect(automationBandRect)
                                                                 : QRectF{})) ||
        !root->setProperty(
            "velocityBandRect",
            QVariant::fromValue(velocityVisible ? localBandRect(velocityBandRect) : QRectF{})) ||
        !root->setProperty("voiceChangesBandRect",
                           QVariant::fromValue(voiceChangesVisible
                                                   ? localBandRect(voiceChangesBandRect)
                                                   : QRectF{})) ||
        !root->setProperty("rulerBandVisible", QVariant::fromValue(rulerVisible)) ||
        !root->setProperty("rollBandVisible", QVariant::fromValue(rollVisible)) ||
        !root->setProperty("otherEventsBandVisible", QVariant::fromValue(otherEventsVisible)) ||
        !root->setProperty("automationBandVisible", QVariant::fromValue(automationVisible)) ||
        !root->setProperty("velocityBandVisible", QVariant::fromValue(velocityVisible)) ||
        !root->setProperty("voiceChangesBandVisible", QVariant::fromValue(voiceChangesVisible))) {
        qFatal("Qt Quick timeline QML has incomplete band properties");
    }

    if (m_rollBandRect.isValid() && m_rollBandRect.size() != rollBandRect.size()) {
        const bool widthOnly = m_rollBandRect.height() == rollBandRect.height();
        requestUpdate(widthOnly ? cPlotAndLoadingDirty : PianoRollQuickDirty::All);
    }
    if (m_rulerBandRect.isValid() && m_rulerBandRect.size() != rulerBandRect.size())
        requestTimelineUpdate(TimelineQuickDirty::Ruler);
    if (m_otherEventsBandRect.isValid() &&
        m_otherEventsBandRect.size() != otherEventsBandRect.size()) {
        requestTimelineUpdate(TimelineQuickDirty::OtherEvents);
    }
    if (m_automationScrollViewport && m_automationBandRect.isValid() &&
        m_automationBandRect.size() != automationBandRect.size()) {
        requestTimelineUpdate(cAutomationMask);
    }
    if (!m_automationWasVisible && automationVisible)
        requestTimelineUpdate(cAutomationMask);
    if (m_velocityBandRect.isValid() && m_velocityBandRect.size() != velocityBandRect.size())
        requestTimelineUpdate(TimelineQuickDirty::Velocity);
    if (!m_velocityWasVisible && velocityVisible)
        requestTimelineUpdate(TimelineQuickDirty::Velocity);
    if (!m_voiceChangesWasVisible && voiceChangesVisible)
        requestTimelineUpdate(TimelineQuickDirty::VoiceChanges);
    if (m_voiceChangesBandRect.size() != voiceChangesBandRect.size())
        requestTimelineUpdate(TimelineQuickDirty::VoiceChanges);
    m_rulerBandRect = rulerBandRect;
    m_rollBandRect = rollBandRect;
    m_otherEventsBandRect = otherEventsBandRect;
    m_automationBandRect = automationBandRect;
    m_velocityBandRect = velocityBandRect;
    m_voiceChangesBandRect = voiceChangesBandRect;
    m_automationWasVisible = automationVisible;
    m_velocityWasVisible = velocityVisible;
    m_voiceChangesWasVisible = voiceChangesVisible;
}

void TimelineQuickView::syncAppearance()
{
    setClearColor(themes::color(themes::Role::song_view_piano_roll_background));
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
    if (m_flushScheduled)
        return;
    m_flushScheduled = true;
    QMetaObject::invokeMethod(this, [this] { flushUpdate(); }, Qt::QueuedConnection);
}

void TimelineQuickView::requestTimelineUpdate(TimelineQuickDirtySet dirty)
{
    if (dirty == TimelineQuickDirty::None)
        return;
    m_pendingTimelineDirty |= dirty;
    if (m_flushScheduled)
        return;
    m_flushScheduled = true;
    QMetaObject::invokeMethod(this, [this] { flushUpdate(); }, Qt::QueuedConnection);
}

void TimelineQuickView::flushUpdate()
{
    m_flushScheduled = false;
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
