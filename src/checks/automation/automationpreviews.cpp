#include "checks/automation/tst_automationediting.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QAbstractItemModel>
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

namespace {

constexpr uint8_t kController = 10;
constexpr uint64_t kNodeTick = 96;
constexpr uint64_t kSecondTick = 144;
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

struct PreviewLane final {
    LaneHandle handle;
    QRect body;
    int minimum = 0;
    int maximum = 0;
};

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

PreviewLane previewLane(AutomationPage &page, LaneKind kind)
{
    if (kind == LaneKind::Tempo) {
        const LaneHandle handle{0};
        return {handle, page.canvas()->laneBody(handle), CoreTimeDefaults::kMinTempoBpm,
                CoreTimeDefaults::kMaxTempoBpm};
    }
    const auto &rows = page.canvas()->rows();
    for (int row = 0; row < int(rows.size()); ++row) {
        if (rows[std::size_t(row)].id.controller == kController) {
            const LaneHandle handle{row + 1};
            return {handle, page.canvas()->laneBody(handle), 0, 127};
        }
    }
    return {};
}

QPointF pointForLane(const SongView &view, const songview::TimelineInputItem &input,
                     const PreviewLane &lane, uint64_t tick, int value)
{
    return {view.camera().displayX(double(tick), 0.0, input.devicePixelRatio()),
            AutomationProjection::valueY(lane.body, AutomationGeometry::resolve(), lane.minimum,
                                         lane.maximum, value)};
}

QRectF nodeProbe(const QPointF &center, qreal radius)
{
    return {center.x() - radius, center.y() - radius, 2.0 * radius, 2.0 * radius};
}

QRectF lineProbe(const QPointF &center, qreal halfWidth, qreal halfHeight)
{
    return {center.x() - halfWidth, center.y() - halfHeight, 2.0 * halfWidth, 2.0 * halfHeight};
}

QRectF previewLabelProbe(qreal x, qreal y, const QRect &plot)
{
    const int gap = layout::space(layout::Space::One);
    const int half = layout::space(layout::Space::Half);
    QRectF rect(x + gap + half, y - gap - layout::fontPx(1.0), layout::fontPx(2.0),
                layout::fontPx(1.0));
    if (rect.right() > plot.right())
        rect.moveRight(plot.right());
    if (rect.left() < plot.left())
        rect.moveLeft(plot.left());
    if (rect.top() < plot.top())
        rect.moveTop(plot.top());
    if (rect.bottom() > plot.bottom())
        rect.moveBottom(plot.bottom());
    return rect.intersected(plot);
}

bool textModelHasRecordIn(QAbstractItemModel *model, const QRectF &probe)
{
    if (!model)
        return false;
    for (int row = 0; row < model->rowCount(); ++row) {
        const QModelIndex index = model->index(row, 0);
        const QRectF rect =
            model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        const QColor color =
            model->data(index, songview::TimelineQuickTextModel::ColorRole).value<QColor>();
        if (!model->data(index, songview::TimelineQuickTextModel::TextRole).toString().isEmpty() &&
            color.isValid() && color.alpha() > 0 && rect.intersects(probe)) {
            return true;
        }
    }
    return false;
}

} // namespace

void AutomationEditingTest::singleNodeDragPreview_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("tempo") << int(LaneKind::Tempo);
    QTest::newRow("cc") << int(LaneKind::Cc);
}

void AutomationEditingTest::singleNodeDragPreview()
{
    QFETCH(int, laneKind);
    const LaneKind kind = LaneKind(laneKind);
    QVERIFY(kind != LaneKind::Tempo || expandTempo());
    QVERIFY(activateParameter(rowId(kind)));
    SongView &view = m_tab->view();
    SongDocument &document = m_tab->document();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    if (kind == LaneKind::Tempo) {
        setTempo(document,
                 {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
                  {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)},
                  {kSecondTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoSecond)}});
    } else {
        setCc(document, {{0, kCcHeld}, {kNodeTick, kCcNode}, {kSecondTick, kCcSecond}});
    }
    const PreviewLane lane = previewLane(*m_page, kind);
    QVERIFY(!lane.body.isEmpty());
    const int nodeValue = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const QPointF source = pointForLane(view, *m_automationInput, lane, kNodeTick, nodeValue);
    const QPointF target =
        pointForLane(view, *m_automationInput, lane, kNodeTick + 48, nodeValue - 24);
    QVERIFY(m_automationInput->bounds().contains(source));
    QVERIFY(m_automationInput->bounds().contains(target));
    const int activationTravel = AutomationGeometry::resolve().nodeDragActivationDistance + 8;
    const QPoint sourceWindow = automationWindowPoint(source);
    const QPoint activationWindow = automationWindowPoint(source + QPointF(activationTravel, 0.0));
    const QPoint targetWindow = automationWindowPoint(target);
    const quint64 transientBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::LeftButton, sourceWindow, Qt::NoModifier);
    mouseMove(activationWindow, Qt::NoModifier);
    mouseMove(activationWindow + targetWindow - sourceWindow, Qt::NoModifier);
    const QColor preview = themes::color(themes::Role::song_view_edit_preview_outline);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientBefore);
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationTransient),
        nodeProbe(target, nodelane::hoverRingRadius(AutomationGeometry::resolve())), preview));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::multiNodeDragPreview_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("tempo") << int(LaneKind::Tempo);
    QTest::newRow("cc") << int(LaneKind::Cc);
}

