// ---------------------------------------------------------------- OtherStrip

#include "ui/songview/otherstrip.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

#include <QStringList>
#include <QVariant>

#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

OtherStrip::Geometry OtherStrip::Geometry::resolve()
{
    return {lyt::fontPx(1.0 / 3.0), lyt::fontPx(1.0 / 3.0), lyt::fontPx(5.0 / 12.0)};
}

OtherStrip::OtherStrip(SongView &owner, QObject *parent)
    : QObject(parent)
    , m_owner(owner)
    , m_camera(owner.camera())
    , m_geometry(Geometry::resolve())
{
    syncToolTipAppearance();
}

void OtherStrip::requestQuickUpdate()
{
    m_owner.requestTimelineQuickUpdate(TimelineQuickDirty::OtherEvents);
}

void OtherStrip::attachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(!m_inputHost || m_inputHost == &host);
    m_inputHost = &host;
    syncToolTipAppearance();
}

void OtherStrip::detachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(m_inputHost == &host);
    if (m_inputHost != &host)
        return;
    clearToolTip();
    m_inputHost = nullptr;
}

bool OtherStrip::pointerMove(const TimelinePointerInput &input)
{
    const MidiTimeline *timeline = m_owner.timeline();
    if (!m_inputHost || !timeline || input.surface != TimelineInputSurface::Plot) {
        clearToolTip();
        return true;
    }
    QStringList lines;
    for (const StripItem &item : m_owner.model().strip) {
        const qreal x = m_camera.displayX(double(item.tick), 0.0, m_inputHost->devicePixelRatio());
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
        clearToolTip();
    else
        updateToolTip(lines.join(QStringLiteral("\n")), input.position);
    return true;
}

void OtherStrip::pointerLeave()
{
    clearToolTip();
}

void OtherStrip::inputCancelled(TimelineInputCancelReason)
{
    clearToolTip();
}

void OtherStrip::hostAppearanceChanged()
{
    if (!m_inputHost)
        return;
    syncToolTipAppearance();
}

void OtherStrip::updateToolTip(const QString &text, const QPointF &position)
{
    if (text.isEmpty()) {
        clearToolTip();
        return;
    }
    if (m_toolTipVisible && m_toolTipText == text && m_toolTipPosition == position)
        return;
    m_toolTipVisible = true;
    m_toolTipText = text;
    m_toolTipPosition = position;
    emit toolTipChanged();
}

void OtherStrip::clearToolTip()
{
    if (!m_toolTipVisible && m_toolTipText.isEmpty() && m_toolTipPosition.isNull())
        return;
    m_toolTipVisible = false;
    m_toolTipText.clear();
    m_toolTipPosition = {};
    emit toolTipChanged();
}

void OtherStrip::syncToolTipAppearance()
{
    QVariantMap next;
    next.insert(QStringLiteral("toolTipBackground"),
                themes::color(themes::Role::tooltip_background));
    next.insert(QStringLiteral("toolTipText"), themes::color(themes::Role::tooltip_text));
    next.insert(QStringLiteral("toolTipOutline"), themes::color(themes::Role::tooltip_outline));
    if (next == m_toolTipAppearance)
        return;
    m_toolTipAppearance = std::move(next);
    emit toolTipAppearanceChanged();
}

} // namespace songview
