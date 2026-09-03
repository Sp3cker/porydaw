#include "playheadoverlay.h"
#include "layout.h"
#include "theme/themeruntime.h"

#include <QEvent>
#include <QLinearGradient>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QtGlobal>
#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
#include <QtMath>
#endif
#include <algorithm>
#include <utility>

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

namespace {

// Quadratic bloom: t=0 outer (α=0) → t=1 at the bar (α=peak).
void setQuadStops(QLinearGradient &g, const QColor &color, qreal peakAlpha)
{
    QColor stopColor = color;
    for (int i = 0; i <= 8; ++i) {
        const qreal t = qreal(i) / 8.0;
        stopColor.setAlphaF(peakAlpha * t * t);
        g.setColorAt(t, stopColor);
    }
}

// Draws the glow + 1px core with the bar at x. All coordinates may be
// fractional: the playhead position is sample-accurate and the antialiased
// vector fill keeps its subpixel motion (rollcheck asserts this at dpr 1).
void paintPlayheadBody(QPainter &painter, qreal x, int top, int height, bool playing,
                       const QColor &color)
{
    const qreal left = playheadGlowLeftExtent(playing);
    const qreal right = playheadGlowRightExtent(playing);
    const qreal peak = playheadPeakAlpha(playing);
    if (left > 0.0) {
        QLinearGradient gradient(x - left, 0, x, 0);
        setQuadStops(gradient, color, peak);
        painter.fillRect(QRectF(x - left, top, left, height), gradient);
    }
    if (right > 0.0) {
        QLinearGradient gradient(x + right, 0, x, 0);
        setQuadStops(gradient, color, peak);
        painter.fillRect(QRectF(x, top, right, height), gradient);
    }

    QPen core(color, playheadLineWidth(), Qt::SolidLine, Qt::FlatCap);
    painter.setPen(core);
    painter.drawLine(QPointF(x, top), QPointF(x, top + height));
}

} // namespace

bool platformPlayheadRendererEnabled()
{
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    return !qEnvironmentVariableIsSet("PORYDAW_FORCE_WIDGET_PLAYHEAD");
#else
    return false;
#endif
}

PlayheadOverlay::PlayheadOverlay(QWidget &owner, PlayheadBand rulerBand, QWidget &rollBand,
                                 std::vector<PlayheadBand> clipBands)
    : QWidget(&owner)
    , m_rulerBand(rulerBand)
    , m_rollBand(rollBand)
    , m_clipBands(std::move(clipBands))
    , m_color(themes::color(themes::Role::song_view_playhead))
{
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_NoSystemBackground);

    // This visual layer must never become the keyboard target.
    setFocusPolicy(Qt::NoFocus);

    observeSurfaceGeometry();
    synchronizeGeometry();
}

PlayheadOverlay::~PlayheadOverlay()
{
    removeObservedSurfaceFilters();
}

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible, bool playing)
{
    if (m_timelineX == timelineX && m_visible == visible && m_playing == playing)
        return;

#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
    const bool playingChanged = m_playing != playing;
#endif

    m_timelineX = timelineX;
    m_visible = visible;
    m_playing = playing;

#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
    if (m_platform && playingChanged && updateImages())
        setPlatformImages();
#endif
    updatePlayhead();
}

void PlayheadOverlay::updateBands(PlayheadBand rulerBand, QWidget &rollBand,
                                  std::vector<PlayheadBand> clipBands)
{
    Q_ASSERT(&m_rulerBand.widget == &rulerBand.widget);
    Q_ASSERT(&m_rollBand == &rollBand);
    m_rulerBand.timelineOrigin = rulerBand.timelineOrigin;
    m_clipBands.swap(clipBands);
    observeSurfaceGeometry();
    synchronizeGeometry();
}

