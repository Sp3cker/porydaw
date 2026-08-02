#pragma once

#include <QColor>

#include <array>
#include <cstddef>
#include <string_view>

namespace themes::track_identity_colors {

/// These fills identify tracks in notes, automation, events, and headers.
/// Keeping them theme-independent preserves that identity while themes change.
inline constexpr auto fills = std::array{
    std::string_view{"#CD5454"}, std::string_view{"#54CD77"}, std::string_view{"#9B54CD"},
    std::string_view{"#CDBD54"}, std::string_view{"#54B9CD"}, std::string_view{"#CD5497"},
    std::string_view{"#73CD54"}, std::string_view{"#5854CD"}, std::string_view{"#CD7D54"},
    std::string_view{"#54CD9F"}, std::string_view{"#C354CD"}, std::string_view{"#B5CD54"},
    std::string_view{"#5491CD"}, std::string_view{"#CD546F"}, std::string_view{"#54CD5E"},
    std::string_view{"#8154CD"},
};

} // namespace themes::track_identity_colors

namespace themes {

inline constexpr std::size_t trackIdentityColorCount = track_identity_colors::fills.size();

/// Returns the shared fill for a track identity index.
const QColor &trackIdentityColor(std::size_t index);

} // namespace themes
