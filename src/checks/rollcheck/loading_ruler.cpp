// Geometry and input-gate coverage for the static time ruler. Geometry: a
// bare unbound SongView must already present the ordinary ruler (chrome,
// pre-roll, bars, beats, labels, implicit 4/4) at the canonical pre-roll
// camera home, binding a default song must not move bar positions,
// ticks-per-beat alone must not move musical positions, and a 3/4 signature
// must move only the signature-dependent bar lines. Input gate: while a
// SongTab is not ready every fixed coverage surface exists, stays enabled
// without disabled styling, and keeps the ordinary gestures consumed; the
// terminal VoicegroupBound stage readies the tab and the same gestures simply
// work again, with no child-control restyle across the transition. Fresh/
// unready, MidiStage-bound/unready, and VoicegroupBound/ready all run on one
// tab. Raster and public-geometry assertions only; nothing here reads
// production source text.
#include <QCoreApplication>
#include <QImage>
#include <QPalette>
#include <QPointer>
#include <QQuickItem>
#include <QScrollBar>
#include <QWidget>
#include <QtGlobal>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <optional>
#include <tuple>
#include <utility>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/tracklimits.h"
#include "project/decompproject.h"
#include "project/projectidentity.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/eventlistview.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"

namespace checks::rollcheck {
namespace {

// --- Shared raster sampling and widget lookup ------------------------------

int maxChannelDelta(QRgb a, QRgb b)
{
    return (std::max)({std::abs(qRed(a) - qRed(b)), std::abs(qGreen(a) - qGreen(b)),
                       std::abs(qBlue(a) - qBlue(b))});
}

bool sameColor(QRgb a, QRgb b, int tolerance)
{
    return maxChannelDelta(a, b) <= tolerance;
}

// Device-pixel sampler over one grabbed widget raster. Every coordinate is
// logical and rounds through the widget's device pixel ratio once.
struct RasterScan {
    QImage image;
    qreal dpr = 1.0;

    bool valid() const { return !image.isNull() && image.width() > 8 && image.height() > 8; }

    int width() const { return image.width(); }

    int height() const { return image.height(); }

    int deviceX(qreal logicalX) const { return qRound(logicalX * dpr); }

    QRgb at(qreal logicalX, qreal logicalY) const
    {
        return image.pixel(std::clamp(deviceX(logicalX), 0, image.width() - 1),
                           std::clamp(qRound(logicalY * dpr), 0, image.height() - 1));
    }

    int matchingInBox(int x0, int x1, int y0, int y1, QRgb color, int tolerance) const
    {
        int count = 0;
        for (int y = (std::max)(0, y0); y <= (std::min)(image.height() - 1, y1); ++y)
            for (int x = (std::max)(0, x0); x <= (std::min)(image.width() - 1, x1); ++x)
                if (sameColor(image.pixel(x, y), color, tolerance))
                    ++count;
        return count;
    }

    int differingInColumn(int xDevice, int y0, int y1, QRgb backdrop, int threshold) const
    {
        if (xDevice < 0 || xDevice >= image.width())
            return 0;
        int count = 0;
        for (int y = (std::max)(0, y0); y <= (std::min)(image.height() - 1, y1); ++y)
            if (maxChannelDelta(image.pixel(xDevice, y), backdrop) > threshold)
                ++count;
        return count;
    }
};

RasterScan grabRaster(QWidget &widget)
{
    widget.ensurePolished();
    widget.update();
    QCoreApplication::processEvents();

    QImage image = widget.grab().toImage();
    const qreal dpr = widget.devicePixelRatioF();
    return {image, dpr > 0.0 ? dpr : 1.0};
}

// The canonical ruler band raster: the Quick canvas captured at the
// SongView-local rect published by the view's own band layout. Empty when the
// ruler band is not published.
RasterScan grabRulerRaster(SongView &view)
{
    const std::optional<songview::TimelineBandGeometry> &band =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    if (!band)
        return {};
    QImage image = checks::support::captureQuickBand(view, band->rect);
    const qreal dpr = image.devicePixelRatio();
    return {image, dpr > 0.0 ? dpr : 1.0};
}

// The canonical ruler band height, from the published layout entry.
int rulerBandHeight(const SongView &view)
{
    return view.timelineBandLayout()
        .geometry(songview::TimelineBand::Ruler)
        .value_or(songview::TimelineBandGeometry{})
        .rect.height();
}

// --- Geometry scenarios ----------------------------------------------------

// The fallback musical axis: 24 ticks per beat with an implicit opening 4/4.
constexpr uint64_t kFallbackTicksPerBeat = 24;
constexpr int kFallbackBeatsPerBar = 4;

struct BarSample {
    uint64_t tick = 0;       // bar-line tick under the governing axis
    int column = -1;         // detected device column, -1 when absent
    bool labelFound = false; // strong label pixels right of the line
};

// Sample the ruler raster for the expected bar lines at ticks
// [(bar-1) * beatsPerBar * ticksPerBeat]. Expected positions come from the
// view's public display geometry; detection asks the raster whether a line
// and its number label were painted there.
std::vector<BarSample> sampleBars(SongView &view, const RasterScan &raster, qreal plotOrigin,
                                  uint32_t ticksPerBeat, int beatsPerBar, int bars)
{
    const int tickRowTop = int(raster.height() * 0.55);
    const int tickRowBottom = raster.height() - 3;
    const int labelWidth = int(34 * raster.dpr);
    const QRgb backdrop = raster.at(plotOrigin + view.camera().leadPadPx() + 80.0, 2.0);
    std::vector<BarSample> samples;
    samples.reserve(size_t(bars));
    for (int bar = 1; bar <= bars; ++bar) {
        const uint64_t tick = uint64_t(bar - 1) * uint64_t(beatsPerBar) * ticksPerBeat;
        const int expected =
            raster.deviceX(view.camera().displayX(double(tick), plotOrigin, raster.dpr));
        if (expected < 2 || expected >= raster.width() - labelWidth - 2)
            continue;
        BarSample sample;
        sample.tick = tick;
        for (int x = expected - 1; x <= expected + 1 && sample.column < 0; ++x) {
            if (raster.differingInColumn(x, tickRowTop, tickRowBottom, backdrop, 6) >= 2)
                sample.column = x;
        }
        int labelPixels = 0;
        for (int x = expected + 3; x <= expected + labelWidth; ++x)
            labelPixels += raster.differingInColumn(x, tickRowTop, tickRowBottom, backdrop, 30);
        sample.labelFound = labelPixels >= 2;
        samples.push_back(sample);
    }
    return samples;
}

// The geometry fixture: the staged timelines must outlive the view that binds
// them, so they are declared before the SongView; the canonical ruler band
// comes from the view's published layout, and the pre-binding value snapshots
// follow.
struct GeometryFixture {
    MidiTimeline default44;
    MidiTimeline t48;
    MidiTimeline t34;
    SongView bare;
    double pxPerBeat = 0.0;      // canonical horizontal scale
    std::vector<BarSample> bars; // fallback bar samples from the bare raster
    std::vector<double> barX;    // pre-binding bar contentX positions
    std::vector<double> beatX;   // pre-binding beat contentX positions

