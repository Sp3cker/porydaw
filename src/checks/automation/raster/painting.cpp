#include "checks/automation/raster/tst_automationraster.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <utility>
#include <vector>

#include <QColor>
#include <QEvent>
#include <QImage>
#include <QQuickItem>
#include <QRectF>

#include <QtTest>

#include "checks/support/eventsynth.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

enum class LaneKind { Tempo, Cc };

struct LaneGeometry {
    LaneHandle handle;
    QRect body;
    QColor curveColor;
};

constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kNodeTick = 96;
constexpr uint64_t kSecondTick = 144;
constexpr int kTempoHeld = 80;
constexpr int kTempoNode = 200;
constexpr int kTempoSecond = 160;
constexpr int kCcHeld = 24;
constexpr int kCcNode = 96;
constexpr int kCcSecond = 72;

QRectF triangleBounds(const songview::TimelineQuickTriangle &triangle)
{
    const qreal left = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal right = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal top = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    const qreal bottom = std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    return QRectF(QPointF(left, top), QPointF(right, bottom));
}

bool layerHasColorIn(const songview::TimelineQuickLayerData &layer, const QRectF &contentProbe,
                     const QPoint &contentOrigin, const QColor &color)
{
    const QRectF probe = contentProbe.translated(contentOrigin);
    for (const songview::TimelineQuickRect &rect : layer.rects) {
        if (rect.rect.intersects(probe) &&
            (rect.topLeft == color || rect.topRight == color || rect.bottomRight == color ||
             rect.bottomLeft == color)) {
            return true;
        }
    }
    for (const songview::TimelineQuickTriangle &triangle : layer.triangles) {
        if (triangleBounds(triangle).intersects(probe) &&
            (triangle.firstColor == color || triangle.secondColor == color ||
             triangle.thirdColor == color)) {
            return true;
        }
    }
    return false;
}

QRectF nodeProbe(qreal x, qreal y, qreal radius)
{
    return {x - radius, y - radius, 2 * radius, 2 * radius};
}

QRectF lineProbe(qreal x, qreal y, qreal halfWidth, qreal halfHeight)
{
    return {x - halfWidth, y - halfHeight, 2 * halfWidth, 2 * halfHeight};
}

bool framebufferHasColorNear(const QImage &framebuffer, const QPointF &point,
                             const QColor &expected)
{
    if (framebuffer.isNull() || framebuffer.devicePixelRatio() <= 0.0)
        return false;

    constexpr int kColorTolerance = 64;
    const qreal dpr = framebuffer.devicePixelRatio();
    const int radius = qCeil(2 * dpr);
    const int centerX = qRound(point.x() * dpr);
    const int centerY = qRound(point.y() * dpr);
    for (int y = std::max(0, centerY - radius);
         y <= std::min(framebuffer.height() - 1, centerY + radius); ++y) {
        for (int x = std::max(0, centerX - radius);
             x <= std::min(framebuffer.width() - 1, centerX + radius); ++x) {
            const QColor pixel = framebuffer.pixelColor(x, y);
            if (pixel.alpha() >= 32 && std::abs(pixel.red() - expected.red()) <= kColorTolerance &&
                std::abs(pixel.green() - expected.green()) <= kColorTolerance &&
                std::abs(pixel.blue() - expected.blue()) <= kColorTolerance) {
                return true;
            }
        }
    }
    return false;
}

bool layerHasSelectionRing(const songview::TimelineQuickLayerData &layer,
                           const QPoint &contentPoint, int verticalScroll, qreal ringRadius,
                           qreal ringWidth, const QColor &selectionColor)
{
    const QPointF center = QPointF(contentPoint) - QPointF(0.0, verticalScroll);
    const qreal tolerance = layout::singlePixel();
    const qreal inner = std::max<qreal>(0.0, ringRadius - ringWidth / 2.0 - tolerance);
    const qreal outer = ringRadius + ringWidth / 2.0 + tolerance;
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    return std::count_if(
               layer.triangles.cbegin(), layer.triangles.cend(),
               [&](const songview::TimelineQuickTriangle &triangle) {
                   const auto onRing = [&](const QPointF &point) {
                       const QPointF delta = point - center;
                       const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
                       return distanceSquared >= innerSquared && distanceSquared <= outerSquared;
                   };
                   return triangle.firstColor == selectionColor &&
                          triangle.secondColor == selectionColor &&
                          triangle.thirdColor == selectionColor && onRing(triangle.first) &&
                          onRing(triangle.second) && onRing(triangle.third);
               }) >= 4;
}