void AutomationEditingTest::multiNodeDragPreview()
{
    QFETCH(int, laneKind);
    const LaneKind kind = LaneKind(laneKind);
    QVERIFY(kind != LaneKind::Tempo || expandTempo());
    QVERIFY(activateParameter(rowId(kind)));
    SongView &view = m_tab->view();
    SongDocument &document = m_tab->document();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    if (kind == LaneKind::Tempo) {
        setTempo(document,
                 {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
                  {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)},
                  {kSecondTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoSecond)}});
    } else {
        setCc(document, {{0, kCcHeld}, {kNodeTick, kCcNode}, {kSecondTick, kCcSecond}});
    }
    const PreviewLane lane = previewLane(*m_page, kind);
    QVERIFY(!lane.body.isEmpty());
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kNodeTick - 24;
    selection.endTick = kSecondTick + 48;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    if (kind == LaneKind::Tempo)
        selection.tempo = true;
    else
        selection.lanes = {{0, kController}};
    view.selectionModel().setTimeSelection(selection);
    const int nodeValue = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const int secondValue = kind == LaneKind::Tempo ? kTempoSecond : kCcSecond;
    const QPointF source = pointForLane(view, *m_automationInput, lane, kNodeTick, nodeValue);
    const QPointF target = pointForLane(view, *m_automationInput, lane, kNodeTick, nodeValue - 24);
    const QPointF second =
        pointForLane(view, *m_automationInput, lane, kSecondTick, secondValue - 24);
    const int activationTravel = AutomationGeometry::resolve().nodeDragActivationDistance + 8;
    const QPoint sourceWindow = automationWindowPoint(source);
    const QPoint activationWindow = automationWindowPoint(source + QPointF(activationTravel, 0.0));
    const QPoint targetWindow = automationWindowPoint(target);
    const quint64 transientBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::LeftButton, sourceWindow, Qt::NoModifier);
    mouseMove(activationWindow, Qt::NoModifier);
    mouseMove(activationWindow + targetWindow - sourceWindow, Qt::NoModifier);
    const QColor preview = themes::color(themes::Role::song_view_edit_preview_outline);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientBefore);
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationTransient),
        nodeProbe(target, nodelane::hoverRingRadius(AutomationGeometry::resolve())), preview));
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationTransient),
        nodeProbe(second, nodelane::hoverRingRadius(AutomationGeometry::resolve())), preview));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::sweepPreview_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("tempo") << int(LaneKind::Tempo);
    QTest::newRow("cc") << int(LaneKind::Cc);
}

void AutomationEditingTest::sweepPreview()
{
    QFETCH(int, laneKind);
    const LaneKind kind = LaneKind(laneKind);
    QVERIFY(kind != LaneKind::Tempo || expandTempo());
    QVERIFY(activateParameter(rowId(kind)));
    SongView &view = m_tab->view();
    SongDocument &document = m_tab->document();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    if (kind == LaneKind::Tempo)
        setTempo(document, {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)}});
    else
        setCc(document, {{0, kCcHeld}});
    const PreviewLane lane = previewLane(*m_page, kind);
    const int held = kind == LaneKind::Tempo ? kTempoHeld : kCcHeld;
    const int node = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const QPointF start = pointForLane(view, *m_automationInput, lane, 48, (held + node) / 2);
    const QPointF target =
        pointForLane(view, *m_automationInput, lane, 144, (held + node) / 2 + 40);
    const int activationTravel = AutomationGeometry::resolve().nodeDragActivationDistance + 8;
    const QPoint startWindow = automationWindowPoint(start);
    const QPoint activationWindow = automationWindowPoint(start + QPointF(activationTravel, 0.0));
    const QPoint targetWindow = automationWindowPoint(target);
    const quint64 transientBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::LeftButton, startWindow, Qt::NoModifier);
    mouseMove(activationWindow, Qt::NoModifier);
    mouseMove(activationWindow + targetWindow - startWindow, Qt::NoModifier);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientBefore);
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationTransient),
        nodeProbe(target, nodelane::hoverRingRadius(AutomationGeometry::resolve())),
        themes::color(themes::Role::song_view_edit_preview_outline)));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::shiftRampPreview_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("tempo") << int(LaneKind::Tempo);
    QTest::newRow("cc") << int(LaneKind::Cc);
}