    GeometryFixture()
    {
        bare.resize(1280, 800);
        bare.show();
        bare.ensurePolished();
        QCoreApplication::processEvents();
        (void)bare.grab(); // force layout so child geometry is real
        pxPerBeat = SongView::ViewState{}.pxPerBeat;

        default44.ticksPerBeat = kFallbackTicksPerBeat;
        default44.lengthTicks = 16 * kFallbackBeatsPerBar * kFallbackTicksPerBeat;
        t48.ticksPerBeat = 48;
        t48.lengthTicks = 16 * kFallbackBeatsPerBar * 48;
        t34.ticksPerBeat = kFallbackTicksPerBeat;
        t34.lengthTicks = 16 * kFallbackBeatsPerBar * kFallbackTicksPerBeat;
        t34.timeSigs = {{0, 3, 2}};
    }

    // Detach the view before the staged timelines die, and settle the hidden
    // widget before fixture scope ends.
    ~GeometryFixture()
    {
        bare.setSong(nullptr, nullptr);
        bare.hide();
        QCoreApplication::processEvents();
    }
};

// --- The bare unbound view and its first bindings -------------------------

// The fallback camera rests at the pre-roll home across resizes: the lead
// pad stays positive and the content origin stays pinned to it, at the
// canonical horizontal scale.
void observeFallbackCamera(GeometryFixture &fx, Harness &check)
{
    for (const int width : {1280, 1000, 1500}) {
        fx.bare.resize(width, 800);
        QCoreApplication::processEvents();
        const double pad = fx.bare.camera().leadPadPx();
        if (pad <= 0.0)
            check.fail("fallback lead pad is not positive");
        else if (std::abs(fx.bare.camera().contentX(0.0) - pad) > 0.5)
            check.fail("fresh view camera is not at the pre-roll home");
        if (!qFuzzyCompare(fx.bare.camera().pxPerBeat(), fx.pxPerBeat))
            check.fail("fresh view horizontal scale is not the canonical default");
    }
}

// The fallback axis iterates the implicit 4/4 grid through the ordinary
// public facade: beats every 24 ticks, bars every 4 beats, 1-based
// numbering, and a tick-0 grid segment that matches.
void observeFallbackGrid(GeometryFixture &fx, Harness &check)
{
    std::vector<std::tuple<uint64_t, bool, int, int>> lines;
    fx.bare.forEachGridLine(0, 4 * kFallbackBeatsPerBar * kFallbackTicksPerBeat,
                            [&lines](uint64_t tick, bool isBar, int barNumber, int beatNumber) {
                                lines.emplace_back(tick, isBar, barNumber, beatNumber);
                            });
    if (lines.size() != 16)
        check.fail("fallback grid iteration did not yield 4/4 beats for 4 bars");
    for (int k = 0; k < int(lines.size()) && k < 16; ++k) {
        const auto &[tick, isBar, barNumber, beatNumber] = lines[size_t(k)];
        if (tick != uint64_t(k) * kFallbackTicksPerBeat || isBar != (k % 4 == 0) ||
            barNumber != k / 4 + 1 || beatNumber != k % 4 + 1)
            check.fail("fallback grid iteration does not match implicit 4/4");
    }
    const songview::Grid::Segment seg = fx.bare.grid().segmentAt(0);
    if (seg.start != 0 || seg.next != UINT64_MAX || seg.beatTicks != kFallbackTicksPerBeat ||
        seg.beatsPerBar != kFallbackBeatsPerBar)
        check.fail("fallback grid segment is not implicit 4/4 at 24 ticks per beat");
}

// A viewport at the unsigned tick ceiling must stop at the ceiling instead of
// wrapping its beat stride to zero and keeping the GUI thread in grid rebuild.
void observeFallbackGridAtTickCeiling(GeometryFixture &fx, Harness &check)
{
    std::vector<uint64_t> ticks;
    fx.bare.forEachGridLine(UINT64_MAX - kFallbackTicksPerBeat, UINT64_MAX,
                            [&ticks](uint64_t tick, bool, int, int) { ticks.push_back(tick); });
    if (ticks.size() > 1 || (!ticks.empty() && ticks.front() < UINT64_MAX - kFallbackTicksPerBeat))
        check.fail("fallback grid iteration wrapped at the unsigned tick ceiling");
}

// Ordinary pre-roll: the strip left of tick 0 paints a flat shade that
// differs from the plain chrome right of it.
void observeFallbackPreRollShade(const RasterScan &raster, qreal plotOrigin, qreal x0, QRgb chrome,
                                 Harness &check)
{
    const qreal rulerLogicalHeight = raster.height() / raster.dpr;
    const QRgb padShade = raster.at(plotOrigin + 4.0, rulerLogicalHeight * 0.5);
    const QRgb padShadeLower =
        raster.at(plotOrigin + 4.0 + (x0 - plotOrigin) * 0.5, rulerLogicalHeight - 4.0);
    if (!sameColor(padShade, padShadeLower, 2))
        check.fail("fresh ruler pre-roll shade is not flat");
    if (sameColor(padShade, chrome, 1))
        check.fail("fresh ruler painted no pre-roll shade before tick 0");
}

// The implicit opening 4/4: a full-height chip stem at tick 0 drawn with
// the implicit (placeholder) presentation, and no loading caption left in
// the pre-roll strip between the plot origin and the tick-0 chip. (Bounded
// with margins: the far-right gutter combos would false-match.)
void observeFallbackSignatureAndCaption(const RasterScan &raster, qreal plotOrigin, qreal x0,
                                        QRgb placeholder, Harness &check)
{
    const int stemColumn = raster.deviceX(x0);
    const int stemTop = int(raster.height() * 0.05);
    const int stemBottom = int(raster.height() * 0.45);
    int stemRun = 0;
    for (int x = stemColumn - 1; x <= stemColumn + 1; ++x) {
        int run = 0;
        for (int y = stemTop; y <= stemBottom; ++y)
            if (sameColor(raster.image.pixel(x, y), placeholder, 12))
                ++run;
        stemRun = (std::max)(stemRun, run);
    }
    if (stemRun < (stemBottom - stemTop) * 7 / 10)
        check.fail("fresh ruler has no implicit 4/4 signature stem at tick 0");
    if (raster.matchingInBox(raster.deviceX(plotOrigin + 4.0), stemColumn - raster.deviceX(4.0), 0,
                             raster.height() - 1, placeholder, 12) > 0)
        check.fail("fresh ruler still paints the loading caption");
}

// Bar and beat content before any setSong(): every expected fallback bar
// line with its number label, at least two painted bars, and the first
// three interior beat lines. Samples the bars into the fixture for the
// binding phases.
void observeFallbackBarsAndBeats(GeometryFixture &fx, const RasterScan &raster, qreal plotOrigin,
                                 QRgb chrome, Harness &check)
{
    fx.bars = sampleBars(fx.bare, raster, plotOrigin, uint32_t(kFallbackTicksPerBeat),
                         kFallbackBeatsPerBar, 6);
    int paintedBars = 0;
    for (const BarSample &sample : fx.bars) {
        if (sample.column >= 0)
            ++paintedBars;
        else
            check.fail("fresh ruler is missing a fallback bar line");
        if (!sample.labelFound)
            check.fail("fresh ruler is missing a bar number label");
    }
    if (paintedBars < 2)
        check.fail("fresh ruler painted too few bar lines to be the ordinary ruler");
    for (int beat = 1; beat <= 3; ++beat) {
        const uint64_t tick = uint64_t(beat) * kFallbackTicksPerBeat;
        const int expected =
            raster.deviceX(fx.bare.camera().displayX(double(tick), plotOrigin, raster.dpr));
        bool found = false;
        for (int x = expected - 1; x <= expected + 1 && !found; ++x)
            found = raster.differingInColumn(x, int(raster.height() * 0.72), raster.height() - 3,
                                             chrome, 6) >= 1;
        if (!found)
            check.fail("fresh ruler is missing a fallback beat line");
    }
}

// The bare ruler raster: a flat pre-roll shade, the implicit 4/4 signature
// stem at tick 0, no loading caption, and painted fallback bars with number
// labels and beat lines. Samples the bars into the fixture for the binding
// phases. Returns false when the ruler raster is unusable.
bool runFallbackRasterScenarios(GeometryFixture &fx, Harness &check)
{
    const RasterScan raster = grabRulerRaster(fx.bare);
    if (!raster.valid()) {
        check.fail("fresh ruler raster could not be captured");
        return false;
    }

    const qreal plotOrigin = check.plotOrigin();
    const qreal x0 = plotOrigin + fx.bare.camera().contentX(0.0); // tick 0 under the home camera
    const QRgb chrome = raster.at(x0 + 80.0, 2.0); // marker row right of the 4/4 chip
    const QRgb placeholder = fx.bare.palette().color(QPalette::PlaceholderText).rgb();

    observeFallbackPreRollShade(raster, plotOrigin, x0, chrome, check);
    observeFallbackSignatureAndCaption(raster, plotOrigin, x0, placeholder, check);
    observeFallbackBarsAndBeats(fx, raster, plotOrigin, chrome, check);
    return true;
}

// Binding a default 4/4 song at the default zoom must not move bar positions
// pixel-for-pixel, and must not change the canonical scale. Snapshots the
// pre-binding bar and beat positions first.
void runDefaultBindScenarios(GeometryFixture &fx, Harness &check)
{
    for (const BarSample &sample : fx.bars)
        fx.barX.push_back(fx.bare.camera().contentX(double(sample.tick)));
    for (int beat = 1; beat <= 8; ++beat)
        fx.beatX.push_back(fx.bare.camera().contentX(double(beat) * kFallbackTicksPerBeat));

    fx.bare.setSong(&fx.default44, nullptr);
    QCoreApplication::processEvents();
    if (!qFuzzyCompare(fx.bare.camera().pxPerBeat(), fx.pxPerBeat))
        check.fail("default binding changed the canonical horizontal scale");
    const qreal plotOrigin = check.plotOrigin();
    const RasterScan bound = grabRulerRaster(fx.bare);
    if (!bound.valid()) {
        check.fail("bound ruler raster could not be captured");
    } else {
        const std::vector<BarSample> boundBars = sampleBars(
            fx.bare, bound, plotOrigin, uint32_t(kFallbackTicksPerBeat), kFallbackBeatsPerBar, 6);
        if (boundBars.size() != fx.bars.size())
            check.fail("default binding changed the sampled bar count");
        for (size_t i = 0; i < boundBars.size() && i < fx.bars.size(); ++i) {
            if (boundBars[i].column != fx.bars[i].column)
                check.fail("default binding moved a sampled bar line");
            const int expected = bound.deviceX(
                fx.bare.camera().displayX(double(boundBars[i].tick), plotOrigin, bound.dpr));
            if (std::abs(boundBars[i].column - expected) > 1)
                check.fail("bound bar line drifted from the public geometry position");
        }
    }
    for (size_t i = 0; i < fx.barX.size(); ++i)
        if (std::abs(fx.bare.camera().contentX(double(fx.bars[i].tick)) - fx.barX[i]) > 1e-9)
            check.fail("default binding moved a bar position in the public geometry");
}

// Ticks per beat alone never moves musical positions: 24-TPB and 48-TPB
// default timelines of equal musical length paint identical bars and beats
// and expose identical public geometry.
void runTpbBindScenarios(GeometryFixture &fx, Harness &check)
{
    const qreal plotOrigin = check.plotOrigin();
    const RasterScan t24 = grabRulerRaster(fx.bare);
    const std::vector<BarSample> t24Bars = sampleBars(
        fx.bare, t24, plotOrigin, uint32_t(kFallbackTicksPerBeat), kFallbackBeatsPerBar, 6);
    // The beat columns are read while the 24-TPB axis still governs the
    // projection: pxPerTick() follows the bound timeline, so after the
    // 48-TPB rebind these 24-TPB ticks would land on half beats instead of
    // the painted beat lines.
    std::vector<int> t24BeatColumns;
    for (int beat = 1; beat <= 3; ++beat)
        t24BeatColumns.push_back(t24.deviceX(
            fx.bare.camera().displayX(double(beat * kFallbackTicksPerBeat), plotOrigin, t24.dpr)));
    fx.bare.setSong(&fx.t48, nullptr);
    QCoreApplication::processEvents();
    if (!qFuzzyCompare(fx.bare.camera().pxPerBeat(), fx.pxPerBeat))
        check.fail("48-TPB binding changed the canonical horizontal scale");
    const RasterScan t48Raster = grabRulerRaster(fx.bare);
    if (!t48Raster.valid()) {
        check.fail("48-TPB ruler raster could not be captured");
    } else {
        const std::vector<BarSample> t48Bars =
            sampleBars(fx.bare, t48Raster, plotOrigin, 48, kFallbackBeatsPerBar, 6);
        if (t48Bars.size() != t24Bars.size())
            check.fail("48-TPB binding changed the sampled bar count");
        for (size_t i = 0; i < t48Bars.size() && i < t24Bars.size(); ++i)
            if (t48Bars[i].column != t24Bars[i].column)
                check.fail("48-TPB binding moved a bar line");
        for (int beat = 1; beat <= 3; ++beat) {
            const int t48Column = t48Raster.deviceX(
                fx.bare.camera().displayX(double(beat * 48), plotOrigin, t48Raster.dpr));
            if (std::abs(t48Column - t24BeatColumns[size_t(beat - 1)]) > 1)
                check.fail("48-TPB binding moved a beat line");
        }
    }
    for (int beat = 1; beat <= 8; ++beat)
        if (std::abs(fx.bare.camera().contentX(double(beat) * 48) - fx.beatX[size_t(beat - 1)]) >
            1e-6)
            check.fail("48-TPB binding moved a beat position in the public geometry");
}

// Public facade after the 3/4 binding: the grid segment resolves to a
// 3-beat grouping at 24 ticks per beat, the canonical scale holds,
// signature-independent geometry (lead pad, ruler height) is undisturbed,
// and the pre-binding beat positions stay put.
void observeSignaturePublicGeometry(GeometryFixture &fx, qreal rulerHeightBefore, Harness &check)
{
    const songview::Grid::Segment seg = fx.bare.grid().segmentAt(0);
    if (seg.start != 0 || seg.next != UINT64_MAX || seg.beatTicks != kFallbackTicksPerBeat ||
        seg.beatsPerBar != 3)
        check.fail("3/4 binding did not resolve its grid segment");
    if (!qFuzzyCompare(fx.bare.camera().pxPerBeat(), fx.pxPerBeat))
        check.fail("3/4 binding changed the canonical horizontal scale");
    if (fx.bare.camera().leadPadPx() <= 0.0 || rulerBandHeight(fx.bare) != rulerHeightBefore)
        check.fail("3/4 binding disturbed signature-independent geometry");
    for (int beat = 1; beat <= 8; ++beat)
        if (std::abs(fx.bare.camera().contentX(double(beat) * kFallbackTicksPerBeat) -
                     fx.beatX[size_t(beat - 1)]) > 1e-6)
            check.fail("3/4 binding moved a signature-independent beat position");
}

// Raster after the 3/4 binding: every expected 3-beat bar line is painted
// at its signature geometry, and the grouping actually moved relative to
// the sampled fallback bars.
void observeSignatureBarGrouping(GeometryFixture &fx, const RasterScan &t34Raster, qreal plotOrigin,
                                 Harness &check)
{
    const std::vector<BarSample> t34Bars =
        sampleBars(fx.bare, t34Raster, plotOrigin, uint32_t(kFallbackTicksPerBeat), 3, 6);
    bool moved = false;
    for (size_t i = 0; i < t34Bars.size(); ++i) {
        if (t34Bars[i].column < 0) {
            check.fail("3/4 ruler is missing an expected bar line");
            continue;
        }
        const int expected = t34Raster.deviceX(
            fx.bare.camera().displayX(double(t34Bars[i].tick), plotOrigin, t34Raster.dpr));
        if (std::abs(t34Bars[i].column - expected) > 1)
            check.fail("3/4 bar line drifted from its signature geometry");
        if (i < fx.bars.size() && t34Bars[i].column != fx.bars[i].column)
            moved = true;
    }
    if (!moved)
        check.fail("3/4 binding did not move the signature-dependent bar lines");
}

// A non-4/4 signature changes only signature-dependent positions: beats stay
// put, bar lines move to the 3-beat grouping, and nothing else (scale, pad,
// ruler height) follows.
void runSignatureGroupingScenarios(GeometryFixture &fx, Harness &check)
{
    const qreal plotOrigin = check.plotOrigin();
    const qreal rulerHeightBefore = rulerBandHeight(fx.bare);
    fx.bare.setSong(&fx.t34, nullptr);
    QCoreApplication::processEvents();
    observeSignaturePublicGeometry(fx, rulerHeightBefore, check);
    const RasterScan t34Raster = grabRulerRaster(fx.bare);
    if (!t34Raster.valid()) {
        check.fail("3/4 ruler raster could not be captured");
        return;
    }
    observeSignatureBarGrouping(fx, t34Raster, plotOrigin, check);
}

void runGeometryScenarios(Harness &check)
{
    GeometryFixture fx;
    observeFallbackCamera(fx, check);
    fx.bare.resize(1280, 800);
    QCoreApplication::processEvents();
    observeFallbackGrid(fx, check);
    observeFallbackGridAtTickCeiling(fx, check);
    if (!fx.bare.timelineBandLayout().geometry(songview::TimelineBand::Ruler)) {
        check.fail("fresh view has no canonical ruler band");
        return;
    }
    if (!runFallbackRasterScenarios(fx, check))
        return;
    runDefaultBindScenarios(fx, check);
    runTpbBindScenarios(fx, check);
    runSignatureGroupingScenarios(fx, check);
}

// --- Loading-tab input gate ------------------------------------------------

// Owning fixture for one loading probe tab: the tab is the first member, so
// every descendant handle behind it dies with the fixture, and the QPointer
// handles can never dangle even if a child dies early. Handles are
// dereferenced only behind validity checks.
struct GateFixture {
    struct GridControlsState {
        QString divisionText;
        QString feelText;
        QString divisionToolTip;
        QString feelToolTip;
        QVariantMap appearance;
        bool controlsEnabled = false;
        bool divisionEnabled = false;
        bool feelEnabled = false;
    };

