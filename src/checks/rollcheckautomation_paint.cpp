#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QAbstractItemModel>
#include <QAction>
#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QUndoStack>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/nodelane/hover.h"
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
void checkAutomationTempoOcclusion(SongView &view, AutomationPage &page, SongDocument &document,
                                   DrawerPageLiveState &live, int &failures);
void checkAutomationCanvasFontPaint(SongView &view, AutomationPage &page, SongDocument &document,
                                    DrawerPageLiveState &live, int &failures);

namespace {

songview::TimelineInputItem *automationInputItem(SongView &view, const QString &objectName)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(objectName)
               : nullptr;
}

// Band input delivery: the Quick input item normalizes raw events in
// viewport coordinates, so content-coordinate probes shift by the page
// scroll before each send.
struct AutomationBandInput {
    AutomationPage &page;
    songview::TimelineInputItem &item;

    void mouse(QEvent::Type type, const QPointF &contentPosition, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendMouse(item, type, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  button, buttons, modifiers);
    }
    void leave() const { mouse(QEvent::Leave, {}, Qt::NoButton, Qt::NoButton, Qt::NoModifier); }
};

enum class LaneKind { Tempo, Cc };

struct LaneCase {
    LaneKind kind = LaneKind::Tempo;
    const char *name = "";
};

struct DocSnap {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;
};

struct LaneGeom {
    LaneHandle handle;
    QRect body;
    QRect plot;
    QColor curveColor;
};

constexpr LaneCase kLanes[] = {
    {LaneKind::Tempo, "Tempo"},
    {LaneKind::Cc, "CC"},
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

void sendActivatedDrag(const AutomationBandInput &band, const QPointF &start, const QPointF &target,
                       int activationDistance, Qt::KeyboardModifiers modifiers)
{
    const QPointF activation = start + QPointF(activationDistance, 0);
    band.mouse(QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton, modifiers);
    band.mouse(QEvent::MouseMove, activation, Qt::NoButton, Qt::LeftButton, modifiers);
    band.mouse(QEvent::MouseMove, activation + target - start, Qt::NoButton, Qt::LeftButton,
               modifiers);
}

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

QPoint automationPlotContentToViewport(const AutomationPage &page)
{
    return {0, -page.verticalScroll()};
}

void leaveCanvas(const AutomationBandInput &band)
{
    band.leave();
    pump();
}

DocSnap snapshot(SongDocument &document)
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

bool unchanged(const DocSnap &before, const DocSnap &after)
{
    return after.smf == before.smf && after.revision == before.revision &&
           after.undoIndex == before.undoIndex;
}

QRectF bounds(const songview::TimelineQuickTriangle &triangle)
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
        if (bounds(triangle).intersects(probe) &&
            (triangle.firstColor == color || triangle.secondColor == color ||
             triangle.thirdColor == color)) {
            return true;
        }
    }
    return false;
}

