#include "tst_swiftrollbench.h"

#include "checks/selectionkey/session.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timecamera.h"

#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QPoint>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QString>
#include <QWheelEvent>

#include <algorithm>
#include <array>
#include <cstddef>
#include <utility>
#include <vector>

#include <QtTest/QTest>

// Frame-cost bench for whichever roll the build mounts: the Swift overlay when
// the Swift grid is compiled in, the C++ roll otherwise. The flavor is
// detected at runtime from the overlay item, so one harness measures both and
// the two runs are directly comparable. Each phase prints one SWIFTROLLBENCH
// line; the timing numbers are the deliverable, the assertions only prove the
// cadence really drove the roll (window active, frames flowed, the roll's
// viewport or camera moved).
namespace {

constexpr int kWheelNotch = 120;
constexpr int kScrollIterations = 120;
constexpr int kZoomIterations = 60;
constexpr int kPaceMs = 16;
constexpr int kSettleMs = 250;
constexpr int kWarmupDeadlineMs = 5000;
constexpr int kMinimumFramesPerPhase = 24;

// Frame stamps for the measured phases. The probe is a queued connection so
// every stamp lands on the GUI thread (the playhead-quick frame-probe
// precedent); stamps accumulate only while a phase is recording.
struct FrameStamps {
    QElapsedTimer clock;
    std::vector<qint64> stamps;
    bool recording = false;
};

struct PhaseStats {
    int frames = 0;
    qint64 medianUs = 0;
    qint64 p95Us = 0;
    qint64 maxUs = 0;
};

// Sorted consecutive-stamp deltas: median, p95, and max in microseconds.
PhaseStats summarize(const std::vector<qint64> &stamps)
{
    PhaseStats stats;
    stats.frames = static_cast<int>(stamps.size());
    if (stamps.size() < 2)
        return stats;
    std::vector<qint64> deltas;
    deltas.reserve(stamps.size() - 1);
    for (std::size_t i = 1; i < stamps.size(); ++i)
        deltas.push_back(stamps[i] - stamps[i - 1]);
    std::sort(deltas.begin(), deltas.end());
    const auto at = [&deltas](std::size_t index) {
        return deltas[std::min(index, deltas.size() - 1)];
    };
    stats.medianUs = at(deltas.size() / 2) / 1000;
    stats.p95Us = at(deltas.size() * 95 / 100) / 1000;
    stats.maxUs = deltas.back() / 1000;
    return stats;
}

// Flavor-neutral movement token: the scalars a wheel cadence can move. The
// Swift roll moves the overlay viewport's content offsets; the C++ roll moves
// the SongView camera (plain wheel zooms the timeline, Ctrl+wheel zooms the
// key height, Shift and horizontal wheels pan).
using MovementToken = std::array<double, 4>;

MovementToken movementToken(const SongView &view, const QQuickItem *swiftViewport)
{
    if (swiftViewport) {
        return {swiftViewport->property("contentX").toDouble(),
                swiftViewport->property("contentY").toDouble(), 0.0, 0.0};
    }
    const songview::TimeCamera &camera = view.camera();
    return {camera.pxPerBeat(), camera.scrollX(), camera.scrollY(), camera.keyHeight()};
}

void sendWheel(QQuickWindow &window, const QPointF &scenePos, int angleY,
               Qt::KeyboardModifiers modifiers)
{
    const QPoint globalPos = window.mapToGlobal(scenePos.toPoint());
    QWheelEvent wheel(scenePos, globalPos, QPoint(), QPoint(0, angleY), Qt::NoButton, modifiers,
                      Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(&window, &wheel);
}

struct PhaseResult {
    PhaseStats stats;
    bool moved = false;
};

} // namespace

SwiftRollBenchTest::SwiftRollBenchTest(QString projectRoot, QString song)
    : m_projectRoot(std::move(projectRoot))
    , m_song(std::move(song))
{}

void SwiftRollBenchTest::initTestCase()
{
    qputenv("PORYDAW_AUDIO_BACKEND", "null");
}

void SwiftRollBenchTest::testScrollZoomFrameCadence()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_song, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    songview::TimelineQuickView *const quickView = view.quickView();
    QVERIFY(quickView != nullptr);
    QQuickWindow *const quickWin = quickView->quickWindow();
    QVERIFY(quickWin != nullptr);
    // The embedded Quick window is a child window: it is exposed with the
    // shell and inherits the shell's active state, so both gates resolve
    // without a band focus request.
    QVERIFY2(QTest::qWaitForWindowExposed(quickWin), "the Quick window must be exposed");
    QVERIFY2(QTest::qWaitForWindowActive(quickWin),
             "the Quick window must be active before the cadence is timed");