    explicit GateFixture(SongName probeName) : tab(std::move(probeName))
    {
        tab.setSampleRate(48000.0);
        tab.resize(1280, 800);
        tab.show();
        tab.ensurePolished();
        QCoreApplication::processEvents();

        SongView &view = tab.view();
        headers = view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"),
                                                               Qt::FindDirectChildrenOnly);
        auto *quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        auto *const quickRoot = quick ? quick->rootObject() : nullptr;
        if (quickRoot) {
            rollInput = quickRoot->findChild<songview::TimelineInputItem *>(
                QStringLiteral("timelineRollInput"));
            stripInput = quickRoot->findChild<songview::TimelineInputItem *>(
                QStringLiteral("timelineOtherEventsInput"));
            rulerInput = quickRoot->findChild<songview::TimelineInputItem *>(
                QStringLiteral("timelineRulerInput"));
            headersInput = quickRoot->findChild<songview::TimelineInputItem *>(
                QStringLiteral("timelineTrackHeadersInput"));
            controls = quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerControls"));
            divisionControl =
                quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
            feelControl =
                quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerFeelControl"));
        }
        ruler =
            rulerInput ? dynamic_cast<songview::TimeRuler *>(rulerInput->interaction()) : nullptr;
        const std::array<QString, 5> drawerChromeInputNames{
            QStringLiteral("drawerVoiceChangesHandleInput"),
            QStringLiteral("drawerVelocityHandleInput"),
            QStringLiteral("drawerAutomationHandleInput"), QStringLiteral("drawerBarInput"),
            QStringLiteral("drawerDetentInput")};
        for (int i = 0; i < int(drawerInputs.size()); ++i) {
            drawerInputs[i] =
                quickRoot
                    ? quickRoot->findChild<songview::TimelineInputItem *>(drawerChromeInputNames[i])
                    : nullptr;
        }
        events = view.findChild<EventListView *>();
        drawer = view.editorDrawer();
        for (QScrollBar *scrollbar : view.findChildren<QScrollBar *>()) {
            if (!scrollbar->isVisibleTo(&view))
                continue;
            if (scrollbar->orientation() == Qt::Horizontal)
                hbar = scrollbar;
            else
                vbar = scrollbar;
        }
    }