bool framebufferHasSelectionRing(const QImage &baseline, const QImage &framebuffer,
                                 const QPoint &contentPoint, int verticalScroll, int gutterWidth,
                                 qreal nodeOuterRadius, qreal ringRadius, qreal ringWidth,
                                 const QColor &selectionColor)
{
    if (baseline.isNull() || framebuffer.isNull() || baseline.size() != framebuffer.size() ||
        framebuffer.devicePixelRatio() <= 0.0 ||
        !qFuzzyCompare(baseline.devicePixelRatio(), framebuffer.devicePixelRatio())) {
        return false;
    }

    const qreal dpr = framebuffer.devicePixelRatio();
    const QPointF center = QPointF(contentPoint) + QPointF(gutterWidth, -verticalScroll);
    const qreal selectedOuterRadius = ringRadius + ringWidth / 2.0;
    const qreal inner = (nodeOuterRadius + selectedOuterRadius) / 2.0;
    const qreal outer = selectedOuterRadius + layout::singlePixel();
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    const int left = std::max(0, qFloor((center.x() - outer) * dpr));
    const int top = std::max(0, qFloor((center.y() - outer) * dpr));
    const int right = std::min(framebuffer.width() - 1, qCeil((center.x() + outer) * dpr));
    const int bottom = std::min(framebuffer.height() - 1, qCeil((center.y() + outer) * dpr));
    unsigned changedQuadrants = 0;
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const QPointF delta((x + 0.5) / dpr - center.x(), (y + 0.5) / dpr - center.y());
            const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
            const QColor pixel = framebuffer.pixelColor(x, y);
            const QColor oldPixel = baseline.pixelColor(x, y);
            const int difference = std::abs(pixel.alpha() - oldPixel.alpha()) +
                                   std::abs(pixel.red() - oldPixel.red()) +
                                   std::abs(pixel.green() - oldPixel.green()) +
                                   std::abs(pixel.blue() - oldPixel.blue());
            if (distanceSquared >= innerSquared && distanceSquared <= outerSquared &&
                difference >= 32 && pixel.alpha() >= 32 &&
                std::abs(pixel.red() - selectionColor.red()) <= 64 &&
                std::abs(pixel.green() - selectionColor.green()) <= 64 &&
                std::abs(pixel.blue() - selectionColor.blue()) <= 64) {
                const unsigned quadrant =
                    (delta.x() >= 0.0 ? 1U : 0U) | (delta.y() >= 0.0 ? 2U : 0U);
                changedQuadrants |= 1U << quadrant;
            }
        }
    }
    return changedQuadrants == 0xFU;
}

LaneGeometry laneGeometry(const AutomationRasterFixture &fixture, LaneKind kind)
{
    LaneGeometry geometry;
    if (kind == LaneKind::Tempo) {
        geometry.handle = AutomationRasterFixture::kTempoHandle;
        geometry.curveColor = themes::color(themes::Role::song_view_automation_tempo_curve);
    } else {
        geometry.handle = fixture.handleFor(fixture.pan);
        geometry.curveColor = themes::trackIdentityColor(0);
    }
    geometry.body = fixture.bodyFor(geometry.handle);
    return geometry;
}

} // namespace

AutomationRasterTest::AutomationRasterTest(QString project, QString song)
    : m_projectPath(std::move(project))
    , m_song(std::move(song))
{}

void AutomationRasterTest::init()
{
    QString error;
    m_project = checks::ProjectFixture::copyOf(m_projectPath, error);
    QVERIFY2(m_project, qPrintable(error));
    m_fixture = AutomationRasterFixture::create(m_project->root(), m_song, error);
    QVERIFY2(m_fixture, qPrintable(error));
}

void AutomationRasterTest::cleanup()
{
    if (m_fixture) {
        m_fixture->shutdown();
        m_fixture.reset();
    }
    m_project.reset();
}

bool AutomationRasterTest::configurePainting()
{
    fixture().configurePainting();
    return fixture().page().canvas() && !fixture().automationGutterInput().bounds().isEmpty();
}

