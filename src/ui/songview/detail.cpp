#include "ui/songview/detail.h"
#include "ui/keymap.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

#include <array>
#include <climits>
#include <cmath>
#include <optional>

namespace songview::detail {

qreal logicalPhysicalPixel(qreal dpr)
{
    return dpr > 0.0 ? 1.0 / dpr : 1.0;
}

QPoint wheelDelta(const QWheelEvent *event)
{
    const QPoint pixelDelta = event->pixelDelta();
    return pixelDelta.isNull() ? event->angleDelta() : pixelDelta;
}

double wheelAngleUnits(const QWheelEvent *event)
{
    if (event->phase() == Qt::ScrollMomentum)
        return 0.0;
    const QPoint delta = wheelDelta(event);
    return double(delta.y()) * (event->pixelDelta().isNull() ? 1.0 : 5.0);
}

double cursorAnchoredScroll(double anchor, double oldScale, double oldScroll, double newScale)
{
    const double content = (anchor + oldScroll) / oldScale;
    return content * newScale - anchor;
}
uint32_t usedTrackMask(const MidiTimeline *timeline) noexcept
{
    if (!timeline)
        return 0;
    uint32_t mask = 0;
    for (int track = 0; track < 16; ++track) {
        if (timeline->tracks[track].used)
            mask |= 1u << track;
    }
    return mask;
}

// Resize hit-zone reach at a note's left/right edges (rollcheck probes
// 2.8 DIPs inside the ends, so the zone must reach past that). Outside the
// note the full reach always applies; inside, both zones shrink to leave the
// resolved minimum move width between them so short notes keep a grabbable
// middle for move drags.
qreal edgeGripInnerReach(const QRectF &noteRect, qreal minimumMoveWidth, qreal edgeGripReach)
{
    return std::clamp((noteRect.width() - minimumMoveWidth) / 2.0, 0.0, edgeGripReach);
}

bool isBlackKey(int key)
{
    switch (key % 12) {
    case 1:
    case 3:
    case 6:
    case 8:
    case 10:
        return true;
    default:
        return false;
    }
}

QString keyName(int key)
{
    static const char *const names[] = {"C",  "C#", "D",  "D#", "E",  "F",
                                        "F#", "G",  "G#", "A",  "A#", "B"};
    return QStringLiteral("%1%2").arg(QLatin1String(names[key % 12])).arg(key / 12 - 1);
}

QString contextShortcutText(const QString &commandId)
{
    const auto shortcut = keymap::Registry::instance().bindings(commandId).value(0);
    return shortcut.isEmpty() ? QString() : shortcut.toString(QKeySequence::NativeText);
}

QString timeSigLabel(int numerator, int denomPow2)
{
    return QStringLiteral("%1/%2").arg(numerator).arg(1 << std::min(denomPow2, 6));
}

QColor loopEdge()
{
    return themes::color(themes::Role::song_view_loop_marker);
}

QColor pianoRollAccidentalLaneColor()
{
    return themes::color(themes::Role::song_view_piano_roll_accidental_lane);
}
QColor pianoRollScaleHighlightColor()
{
    auto color = themes::color(themes::Role::song_view_scale_highlight);
    color.setAlpha(51);
    return color;
}
QColor trackHeaderAlsoSelectedColor()
{
    auto color = themes::color(themes::Role::song_view_track_header_selection);
    color.setAlpha(99);
    return color;
}
// Perceptual blend for receding a color into its backdrop (silent-in-game
// track headers): t = 0 keeps `color`, t = 1 lands on `backdrop`.
QColor mixTowardOklabImpl(const QColor &color, const QColor &backdrop, double t)
{
    const themes::Oklab from = themes::oklabFromColor(color);
    const themes::Oklab to = themes::oklabFromColor(backdrop);
    return themes::colorFromOklab({from.lightness + (to.lightness - from.lightness) * t,
                                   from.a + (to.a - from.a) * t, from.b + (to.b - from.b) * t});
}

std::size_t trackIdentityIndex(int track)
{
    const auto count = static_cast<int>(themes::trackIdentityColorCount);
    return static_cast<std::size_t>(((track % count) + count) % count);
}

// The higher-contrast piano-key color over a note fill.
QColor contrastingTextColor(const QColor &backdrop)
{
    const auto light = themes::color(themes::Role::song_view_piano_keyboard_natural_key);
    const auto dark = themes::color(themes::Role::song_view_piano_keyboard_black_key);
    return themes::contrastRatio(backdrop, light) >= themes::contrastRatio(backdrop, dark) ? light
                                                                                           : dark;
}

// Ghost notes (unselected tracks) mix 24% of their track identity into the
// row background in OKLab. Cap only the lightness offset so bright identities
// stay equally recessive on light and dark themes.
QColor ghostNoteColor(int track, bool accidentalRow)
{
    static std::array<std::array<QColor, 2>, themes::trackIdentityColorCount> colors{};
    static std::optional<QRgb> backgroundKeys[2]{};

    const auto &naturalBackground = themes::color(themes::Role::song_view_piano_roll_background);
    const auto &accidentalBackground =
        themes::color(themes::Role::song_view_piano_roll_accidental_lane);
    if (!backgroundKeys[0] || !backgroundKeys[1] ||
        *backgroundKeys[0] != naturalBackground.rgba() ||
        *backgroundKeys[1] != accidentalBackground.rgba()) {
        backgroundKeys[0] = naturalBackground.rgba();
        backgroundKeys[1] = accidentalBackground.rgba();
        const themes::Oklab backgrounds[2] = {themes::oklabFromColor(naturalBackground),
                                              themes::oklabFromColor(accidentalBackground)};
        constexpr double kIdentityWeight = 60.0 / 255.0;
        constexpr double kMaxLightnessOffset = 0.055;
        for (std::size_t i = 0; i < colors.size(); ++i) {
            const auto identity = themes::oklabFromColor(themes::trackIdentityColor(i));
            for (int background = 0; background < 2; ++background) {
                const double lightnessOffset = std::clamp(
                    (identity.lightness - backgrounds[background].lightness) * kIdentityWeight,
                    -kMaxLightnessOffset, kMaxLightnessOffset);
                colors[i][background] = themes::colorFromOklab(
                    {backgrounds[background].lightness + lightnessOffset,
                     backgrounds[background].a +
                         (identity.a - backgrounds[background].a) * kIdentityWeight,
                     backgrounds[background].b +
                         (identity.b - backgrounds[background].b) * kIdentityWeight});
            }
        }
    }
    return colors[trackIdentityIndex(track)][accidentalRow ? 1 : 0];
}

// Subdivision level of a sub-beat grid tick (relative to its segment's
// start): 1 = the beat's first split (half beat, or a third in triplet
// feel), 2 = the next, 3 = finer. Cosmetic only (drives the line fade).
int subGridLevel(uint64_t relTick, uint64_t beatTicks, bool triplet)
{
    if (relTick % std::max<uint64_t>(1, beatTicks / (triplet ? 3 : 2)) == 0)
        return 1;
    if (relTick % std::max<uint64_t>(1, beatTicks / (triplet ? 6 : 4)) == 0)
        return 2;
    return 3;
}

// Strictly below 2^64, where double -> uint64 conversion is defined; the
// largest representable double below it (2^64 - 2^11) still converts
// exactly, and anything at or above the ceiling is out of tick range.
constexpr double kUint64TickCeiling = 0x1p64;

TickRange tickRange(const double begin, const double end) noexcept
{
    if (!std::isfinite(begin) || !std::isfinite(end))
        return {};
    const double first = std::max(0.0, begin);
    if (end <= first || end >= kUint64TickCeiling)
        return {};
    return {uint64_t(first), uint64_t(end)};
}

QColor gridLineColor(int alpha)
{
    auto color = themes::color(themes::Role::song_view_grid);
    color.setAlpha((color.alpha() * alpha + 127) / 255);
    return color;
}

} // namespace songview::detail

namespace songview {
using namespace detail;

QColor mixTowardOklab(const QColor &color, const QColor &backdrop, double t)
{
    return mixTowardOklabImpl(color, backdrop, t);
}

} // namespace songview