    // Runtime flavor detection: the overlay is mounted only when the Swift
    // grid is compiled in, so the same harness measures either roll.
    QQuickItem *const overlay =
        quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    const QString roll = overlay ? QStringLiteral("swift") : QStringLiteral("cpp");
    QQuickItem *const swiftViewport =
        overlay ? overlay->findChild<QQuickItem *>(QStringLiteral("swiftRollViewport")) : nullptr;
    QVERIFY2(!overlay || swiftViewport != nullptr,
             "the Swift roll overlay must expose its viewport item");

    QQuickItem *const root = quickView->rootObject();
    QVERIFY(root != nullptr);
    const QRectF rollBand = root->property("rollBandRect").toRectF();
    QVERIFY2(rollBand.isValid() && !rollBand.isEmpty(),
             "the roll band rect must be published before the cadence");
    const QPointF rollCenter = root->mapToScene(rollBand.center());

    FrameStamps stamps;
    stamps.clock.start();
    QObject frameProbe;
    QObject::connect(
        quickWin, &QQuickWindow::frameSwapped, &frameProbe,
        [&stamps] {
            if (stamps.recording)
                stamps.stamps.push_back(stamps.clock.nsecsElapsed());
        },
        Qt::QueuedConnection);

    // Warm-up: one swapped frame proves the render loop is live before the
    // measured phases; the stamps collected here are discarded.
    stamps.recording = true;
    quickWin->update();
    QElapsedTimer warmup;
    warmup.start();
    while (stamps.stamps.empty() && warmup.elapsed() < kWarmupDeadlineMs)
        QTest::qWait(10);
    QVERIFY2(!stamps.stamps.empty(), "the Quick window must swap a frame before the cadence");
    stamps.stamps.clear();

    // One phase of paced wheel notches. The notch direction alternates: a
    // single-direction cadence saturates the roll's scroll/zoom clamp within a
    // handful of notches (the Swift viewport reaches its content bound, the
    // C++ camera its zoom limit), after which the roll publishes no scene
    // update at all and the phase would time an idle window instead of frame
    // cost. Alternating keeps every iteration a real update in both flavors.
    const auto runPhase = [&](int iterations, Qt::KeyboardModifiers modifiers) {
        PhaseResult result;
        MovementToken previous = movementToken(view, swiftViewport);
        stamps.stamps.clear();
        stamps.recording = true;
        for (int i = 0; i < iterations; ++i) {
            sendWheel(*quickWin, rollCenter, i % 2 == 0 ? -kWheelNotch : kWheelNotch, modifiers);
            QTest::qWait(kPaceMs);
            const MovementToken current = movementToken(view, swiftViewport);
            result.moved = result.moved || current != previous;
            previous = current;
        }
        stamps.recording = false;
        // Settle after the cadence: the tail frames are not part of the
        // measured cadence, and the last notch's effect must land before the
        // next phase starts.
        QTest::qWait(kSettleMs);
        result.stats = summarize(stamps.stamps);
        return result;
    };

    const PhaseResult scroll = runPhase(kScrollIterations, Qt::NoModifier);
    const PhaseResult zoom = runPhase(kZoomIterations, Qt::ControlModifier);

    const auto report = [&roll](const char *phase, const PhaseResult &result) {
        qInfo().noquote() << QStringLiteral(
                                 "SWIFTROLLBENCH roll=%1 phase=%2 frames=%3 median_us=%4 "
                                 "p95_us=%5 max_us=%6 viewport_moved=%7")
                                 .arg(roll)
                                 .arg(QString::fromLatin1(phase))
                                 .arg(result.stats.frames)
                                 .arg(result.stats.medianUs)
                                 .arg(result.stats.p95Us)
                                 .arg(result.stats.maxUs)
                                 .arg(result.moved ? 1 : 0);
    };
    report("scroll", scroll);
    report("zoom", zoom);

    QVERIFY2(scroll.stats.frames >= kMinimumFramesPerPhase,
             "the scroll cadence must swap at least 24 frames");
    QVERIFY2(zoom.stats.frames >= kMinimumFramesPerPhase,
             "the zoom cadence must swap at least 24 frames");
    QVERIFY2(scroll.moved, "the scroll cadence must move the active roll's viewport");
    QVERIFY2(zoom.moved, "the zoom cadence must move the active roll's viewport");
}

int runSwiftRollBenchCheck(const QString &projectRoot, const QString &song,
                           const QStringList &qtArguments)
{
    SwiftRollBenchTest test(projectRoot, song);
    QStringList arguments = {QStringLiteral("swiftrollbench")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
