#include "checks/automation/raster/tst_automationraster.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QtTest>

#include <QAbstractItemModel>
#include <QByteArray>
#include <QColor>
#include <QGuiApplication>
#include <QImage>
#include <QQuickItem>
#include <QStringList>
#include <QUndoStack>
#include <QtGlobal>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

enum class AdapterKind { Tempo, Cc };

struct HoverCase {
    AdapterKind kind;
    const char *name;
};

struct PreparedLane {
    LaneHandle handle;
    QRect body;
    QPointF insertionPosition;
    QPointF nodePosition;
    uint64_t insertionTick = 0;
    qreal insertionX = 0.0;
    qreal heldY = 0.0;
    qreal nodeX = 0.0;
    qreal nodeY = 0.0;
    int heldValue = 0;
    int nodeValue = 0;
    int cursorValue = 0;
};

struct HoverObservation {
    songview::TimelineQuickLayerData layer;
    QImage framebuffer;
    int textRows = 0;
    QString valueText;
    bool chromeVisible = false;
    bool framebufferReady = false;
};

struct DocumentSnapshot {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;

    bool operator==(const DocumentSnapshot &) const = default;
};

constexpr std::array kHoverCases{
    HoverCase{AdapterKind::Tempo, "Tempo"},
    HoverCase{AdapterKind::Cc, "CC"},
};
constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kNodeTick = 144;
constexpr uint64_t kInsertionTick = 96;
constexpr double kHeldBodyFraction = 0.25;
constexpr double kNodeBodyFraction = 0.75;
constexpr double kCursorBodyFraction = 0.50;
DocumentSnapshot snapshot(SongDocument &document)
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

uint32_t tempoUsForBpm(int bpm)
{
    return CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm);
}

int valueAtBodyFraction(int minimum, int maximum, double fractionFromBottom)
{
    return minimum + int(std::lround(double(maximum - minimum) * fractionFromBottom));
}

qreal valueY(const QRect &body, const AutomationGeometry &geometry, int minimum, int maximum,
             int value)
{
    return AutomationProjection::valueY(body, geometry, minimum, maximum, value);
}

HoverObservation observeHover(AutomationRasterFixture &fixture)
{
    HoverObservation observation;
    QString error;
    observation.framebuffer = fixture.renderAutomationViewport(&error);
    observation.framebufferReady = error.isEmpty() && !observation.framebuffer.isNull();
    observation.layer = fixture.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    const QAbstractItemModel *const model = fixture.quickScene().automationHoverTextModel();
    observation.textRows = model->rowCount();
    if (observation.textRows > 0) {
        observation.valueText =
            model->index(0, 0).data(songview::TimelineQuickTextModel::TextRole).toString();
    }
    auto *quickHost = fixture.view().findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    const QQuickItem *const root = quickHost ? quickHost->rootObject() : nullptr;
    const QQuickItem *const chrome =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineQuickAutomationHoverChrome"))
             : nullptr;
    observation.chromeVisible = chrome && chrome->isVisible();
    return observation;
}

bool hasFilledNodeAt(const songview::TimelineQuickLayerData &layer, const QPointF &center)
{
    const qreal tolerance = layout::singlePixel();
    const auto nearCenter = [&](const QPointF &point) {
        const QPointF delta = point - center;
        return delta.x() * delta.x() + delta.y() * delta.y() <= tolerance * tolerance;
    };
    return std::any_of(layer.triangles.cbegin(), layer.triangles.cend(),
                       [&](const songview::TimelineQuickTriangle &triangle) {
                           return nearCenter(triangle.first) || nearCenter(triangle.second) ||
                                  nearCenter(triangle.third);
                       });
}