bool textModelHasRecordIn(QAbstractItemModel *model, const QRectF &contentProbe,
                          const QPoint &contentOrigin)
{
    if (!model)
        return false;
    const QRectF probe = contentProbe.translated(contentOrigin);
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

QRectF nodeProbe(qreal x, qreal y, qreal radius)
{
    return {x - radius, y - radius, 2 * radius, 2 * radius};
}

QRectF lineProbe(qreal x, qreal y, qreal halfWidth, qreal halfHeight)
{
    return {x - halfWidth, y - halfHeight, 2 * halfWidth, 2 * halfHeight};
}

QRectF previewLabelProbe(qreal x, qreal y, const QRect &plot)
{
    const int gap = layout::space(layout::Space::One);
    const int half = layout::space(layout::Space::Half);
    const int width = layout::fontPx(2.0);
    const int height = layout::fontPx(1.0);
    QRectF rect(x + gap + half, y - gap - height, width, height);
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
bool framebufferHasColorNear(const QImage &framebuffer, const QPointF &point,
                             const QColor &expected)
{
    if (framebuffer.isNull())
        return false;
    const qreal dpr = framebuffer.devicePixelRatio();
    if (dpr <= 0.0)
        return false;
    constexpr int kColorTolerance = 64;
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

QPointF tempoHeaderPoint(const AutomationPage &page)
{
    const QRect tempo = page.canvas()->pinnedTempoRect();
    return {qreal(layout::space(layout::Space::One)), qreal(tempo.center().y())};
}

int panRowIndex(const AutomationPage &page)
{
    const auto &rows = page.canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id.controller == 10)
            return index;
    }
    return -1;
}

QAction *pencilModeAction(AutomationPage &page)
{
    for (QAction *action : page.findChildren<QAction *>()) {
        if (action->text() == QStringLiteral("Pencil Mode"))
            return action;
    }
    return nullptr;
}

void refresh(AutomationPage &page, SongDocument &document, DrawerPageLiveState &live)
{
    live.documentRevision = document.revision();
    page.documentChanged();
    page.refreshLiveState(live);
    pump();
}

void setTempoPoints(AutomationPage &page, SongDocument &document, DrawerPageLiveState &live,
                    const std::vector<TempoPoint> &points)
{
    if (document.tempoPoints() == points)
        return;
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = points;
    document.applyTempoEdit(edit);
    refresh(page, document, live);
}

void setCcPoints(AutomationPage &page, SongDocument &document, DrawerPageLiveState &live,
                 const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(0, uint8_t{10}, 0, std::numeric_limits<uint64_t>::max(), points);
    refresh(page, document, live);
}

bool toggleTempoExpanded(SongView &view, AutomationPage &page, bool wantExpanded, int &)
{
    const bool expanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (expanded == wantExpanded)
        return expanded;
    AutomationBandInput gutter{
        page, *automationInputItem(view, QStringLiteral("timelineAutomationGutterInput"))};
    gutter.mouse(QEvent::MouseButtonPress, tempoHeaderPoint(page), Qt::LeftButton, Qt::LeftButton,
                 Qt::NoModifier);
    gutter.mouse(QEvent::MouseButtonRelease, tempoHeaderPoint(page), Qt::LeftButton, Qt::NoButton,
                 Qt::NoModifier);
    pump();
    return !page.canvas()->laneBody(LaneHandle{0}).isEmpty() == wantExpanded;
}

LaneGeom laneGeom(AutomationPage &page, const LaneCase &row)
{
    LaneGeom geom;
    if (row.kind == LaneKind::Tempo) {
        geom.handle = LaneHandle{0};
        geom.body = page.canvas()->laneBody(geom.handle);
        geom.curveColor = themes::color(themes::Role::song_view_automation_tempo_curve);
    } else {
        const int panRow = panRowIndex(page);
        if (panRow < 0)
            return geom;
        geom.handle = LaneHandle{panRow + 1};
        geom.body = page.canvas()->laneBody(geom.handle);
        geom.curveColor = themes::trackIdentityColor(0);
    }
    geom.plot = geom.body;
    return geom;
}

} // namespace

