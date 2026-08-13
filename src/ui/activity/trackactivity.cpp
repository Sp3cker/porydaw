#include "trackactivity.h"

#include "ui/theme/color_math.h"

#include <QColor>
#include <QPainter>
#include <QRectF>

#include <algorithm>
#include <cmath>

namespace {
constexpr auto kAttackSeconds = 0.015f;
constexpr auto kReleaseSeconds = 0.050f;
constexpr auto kVisibleFloor = 0.002f;

double interpolate(double from, double to, double amount)
{
    return from + (to - from) * amount;
}

QColor gamutMappedOklch(themes::Oklch color, int alpha = 255)
{
    for (auto attempt = 0; attempt < 12; attempt++) {
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

void TrackActivity::advance(const std::array<uint8_t, MAX_TRACKS> &levels, float elapsedSeconds)
{
    const auto elapsed = std::max(0.0f, elapsedSeconds);
    const auto attackAmount = 1.0f - std::exp(-elapsed / kAttackSeconds);
    const auto release = std::exp(-elapsed / kReleaseSeconds);
    for (auto track = 0; track < MAX_TRACKS; track++) {
        const auto target = float(levels[size_t(track)]) / 255.0f;
        auto &intensity = m_intensities[size_t(track)];
        intensity = target > intensity ? intensity + (target - intensity) * attackAmount
                                       : intensity * release;
        if (intensity < kVisibleFloor)
            intensity = 0.0f;
    }
}

void TrackActivity::reset()
{
    m_intensities.fill(0.0f);
}

float TrackActivity::intensity(int track) const
{
    if (track < 0 || track >= MAX_TRACKS)
        return 0.0f;
    return m_intensities[size_t(track)];
}

void TrackActivity::paintLight(QPainter &p, int track, const QRectF &barRect,
                               const QColor &identityColor, float maximumIntensity) const
{
    const auto identity = themes::oklchFromColor(identityColor);
    const auto activity = std::min(double(intensity(track)), double(maximumIntensity));
    const auto perceptualActivity = std::pow(activity, 0.55);
    auto emitter = identity;
    if (activity > 0.0) {
        constexpr auto pi = 3.14159265358979323846;
        const auto warmth =
            std::clamp(std::cos((identity.hue - 75.0) * pi / 180.0) * 0.5 + 0.5, 0.0, 1.0);
        emitter.hue = identity.hue;
        const auto peakLightness = std::min(0.90, identity.lightness + 0.22 + 0.08 * warmth);
        emitter.lightness = interpolate(identity.lightness, peakLightness, perceptualActivity);
        const auto peakChroma = identity.chroma * 0.42;
        emitter.chroma = interpolate(identity.chroma, peakChroma, perceptualActivity);
        if (emitter.lightness > 0.74) {
            const auto compression = std::clamp((emitter.lightness - 0.74) / 0.16, 0.0, 1.0);
            emitter.chroma *= interpolate(1.0, 0.50, compression);
        }
    }
    p.fillRect(barRect, gamutMappedOklch(emitter));
}