bool hasAnnulusPixelChanges(const QImage &before, const QImage &after, const QPointF &center,
                            qreal radius, qreal width)
{
    if (before.isNull() || after.isNull() || before.size() != after.size())
        return false;
    const qreal dpr = after.devicePixelRatio();
    if (dpr <= 0.0 || !qFuzzyCompare(before.devicePixelRatio(), dpr))
        return false;

    const qreal tolerance = 2 * layout::singlePixel();
    const qreal inner = std::max<qreal>(0.0, radius - width / 2.0 - tolerance);
    const qreal outer = radius + width / 2.0 + tolerance;
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    const int left = std::max(0, qFloor((center.x() - outer) * dpr));
    const int top = std::max(0, qFloor((center.y() - outer) * dpr));
    const int right = std::min(after.width() - 1, qCeil((center.x() + outer) * dpr));
    const int bottom = std::min(after.height() - 1, qCeil((center.y() + outer) * dpr));
    int changedPixels = 0;
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const QPointF delta((x + 0.5) / dpr - center.x(), (y + 0.5) / dpr - center.y());
            const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
            if (distanceSquared < innerSquared || distanceSquared > outerSquared)
                continue;
            const QColor oldPixel = before.pixelColor(x, y);
            const QColor newPixel = after.pixelColor(x, y);
            const int difference = std::abs(newPixel.alpha() - oldPixel.alpha()) +
                                   std::abs(newPixel.red() - oldPixel.red()) +
                                   std::abs(newPixel.green() - oldPixel.green()) +
                                   std::abs(newPixel.blue() - oldPixel.blue());
            if (newPixel.alpha() >= 32 && difference >= 32 && ++changedPixels == 2)
                return true;
        }
    }
    return false;
}

bool pixelChangedAt(const QImage &before, const QImage &after, const QPointF &point)
{
    if (before.isNull() || after.isNull() || before.size() != after.size())
        return false;
    const qreal dpr = after.devicePixelRatio();
    if (dpr <= 0.0 || !qFuzzyCompare(before.devicePixelRatio(), dpr))
        return false;
    const int x = std::clamp(qRound(point.x() * dpr), 0, after.width() - 1);
    const int y = std::clamp(qRound(point.y() * dpr), 0, after.height() - 1);
    const QColor oldPixel = before.pixelColor(x, y);
    const QColor newPixel = after.pixelColor(x, y);
    return std::abs(newPixel.alpha() - oldPixel.alpha()) +
               std::abs(newPixel.red() - oldPixel.red()) +
               std::abs(newPixel.green() - oldPixel.green()) +
               std::abs(newPixel.blue() - oldPixel.blue()) >=
           32;
}

bool pixelMatchesIdleAt(const QImage &idle, const QImage &cleared, const QPointF &point)
{
    if (idle.isNull() || cleared.isNull() || idle.size() != cleared.size())
        return false;
    const qreal dpr = cleared.devicePixelRatio();
    if (dpr <= 0.0 || !qFuzzyCompare(idle.devicePixelRatio(), dpr))
        return false;
    const int x = std::clamp(qRound(point.x() * dpr), 0, cleared.width() - 1);
    const int y = std::clamp(qRound(point.y() * dpr), 0, cleared.height() - 1);
    const QColor idlePixel = idle.pixelColor(x, y);
    const QColor clearedPixel = cleared.pixelColor(x, y);
    return std::abs(clearedPixel.alpha() - idlePixel.alpha()) <= 8 &&
           std::abs(clearedPixel.red() - idlePixel.red()) <= 8 &&
           std::abs(clearedPixel.green() - idlePixel.green()) <= 8 &&
           std::abs(clearedPixel.blue() - idlePixel.blue()) <= 8;
}

bool isClear(const HoverObservation &observation)
{
    return observation.framebufferReady && observation.layer.rects.empty() &&
           observation.layer.triangles.empty() && observation.textRows == 0 &&
           !observation.chromeVisible;
}

void setTempoPoints(AutomationRasterFixture &fixture, const std::vector<TempoPoint> &points)
{
    TempoEdit edit;
    edit.remove = fixture.document().tempoPoints();
    edit.add = points;
    fixture.document().applyTempoEdit(edit);
    fixture.documentChanged();
}

void setCcPoints(AutomationRasterFixture &fixture,
                 const std::vector<SongDocument::LanePointValue> &points)
{
    fixture.document().writeLanePoints(fixture.pan.track, fixture.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), points);
    fixture.documentChanged();
}

