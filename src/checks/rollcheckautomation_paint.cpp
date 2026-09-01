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
#include <QString>
#include <QUndoStack>
#include <QWidget>

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
QImage captureAutomationViewport(SongView &view, AutomationPage &page, int &failures)
{
    QString error;
    QWidget *const viewport = page.scrollViewport();
    const QImage image =
        viewport ? checks::support::captureQuickBand(view, *viewport, &error) : QImage{};
    if (!image.isNull())
        return image;
    std::fprintf(stderr, "automation-check: FAIL paint: %s\n", qUtf8Printable(error));
    ++failures;
    return {};
}

QPoint automationContentToViewport(const AutomationPage &page)
{
    QWidget *const viewport = page.scrollViewport();
    return viewport ? page.canvas()->mapTo(viewport, QPoint{}) : QPoint{};
}

QRectF toViewport(const QRectF &content, const QPoint &origin)
{
    return content.translated(origin);
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

int changedPixels(const QImage &idle, const QImage &hover, const QRectF &logical,
                  const QPoint &origin, qreal dpr)
{
    if (idle.size() != hover.size() || idle.format() != hover.format())
        return -1;
    const QRect rect =
        deviceRect(toViewport(logical, origin), dpr, idle.size()).intersected(idle.rect());
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

bool hasColorNear(const QImage &image, const QRectF &logical, const QPoint &origin, qreal dpr,
                  const QColor &expected, int tolerance)
{
    const QRect rect =
        deviceRect(toViewport(logical, origin), dpr, image.size()).intersected(image.rect());
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

bool toggleTempoExpanded(SongView &view, AutomationPage &page, bool wantExpanded, int &failures)
{
    const bool expanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (expanded == wantExpanded)
        return expanded;
    const QImage beforeToggle = captureAutomationViewport(view, page, failures);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, tempoHeaderPoint(page),
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease, tempoHeaderPoint(page),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    pump();
    if (captureAutomationViewport(view, page, failures) == beforeToggle) {
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
    const bool tempoExpanded = toggleTempoExpanded(view, page, true, failures);
    check(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"));
    checkAutomationCanvasFontPaint(view, page, document, live, failures);
    auto geometry = AutomationGeometry::resolve();
    geometry.plotOrigin = page.canvas()->plotOrigin();
    const qreal dpr = page.canvas()->devicePixelRatioF();
    const QPoint captureOrigin = automationContentToViewport(page);
    QWidget *const automationViewport = page.scrollViewport();
    const QRect viewportContent = automationViewport
                                      ? QRect{page.canvas()->mapFrom(automationViewport, QPoint{}),
                                              automationViewport->size()}
                                      : QRect{};
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
    const QImage emptyTempo = captureAutomationViewport(view, page, failures);
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
           !hasColorNear(emptyTempo, lineProbe(xMid, y120, 8, lineHalf), captureOrigin, dpr,
                         tempoGeom.curveColor, 12),
           QStringLiteral("empty storage painted a 120 lead-in curve"));
    report("Tempo",
           !hasColorNear(emptyTempo, nodeProbe(x0, y120, radius), captureOrigin, dpr,
                         tempoGeom.curveColor, 12),
           QStringLiteral("empty storage painted a 120 lead-in node"));
    setTempoPoints(page, document, live,
                   {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)}});
    const auto leadSnap = snapshot(document);
    leaveCanvas(page);
    const QImage leadTempo = captureAutomationViewport(view, page, failures);
    paintUnchanged("Tempo lead-in paint", leadSnap);
    const int leadLine = changedPixels(emptyTempo, leadTempo, lineProbe(xMid, y120, 8, lineHalf),
                                       captureOrigin, dpr);
    const int leadOrigin =
        changedPixels(emptyTempo, leadTempo, nodeProbe(x0, y120, radius), captureOrigin, dpr);
    const int leadNode =
        changedPixels(emptyTempo, leadTempo, nodeProbe(x96, y200, radius), captureOrigin, dpr);
    report("Tempo", leadLine > 0, QStringLiteral("first nonzero point painted no 120 lead-in"));
    report("Tempo", leadOrigin > 0 && leadOrigin <= lineBudget(radius, dpr),
           QStringLiteral("120 lead-in painted a tick-0 node"));
    report("Tempo", leadNode > lineBudget(radius, dpr),
           QStringLiteral("first nonzero point painted no node"));
    setTempoPoints(page, document, live,
                   {{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)}});
    const auto tick0Snap = snapshot(document);
    leaveCanvas(page);
    const QImage tick0Tempo = captureAutomationViewport(view, page, failures);
    paintUnchanged("Tempo tick-0 paint", tick0Snap);
    report("Tempo",
           changedPixels(emptyTempo, tick0Tempo, nodeProbe(x0, y80, radius), captureOrigin, dpr) >
               lineBudget(radius, dpr),
           QStringLiteral("explicit tick-0 point painted no node"));
    report("Tempo",
           changedPixels(emptyTempo, tick0Tempo, lineProbe(xMid, y120, 8, lineHalf), captureOrigin,
                         dpr) <= 0,
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
        if (!QRectF(viewportContent).contains(QRectF(geom.body))) {
            report(row.name, false,
                   QStringLiteral("lane paint probe is outside the automation scroll viewport"));
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
        const QImage idle = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, idleSnap);
        report(row.name,
               hasColorNear(idle, lineProbe(midX, heldY, 8, lineHalf), captureOrigin, dpr,
                            geom.curveColor, 16),
               QStringLiteral("normal step curve is missing"));
        report(row.name,
               hasColorNear(idle, nodeProbe(nodeX, nodeY, radius), captureOrigin, dpr,
                            geom.curveColor, 16),
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
        const QImage selected = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, selectedSnap);
        const qreal ringOuter = geometry.selectedNodeRingRadius + layout::singlePixel();
        report(row.name,
               changedPixels(idle, selected, nodeProbe(nodeX, nodeY, ringOuter), captureOrigin,
                             dpr) > 0,
               QStringLiteral("selected ring did not paint above the node"));
        report(
            row.name,
            hasColorNear(selected,
                         QRectF((tickX(kNodeTick) + tickX(kNodeTick + 1)) / 2.0 - 2.0,
                                geom.plot.top() + 2.0, 4.0, 6.0),
                         captureOrigin, dpr, themes::color(themes::Role::song_view_selection_edge),
                         24) ||
                hasColorNear(selected,
                             QRectF(tickX(kNodeTick) + 4.0, geom.body.center().y() - 2.0, 8.0, 4.0),
                             captureOrigin, dpr,
                             themes::color(themes::Role::song_view_selection_fill), 24),
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
        const QImage dragPreview = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, dragSnap);
        report(row.name,
               hasColorNear(dragPreview, nodeProbe(dragTarget.x(), dragTarget.y(), radius),
                            captureOrigin, dpr,
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
        const QImage multiPreview = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, multiSnap);
        const QPointF secondPreview(secondX,
                                    nodelane::valueY(lane, geom.body, geometry, second - 24));
        report(row.name,
               hasColorNear(multiPreview, nodeProbe(multiTarget.x(), multiTarget.y(), radius),
                            captureOrigin, dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24) &&
                   hasColorNear(multiPreview,
                                nodeProbe(secondPreview.x(), secondPreview.y(), radius),
                                captureOrigin, dpr,
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
        const QImage sweepPreview = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, sweepSnap);
        report(row.name,
               hasColorNear(sweepPreview, nodeProbe(sweepTarget.x(), sweepTarget.y(), radius),
                            captureOrigin, dpr,
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
        const QImage rampPreview = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, rampSnap);
        const QPointF rampMid((rampStart.x() + rampEnd.x()) / 2.0,
                              (rampStart.y() + rampEnd.y()) / 2.0);
        report(row.name,
               hasColorNear(rampPreview, QRectF(rampMid.x() - 3.0, rampMid.y() - 3.0, 6.0, 6.0),
                            captureOrigin, dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24),
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
        const QImage pencilPreview = captureAutomationViewport(view, page, failures);
        paintUnchanged(row.name, pencilSnap);
        report(row.name,
               hasColorNear(pencilPreview, lineProbe(tickX(48), pencilHold.y(), 8, lineHalf),
                            captureOrigin, dpr,
                            themes::color(themes::Role::song_view_edit_preview_outline), 24),
               QStringLiteral("Pencil preview curve is missing"));
        report(row.name,
               changedPixels(idle, pencilPreview,
                             labelProbe(pencilEnd.x(), pencilEnd.y(), geom.plot), captureOrigin,
                             dpr) > 0,
               QStringLiteral("Pencil preview value label is missing"));
        cancel();
        pencil->setChecked(false);
        pump();
    }
    live.editCursorTick = 24;
    refresh(page, document, live);
    leaveCanvas(page);
    const auto cursorSnap = snapshot(document);
    const QImage cursorA = captureAutomationViewport(view, page, failures);
    paintUnchanged("edit cursor", cursorSnap);
    live.editCursorTick = 96;
    refresh(page, document, live);
    leaveCanvas(page);
    const QImage cursorB = captureAutomationViewport(view, page, failures);
    paintUnchanged("edit cursor move", cursorSnap);
    const qreal cursorX = tickX(96);
    check(cursorA != cursorB, QStringLiteral("moving the edit cursor did not repaint the canvas"));
    check(hasColorNear(cursorB, QRectF(cursorX - 2.0, 4.0, 4.0, 12.0), captureOrigin, dpr,
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
    toggleTempoExpanded(view, page, false, failures);
    pump();
    check(document.smf().write() == startSnap.smf &&
              document.undoStack()->index() == startSnap.undoIndex &&
              document.tempoPoints() == startTempo,
          QStringLiteral("paint coverage did not restore SMF, tempo, or undo"));
}
