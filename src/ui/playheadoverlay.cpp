#include "playheadoverlay.h"
#include "layout.h"
#include "songview.h"
#include "theme/themeruntime.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QLinearGradient>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QSize>
#include <QWidget>
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
    return !qEnvironmentVariableIsSet("PORYDAW_FORCE_WIDGET_PLAYHEAD") &&
           !qEnvironmentVariableIsSet("PORYDAW_FORCE_QUICK_PLAYHEAD");
#else
    return false;
#endif
}

bool quickPlayheadRendererEnabled()
{
    return qEnvironmentVariableIsSet("PORYDAW_FORCE_QUICK_PLAYHEAD");
}

// Software-painting stand-in for the native compositor layers: a transparent
// child of SongView hosting the vector glow + triangle that used to be painted
// by the overlay widget itself. PlayheadOverlay creates it lazily only while
// the native platform renderer is not applied and a paint region exists.
class PlayheadOverlay::FallbackWidget final : public QWidget
{
  public:
    explicit FallbackWidget(PlayheadOverlay &overlay)
        : QWidget(&overlay.m_owner)
        , m_overlay(overlay)
    {
        setAttribute(Qt::WA_TransparentForMouseEvents);
        setAttribute(Qt::WA_NoSystemBackground);

        // This visual layer must never become the keyboard target.
        setFocusPolicy(Qt::NoFocus);

        setGeometry(m_overlay.m_owner.rect());
    }

    // Releases the painted pixels before PlayheadOverlay destroys this
    // widget because the native platform renderer took over.
    void retire()
    {
        if (!isHidden())
            hide();
        if (!mask().isEmpty())
            clearMask();
        exposeFallbackPixels(m_paintRegion);
    }

    const QRegion &paintRegion() const { return m_paintRegion; }

    // Where the playhead will paint for the overlay's current state; empty
    // while the playhead is invisible. Static so PlayheadOverlay can decide
    // whether a fallback widget is worth creating.
    static QRegion fallbackPaintRegion(const PlayheadOverlay &overlay)
    {
        if (!overlay.m_visible)
            return {};

        const qreal padding = layout::singlePixel();
        const qreal coreHalfWidth = playheadLineWidth() / 2.0;
        const qreal leftExtent = std::max(playheadGlowLeftExtent(overlay.m_playing), coreHalfWidth);
        const qreal rightExtent =
            std::max(playheadGlowRightExtent(overlay.m_playing), coreHalfWidth);
        const QRect bodyBounds = QRectF(overlay.finalX() - leftExtent, overlay.m_bodyGeometry.top(),
                                        leftExtent + rightExtent, overlay.m_bodyGeometry.height())
                                     .adjusted(-padding, -padding, padding, padding)
                                     .toAlignedRect();
        const QRect triangleBounds =
            QRectF(overlay.finalX() - playheadTriangleHalfWidth(), overlay.m_triangleClip.top(),
                   2 * playheadTriangleHalfWidth(), playheadTriangleHeight())
                .adjusted(-padding, -padding, padding, padding)
                .toAlignedRect();

        QRegion region = overlay.m_visibleSurfaceRegion.intersected(bodyBounds);
        region += overlay.m_triangleClip.intersected(triangleBounds);
        return region;
    }

    void updateFallbackRegion()
    {
        const QRegion previousRegion = m_paintRegion;
        const QRegion currentRegion = fallbackPaintRegion(m_overlay);
        const bool shouldShow = !currentRegion.isEmpty();
        if (previousRegion == currentRegion && isHidden() == !shouldShow)
            return;

        m_paintRegion = currentRegion;
        if (!shouldShow) {
            if (!isHidden())
                hide();
            if (!mask().isEmpty())
                clearMask();
            exposeFallbackPixels(previousRegion);
            return;
        }

        const QRect ownerRect = m_overlay.m_owner.rect();
        if (geometry() != ownerRect)
            setGeometry(ownerRect);
        if (mask() != currentRegion)
            setMask(currentRegion);
        if (isHidden())
            show();
        raise();
        exposeFallbackPixels(previousRegion);
        update(currentRegion);
    }

