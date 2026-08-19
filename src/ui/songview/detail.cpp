#include "ui/songview/detail.h"
#include "ui/layout.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineF>
#include <QPen>
#include <QSpinBox>
#include <QVBoxLayout>
#include <QVector>
#include <array>
#include <climits>
#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

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
qreal velocityHandlePointerHitPadding(qreal noteHeight, qreal physicalPixel)
{
    const auto physicalNoteHeight = qRound(noteHeight / physicalPixel);
    const auto paddingPixels = std::clamp(physicalNoteHeight / 6, 2, 4);
    return paddingPixels * physicalPixel;
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

bool resolveFoldDestinations(porydaw_scale::ScaleId scaleId, int scaleRoot,
                             std::vector<DocNote> &notes, int degreeDelta,
                             std::vector<uint8_t> &destinations)
{
    if (notes.empty() || degreeDelta == 0)
        return false;
    std::sort(notes.begin(), notes.end(),
              [](const DocNote &a, const DocNote &b) { return a.key < b.key; });
    std::vector<uint8_t> sources(notes.size());
    std::vector<int> degrees(notes.size(), degreeDelta);
    for (size_t i = 0; i < notes.size(); i++)
        sources[i] = notes[i].key;
    destinations.resize(notes.size());
    return porydaw_scale::resolveDiatonicDestinations(scaleId, scaleRoot, std::span(sources),
                                                      std::span(degrees), std::span(destinations));
}

QString keyName(int key)
{
    static const char *const names[] = {"C",  "C#", "D",  "D#", "E",  "F",
                                        "F#", "G",  "G#", "A",  "A#", "B"};
    return QStringLiteral("%1%2").arg(QLatin1String(names[key % 12])).arg(key / 12 - 1);
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

// SongView paint paths request canvas-specific roles directly, making each
// visible element traceable without knowing a shared theme alias.
QLinearGradient loopGlow(qreal edgeX, qreal transparentX)
{
    auto color = themes::color(themes::Role::song_view_loop_marker);
    auto transparent = color;
    color.setAlpha(150);
    transparent.setAlpha(0);
    QLinearGradient gradient(edgeX, 0, transparentX, 0);
    gradient.setColorAt(0.0, color);
    color.setAlpha(18);
    gradient.setColorAt(0.2, color);
    gradient.setColorAt(1.0, transparent);
    return gradient;
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
    const auto &identity = themes::trackIdentityColor(trackIdentityIndex(track));
    const auto background =
        themes::color(accidentalRow ? themes::Role::song_view_piano_roll_accidental_lane
                                    : themes::Role::song_view_piano_roll_background);
    const auto identityLab = themes::oklabFromColor(identity);
    const auto backgroundLab = themes::oklabFromColor(background);
    constexpr auto kIdentityWeight = 60.0 / 255.0;
    constexpr auto kMaxLightnessOffset = 0.055;
    const auto lightnessOffset =
        std::clamp((identityLab.lightness - backgroundLab.lightness) * kIdentityWeight,
                   -kMaxLightnessOffset, kMaxLightnessOffset);
    return themes::colorFromOklab(
        {backgroundLab.lightness + lightnessOffset,
         backgroundLab.a + (identityLab.a - backgroundLab.a) * kIdentityWeight,
         backgroundLab.b + (identityLab.b - backgroundLab.b) * kIdentityWeight});
}

// Draw the loop-region band across rect. x positions are
// computed with origin = local x of timeline tick 0's content position.
// timeSelCovered says whether this widget (or row) is inside the active time
// selection's scope, so the selection band tints exactly the covered content.
void drawOverlays(QPainter &p, const SongView *sv, const QRect &rect, qreal origin,
                  bool timeSelCovered, bool loopMarkersVisible)
{
    const MidiTimeline *tl = sv->timeline();
    if (!tl)
        return;

    const qreal dpr = p.device()->devicePixelRatioF();
    const auto &tsel = sv->selectionModel().timeSelection();
    if (timeSelCovered && tsel.active()) {
        const qreal x0 = sv->displayX(double(tsel.startTick), origin, dpr);
        const qreal x1 = sv->displayX(double(tsel.endTick), origin, dpr);
        if (x1 > rect.left() && x0 < rect.right()) {
            QColor fill = themes::color(themes::Role::song_view_selection_fill);
            fill.setAlpha(30);
            const QRectF selectionRect(x0, rect.top(), x1 - x0, rect.height());
            p.fillRect(selectionRect.intersected(QRectF(rect)), fill);
            p.setPen(
                QPen(themes::color(themes::Role::song_view_selection_edge), lyt::singlePixel()));
            p.drawLine(QLineF(x0, rect.top(), x0, rect.bottom()));
            p.drawLine(QLineF(x1, rect.top(), x1, rect.bottom()));
        }
    }
    if (loopMarkersVisible && (tl->loopStartTick != UINT64_MAX || tl->loopEndTick != UINT64_MAX)) {
        const bool hasStart = tl->loopStartTick != UINT64_MAX;
        const bool hasEnd = tl->loopEndTick != UINT64_MAX;
        const qreal x0 =
            hasStart ? sv->displayX(double(tl->loopStartTick), origin, dpr) : rect.left();
        const qreal x1 = hasEnd ? sv->displayX(double(tl->loopEndTick), origin, dpr) : rect.right();
        if (x1 > rect.left() && x0 < rect.right()) {
            const qreal glowWidth = std::min<qreal>(lyt::space(Space::Eight), x1 - x0);
            if (hasStart && glowWidth > 0) {
                const QRectF glowRect(x0, rect.top(), glowWidth, rect.height());
                p.fillRect(glowRect.intersected(QRectF(rect)), loopGlow(x0, x0 + glowWidth));
            }
            if (hasEnd && glowWidth > 0) {
                const QRectF glowRect(x1 - glowWidth, rect.top(), glowWidth, rect.height());
                p.fillRect(glowRect.intersected(QRectF(rect)), loopGlow(x1, x1 - glowWidth));
            }
            p.setPen(QPen(loopEdge(), lyt::singlePixel()));
            if (hasStart)
                p.drawLine(QLineF(x0, rect.top(), x0, rect.bottom()));
            if (hasEnd)
                p.drawLine(QLineF(x1, rect.top(), x1, rect.bottom()));
        }
    }
    const qreal cursorX = sv->displayX(double(sv->editCursorTick()), origin, dpr);
    if (cursorX >= rect.left() && cursorX <= rect.right()) {
        p.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), lyt::singlePixel(),
                      Qt::DashLine));
        p.drawLine(QLineF(cursorX, rect.top(), cursorX, rect.bottom()));
    }
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

