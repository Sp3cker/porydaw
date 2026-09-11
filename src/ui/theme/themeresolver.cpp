#include "themeresolver.h"
#include "color_math.h"
#include "presetcolors.h"

#include <array>
#include <cmath>

namespace themes {
namespace {

QColor mixColors(const QColor &first, const QColor &second, double firstWeight)
{
    const auto secondWeight = 1.0 - firstWeight;
    const auto channel = [firstWeight, secondWeight](int firstValue, int secondValue) {
        const auto value = firstValue * firstWeight + secondValue * secondWeight;
        return static_cast<int>(std::floor(value + 0.5));
    };
    return QColor::fromRgb(channel(first.red(), second.red()),
                           channel(first.green(), second.green()),
                           channel(first.blue(), second.blue()));
}

QColor colorFromHex(preset_colors::HexColor hex)
{
    return QColor(QLatin1String(hex.data(), static_cast<int>(hex.size())));
}

Theme resolvePreset(const preset_colors::PresetColors &colors)
{
    Theme theme;
    for (std::size_t index = 0; index < roleCount; ++index) {
        const auto role = static_cast<Role>(index);
        theme.colors[index] = colorFromHex(colors.color(role));
    }
    return theme;
}

Theme resolveDarkPreset(const preset_colors::PresetColors &colors)
{
    auto theme = resolvePreset(colors);
    // The pale foreground is unreadable on the light active fills. Reuse the
    // dark resting-button surface as their foreground.
    const auto activeText = theme.color(Role::button_background);
    constexpr auto activeTextRoles = std::array{
        Role::selection_text,          Role::tab_selected_text,
        Role::button_pressed_text,     Role::menu_item_pressed_text,
        Role::item_selected_text,      Role::header_checked_text,
        Role::track_mute_checked_text, Role::song_view_track_header_selection_text,
    };
    for (const auto role : activeTextRoles)
        theme.color(role) = activeText;
    return theme;
}

} // namespace

Theme withGridLineContrast(Theme theme, int contrast)
{
    Q_ASSERT(contrast >= 0 && contrast <= 100);
    if (contrast == 50)
        return theme;
    const auto grid = theme.color(Role::song_view_grid);
    const auto background = theme.color(Role::song_view_piano_roll_background);
    if (contrast < 50) {
        auto adjusted = mixColors(grid, background, static_cast<double>(contrast) / 50.0);
        adjusted.setAlpha((grid.alpha() * contrast + 25) / 50);
        theme.color(Role::song_view_grid) = adjusted;
        return theme;
    }
    const auto endpoint = relativeLuminance(grid) <= relativeLuminance(background)
                              ? QColor::fromRgb(0, 0, 0)
                              : QColor::fromRgb(255, 255, 255);
    const auto endpointWeight = static_cast<double>(contrast - 50) / 50.0;
    auto adjusted = mixColors(endpoint, grid, endpointWeight);
    adjusted.setAlpha(grid.alpha() + ((255 - grid.alpha()) * (contrast - 50) + 25) / 50);
    theme.color(Role::song_view_grid) = adjusted;
    return theme;
}

Theme vanilla()
{
    return resolvePreset(preset_colors::vanilla);
}

Theme darkNeutralHigh()
{
    return resolveDarkPreset(preset_colors::darkNeutralHigh);
}

Theme immaterial()
{
    return resolveDarkPreset(preset_colors::immaterial);
}

} // namespace themes