const QPainterPath &PlayheadOverlay::playheadTrianglePath()
{
    const QSize currentSize(playheadTriangleHalfWidth(), playheadTriangleHeight());
    if (m_playheadTrianglePathSize == currentSize)
        return m_playheadTrianglePath;

    QPainterPath path;
    path.moveTo(-currentSize.width(), 0);
    path.lineTo(currentSize.width(), 0);
    path.lineTo(0, currentSize.height());
    path.closeSubpath();
    m_playheadTrianglePath = std::move(path);
    m_playheadTrianglePathSize = currentSize;
    return m_playheadTrianglePath;
}
void PlayheadOverlay::paintEvent(QPaintEvent *event)
{
    if (m_platformApplied || !m_visible || m_fallbackPaintRegion.isEmpty())
        return;

    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setClipRegion(event->region().intersected(m_fallbackPaintRegion));

    painter.save();
    painter.setClipRegion(m_visibleSurfaceRegion, Qt::IntersectClip);
    paintPlayheadBody(painter, finalX(), m_bodyGeometry.top(), m_bodyGeometry.height(), m_playing,
                      m_color);
    painter.restore();

    painter.save();
    painter.setClipRect(m_triangleClip, Qt::IntersectClip);
    painter.translate(finalX(), m_triangleClip.top());
    if (m_trianglePointsUp) {
        painter.translate(0.0, playheadTriangleHeight());
        painter.scale(1.0, -1.0);
    }
    painter.fillPath(playheadTrianglePath(), m_color);
    painter.restore();
}
QRegion PlayheadOverlay::fallbackPaintRegion() const
{
    if (!m_visible)
        return {};

    const qreal padding = layout::singlePixel();
    const qreal coreHalfWidth = playheadLineWidth() / 2.0;
    const qreal leftExtent = std::max(playheadGlowLeftExtent(m_playing), coreHalfWidth);
    const qreal rightExtent = std::max(playheadGlowRightExtent(m_playing), coreHalfWidth);
    const QRect bodyBounds = QRectF(finalX() - leftExtent, m_bodyGeometry.top(),
                                    leftExtent + rightExtent, m_bodyGeometry.height())
                                 .adjusted(-padding, -padding, padding, padding)
                                 .toAlignedRect();
    const QRect triangleBounds =
        QRectF(finalX() - playheadTriangleHalfWidth(), m_triangleClip.top(),
               2 * playheadTriangleHalfWidth(), playheadTriangleHeight())
            .adjusted(-padding, -padding, padding, padding)
            .toAlignedRect();

    QRegion region = m_visibleSurfaceRegion.intersected(bodyBounds);
    region += m_triangleClip.intersected(triangleBounds);
    return region;
}

void PlayheadOverlay::removeObservedSurfaceFilters()
{
    for (const QPointer<QWidget> &widget : m_observedSurfaceChain) {
        if (widget)
            widget->removeEventFilter(this);
    }
    m_observedSurfaceChain.clear();
}
void PlayheadOverlay::exposeFallbackPixels(const QRegion &region)
{
    if (region.isEmpty())
        return;
    if (QWidget *owner = parentWidget())
        owner->update(region);
}

void PlayheadOverlay::updateFallbackRegion()
{
    const QRegion previousRegion = m_fallbackPaintRegion;
    const QRegion currentRegion = m_platformApplied ? QRegion{} : fallbackPaintRegion();
    const bool shouldShow = !currentRegion.isEmpty();
    if (previousRegion == currentRegion && isHidden() == !shouldShow)
        return;

    m_fallbackPaintRegion = currentRegion;
    if (!shouldShow) {
        if (!isHidden())
            hide();
        if (!mask().isEmpty())
            clearMask();
        exposeFallbackPixels(previousRegion);
        return;
    }

    if (mask() != currentRegion)
        setMask(currentRegion);
    if (isHidden())
        show();
    raise();
    exposeFallbackPixels(previousRegion);
    update(currentRegion);
}

void PlayheadOverlay::observeSurfaceGeometry()
{
    removeObservedSurfaceFilters();

    QWidget *owner = parentWidget();
    if (!owner)
        return;
    QWidget *const topLevel = owner->window();

    const auto observe = [this, topLevel](QWidget *surface) {
        for (QWidget *widget = surface; widget; widget = widget->parentWidget()) {
            bool alreadyObserved = false;
            for (const QPointer<QWidget> &observed : m_observedSurfaceChain) {
                if (observed.data() == widget) {
                    alreadyObserved = true;
                    break;
                }
            }
            if (!alreadyObserved) {
                widget->installEventFilter(this);
                m_observedSurfaceChain.push_back(widget);
            }
            if (widget == topLevel)
                break;
        }
    };
    observe(&m_rulerBand.widget);
    observe(&m_rollBand);
    for (const PlayheadBand &band : m_clipBands)
        observe(&band.widget);
}

