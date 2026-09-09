#include "playheadoverlay.h"
#include "layout.h"
#include "songview.h"
#include "theme/themeruntime.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtGlobal>
#include <algorithm>

namespace songview {

int playheadGlowRadius()
{
    return layout::fontPx(0.625);
}

int playheadTriangleHalfWidth()
{
    return layout::fontPx(0.25);
}

int playheadTriangleHeight()
{
    return layout::fontPx(0.5);
}

qreal playheadLineWidth()
{
    return layout::singlePixel();
}

namespace {

constexpr qreal kPlayheadPeakPlaying = 0.13;
constexpr qreal kPlayheadPeakPaused = 0.06;

#ifdef __APPLE__
void appendNonEmpty(QVector<QRectF> &rects, const QRectF &rect)
{
    if (!rect.isEmpty())
        rects.append(rect);
}

void appendWithoutOcclusion(QVector<QRectF> &rects, const QRectF &surface, const QRectF &occlusion)
{
    const QRectF intersection = surface.intersected(occlusion);
    if (intersection.isEmpty()) {
        appendNonEmpty(rects, surface);
        return;
    }

    appendNonEmpty(rects, QRectF(surface.left(), surface.top(), surface.width(),
                                 intersection.top() - surface.top()));
    appendNonEmpty(rects, QRectF(surface.left(), intersection.bottom(), surface.width(),
                                 surface.bottom() - intersection.bottom()));
    appendNonEmpty(rects, QRectF(surface.left(), intersection.top(),
                                 intersection.left() - surface.left(), intersection.height()));
    appendNonEmpty(rects, QRectF(intersection.right(), intersection.top(),
                                 surface.right() - intersection.right(), intersection.height()));
}
#endif

} // namespace

qreal playheadGlowLeftExtent(bool playing)
{
    return playing ? qreal(playheadGlowRadius()) - playheadLineWidth()
                   : qreal(playheadGlowRadius());
}

qreal playheadGlowRightExtent(bool playing)
{
    return playing ? (playheadLineWidth() / 2.0) : qreal(playheadGlowRadius());
}

qreal playheadPeakAlpha(bool playing)
{
    return playing ? kPlayheadPeakPlaying : kPlayheadPeakPaused;
}

PlayheadOverlay::PlayheadOverlay(SongView &owner, const TimelineBandLayout &layout)
    : QObject(&owner)
    , m_owner(owner)
    , m_layout(layout)
    , m_color(themes::color(themes::Role::song_view_playhead))
{
    synchronizeGeometry();
}

PlayheadOverlay::~PlayheadOverlay() = default;

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible, bool playing)
{
    if (m_timelineX == timelineX && m_visible == visible && m_playing == playing)
        return;

    m_timelineX = timelineX;
    m_visible = visible;
    m_playing = playing;

    updatePlayhead();
}

void PlayheadOverlay::updateBands(const TimelineBandLayout &layout)
{
    m_layout = layout;
    synchronizeGeometry();
}

void PlayheadOverlay::syncAppearance()
{
    const QColor newColor = themes::color(themes::Role::song_view_playhead);
    if (m_color == newColor)
        return;
    m_color = newColor;
#ifdef __APPLE__
    if (m_platform)
        setPlatformImages();
#endif
    updatePlayhead();
}

songview::TimelineQuickView *PlayheadOverlay::quickView() const
{
    return m_owner.quickView();
}

QQuickWindow *PlayheadOverlay::quickWindow() const
{
    songview::TimelineQuickView *quickView = m_owner.quickView();
    return quickView ? quickView->quickWindow() : nullptr;
}

QRectF PlayheadOverlay::canvasTimelineColumnRect() const
{
    songview::TimelineQuickView *const quickView = m_owner.quickView();
    QQuickItem *const root = quickView ? quickView->rootObject() : nullptr;
    QQuickWindow *const window = quickWindow();
    if (!root || !window || root->window() != window)
        return {};

    const qreal split = m_owner.timelineSplitX();
    return {split, 0.0, std::max<qreal>(0.0, root->width() - split),
            std::max<qreal>(0.0, root->height())};
}

