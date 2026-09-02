// ---------------------------------------------------------------- OtherStrip

#include "ui/songview/otherstrip.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QStringList>
#include <QToolTip>

#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

OtherStrip::Geometry OtherStrip::Geometry::resolve()
{
    return {lyt::fontPx(1.0 / 3.0), lyt::fontPx(1.0 / 3.0), lyt::fontPx(5.0 / 12.0)};
}

void OtherStrip::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    requestQuickUpdate();
}

OtherStrip::OtherStrip(SongView &owner, QObject *parent)
    : QObject(parent)
    , m_owner(owner)
    , m_geometry(Geometry::resolve())
{}

void OtherStrip::requestQuickUpdate()
{
    m_owner.requestTimelineQuickUpdate(TimelineQuickDirty::OtherEvents);
}

void OtherStrip::attachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(!m_inputHost || m_inputHost == &host);
    m_inputHost = &host;
}

void OtherStrip::detachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(m_inputHost == &host);
    if (m_inputHost != &host)
        return;
    QToolTip::hideText();
    m_inputHost = nullptr;
}

bool OtherStrip::pointerMove(const TimelinePointerInput &input)
{
    const MidiTimeline *timeline = m_owner.timeline();
    const qreal plotOrigin = m_owner.timelinePlotOrigin();
    if (!m_inputHost || !timeline || input.position.x() < plotOrigin) {
        QToolTip::hideText();
        return true;
    }
    QStringList lines;
    for (const StripItem &item : m_owner.model().strip) {
        const qreal x =
            m_owner.displayX(double(item.tick), plotOrigin, m_inputHost->devicePixelRatio());
        if (std::abs(x - input.position.x()) > m_geometry.otherEventHitSlop)
            continue;
        const double seconds = double(timeline->sampleForTick(item.tick)) / timeline->sampleRate;
        const QString where =
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
        QToolTip::showText(input.globalPosition.toPoint(), lines.join(QStringLiteral("\n")),
                           &m_owner);
    return true;
}

void OtherStrip::pointerLeave()
{
    QToolTip::hideText();
}

void OtherStrip::inputCancelled(TimelineInputCancelReason)
{
    QToolTip::hideText();
}

void OtherStrip::hostAppearanceChanged()
{
    refreshGeometry();
}

} // namespace songview
