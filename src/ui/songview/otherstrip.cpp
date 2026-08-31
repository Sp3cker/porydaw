// ---------------------------------------------------------------- OtherStrip

#include "ui/songview/otherstrip.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/pianorollquick.h"

#include <QEvent>
#include <QFontMetrics>
#include <QMouseEvent>
#include <QStringList>
#include <QToolTip>

#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

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
    requestQuickUpdate();
}

OtherStrip::OtherStrip(SongView *sv)
    : TimelineSurface(sv)
    , m_sv(sv)
    , m_geometry(Geometry::resolve())
{
    setObjectName(QStringLiteral("otherEventsStrip"));
    setAutoFillBackground(false);
    refreshGeometry();
    setMouseTracking(true);
}

void OtherStrip::paintContent(QPainter &) {}

void OtherStrip::requestQuickUpdate()
{
    m_sv->requestTimelineQuickUpdate(TimelineQuickDirty::OtherEvents);
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
