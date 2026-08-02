#include "trackidentitycolors.h"

#include <QStringView>

#include <array>

namespace themes {
namespace {

using TrackIdentityPalette = std::array<QColor, trackIdentityColorCount>;

QColor colorFromHex(std::string_view hex)
{
    return QColor(QLatin1String(hex.data(), static_cast<int>(hex.size())));
}

const TrackIdentityPalette &resolvedTrackIdentityPalette()
{
    static const auto palette = [] {
        TrackIdentityPalette result;
        for (std::size_t index = 0; index < trackIdentityColorCount; ++index)
            result[index] = colorFromHex(track_identity_colors::fills[index]);
        return result;
    }();
    return palette;
}

} // namespace

const QColor &trackIdentityColor(std::size_t index)
{
    return resolvedTrackIdentityPalette().at(index);
}

} // namespace themes
