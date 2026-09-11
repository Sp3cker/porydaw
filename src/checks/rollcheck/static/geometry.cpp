#include "checks/rollcheck/static/tst_pianorollstatic.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QPalette>
#include <QSize>
#include <QtTest>

#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

#include "checks/rollcheck/static/fixtures.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::rollcheck::staticcheck {
namespace {
constexpr uint64_t kTicksPerBeat = 24;
constexpr int kBeatsPerBar = 4;

struct BareView {
    MidiTimeline default44;
    MidiTimeline t48;
    MidiTimeline t34;
    SongView view;

    BareView()
    {
        auto *const editActions = new songview::EditActions(&view);
        editActions->rebind(&view);
        if (!checks::support::showQuickViewport(view, QSize(1280, 800)))
            qFatal("static geometry fixture could not expose the Quick window");
        default44 = {.ticksPerBeat = kTicksPerBeat,
                     .lengthTicks = 16 * kBeatsPerBar * kTicksPerBeat};
        t48 = {.ticksPerBeat = 48, .lengthTicks = 16 * kBeatsPerBar * 48};
        t34 = {.ticksPerBeat = kTicksPerBeat,
               .lengthTicks = 16 * kBeatsPerBar * kTicksPerBeat,
               .timeSigs = {{0, 3, 2}}};
    }

    ~BareView()
    {
        view.setSong(nullptr, nullptr);
        QCoreApplication::processEvents();
    }
};

int channelDelta(QRgb left, QRgb right)
{
    return (std::max)({std::abs(qRed(left) - qRed(right)), std::abs(qGreen(left) - qGreen(right)),
                       std::abs(qBlue(left) - qBlue(right))});
}

bool hasPaintedColumn(const Raster &raster, int column, int first, int last, QRgb backdrop,
                      int threshold, int minimum)
{
    if (column < 0 || column >= raster.image.width())
        return false;
    int changed = 0;
    for (int y = std::max(0, first); y <= std::min(last, raster.image.height() - 1); ++y)
        if (channelDelta(raster.image.pixel(column, y), backdrop) > threshold &&
            ++changed >= minimum)
            return true;
    return false;
}

bool lineAt(const Raster &raster, int expected, int first, int last, QRgb backdrop, int threshold,
            int minimum)
{
    return hasPaintedColumn(raster, expected - 1, first, last, backdrop, threshold, minimum) ||
           hasPaintedColumn(raster, expected, first, last, backdrop, threshold, minimum) ||
           hasPaintedColumn(raster, expected + 1, first, last, backdrop, threshold, minimum);
}

int detectedLine(const Raster &raster, int expected, int first, int last, QRgb backdrop)
{
    for (int x = expected - 1; x <= expected + 1; ++x)
        if (hasPaintedColumn(raster, x, first, last, backdrop, 6, 2))
            return x;
    return -1;
}
} // namespace

void PianoRollStaticTest::fallbackCamera_data()
{
    QTest::addColumn<int>("width");
    QTest::newRow("1280") << 1280;
    QTest::newRow("1000") << 1000;
    QTest::newRow("1500") << 1500;
}

void PianoRollStaticTest::fallbackCamera()
{
    QFETCH(int, width);
    BareView fixture;
    QVERIFY(fixture.view.quickView() && fixture.view.quickView()->quickWindow());
    fixture.view.quickView()->quickWindow()->resize(QSize(width, 800));
    QCoreApplication::processEvents();
    const double leadPad = fixture.view.camera().leadPadPx();
    QVERIFY2(leadPad > 0.0, "fallback lead pad is not positive");
    QVERIFY2(std::abs(fixture.view.camera().contentX(0.0) - leadPad) <= 0.5,
             "fresh view camera is not at the pre-roll home");
    QCOMPARE(fixture.view.camera().pxPerBeat(), SongView::ViewState{}.pxPerBeat);
}

