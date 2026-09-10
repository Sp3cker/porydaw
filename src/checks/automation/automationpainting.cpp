#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <vector>

#include <QColor>
#include <QSignalSpy>
#include <QtTest>

#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

constexpr uint8_t kController = 10;
constexpr uint64_t kFirstNodeTick = 96;
constexpr uint64_t kSecondNodeTick = 144;
constexpr int kTempoHeld = 80;
constexpr int kTempoNode = 200;
constexpr int kTempoSecond = 160;
constexpr int kCcHeld = 24;
constexpr int kCcNode = 96;
constexpr int kCcSecond = 72;

enum class LaneKind { Tempo, Cc };

EditorAutomationRowId rowId(LaneKind kind)
{
    return kind == LaneKind::Tempo
               ? EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}
               : EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kController};
}

struct LanePaint final {
    LaneHandle handle;
    QRect body;
    QColor color;
    int minimum = 0;
    int maximum = 0;
};

QRectF nodeProbe(const QPointF &center, qreal radius)
{
    return {center.x() - radius, center.y() - radius, 2.0 * radius, 2.0 * radius};
}

QRectF lineProbe(const QPointF &center, qreal halfWidth, qreal halfHeight)
{
    return {center.x() - halfWidth, center.y() - halfHeight, 2.0 * halfWidth, 2.0 * halfHeight};
}

void setTempo(SongDocument &document, const std::vector<TempoPoint> &points)
{
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = points;
    document.applyTempoEdit(edit);
}

void setCc(SongDocument &document, const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(), points);
}

LanePaint lanePaint(AutomationPage &page, LaneKind kind)
{
    if (kind == LaneKind::Tempo) {
        const LaneHandle handle{0};
        return {handle, page.canvas()->laneBody(handle),
                themes::color(themes::Role::song_view_automation_tempo_curve),
                CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm};
    }

    const auto &rows = page.canvas()->rows();
    for (int row = 0; row < int(rows.size()); ++row) {
        if (rows[std::size_t(row)].id.controller == kController) {
            const LaneHandle handle{row + 1};
            return {handle, page.canvas()->laneBody(handle), themes::trackIdentityColor(0), 0, 127};
        }
    }
    return {};
}

QPointF nodePoint(const SongView &view, const songview::TimelineInputItem &input,
                  const LanePaint &lane, uint64_t tick, int value)
{
    return {view.camera().displayX(double(tick), 0.0, input.devicePixelRatio()),
            AutomationProjection::valueY(lane.body, AutomationGeometry::resolve(), lane.minimum,
                                         lane.maximum, value)};
}

} // namespace

