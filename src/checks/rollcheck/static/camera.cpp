#include "checks/rollcheck/static/tst_pianorollstatic.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QtTest>

#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include "checks/rollcheck/static/fixtures.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/songdocument.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::rollcheck::staticcheck {
namespace {

int keyAt(const SongView &view, qreal y)
{
    const qreal dpr = view.quickView() ? view.quickView()->quickDevicePixelRatio() : 1.0;
    for (int row = 0; row < 128; ++row) {
        const qreal edge =
            std::round((double(row + 1) * view.camera().keyHeight() - view.camera().scrollY()) *
                       dpr) /
            dpr;
        if (y < edge)
            return 127 - row;
    }
    return 0;
}

qreal rowCenter(const SongView &view, int key)
{
    const qreal dpr = view.quickView() ? view.quickView()->quickDevicePixelRatio() : 1.0;
    const auto edge = [&view, dpr](int row) {
        return std::round((double(row) * view.camera().keyHeight() - view.camera().scrollY()) *
                          dpr) /
               dpr;
    };
    return std::floor((edge(127 - key) + edge(128 - key)) / 2.0);
}

void wheel(songview::TimelineInputItem &input, const QPointF &position, QPoint pixel, QPoint angle,
           Qt::KeyboardModifiers modifiers = Qt::NoModifier,
           Qt::ScrollPhase phase = Qt::NoScrollPhase)
{
    checks::events::sendWheel(input, position, pixel, angle, Qt::NoButton, modifiers, phase, false);
}
} // namespace

PianoRollStaticTest::PianoRollStaticTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

void PianoRollStaticTest::tickRangeRejectsInvalidBounds()
{
    using songview::detail::tickRange;
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double infinity = std::numeric_limits<double>::infinity();
    QVERIFY(tickRange(nan, 100.0).empty());
    QVERIFY(tickRange(0.0, nan).empty());
    QVERIFY(tickRange(infinity, 100.0).empty());
    QVERIFY(tickRange(0.0, -infinity).empty());
    QVERIFY(tickRange(-64.0, -1.0).empty());
    QVERIFY(tickRange(48.0, 48.0).empty());
    QVERIFY(tickRange(64.0, 32.0).empty());
    QVERIFY(tickRange(1.0, 0x1p64).empty());
    QVERIFY(tickRange(0x1p64, 0x1p64 + 4096.0).empty());
    QVERIFY(tickRange(1.0, std::numeric_limits<double>::max()).empty());
    const songview::detail::TickRange clipped = tickRange(-24.0, 72.5);
    QCOMPARE(clipped.begin, uint64_t(0));
    QCOMPARE(clipped.end, uint64_t(72));
    const songview::detail::TickRange fractional = tickRange(96.75, 289.25);
    QCOMPARE(fractional.begin, uint64_t(96));
    QCOMPARE(fractional.end, uint64_t(289));
    const double largestBelowCeiling = std::nextafter(double(CoreTimeDefaults::kNoTick), 0.0);
    QCOMPARE(tickRange(0.0, largestBelowCeiling).end, Tick(largestBelowCeiling));
    QCOMPARE(tickRange(double(CoreTimeDefaults::kMaxTick) - 2048.0,
                       double(CoreTimeDefaults::kMaxTick) - 1024.0)
                 .begin,
             CoreTimeDefaults::kMaxTick - 2048);
}

