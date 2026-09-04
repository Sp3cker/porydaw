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
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/playheadquick.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/theme/themeruntime.h"
#include <QColor>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickImageProvider>
#include <QQuickView>
#include <QSurfaceFormat>
#include <QUrl>
#include <QVariant>
#include <QtQml>
#include <algorithm>
#include <array>
#include <chrono>
#include <mutex>
#include <utility>

namespace songview {

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

namespace {

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

struct DrawerChromeRect {
    QRectF rect;
    bool visible = false;
};

std::array<DrawerChromeRect, 9> visibleDrawerChromeRects(const DrawerChrome *chrome)
{
    if (!chrome)
        return {};

    // Enumerate every visible QML chrome surface so the host envelope is
    // exactly the Quick-visible area, including the automation scrollbar only
    // while the automation body owns it.
    return {{
        {chrome->voiceChangesHandleRect(), chrome->voiceChangesHandleVisible()},
        {chrome->velocityHandleRect(), chrome->velocityHandleVisible()},
        {chrome->automationHandleRect(), chrome->automationHandleVisible()},
        {chrome->barRect(), chrome->barVisible()},
        {chrome->voiceChangesToggleRect(), chrome->voiceChangesToggleVisible()},
        {chrome->automationToggleRect(), chrome->automationToggleVisible()},
        {chrome->velocityToggleRect(), chrome->velocityToggleVisible()},
        {chrome->detentRect(), chrome->detentVisible()},
        {chrome->automationScrollbarRect(), chrome->automationScrollbarVisible()},
    }};
}

} // namespace

TimelineQuickView::TimelineQuickView(TimeRuler &ruler, PianoRoll &roll, OtherStrip &otherEvents,
                                     AutomationPage &automation, VelocityArea &velocity,
                                     VoiceChangeArea &voiceChanges, DrawerChrome &drawerChrome,
                                     TrackHeaderModel &trackHeaders, SongView &songView)
    : QWidget(&songView)
    , m_ruler(&ruler)
    , m_trackHeaders(&trackHeaders)
    , m_roll(&roll)
    , m_otherEvents(&otherEvents)
    , m_automation(&automation)
    , m_velocity(&velocity)
    , m_voiceChanges(&voiceChanges)
    , m_drawerChrome(&drawerChrome)
    , m_songView(&songView)
    , m_camera(songView.camera())
    , m_playheadColor(themes::color(themes::Role::song_view_playhead))
{
    m_layoutTimer.setSingleShot(true);
    m_layoutTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_layoutTimer, &QTimer::timeout, this, &TimelineQuickView::publishTimelineBandLayout);
    m_flushTimer.setSingleShot(true);
    m_flushTimer.setInterval(std::chrono::milliseconds::zero());
    connect(&m_flushTimer, &QTimer::timeout, this, &TimelineQuickView::flushUpdate);
    // Chrome snapshot changes re-envelope the Quick host; scroll changes only
    // repaint the automation layers.
    connect(m_drawerChrome, &DrawerChrome::chromeChanged, this,
            [this] { scheduleTimelineBandLayoutPublication(); });
    connect(m_drawerChrome, &DrawerChrome::scrollChanged, this,
            [this] { requestAutomationUpdate(AutomationRefresh::All); });

    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<TimelineChromeItem>("Porydaw.Ui", 1, 0, "TimelineChromeItem");
        qmlRegisterType<TimelineInputItem>("Porydaw.Ui", 1, 0, "TimelineInputItem");
        qmlRegisterType<TimelinePlayheadItem>("Porydaw.Ui", 1, 0, "TimelinePlayheadItem");
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
    m_quickView->rootContext()->setContextProperty(QStringLiteral("drawerChrome"), &drawerChrome);
    m_quickView->rootContext()->setContextProperty(QStringLiteral("trackHeaderModel"),
                                                   &trackHeaders);
    m_quickView->rootContext()->setContextProperty(QStringLiteral("timeRuler"), &ruler);
    m_quickView->engine()->addImageProvider(QStringLiteral("drawerchrome"),
                                            drawerChrome.releaseIconProvider());
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