bool AutomationRasterTest::configureInteraction()
{
    fixture().configureInteraction();
    return fixture().page().canvas() && !fixture().voiceInput().bounds().isEmpty();
}

AutomationRasterFixture &AutomationRasterTest::fixture() noexcept
{
    return *m_fixture;
}

const AutomationRasterFixture &AutomationRasterTest::fixture() const noexcept
{
    return *m_fixture;
}

void AutomationRasterTest::resizeBoundaryShowsSplitCursorWithoutPreview()
{
    QVERIFY(configurePainting());
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, 21};
    const LaneHandle lfoHandle = fixture().handleFor({lfo, 0, 21});
    const QRect body = fixture().bodyFor(lfoHandle);
    QVERIFY(lfoHandle.valid());
    QVERIFY(!body.isEmpty());

    fixture().canvas().cancelInteraction();
    fixture().automationPointerLeave();
    fixture().pump();
    QString error;
    const QImage baseline = fixture().renderAutomationViewport(&error);
    QVERIFY2(error.isEmpty() && !baseline.isNull(), qPrintable(error));

    const QPointF boundary(layout::space(layout::Space::One), body.bottom() + 1);
    checks::events::sendMouse(fixture().automationGutterInput(), QEvent::MouseMove,
                              fixture().automationContentToViewport(boundary), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    fixture().pump();
    const QImage hovered = fixture().renderAutomationViewport(&error);
    QVERIFY2(error.isEmpty() && !hovered.isNull(), qPrintable(error));
    QCOMPARE(fixture().automationGutterInput().cursor().shape(), Qt::SplitVCursor);
    QVERIFY(hovered == baseline);
}

void AutomationRasterTest::curvesNodesAndSelectedRingsRender_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::addColumn<bool>("logicalDpr");
    QTest::newRow("tempo-native-dpr") << int(LaneKind::Tempo) << false;
    QTest::newRow("cc-native-dpr") << int(LaneKind::Cc) << false;
    // This row exercises the logical-DPR projection path separately from the native window DPR.
    QTest::newRow("tempo-one-dpr") << int(LaneKind::Tempo) << true;
}