PreparedLane prepareLane(AutomationRasterFixture &fixture, AdapterKind kind)
{
    PreparedLane lane;
    const int minimum = kind == AdapterKind::Tempo ? CoreTimeDefaults::kMinTempoBpm : 0;
    const int maximum = kind == AdapterKind::Tempo ? CoreTimeDefaults::kMaxTempoBpm : 127;
    const int held = valueAtBodyFraction(minimum, maximum, kHeldBodyFraction);
    const int node = valueAtBodyFraction(minimum, maximum, kNodeBodyFraction);
    const int cursor = valueAtBodyFraction(minimum, maximum, kCursorBodyFraction);
    lane.heldValue = held;
    lane.nodeValue = node;
    lane.cursorValue = cursor;
    if (kind == AdapterKind::Tempo) {
        setTempoPoints(fixture,
                       {{kHeldTick, tempoUsForBpm(held)}, {kNodeTick, tempoUsForBpm(node)}});
        lane.handle = AutomationRasterFixture::kTempoHandle;
    } else {
        lane.handle = fixture.handleFor(fixture.pan);
        if (!lane.handle.valid())
            return lane;
        setCcPoints(fixture, {{kHeldTick, held}, {kNodeTick, node}});
    }

    const AutomationGeometry geometry = fixture.geometry();
    const AutomationProjection projection = fixture.projection();
    lane.body = fixture.bodyFor(lane.handle);
    lane.insertionPosition = {projection.displayX(kInsertionTick, fixture.automationDpr()),
                              valueY(lane.body, geometry, minimum, maximum, cursor)};
    lane.heldY = valueY(lane.body, geometry, minimum, maximum, held);
    lane.nodeY = valueY(lane.body, geometry, minimum, maximum, node);
    NodeLaneHoverState insertionProbe(QGuiApplication::font());
    insertionProbe.hover.lane = lane.handle;
    insertionProbe.hover.pos = lane.insertionPosition;
    lane.insertionTick = uint64_t(std::max(0.0, insertionProbe.insertionTick(projection, false)));
    lane.insertionX = projection.displayX(lane.insertionTick, fixture.automationDpr());
    lane.nodeX = projection.displayX(kNodeTick, fixture.automationDpr());
    lane.nodePosition = {lane.nodeX, lane.nodeY};
    return lane;
}

qreal voiceX(const AutomationRasterFixture &fixture, uint64_t tick)
{
    return fixture.view().camera().displayX(double(tick), 0.0,
                                            fixture.voiceInput().devicePixelRatio());
}

QPointF voicePoint(const AutomationRasterFixture &fixture, uint64_t tick)
{
    return {voiceX(fixture, tick), fixture.voiceInput().bounds().center().y()};
}

void seedVoice(AutomationRasterFixture &fixture)
{
    fixture.document().writeLanePoints(0, DOC_CC_VOICE, 0, std::numeric_limits<uint64_t>::max(),
                                       {{24, 5}, {48, 6}});
    fixture.documentChanged();
    fixture.pump();
}

// Direct plot presses drive the canvas's attached fixture host, so the input
// needs no global mapping: left-button phantom drags never consult it.
songview::TimelinePointerInput plotPointer(Qt::MouseButton button, Qt::MouseButtons buttons,
                                           const QPointF &position)
{
    return {.position = position,
            .globalPosition = {},
            .button = button,
            .buttons = buttons,
            .modifiers = Qt::NoModifier,
            .surface = songview::TimelineInputSurface::Plot,
            .host = nullptr};
}
} // namespace

void AutomationRasterTest::hoverGhostRingAndLeaveClear_data()
{
    QTest::addColumn<int>("adapterKind");
    QTest::newRow(kHoverCases[0].name) << int(kHoverCases[0].kind);
    QTest::newRow(kHoverCases[1].name) << int(kHoverCases[1].kind);
}