void AutomationEditingTest::emptyTempoStorageComposesNoLeadIn()
{
    QVERIFY(expandTempo());
    QVERIFY(activateParameter(rowId(LaneKind::Tempo)));
    SongDocument &document = m_tab->document();
    SongView &view = m_tab->view();
    const LanePaint tempo = lanePaint(*m_page, LaneKind::Tempo);
    QVERIFY(!tempo.body.isEmpty());

    const auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    QVERIFY(document.tempoPoints().empty());

    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    const qreal x0 = nodePoint(view, *m_automationInput, tempo, 0, CoreTimeDefaults::kTempoBpm).x();
    const qreal xMid =
        nodePoint(view, *m_automationInput, tempo, kFirstNodeTick / 2, CoreTimeDefaults::kTempoBpm)
            .x();
    const qreal y120 =
        nodePoint(view, *m_automationInput, tempo, 0, CoreTimeDefaults::kTempoBpm).y();
    const qreal radius = nodelane::hoverRingRadius(AutomationGeometry::resolve());
    const qreal lineHalf = std::max(qreal(layout::singlePixel()),
                                    qreal(AutomationGeometry::resolve().hoverPaintPadding + 1));
    const auto &curves = scene->layer(songview::TimelineQuickLayer::AutomationCurves);
    const auto &nodes = scene->layer(songview::TimelineQuickLayer::AutomationNodes);
    QVERIFY(!checks::support::layerHasColorIn(curves, lineProbe(QPointF(xMid, y120), 8.0, lineHalf),
                                              tempo.color));
    QVERIFY(!checks::support::layerHasColorIn(nodes, nodeProbe(QPointF(x0, y120), radius),
                                              tempo.color));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::firstNonzeroTempoPointComposesImplicitLeadInCurve()
{
    QVERIFY(expandTempo());
    QVERIFY(activateParameter(rowId(LaneKind::Tempo)));
    SongDocument &document = m_tab->document();
    SongView &view = m_tab->view();
    const LanePaint tempo = lanePaint(*m_page, LaneKind::Tempo);
    QVERIFY(!tempo.body.isEmpty());
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);

    const quint64 curvesBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision;
    setTempo(document,
             {{kFirstNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)}});
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision >
                curvesBefore);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    const QPointF leadMid =
        nodePoint(view, *m_automationInput, tempo, kFirstNodeTick / 2, CoreTimeDefaults::kTempoBpm);
    const QPointF zero = nodePoint(view, *m_automationInput, tempo, 0, CoreTimeDefaults::kTempoBpm);
    const QPointF node = nodePoint(view, *m_automationInput, tempo, kFirstNodeTick, kTempoNode);
    const qreal radius = nodelane::hoverRingRadius(AutomationGeometry::resolve());
    const qreal lineHalf = std::max(qreal(layout::singlePixel()),
                                    qreal(AutomationGeometry::resolve().hoverPaintPadding + 1));
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationCurves),
        lineProbe(leadMid, 8.0, lineHalf), tempo.color));
    QVERIFY(!checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationNodes), nodeProbe(zero, radius),
        tempo.color));
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationNodes), nodeProbe(node, radius),
        tempo.color));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::explicitTickZeroTempoPointSuppressesLeadInCurve()
{
    QVERIFY(expandTempo());
    QVERIFY(activateParameter(rowId(LaneKind::Tempo)));
    SongDocument &document = m_tab->document();
    SongView &view = m_tab->view();
    const LanePaint tempo = lanePaint(*m_page, LaneKind::Tempo);
    QVERIFY(!tempo.body.isEmpty());
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);

    const quint64 nodesBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    setTempo(document, {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)}});
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision > nodesBefore);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    const QPointF zero = nodePoint(view, *m_automationInput, tempo, 0, kTempoHeld);
    const QPointF leadMid =
        nodePoint(view, *m_automationInput, tempo, kFirstNodeTick / 2, CoreTimeDefaults::kTempoBpm);
    const qreal radius = nodelane::hoverRingRadius(AutomationGeometry::resolve());
    const qreal lineHalf = std::max(qreal(layout::singlePixel()),
                                    qreal(AutomationGeometry::resolve().hoverPaintPadding + 1));
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationNodes), nodeProbe(zero, radius),
        tempo.color));
    QVERIFY(!checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationCurves),
        lineProbe(leadMid, 8.0, lineHalf), tempo.color));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::stepCurvesAndNodesComposed_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("tempo") << int(LaneKind::Tempo);
    QTest::newRow("cc") << int(LaneKind::Cc);
}

void AutomationEditingTest::stepCurvesAndNodesComposed()
{
    QFETCH(int, laneKind);
    const LaneKind kind = LaneKind(laneKind);
    QVERIFY(kind != LaneKind::Tempo || expandTempo());
    QVERIFY(activateParameter(rowId(kind)));
    SongDocument &document = m_tab->document();
    SongView &view = m_tab->view();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    const quint64 curvesBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision;
    const quint64 nodesBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    if (kind == LaneKind::Tempo) {
        setTempo(
            document,
            {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
             {kFirstNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)},
             {kSecondNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoSecond)}});
    } else {
        setCc(document, {{0, kCcHeld}, {kFirstNodeTick, kCcNode}, {kSecondNodeTick, kCcSecond}});
    }
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision >
                curvesBefore);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision > nodesBefore);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());

    const LanePaint lane = lanePaint(*m_page, kind);
    QVERIFY(lane.handle.valid());
    QVERIFY(!lane.body.isEmpty());
    const int held = kind == LaneKind::Tempo ? kTempoHeld : kCcHeld;
    const int node = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const QPointF mid = nodePoint(view, *m_automationInput, lane, kFirstNodeTick / 2, held);
    const QPointF point = nodePoint(view, *m_automationInput, lane, kFirstNodeTick, node);
    const qreal radius = nodelane::hoverRingRadius(AutomationGeometry::resolve());
    const qreal lineHalf = std::max(qreal(layout::singlePixel()),
                                    qreal(AutomationGeometry::resolve().hoverPaintPadding + 1));
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationCurves), lineProbe(mid, 8.0, lineHalf),
        lane.color));
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationNodes), nodeProbe(point, radius),
        lane.color));

    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::selectionRingsAndReticlesComposed_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("tempo") << int(LaneKind::Tempo);
    QTest::newRow("cc") << int(LaneKind::Cc);
}