void AutomationRasterTest::curvesNodesAndSelectedRingsRender()
{
    QFETCH(int, laneKind);
    QFETCH(bool, logicalDpr);
    QVERIFY(configurePainting());
    if (logicalDpr)
        fixture().setAutomationDpr(1.0);
    else
        fixture().setAutomationDpr(fixture().nativeAutomationDpr());
    QVERIFY(fixture().automationDpr() > 0.0);

    const auto kind = static_cast<LaneKind>(laneKind);
    QVERIFY(fixture().expandTempo());
    SongDocument &document = fixture().document();
    TempoLane tempoLane(document);
    CCLaneAdapter ccLane(document, 0, uint8_t{10});
    NodeLane &lane = kind == LaneKind::Tempo ? static_cast<NodeLane &>(tempoLane)
                                             : static_cast<NodeLane &>(ccLane);
    if (kind == LaneKind::Tempo) {
        TempoEdit edit;
        edit.remove = document.tempoPoints();
        edit.add = {
            {kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
            {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)},
            {kSecondTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoSecond)}};
        document.applyTempoEdit(edit);
    } else {
        document.writeLanePoints(
            0, uint8_t{10}, 0, std::numeric_limits<uint64_t>::max(),
            {{kHeldTick, kCcHeld}, {kNodeTick, kCcNode}, {kSecondTick, kCcSecond}});
    }

    const quint64 curvesBefore =
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationCurves).revision;
    const quint64 nodesBefore =
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    fixture().documentChanged();
    fixture().automationPointerLeave();
    fixture().pump();

    const LaneGeometry geometry = laneGeometry(fixture(), kind);
    QVERIFY(geometry.handle.valid());
    QVERIFY(!geometry.body.isEmpty());
    const int held = kind == LaneKind::Tempo ? kTempoHeld : kCcHeld;
    const int node = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const qreal heldY = nodelane::valueY(lane, geometry.body, fixture().geometry(), held);
    const qreal nodeY = nodelane::valueY(lane, geometry.body, fixture().geometry(), node);
    const qreal nodeX = fixture().projection().displayX(kNodeTick, fixture().automationDpr());
    const qreal midX = fixture().projection().displayX(48, fixture().automationDpr());
    const QPoint origin(0, -fixture().page().verticalScroll());
    const qreal nodeRadius = nodelane::hoverRingRadius(fixture().geometry());
    const qreal lineHalf =
        std::max(qreal(layout::singlePixel()), qreal(fixture().geometry().hoverPaintPadding + 1));
    const auto &scene = fixture().quickScene();
    QVERIFY(scene.layer(songview::TimelineQuickLayer::AutomationCurves).revision > curvesBefore);
    QVERIFY(scene.layer(songview::TimelineQuickLayer::AutomationNodes).revision > nodesBefore);
    QVERIFY(layerHasColorIn(scene.layer(songview::TimelineQuickLayer::AutomationCurves),
                            lineProbe(midX, heldY, 8, lineHalf), origin, geometry.curveColor));
    QVERIFY(layerHasColorIn(scene.layer(songview::TimelineQuickLayer::AutomationNodes),
                            nodeProbe(nodeX, nodeY, nodeRadius), origin, geometry.curveColor));

    QString error;
    const QImage normal = fixture().renderAutomationViewport(&error);
    QVERIFY2(error.isEmpty() && !normal.isNull(), qPrintable(error));
    const QPointF framebufferOrigin(fixture().automationGutterInput().bounds().width(),
                                    -fixture().page().verticalScroll());
    QVERIFY(framebufferHasColorNear(normal, framebufferOrigin + QPointF(midX, heldY),
                                    geometry.curveColor));
    QVERIFY(framebufferHasColorNear(normal, framebufferOrigin + QPointF(nodeX, nodeY),
                                    geometry.curveColor));

    const quint64 selectionBefore =
        scene.layer(songview::TimelineQuickLayer::AutomationSelection).revision;
    const quint64 selectedNodesBefore =
        scene.layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kNodeTick;
    selection.endTick = kNodeTick + 1;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    if (kind == LaneKind::Tempo)
        selection.tempo = true;
    else
        selection.lanes = {{0, 10}};
    fixture().view().selectionModel().setTimeSelection(selection);
    fixture().documentChanged();
    fixture().automationPointerLeave();
    fixture().pump();

    const QColor highlight = fixture().automationGutterInput().palette().highlight().color();
    const qreal ringOuter = fixture().geometry().selectedNodeRingRadius + layout::singlePixel();
    QVERIFY(layerHasColorIn(scene.layer(songview::TimelineQuickLayer::AutomationNodes),
                            nodeProbe(nodeX, nodeY, ringOuter), origin, highlight));
    const QImage selected = fixture().renderAutomationViewport(&error);
    QVERIFY2(error.isEmpty() && !selected.isNull(), qPrintable(error));
    QVERIFY(framebufferHasColorNear(
        selected,
        framebufferOrigin + QPointF(nodeX, nodeY - fixture().geometry().selectedNodeRingRadius),
        highlight));
    QVERIFY(scene.layer(songview::TimelineQuickLayer::AutomationSelection).revision >
            selectionBefore);
    QVERIFY(scene.layer(songview::TimelineQuickLayer::AutomationNodes).revision >
            selectedNodesBefore);
}

void AutomationRasterTest::halfOpenTrackSelectionRendersOnlyIncludedNodes_data()
{
    QTest::addColumn<bool>("includeEnd");
    QTest::newRow("end-at-group-b-excludes-b") << false;
    QTest::newRow("end-after-group-b-includes-b") << true;
}