bool PlayheadOverlay::eventFilter(QObject *, QEvent *event)
{
    switch (event->type()) {
    case QEvent::Show:
    case QEvent::WinIdChange:
        synchronizeGeometry();
        break;
    case QEvent::ParentChange:
        observeSurfaceGeometry();
        synchronizeGeometry();
        break;
    case QEvent::Hide:
    case QEvent::Move:
    case QEvent::Resize:
    case QEvent::LayoutRequest:
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    case QEvent::DevicePixelRatioChange:
#else
    case QEvent::ScreenChangeInternal:
#endif
        synchronizeGeometry();
        break;
    default:
        break;
    }
    return false;
}

void PlayheadOverlay::changeEvent(QEvent *event)
{
    QWidget::changeEvent(event);
    switch (event->type()) {
    case QEvent::ApplicationPaletteChange:
    case QEvent::PaletteChange:
    case QEvent::StyleChange: {
        const QColor newColor = themes::color(themes::Role::song_view_playhead);
        if (m_color != newColor) {
            m_color = newColor;
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
            if (m_platform) {
#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
                if (updateImages())
                    setPlatformImages();
#else
                setPlatformImages();
#endif
            }
#endif
            updatePlayhead();
            if (!m_platformApplied && !m_fallbackPaintRegion.isEmpty())
                update(m_fallbackPaintRegion);
        }
        break;
    }
    default:
        break;
    }
}

QRect PlayheadOverlay::visibleSurfaceRect(const QWidget *surface, QWidget *owner, int origin) const
{
    if (!surface->isVisibleTo(owner))
        return {};
    if (origin >= surface->width())
        return {};
    QPoint offset = surface->mapTo(owner, QPoint(0, 0));
    QRect visible(offset + QPoint(origin, 0), QSize(surface->width() - origin, surface->height()));
    for (const QWidget *widget = surface; widget; widget = widget->parentWidget()) {
        if (!widget->isVisible())
            return {};

        visible &= QRect(widget->mapTo(owner, QPoint(0, 0)), widget->size());
        if (widget == owner)
            break;
    }
    return visible;
}

void PlayheadOverlay::synchronizeGeometry()
{
    QWidget *ownerWidget = parentWidget();
    if (!ownerWidget)
        return;
    QWidget &owner = *ownerWidget;

    const QRect rulerGeometry(m_rulerBand.widget.mapTo(&owner, QPoint(0, 0)),
                              m_rulerBand.widget.size());
    const int bodyTop = rulerGeometry.top();
    const QRect bodyGeometry(0, bodyTop, owner.width(), std::max(0, owner.height() - bodyTop));
    const QRect rulerVisible =
        visibleSurfaceRect(&m_rulerBand.widget, &owner, m_rulerBand.timelineOrigin);
    const int triangleTop =
        rulerGeometry.bottom() - playheadTriangleHeight() + layout::singlePixel();
    const QRect triangleClip = rulerVisible.intersected(
        QRect(rulerVisible.left(), triangleTop, rulerVisible.width(), playheadTriangleHeight()));

    QRegion visibleSurfaces =
        visibleSurfaceRect(&m_rulerBand.widget, &owner, m_rulerBand.timelineOrigin);
    for (const PlayheadBand &band : m_clipBands)
        visibleSurfaces += visibleSurfaceRect(&band.widget, &owner, band.timelineOrigin);

    const int timelineOrigin =
        m_rulerBand.widget.mapTo(&owner, QPoint(m_rulerBand.timelineOrigin, 0)).x();

    if (geometry() != owner.rect())
        setGeometry(owner.rect());

    m_visibleSurfaceRegion = visibleSurfaces;
    m_bodyGeometry = bodyGeometry;
    m_triangleClip = triangleClip;
    m_timelineOrigin = timelineOrigin;
    m_trianglePointsUp = !m_rollBand.isVisibleTo(&owner);
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    m_devicePixelRatio = owner.devicePixelRatioF();
    bool platformCreated = false;
    if (!m_platform && !m_platformAttempted && owner.isVisible()) {
        m_platformAttempted = true;
        if (platformPlayheadRendererEnabled()) {
            initializePlatform(owner);
            platformCreated = true;
        }
    }
#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
    const bool imagesChanged = m_platform && updateImages();
    if (m_platform && (imagesChanged || platformCreated))
        setPlatformImages();
#else
    if (m_platform && platformCreated)
        setPlatformImages();
#endif
    if (m_platform)
        setPlatformLayout();
#endif
    updatePlayhead();
}

void PlayheadOverlay::updatePlayhead()
{
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    m_platformApplied = m_platform && setPlatformPosition();
#else
    m_platformApplied = false;
#endif
    updateFallbackRegion();
}