    // Window teardown settles while every child is still alive.
    ~GateFixture()
    {
        tab.hide();
        QCoreApplication::processEvents();
    }

    // Every fixed coverage surface exists and stays enabled while loading:
    // the gate must not reuse the disabled-styling presentation.
    void checkSurfacesEnabled(Harness &check) const
    {
        const std::pair<const char *, QWidget *> widgetSurfaces[] = {
            {"event list", events.data()},
            {"horizontal scrollbar", hbar.data()},
            {"vertical scrollbar", vbar.data()},
        };
        for (const auto &[name, widget] : widgetSurfaces) {
            if (!widget)
                check.fail(qUtf8Printable(QObject::tr("loading view is missing its %1").arg(name)));
            else if (!widget->isEnabled())
                check.fail(qUtf8Printable(
                    QObject::tr("loading %1 was disabled instead of gated").arg(name)));
        }
        if (!drawer)
            check.fail("loading view is missing its editor drawer");
        if (!headers)
            check.fail("loading view is missing its TrackHeaderModel");
        else if (!headersInput || headersInput->interaction() != headers.data())
            check.fail("loading view is missing its TrackHeaders Quick input");
        else if (!headersInput->isEnabled())
            check.fail("loading TrackHeaders Quick input was disabled instead of gated");
        if (!controls || !divisionControl || !feelControl)
            check.fail("loading view is missing its Quick ruler controls");
        else if (!controls->isEnabled() || !divisionControl->isEnabled() ||
                 !feelControl->isEnabled())
            check.fail("loading Quick ruler controls were disabled instead of gated");
        if (!rollInput)
            check.fail("loading view is missing its roll Quick input");
        else if (!rollInput->isEnabled())
            check.fail("loading roll Quick input was disabled instead of gated");
        if (!stripInput)
            check.fail("loading view is missing its other-events Quick input");
        else if (!stripInput->isEnabled())
            check.fail("loading other-events Quick input was disabled instead of gated");
        if (!rulerInput || !ruler)
            check.fail("loading view is missing its TimeRuler Quick input");
        else if (!rulerInput->isEnabled())
            check.fail("loading ruler Quick input was disabled instead of gated");
        for (const QPointer<songview::TimelineInputItem> &input : drawerInputs) {
            if (!input)
                check.fail("loading view is missing a drawer chrome Quick input");
            else if (!input->isEnabled())
                check.fail("loading drawer chrome Quick input was disabled instead of gated");
        }
    }