void AutomationRasterTest::hoverGhostRingAndLeaveClear()
{
    QFETCH(int, adapterKind);
    QVERIFY(configureInteraction());
    const auto kind = static_cast<AdapterKind>(adapterKind);
    // The shared plot only shows the active parameter, so the intended CC or
    // Tempo must be activated through its selector label before every real
    // pointer sequence.
    const EditorAutomationRowId row =
        kind == AdapterKind::Tempo ? EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}
                                   : fixture().pan.row;
    QVERIFY(fixture().activateParameter(row));
    const PreparedLane lane = prepareLane(fixture(), kind);
    QVERIFY(lane.handle.valid());
    QVERIFY(!lane.body.isEmpty());
    QVERIFY(lane.insertionTick != kHeldTick);
    QVERIFY(lane.insertionTick != kNodeTick);

    fixture().automationPointerLeave();
    fixture().pump();
    fixture().pump();
    const HoverObservation idle = observeHover(fixture());
    QVERIFY(idle.framebufferReady);
    const DocumentSnapshot before = snapshot(fixture().document());
    const QPointF insertionCenter =
        fixture().automationContentToViewport(QPointF(lane.insertionX, lane.heldY));
    const QPointF nodeCenter =
        fixture().automationContentToViewport(QPointF(lane.nodeX, lane.nodeY));
    const QPointF framebufferOffset(fixture().automationGutterInput().bounds().width(), 0.0);

    fixture().automationMouseMove(lane.insertionPosition);
    fixture().pump();
    fixture().pump();
    const HoverObservation insertion = observeHover(fixture());
    QVERIFY(snapshot(fixture().document()) == before);
    QVERIFY(insertion.framebufferReady);
    QVERIFY(insertion.layer.revision > idle.layer.revision);
    QVERIFY(hasFilledNodeAt(insertion.layer, insertionCenter));
    QVERIFY(pixelChangedAt(idle.framebuffer, insertion.framebuffer,
                           insertionCenter + framebufferOffset));

    fixture().automationMouseMove(lane.insertionPosition);
    fixture().pump();
    fixture().pump();
    const HoverObservation repeated = observeHover(fixture());
    QVERIFY(snapshot(fixture().document()) == before);
    QVERIFY(repeated.framebufferReady);
    QVERIFY(insertion.framebuffer == repeated.framebuffer);

    fixture().automationMouseMove(lane.nodePosition);
    fixture().pump();
    fixture().pump();
    const HoverObservation nodeHover = observeHover(fixture());
    QVERIFY(snapshot(fixture().document()) == before);
    QVERIFY(nodeHover.framebufferReady);
    QVERIFY(nodeHover.layer.revision > insertion.layer.revision);
    QVERIFY(!nodeHover.layer.triangles.empty());
    QVERIFY(hasAnnulusPixelChanges(
        insertion.framebuffer, nodeHover.framebuffer, nodeCenter + framebufferOffset,
        nodelane::hoverRingRadius(fixture().geometry()), 2 * layout::singlePixel()));

    fixture().automationPointerLeave();
    fixture().pump();
    fixture().pump();
    const HoverObservation transitioned = observeHover(fixture());
    fixture().automationPointerLeave();
    fixture().pump();
    fixture().pump();
    const HoverObservation left = observeHover(fixture());
    QVERIFY(snapshot(fixture().document()) == before);

    // The old comparison against nodeHover at insertionCenter was incidental: a valid node ring
    // can overlap that pixel. The replacement contract is that each post-leave clear frame has
    // empty retained hover state and restores the insertion probe to the idle framebuffer.
    QVERIFY(isClear(transitioned));
    QVERIFY(isClear(left));
    QVERIFY(pixelMatchesIdleAt(idle.framebuffer, transitioned.framebuffer,
                               insertionCenter + framebufferOffset));
    QVERIFY(pixelMatchesIdleAt(idle.framebuffer, left.framebuffer,
                               insertionCenter + framebufferOffset));

    // Horizontal scroll past the node: the origin phantom must keep
    // presenting the node's original source event at the plot origin, and a
    // parameter switch must clear stale hover and transient pixels before the
    // drag re-arms on the reactivated plot.
    const AutomationGeometry geometry = fixture().geometry();
    const QPointF plotOrigin(0.0, lane.nodeY);
    // The insertion probe y is the cursor fraction of the same body, so the
    // vertical drag lands on a value distinct from both stored points.
    const QPointF dragTarget(0.0, lane.insertionPosition.y());
    const QPointF framebufferOrigin(fixture().automationGutterInput().bounds().width(), 0.0);
    QVERIFY(std::abs(dragTarget.y() - plotOrigin.y()) > qreal(geometry.nodeDragActivationDistance));
    fixture().setAutomationScroll(lane.nodeX + 2.0 * geometry.pointHitRadius);
    fixture().automationPointerLeave();
    fixture().pump();
    fixture().pump();
    const HoverObservation scrolledIdle = observeHover(fixture());
    QVERIFY(scrolledIdle.framebufferReady);
    const DocumentSnapshot scrolled = snapshot(fixture().document());

    SongDocument &document = fixture().document();
    TempoLane tempoLane(document);
    CCLaneAdapter ccLane(document, fixture().pan.track, fixture().pan.controller);
    NodeLane &laneAdapter = kind == AdapterKind::Tempo ? static_cast<NodeLane &>(tempoLane)
                                                       : static_cast<NodeLane &>(ccLane);

    // Before the drag: the scrolled-out node paints as a static phantom at the
    // plot's left edge, and hovering it rings exactly there with its value
    // readout.
    fixture().automationMouseMove(plotOrigin);
    fixture().pump();
    fixture().pump();
    const HoverObservation phantomHover = observeHover(fixture());
    QVERIFY(phantomHover.framebufferReady);
    QVERIFY(phantomHover.layer.revision > scrolledIdle.layer.revision);
    QCOMPARE(phantomHover.textRows, 1);
    QCOMPARE(phantomHover.valueText, laneAdapter.valueText(lane.nodeValue));
    QVERIFY(hasAnnulusPixelChanges(scrolledIdle.framebuffer, phantomHover.framebuffer,
                                   framebufferOrigin + plotOrigin,
                                   nodelane::hoverRingRadius(geometry), 2 * layout::singlePixel()));
    QVERIFY(hasFilledNodeAt(
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationNodes), plotOrigin));

    // Arming the vertical drag previews from the plot origin without touching
    // the document.
    const auto transientBefore =
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationTransient);
    const DocumentSnapshot dragged = snapshot(fixture().document());
    QVERIFY(
        fixture().canvas().pointerPress(plotPointer(Qt::LeftButton, Qt::LeftButton, plotOrigin)));
    QVERIFY(fixture().canvas().gestureActive());
    // The first move crosses the drag-activation slop and becomes the slop
    // origin; the second mirrors the press around the target so the effective
    // drag position is exactly the target value.
    fixture().canvas().pointerMove(plotPointer(Qt::NoButton, Qt::LeftButton, dragTarget));
    const QPointF dragAnchor = 2.0 * dragTarget - plotOrigin;
    fixture().canvas().pointerMove(plotPointer(Qt::NoButton, Qt::LeftButton, dragAnchor));
    fixture().pump();
    fixture().pump();
    QTRY_VERIFY(
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationTransient).revision >
        transientBefore.revision);
    const auto draggedTransient =
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationTransient);
    QVERIFY(hasFilledNodeAt(draggedTransient, dragTarget));
    QVERIFY(snapshot(fixture().document()) == dragged);

    // Switching away cancels the provisional drag and clears the old hover and
    // transient pixels; every stored value survives both activations.
    const EditorAutomationRowId away =
        kind == AdapterKind::Tempo ? fixture().pan.row
                                   : EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0};
    QVERIFY(fixture().activateParameter(away));
    QVERIFY(!fixture().canvas().gestureActive());
    QTRY_VERIFY(fixture()
                    .quickScene()
                    .layer(songview::TimelineQuickLayer::AutomationTransient)
                    .rects.empty());
    QTRY_VERIFY(fixture()
                    .quickScene()
                    .layer(songview::TimelineQuickLayer::AutomationTransient)
                    .triangles.empty());
    QVERIFY(isClear(observeHover(fixture())));
    QVERIFY(snapshot(fixture().document()) == scrolled);
    QVERIFY(fixture().activateParameter(row));
    fixture().automationPointerLeave();
    fixture().pump();
    fixture().pump();
    QVERIFY(isClear(observeHover(fixture())));

    // The committed drag edits the node's original source event: same tick,
    // moved value, and no duplicate inserted at the viewport edge.
    fixture().automationMouseMove(plotOrigin);
    fixture().pump();
    fixture().pump();
    QVERIFY(
        fixture().canvas().pointerPress(plotPointer(Qt::LeftButton, Qt::LeftButton, plotOrigin)));
    // The first move crosses the drag-activation slop and becomes the slop
    // origin; the second mirrors the press around the target so the effective
    // drag position is exactly the target value.
    fixture().canvas().pointerMove(plotPointer(Qt::NoButton, Qt::LeftButton, dragTarget));
    const QPointF commitAnchor = 2.0 * dragTarget - plotOrigin;
    fixture().canvas().pointerMove(plotPointer(Qt::NoButton, Qt::LeftButton, commitAnchor));
    fixture().pump();
    QVERIFY(fixture().canvas().gestureActive());
    // Releasing at the anchor keeps the slop-compensated effective position
    // on the target value for the commit.
    QVERIFY(
        fixture().canvas().pointerRelease(plotPointer(Qt::LeftButton, Qt::NoButton, commitAnchor)));
    fixture().pump();
    fixture().pump();
    QVERIFY(!fixture().canvas().gestureActive());
    QCOMPARE(fixture().document().revision(), scrolled.revision + 1);
    if (kind == AdapterKind::Tempo) {
        const std::vector<TempoPoint> expected{{kHeldTick, tempoUsForBpm(lane.heldValue)},
                                               {kNodeTick, tempoUsForBpm(lane.cursorValue)}};
        QCOMPARE(fixture().document().tempoPoints(), expected);
    } else {
        const std::vector<DocLanePoint> points =
            fixture().document().lanePoints(fixture().pan.track, fixture().pan.controller);
        QCOMPARE(points.size(), std::size_t(2));
        QCOMPARE(points[0].tick, kHeldTick);
        QCOMPARE(points[0].value, lane.heldValue);
        QCOMPARE(points[1].tick, kNodeTick);
        QCOMPARE(points[1].value, lane.cursorValue);
    }
}