#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
bool PlayheadOverlay::updateImages()
{
    const QColor currentThemeColor = m_color;
    const int currentHeight = m_bodyGeometry.height();
    const qreal currentDpr = m_devicePixelRatio > 0.0 ? m_devicePixelRatio : 1.0;
    const bool geometryValid = !m_bodyGeometry.isEmpty() && currentHeight > 0;
    bool imagesChanged = false;

    if (!geometryValid) {
        imagesChanged = !m_bodyImage.isNull() || !m_triangleImage.isNull();
        m_bodyImage = QImage();
        m_triangleImage = QImage();
        m_cachedBodyValid = false;
        m_cachedTriangleValid = false;
        return imagesChanged;
    }

    const bool bodyNeedsUpdate = !m_cachedBodyValid || m_cachedBodyHeight != currentHeight ||
                                 m_cachedBodyPlaying != m_playing ||
                                 m_cachedBodyDpr != currentDpr ||
                                 m_cachedBodyThemeColor != currentThemeColor;

    if (bodyNeedsUpdate) {
        imagesChanged = true;
        m_cachedBodyHeight = currentHeight;
        m_cachedBodyPlaying = m_playing;
        m_cachedBodyDpr = currentDpr;
        m_cachedBodyThemeColor = currentThemeColor;
        m_cachedBodyValid = true;

        const qreal leftExtent = playheadGlowLeftExtent(m_playing);
        const qreal rightExtent = playheadGlowRightExtent(m_playing);
        m_bodyImageLeftExtent = leftExtent;

        const qreal bodyWidthLogical = leftExtent + rightExtent;
        const int bodyPixelWidth = qCeil(bodyWidthLogical * currentDpr);
        const int bodyPixelHeight = qCeil(currentHeight * currentDpr);

        if (bodyPixelWidth > 0 && bodyPixelHeight > 0) {
            QImage bodyImg(bodyPixelWidth, bodyPixelHeight, QImage::Format_ARGB32_Premultiplied);
            bodyImg.setDevicePixelRatio(currentDpr);
            bodyImg.fill(Qt::transparent);

            QPainter painter(&bodyImg);
            painter.setRenderHint(QPainter::Antialiasing);
            // The bar sits leftExtent from the image's left edge; the
            // platform renderers position the image so it lands on finalX.
            paintPlayheadBody(painter, leftExtent, 0, currentHeight, m_playing, currentThemeColor);
            painter.end();

            m_bodyImage = std::move(bodyImg);
        } else {
            m_bodyImage = QImage();
        }
    }

    const QSize currentTriangleSize(2 * playheadTriangleHalfWidth(), playheadTriangleHeight());
    const bool triangleNeedsUpdate =
        !m_cachedTriangleValid || m_cachedTrianglePointsUp != m_trianglePointsUp ||
        m_cachedTriangleDpr != currentDpr || m_cachedTriangleThemeColor != currentThemeColor ||
        m_cachedTriangleSize != currentTriangleSize;

    if (triangleNeedsUpdate) {
        imagesChanged = true;
        m_cachedTrianglePointsUp = m_trianglePointsUp;
        m_cachedTriangleDpr = currentDpr;
        m_cachedTriangleThemeColor = currentThemeColor;
        m_cachedTriangleSize = currentTriangleSize;
        m_cachedTriangleValid = true;

        const qreal triWidthLogical = currentTriangleSize.width();
        const qreal triHeightLogical = currentTriangleSize.height();
        const int triPixelWidth = qCeil(triWidthLogical * currentDpr);
        const int triPixelHeight = qCeil(triHeightLogical * currentDpr);

        if (triPixelWidth > 0 && triPixelHeight > 0) {
            QImage triImg(triPixelWidth, triPixelHeight, QImage::Format_ARGB32_Premultiplied);
            triImg.setDevicePixelRatio(currentDpr);
            triImg.fill(Qt::transparent);

            QPainter painter(&triImg);
            painter.setRenderHint(QPainter::Antialiasing);
            painter.translate(currentTriangleSize.width() / 2.0,
                              m_trianglePointsUp ? triHeightLogical : 0);
            if (m_trianglePointsUp)
                painter.scale(1.0, -1.0);
            painter.fillPath(playheadTrianglePath(), currentThemeColor);
            painter.end();

            m_triangleImage = std::move(triImg);
        } else {
            m_triangleImage = QImage();
        }
    }
    return imagesChanged;
}
#endif // PORYDAW_USE_MACOS_PLAYHEAD_IMAGES

} // namespace songview