    // The TimeRuler state and the QML controls must all stay enabled while loading.
    void checkGridControlsEnabled(Harness &check) const
    {
        if (!ruler || !controls || !divisionControl || !feelControl) {
            check.fail("time ruler has no Quick grid controls");
            return;
        }
        if (!ruler->gridControlsEnabled() || !controls->isEnabled() ||
            !divisionControl->isEnabled() || !feelControl->isEnabled()) {
            check.fail("Quick grid controls were disabled while loading");
            return;
        }
        if (divisionControl->property("controlText").toString() != ruler->divisionText() ||
            feelControl->property("controlText").toString() != ruler->feelText() ||
            divisionControl->property("controlToolTip").toString() != ruler->divisionToolTip() ||
            feelControl->property("controlToolTip").toString() != ruler->feelToolTip()) {
            check.fail("Quick grid controls did not reflect TimeRuler state while loading");
        }
    }

    void snapshotGridControls()
    {
        if (!ruler || !controls || !divisionControl || !feelControl)
            return;
        gatedGridControls = GridControlsState{
            ruler->divisionText(),          ruler->feelText(),
            ruler->divisionToolTip(),       ruler->feelToolTip(),
            ruler->gridControlAppearance(), controls->isEnabled(),
            divisionControl->isEnabled(),   feelControl->isEnabled(),
        };
    }