void AutomationRasterTest::halfOpenTrackSelectionRendersOnlyIncludedNodes()
{
    QFETCH(bool, includeEnd);
    QVERIFY(configurePainting());
    QVERIFY(fixture().expandTempo());
    fixture().setAutomationDpr(fixture().nativeAutomationDpr());

    SongView &view = fixture().view();
    const uint64_t groupA = view.grid().snapTick(48.0, false);
    const uint64_t groupB = view.grid().snapTick(72.0, false);
    const uint64_t groupC = view.grid().snapTick(120.0, false);
    constexpr int kGroupAValue = 40;
    constexpr int kGroupBValue = 80;
    constexpr int kGroupCValue = 55;
    fixture().document().writeLanePoints(
        0, fixture().pan.controller, 0, std::numeric_limits<uint64_t>::max(),
        {{groupA, kGroupAValue}, {groupB, kGroupBValue}, {groupC, kGroupCValue}});
    fixture().documentChanged();

    const LaneHandle panHandle = fixture().handleFor(fixture().pan);
    const QRect body = fixture().bodyFor(panHandle);
    QVERIFY(panHandle.valid());
    QVERIFY(!body.isEmpty());
    CCLaneAdapter panLane(fixture().document(), fixture().pan.track, fixture().pan.controller);
    const auto pointAt = [&](uint64_t tick, int value) {
        return QPoint(qRound(fixture().projection().displayX(tick, fixture().automationDpr())),
                      qRound(nodelane::valueY(panLane, body, fixture().geometry(), value)));
    };
    const QPoint groupAPoint = pointAt(groupA, kGroupAValue);
    const QPoint groupBPoint = pointAt(groupB, kGroupBValue);
    const QPoint groupCPoint = pointAt(groupC, kGroupCValue);

    QString error;
    const QImage baseline = fixture().renderAutomationViewport(&error);
    QVERIFY2(error.isEmpty() && !baseline.isNull(), qPrintable(error));

    const quint64 nodesBefore =
        fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = groupA;
    selection.endTick = includeEnd ? groupB + 1 : groupB;
    view.selectionModel().setTimeSelection(selection);
    fixture().documentChanged();
    fixture().pump();

    const auto &nodes = fixture().quickScene().layer(songview::TimelineQuickLayer::AutomationNodes);
    const QColor selectionColor = fixture().automationGutterInput().palette().highlight().color();
    const qreal ringRadius = fixture().geometry().selectedNodeRingRadius;
    const qreal ringWidth = fixture().geometry().selectedNodeRingDipWidth;
    const qreal nodeOuterRadius =
        fixture().geometry().nodePaintRadius + fixture().geometry().nodeOutlineDipWidth;
    QVERIFY(ringRadius + ringWidth / 2.0 > nodeOuterRadius);
    QVERIFY(nodes.revision > nodesBefore);
    QVERIFY(layerHasSelectionRing(nodes, groupAPoint, fixture().page().verticalScroll(), ringRadius,
                                  ringWidth, selectionColor));
    QCOMPARE(layerHasSelectionRing(nodes, groupBPoint, fixture().page().verticalScroll(),
                                   ringRadius, ringWidth, selectionColor),
             includeEnd);
    QVERIFY(!layerHasSelectionRing(nodes, groupCPoint, fixture().page().verticalScroll(),
                                   ringRadius, ringWidth, selectionColor));

    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const quickRoot = quickCanvas ? quickCanvas->rootObject() : nullptr;
    QQuickItem *const selectionLayer =
        quickRoot
            ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineQuickAutomationSelection"))
            : nullptr;
    QVERIFY(selectionLayer);
    // A track-range selection also dims unselected nodes and paints a reticle up to the
    // half-open endpoint. Hide the reticle so this framebuffer probe isolates the node layer;
    // its outer annulus excludes the smaller normal/dimmed marker.
    selectionLayer->setVisible(false);
    fixture().pump();
    const QImage framebuffer = fixture().renderAutomationViewport(&error);
    QVERIFY2(error.isEmpty() && !framebuffer.isNull(), qPrintable(error));
    const int gutterWidth = qRound(fixture().automationGutterInput().bounds().width());
    QVERIFY(framebufferHasSelectionRing(baseline, framebuffer, groupAPoint,
                                        fixture().page().verticalScroll(), gutterWidth,
                                        nodeOuterRadius, ringRadius, ringWidth, selectionColor));
    QCOMPARE(framebufferHasSelectionRing(baseline, framebuffer, groupBPoint,
                                         fixture().page().verticalScroll(), gutterWidth,
                                         nodeOuterRadius, ringRadius, ringWidth, selectionColor),
             includeEnd);
    QVERIFY(!framebufferHasSelectionRing(baseline, framebuffer, groupCPoint,
                                         fixture().page().verticalScroll(), gutterWidth,
                                         nodeOuterRadius, ringRadius, ringWidth, selectionColor));
}