void PianoRollStaticTest::tickRangeWalksFractionalLattice()
{
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    const SongView::ViewState original = view.viewState();
    SongView::ViewState zoomed = original;
    zoomed.pxPerBeat = 384.0;
    zoomed.gridMinDenom = 0;
    view.applyViewState(zoomed);
    const songview::Grid::Segment segment = view.grid().segmentAt(96);
    QVERIFY(segment.start <= 96);
    QVERIFY(segment.next >= 289);
    const Tick lattice = view.grid().gridTicksAt(96);
    QVERIFY(lattice > 0);
    QVERIFY(lattice < segment.beatTicks);
    std::vector<Tick> expected;
    const Tick first = segment.start + (96 - segment.start + lattice - 1) / lattice * lattice;
    for (Tick tick = first; tick < 289; tick += lattice)
        if ((tick - segment.start) % segment.beatTicks != 0)
            expected.push_back(tick);
    std::vector<Tick> observed;
    songview::detail::forEachSubGridLine(view.grid(), view.camera(),
                                         songview::detail::tickRange(96.75, 289.25), 1,
                                         [&observed](Tick tick, int) { observed.push_back(tick); });
    QCOMPARE(observed, expected);
    std::vector<Tick> rejected;
    songview::detail::forEachSubGridLine(
        view.grid(), view.camera(),
        songview::detail::tickRange(std::numeric_limits<double>::quiet_NaN(), 100.0), 1,
        [&rejected](Tick tick, int) { rejected.push_back(tick); });
    QVERIFY(rejected.empty());
    // Boundary scenarios on a coarser lattice: gridMinDenom=16 keeps the
    // drawn sub-grid above the clock floor at any cell-width threshold, so
    // the stride is a nontrivial divisor of the 24-tick beat. The snap grid
    // runs one ladder step finer (8 divisions), which also stays nontrivial:
    // gcd(6, 3) = 3 ticks. (Denom=32 would cap the drawn grid at 3 ticks and
    // collapse the snap stride to the 1-tick clock floor.)
    SongView::ViewState coarse = original;
    coarse.pxPerBeat = 192.0;
    coarse.gridMinDenom = 16;
    view.applyViewState(coarse);
    const Tick latticeG = view.grid().gridTicksAt(0);
    const Tick snapG = view.grid().snapTicksAt(0);
    QVERIFY(latticeG > 1);
    QVERIFY(latticeG < segment.beatTicks);
    QVERIFY(96 % latticeG == 0);
    QVERIFY(snapG >= 3);
    QVERIFY(segment.beatTicks % snapG == 0);
    QCOMPARE(view.grid().fineGridTicks(), Tick(1));
    // Collects the walked ticks; a callback outside the half-open range
    // aborts the walk so a wrapped candidate cannot accumulate callbacks
    // (a missing advancement stays bounded by the harness timeout).
    struct OutOfRangeTick {};
    const auto walk = [&view](Tick begin, Tick end) {
        std::vector<Tick> ticks;
        songview::detail::forEachSubGridLine(view.grid(), view.camera(),
                                             songview::detail::TickRange{begin, end}, 1,
                                             [&ticks, begin, end](Tick tick, int) {
                                                 if (tick < begin || tick >= end)
                                                     throw OutOfRangeTick{};
                                                 ticks.push_back(tick);
                                             });
        return ticks;
    };
    // Independent membership expectation: every in-range tick on its
    // governing segment's sub-beat lattice that is not a beat line.
    const auto expectedLines = [&view](Tick begin, Tick end) {
        std::vector<Tick> ticks;
        for (Tick tick = begin; tick < end; ++tick) {
            const songview::Grid::Segment s = view.grid().segmentAt(tick);
            const Tick step = view.grid().gridTicksAt(tick);
            if (step > 0 && step < s.beatTicks && (tick - s.start) % step == 0 &&
                (tick - s.start) % s.beatTicks != 0 &&
                view.camera().pxPerTick() * double(s.beatTicks) >= 1)
                ticks.push_back(tick);
        }
        return ticks;
    };
    // The first ceiling-aligned candidate (96 + latticeG) already lies at
    // or beyond the range end: the segment contributes nothing.
    const std::vector<Tick> firstOutside = walk(97, 98);
    QVERIFY2(firstOutside.empty(), "a first aligned candidate past the range end must be skipped");
    // The first candidate is the beat line at 96: only its callback is
    // skipped; the walk still advances through the rest of the range.
    QCOMPARE(walk(95, 110), expectedLines(95, 110));
    // The terminal range ends mid-cell (kMaxTick is not on the lattice):
    // the last advancement must break instead of striding past the end.
    QCOMPARE(walk(CoreTimeDefaults::kMaxTick - 9, CoreTimeDefaults::kMaxTick),
             expectedLines(CoreTimeDefaults::kMaxTick - 9, CoreTimeDefaults::kMaxTick));
    const std::vector<Tick> ceilingCell =
        walk(CoreTimeDefaults::kMaxTick - 1, CoreTimeDefaults::kMaxTick);
    QVERIFY2(ceilingCell.empty(), "a ceiling-aligned candidate past kMaxTick must not wrap");
    // Snap inputs: NaN and non-positive values map to 0, infinities clamp
    // to the corresponding endpoint (down lands on the lattice below it).
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double infinity = std::numeric_limits<double>::infinity();
    QCOMPARE(view.grid().snapTick(nan), Tick(0));
    QCOMPARE(view.grid().snapTickDown(nan), Tick(0));
    QCOMPARE(view.grid().snapTickUp(nan), Tick(0));
    QCOMPARE(view.grid().snapTick(-infinity), Tick(0));
    QCOMPARE(view.grid().snapTick(infinity), CoreTimeDefaults::kMaxTick);
    QCOMPARE(view.grid().snapTickDown(infinity), Tick(CoreTimeDefaults::kMaxTick / snapG * snapG));
    QCOMPARE(view.grid().snapTickUp(infinity), CoreTimeDefaults::kMaxTick);
    QCOMPARE(view.grid().snapTick(infinity, true), CoreTimeDefaults::kMaxTick);
    // Fractional nearest tie on either side of the midpoint: the lower
    // candidate wins exactly at the tie.
    QCOMPARE(view.grid().snapTick(96.0 + snapG / 2.0), Tick(96));
    QCOMPARE(view.grid().snapTick(96.0 + snapG / 2.0 - 0.25), Tick(96));
    QCOMPARE(view.grid().snapTick(96.0 + snapG / 2.0 + 0.25), Tick(96 + snapG));
    QCOMPARE(view.grid().snapTickDown(96.0 + snapG / 2.0 + 0.25), Tick(96));
    QCOMPARE(view.grid().snapTickUp(96.0 + snapG / 2.0 - 0.25), Tick(96 + snapG));
    // Coarse up/nearest at the domain edge saturate at kMaxTick instead of
    // wrapping the lo + g candidate; down stays on the lattice.
    QCOMPARE(view.grid().snapTickUp(double(CoreTimeDefaults::kMaxTick) - 0.5),
             CoreTimeDefaults::kMaxTick);
    QCOMPARE(view.grid().snapTick(double(CoreTimeDefaults::kMaxTick) - 0.5),
             CoreTimeDefaults::kMaxTick);
    QCOMPARE(view.grid().snapTickDown(double(CoreTimeDefaults::kMaxTick) - 0.5),
             Tick((CoreTimeDefaults::kMaxTick - 1) / snapG * snapG));
    // Fine snap rounds on the clock grid; a rounded result past the domain
    // saturates through tickFromDouble instead of producing the sentinel.
    QCOMPARE(view.grid().snapTick(double(CoreTimeDefaults::kMaxTick) + 0.6, true),
             CoreTimeDefaults::kMaxTick);
    QCOMPARE(view.grid().snapTick(double(CoreTimeDefaults::kMaxTick) - 0.4, true),
             CoreTimeDefaults::kMaxTick);
    QCOMPARE(view.grid().snapTick(1e30, true), CoreTimeDefaults::kMaxTick);
    // A mid-cell signature change re-anchors the lattice: the first
    // segment's walk stops at the seam (its next candidate lies at the
    // segment end), and the new segment restarts its own lattice and
    // beat-line omission from its start.
    fixture.tab()->document().setTimeSig(102, 4, 2);
    QTRY_VERIFY(view.grid().segmentAt(102).start == 102);
    QCOMPARE(view.grid().segmentAt(101).next, Tick(102));
    QCOMPARE(walk(95, 130), expectedLines(95, 130));
    QCOMPARE(walk(100, 110), expectedLines(100, 110));
    QCOMPARE(view.grid().snapTickDown(103.5), Tick(102));
    QCOMPARE(view.grid().snapTickUp(101.5), Tick(102));
    QCOMPARE(view.grid().snapTick(103.5), Tick(102));
    QCOMPARE(view.grid().snapTick(103.5 + double(snapG)), Tick(102 + snapG));
    fixture.tab()->document().deleteTimeSig(102);
    QTRY_VERIFY(view.grid().segmentAt(102).start == segment.start);
    view.applyViewState(original);
}

