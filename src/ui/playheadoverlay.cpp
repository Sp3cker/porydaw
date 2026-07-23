#include "playheadoverlay.h"

#include <QEvent>
#include <QPainter>
#include <QPainterPath>
#include <algorithm>

namespace songview {

namespace {

const QPainterPath kPlayheadTriangle = [] {
    QPainterPath path;
    path.moveTo(-kPlayheadTriangleHalfWidth, 0);
    path.lineTo(kPlayheadTriangleHalfWidth, 0);
    path.lineTo(0, kPlayheadTriangleHeight);
    path.closeSubpath();
    return path;
}();

} // namespace

PlayheadOverlay::PlayheadOverlay(QWidget *owner, const Surfaces &surfaces,
                                 const QColor &color)
    : QWidget(owner)
    , m_surfaces(surfaces)
    , m_color(color)
{
    Q_ASSERT(owner);
    Q_ASSERT(m_surfaces.ruler);
    Q_ASSERT(m_surfaces.roll);

    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_NoSystemBackground);

    // Capture geometry of the ruler (and roll for show/hide) once at build
    // time. Reparenting afterwards leaves filters stale — SongView must
    // finish its hierarchy before creating the overlay.
    const auto observe = [this, owner](QWidget *surface) {
        for (QWidget *widget = surface; widget; widget = widget->parentWidget()) {
            widget->installEventFilter(this);
            if (widget == owner)
                break;
        }
    };
    observe(m_surfaces.ruler);
    observe(m_surfaces.roll);

    synchronizeGeometry();
    show();
}

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible)
{
    const qreal oldLocalX = m_localOrigin + m_timelineX;
    const bool oldVisible = m_visible;

    m_timelineX = timelineX;
    m_visible = visible;
    const qreal newLocalX = m_localOrigin + m_timelineX;

    if (oldLocalX == newLocalX && oldVisible == m_visible)
        return;

    QRegion dirty;
    if (oldVisible)
        dirty += playheadRegion(oldLocalX);
    if (m_visible)
        dirty += playheadRegion(newLocalX);
    if (!dirty.isEmpty())
        update(dirty);
}

bool PlayheadOverlay::eventFilter(QObject *, QEvent *event)
{
    switch (event->type()) {
    case QEvent::Move:
    case QEvent::Resize:
    case QEvent::Show:
    case QEvent::Hide:
    case QEvent::LayoutRequest:
        synchronizeGeometry();
        break;
    default:
        break;
    }
    return false;
}

void PlayheadOverlay::paintEvent(QPaintEvent *)
{
    if (!m_visible || width() <= 0 || height() <= 0)
        return;

    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);

    const qreal playheadX = m_localOrigin + m_timelineX;
    const bool trianglePointsUp = !m_surfaces.roll->isVisible();
    painter.translate(playheadX,
                      trianglePointsUp ? kPlayheadTriangleHeight : 0);
    if (trianglePointsUp)
        painter.scale(1.0, -1.0);
    painter.fillPath(kPlayheadTriangle, m_color);
}

QRect PlayheadOverlay::visibleTimelineBand(QWidget *owner) const
{
    const QWidget *ruler = m_surfaces.ruler;
    if (!ruler->isVisible() || m_surfaces.rulerOrigin >= ruler->width())
        return {};

    // Horizontal span matches the ruler's timeline area; vertical sits just
    // below the ruler (so do not intersect against the ruler's own rect).
    const QPoint rulerOrigin =
        ruler->mapTo(owner, QPoint(m_surfaces.rulerOrigin, 0));
    const int top = ruler->mapTo(owner, QPoint(0, 0)).y() + ruler->height();
    int left = rulerOrigin.x();
    int right = ruler->mapTo(owner, QPoint(ruler->width(), 0)).x();

    for (const QWidget *widget = ruler; widget; widget = widget->parentWidget()) {
        if (!widget->isVisible())
            return {};
        const QRect r(widget->mapTo(owner, QPoint(0, 0)), widget->size());
        left = std::max(left, r.left());
        right = std::min(right, r.right() + 1);
        if (widget == owner)
            break;
    }
    if (right - left <= 0)
        return {};
    return QRect(left, top, right - left, kPlayheadTriangleHeight + 1);
}

QRegion PlayheadOverlay::playheadRegion(qreal localX) const
{
    if (width() <= 0 || height() <= 0)
        return {};
    constexpr qreal kAntialiasPadding = 1.0;
    const QRect bounds =
        QRectF(localX - kPlayheadTriangleHalfWidth - kAntialiasPadding, 0,
               2.0 * kPlayheadTriangleHalfWidth + kAntialiasPadding * 2.0,
               height())
            .toAlignedRect()
            .intersected(rect());
    return QRegion(bounds);
}

void PlayheadOverlay::synchronizeGeometry()
{
    QWidget *owner = parentWidget();
    Q_ASSERT(owner);

    const QRect band = visibleTimelineBand(owner);
    const qreal ownerOrigin =
        m_surfaces.ruler->mapTo(owner, QPoint(m_surfaces.rulerOrigin, 0)).x();
    const qreal localOrigin = band.isEmpty() ? 0.0 : ownerOrigin - band.left();

    const qreal oldLocalX = m_localOrigin + m_timelineX;
    const QRegion oldDirty = m_visible ? playheadRegion(oldLocalX) : QRegion();

    if (band.isEmpty()) {
        hide();
        m_localOrigin = 0.0;
        return;
    }

    if (!isVisible())
        show();

    const bool geometryChanged = geometry() != band;
    const bool originChanged = m_localOrigin != localOrigin;
    if (!geometryChanged && !originChanged)
        return;

    if (geometryChanged)
        setGeometry(band);
    m_localOrigin = localOrigin;

    // After a move/resize, old local coords are stale — repaint the band.
    if (geometryChanged)
        update();
    else {
        const qreal newLocalX = m_localOrigin + m_timelineX;
        QRegion dirty =
            oldDirty | (m_visible ? playheadRegion(newLocalX) : QRegion());
        if (!dirty.isEmpty())
            update(dirty);
    }
    raise();
}

} // namespace songview
