#include "ui/songview/detail.h"
#include "ui/keymap.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QKeySequence>
#include <QLabel>
#include <QLineF>
#include <QPen>
#include <QSpinBox>
#include <QVBoxLayout>
#include <QVector>
#include <array>
#include <climits>
#include <cmath>
#include <optional>

namespace songview::detail {

qreal logicalPhysicalPixel(qreal dpr)
{
    return dpr > 0.0 ? 1.0 / dpr : 1.0;
}

int scrollUnits(double dip)
{
    // Negative units carry the pre-roll pad (scroll positions left of
    // tick 0) into the scrollbar's range.
    const double units = std::clamp(dip * kScrollUnitsPerDip, double(INT_MIN), double(INT_MAX));
    return int(std::lround(units));
}

double scrollDips(int units)
{
    return double(units) / kScrollUnitsPerDip;
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

QString contextActionText(const QString &text, const QString &commandId)
{
    const auto shortcut = keymap::Registry::instance().bindings(commandId).value(0);
    if (shortcut.isEmpty())
        return text;
    return text + u'\t' + shortcut.toString(QKeySequence::NativeText);
}

QString timeSigLabel(int numerator, int denomPow2)
{
    return QStringLiteral("%1/%2").arg(numerator).arg(1 << std::min(denomPow2, 6));
}

// Modal numerator/denominator editor for a ruler time-signature marker.
bool askTimeSignature(QWidget *parent, int *numerator, int *denomPow2)
{
    QDialog dlg(parent);
    dlg.setWindowTitle(SongView::tr("Time Signature"));
    auto *num = new QSpinBox(&dlg);
    num->setRange(1, 32);
    num->setValue(std::clamp(*numerator, 1, 32));
    auto *den = new QComboBox(&dlg);
    for (int p = 0; p <= 5; p++)
        den->addItem(QString::number(1 << p), p);
    den->setCurrentIndex(std::clamp(*denomPow2, 0, 5));
    auto *row = new QHBoxLayout;
    row->addWidget(num);
    row->addWidget(new QLabel(QStringLiteral("/"), &dlg));
    row->addWidget(den);
    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dlg);
    QObject::connect(buttons, &QDialogButtonBox::accepted, &dlg, &QDialog::accept);
    QObject::connect(buttons, &QDialogButtonBox::rejected, &dlg, &QDialog::reject);
    auto *layout = new QVBoxLayout(&dlg);
    layout->addLayout(row);
    layout->addWidget(buttons);
    if (dlg.exec() != QDialog::Accepted)
        return false;
    *numerator = num->value();
    *denomPow2 = den->currentData().toInt();
    return true;
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

QColor gridLineColor(int alpha)
{
    auto color = themes::color(themes::Role::song_view_grid);
    color.setAlpha((color.alpha() * alpha + 127) / 255);
    return color;
}

// Vertical bar/beat grid lines inside rect, with zoom-adaptive sub-beat
// lines at the snap grid's positions fading lighter per subdivision level.
// Lines are batched per level so each color is a single drawLines() call.
void drawGrid(QPainter &p, const SongView *sv, const QRect &rect, qreal origin,
              int timelineDetailMinimumPixelsPerBeat, int gridLineStrokeWidth)
{
    const qreal dpr = p.device()->devicePixelRatioF();
    const qreal physicalPixel = logicalPhysicalPixel(dpr);
    const qreal roundingMargin = physicalPixel / 2.0;
    const double t0 = std::max(0.0, sv->tickAtContentX(rect.left() - origin - roundingMargin));
    const double t1 =
        sv->tickAtContentX(rect.x() + rect.width() - physicalPixel - origin + roundingMargin) + 1;
    const bool drawBeats = sv->pxPerBeat() >= timelineDetailMinimumPixelsPerBeat;
    // Batches 0-2 hold sub-grid levels 1-3 (fading lighter), 3 beats, 4
    // finest-grid beats, 5 bars; painted in that order so beats and bars
    // land on top.
    const std::array<QColor, 6> colors = {gridLineColor(125), gridLineColor(100), gridLineColor(75),
                                          gridLineColor(160), gridLineColor(200), gridLineColor()};
    std::array<QVector<QLineF>, 6> batches;
    forEachSubGridLine(sv, t0, t1, timelineDetailMinimumPixelsPerBeat,
                       [&](uint64_t tick, int level) {
                           const qreal x = sv->displayX(double(tick), origin, dpr);
                           batches[level - 1].append(QLineF(x, rect.top(), x, rect.bottom()));
                       });
    sv->forEachGridLine(uint64_t(t0), uint64_t(t1), [&](uint64_t tick, bool isBar, int, int) {
        if (!isBar && !drawBeats)
            return;
        const qreal x = sv->displayX(double(tick), origin, dpr);
        const bool atFinestGrid = sv->document() && sv->gridTicksAt(tick) == sv->fineGridTicks();
        batches[isBar ? 5 : atFinestGrid ? 4 : 3].append(QLineF(x, rect.top(), x, rect.bottom()));
    });
    for (size_t i = 0; i < batches.size(); ++i) {
        if (batches[i].isEmpty())
            continue;
        // Grid lines use the resolved physical width on every display scale.
        p.setPen(QPen(colors[i], gridLineStrokeWidth * physicalPixel));
        p.drawLines(batches[i]);
    }
}

} // namespace songview::detail

namespace songview {
using namespace detail;

QColor mixTowardOklab(const QColor &color, const QColor &backdrop, double t)
{
    return mixTowardOklabImpl(color, backdrop, t);
}

} // namespace songview