    // The readiness transition must not alter the TimeRuler state or the
    // properties that render its existing Quick controls.
    void checkGridControlsUnchanged(Harness &check) const
    {
        if (!gatedGridControls) {
            check.fail("Quick grid control state was not snapshotted before readiness");
            return;
        }
        if (!ruler || !controls || !divisionControl || !feelControl) {
            check.fail("a Quick grid control was destroyed across the readiness transition");
            return;
        }
        const GridControlsState &before = *gatedGridControls;
        const bool unchanged =
            ruler->divisionText() == before.divisionText && ruler->feelText() == before.feelText &&
            ruler->divisionToolTip() == before.divisionToolTip &&
            ruler->feelToolTip() == before.feelToolTip &&
            ruler->gridControlAppearance() == before.appearance &&
            controls->isEnabled() == before.controlsEnabled &&
            divisionControl->isEnabled() == before.divisionEnabled &&
            feelControl->isEnabled() == before.feelEnabled &&
            divisionControl->property("controlText").toString() == before.divisionText &&
            feelControl->property("controlText").toString() == before.feelText &&
            divisionControl->property("controlToolTip").toString() == before.divisionToolTip &&
            feelControl->property("controlToolTip").toString() == before.feelToolTip;
        if (!unchanged)
            check.fail(
                "Quick grid controls changed state or styling across the readiness transition");
    }