void PianoRollStaticTest::fallbackGrid()
{
    BareView fixture;
    struct Line {
        uint64_t tick;
        bool bar;
        int barNumber;
        int beatNumber;
    };
    std::vector<Line> lines;
    fixture.view.forEachGridLine(0, 4 * kBeatsPerBar * kTicksPerBeat,
                                 [&lines](uint64_t tick, bool bar, int barNumber, int beatNumber) {
                                     lines.push_back({tick, bar, barNumber, beatNumber});
                                 });
    QCOMPARE(lines.size(), size_t(16));
    for (int index = 0; index < 16; ++index) {
        const Line line = lines[size_t(index)];
        QCOMPARE(line.tick, uint64_t(index) * kTicksPerBeat);
        QCOMPARE(line.bar, index % 4 == 0);
        QCOMPARE(line.barNumber, index / 4 + 1);
        QCOMPARE(line.beatNumber, index % 4 + 1);
    }
    const songview::Grid::Segment segment = fixture.view.grid().segmentAt(0);
    QCOMPARE(segment.start, uint64_t(0));
    QCOMPARE(segment.next, UINT64_MAX);
    QCOMPARE(segment.beatTicks, kTicksPerBeat);
    QCOMPARE(segment.beatsPerBar, kBeatsPerBar);
}

void PianoRollStaticTest::tickCeilingDoesNotWrap()
{
    BareView fixture;
    std::vector<uint64_t> ticks;
    fixture.view.forEachGridLine(
        UINT64_MAX - kTicksPerBeat, UINT64_MAX,
        [&ticks](uint64_t tick, bool, int, int) { ticks.push_back(tick); });
    QVERIFY(ticks.size() <= 1);
    QVERIFY(ticks.empty() || ticks.front() >= UINT64_MAX - kTicksPerBeat);
}

void PianoRollStaticTest::preRollRulerShade()
{
    BareView fixture;
    const Raster raster = captureRuler(fixture.view);
    QVERIFY2(raster.valid(), "fresh ruler raster could not be captured");
    const qreal plotOffset = rulerPlotOffset(fixture.view);
    const qreal tickZero = plotOffset + fixture.view.camera().contentX(0.0);
    const QRgb padUpper = raster.at(plotOffset + 4.0, raster.image.height() / raster.dpr * 0.5);
    const QRgb padLower = raster.at(plotOffset + 4.0 + (tickZero - plotOffset) * 0.5,
                                    raster.image.height() / raster.dpr - 4.0);
    const QRgb chrome = raster.at(tickZero + 80.0, 2.0);
    QVERIFY(channelDelta(padUpper, padLower) <= 2);
    QVERIFY(channelDelta(padUpper, chrome) > 1);
}

void PianoRollStaticTest::fallbackRulerStemAndBars()
{
    BareView fixture;
    const Raster raster = captureRuler(fixture.view);
    QVERIFY2(raster.valid(), "fresh ruler raster could not be captured");
    const qreal offset = rulerPlotOffset(fixture.view);
    const int tickZero = raster.deviceX(offset + fixture.view.camera().contentX(0.0));
    const QRgb placeholder = QGuiApplication::palette().color(QPalette::PlaceholderText).rgb();
    const int top = int(raster.image.height() * 0.05);
    const int bottom = int(raster.image.height() * 0.45);
    int longestStem = 0;
    for (int x = tickZero - 1; x <= tickZero + 1; ++x) {
        int matching = 0;
        for (int y = top; y <= bottom; ++y)
            if (channelDelta(raster.image.pixel(x, y), placeholder) <= 12)
                ++matching;
        longestStem = std::max(longestStem, matching);
    }
    QVERIFY(longestStem >= (bottom - top) * 7 / 10);
    const int captionLeft = std::clamp(raster.deviceX(offset + 4.0), 0, raster.image.width());
    const int captionRight =
        std::clamp(tickZero - qRound(4.0 * raster.dpr), 0, raster.image.width());
    QVERIFY(captionRight > captionLeft);
    int captionPixels = 0;
    for (int y = 0; y < raster.image.height(); ++y)
        for (int x = captionLeft; x < captionRight; ++x)
            if (channelDelta(raster.image.pixel(x, y), placeholder) <= 12)
                ++captionPixels;
    QCOMPARE(captionPixels, 0);
    const QRgb backdrop = raster.at(offset + fixture.view.camera().leadPadPx() + 80.0, 2.0);
    int paintedBars = 0;
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * kBeatsPerBar * kTicksPerBeat;
        const int expected =
            raster.deviceX(fixture.view.camera().displayX(double(tick), offset, raster.dpr));
        const int line = detectedLine(raster, expected, int(raster.image.height() * 0.55),
                                      raster.image.height() - 3, backdrop);
        QVERIFY2(line >= 0, "fresh ruler is missing a fallback bar line");
        ++paintedBars;
        int labelPixels = 0;
        for (int x = expected + 3; x <= expected + int(34 * raster.dpr); ++x)
            for (int y = int(raster.image.height() * 0.55); y < raster.image.height() - 3; ++y)
                if (channelDelta(raster.image.pixel(x, y), backdrop) > 30)
                    ++labelPixels;
        QVERIFY(labelPixels >= 2);
    }
    QVERIFY(paintedBars >= 2);
    for (int beat = 1; beat <= 3; ++beat) {
        const int expected = raster.deviceX(
            fixture.view.camera().displayX(double(beat * kTicksPerBeat), offset, raster.dpr));
        QVERIFY(lineAt(raster, expected, int(raster.image.height() * 0.72),
                       raster.image.height() - 3, backdrop, 6, 1));
    }
}