// Flat fill over the camera's pre-roll pad (the scrollable dead space left
// of tick 0). Opaque and stripe-free so it reads as "outside the song";
// blending the surface's own background toward the grid ink dims it in
// light themes and lifts it in dark ones. Painted before drawGrid so the
// tick-0 bar line stays a crisp boundary on top.
void drawPreRoll(QPainter &p, const SongView *sv, const QRect &rect, qreal origin,
                 const QColor &background)
{
    const qreal dpr = p.device()->devicePixelRatioF();
    const qreal x0 = sv->displayX(0.0, origin, dpr);
    if (x0 <= rect.left())
        return;
    p.fillRect(QRectF(rect.left(), rect.top(), x0 - rect.left(), rect.height()),
               mixTowardOklab(background, gridLineColor(), 0.15));
}

// Vertical bar/beat grid lines inside rect, with zoom-adaptive sub-beat
// lines at the snap grid's positions fading lighter per subdivision level.
// Lines are batched per level so each color is a single drawLines() call.
void drawGrid(QPainter &p, const SongView *sv, const QRect &rect, qreal origin,
              int timelineDetailMinimumPixelsPerBeat, int gridLineStrokeWidth)
{
    if (!sv->timeline())
        return;
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

QFont timeRulerFont(const QFont &source, int minimumFontPixelSize, qreal letterSpacing)
{
    auto font = typography::bodyMono(typography::caption(source));
    font.setPixelSize(std::max(minimumFontPixelSize, font.pixelSize() - lyt::singlePixel()));
    font.setLetterSpacing(QFont::AbsoluteSpacing, letterSpacing);
    return font;
}
// "bar.beat" labels sit one size below the bar numbers so the two label
// tiers read apart even where the deemphasized color alone wouldn't.
QFont beatRulerFont(const QFont &source, int minimumFontPixelSize, qreal letterSpacing)
{
    auto font = timeRulerFont(source, minimumFontPixelSize, letterSpacing);
    font.setPixelSize(std::max(minimumFontPixelSize, font.pixelSize() - lyt::singlePixel()));
    return font;
}

std::optional<QFont> velocityLabelFont(const QFont &source, int availableHeight)
{
    auto font = typography::fitted(source, availableHeight);
    if (font)
        font->setPixelSize(std::max(lyt::singlePixel(), font->pixelSize() - lyt::singlePixel()));
    return font;
}
// Note text sits on a plate of the note's own fill: the velocity bar can
// cross the text rows, and both the bar and a dark picked ink derive from
// the fill, so glyphs painted straight over the bar lose their contrast.
// The plate is a no-op wherever the backdrop is already the plain fill.
void drawPlatedNoteText(QPainter &painter, const QRectF &rect, int flags, const QString &text,
                        const QColor &fill, const QColor &ink)
{
    const QRectF plate = painter.boundingRect(rect, flags, text);
    const qreal pad = lyt::singlePixel();
    painter.fillRect(plate.adjusted(-pad, 0.0, pad, 0.0), fill);
    painter.setPen(ink);
    painter.drawText(rect, flags, text);
}

QFont fixedNoteNameFont(const QFont &source)
{
    auto font = typography::noteName(source);
    font.setPixelSize(std::max(lyt::singlePixel(), font.pixelSize() - 2 * lyt::singlePixel()));
    return font;
}

std::optional<QFont> noteNameFont(const QFont &source, qreal noteBoxHeight)
{
    const auto textHeight = int(std::floor(noteBoxHeight - 2.0 * lyt::space(Space::Half)));
    const auto font = fixedNoteNameFont(source);
    // The face is fixed: when its padded height misses the row, labels hide
    // rather than shrink.
    const QFontMetrics metrics(font);
    if (metrics.ascent() + metrics.descent() > textHeight)
        return std::nullopt;
    return font;
}

} // namespace songview::detail

namespace songview {
using namespace detail;

QColor mixTowardOklab(const QColor &color, const QColor &backdrop, double t)
{
    return mixTowardOklabImpl(color, backdrop, t);
}

} // namespace songview