void AutomationEditingTest::selectionRingsAndReticlesComposed()
{
    QFETCH(int, laneKind);
    const LaneKind kind = LaneKind(laneKind);
    QVERIFY(kind != LaneKind::Tempo || expandTempo());
    QVERIFY(activateParameter(rowId(kind)));
    SongDocument &document = m_tab->document();
    SongView &view = m_tab->view();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    if (kind == LaneKind::Tempo) {
        setTempo(document, {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
                            {kFirstNodeTick,
                             CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)}});
    } else {
        setCc(document, {{0, kCcHeld}, {kFirstNodeTick, kCcNode}});
    }
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    const LanePaint lane = lanePaint(*m_page, kind);
    QVERIFY(!lane.body.isEmpty());
    const int nodeValue = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const QPointF node = nodePoint(view, *m_automationInput, lane, kFirstNodeTick, nodeValue);
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kFirstNodeTick;
    selection.endTick = kFirstNodeTick + 1;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    if (kind == LaneKind::Tempo)
        selection.tempo = true;
    else
        selection.lanes = {{0, kController}};
    const quint64 nodesBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    const quint64 selectionBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationSelection).revision;
    view.selectionModel().setTimeSelection(selection);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision > nodesBefore);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationSelection).revision >
                selectionBefore);

    const QColor highlight = m_automationInput->palette().highlight().color();
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    QVERIFY(checks::support::layerHasRingAt(
        scene->layer(songview::TimelineQuickLayer::AutomationNodes), node,
        geometry.selectedNodeRingRadius, geometry.selectedNodeRingDipWidth, highlight));
    const QColor edge = themes::color(themes::Role::song_view_selection_edge);
    const QColor fill = themes::color(themes::Role::song_view_selection_fill);
    const qreal firstX = nodePoint(view, *m_automationInput, lane, kFirstNodeTick, nodeValue).x();
    const qreal lastX =
        nodePoint(view, *m_automationInput, lane, kFirstNodeTick + 1, nodeValue).x();
    const QRectF reticle((firstX + lastX) / 2.0 - 2.0, lane.body.top() + 2.0, 4.0, 6.0);
    QVERIFY(checks::support::layerHasColorIn(
                scene->layer(songview::TimelineQuickLayer::AutomationSelection), reticle, edge) ||
            checks::support::layerHasColorIn(
                scene->layer(songview::TimelineQuickLayer::AutomationSelection),
                QRectF(firstX + 4.0, lane.body.center().y() - 2.0, 8.0, 4.0), fill));

    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::halfOpenTimeSelectionComposesNodeRings()
{
    SongDocument &document = m_tab->document();
    SongView &view = m_tab->view();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    setCc(document, {{48, 40}, {72, 80}, {120, 55}});
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    const LanePaint lane = lanePaint(*m_page, LaneKind::Cc);
    QVERIFY(!lane.body.isEmpty());
    const QPointF first = nodePoint(view, *m_automationInput, lane, 48, 40);
    const QPointF second = nodePoint(view, *m_automationInput, lane, 72, 80);
    const QPointF third = nodePoint(view, *m_automationInput, lane, 120, 55);
    const QColor highlight = m_automationInput->palette().highlight().color();
    const AutomationGeometry geometry = AutomationGeometry::resolve();

    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = 48;
    selection.endTick = 72;
    const quint64 initialRevision =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision;
    view.selectionModel().setTimeSelection(selection);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision >
                initialRevision);
    const songview::TimelineQuickLayerData excluded =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes);
    QVERIFY(checks::support::layerHasRingAt(excluded, first, geometry.selectedNodeRingRadius,
                                            geometry.selectedNodeRingDipWidth, highlight));
    QVERIFY(!checks::support::layerHasRingAt(excluded, second, geometry.selectedNodeRingRadius,
                                             geometry.selectedNodeRingDipWidth, highlight));
    QVERIFY(!checks::support::layerHasRingAt(excluded, third, geometry.selectedNodeRingRadius,
                                             geometry.selectedNodeRingDipWidth, highlight));

    selection.endTick = 73;
    const quint64 excludedRevision = excluded.revision;
    view.selectionModel().setTimeSelection(selection);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationNodes).revision >
                excludedRevision);
    const songview::TimelineQuickLayerData included =
        scene->layer(songview::TimelineQuickLayer::AutomationNodes);
    QVERIFY(checks::support::layerHasRingAt(included, first, geometry.selectedNodeRingRadius,
                                            geometry.selectedNodeRingDipWidth, highlight));
    QVERIFY(checks::support::layerHasRingAt(included, second, geometry.selectedNodeRingRadius,
                                            geometry.selectedNodeRingDipWidth, highlight));
    QVERIFY(!checks::support::layerHasRingAt(included, third, geometry.selectedNodeRingRadius,
                                             geometry.selectedNodeRingDipWidth, highlight));

    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}