void checkAutomationNodePaint(SongView &view, AutomationPage &page, SongDocument &document,
                              DrawerPageLiveState &live, int &failures)
{
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-check: FAIL paint: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const auto report = [&check](const char *name, bool condition, const QString &message) {
        check(condition, QStringLiteral("%1: %2").arg(QLatin1String(name), message));
    };
    view.setEditCursorTick(480);
    live.timeZoom = 96.0;
    live.horizontalScroll = 0.0;
    view.setEditorTimeZoom(live.timeZoom);
    view.setEditorHorizontalScroll(live.horizontalScroll);
    view.selectionModel().clearTimeSelection();
    if (QAction *pencil = pencilModeAction(page))
        pencil->setChecked(false);
    refresh(page, document, live);
    const auto startSnap = snapshot(document);
    const auto startTempo = document.tempoPoints();
    TempoLane tempoLane(document);
    CCLaneAdapter ccLane(document, 0, uint8_t{10});
    const bool tempoExpanded = toggleTempoExpanded(view, page, true, failures);
    check(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"));
    checkAutomationCanvasFontPaint(view, page, document, live, failures);
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    auto *quickView =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    check(quickScene && quickView,
          QStringLiteral("retained Quick automation scene was not available"));
    const auto layerRevision = [quickScene](songview::TimelineQuickLayer layer) {
        return quickScene ? quickScene->layer(layer).revision : quint64{0};
    };
    const auto layerHas = [quickScene](songview::TimelineQuickLayer layer,
                                       const QRectF &contentProbe, const QPoint &contentOrigin,
                                       const QColor &color) {
        return quickScene &&
               layerHasColorIn(quickScene->layer(layer), contentProbe, contentOrigin, color);
    };
    auto geometry = AutomationGeometry::resolve();
    const AutomationBandInput band{
        page, *automationInputItem(view, QStringLiteral("timelineAutomationInput"))};
    const qreal dpr = band.item.devicePixelRatio();
    const QPoint plotContentOrigin = automationPlotContentToViewport(page);
    const auto &automationBandGeometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    const auto automationBandRect = [&]() -> QRect {
        return automationBandGeometry ? automationBandGeometry->rect : QRect{};
    };
    const int automationGutterWidth =
        automationBandGeometry
            ? std::max(0, automationBandGeometry->plotRect.x() - automationBandGeometry->rect.x())
            : 0;
    const QPoint plotFramebufferOrigin = plotContentOrigin + QPoint(automationGutterWidth, 0);
    const auto captureAutomationViewport = [&] {
        QString error;
        const QImage image = checks::support::captureQuickBand(view, automationBandRect(), &error);
        report("framebuffer", !image.isNull(),
               QStringLiteral("automation viewport framebuffer capture failed: %1").arg(error));
        return image;
    };
    const qreal radius = nodelane::hoverRingRadius(geometry);
    const qreal lineHalf =
        std::max(qreal(layout::singlePixel()), qreal(geometry.hoverPaintPadding + 1));
    const auto tickX = [&](uint64_t tick) {
        return view.camera().displayX(double(tick), 0.0, dpr);
    };
    const auto paintUnchanged = [&](const char *label, const DocSnap &before) {
        check(unchanged(before, snapshot(document)),
              QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
    };
    const auto cancel = [&] {
        page.cancelInteraction();
        leaveCanvas(band);
    };
    // Tempo leadIn: empty storage, first nonzero point, explicit tick-0.
    setTempoPoints(page, document, live, {});
    leaveCanvas(band);
    const auto emptySnap = snapshot(document);
    paintUnchanged("empty Tempo paint", emptySnap);
    const auto tempoGeom = laneGeom(page, kLanes[0]);
    check(!tempoGeom.plot.isEmpty(), QStringLiteral("Tempo: expanded body plot is empty"));
    const qreal y120 =
        nodelane::valueY(tempoLane, tempoGeom.body, geometry, CoreTimeDefaults::kTempoBpm);
    const qreal y200 = nodelane::valueY(tempoLane, tempoGeom.body, geometry, kTempoNode);
    const qreal y80 = nodelane::valueY(tempoLane, tempoGeom.body, geometry, kTempoHeld);
    const qreal x0 = tickX(0);
    const qreal xMid = tickX(48);
    const qreal x96 = tickX(kNodeTick);
    report("Tempo",
           !layerHas(songview::TimelineQuickLayer::AutomationCurves,
                     lineProbe(xMid, y120, 8, lineHalf), plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("empty storage composed a 120 lead-in curve"));
    report("Tempo",
           !layerHas(songview::TimelineQuickLayer::AutomationNodes, nodeProbe(x0, y120, radius),
                     plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("empty storage composed a 120 lead-in node"));
    setTempoPoints(page, document, live,
                   {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)}});
    const auto leadSnap = snapshot(document);
    leaveCanvas(band);
    paintUnchanged("Tempo lead-in paint", leadSnap);
    report("Tempo",
           layerHas(songview::TimelineQuickLayer::AutomationCurves,
                    lineProbe(xMid, y120, 8, lineHalf), plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("first nonzero point composed no 120 lead-in"));
    report("Tempo",
           !layerHas(songview::TimelineQuickLayer::AutomationNodes, nodeProbe(x0, y120, radius),
                     plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("120 lead-in composed a tick-0 node"));
    report("Tempo",
           layerHas(songview::TimelineQuickLayer::AutomationNodes, nodeProbe(x96, y200, radius),
                    plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("first nonzero point composed no node"));
    setTempoPoints(page, document, live,
                   {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)}});
    const auto tick0Snap = snapshot(document);
    leaveCanvas(band);
    paintUnchanged("Tempo tick-0 paint", tick0Snap);
    report("Tempo",
           layerHas(songview::TimelineQuickLayer::AutomationNodes, nodeProbe(x0, y80, radius),
                    plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("explicit tick-0 point composed no node"));
    report("Tempo",
           !layerHas(songview::TimelineQuickLayer::AutomationCurves,
                     lineProbe(xMid, y120, 8, lineHalf), plotContentOrigin, tempoGeom.curveColor),
           QStringLiteral("explicit tick-0 point did not suppress 120 lead-in"));
    // Normal curves, selected rings, and live gesture previews for both lanes.
    for (const auto &row : kLanes) {
        const quint64 curvesRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationCurves);
        const quint64 nodesRevision = layerRevision(songview::TimelineQuickLayer::AutomationNodes);
        NodeLane &lane = row.kind == LaneKind::Tempo ? static_cast<NodeLane &>(tempoLane)
                                                     : static_cast<NodeLane &>(ccLane);
        if (row.kind == LaneKind::Tempo) {
            setTempoPoints(
                page, document, live,
                {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
                 {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)},
                 {kSecondTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoSecond)}});
        } else {
            setCcPoints(page, document, live,
                        {{kHeldTick, kCcHeld}, {kNodeTick, kCcNode}, {kSecondTick, kCcSecond}});
        }
        const auto geom = laneGeom(page, row);
        if (!geom.handle.valid() || geom.plot.isEmpty()) {
            report(row.name, false, QStringLiteral("lane body is missing from the canvas stack"));
            continue;
        }
        const int held = row.kind == LaneKind::Tempo ? kTempoHeld : kCcHeld;
        const int node = row.kind == LaneKind::Tempo ? kTempoNode : kCcNode;
        const int second = row.kind == LaneKind::Tempo ? kTempoSecond : kCcSecond;
        const qreal heldY = nodelane::valueY(lane, geom.body, geometry, held);
        const qreal nodeY = nodelane::valueY(lane, geom.body, geometry, node);
        const qreal nodeX = tickX(kNodeTick);
        const qreal secondX = tickX(kSecondTick);
        const qreal midX = tickX(48);
        leaveCanvas(band);
        const auto idleSnap = snapshot(document);
        paintUnchanged(row.name, idleSnap);
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationCurves) > curvesRevision &&
                   layerRevision(songview::TimelineQuickLayer::AutomationNodes) > nodesRevision,
               QStringLiteral("document refresh did not rebuild the Quick curves and nodes"));
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationCurves,
                        lineProbe(midX, heldY, 8, lineHalf), plotContentOrigin, geom.curveColor),
               QStringLiteral("normal step curve is missing from the retained Quick layer"));
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationNodes,
                        nodeProbe(nodeX, nodeY, radius), plotContentOrigin, geom.curveColor),
               QStringLiteral("normal node is missing from the retained Quick layer"));
        const QImage normalFramebuffer = captureAutomationViewport();
        report(row.name,
               framebufferHasColorNear(normalFramebuffer,
                                       QPointF(plotFramebufferOrigin) + QPointF(midX, heldY),
                                       geom.curveColor) &&
                   framebufferHasColorNear(normalFramebuffer,
                                           QPointF(plotFramebufferOrigin) + QPointF(nodeX, nodeY),
                                           geom.curveColor),
               QStringLiteral("normal step curve or node did not render at its Quick position"));
        const quint64 selectionRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationSelection);
        const quint64 selectedNodesRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationNodes);
        songview::EditorSelectionModel::TimeSelection selection;
        selection.startTick = kNodeTick;
        selection.endTick = kNodeTick + 1;
        selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        if (row.kind == LaneKind::Tempo)
            selection.tempo = true;
        else
            selection.lanes = {{0, 10}};
        view.selectionModel().setTimeSelection(selection);
        refresh(page, document, live);
        leaveCanvas(band);
        const auto selectedSnap = snapshot(document);
        paintUnchanged(row.name, selectedSnap);
        const qreal ringOuter = geometry.selectedNodeRingRadius + layout::singlePixel();
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationNodes,
                        nodeProbe(nodeX, nodeY, ringOuter), plotContentOrigin,
                        band.item.palette().highlight().color()),
               QStringLiteral("selected ring is missing from the retained Quick node layer"));
        const QImage selectedFramebuffer = captureAutomationViewport();
        report(row.name,
               framebufferHasColorNear(selectedFramebuffer,
                                       QPointF(plotFramebufferOrigin) +
                                           QPointF(nodeX, nodeY - geometry.selectedNodeRingRadius),
                                       band.item.palette().highlight().color()),
               QStringLiteral("selected ring did not render at its Quick node position"));
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationSelection) >
                       selectionRevision &&
                   layerRevision(songview::TimelineQuickLayer::AutomationNodes) >
                       selectedNodesRevision,
               QStringLiteral("selected-node change did not rebuild the retained Quick node and "
                              "selection layers"));
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationSelection,
                        QRectF((tickX(kNodeTick) + tickX(kNodeTick + 1)) / 2.0 - 2.0,
                               geom.plot.top() + 2.0, 4.0, 6.0),
                        plotContentOrigin, themes::color(themes::Role::song_view_selection_edge)) ||
                   layerHas(songview::TimelineQuickLayer::AutomationSelection,
                            QRectF(tickX(kNodeTick) + 4.0, geom.body.center().y() - 2.0, 8.0, 4.0),
                            plotContentOrigin,
                            themes::color(themes::Role::song_view_selection_fill)),
               QStringLiteral("selection reticle is missing from the retained Quick layer"));
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
        const QPointF nodePos(nodeX, nodeY);
        const quint64 dragRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationTransient);
        const int drag = geometry.nodeDragActivationDistance + 8;
        const QPointF dragTarget(tickX(kNodeTick + 48),
                                 nodelane::valueY(lane, geom.body, geometry, node - 24));
        sendActivatedDrag(band, nodePos, dragTarget, drag, Qt::NoModifier);
        pump();
        const auto dragSnap = snapshot(document);
        paintUnchanged(row.name, dragSnap);
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationTransient,
                        nodeProbe(dragTarget.x(), dragTarget.y(), radius), plotContentOrigin,
                        themes::color(themes::Role::song_view_edit_preview_outline)),
               QStringLiteral("node drag preview is missing from the retained Quick layer"));
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationTransient) > dragRevision,
               QStringLiteral("node drag did not rebuild the Quick transient layer"));
        cancel();
        selection.startTick = kNodeTick - 24;
        selection.endTick = kSecondTick + 48;
        if (row.kind == LaneKind::Tempo)
            selection.tempo = true;
        else
            selection.lanes = {{0, 10}};
        view.selectionModel().setTimeSelection(selection);
        refresh(page, document, live);
        const quint64 multiRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationTransient);
        const QPointF multiTarget(nodeX, nodelane::valueY(lane, geom.body, geometry, node - 24));
        sendActivatedDrag(band, nodePos, multiTarget, drag, Qt::NoModifier);
        pump();
        const auto multiSnap = snapshot(document);
        paintUnchanged(row.name, multiSnap);
        const QPointF secondPreview(secondX,
                                    nodelane::valueY(lane, geom.body, geometry, second - 24));
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationTransient,
                        nodeProbe(multiTarget.x(), multiTarget.y(), radius), plotContentOrigin,
                        themes::color(themes::Role::song_view_edit_preview_outline)) &&
                   layerHas(songview::TimelineQuickLayer::AutomationTransient,
                            nodeProbe(secondPreview.x(), secondPreview.y(), radius),
                            plotContentOrigin,
                            themes::color(themes::Role::song_view_edit_preview_outline)),
               QStringLiteral("multi-drag preview is missing from the retained Quick layer"));
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationTransient) > multiRevision,
               QStringLiteral("multi-drag did not rebuild the Quick transient layer"));
        cancel();
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
        const quint64 sweepRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationTransient);
        const QPointF sweepStart(tickX(48),
                                 nodelane::valueY(lane, geom.body, geometry, (held + node) / 2));
        const QPointF sweepTarget(
            tickX(144), nodelane::valueY(lane, geom.body, geometry, (held + node) / 2 + 40));
        sendActivatedDrag(band, sweepStart, sweepTarget, drag, Qt::NoModifier);
        pump();
        const auto sweepSnap = snapshot(document);
        paintUnchanged(row.name, sweepSnap);
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationTransient,
                        nodeProbe(sweepTarget.x(), sweepTarget.y(), radius), plotContentOrigin,
                        themes::color(themes::Role::song_view_edit_preview_outline)),
               QStringLiteral("sweep preview is missing from the retained Quick layer"));
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationTransient) > sweepRevision,
               QStringLiteral("sweep did not rebuild the Quick transient layer"));
        cancel();
        const quint64 rampRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationTransient);
        const QPointF rampStart(tickX(48), heldY);
        const QPointF rampEnd(tickX(kSecondTick), nodeY);
        band.mouse(QEvent::MouseButtonPress, rampStart, Qt::LeftButton, Qt::LeftButton,
                   Qt::ShiftModifier);
        band.mouse(QEvent::MouseMove, rampStart + QPointF(drag, 0), Qt::NoButton, Qt::LeftButton,
                   Qt::ShiftModifier);
        band.mouse(QEvent::MouseMove, rampEnd, Qt::NoButton, Qt::LeftButton, Qt::ShiftModifier);
        pump();
        const auto rampSnap = snapshot(document);
        paintUnchanged(row.name, rampSnap);
        const QPointF rampMid((rampStart.x() + rampEnd.x()) / 2.0,
                              (rampStart.y() + rampEnd.y()) / 2.0);
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationTransient,
                        QRectF(rampMid.x() - 3.0, rampMid.y() - 3.0, 6.0, 6.0), plotContentOrigin,
                        themes::color(themes::Role::song_view_edit_preview_outline)),
               QStringLiteral("Shift-ramp preview is missing from the retained Quick layer"));
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationTransient) > rampRevision,
               QStringLiteral("Shift-ramp did not rebuild the Quick transient layer"));
        cancel();
        if (row.kind != LaneKind::Cc)
            continue;
        QAction *pencil = pencilModeAction(page);
        report(row.name, pencil != nullptr, QStringLiteral("Pencil Mode action is unavailable"));
        if (!pencil)
            continue;
        pencil->setChecked(true);
        pump();
        const quint64 pencilRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationTransient);
        const QPointF pencilStart(tickX(24), nodelane::valueY(lane, geom.body, geometry, 40));
        const QPointF pencilHold(tickX(72), nodelane::valueY(lane, geom.body, geometry, 40));
        const QPointF pencilEnd(tickX(120), nodelane::valueY(lane, geom.body, geometry, 100));
        band.mouse(QEvent::MouseButtonPress, pencilStart, Qt::LeftButton, Qt::LeftButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseMove, pencilHold, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        band.mouse(QEvent::MouseMove, pencilEnd, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        pump();
        const auto pencilSnap = snapshot(document);
        paintUnchanged(row.name, pencilSnap);
        report(row.name,
               layerHas(songview::TimelineQuickLayer::AutomationTransient,
                        lineProbe(tickX(48), pencilHold.y(), 8, lineHalf), plotContentOrigin,
                        themes::color(themes::Role::song_view_edit_preview_outline)),
               QStringLiteral("Pencil preview curve is missing from the retained Quick layer"));
        report(row.name,
               quickScene &&
                   textModelHasRecordIn(quickScene->automationTransientTextModel(),
                                        previewLabelProbe(pencilEnd.x(), pencilEnd.y(), geom.plot),
                                        plotContentOrigin),
               QStringLiteral("Pencil preview value label is missing from the retained Quick "
                              "text model"));
        report(row.name,
               layerRevision(songview::TimelineQuickLayer::AutomationTransient) > pencilRevision &&
                   quickScene && quickScene->automationTransientTextModel()->rowCount() > 0,
               QStringLiteral("Pencil preview did not reach the Quick transient layer and text "
                              "model"));
        cancel();
        pencil->setChecked(false);
        pump();
    }
    view.setEditCursorTick(24);
    pump();
    leaveCanvas(band);
    const auto cursorSnap = snapshot(document);
    const qreal cursorA = quickView ? quickView->editRootContentX() : 0.0;
    const bool cursorAVisible = quickView && quickView->editVisible();
    paintUnchanged("edit cursor", cursorSnap);
    view.setEditCursorTick(96);
    pump();
    leaveCanvas(band);
    const qreal cursorB = quickView ? quickView->editRootContentX() : 0.0;
    const bool cursorBVisible = quickView && quickView->editVisible();
    paintUnchanged("edit cursor move", cursorSnap);
    check(cursorAVisible && cursorBVisible,
          QStringLiteral("retained Quick edit chrome was not visible at both edit ticks"));
    check(quickView && !qFuzzyCompare(cursorA, cursorB) &&
              std::abs((cursorB - cursorA) - (tickX(96) - tickX(24))) < 0.5,
          QStringLiteral("retained Quick edit cursor x did not follow the edit tick"));
    checkAutomationTempoOcclusion(view, page, document, live, failures);
    cancel();
    if (QAction *pencil = pencilModeAction(page))
        pencil->setChecked(false);
    view.selectionModel().clearTimeSelection();
    document.undoStack()->setIndex(startSnap.undoIndex);
    live.documentRevision = document.revision();
    view.setEditCursorTick(24);
    page.documentChanged();
    page.refreshLiveState(live);
    toggleTempoExpanded(view, page, false, failures);
    pump();
    check(document.smf().write() == startSnap.smf &&
              document.undoStack()->index() == startSnap.undoIndex &&
              document.tempoPoints() == startTempo,
          QStringLiteral("paint coverage did not restore SMF, tempo, or undo"));
}
