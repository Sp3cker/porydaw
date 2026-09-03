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

PlayheadOverlay::PlayheadOverlay(QWidget &owner, const TimelineBandLayout &layout)
    : QWidget(&owner)
    , m_layout(layout)
    , m_color(themes::color(themes::Role::song_view_playhead))
{
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_NoSystemBackground);

    // This visual layer must never become the keyboard target.
    setFocusPolicy(Qt::NoFocus);

    synchronizeGeometry();
}

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
            if (m_platform)
                setPlatformImages();
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

void PlayheadOverlay::synchronizeGeometry()
{
    QWidget *ownerWidget = parentWidget();
    if (!ownerWidget)
        return;
    QWidget &owner = *ownerWidget;

    const std::optional<TimelineBandGeometry> &rulerBand = m_layout.geometry(TimelineBand::Ruler);
    if (!rulerBand) {
        // Without a ruler row nothing can be clipped to a timeline column.
        m_visibleSurfaceRegion = {};
        m_bodyGeometry = {};
        m_triangleClip = {};
    } else {
        const QRect &rulerRect = rulerBand->rect;
        const int bodyTop = rulerRect.top();
        m_bodyGeometry = QRect(0, bodyTop, owner.width(), std::max(0, owner.height() - bodyTop));

        // Canonical entries are SongView-local and omit hidden bands; each clip
        // rect starts at its band's timeline origin. Producer contract
        // (timelinebandlayout.h): band rects are already clipped to what their
        // layout owner shows, and this widget's parent is SongView, so one
        // intersected(owner.rect()) bounds the surface — no ancestor walk.
        const auto visibleBandRect = [&owner](const TimelineBandGeometry &band) {
            if (band.timelineOrigin >= band.rect.width())
                return QRect();
            const QRect visible(band.rect.x() + band.timelineOrigin, band.rect.y(),
                                band.rect.width() - band.timelineOrigin, band.rect.height());
            Q_ASSERT(visible.isEmpty() || owner.rect().contains(visible));
            return visible.intersected(owner.rect());
        };

        const QRect rulerVisible = visibleBandRect(*rulerBand);
        const int triangleTop =
            rulerRect.bottom() - playheadTriangleHeight() + layout::singlePixel();
        m_triangleClip = rulerVisible.intersected(QRect(
            rulerVisible.left(), triangleTop, rulerVisible.width(), playheadTriangleHeight()));

        m_visibleSurfaceRegion = rulerVisible;
        for (std::size_t index = 0; index < m_layout.bands.size(); ++index) {
            if (index == timelineBandIndex(TimelineBand::Ruler))
                continue;
            const std::optional<TimelineBandGeometry> &band = m_layout.bands[index];
            if (band)
                m_visibleSurfaceRegion += visibleBandRect(*band);
        }
        m_timelineOrigin = rulerRect.x() + rulerBand->timelineOrigin;
    }
    m_trianglePointsUp = !m_layout.geometry(TimelineBand::Roll).has_value();

    if (geometry() != owner.rect())
        setGeometry(owner.rect());

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
    if (m_platform && platformCreated)
        setPlatformImages();
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

} // namespace songview