void PianoRollStaticTest::defaultBindKeepsGeometry()
{
    BareView fixture;
    const Raster before = captureRuler(fixture.view);
    QVERIFY(before.valid());
    const qreal offset = rulerPlotOffset(fixture.view);
    const QRgb backdrop = before.at(offset + fixture.view.camera().leadPadPx() + 80.0, 2.0);
    std::array<int, 6> columns{};
    std::array<double, 6> geometry{};
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * kBeatsPerBar * kTicksPerBeat;
        columns[size_t(bar)] = detectedLine(
            before,
            before.deviceX(fixture.view.camera().displayX(double(tick), offset, before.dpr)),
            int(before.image.height() * 0.55), before.image.height() - 3, backdrop);
        geometry[size_t(bar)] = fixture.view.camera().contentX(double(tick));
    }
    fixture.view.setSong(&fixture.default44, nullptr);
    QCoreApplication::processEvents();
    QCOMPARE(fixture.view.camera().pxPerBeat(), SongView::ViewState{}.pxPerBeat);
    const Raster after = captureRuler(fixture.view);
    QVERIFY(after.valid());
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * kBeatsPerBar * kTicksPerBeat;
        const int expected =
            after.deviceX(fixture.view.camera().displayX(double(tick), offset, after.dpr));
        QCOMPARE(detectedLine(after, expected, int(after.image.height() * 0.55),
                              after.image.height() - 3, backdrop),
                 columns[size_t(bar)]);
        QVERIFY(std::abs(fixture.view.camera().contentX(double(tick)) - geometry[size_t(bar)]) <=
                1e-9);
    }
}