void AutomationRasterTest::voicePressWithoutMoveHasNoPreview()
{
    QVERIFY(configureInteraction());
    fixture().canvas().cancelInteraction();
    fixture().pump();
    seedVoice(fixture());
    const QPointF source = voicePoint(fixture(), 24);
    const DocumentSnapshot before = snapshot(fixture().document());
    QString error;
    const QImage idle = fixture().renderVoiceChanges(&error);
    QVERIFY2(error.isEmpty() && !idle.isNull(), qPrintable(error));

    fixture().voiceMousePress(source);
    fixture().pump();
    const QImage pressed = fixture().renderVoiceChanges(&error);
    QVERIFY2(error.isEmpty() && !pressed.isNull(), qPrintable(error));
    QVERIFY(snapshot(fixture().document()) == before);
    QVERIFY(pressed == idle);

    fixture().voiceMouseRelease(source);
    fixture().pump();
    QVERIFY(!fixture().view().userGestureActive());
}

void AutomationRasterTest::voiceDragPreviewsWithoutCommitUntilRelease()
{
    QVERIFY(configureInteraction());
    fixture().canvas().cancelInteraction();
    fixture().pump();
    seedVoice(fixture());
    const QPointF source = voicePoint(fixture(), 24);
    const QPointF target = voicePoint(fixture(), 72);
    const DocumentSnapshot before = snapshot(fixture().document());
    QString error;
    const QImage idle = fixture().renderVoiceChanges(&error);
    QVERIFY2(error.isEmpty() && !idle.isNull(), qPrintable(error));

    fixture().voiceMousePress(source);
    fixture().voiceMouseMove(target);
    fixture().pump();
    const QImage preview = fixture().renderVoiceChanges(&error);
    QVERIFY2(error.isEmpty() && !preview.isNull(), qPrintable(error));
    QVERIFY(snapshot(fixture().document()) == before);
    QVERIFY(fixture().view().userGestureActive());
    QCOMPARE(fixture().voiceInput().cursor().shape(), Qt::SizeHorCursor);
    QCOMPARE(preview.size(), idle.size());
    QVERIFY(preview != idle);

    fixture().voiceMouseRelease(target);
    fixture().pump();
    QVERIFY(!fixture().view().userGestureActive());
}

int runAutomationRasterCheck(const QString &project, const QString &song,
                             const QStringList &qtArguments)
{
    AutomationRasterTest test(project, song);
    QStringList arguments{QStringLiteral("automation-raster")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
