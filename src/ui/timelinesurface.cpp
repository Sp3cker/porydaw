#include "timelinesurface.h"

#include <QEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QResizeEvent>

namespace songview {

int deviceAlignmentGrid(qreal dpr) noexcept
{
    for (int candidate = 1; candidate <= 64; ++candidate) {
        const qreal scaled = dpr * candidate;
        if (qAbs(scaled - qRound(scaled)) < 1e-9)
            return candidate;
    }
    return 0;
}

QRegion expandRegionToDeviceGrid(const QRegion &region, int grid)
{
    if (grid <= 1)
        return region;
    QRegion expanded;
    for (const QRect &rect : region) {
        const int left = (rect.left() / grid) * grid;
        const int top = (rect.top() / grid) * grid;
        const int right = ((rect.right() + grid) / grid) * grid;
        const int bottom = ((rect.bottom() + grid) / grid) * grid;
        expanded += QRect(left, top, right - left, bottom - top);
    }
    return expanded;
}

TimelineSurface::TimelineSurface(QWidget *parent) : QWidget(parent) {}

void TimelineSurface::invalidateContent()
{
    m_dirtyContentRegion = rect();
    QWidget::update();
}

void TimelineSurface::invalidateContent(const QRegion &region)
{
    // Snap the update region to whole device pixels before it reaches Qt.
    // The region does not stay internal: it becomes the paint-event region,
    // the backing-store dirty region, and ultimately the on-screen flush
    // rectangle — every one of which Qt scales to device pixels with its own
    // rounding. At fractional scale factors an exact logical region can lose
    // its half-covered boundary device pixels in that rounding, leaving old
    // screen content behind ("cursor trails" that no cache-level fix — nor a
    // grab()-based check, which bypasses the backing store — can catch).
    const int grid = deviceAlignmentGrid(devicePixelRatioF());
    QRegion clipped = region.intersected(rect());
    if (clipped.isEmpty())
        return;
    clipped =
        grid == 0 ? QRegion(rect()) : expandRegionToDeviceGrid(clipped, grid).intersected(rect());
    m_dirtyContentRegion |= clipped;
    QWidget::update(clipped);
}

TimelineSurfaceDiagnostics TimelineSurface::diagnostics() const noexcept
{
    return m_diagnostics;
}

void TimelineSurface::paintEvent(QPaintEvent *event)
{
    const qreal dpr = devicePixelRatioF();
    const QSize pixelSize(qCeil(width() * dpr), qCeil(height() * dpr));
    const qint64 estimatedCacheBytes = qint64(pixelSize.width()) * qint64(pixelSize.height()) * 4;
    constexpr qint64 maxEstimatedCacheBytes = 256 * 1024 * 1024;
    // Diagnostic escape hatch: paints every surface directly, isolating the
    // cache when hunting stale-pixel artifacts in the field.
    static const bool forceUncached = qEnvironmentVariableIsSet("PORYDAW_FORCE_UNCACHED_TIMELINE");
    const bool estimateFitsBudget = !forceUncached && pixelSize.width() > 0 &&
                                    pixelSize.height() > 0 && estimatedCacheBytes > 0 &&
                                    estimatedCacheBytes <= maxEstimatedCacheBytes;

    if (!estimateFitsBudget) {
        m_contentCache = {};
        m_diagnostics.estimatedContentCacheBytes = 0;
        QPainter painter(this);
        countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
        paintContent(painter);
        return;
    }

    if (m_contentCache.size() != pixelSize ||
        !qFuzzyCompare(m_contentCache.devicePixelRatio(), dpr)) {
        m_contentCache = QPixmap(pixelSize);
        if (!m_contentCache.isNull()) {
            m_contentCache.setDevicePixelRatio(dpr);
            m_dirtyContentRegion = rect();
            m_diagnostics.estimatedContentCacheBytes = quint64(estimatedCacheBytes);
        }
    }

    if (m_contentCache.isNull()) {
        m_diagnostics.estimatedContentCacheBytes = 0;
        QPainter painter(this);
        countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
        paintContent(painter);
        return;
    }

    if (m_dirtyContentRegion.isEmpty()) {
        QPainter painter(this);
        painter.drawPixmap(QPointF(0, 0), m_contentCache);
        return;
    }

    // Re-rasterize only the dirty content this paint event exposes. The
    // automation lanes are a full-height content widget inside a scroll
    // area: without this bound, a full invalidation (every drag move)
    // rasterizes its off-viewport rows too. Dirt outside the event region
    // stays pending and repaints exactly once when Qt exposes it — and
    // QWidget::render (so grab()) delivers the full rect, keeping offscreen
    // snapshots complete.
    const QRegion dirtyRegion =
        m_dirtyContentRegion.intersected(event->region()).intersected(rect());
    if (dirtyRegion.isEmpty()) {
        QPainter painter(this);
        painter.drawPixmap(QPointF(0, 0), m_contentCache);
        return;
    }

    // Partial repaints must be pixel-identical to a full repaint, or stale
    // fringes accumulate in the cache ("cursor trails"). Two ingredients:
    //
    // 1. Render straight into the cache under a clip — the painter transform
    //    is then the full repaint's, so rasterization matches bit-for-bit.
    //    (An intermediate patch pixmap is NOT equivalent: its fractional
    //    translate, deviceLeft / dpr, perturbs coordinates that land exactly
    //    on device-pixel boundaries at fractional scale factors.) This
    //    relies on paintContent implementations only ever narrowing the
    //    painter's clip (save + Qt::IntersectClip + restore, no ReplaceClip).
    //
    // 2. The clip itself must sit on whole device pixels, or Qt recomposes
    //    the boundary pixels at partial clip coverage. invalidateContent
    //    already snaps its regions, but Qt may coalesce or synthesize event
    //    regions (render()/grab(), platform expose events), so snap again to
    //    the smallest logical grid whose device size is integral (1 at
    //    integer scales, 2 at 150%, 4 at any quarter scale — exact in binary
    //    floating point). With no practical grid, repaint fully. Overhang
    //    past the widget is fine: the pixmap edge is a whole device pixel,
    //    so the engine's clamp stays device-aligned.
    const int alignmentGrid = deviceAlignmentGrid(dpr);
    const QRegion repaintRegion =
        alignmentGrid == 0 ? QRegion(rect()) : expandRegionToDeviceGrid(dirtyRegion, alignmentGrid);

    if (QRegion(rect()).subtracted(repaintRegion).isEmpty()) {
        m_contentCache.fill(Qt::transparent);
        QPainter cachePainter(&m_contentCache);
        countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
        paintContent(cachePainter);
        m_dirtyContentRegion = QRegion();
    } else {
        QPainter cachePainter(&m_contentCache);
        cachePainter.setClipRegion(repaintRegion);
        cachePainter.setCompositionMode(QPainter::CompositionMode_Clear);
        cachePainter.fillRect(rect(), Qt::transparent);
        cachePainter.setCompositionMode(QPainter::CompositionMode_SourceOver);
        quint64 repaintDevicePixels = 0;
        for (const QRect &logicalRect : repaintRegion) {
            const quint64 deviceWidth = quint64(qCeil((logicalRect.right() + 1) * dpr)) -
                                        quint64(qFloor(logicalRect.left() * dpr));
            const quint64 deviceHeight = quint64(qCeil((logicalRect.bottom() + 1) * dpr)) -
                                         quint64(qFloor(logicalRect.top() * dpr));
            repaintDevicePixels += deviceWidth * deviceHeight;
        }
        countContentPaint(repaintDevicePixels);
        paintContent(cachePainter);
        // Everything under the (possibly expanded) repaint is fresh now; any
        // pending dirt it covered still has its own queued update event, so
        // the screen catches up even though the cache is already clean.
        m_dirtyContentRegion -= repaintRegion;
    }

    QPainter painter(this);
    painter.drawPixmap(QPointF(0, 0), m_contentCache);
}

void TimelineSurface::changeEvent(QEvent *event)
{
    QWidget::changeEvent(event);
    switch (event->type()) {
    case QEvent::PaletteChange:
    case QEvent::ApplicationPaletteChange:
    case QEvent::FontChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
        invalidateContent();
        break;
    default:
        break;
    }
}

void TimelineSurface::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_contentCache = {};
    m_diagnostics.estimatedContentCacheBytes = 0;
    invalidateContent();
}

void TimelineSurface::countContentPaint(quint64 pixelCount) noexcept
{
    ++m_diagnostics.contentPaintCount;
    m_diagnostics.contentPaintPixelCount += pixelCount;
}

} // namespace songview