void PianoRollStaticTest::ticksPerBeatKeepsGeometry()
{
    BareView fixture;
    fixture.view.setSong(&fixture.default44, nullptr);
    QCoreApplication::processEvents();
    const Raster before = captureRuler(fixture.view);
    QVERIFY(before.valid());
    const qreal offset = rulerPlotOffset(fixture.view);
    const QRgb backdrop = before.at(offset + fixture.view.camera().leadPadPx() + 80.0, 2.0);
    std::array<int, 6> barColumns{};
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * kBeatsPerBar * kTicksPerBeat;
        const int expected =
            before.deviceX(fixture.view.camera().displayX(double(tick), offset, before.dpr));
        barColumns[size_t(bar)] = detectedLine(before, expected, int(before.image.height() * .55),
                                               before.image.height() - 3, backdrop);
    }
    std::array<int, 3> beatColumns{};
    std::array<double, 8> beatGeometry{};
    for (int beat = 1; beat <= 3; ++beat)
        beatColumns[size_t(beat - 1)] = before.deviceX(
            fixture.view.camera().displayX(double(beat * kTicksPerBeat), offset, before.dpr));
    for (int beat = 1; beat <= 8; ++beat)
        beatGeometry[size_t(beat - 1)] =
            fixture.view.camera().contentX(double(beat * kTicksPerBeat));
    fixture.view.setSong(&fixture.t48, nullptr);
    QCoreApplication::processEvents();
    QCOMPARE(fixture.view.camera().pxPerBeat(), SongView::ViewState{}.pxPerBeat);
    const Raster after = captureRuler(fixture.view);
    QVERIFY(after.valid());
    for (int beat = 1; beat <= 3; ++beat) {
        const int expected =
            after.deviceX(fixture.view.camera().displayX(double(beat * 48), offset, after.dpr));
        QVERIFY(std::abs(expected - beatColumns[size_t(beat - 1)]) <= 1);
        QVERIFY(lineAt(after, expected, int(after.image.height() * .72), after.image.height() - 3,
                       backdrop, 6, 1));
    }
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * kBeatsPerBar * 48;
        const int expected =
            after.deviceX(fixture.view.camera().displayX(double(tick), offset, after.dpr));
        QCOMPARE(detectedLine(after, expected, int(after.image.height() * .55),
                              after.image.height() - 3, backdrop),
                 barColumns[size_t(bar)]);
    }
    for (int beat = 1; beat <= 8; ++beat)
        QVERIFY(std::abs(fixture.view.camera().contentX(double(beat * 48)) -
                         beatGeometry[size_t(beat - 1)]) <= 1e-6);
}

void PianoRollStaticTest::signatureGroupingKeepsBeatsAndMovesBars()
{
    BareView fixture;
    fixture.view.setSong(&fixture.default44, nullptr);
    QCoreApplication::processEvents();
    const Raster before = captureRuler(fixture.view);
    QVERIFY(before.valid());
    const qreal offset = rulerPlotOffset(fixture.view);
    const QRgb backdrop = before.at(offset + fixture.view.camera().leadPadPx() + 80.0, 2.0);
    std::array<int, 6> fallbackBars{};
    std::array<double, 8> beats{};
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * kBeatsPerBar * kTicksPerBeat;
        fallbackBars[size_t(bar)] = detectedLine(
            before,
            before.deviceX(fixture.view.camera().displayX(double(tick), offset, before.dpr)),
            int(before.image.height() * .55), before.image.height() - 3, backdrop);
    }
    for (int beat = 1; beat <= 8; ++beat)
        beats[size_t(beat - 1)] = fixture.view.camera().contentX(double(beat * kTicksPerBeat));
    const int height = rulerBandHeight(fixture.view);
    fixture.view.setSong(&fixture.t34, nullptr);
    QCoreApplication::processEvents();
    const songview::Grid::Segment segment = fixture.view.grid().segmentAt(0);
    QCOMPARE(segment.start, uint64_t(0));
    QCOMPARE(segment.next, UINT64_MAX);
    QCOMPARE(segment.beatTicks, kTicksPerBeat);
    QCOMPARE(segment.beatsPerBar, 3);
    QCOMPARE(rulerBandHeight(fixture.view), height);
    QVERIFY(fixture.view.camera().leadPadPx() > 0.0);
    for (int beat = 1; beat <= 8; ++beat)
        QVERIFY(std::abs(fixture.view.camera().contentX(double(beat * kTicksPerBeat)) -
                         beats[size_t(beat - 1)]) <= 1e-6);
    const Raster after = captureRuler(fixture.view);
    QVERIFY(after.valid());
    bool moved = false;
    for (int bar = 0; bar < 6; ++bar) {
        const uint64_t tick = uint64_t(bar) * 3 * kTicksPerBeat;
        const int expected =
            after.deviceX(fixture.view.camera().displayX(double(tick), offset, after.dpr));
        const int line = detectedLine(after, expected, int(after.image.height() * .55),
                                      after.image.height() - 3, backdrop);
        QVERIFY(line >= 0);
        QVERIFY(std::abs(line - expected) <= 1);
        moved = moved || line != fallbackBars[size_t(bar)];
    }
    QVERIFY2(moved, "3/4 binding did not move the signature-dependent bar lines");
}

} // namespace checks::rollcheck::staticcheck