void PianoRollStaticTest::verticalCameraWheelContract()
{
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    auto &roll = *fixture.rollInput();
    const SongView::ViewState original = view.viewState();
    SongView::ViewState state = original;
    state.keyHeight = 8.0;
    state.scrollY = 300.0;
    view.applyViewState(state);
    const QPointF anchor(40.0, 200.0);
    for (int index = 0; index < 4; ++index)
        wheel(roll, anchor, {}, {0, 30}, Qt::ControlModifier);
    const double partialHeight = view.camera().keyHeight();
    const double partialScroll = view.camera().scrollY();
    view.applyViewState(state);
    wheel(roll, anchor, {}, {0, 120}, Qt::ControlModifier);
    QVERIFY(std::abs(view.camera().keyHeight() - partialHeight) <= 1e-12);
    QVERIFY(std::abs(view.camera().scrollY() - partialScroll) <= 1e-10);
    const double settledHeight = view.camera().keyHeight();
    const double settledScroll = view.camera().scrollY();
    wheel(roll, anchor, {}, {0, 120}, Qt::ControlModifier, Qt::ScrollMomentum);
    QVERIFY(std::abs(view.camera().keyHeight() - settledHeight) <= 1e-12);
    QVERIFY(std::abs(view.camera().scrollY() - settledScroll) <= 1e-10);
    view.applyViewState(state);
    const double row = (anchor.y() + view.camera().scrollY()) / view.camera().keyHeight();
    wheel(roll, anchor, {}, {0, 30}, Qt::ControlModifier);
    QVERIFY(std::abs((anchor.y() + view.camera().scrollY()) / view.camera().keyHeight() - row) <=
            1e-12);
    view.applyViewState(state);
    for (int index = 0; index < 10; ++index)
        wheel(roll, anchor, {}, {0, 120}, Qt::ControlModifier);
    QVERIFY(std::abs(view.camera().keyHeight() - 16.0) <= 1e-12);
    view.applyViewState(state);
    wheel(roll, anchor, {0, 240}, {}, Qt::ControlModifier);
    QVERIFY(std::abs(view.camera().keyHeight() - 16.0) <= 1e-12);
    const double keyboardScroll = view.camera().scrollY();
    wheel(*fixture.gutterInput(), {fixture.gutterInput()->bounds().width() - 1.0, anchor.y()},
          {0, 1}, {});
    QVERIFY(std::abs(view.camera().scrollY() - (keyboardScroll - 0.5)) <= 1e-12);
    view.applyViewState(state);
    for (int index = 0; index < 4; ++index)
        wheel(roll, anchor, {}, {0, 30}, Qt::ControlModifier);
    for (int index = 0; index < 4; ++index)
        wheel(roll, anchor, {}, {0, -30}, Qt::ControlModifier);
    QVERIFY(std::abs(view.camera().keyHeight() - state.keyHeight) <= 1e-12);
    QVERIFY(std::abs(view.camera().scrollY() - state.scrollY) <= 1e-10);
    state.keyHeight = 9.375;
    state.scrollY = 257.625;
    view.applyViewState(state);
    QCOMPARE(view.viewState().keyHeight, state.keyHeight);
    QCOMPARE(view.viewState().scrollY, state.scrollY);
    const int boundaryRow = 40;
    const qreal dpr = fixture.rollInput()->devicePixelRatio();
    const qreal boundary =
        std::round((boundaryRow * view.camera().keyHeight() - view.camera().scrollY()) * dpr) / dpr;
    checks::events::sendMouse(*fixture.gutterInput(), QEvent::MouseMove,
                              QPointF(4.0, boundary - .25), Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QCOMPARE(fixture.roll()->property("hoverKey").toInt(), 128 - boundaryRow);
    checks::events::sendMouse(*fixture.gutterInput(), QEvent::MouseMove,
                              QPointF(4.0, boundary + .25), Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QCOMPARE(fixture.roll()->property("hoverKey").toInt(), 127 - boundaryRow);
    state.keyHeight = 11.0;
    state.scrollY = 217.0;
    view.applyViewState(state);
    QCOMPARE(view.viewState().keyHeight, 11.0);
    QCOMPARE(view.viewState().scrollY, 217.0);
    view.applyViewState(original);
}

void PianoRollStaticTest::horizontalCameraWheelContract()
{
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    auto &roll = *fixture.rollInput();
    const SongView::ViewState original = view.viewState();
    SongView::ViewState state = original;
    state.pxPerBeat = 500.125;
    state.scrollPx = 23.625;
    const QPointF anchor(73.375, 200.0);
    view.applyViewState(state);
    for (int index = 0; index < 4; ++index)
        wheel(roll, anchor, {}, {0, 30});
    const double partialScale = view.camera().pxPerBeat();
    const double partialScroll = view.camera().scrollX();
    view.applyViewState(state);
    wheel(roll, anchor, {}, {0, 120});
    QVERIFY(std::abs(view.camera().pxPerBeat() - state.pxPerBeat * std::pow(1.0015, 120.0)) <=
            1e-10);
    QVERIFY(std::abs(view.camera().pxPerBeat() - partialScale) <= 1e-12);
    QVERIFY(std::abs(view.camera().scrollX() - partialScroll) <= 1e-9);
    const double fullScale = view.camera().pxPerBeat();
    const double fullScroll = view.camera().scrollX();
    view.applyViewState(state);
    wheel(roll, anchor, {0, 24}, {});
    QVERIFY(std::abs(view.camera().pxPerBeat() - fullScale) <= 1e-12);
    QVERIFY(std::abs(view.camera().scrollX() - fullScroll) <= 1e-9);
    view.applyViewState(state);
    const double horizontalScroll = view.camera().scrollX();
    const double horizontalScale = view.camera().pxPerBeat();
    wheel(roll, anchor, {8, 0}, {});
    QVERIFY(std::abs(view.camera().scrollX() - (horizontalScroll - 8.0)) <= 1e-12);
    QVERIFY(std::abs(view.camera().pxPerBeat() - horizontalScale) <= 1e-12);
    view.applyViewState(state);
    const double tick = view.camera().tickAtContentX(anchor.x());
    wheel(roll, anchor, {}, {0, 30});
    QVERIFY(std::abs(view.camera().tickAtContentX(anchor.x()) - tick) <= 1e-9);
    view.applyViewState(state);
    for (int index = 0; index < 4; ++index)
        wheel(roll, anchor, {}, {0, 30});
    for (int index = 0; index < 4; ++index)
        wheel(roll, anchor, {}, {0, -30});
    QVERIFY(std::abs(view.camera().pxPerBeat() - state.pxPerBeat) <= 1e-10);
    QVERIFY(std::abs(view.camera().scrollX() - state.scrollPx) <= 1e-9);
    state.pxPerBeat = 311.375;
    state.scrollPx = 47.625;
    view.applyViewState(state);
    QCOMPARE(view.viewState().pxPerBeat, state.pxPerBeat);
    QCOMPARE(view.viewState().scrollPx, state.scrollPx);
    view.applyViewState(original);
}

void PianoRollStaticTest::affineCameraProjection_data()
{
    QTest::addColumn<double>("pxPerBeat");
    QTest::addColumn<double>("scrollPx");
    QTest::newRow("low") << 37.125 << .375;
    QTest::newRow("fractional") << 37.375 << 13.625;
    QTest::newRow("high") << 512.5 << 71.3125;
}

void PianoRollStaticTest::affineCameraProjection()
{
    QFETCH(double, pxPerBeat);
    QFETCH(double, scrollPx);
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    const SongView::ViewState original = view.viewState();
    SongView::ViewState state = original;
    state.pxPerBeat = pxPerBeat;
    state.scrollPx = scrollPx;
    state.gridMinDenom = 0;
    view.applyViewState(state);
    const qreal visibleWidth = fixture.rollInput()->bounds().width();
    const double affineTick = view.camera().tickAtContentX(visibleWidth * 0.371) + 0.375;
    QVERIFY(std::abs(view.camera().tickAtContentX(view.camera().contentX(affineTick)) -
                     affineTick) <= 1e-9);
    Tick tick = view.grid().snapTickUp(std::max(0.0, view.camera().tickAtContentX(0.0)));
    int visible = 0;
    for (int guard = 0; guard < 10000; ++guard) {
        const qreal x = view.camera().contentX(double(tick));
        if (x > visibleWidth)
            break;
        if (x >= 0.0) {
            ++visible;
            for (const qreal origin : {0.0, .25}) {
                for (const qreal dpr : {1.0, 2.0}) {
                    const qreal displayed = view.camera().displayX(double(tick), origin, dpr);
                    QCOMPARE(displayed, std::round((origin + x) * dpr) / dpr);
                    QCOMPARE(view.grid().snapTick(view.camera().tickAtContentX(displayed - origin)),
                             tick);
                }
            }
        }
        const Tick next = view.grid().snapTickUp(double(tick) + 1.0);
        QVERIFY(next > tick);
        tick = next;
    }
    QVERIFY(visible >= 2);
    view.applyViewState(original);
}

void PianoRollStaticTest::cameraRangeAndPreRollRaster()
{
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    auto &roll = *fixture.rollInput();
    const SongView::ViewState original = view.viewState();
    const double pad = view.camera().leadPadPx();
    QVERIFY(pad > 0.0);
    SongView::ViewState state = original;
    state.scrollPx = -1e9;
    view.applyViewState(state);
    QVERIFY(std::abs(view.camera().scrollX() + pad) <= 1e-9);
    state.scrollPx = 1e9;
    view.applyViewState(state);
    QVERIFY(std::abs(view.camera().scrollX() - double(fixture.tab()->timeline()->lengthTicks) *
                                                   view.camera().pxPerTick()) <= 1e-9);
    view.goToStart();
    QVERIFY(std::abs(view.camera().scrollX() + pad) <= 1e-9);
    QCOMPARE(view.editCursorTick(), uint64_t(0));
    state.scrollPx = 0.0;
    view.applyViewState(state);
    state.scrollPx = -pad;
    view.applyViewState(state);
    const auto rollBand = view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(rollBand.has_value());
    const QImage raster = checks::support::captureQuickBand(view, rollBand->rect);
    QVERIFY(!raster.isNull());
    const qreal dpr = raster.devicePixelRatio();
    QVERIFY(dpr > 0.0);
    const auto isBlackKey = [](int key) {
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
    };
    const int midKey = keyAt(view, roll.bounds().height() / 2.0);
    int naturalKey = -1;
    int accidentalKey = -1;
    for (int key = midKey - 4; key <= midKey + 4; ++key) {
        if (key < 0 || key > 127 || rowCenter(view, key) < 0 ||
            rowCenter(view, key) >= roll.bounds().height())
            continue;
        (isBlackKey(key) ? accidentalKey : naturalKey) = key;
    }
    QVERIFY(naturalKey >= 0);
    QVERIFY(accidentalKey >= 0);
    const qreal plotOffset = rollBand->plotRect.x() - rollBand->rect.x();
    const auto pixel = [&raster, dpr](qreal x, qreal y) {
        return raster.pixel(qRound(x * dpr), qRound(y * dpr));
    };
    const QRgb padNatural = pixel(plotOffset + pad / 2.0, rowCenter(view, naturalKey));
    const QRgb padAccidental = pixel(plotOffset + pad / 2.0, rowCenter(view, accidentalKey));
    const QRgb plainNatural = pixel(plotOffset + pad + 20.0, rowCenter(view, naturalKey));
    QCOMPARE(padNatural, padAccidental);
    QVERIFY(padNatural != plainNatural);
    state.scrollPx = 0.0;
    view.applyViewState(state);
    wheel(roll, {40.0, 200.0}, {8, 0}, {});
    QVERIFY(std::abs(view.camera().scrollX() + 8.0) <= 1e-12);
    state.scrollPx = -pad / 2.0;
    view.applyViewState(state);
    QVERIFY(std::abs(view.viewState().scrollPx + pad / 2.0) <= 1e-12);
    view.applyViewState(original);
}

void PianoRollStaticTest::scratchSpaceDrawGrowsTimeline()
{
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    SongDocument &document = fixture.tab()->document();
    auto &roll = *fixture.rollInput();
    const SongView::ViewState original = view.viewState();
    const Tick length = fixture.tab()->timeline()->lengthTicks;
    const QByteArray bytes = document.smf().write();
    const int undo = document.undoStack()->index();
    SongView::ViewState state = original;
    state.scrollPx = 1e9;
    view.applyViewState(state);
    const Tick tick =
        view.grid().snapTickDown(view.camera().tickAtContentX(roll.bounds().width() / 2.0));
    const int key = keyAt(view, roll.bounds().height() / 2.0);
    const qreal begin = view.camera().contentX(double(tick));
    const qreal end = view.camera().contentX(double(tick + view.grid().snapTicksAt(tick)));
    checks::events::sendMouse(roll, QEvent::MouseButtonDblClick,
                              QPointF((begin + end) / 2.0, rowCenter(view, key)), Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(roll, QEvent::MouseButtonRelease,
                              QPointF((begin + end) / 2.0, rowCenter(view, key)), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote note;
    QVERIFY(tick >= length);
    QVERIFY(document.findNote(fixture.track(), tick, uint8_t(key), &note));
    QVERIFY(fixture.tab()->timeline()->lengthTicks > length);
    while (document.undoStack()->index() > undo && document.undoStack()->canUndo())
        document.undoStack()->undo();
    QCOMPARE(document.smf().write(), bytes);
    view.applyViewState(original);
}

void PianoRollStaticTest::keyboardGutterHoverTracksRows()
{
    CameraFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    SongView &view = *fixture.view();
    auto &gutter = *fixture.gutterInput();
    const int y = int(gutter.bounds().height()) / 2;
    const int expected = keyAt(view, y);
    checks::events::sendMouse(gutter, QEvent::MouseMove, QPointF(4.0, y), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QCOMPARE(fixture.roll()->property("hoverKey").toInt(), expected);
    checks::events::sendMouse(gutter, QEvent::MouseMove,
                              QPointF(4.0, rowCenter(view, expected - 1)), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QCOMPARE(fixture.roll()->property("hoverKey").toInt(), expected - 1);
    checks::events::sendMouse(gutter, QEvent::Leave, QPointF(4.0, y), Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QCOMPARE(fixture.roll()->property("hoverKey").toInt(), -1);
}

} // namespace checks::rollcheck::staticcheck