  protected:
    void paintEvent(QPaintEvent *event) override
    {
        const PlayheadOverlay &overlay = m_overlay;
        if (!overlay.m_visible || m_paintRegion.isEmpty())
            return;

        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setClipRegion(event->region().intersected(m_paintRegion));

        painter.save();
        painter.setClipRegion(overlay.m_visibleSurfaceRegion, Qt::IntersectClip);
        paintPlayheadBody(painter, overlay.finalX(), overlay.m_bodyGeometry.top(),
                          overlay.m_bodyGeometry.height(), overlay.m_playing, overlay.m_color);
        painter.restore();

        painter.save();
        painter.setClipRect(overlay.m_triangleClip, Qt::IntersectClip);
        painter.translate(overlay.finalX(), overlay.m_triangleClip.top());
        if (overlay.m_trianglePointsUp) {
            painter.translate(0.0, playheadTriangleHeight());
            painter.scale(1.0, -1.0);
        }
        painter.fillPath(playheadTrianglePath(), overlay.m_color);
        painter.restore();
    }

  private:
    void exposeFallbackPixels(const QRegion &region)
    {
        if (region.isEmpty())
            return;
        m_overlay.m_owner.update(region);
    }

    const QPainterPath &playheadTrianglePath()
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

    PlayheadOverlay &m_overlay;
    QPainterPath m_playheadTrianglePath;
    QSize m_playheadTrianglePathSize;
    QRegion m_paintRegion;
};

PlayheadOverlay::PlayheadOverlay(SongView &owner, const TimelineBandLayout &layout)
    : QObject(&owner)
    , m_owner(owner)
    , m_layout(layout)
    , m_color(themes::color(themes::Role::song_view_playhead))
{
    synchronizeGeometry();
}

// SongView destroys its QWidget children (including FallbackWidget) before
// its QObject children, so during SongView teardown the fallback has usually
// already died and QPointer cleared itself. When this overlay dies first
// while SongView still lives, retire the painted pixels and delete the
// leftover child.
PlayheadOverlay::~PlayheadOverlay()
{
    if (m_fallback) {
        m_fallback->retire();
        delete m_fallback.data();
    }
}

QWidget *PlayheadOverlay::fallbackWidget() const noexcept
{
    return m_fallback;
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

void PlayheadOverlay::syncAppearance()
{
    const QColor newColor = themes::color(themes::Role::song_view_playhead);
    if (m_color == newColor)
        return;
    m_color = newColor;
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    if (m_platform)
        setPlatformImages();
#endif
    if (quickPlayheadRendererEnabled()) {
        if (auto *quickView =
                m_owner.findChild<TimelineQuickView *>(QStringLiteral("timelineQuickCanvas")))
            quickView->setPlayheadColor(m_color);
    }
    updatePlayhead();
    if (m_fallback) {
        const QRegion &region = m_fallback->paintRegion();
        if (!region.isEmpty())
            m_fallback->update(region);
    }
}

void PlayheadOverlay::updateFallbackRegion()
{
    if (m_platformApplied || quickPlayheadRendererEnabled()) {
        if (m_fallback) {
            m_fallback->retire();
            delete m_fallback.data();
        }
        return;
    }
    if (!m_fallback) {
        if (FallbackWidget::fallbackPaintRegion(*this).isEmpty())
            return;
        m_fallback = new FallbackWidget(*this);
    }
    m_fallback->updateFallbackRegion();
}

void PlayheadOverlay::synchronizeGeometry()
{
    SongView &owner = m_owner;

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
        // layout owner shows, and this overlay's owner is SongView, so one
        // intersected(owner.rect()) bounds the surface — no ancestor walk.
        const auto visibleBandRect = [&owner](const TimelineBandGeometry &band) {
            if (band.timelineOrigin >= band.rect.width())
                return QRect();
            const QRect visible(band.rect.x() + band.timelineOrigin, band.rect.y(),
                                band.rect.width() - band.timelineOrigin, band.rect.height());
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
    if (quickPlayheadRendererEnabled()) {
        if (auto *quickView =
                m_owner.findChild<TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"))) {
            quickView->setPlayhead(finalX(), m_visible, m_playing, m_trianglePointsUp);
            quickView->setPlayheadColor(m_color);
        }
    }
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    m_platformApplied = m_platform && setPlatformPosition();
#else
    m_platformApplied = false;
#endif
    updateFallbackRegion();
}

} // namespace songview