void AutomationEditingTest::shiftRampPreview()
{
    QFETCH(int, laneKind);
    const LaneKind kind = LaneKind(laneKind);
    QVERIFY(kind != LaneKind::Tempo || expandTempo());
    QVERIFY(activateParameter(rowId(kind)));
    SongView &view = m_tab->view();
    SongDocument &document = m_tab->document();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    if (kind == LaneKind::Tempo)
        setTempo(document, {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)}});
    else
        setCc(document, {{0, kCcHeld}});
    const PreviewLane lane = previewLane(*m_page, kind);
    const int held = kind == LaneKind::Tempo ? kTempoHeld : kCcHeld;
    const int node = kind == LaneKind::Tempo ? kTempoNode : kCcNode;
    const QPointF start = pointForLane(view, *m_automationInput, lane, 48, held);
    const QPointF end = pointForLane(view, *m_automationInput, lane, kSecondTick, node);
    const int activationTravel = AutomationGeometry::resolve().nodeDragActivationDistance + 8;
    const quint64 transientBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::LeftButton, automationWindowPoint(start), Qt::ShiftModifier);
    mouseMove(automationWindowPoint(start + QPointF(activationTravel, 0.0)), Qt::ShiftModifier);
    mouseMove(automationWindowPoint(end), Qt::ShiftModifier);
    const QPointF mid = (start + end) / 2.0;
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientBefore);
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationTransient), lineProbe(mid, 3.0, 3.0),
        themes::color(themes::Role::song_view_edit_preview_outline)));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::pencilPreviewAndValueLabel()
{
    SongView &view = m_tab->view();
    SongDocument &document = m_tab->document();
    auto *scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    setCc(document, {{0, kCcHeld}, {kNodeTick, kCcNode}, {kSecondTick, kCcSecond}});
    const PreviewLane lane = previewLane(*m_page, LaneKind::Cc);
    QVERIFY(!lane.body.isEmpty());
    setPencilMode(true);
    const QPointF start = pointForLane(view, *m_automationInput, lane, 24, 40);
    const QPointF hold = pointForLane(view, *m_automationInput, lane, 72, 40);
    const QPointF end = pointForLane(view, *m_automationInput, lane, 120, 100);
    const quint64 transientBefore =
        scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    mousePress(Qt::LeftButton, automationWindowPoint(start), Qt::NoModifier);
    mouseMove(automationWindowPoint(hold), Qt::NoModifier);
    mouseMove(automationWindowPoint(end), Qt::NoModifier);
    const QColor preview = themes::color(themes::Role::song_view_edit_preview_outline);
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                transientBefore);
    QVERIFY(checks::support::layerHasColorIn(
        scene->layer(songview::TimelineQuickLayer::AutomationTransient),
        lineProbe(pointForLane(view, *m_automationInput, lane, 48, 40), 8.0,
                  std::max(qreal(layout::singlePixel()),
                           qreal(AutomationGeometry::resolve().hoverPaintPadding + 1))),
        preview));
    QVERIFY(textModelHasRecordIn(scene->automationTransientTextModel(),
                                 previewLabelProbe(end.x(), end.y(), lane.body)));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}

void AutomationEditingTest::editCursorTracksQuickView()
{
    SongView &view = m_tab->view();
    auto *quick = view.quickView();
    QVERIFY(quick);
    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState before = frozenDocumentState(documentChanged.count(), edited.count());
    view.setEditCursorTick(24);
    QTRY_VERIFY(quick->editVisible());
    const qreal firstX = quick->editRootContentX();
    view.setEditCursorTick(96);
    QTRY_VERIFY(quick->editVisible());
    const qreal secondX = quick->editRootContentX();
    const qreal expected =
        view.camera().displayX(96.0, 0.0, m_automationInput->devicePixelRatio()) -
        view.camera().displayX(24.0, 0.0, m_automationInput->devicePixelRatio());
    QVERIFY(!qFuzzyCompare(firstX, secondX));
    QVERIFY(std::abs((secondX - firstX) - expected) < 0.5);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == before);
}
