#include "timelinesurface.h"

#include <QEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QResizeEvent>

namespace songview {

TimelineSurface::TimelineSurface(QWidget *parent)
    : QWidget(parent)
{
}

void TimelineSurface::invalidateContent()
{
    m_dirtyContentRegion = rect();
    QWidget::update();
}

void TimelineSurface::invalidateContent(const QRegion &region)
{
    const QRegion clipped = region.intersected(rect());
    if (clipped.isEmpty())
        return;
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
    const qint64 estimatedCacheBytes =
        qint64(pixelSize.width()) * qint64(pixelSize.height()) * 4;
    constexpr qint64 maxEstimatedCacheBytes = 256 * 1024 * 1024;
    const bool estimateFitsBudget = pixelSize.width() > 0 && pixelSize.height() > 0
                                    && estimatedCacheBytes > 0
                                    && estimatedCacheBytes <= maxEstimatedCacheBytes;

    if (!estimateFitsBudget) {
        m_contentCache = {};
        m_diagnostics.estimatedContentCacheBytes = 0;
        QPainter painter(this);
        countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
        paintContent(painter);
        return;
    }

    if (m_contentCache.size() != pixelSize
        || !qFuzzyCompare(m_contentCache.devicePixelRatio(), dpr)) {
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
    //    the boundary pixels at partial clip coverage. Snap each dirty rect
    //    outward to the smallest logical grid whose device size is integral
    //    (1 at integer scales, 2 at 150%, 4 at any quarter scale — exact in
    //    binary floating point). With no practical grid, repaint fully.
    int alignmentGrid = 0;
    for (int candidate = 1; candidate <= 64; ++candidate) {
        const qreal scaled = dpr * candidate;
        if (qAbs(scaled - qRound(scaled)) < 1e-9) {
            alignmentGrid = candidate;
            break;
        }
    }
    QRegion repaintRegion;
    if (alignmentGrid == 0) {
        repaintRegion = rect();
    } else if (alignmentGrid == 1) {
        repaintRegion = dirtyRegion;
    } else {
        for (const QRect &dirtyRect : dirtyRegion) {
            const int left = (dirtyRect.left() / alignmentGrid) * alignmentGrid;
            const int top = (dirtyRect.top() / alignmentGrid) * alignmentGrid;
            const int right = ((dirtyRect.right() + alignmentGrid) / alignmentGrid)
                              * alignmentGrid;
            const int bottom = ((dirtyRect.bottom() + alignmentGrid) / alignmentGrid)
                               * alignmentGrid;
            // Overhang past the widget is fine: the pixmap edge is a whole
            // device pixel, so the engine's clamp stays device-aligned.
            repaintRegion += QRect(left, top, right - left, bottom - top);
        }
    }

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
            const quint64 deviceWidth =
                quint64(qCeil((logicalRect.right() + 1) * dpr))
                - quint64(qFloor(logicalRect.left() * dpr));
            const quint64 deviceHeight =
                quint64(qCeil((logicalRect.bottom() + 1) * dpr))
                - quint64(qFloor(logicalRect.top() * dpr));
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
