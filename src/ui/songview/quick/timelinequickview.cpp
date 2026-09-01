#include "ui/songview/quick/timelinequickview.h"
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
                                     VelocityArea &velocity, VoiceChangeArea &voiceChanges,
                                     SongView &songView)
    : QQuickWidget(&songView)
    , m_ruler(&ruler)
    , m_roll(&roll)
    , m_otherEvents(&otherEvents)
    , m_velocity(&velocity)
    , m_voiceChanges(&voiceChanges)
    , m_songView(&songView)
{
    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<TimelineQuickItem>("Porydaw.Ui", 1, 0, "TimelineQuickItem");
    });

    setObjectName(QStringLiteral("timelineQuickCanvas"));
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_OpaquePaintEvent, true);
    setAttribute(Qt::WA_AlwaysStackOnTop, false);
    setFocusPolicy(Qt::NoFocus);
    setResizeMode(QQuickWidget::SizeRootObjectToView);

    m_scene = new TimelineQuickScene(this);
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

    static constexpr std::array<std::pair<TimelineQuickLayer, const char *>, 24> layers = {{
        {TimelineQuickLayer::RulerChrome, "timelineQuickRulerChrome"},
        {TimelineQuickLayer::RulerMarks, "timelineQuickRulerMarks"},
        {TimelineQuickLayer::PianoGrid, "timelineQuickPianoGrid"},
        {TimelineQuickLayer::PianoNoteFills, "timelineQuickPianoNoteFills"},
        {TimelineQuickLayer::PianoDrawPreviewFill, "timelineQuickPianoDrawPreviewFill"},
        {TimelineQuickLayer::PianoNoteBordersAndSelection,
         "timelineQuickPianoNoteBordersAndSelection"},
        {TimelineQuickLayer::PianoOverlay, "timelineQuickPianoOverlay"},
        {TimelineQuickLayer::PianoKeyboardKeys, "timelineQuickPianoKeyboardKeys"},
        {TimelineQuickLayer::PianoKeyboardHighlights, "timelineQuickPianoKeyboardHighlights"},
        {TimelineQuickLayer::OtherEventsChrome, "timelineQuickOtherEventsChrome"},
        {TimelineQuickLayer::OtherEventsMarkers, "timelineQuickOtherEventsMarkers"},
        {TimelineQuickLayer::VelocityChrome, "timelineQuickVelocityChrome"},
        {TimelineQuickLayer::VelocityAxis, "timelineQuickVelocityAxis"},
        {TimelineQuickLayer::VelocityGrid, "timelineQuickVelocityGrid"},
        {TimelineQuickLayer::VelocityBands, "timelineQuickVelocityBands"},
        {TimelineQuickLayer::VelocityStems, "timelineQuickVelocityStems"},
        {TimelineQuickLayer::VelocityNodes, "timelineQuickVelocityNodes"},
        {TimelineQuickLayer::VelocityTransient, "timelineQuickVelocityTransient"},
        {TimelineQuickLayer::VoiceChangesChrome, "timelineQuickVoiceChangesChrome"},
        {TimelineQuickLayer::VoiceChangesGrid, "timelineQuickVoiceChangesGrid"},
        {TimelineQuickLayer::VoiceChangesSpans, "timelineQuickVoiceChangesSpans"},
        {TimelineQuickLayer::VoiceChangesMarkers, "timelineQuickVoiceChangesMarkers"},
        {TimelineQuickLayer::VoiceChangesTransient, "timelineQuickVoiceChangesTransient"},
        {TimelineQuickLayer::VoiceChangesHover, "timelineQuickVoiceChangesHover"},
    }};
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

    m_ruler->installEventFilter(this);
    m_roll->installEventFilter(this);
    m_otherEvents->installEventFilter(this);
    m_velocity->installEventFilter(this);
    m_voiceChanges->installEventFilter(this);
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
}

bool TimelineQuickView::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_ruler.data() || watched == m_roll.data() || watched == m_otherEvents.data() ||
        watched == m_velocity.data() || watched == m_voiceChanges.data()) {
        switch (event->type()) {
        case QEvent::Show:
        case QEvent::Hide:
        case QEvent::Move:
        case QEvent::Resize:
        case QEvent::ParentChange:
            synchronizeHostGeometryAndVisibility();
            break;
        default:
            break;
        }
    }
    return QQuickWidget::eventFilter(watched, event);
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
    const QRect hostRect = rulerBandRect.united(rollBandRect)
                               .united(otherEventsBandRect)
                               .united(velocityBandRect)
                               .united(voiceChangesBandRect);
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
    const bool velocityVisible = m_velocity->isVisibleTo(m_songView.data());
    const bool voiceChangesVisible = m_voiceChanges->isVisibleTo(m_songView.data());
    const bool anyBandVisible =
        rulerVisible || rollVisible || otherEventsVisible || velocityVisible || voiceChangesVisible;
    if (isVisible() != anyBandVisible)
        setVisible(anyBandVisible);

    if (!root->setProperty("rulerBandRect", QVariant::fromValue(localBandRect(rulerBandRect))) ||
        !root->setProperty("rollBandRect", QVariant::fromValue(localBandRect(rollBandRect))) ||
        !root->setProperty("otherEventsBandRect",
                           QVariant::fromValue(localBandRect(otherEventsBandRect))) ||
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
    m_velocityBandRect = velocityBandRect;
    m_voiceChangesBandRect = voiceChangesBandRect;
    m_velocityWasVisible = velocityVisible;
    m_voiceChangesWasVisible = voiceChangesVisible;
}

void TimelineQuickView::syncAppearance()
{
    setClearColor(themes::color(themes::Role::song_view_piano_roll_background));
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
