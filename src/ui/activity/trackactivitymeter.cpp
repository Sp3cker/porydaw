#include "trackactivitymeter.h"

#include "ui/layout.h"
#include "ui/theme/color_math.h"

#include <QPaintEvent>
#include <QPainter>
#include <QRectF>
#include <QtGlobal>

#include <algorithm>
#include <cmath>
#include <utility>

namespace {

double interpolate(double from, double to, double amount)
{
    return from + (to - from) * amount;
}

QColor gamutMappedOklch(themes::Oklch color, int alpha = 255)
{
    for (auto attempt = 0; attempt < 12; ++attempt) {
        auto result = themes::colorFromOklch(color);
        if (result.isValid()) {
            result.setAlpha(alpha);
            return result;
        }
        color.chroma *= 0.85;
    }
    return themes::colorFromOklab({color.lightness, 0.0, 0.0}, alpha);
}

int physicalHeight(const TrackActivityMeter::State &state, float channelIntensity, int widgetHeight,
                   qreal devicePixelRatio)
{
    const float paintedIntensity =
        state.playing ? std::min(channelIntensity, state.maximumIntensity) : channelIntensity;
    return qRound(double(paintedIntensity) * widgetHeight * devicePixelRatio);
}

struct RenderKey {
    int leftHeight;
    int rightHeight;
    bool playing;

    bool operator==(const RenderKey &) const = default;
};

RenderKey renderKey(const TrackActivityMeter::State &state, int widgetHeight,
                    qreal devicePixelRatio)
{
    return {physicalHeight(state, state.intensity.left, widgetHeight, devicePixelRatio),
            physicalHeight(state, state.intensity.right, widgetHeight, devicePixelRatio),
            state.playing};
}

void paintActivityLight(QPainter &p, const TrackActivityMeter::State &state, const QRectF &barRect,
                        const QColor &identityColor)
{
    const auto identity = themes::oklchFromColor(identityColor);
    auto dimmedIdentity = identity;
    dimmedIdentity.lightness = std::max(0.0, dimmedIdentity.lightness - 0.18);
    p.fillRect(barRect, gamutMappedOklch(dimmedIdentity));

    const auto split = barRect.left() + barRect.width() * 0.5;
    const QRectF leftRect(barRect.left(), barRect.top(), split - barRect.left(), barRect.height());
    const QRectF rightRect(split, barRect.top(), barRect.right() - split, barRect.height());
    const auto paintMeter = [&](QRectF meterRect, float channelIntensity) {
        const auto current = double(channelIntensity);
        const auto activity =
            state.playing ? std::min(current, double(state.maximumIntensity)) : current;
        if (activity <= 0.0)
            return;
        meterRect.setTop(barRect.bottom() - barRect.height() * activity);
        p.fillRect(meterRect, gamutMappedOklch(identity));
    };
    paintMeter(leftRect, state.intensity.left);
    paintMeter(rightRect, state.intensity.right);
}

} // namespace

TrackActivityMeter::TrackActivityMeter(QColor identityColor, QWidget *parent)
    : QWidget(parent)
    , m_identityColor(std::move(identityColor))
{
    setObjectName(QStringLiteral("trackActivityMeter"));
    setAttribute(Qt::WA_OpaquePaintEvent);
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setFixedWidth(layout::space(layout::Space::One));
}

void TrackActivityMeter::setState(State state)
{
    const int widgetHeight = height();
    const qreal devicePixelRatio = devicePixelRatioF();
    const RenderKey oldKey = renderKey(m_state, widgetHeight, devicePixelRatio);
    const RenderKey newKey = renderKey(state, widgetHeight, devicePixelRatio);

    m_state = state;
    if (oldKey != newKey) {
        update();
    }
}

void TrackActivityMeter::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.setClipRect(rect());
    paintActivityLight(painter, m_state, QRectF(rect()), m_identityColor);
}