QRectF PlayheadOverlay::timelineColumnRect() const
{
    songview::TimelineQuickView *const quickView = m_owner.quickView();
    QQuickItem *const root = quickView ? quickView->rootObject() : nullptr;
    const QRectF localColumn = canvasTimelineColumnRect();
    return root && !localColumn.isEmpty() ? root->mapRectToScene(localColumn) : QRectF{};
}

void PlayheadOverlay::ensureWindowTracking()
{
    songview::TimelineQuickView *quickView = m_owner.quickView();
    if (quickView && !m_detachConnected) {
        connect(quickView, &songview::TimelineQuickView::windowAboutToDetach, this,
                &PlayheadOverlay::clearNativeAttachment);
        m_detachConnected = true;
    }
    if (quickView && !m_inputEligibilityConnected) {
        connect(quickView, &songview::TimelineQuickView::inputEligibleChanged, this,
                &PlayheadOverlay::synchronizeGeometry);
        m_inputEligibilityConnected = true;
    }

#ifdef __APPLE__
    QuickPopupSession *const popupSession = quickView ? quickView->popupSession() : nullptr;
    if (m_popupSession != popupSession) {
        if (m_popupSession)
            disconnect(m_popupSession, nullptr, this, nullptr);
        m_popupSession = popupSession;
        if (m_popupSession) {
            connect(m_popupSession, &QuickPopupSession::isOpenChanged, this,
                    &PlayheadOverlay::synchronizeGeometry);
            connect(m_popupSession, &QuickPopupSession::geometryChanged, this,
                    &PlayheadOverlay::synchronizeGeometry);
        }
    }
#endif

    QQuickWindow *window = quickView ? quickView->quickWindow() : nullptr;
    if (window && m_filteredWindow != window) {
        if (m_filteredWindow)
            m_filteredWindow->removeEventFilter(this);
        window->installEventFilter(this);
        m_filteredWindow = window;
    }
}

bool PlayheadOverlay::eventFilter(QObject *watched, QEvent *event)
{
    // SurfaceCreated always arrives after the platform window exists, but a
    // surface can also be created while the window is still hidden (deferred
    // creation); QShowEvent is then the one authoritative show notification,
    // so both re-run the attach gate. Neither forces surface creation.
    if (event->type() == QEvent::PlatformSurface) {
        const auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
        if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed)
            clearNativeAttachment();
        else if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated)
            synchronizeGeometry();
    } else if (event->type() == QEvent::Show) {
        synchronizeGeometry();
    }
    return QObject::eventFilter(watched, event);
}

void PlayheadOverlay::clearNativeAttachment()
{
#ifdef __APPLE__
    if (m_platform)
        detachPlatform();
#endif
}