    const auto bindInput = [&root](TimelineInputItem *&destination,
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

    for (std::size_t index = 0; index < kDrawerChromeInputQmlProperties.size(); ++index) {
        const DrawerChromeInputQmlProperties &properties = kDrawerChromeInputQmlProperties[index];
        TimelineInputItem *const input =
            root->findChild<TimelineInputItem *>(QString::fromLatin1(properties.objectName));
        if (!input) {
            qFatal("Qt Quick timeline QML has no drawer chrome input '%s'", properties.objectName);
        }
        input->setInteraction(&drawerChrome.interaction(properties.target));
        m_drawerChromeInputs[index] = input;
    }

    syncAppearance();
}

TimelineQuickView::~TimelineQuickView()
{
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
    m_quickView->setSource(QUrl{});
}

void TimelineQuickView::detachInputInteraction(TimelineBand band)
{
    const std::size_t index = timelineBandIndex(band);
    if (TimelineInputItem *const gutterItem = m_gutterInputItems[index])
        gutterItem->setInteraction(nullptr);
    if (TimelineInputItem *const primaryItem = m_inputItems[index])
        primaryItem->setInteraction(nullptr);
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

qreal TimelineQuickView::hostX() const noexcept
{
    return m_publishedHostRect.x();
}

qreal TimelineQuickView::hostY() const noexcept
{
    return m_publishedHostRect.y();
}
qreal TimelineQuickView::rulerPlotOrigin() const noexcept
{
    return m_publishedRulerPlotOrigin;
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

bool TimelineQuickView::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_quickView && event->type() == QEvent::Resize)
        scheduleTimelineBandLayoutPublication();

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
        for (TimelineInputItem *item : m_drawerChromeInputs) {
            if (item && item->interaction())
                item->interaction()->inputCancelled(TimelineInputCancelReason::WindowDeactivated);
        }
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
    if (m_quickContainer)
        m_quickContainer->setGeometry(rect());
    scheduleTimelineBandLayoutPublication();
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
    // Quick-window lifecycle events (show, WinId, DPR) can drop published
    // QML geometry; republish the stored layout as-is, without changing the
    // canonical value or queueing dirty domains.
    scheduleTimelineBandLayoutPublication();
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
    if (!m_songView)
        return;

    // Band rects arrive already visible and SongView-local; consumers such as
    // PlayheadOverlay intersect only their owner's rect. Here they are
    // translated to this host's local origin for the QML scene.
    std::optional<QRect> hostRect;
    for (const std::optional<TimelineBandGeometry> &band : m_bandLayout.bands) {
        if (!band)
            continue;
        hostRect = hostRect ? hostRect->united(band->rect) : band->rect;
    }
    const auto drawerChromeRects = visibleDrawerChromeRects(m_drawerChrome.data());
    for (const DrawerChromeRect &chrome : drawerChromeRects) {
        if (!chrome.visible || chrome.rect.isEmpty())
            continue;
        const QRect chromeRect = chrome.rect.toAlignedRect();
        hostRect = hostRect ? hostRect->united(chromeRect) : chromeRect;
    }
    const QRect publishedHostRect = hostRect.value_or(QRect{});
    const qreal publishedRulerPlotOrigin = m_songView->timelineSplitX() - publishedHostRect.x();
    const bool hostOriginChanged = m_publishedHostRect.topLeft() != publishedHostRect.topLeft();
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
        // Plot rects are SongView-local like the band rect and share the
        // same host translation; empty plot rects (TrackHeaders) stay empty.
        const QRectF localBandPlotRect =
            band ? QRectF{band->plotRect.translated(-publishedHostRect.topLeft())} : QRectF{};
        if (!root->setProperty(properties.rect, QVariant::fromValue(localBandRect)) ||
            !root->setProperty(properties.visible, QVariant::fromValue(band.has_value())) ||
            !root->setProperty(properties.plotRect, QVariant::fromValue(localBandPlotRect))) {
            qFatal("Qt Quick timeline QML has incomplete band properties");
        }
    }

    const bool publishedGeometryChanged =
        std::exchange(m_publishedHostRect, publishedHostRect) != publishedHostRect ||
        std::exchange(m_publishedRulerPlotOrigin, publishedRulerPlotOrigin) !=
            publishedRulerPlotOrigin;
    if (publishedGeometryChanged)
        emit hostGeometryChanged();

    if (hostOriginChanged) {
        if (m_hoverSongViewContentX)
            emit hoverChromeChanged();
        if (m_editSongViewContentX)
            emit editChromeChanged();
    }
}

void TimelineQuickView::syncAppearance()
{
    for (TimelineInputItem *item : m_gutterInputItems) {
        if (item && m_songView)
            item->setHostAppearance(m_songView->font(), m_songView->palette());
    }
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
    requestAutomationUpdate(AutomationRefresh::All);
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
