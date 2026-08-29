#include "ui/activity/trackactivityrender.h"

#include "ui/theme/color_math.h"

#include <algorithm>

namespace track_activity_render {
namespace {

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

} // namespace

int physicalHeight(const State &state, float channelIntensity, int meterHeight,
                   qreal devicePixelRatio)
{
    const float paintedIntensity =
        state.playing ? std::min(channelIntensity, state.maximumIntensity) : channelIntensity;
    return qRound(double(paintedIntensity) * meterHeight * devicePixelRatio);
}

RenderKey renderKey(const State &state, int meterHeight, qreal devicePixelRatio)
{
    return {physicalHeight(state, state.intensity.left, meterHeight, devicePixelRatio),
            physicalHeight(state, state.intensity.right, meterHeight, devicePixelRatio),
            state.playing};
}

qreal snappedHeight(const State &state, float channelIntensity, int meterHeight,
                    qreal devicePixelRatio)
{
    return qreal(physicalHeight(state, channelIntensity, meterHeight, devicePixelRatio)) /
           devicePixelRatio;
}

Colors colors(const QColor &identityColor)
{
    const auto identity = themes::oklchFromColor(identityColor);
    auto dimmedIdentity = identity;
    dimmedIdentity.lightness = std::max(0.0, dimmedIdentity.lightness - 0.18);
    return {gamutMappedOklch(dimmedIdentity), gamutMappedOklch(identity)};
}

} // namespace track_activity_render