void PlayheadOverlay::synchronizeGeometry()
{
    ensureWindowTracking();
#ifdef __APPLE__
    QQuickWindow *const window = quickWindow();
    songview::TimelineQuickView *const quickCanvas = quickView();
    QQuickItem *const root = quickCanvas ? quickCanvas->rootObject() : nullptr;
    const QRectF canvasTimelineColumn = canvasTimelineColumnRect();
    const QRectF timelineColumn = timelineColumnRect();
    const std::optional<TimelineBandGeometry> &rulerBand = m_layout.geometry(TimelineBand::Ruler);

    m_visibleSurfaceRects.clear();
    m_triangleClips.clear();
    m_bodyGeometry = {};
    m_triangleTop = 0.0;

    if (root && window && root->window() == window && !canvasTimelineColumn.isEmpty() &&
        !timelineColumn.isEmpty() && rulerBand && !rulerBand->plotRect.isEmpty()) {
        const auto relativeToTimelineColumn = [&root, &timelineColumn](const QRectF &canvasRect) {
            return root->mapRectToScene(canvasRect).translated(-timelineColumn.topLeft());
        };
        const auto mapToVisibleScene = [root](const QRectF &canvasRect) {
            QRectF sceneRect = root->mapRectToScene(canvasRect);
            for (QQuickItem *ancestor = root; ancestor && !sceneRect.isEmpty();
                 ancestor = ancestor->parentItem()) {
                if (ancestor->clip())
                    sceneRect =
                        sceneRect.intersected(ancestor->mapRectToScene(ancestor->boundingRect()));
            }
            return sceneRect;
        };
        const auto visibleBandRect = [&canvasTimelineColumn](const TimelineBandGeometry &band) {
            return QRectF(band.plotRect).intersected(canvasTimelineColumn);
        };
        const QRectF rulerVisible = visibleBandRect(*rulerBand);
        if (!rulerVisible.isEmpty()) {
            const QRectF bodyCanvasGeometry{
                canvasTimelineColumn.left(), rulerVisible.top(), canvasTimelineColumn.width(),
                std::max<qreal>(0.0, canvasTimelineColumn.bottom() - rulerVisible.top())};
            m_bodyGeometry = relativeToTimelineColumn(bodyCanvasGeometry);

            QRectF popupOcclusion;
            if (m_popupSession && m_popupSession->isOpen())
                popupOcclusion = m_popupSession->contentRectInScene();

            for (const std::optional<TimelineBandGeometry> &band : m_layout.bands) {
                if (!band)
                    continue;
                const QRectF visible = visibleBandRect(*band);
                if (visible.isEmpty())
                    continue;
                const QRectF sceneRect = mapToVisibleScene(visible);
                const QRectF localRect = sceneRect.translated(-timelineColumn.topLeft());
                const QRectF localOcclusion = popupOcclusion.translated(-timelineColumn.topLeft());
                appendWithoutOcclusion(m_visibleSurfaceRects, localRect, localOcclusion);
            }

            const qreal triangleHeight = playheadTriangleHeight();
            const qreal triangleHalfWidth = playheadTriangleHalfWidth();
            const qreal triangleTop = rulerVisible.top() + rulerVisible.height() - triangleHeight;
            const QRectF triangleBounds{rulerVisible.left() - triangleHalfWidth, rulerVisible.top(),
                                        rulerVisible.width() + triangleHalfWidth,
                                        rulerVisible.height()};
            const QRectF triangleCanvasClip = triangleBounds.intersected(
                QRectF(triangleBounds.left(), triangleTop, triangleBounds.width(), triangleHeight));
            if (!triangleCanvasClip.isEmpty()) {
                const QRectF triangleSceneGeometry = root->mapRectToScene(triangleCanvasClip);
                m_triangleTop = triangleSceneGeometry.translated(-timelineColumn.topLeft()).top();
                appendWithoutOcclusion(
                    m_triangleClips,
                    mapToVisibleScene(triangleCanvasClip).translated(-timelineColumn.topLeft()),
                    popupOcclusion.translated(-timelineColumn.topLeft()));
            }
        }
    }
#endif
    m_trianglePointsUp = !m_layout.geometry(TimelineBand::Roll).has_value();

#ifdef __APPLE__
    m_devicePixelRatio = window ? window->effectiveDevicePixelRatio() : 1.0;
    // Attach only to an already-created platform surface of a visible window;
    // surface creation is never forced here, and a later SurfaceCreated event
    // re-syncs through the window filter.
    if (!m_platform && window && window->handle() && window->isVisible())
        initializePlatform();
    if (m_platform) {
        setPlatformImages();
        setPlatformLayout();
    }
#endif
    updatePlayhead();
}

bool PlayheadOverlay::effectiveVisible() const
{
    songview::TimelineQuickView *const quickCanvas = quickView();
    const std::optional<TimelineBandGeometry> &rulerBand = m_layout.geometry(TimelineBand::Ruler);
    return quickCanvas && quickCanvas->inputEligible() && m_visible && rulerBand &&
           !rulerBand->plotRect.isEmpty() && m_timelineX >= 0.0 &&
           m_timelineX < canvasTimelineColumnRect().width();
}

void PlayheadOverlay::updatePlayhead()
{
#ifdef __APPLE__
    if (m_platform)
        setPlatformPosition();
#else
    if (auto *quickView = m_owner.quickView()) {
        quickView->setPlayhead(m_timelineX, effectiveVisible(), m_playing, m_trianglePointsUp);
        quickView->setPlayheadColor(m_color);
    }
#endif
}

} // namespace songview
