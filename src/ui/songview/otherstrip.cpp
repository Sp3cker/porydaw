// ---------------------------------------------------------------- OtherStrip

#include "ui/songview/otherstrip.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"

#include <QEvent>
#include <QFontMetrics>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QStringList>
#include <QToolTip>

#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;

OtherStrip::Geometry OtherStrip::Geometry::resolve()
{
    return {lyt::fontPx(17.5 + 13.0 / 3.0), lyt::fontPx(1.0 / 3.0), lyt::fontPx(1.0 / 3.0),
            lyt::fontPx(5.0 / 12.0)};
}

void OtherStrip::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    setFixedHeight(QFontMetrics(font()).height() + lyt::space(Space::Two));
    invalidateContent();
}

OtherStrip::OtherStrip(SongView *sv)
    : TimelineSurface(sv)
    , m_sv(sv)
    , m_geometry(Geometry::resolve())
{
    setObjectName(QStringLiteral("otherEventsStrip"));
    refreshGeometry();
    setMouseTracking(true);
}

void OtherStrip::paintContent(QPainter &p)
{
    const qreal dpr = p.device()->devicePixelRatioF();
    p.fillRect(rect(), themes::color(themes::Role::song_view_timeline_chrome_background));
    p.setPen(themes::color(themes::Role::song_view_separator));
    p.drawLine(lyt::space(Space::Zero), lyt::space(Space::Zero), width(), lyt::space(Space::Zero));

    const SongViewModel &model = m_sv->model();
    p.setPen(themes::color(themes::Role::song_view_primary_text));
    const auto textInset = lyt::space(Space::Two);
    p.drawText(
        QRect(textInset, lyt::space(Space::Zero), m_geometry.plotOrigin - 2 * textInset, height()),
        Qt::AlignVCenter, SongView::tr("Other events (%1)").arg(model.strip.size()));
    if (!m_sv->timeline())
        return;

    const QRect area(m_geometry.plotOrigin, lyt::space(Space::Zero),
                     width() - m_geometry.plotOrigin, height());
    p.setClipRect(area, Qt::IntersectClip);
    drawPreRoll(p, m_sv, area, m_geometry.plotOrigin,
                themes::color(themes::Role::song_view_timeline_chrome_background));
    drawOverlays(p, m_sv, area, m_geometry.plotOrigin, false, false);

    const int cy = height() / 2;
    for (const StripItem &item : model.strip) {
        const qreal x = m_sv->displayX(double(item.tick), m_geometry.plotOrigin, dpr);
        if (x < area.left() - m_geometry.otherEventHitSlop ||
            x > area.right() + m_geometry.otherEventHitSlop)
            continue;
        QColor c = item.track >= 0 ? SongView::trackColor(item.track)
                                   : themes::color(themes::Role::song_view_file_event_marker);
        QPainterPath diamond;
        diamond.moveTo(x, cy - m_geometry.otherEventMarkerHalfHeight);
        diamond.lineTo(x + m_geometry.otherEventMarkerHalfWidth, cy);
        diamond.lineTo(x, cy + m_geometry.otherEventMarkerHalfHeight);
        diamond.lineTo(x - m_geometry.otherEventMarkerHalfWidth, cy);
        diamond.closeSubpath();
        p.fillPath(diamond, c);
    }
}

bool OtherStrip::event(QEvent *event)
{
    const bool handled = TimelineSurface::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}

void OtherStrip::mouseMoveEvent(QMouseEvent *event)
{
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl || event->position().x() < m_geometry.plotOrigin) {
        QToolTip::hideText();
        return;
    }
    QStringList lines;
    for (const StripItem &item : m_sv->model().strip) {
        const qreal x =
            m_sv->displayX(double(item.tick), m_geometry.plotOrigin, devicePixelRatioF());
        if (std::abs(x - event->position().x()) > m_geometry.otherEventHitSlop)
            continue;
        const double seconds = double(tl->sampleForTick(item.tick)) / tl->sampleRate;
        QString where =
            item.track >= 0 ? SongView::tr("Track %1").arg(item.track + 1) : SongView::tr("File");
        lines << QStringLiteral("%1:%2 · %3 · %4")
                     .arg(int(seconds) / 60)
                     .arg(int(seconds) % 60, 2, 10, QLatin1Char('0'))
                     .arg(where, item.label);
        if (lines.size() >= 12) {
            lines << SongView::tr("…");
            break;
        }
    }
    if (lines.isEmpty())
        QToolTip::hideText();
    else
        QToolTip::showText(event->globalPosition().toPoint(), lines.join(QStringLiteral("\n")),
                           this);
}

} // namespace songview