    SongTab tab;
    QPointer<songview::TrackHeaderModel> headers;
    QPointer<songview::TimelineInputItem> headersInput;
    QPointer<QQuickItem> controls;
    QPointer<QQuickItem> divisionControl;
    QPointer<QQuickItem> feelControl;
    QPointer<songview::TimeRuler> ruler;
    QPointer<songview::TimelineInputItem> rollInput;
    QPointer<songview::TimelineInputItem> rulerInput;
    QPointer<songview::TimelineInputItem> stripInput;
    std::array<QPointer<songview::TimelineInputItem>, 5> drawerInputs;
    QPointer<EventListView> events;
    QPointer<EditorDrawer> drawer;
    QPointer<QScrollBar> hbar;
    QPointer<QScrollBar> vbar;
    std::optional<GridControlsState> gatedGridControls;
};

// --- Repeated-gesture observers -------------------------------------------
//
// Each observer fires one gesture and reports the before/after state it saw;
// the phase functions own every assertion about what changed.

struct RulerScrubSample {
    uint64_t cursorBefore = 0;
    uint64_t cursorAfter = 0;
    bool gestureArmed = false;
};

// One click at the covered ruler point. Empty when the view has no pre-roll
// padding to anchor the point to.
std::optional<RulerScrubSample> scrubRuler(SongView &view, songview::TimelineInputItem &rulerInput,
                                           qreal plotOrigin)
{
    const qreal pad = view.camera().leadPadPx();
    if (pad <= 0)
        return std::nullopt;
    const std::optional<songview::TimelineBandGeometry> rulerBand =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    if (!rulerBand)
        return std::nullopt;
    const QPointF point(plotOrigin + pad + 140.0, rulerBand->rect.height() * 3.0 / 4.0);
    RulerScrubSample sample;
    sample.cursorBefore = view.editCursorTick();
    checks::events::sendMouse(rulerInput, QEvent::MouseButtonPress, point, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rulerInput, QEvent::MouseButtonRelease, point, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    sample.cursorAfter = view.editCursorTick();
    sample.gestureArmed = view.userGestureActive();
    return sample;
}

struct RollWheelSample {
    double zoomBefore = 0.0;
    double zoomAfter = 0.0;
};

// One wheel tick over the piano roll at the covered point.
RollWheelSample wheelRoll(Harness &check, songview::TimelineInputItem &roll, SongView &view)
{
    RollWheelSample sample;
    sample.zoomBefore = view.camera().pxPerBeat();
    checks::events::sendWheel(roll, QPointF(check.pianoKeyboardWidth() + 80.0, 100.0), QPoint(0, 0),
                              QPoint(0, 120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase,
                              false);
    sample.zoomAfter = view.camera().pxPerBeat();
    return sample;
}

struct ScrollWheelSample {
    int valueBefore = 0;
    int valueAfter = 0;
};

// One wheel tick over the horizontal camera scrollbar.
ScrollWheelSample wheelHorizontalScrollbar(QScrollBar &bar)
{
    ScrollWheelSample sample;
    sample.valueBefore = bar.value();
    checks::events::sendWheel(bar, QPointF(bar.width() / 2.0, bar.height() / 2.0), QPoint(0, 0),
                              QPoint(0, -120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase,
                              false);
    sample.valueAfter = bar.value();
    return sample;
}

// The loading gate consumes a ruler press without moving the edit cursor and
// disarms the gesture afterwards.
void checkGatedRulerScrub(Harness &check, GateFixture &probe, const char *scrubFailure)
{
    if (!probe.rulerInput)
        return;
    const std::optional<RulerScrubSample> sample =
        scrubRuler(probe.tab.view(), *probe.rulerInput, check.plotOrigin());
    if (!sample)
        return;
    if (sample->cursorAfter != sample->cursorBefore)
        check.fail(scrubFailure);
    if (sample->gestureArmed)
        check.fail("ruler gesture stayed armed after a gated press");
}

// Once ready the same press scrubs again and still disarms the gesture.
void checkReadyRulerScrub(Harness &check, GateFixture &probe)
{
    if (!probe.rulerInput)
        return;
    const std::optional<RulerScrubSample> sample =
        scrubRuler(probe.tab.view(), *probe.rulerInput, check.plotOrigin());
    if (!sample)
        return;
    if (sample->cursorAfter == sample->cursorBefore)
        check.fail("ruler click did not scrub after readiness");
    if (sample->gestureArmed)
        check.fail("ruler gesture stayed armed after a plain click");
}

// The loading gate consumes a horizontal scrollbar wheel tick.
void checkGatedScrollWheel(Harness &check, GateFixture &probe)
{
    if (!probe.hbar)
        return;
    const ScrollWheelSample sample = wheelHorizontalScrollbar(*probe.hbar);
    if (sample.valueAfter != sample.valueBefore)
        check.fail("scrollbar wheel scrolled while the tab was loading");
}

// Once ready the same wheel tick scrolls again.
void checkReadyScrollWheel(Harness &check, GateFixture &probe)
{
    if (!probe.hbar)
        return;
    const ScrollWheelSample sample = wheelHorizontalScrollbar(*probe.hbar);
    if (sample.valueAfter == sample.valueBefore)
        check.fail("scrollbar wheel did not scroll after readiness");
}

// The loading gate consumes a roll wheel zoom.
void checkGatedRollWheel(Harness &check, GateFixture &probe)
{
    if (!probe.rollInput)
        return;
    const RollWheelSample sample = wheelRoll(check, *probe.rollInput, probe.tab.view());
    if (!qFuzzyCompare(sample.zoomAfter, sample.zoomBefore))
        check.fail("roll wheel zoomed while the tab was loading");
}

// Once ready the same wheel tick zooms again.
void checkReadyRollWheel(Harness &check, GateFixture &probe)
{
    if (!probe.rollInput)
        return;
    const RollWheelSample sample = wheelRoll(check, *probe.rollInput, probe.tab.view());
    if (qFuzzyCompare(sample.zoomAfter, sample.zoomBefore))
        check.fail("roll wheel did not zoom after readiness");
}

// --- Phase one: fresh tab, nothing bound, gate fully closed ---------------

void runFreshGatePhase(Harness &check, GateFixture &probe)
{
    probe.checkSurfacesEnabled(check);
    probe.checkGridControlsEnabled(check);

    // A fresh tab is not ready, but programmatic state application and
    // paint still work.
    if (probe.tab.isReady())
        check.fail("fresh tab reported readiness before any load stage");
    SongView &view = probe.tab.view();
    view.setEditCursorTick(96);
    if (view.editCursorTick() != 96)
        check.fail("programmatic edit-cursor application failed while loading");
    if (grabRaster(view).image.isNull())
        check.fail("loading view could not paint");

    // Loading input is inert on representative descendants.
    checkGatedRulerScrub(check, probe, "ruler click scrubbed while the tab was loading");
    checkGatedRollWheel(check, probe);
}

// --- Phase two: MidiStage bound, still not ready --------------------------

void runMidiStageGatePhase(Harness &check, GateFixture &probe)
{
    // MidiStage alone must not ready the tab or release the gate.
    SmfFile emptySmf;
    SongInfo probeInfo;
    probeInfo.label = probe.tab.name().value();
    probe.tab.applyMidiStage(probeInfo, std::move(emptySmf), track_limits::kHardwareCapacity);
    if (probe.tab.isReady())
        check.fail("readiness landed before the terminal voicegroup stage");
    if (!probe.tab.view().timeline())
        check.fail("MidiStage did not bind the view timeline");
    if (probe.tab.view().editCursorTick() != 0)
        check.fail("MidiStage did not establish the canonical edit-cursor default");
    if (!probe.tab.view().isEnabled())
        check.fail("midi-bound loading view was disabled instead of gated");
    // The bind transition must not drop a coverage surface or grid control.
    probe.checkSurfacesEnabled(check);
    probe.checkGridControlsEnabled(check);

    probe.snapshotGridControls();

    // Bound but not ready: the ordinary gestures stay consumed.
    checkGatedRulerScrub(check, probe,
                         "ruler click moved the edit cursor while the tab was loading");
    checkGatedScrollWheel(check, probe);
    checkGatedRollWheel(check, probe);
}

// --- Phase three: terminal VoicegroupBound readies the tab ----------------

void runReadyGatePhase(Harness &check, GateFixture &probe)
{
    // Terminal VoicegroupBound readies the tab; input is simply no longer
    // gated, and no child-control styling changed across the transition.
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/loading_probe.inc"), QString());
    if (!identity)
        check.fail("probe voicegroup identity was rejected");
    else
        probe.tab.applyVoicegroupBound(*identity);
    if (!probe.tab.isReady())
        check.fail("terminal voicegroup stage did not ready the tab");
    if (!probe.tab.view().isEnabled())
        check.fail("ready view lost its enabled state");
    // The terminal transition must not drop a coverage surface or grid control.
    probe.checkSurfacesEnabled(check);
    probe.checkGridControlsEnabled(check);
    probe.checkGridControlsUnchanged(check);

    // The same gestures work again once ready.
    checkReadyRulerScrub(check, probe);
    checkReadyScrollWheel(check, probe);
    checkReadyRollWheel(check, probe);
}

void runInputGateScenarios(Harness &check)
{
    const std::optional<SongName> probeName =
        SongName::create(QStringLiteral("mus_loading_ruler_probe"));
    if (!probeName) {
        check.fail("probe song name was rejected as an identity");
        return;
    }

    GateFixture probe(*probeName);
    runFreshGatePhase(check, probe);
    runMidiStageGatePhase(check, probe);
    runReadyGatePhase(check, probe);
}

} // namespace

ScenarioContinuation runLoadingRulerScenarios(Harness &check)
{
    runGeometryScenarios(check);
    runInputGateScenarios(check);

    // The scenarios above raise their own windows; hand focus back to the
    // rig view for the sequential gesture suites that follow.
    check.view().raise();
    check.view().activateWindow();
    QCoreApplication::processEvents();
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
