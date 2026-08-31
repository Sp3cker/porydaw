#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QAction>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPainter>
#include <QString>
#include <QUndoStack>
#include <QWidget>

#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/nodelane/paint.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
void checkAutomationTempoOcclusion(SongView &view, AutomationPage &page, SongDocument &document,
                                   DrawerPageLiveState &live, int &failures);
void checkAutomationCanvasFontPaint(SongView &view, AutomationPage &page, SongDocument &document,
                                    DrawerPageLiveState &live, int &failures);

namespace {

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

void sendActivatedDrag(QWidget *widget, const QPointF &start, const QPointF &target,
                       int activationDistance, Qt::KeyboardModifiers modifiers)
{
    const QPointF activation = start + QPointF(activationDistance, 0);
    checks::events::sendMouse(*widget, QEvent::MouseButtonPress, start, Qt::LeftButton,
                              Qt::LeftButton, modifiers);
    checks::events::sendMouse(*widget, QEvent::MouseMove, activation, Qt::NoButton, Qt::LeftButton,
                              modifiers);
    checks::events::sendMouse(*widget, QEvent::MouseMove, activation + target - start, Qt::NoButton,
                              Qt::LeftButton, modifiers);
}

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void leaveCanvas(AutomationPage &page)
{
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(page.canvas(), &leave);
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

QRect deviceRect(const QRectF &logical, qreal dpr, const QSize &bound)
{
    const int left = std::clamp(int(std::floor(logical.left() * dpr)), 0, bound.width());
    const int top = std::clamp(int(std::floor(logical.top() * dpr)), 0, bound.height());
    const int right = std::clamp(int(std::ceil(logical.right() * dpr)), 0, bound.width());
    const int bottom = std::clamp(int(std::ceil(logical.bottom() * dpr)), 0, bound.height());
    return {left, top, std::max(0, right - left), std::max(0, bottom - top)};
}

int changedPixels(const QImage &idle, const QImage &hover, const QRectF &logical, qreal dpr)
{
    if (idle.size() != hover.size() || idle.format() != hover.format())
        return -1;
    const QRect rect = deviceRect(logical, dpr, idle.size()).intersected(idle.rect());
    if (rect.isEmpty())
        return -1;
    auto count = 0;
    for (int y = rect.top(); y <= rect.bottom(); ++y) {
        for (int x = rect.left(); x <= rect.right(); ++x) {
            if (idle.pixel(x, y) != hover.pixel(x, y))
                ++count;
        }
    }
    return count;
}

bool hasColorNear(const QImage &image, const QRectF &logical, qreal dpr, const QColor &expected,
                  int tolerance)
{
    const QRect rect = deviceRect(logical, dpr, image.size()).intersected(image.rect());
    for (int y = rect.top(); y <= rect.bottom(); ++y) {
        for (int x = rect.left(); x <= rect.right(); ++x) {
            const QColor actual(image.pixel(x, y));
            if (std::abs(actual.red() - expected.red()) <= tolerance &&
                std::abs(actual.green() - expected.green()) <= tolerance &&
                std::abs(actual.blue() - expected.blue()) <= tolerance)
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

QRectF labelProbe(qreal x, qreal y, const QRect &plot)
{
    const int gap = layout::space(layout::Space::One);
    const int width = layout::fontPx(2.0);
    const int height = layout::fontPx(1.0);
    QRectF rect(x - gap - width, y - gap - height, width, height);
    if (rect.left() < plot.left())
        rect.moveLeft(x + gap);
    if (rect.top() < plot.top())
        rect.moveTop(y + gap);
    return rect.intersected(plot);
}

int lineBudget(qreal radius, qreal dpr)
{
    return std::max(4, int(std::ceil(6.0 * radius * dpr)));
}

QPointF tempoHeaderPoint(const AutomationPage &page)
{
    const QRect tempo = page.canvas()->pinnedTempoRect();
    return {page.canvas()->plotOrigin() / 2.0, qreal(tempo.center().y())};
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
    for (QAction *action : page.actions()) {
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

bool toggleTempoExpanded(AutomationPage &page, bool wantExpanded, int &failures)
{
    const bool expanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (expanded == wantExpanded)
        return expanded;
    const QImage beforeToggle = page.canvas()->grab().toImage();
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, tempoHeaderPoint(page),
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease, tempoHeaderPoint(page),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    pump();
    if (page.canvas()->grab().toImage() == beforeToggle) {
        std::fprintf(stderr, "automation-check: FAIL paint: tempo header toggle did not repaint\n");
        ++failures;
    }
    return !page.canvas()->laneBody(LaneHandle{0}).isEmpty() == wantExpanded;
}

LaneGeom laneGeom(AutomationPage &page, const LaneCase &row)
{
    LaneGeom geom;
    auto geometry = AutomationGeometry::resolve();
    geometry.plotOrigin = page.canvas()->plotOrigin();
    if (row.kind == LaneKind::Tempo) {
        geom.handle = LaneHandle{0};
        geom.body = page.canvas()->laneBody(geom.handle);
        geom.curveColor = themes::color(themes::Role::song_view_automation_tempo_curve);
    } else {
        const int panRow = panRowIndex(page);
        if (panRow < 0)
            return geom;
        geom.handle = LaneHandle{panRow + 1};
        const auto &state = page.automationViewState();
        const int shared = state.laneHeight > 0 ? state.laneHeight : geometry.rowDefaultHeight;
        const auto &rows = page.canvas()->rows();
        int top = 0;
        for (int index = 0; index < panRow; ++index) {
            const auto it = state.laneHeights.find(rows[std::size_t(index)].id);
            top += std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                              geometry.rowMinimumHeight, geometry.rowMaximumHeight);
        }
        const auto it = state.laneHeights.find(rows[std::size_t(panRow)].id);
        const int height = std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                                      geometry.rowMinimumHeight, geometry.rowMaximumHeight);
        geom.body = {0, top, page.canvas()->width(), height};
        geom.curveColor = themes::trackIdentityColor(0);
    }
    geom.plot = nodelane::plotRect(geom.body, geometry);
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
    live.timeZoom = 96.0;
    live.horizontalScroll = 0.0;
    live.editCursorTick = 480;
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
    const bool tempoExpanded = toggleTempoExpanded(page, true, failures);
    check(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"));
    checkAutomationCanvasFontPaint(view, page, document, live, failures);
    auto geometry = AutomationGeometry::resolve();
    geometry.plotOrigin = page.canvas()->plotOrigin();
    const qreal dpr = page.canvas()->devicePixelRatioF();
    const qreal radius = nodelane::hoverRingRadius(geometry);
    const qreal lineHalf =
        std::max(qreal(layout::singlePixel()), qreal(geometry.hoverPaintPadding + 1));
    const auto tickX = [&](uint64_t tick) {
        return view.displayX(double(tick), geometry.plotOrigin, dpr);
    };
    const auto paintUnchanged = [&](const char *label, const DocSnap &before) {
        check(unchanged(before, snapshot(document)),
              QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
    };
    const auto cancel = [&] {
        page.cancelInteraction();
        leaveCanvas(page);
    };
    // Tempo leadIn: empty storage, first nonzero point, explicit tick-0.
    setTempoPoints(page, document, live, {});
    leaveCanvas(page);
    const auto emptySnap = snapshot(document);
    const QImage emptyTempo = page.canvas()->grab().toImage();
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
           !hasColorNear(emptyTempo, lineProbe(xMid, y120, 8, lineHalf), dpr, tempoGeom.curveColor,
                         12),
           QStringLiteral("empty storage painted a 120 lead-in curve"));
    report("Tempo",
           !hasColorNear(emptyTempo, nodeProbe(x0, y120, radius), dpr, tempoGeom.curveColor, 12),
           QStringLiteral("empty storage painted a 120 lead-in node"));
    setTempoPoints(page, document, live,
                   {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)}});
    const auto leadSnap = snapshot(document);
    leaveCanvas(page);
    const QImage leadTempo = page.canvas()->grab().toImage();
    paintUnchanged("Tempo lead-in paint", leadSnap);
    const int leadLine =
        changedPixels(emptyTempo, leadTempo, lineProbe(xMid, y120, 8, lineHalf), dpr);
    const int leadOrigin = changedPixels(emptyTempo, leadTempo, nodeProbe(x0, y120, radius), dpr);
    const int leadNode = changedPixels(emptyTempo, leadTempo, nodeProbe(x96, y200, radius), dpr);
    report("Tempo", leadLine > 0, QStringLiteral("first nonzero point painted no 120 lead-in"));
    report("Tempo", leadOrigin > 0 && leadOrigin <= lineBudget(radius, dpr),
           QStringLiteral("120 lead-in painted a tick-0 node"));
    report("Tempo", leadNode > lineBudget(radius, dpr),
           QStringLiteral("first nonzero point painted no node"));
    setTempoPoints(page, document, live,
                   {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)}});
    const auto tick0Snap = snapshot(document);
    leaveCanvas(page);
    const QImage tick0Tempo = page.canvas()->grab().toImage();
    paintUnchanged("Tempo tick-0 paint", tick0Snap);
    report("Tempo",
           changedPixels(emptyTempo, tick0Tempo, nodeProbe(x0, y80, radius), dpr) >
               lineBudget(radius, dpr),
           QStringLiteral("explicit tick-0 point painted no node"));
    report("Tempo",
           changedPixels(emptyTempo, tick0Tempo, lineProbe(xMid, y120, 8, lineHalf), dpr) <= 0,
           QStringLiteral("explicit tick-0 point did not suppress 120 lead-in"));
    // Normal curves, selected rings, and live gesture previews for both lanes.
    for (const auto &row : kLanes) {
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
        const qreal secondY = nodelane::valueY(lane, geom.body, geometry, second);
        const qreal heldX = tickX(kHeldTick);
        const qreal nodeX = tickX(kNodeTick);
        const qreal secondX = tickX(kSecondTick);
        const qreal midX = tickX(48);
        leaveCanvas(page);
        const auto idleSnap = snapshot(document);
        const QImage idle = page.canvas()->grab().toImage();
        paintUnchanged(row.name, idleSnap);
        report(row.name,
               hasColorNear(idle, lineProbe(midX, heldY, 8, lineHalf), dpr, geom.curveColor, 16),
               QStringLiteral("normal step curve is missing"));
        report(row.name,
               hasColorNear(idle, nodeProbe(nodeX, nodeY, radius), dpr, geom.curveColor, 16),
               QStringLiteral("normal node is missing"));
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
        leaveCanvas(page);
        const auto selectedSnap = snapshot(document);
        const QImage selected = page.canvas()->grab().toImage();
        paintUnchanged(row.name, selectedSnap);
        const qreal ringOuter = geometry.selectedNodeRingRadius + layout::singlePixel();
        report(row.name, changedPixels(idle, selected, nodeProbe(nodeX, nodeY, ringOuter), dpr) > 0,
               QStringLiteral("selected ring did not paint above the node"));
        report(
            row.name,
            hasColorNear(selected,
                         QRectF((tickX(kNodeTick) + tickX(kNodeTick + 1)) / 2.0 - 2.0,
                                geom.plot.top() + 2.0, 4.0, 6.0),
                         dpr, themes::color(themes::Role::song_view_selection_edge), 24) ||
                hasColorNear(selected,
                             QRectF(tickX(kNodeTick) + 4.0, geom.body.center().y() - 2.0, 8.0, 4.0),
                             dpr, themes::color(themes::Role::song_view_selection_fill), 24),
            QStringLiteral("selection reticle did not paint"));
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
        const QPointF nodePos(nodeX, nodeY);
        const int drag = geometry.nodeDragActivationDistance + 8;
        const QPointF dragTarget(tickX(kNodeTick + 48),
                                 nodelane::valueY(lane, geom.body, geometry, node - 24));
        sendActivatedDrag(page.canvas(), nodePos, dragTarget, drag, Qt::NoModifier);
        pump();
        const auto dragSnap = snapshot(document);
        const QImage dragPreview = page.canvas()->grab().toImage();
        paintUnchanged(row.name, dragSnap);
        report(row.name,
               hasColorNear(dragPreview, nodeProbe(dragTarget.x(), dragTarget.y(), radius), dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24),
               QStringLiteral("node drag preview is missing"));
        cancel();
        selection.startTick = kNodeTick - 24;
        selection.endTick = kSecondTick + 48;
        if (row.kind == LaneKind::Tempo)
            selection.tempo = true;
        else
            selection.lanes = {{0, 10}};
        view.selectionModel().setTimeSelection(selection);
        refresh(page, document, live);
        const QPointF multiTarget(nodeX, nodelane::valueY(lane, geom.body, geometry, node - 24));
        sendActivatedDrag(page.canvas(), nodePos, multiTarget, drag, Qt::NoModifier);
        pump();
        const auto multiSnap = snapshot(document);
        const QImage multiPreview = page.canvas()->grab().toImage();
        paintUnchanged(row.name, multiSnap);
        const QPointF secondPreview(secondX,
                                    nodelane::valueY(lane, geom.body, geometry, second - 24));
        report(row.name,
               hasColorNear(multiPreview, nodeProbe(multiTarget.x(), multiTarget.y(), radius), dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24) &&
                   hasColorNear(multiPreview,
                                nodeProbe(secondPreview.x(), secondPreview.y(), radius), dpr,
                                themes::color(themes::Role::song_view_edit_preview_outline), 24),
               QStringLiteral("multi-drag preview is missing"));
        cancel();
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
        const QPointF sweepStart(tickX(48),
                                 nodelane::valueY(lane, geom.body, geometry, (held + node) / 2));
        const QPointF sweepTarget(
            tickX(144), nodelane::valueY(lane, geom.body, geometry, (held + node) / 2 + 40));
        sendActivatedDrag(page.canvas(), sweepStart, sweepTarget, drag, Qt::NoModifier);
        pump();
        const auto sweepSnap = snapshot(document);
        const QImage sweepPreview = page.canvas()->grab().toImage();
        paintUnchanged(row.name, sweepSnap);
        report(row.name,
               hasColorNear(sweepPreview, nodeProbe(sweepTarget.x(), sweepTarget.y(), radius), dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24),
               QStringLiteral("sweep preview is missing"));
        cancel();
        const QPointF rampStart(tickX(48), heldY);
        const QPointF rampEnd(tickX(kSecondTick), nodeY);
        checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, rampStart,
                                  Qt::LeftButton, Qt::LeftButton, Qt::ShiftModifier);
        checks::events::sendMouse(*page.canvas(), QEvent::MouseMove, rampStart + QPointF(drag, 0),
                                  Qt::NoButton, Qt::LeftButton, Qt::ShiftModifier);
        checks::events::sendMouse(*page.canvas(), QEvent::MouseMove, rampEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::ShiftModifier);
        pump();
        const auto rampSnap = snapshot(document);
        const QImage rampPreview = page.canvas()->grab().toImage();
        paintUnchanged(row.name, rampSnap);
        const QPointF rampMid((rampStart.x() + rampEnd.x()) / 2.0,
                              (rampStart.y() + rampEnd.y()) / 2.0);
        report(row.name,
               hasColorNear(rampPreview, QRectF(rampMid.x() - 3.0, rampMid.y() - 3.0, 6.0, 6.0),
                            dpr, themes::color(themes::Role::song_view_edit_preview_outline), 24),
               QStringLiteral("Shift-ramp preview is missing"));
        cancel();
        if (row.kind != LaneKind::Cc)
            continue;
        QAction *pencil = pencilModeAction(page);
        report(row.name, pencil != nullptr, QStringLiteral("Pencil Mode action is unavailable"));
        if (!pencil)
            continue;
        pencil->setChecked(true);
        pump();
        const QPointF pencilStart(tickX(24), nodelane::valueY(lane, geom.body, geometry, 40));
        const QPointF pencilHold(tickX(72), nodelane::valueY(lane, geom.body, geometry, 40));
        const QPointF pencilEnd(tickX(120), nodelane::valueY(lane, geom.body, geometry, 100));
        checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, pencilStart,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*page.canvas(), QEvent::MouseMove, pencilHold, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*page.canvas(), QEvent::MouseMove, pencilEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        pump();
        const auto pencilSnap = snapshot(document);
        const QImage pencilPreview = page.canvas()->grab().toImage();
        paintUnchanged(row.name, pencilSnap);
        report(row.name,
               hasColorNear(pencilPreview, lineProbe(tickX(48), pencilHold.y(), 8, lineHalf), dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24),
               QStringLiteral("Pencil preview curve is missing"));
        report(row.name,
               changedPixels(idle, pencilPreview,
                             labelProbe(pencilEnd.x(), pencilEnd.y(), geom.plot), dpr) > 0,
               QStringLiteral("Pencil preview value label is missing"));
        cancel();
        pencil->setChecked(false);
        pump();
    }
    live.editCursorTick = 24;
    refresh(page, document, live);
    leaveCanvas(page);
    const auto cursorSnap = snapshot(document);
    const QImage cursorA = page.canvas()->grab().toImage();
    paintUnchanged("edit cursor", cursorSnap);
    live.editCursorTick = 96;
    refresh(page, document, live);
    leaveCanvas(page);
    const QImage cursorB = page.canvas()->grab().toImage();
    paintUnchanged("edit cursor move", cursorSnap);
    const qreal cursorX = tickX(96);
    check(cursorA != cursorB, QStringLiteral("moving the edit cursor did not repaint the canvas"));
    check(hasColorNear(cursorB, QRectF(cursorX - 2.0, 4.0, 4.0, 12.0), dpr,
                       themes::color(themes::Role::song_view_edit_cursor), 16),
          QStringLiteral("canvas did not paint the edit cursor"));
    checkAutomationTempoOcclusion(view, page, document, live, failures);
    cancel();
    if (QAction *pencil = pencilModeAction(page))
        pencil->setChecked(false);
    view.selectionModel().clearTimeSelection();
    document.undoStack()->setIndex(startSnap.undoIndex);
    live.documentRevision = document.revision();
    live.editCursorTick = 24;
    page.documentChanged();
    page.refreshLiveState(live);
    toggleTempoExpanded(page, false, failures);
    pump();
    check(document.smf().write() == startSnap.smf &&
              document.undoStack()->index() == startSnap.undoIndex &&
              document.tempoPoints() == startTempo,
          QStringLiteral("paint coverage did not restore SMF, tempo, or undo"));
}

// Pixel oracle for the terminal hold: every held segment (committed curve,
// phantom preview, drag preview, both pencil tails) must stop at
// min(plot.right(), songEndX) and never paint past the song end.
void checkAutomationTerminalHold(SongView &view, AutomationPage &page, SongDocument &document,
                                 DrawerPageLiveState &live, int &failures)
{
    const auto report = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-check: FAIL paint: terminal hold: %s\n",
                     qUtf8Printable(message));
        ++failures;
    };
    const MidiTimeline *timeline = view.timeline();
    if (!timeline || timeline->lengthTicks == 0) {
        report(false, QStringLiteral("fixture song has no bounded timeline"));
        return;
    }
    AutomationGeometry geometry = AutomationGeometry::resolve();
    geometry.plotOrigin = page.canvas()->plotOrigin();
    const qreal dpr = page.canvas()->devicePixelRatioF();
    AutomationProjection projection(geometry, &page);
    const uint64_t songEndTick = timeline->lengthTicks;
    const QColor previewColor = themes::color(themes::Role::song_view_edit_preview_outline);
    const QColor backdrop = themes::color(themes::Role::song_view_piano_roll_background);
    const qreal pxPerTick = view.pxPerTick();
    const qreal beatPx = qreal(timeline->ticksPerBeat) * pxPerTick;
    const int plotDevRight = qRound(qreal(page.canvas()->width() - 1) * dpr);
    const int capFringe = int(std::ceil(dpr));
    const qreal lineHalf =
        std::max(qreal(layout::singlePixel()), qreal(geometry.hoverPaintPadding + 1));
    constexpr int heldValue = 24;
    constexpr int nodeValue = 96;
    constexpr int strokeValue = 60;
    constexpr int dragValue = 127;

    const auto setScroll = [&](double scroll) {
        view.setEditorHorizontalScroll(scroll);
        live.horizontalScroll = scroll;
        refresh(page, document, live);
    };
    const auto cancel = [&] {
        page.cancelInteraction();
        leaveCanvas(page);
    };
    const auto grabCanvas = [&] {
        leaveCanvas(page);
        return page.canvas()->grab().toImage();
    };
    setScroll(qreal(timeline->lengthTicks) * pxPerTick - 300.0);
    const std::optional<qreal> insideEnd = projection.songEndX(dpr);
    const qreal endX = insideEnd.value_or(qreal(geometry.plotOrigin));
    const QRect plot(geometry.plotOrigin, 0,
                     std::max(0, page.canvas()->width() - geometry.plotOrigin), 1);
    if (!insideEnd || endX < plot.left() + 250.0 || endX + 3.5 * beatPx + 12.0 >= plot.right()) {
        report(false, QStringLiteral("inside fixture: song end %1 lacks plot clearance").arg(endX));
        setScroll(0.0);
        return;
    }
    const uint64_t nodeTick = view.snapTickDown(double(songEndTick) - 16.0);
    CCLaneAdapter lane(document, 0, uint8_t{10});
    const auto geom = laneGeom(page, kLanes[1]);
    if (nodeTick == 0 || !geom.handle.valid() || geom.plot.isEmpty()) {
        report(false, QStringLiteral("pan lane or trailing node is missing from the rig"));
        setScroll(0.0);
        return;
    }
    setCcPoints(page, document, live, {{0, heldValue}, {nodeTick, nodeValue}});
    const QColor &curveColor = geom.curveColor;
    const qreal heldY = nodelane::valueY(lane, geom.body, geometry, heldValue);
    const qreal nodeY = nodelane::valueY(lane, geom.body, geometry, nodeValue);
    const qreal strokeY = nodelane::valueY(lane, geom.body, geometry, strokeValue);
    const qreal dragY = nodelane::valueY(lane, geom.body, geometry, dragValue);
    const qreal nodeX = projection.displayX(nodeTick, dpr);
    NodeLaneHoverState hoverState;
    const std::vector<NodePoint> committed{{0, heldValue}, {nodeTick, nodeValue}};
    const std::vector<NodePoint> edgeCommitted{{0, heldValue},
                                               {uint64_t(timeline->ticksPerBeat) * 2, nodeValue}};

    const auto renderLane = [&](const AutomationProjection &paintProjection,
                                const std::vector<NodePoint> &points,
                                std::optional<nodelane::OriginPhantomPaint> phantom) {
        QImage image(page.canvas()->size(), QImage::Format_ARGB32_Premultiplied);
        image.setDevicePixelRatio(dpr);
        image.fill(backdrop);
        QPainter painter(&image);
        nodelane::paintNodeLane(painter, nodelane::NodeLanePaint{
                                             .lane = lane,
                                             .points = points,
                                             .body = geom.body,
                                             .geometry = geometry,
                                             .projection = paintProjection,
                                             .color = curveColor,
                                             .handle = geom.handle,
                                             .hoverState = hoverState,
                                             .phantom = std::move(phantom),
                                         });
        painter.end();
        return image;
    };
    const auto renderPencil = [&](const LaneGeom &paintGeom, const std::vector<NodePoint> &points,
                                  const PencilGesture &pencilGesture) {
        QImage image(page.canvas()->size(), QImage::Format_ARGB32_Premultiplied);
        image.setDevicePixelRatio(dpr);
        image.fill(backdrop);
        QPainter painter(&image);
        nodelane::paintNodeLane(painter, nodelane::NodeLanePaint{
                                             .lane = lane,
                                             .points = points,
                                             .body = paintGeom.body,
                                             .geometry = geometry,
                                             .projection = projection,
                                             .color = curveColor,
                                             .handle = paintGeom.handle,
                                             .hoverState = hoverState,
                                             .pencil = &pencilGesture,
                                             .pencilMode = true,
                                         });
        painter.end();
        return image;
    };
    const auto lastColoredColumn = [&](const QImage &image, int xFrom, int xTo, qreal y,
                                       const QColor &color, int tolerance) {
        for (int x = xTo; x >= xFrom; --x) {
            if (hasColorNear(image, QRectF(x, y - lineHalf, 1.0, 2 * lineHalf), dpr, color,
                             tolerance))
                return x;
        }
        return -1;
    };
    const auto beyondEnd = [&](qreal y) {
        return QRectF(endX + 2.0, y - lineHalf, plot.right() - endX - 4.0, 2 * lineHalf);
    };

    const auto verifyInside = [&] {
        const QImage insideCommitted = renderLane(projection, committed, std::nullopt);
        const int endDev = qRound(endX * dpr);
        const int insideLast = lastColoredColumn(
            insideCommitted, qRound((nodeX + geometry.nodePaintRadius + 3.0) * dpr), plotDevRight,
            nodeY, curveColor, 16);
        report(insideLast >= endDev - 1 && insideLast <= endDev + capFringe,
               QStringLiteral("committed hold ended %1 device px from the end column %2")
                   .arg(insideLast - endDev)
                   .arg(endDev));
        report(lastColoredColumn(insideCommitted, endDev + capFringe + 1, plotDevRight, nodeY,
                                 curveColor, 16) < 0,
               QStringLiteral("committed curve painted right of the song end"));
        const QImage insidePhantom = renderLane(
            projection, committed,
            nodelane::OriginPhantomPaint{OriginPhantom{geom.handle, committed.back(),
                                                       lane.minimumValue(), lane.maximumValue()},
                                         committed.back()});
        report(hasColorNear(insidePhantom,
                            QRectF(plot.left() + 2.0, nodeY - lineHalf, endX - plot.left() - 8.0,
                                   2 * lineHalf),
                            dpr, previewColor, 24),
               QStringLiteral("phantom preview hold is missing before the song end"));
        report(!hasColorNear(insidePhantom, beyondEnd(nodeY), dpr, previewColor, 24),
               QStringLiteral("phantom preview hold ran past the song end"));
    };
    const auto verifyAfterAndZeroLength = [&] {
        setScroll(0.0);
        const std::optional<qreal> afterEnd = projection.songEndX(dpr);
        report(afterEnd && *afterEnd > plot.right(),
               QStringLiteral("after fixture: song end is not right of the plot"));
        const QImage afterCommitted = renderLane(projection, edgeCommitted, std::nullopt);
        report(lastColoredColumn(afterCommitted, 0, plotDevRight, nodeY, curveColor, 16) >=
                   plotDevRight - capFringe,
               QStringLiteral("hold stopped short of the plot edge with the song end right of it"));
        MidiTimeline zeroTimeline;
        zeroTimeline.ticksPerBeat = timeline->ticksPerBeat;
        SongView zeroView;
        zeroView.setSong(&zeroTimeline, nullptr);
        zeroView.setEditorTimeZoom(live.timeZoom);
        zeroView.setEditorHorizontalScroll(0.0);
        AutomationProjection zeroProjection(geometry, &zeroView);
        report(!zeroProjection.songEndX(dpr).has_value(),
               QStringLiteral("zero-length timeline still resolved a song end"));
        const QImage zeroCommitted = renderLane(zeroProjection, edgeCommitted, std::nullopt);
        report(zeroCommitted == afterCommitted,
               QStringLiteral("zero-length fallback raster differs from the past-end raster"));
    };
    const auto verifyBefore = [&] {
        setScroll(qreal(timeline->lengthTicks) * pxPerTick + qreal(plot.width()));
        const std::optional<qreal> beforeEnd = projection.songEndX(dpr);
        report(beforeEnd && *beforeEnd < plot.left(),
               QStringLiteral("before fixture: song end is not left of the plot"));
        const QImage beforeCommitted = renderLane(projection, committed, std::nullopt);
        report(lastColoredColumn(beforeCommitted, qRound(plot.left() * dpr), plotDevRight, nodeY,
                                 curveColor, 16) < 0 &&
                   lastColoredColumn(beforeCommitted, qRound(plot.left() * dpr), plotDevRight,
                                     heldY, curveColor, 16) < 0,
               QStringLiteral("held-segment pixels reached the plot with the song end left of it"));
    };
    const auto verifyDrag = [&] {
        setScroll(qreal(songEndTick) * pxPerTick - 300.0);
        const QPointF nodePos(nodeX, nodeY);
        const int dragActivation = geometry.nodeDragActivationDistance + 8;
        const auto reportCleanBeyondEnd = [&](const QImage &image, const char *label) {
            report(!hasColorNear(image, beyondEnd(strokeY), dpr, previewColor, 24) &&
                       !hasColorNear(image, beyondEnd(nodeY), dpr, curveColor, 16) &&
                       !hasColorNear(image, beyondEnd(heldY), dpr, curveColor, 16) &&
                       !hasColorNear(image, beyondEnd(heldY), dpr, previewColor, 24),
                   QStringLiteral("%1 painted held pixels beyond the song end")
                       .arg(QLatin1String(label)));
        };
        sendActivatedDrag(page.canvas(), nodePos, QPointF(endX - 100.0, strokeY), dragActivation,
                          Qt::NoModifier);
        pump();
        const QImage dragInside = grabCanvas();
        report(hasColorNear(dragInside, QRectF(endX - 65.0, strokeY - lineHalf, 30.0, 2 * lineHalf),
                            dpr, previewColor, 24),
               QStringLiteral("single drag hold is missing before the song end"));
        reportCleanBeyondEnd(dragInside, "single drag");
        cancel();
        const qreal pastXMin = endX + beatPx + 4.0;
        const qreal pastXMax = endX + 3.5 * beatPx - 4.0;
        sendActivatedDrag(page.canvas(), nodePos, QPointF(endX + 2.5 * beatPx, strokeY),
                          dragActivation, Qt::NoModifier);
        pump();
        const QImage dragPast = grabCanvas();
        report(hasColorNear(dragPast, lineProbe(endX, (heldY + strokeY) / 2.0, 2.0, lineHalf), dpr,
                            previewColor, 24),
               QStringLiteral("past-end drag did not step down at the song end"));
        report(hasColorNear(
                   dragPast,
                   QRectF(pastXMin, strokeY - 2 * lineHalf, pastXMax - pastXMin, 4 * lineHalf), dpr,
                   previewColor, 24),
               QStringLiteral("past-end drag marker is missing"));
        report(!hasColorNear(dragPast, beyondEnd(heldY), dpr, curveColor, 16) &&
                   !hasColorNear(dragPast, beyondEnd(heldY), dpr, previewColor, 24) &&
                   !hasColorNear(dragPast, beyondEnd(nodeY), dpr, curveColor, 16) &&
                   !hasColorNear(
                       dragPast,
                       QRectF(endX + 2.0, strokeY - lineHalf, pastXMin - endX - 6.0, 2 * lineHalf),
                       dpr, previewColor, 24) &&
                   !hasColorNear(dragPast,
                                 QRectF(pastXMax + 4.0, strokeY - lineHalf,
                                        plot.right() - pastXMax - 6.0, 2 * lineHalf),
                                 dpr, previewColor, 24),
               QStringLiteral("past-end drag painted held pixels beyond the song end"));
        cancel();
        sendActivatedDrag(page.canvas(), nodePos, QPointF(plot.right() + 120.0, strokeY),
                          dragActivation, Qt::NoModifier);
        pump();
        const QImage dragOff = grabCanvas();
        report(!hasColorNear(dragOff, beyondEnd(strokeY), dpr, previewColor, 24),
               QStringLiteral("off-viewport drag painted a reversed segment into the plot"));
        report(hasColorNear(dragOff, lineProbe(endX, (heldY + strokeY) / 2.0, 2.0, lineHalf), dpr,
                            previewColor, 24),
               QStringLiteral("off-viewport drag lost the step-down at the song end"));
        reportCleanBeyondEnd(dragOff, "off-viewport drag");
        cancel();
    };
    const auto verifyPreparedDrag = [&] {
        songview::EditorSelectionModel::TimeSelection selection;
        selection.startTick = 0;
        selection.endTick = nodeTick + 1;
        selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        selection.lanes = {{0, 10}};
        view.selectionModel().setTimeSelection(selection);
        refresh(page, document, live);
        sendActivatedDrag(page.canvas(), QPointF(nodeX, nodeY), QPointF(nodeX, dragY),
                          geometry.nodeDragActivationDistance + 8, Qt::NoModifier);
        pump();
        const QImage preparedDrag = grabCanvas();
        report(hasColorNear(preparedDrag, QRectF(endX - 60.0, dragY - lineHalf, 54.0, 2 * lineHalf),
                            dpr, curveColor, 16),
               QStringLiteral("prepared drag hold is missing before the song end"));
        report(!hasColorNear(preparedDrag, beyondEnd(dragY), dpr, curveColor, 16) &&
                   !hasColorNear(preparedDrag, beyondEnd(dragY), dpr, previewColor, 24) &&
                   !hasColorNear(preparedDrag, beyondEnd(nodeY), dpr, curveColor, 16),
               QStringLiteral("prepared drag painted beyond the song end"));
        cancel();
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
    };
    const auto verifyPencilTails = [&] {
        QAction *pencil = pencilModeAction(page);
        report(pencil != nullptr, QStringLiteral("Pencil Mode action is unavailable"));
        if (pencil) {
            pencil->setChecked(true);
            pump();
            const auto pencilStroke = [&](const QPointF &from, const QPointF &to) {
                checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, from,
                                          Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                checks::events::sendMouse(*page.canvas(), QEvent::MouseMove, (from + to) / 2.0,
                                          Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
                checks::events::sendMouse(*page.canvas(), QEvent::MouseMove, to, Qt::NoButton,
                                          Qt::LeftButton, Qt::NoModifier);
                pump();
            };
            pencilStroke(QPointF(std::max(nodeX - 120.0, plot.left() + 20.0), strokeY),
                         QPointF(nodeX - 80.0, strokeY));
            const QImage retainedStroke = page.canvas()->grab().toImage();
            report(hasColorNear(
                       retainedStroke,
                       QRectF(nodeX + 8.0, nodeY - lineHalf, endX - nodeX - 16.0, 2 * lineHalf),
                       dpr, curveColor, 16),
                   QStringLiteral("pencil retained-source tail is missing before the song end"));
            report(!hasColorNear(retainedStroke, beyondEnd(nodeY), dpr, curveColor, 16),
                   QStringLiteral("pencil retained-source tail ran past the song end"));
            report(!hasColorNear(retainedStroke, beyondEnd(strokeY), dpr, previewColor, 24),
                   QStringLiteral("pencil preview pixels ran past the retained source node"));
            cancel();
            setCcPoints(page, document, live, {{0, heldValue}});
            const MidiTimeline *tailTimeline = view.timeline();
            const uint64_t tailSongEnd = tailTimeline ? tailTimeline->lengthTicks : 0;
            if (tailSongEnd > 0)
                setScroll(qreal(tailSongEnd) * pxPerTick - 300.0);
            const std::optional<qreal> tailEnd = projection.songEndX(dpr);
            const qreal tailEndX = tailEnd.value_or(qreal(plot.left()));
            const auto tailGeom = laneGeom(page, kLanes[1]);
            const bool tailLaneUsable = tailGeom.handle.valid() && !tailGeom.plot.isEmpty();
            report(tailLaneUsable, QStringLiteral("pan lane disappeared during pencil tail setup"));
            const qreal tailStrokeY =
                tailLaneUsable ? nodelane::valueY(lane, tailGeom.body, geometry, strokeValue)
                               : strokeY;
            const AutomationGridCell finalCell =
                tailSongEnd == 0 ? AutomationGridCell{}
                                 : projection.snapCellAt(double(tailSongEnd - 1));
            const AutomationGridCell tailStrokeCell =
                finalCell.tickBegin == 0 ? AutomationGridCell{}
                                         : projection.snapCellAt(double(finalCell.tickBegin - 1));
            const uint64_t tailCellWidth = tailStrokeCell.tickEnd - tailStrokeCell.tickBegin;
            const bool tailCellUsable = tailLaneUsable && tailEnd &&
                                        finalCell.tickEnd == tailSongEnd &&
                                        tailStrokeCell.tickEnd < tailSongEnd && tailCellWidth >= 2;
            report(tailCellUsable,
                   QStringLiteral("pencil cells [%1, %2), [%3, %4), song end %5 are not usable")
                       .arg(tailStrokeCell.tickBegin)
                       .arg(tailStrokeCell.tickEnd)
                       .arg(finalCell.tickBegin)
                       .arg(finalCell.tickEnd)
                       .arg(tailSongEnd));
            if (tailCellUsable) {
                const std::vector<NodePoint> tailSource = lane.points();
                report(
                    tailSource.size() == 1 && tailSource.front().tick == 0,
                    QStringLiteral("pencil tail source retained %1 points").arg(tailSource.size()));
                const uint64_t tailStrokeFirst = tailStrokeCell.tickBegin + tailCellWidth / 4;
                const QPointF tailStrokeStart(projection.displayX(tailStrokeFirst, dpr),
                                              tailStrokeY);
                const auto mappedTailStart = projection.pointerMapping(
                    lane, tailGeom.body, tailStrokeStart.x(), tailStrokeStart.y());
                report(mappedTailStart.cell.tickBegin == tailStrokeCell.tickBegin &&
                           mappedTailStart.cell.tickEnd == tailStrokeCell.tickEnd,
                       QStringLiteral("pencil tail press mapped to [%1, %2), expected [%3, %4)")
                           .arg(mappedTailStart.cell.tickBegin)
                           .arg(mappedTailStart.cell.tickEnd)
                           .arg(tailStrokeCell.tickBegin)
                           .arg(tailStrokeCell.tickEnd));
                auto tailStroke = AutomationPencilGesture::start(
                    {tailGeom.handle, document.revision()}, lane.minimumValue(),
                    lane.maximumValue(), tailSongEnd, document.ticksPerClock(), tailSource,
                    {mappedTailStart.rawTick, tailStrokeStart.x(), mappedTailStart.point,
                     double(mappedTailStart.point.value)},
                    mappedTailStart.cell);
                report(tailStroke.has_value(),
                       QStringLiteral("pencil tail gesture could not start"));
                if (tailStroke) {
                    PencilGesture tailGesture{tailGeom.handle, std::move(*tailStroke)};
                    const QImage tailPreview = renderPencil(tailGeom, tailSource, tailGesture);
                    const qreal tailHeldY =
                        nodelane::valueY(lane, tailGeom.body, geometry, heldValue);
                    const qreal tailStartX = projection.displayX(tailStrokeCell.tickEnd, dpr);
                    const int tailEndDev = qRound(tailEndX * dpr);
                    const int previewTailLast =
                        lastColoredColumn(tailPreview, qRound(tailStartX * dpr), plotDevRight,
                                          tailHeldY, previewColor, 24);
                    report(previewTailLast >= tailEndDev - 1,
                           QStringLiteral("pencil preview-value tail ended at device column %1, "
                                          "expected end column %2")
                               .arg(previewTailLast)
                               .arg(tailEndDev));
                    const QRectF tailBeyondEnd(tailEndX + 2.0, tailHeldY - lineHalf,
                                               plot.right() - tailEndX - 4.0, 2 * lineHalf);
                    report(!hasColorNear(tailPreview, tailBeyondEnd, dpr, previewColor, 24),
                           QStringLiteral("pencil preview-value tail ran past the song end"));
                    report(!hasColorNear(tailPreview,
                                         QRectF(tailEndX + 2.0, tailHeldY - lineHalf,
                                                plot.right() - tailEndX - 4.0, 2 * lineHalf),
                                         dpr, curveColor, 16),
                           QStringLiteral("pencil committed tail appeared past the song end"));
                }
            }
            pencil->setChecked(false);
            pump();
        }
    };

    verifyInside();
    verifyAfterAndZeroLength();
    verifyBefore();
    verifyDrag();
    verifyPreparedDrag();
    verifyPencilTails();
    cancel();
    view.selectionModel().clearTimeSelection();
    setScroll(0.0);
}
