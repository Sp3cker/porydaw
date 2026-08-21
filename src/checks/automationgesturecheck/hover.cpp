#include "domains.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QString>
#include <QUndoStack>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/songview.h"

namespace {

enum class AdapterKind { Tempo, Cc };

struct Case {
    AdapterKind kind = AdapterKind::Tempo;
    const char *name = "";
};

struct Topology {
    bool insertionLine = false;
    bool heldGhost = false;
    bool insertionLabel = false;
    bool nodeRing = false;
    bool nodeLabel = false;
    bool noInsertionGhost = false;
    bool leaveCleared = false;
    bool noRepeatChurn = false;
};

struct DocSnap {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;
};

struct PreparedLane {
    LaneHandle handle;
    QRect body;
    QRect plot;
    QPointF insertionPos;
    QPointF nodePos;
    uint64_t insertionTick = 0;
    qreal insertionX = 0;
    qreal heldY = 0;
    qreal nodeX = 0;
    qreal nodeY = 0;
    qreal priorHeldY = 0;
};

constexpr std::array kCases{
    Case{AdapterKind::Tempo, "Tempo"},
    Case{AdapterKind::Cc, "CC"},
};

constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kNodeTick = 144;
constexpr int kTempoHeld = 80;
constexpr int kTempoNode = 200;
constexpr int kTempoCursor = 140;
constexpr int kCcHeld = 16;
constexpr int kCcNode = 112;
constexpr int kCcCursor = 64;

void report(const AutomationGestureCheck &check, const char *name, bool condition,
            const QString &message)
{
    check(condition, QStringLiteral("%1: %2").arg(QLatin1String(name), message));
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

void leaveCanvas(AutomationGestureCheckRig &rig)
{
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(&rig.canvas(), &leave);
    rig.pump();
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

bool cropUnchanged(const QImage &idle, const QImage &hover, const QRectF &logical, qreal dpr)
{
    const QRect rect = deviceRect(logical, dpr, idle.size()).intersected(idle.rect());
    return !rect.isEmpty() && idle.size() == hover.size() && idle.copy(rect) == hover.copy(rect);
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

qreal lineSampleY(const QRect &plot, qreal avoidY, qreal clearance)
{
    const qreal top = plot.top() + clearance;
    const qreal bottom = plot.bottom() - clearance;
    if (std::abs(top - avoidY) >= std::abs(bottom - avoidY))
        return top;
    return bottom;
}

int lineBudget(qreal radius, qreal dpr)
{
    return std::max(4, int(std::ceil(6.0 * radius * dpr)));
}

void setTempoPoints(AutomationGestureCheckRig &rig, const std::vector<TempoPoint> &points)
{
    if (rig.document().tempoPoints() == points)
        return;
    TempoEdit edit;
    edit.remove = rig.document().tempoPoints();
    edit.add = points;
    rig.document().applyTempoEdit(edit);
    rig.documentChanged();
}

void setCcPoints(AutomationGestureCheckRig &rig,
                 const std::vector<SongDocument::LanePointValue> &points)
{
    rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                   std::numeric_limits<uint64_t>::max(), points);
    rig.documentChanged();
}

std::vector<SongDocument::LanePointValue> laneValues(const std::vector<DocLanePoint> &points)
{
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const auto &point : points)
        values.push_back({point.tick, point.value});
    return values;
}

qreal valueY(const QRect &body, const AutomationGeometry &geometry, int minimum, int maximum,
             int value)
{
    return AutomationProjection::valueY(body, geometry, minimum, maximum, value);
}

PreparedLane prepareLane(AutomationGestureCheckRig &rig, const Case &row)
{
    PreparedLane lane;
    if (row.kind == AdapterKind::Tempo) {
        setTempoPoints(
            rig, {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
                  {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)}});
        lane.handle = LaneHandle{0};
    } else {
        lane.handle = rig.handleFor(rig.pan);
        if (!lane.handle.valid())
            return lane;
        setCcPoints(rig, {{kHeldTick, kCcHeld}, {kNodeTick, kCcNode}});
    }
    const auto geometry = rig.geometry();
    const qreal dpr = rig.canvas().devicePixelRatioF();
    const auto projection = rig.projection();
    lane.body = rig.bodyFor(lane.handle);
    if (row.kind == AdapterKind::Tempo) {
        lane.insertionPos = rig.tempoBodyPoint(96, kTempoCursor);
        lane.heldY = valueY(lane.body, geometry, CoreTimeDefaults::kMinTempoBpm,
                            CoreTimeDefaults::kMaxTempoBpm, kTempoHeld);
        lane.nodeY = valueY(lane.body, geometry, CoreTimeDefaults::kMinTempoBpm,
                            CoreTimeDefaults::kMaxTempoBpm, kTempoNode);
    } else {
        lane.insertionPos = rig.pointAt(rig.pan, 96, kCcCursor).position;
        lane.heldY = valueY(lane.body, geometry, 0, 127, kCcHeld);
        lane.nodeY = valueY(lane.body, geometry, 0, 127, kCcNode);
    }
    lane.priorHeldY = lane.heldY;
    lane.plot = {geometry.plotOrigin, lane.body.top(),
                 std::max(0, rig.canvas().width() - geometry.plotOrigin), lane.body.height()};
    NodeLaneHoverState insertionProbe;
    insertionProbe.hover.lane = lane.handle;
    insertionProbe.hover.pos = lane.insertionPos;
    lane.insertionTick = uint64_t(std::max(0.0, insertionProbe.insertionTick(projection, false)));
    lane.insertionX = projection.displayX(lane.insertionTick, dpr);
    lane.nodeX = projection.displayX(kNodeTick, dpr);
    lane.nodePos = QPointF(lane.nodeX, lane.nodeY);
    return lane;
}

Topology runCase(AutomationGestureCheckRig &rig, const Case &row,
                 const AutomationGestureCheck &check)
{
    Topology topology;
    const auto lane = prepareLane(rig, row);
    if (!lane.handle.valid() || lane.plot.isEmpty()) {
        report(check, row.name, false,
               QStringLiteral("lane body is missing from the canvas stack"));
        return topology;
    }
    report(check, row.name, lane.insertionTick != kHeldTick && lane.insertionTick != kNodeTick,
           QStringLiteral("inter-node insertion landed on an existing node"));
    leaveCanvas(rig);
    const QImage idle = rig.renderArea();
    const auto before = snapshot(rig.document());
    const auto geometry = rig.geometry();
    const qreal dpr = rig.canvas().devicePixelRatioF();
    const qreal radius =
        geometry.nodePaintRadius + geometry.nodeOutlineDipWidth + 2 * layout::singlePixel();
    const qreal lineHalf =
        std::max(qreal(layout::singlePixel()), qreal(geometry.hoverPaintPadding + 1));
    const auto previewUnchanged = [&](const char *label) {
        report(check, row.name, unchanged(before, snapshot(rig.document())),
               QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
    };
    report(check, row.name,
           lane.nodeX - radius >= 0 && lane.nodeX + radius < rig.canvas().width() &&
               lane.nodeY - radius >= 0 && lane.nodeY + radius < rig.canvas().height(),
           QStringLiteral("existing-node hover probe is outside the canvas"));

    rig.mouseMove(lane.insertionPos, Qt::NoButton);
    rig.pump();
    const QImage insertion = rig.renderArea();
    previewUnchanged("insertion preview");
    const qreal insertionLineY = lineSampleY(lane.plot, lane.heldY, radius + 4);
    topology.insertionLine =
        changedPixels(idle, insertion, lineProbe(lane.insertionX, insertionLineY, lineHalf, 6),
                      dpr) > 0;
    const int ghostPixels =
        changedPixels(idle, insertion, nodeProbe(lane.insertionX, lane.heldY, radius), dpr);
    topology.heldGhost = ghostPixels > lineBudget(radius, dpr);
    topology.insertionLabel =
        changedPixels(idle, insertion, labelProbe(lane.insertionX, lane.heldY, lane.plot), dpr) > 0;
    report(check, row.name, topology.insertionLine,
           QStringLiteral("inter-node hover did not paint an insertion line"));
    report(check, row.name, topology.heldGhost,
           QStringLiteral("inter-node hover did not paint a held-value ghost"));
    report(check, row.name, topology.insertionLabel,
           QStringLiteral("inter-node hover did not paint a value label"));

    const auto afterInsertion = rig.canvas().diagnostics();
    rig.mouseMove(lane.insertionPos, Qt::NoButton);
    rig.pump();
    const auto afterRepeat = rig.canvas().diagnostics();
    const QImage repeated = rig.renderArea();
    previewUnchanged("repeat hover");
    topology.noRepeatChurn =
        afterRepeat.contentInvalidationCount == afterInsertion.contentInvalidationCount &&
        repeated == insertion;
    report(check, row.name, topology.noRepeatChurn,
           QStringLiteral("repeat hover at the same coordinate churned a stale repaint"));

    rig.mouseMove(lane.nodePos, Qt::NoButton);
    rig.pump();
    const QImage nodeHover = rig.renderArea();
    previewUnchanged("node hover");
    topology.nodeRing =
        changedPixels(idle, nodeHover, nodeProbe(lane.nodeX, lane.nodeY, radius), dpr) > 0;
    topology.nodeLabel =
        changedPixels(idle, nodeHover, labelProbe(lane.nodeX, lane.nodeY, lane.plot), dpr) > 0;
    const int strayGhost =
        changedPixels(idle, nodeHover, nodeProbe(lane.nodeX, lane.priorHeldY, radius), dpr);
    topology.noInsertionGhost = strayGhost >= 0 &&
                                std::abs(lane.nodeY - lane.priorHeldY) > 2 * radius &&
                                strayGhost <= lineBudget(radius, dpr);
    report(check, row.name, topology.nodeRing,
           QStringLiteral("existing-node hover did not paint a node ring"));
    report(check, row.name, topology.nodeLabel,
           QStringLiteral("existing-node hover did not paint a value label"));
    report(check, row.name, topology.noInsertionGhost,
           QStringLiteral("existing-node hover painted an insertion ghost"));

    const QRect voice = rig.voiceBounds();
    if (!voice.isEmpty()) {
        rig.mouseMove(QPointF(lane.insertionPos.x(), voice.center().y()), Qt::NoButton);
        rig.pump();
    } else {
        leaveCanvas(rig);
    }
    const QImage transitioned = rig.renderArea();
    previewUnchanged("lane transition");
    const bool transitionCleared = cropUnchanged(idle, transitioned, lane.plot, dpr);
    leaveCanvas(rig);
    const QImage left = rig.renderArea();
    previewUnchanged("leave");
    topology.leaveCleared = transitionCleared && cropUnchanged(idle, left, lane.plot, dpr);
    report(check, row.name, topology.leaveCleared,
           QStringLiteral("lane transition or leave left dirty hover bounds"));
    return topology;
}

bool sameTopology(const Topology &left, const Topology &right)
{
    return left.insertionLine == right.insertionLine && left.heldGhost == right.heldGhost &&
           left.insertionLabel == right.insertionLabel && left.nodeRing == right.nodeRing &&
           left.nodeLabel == right.nodeLabel && left.noInsertionGhost == right.noInsertionGhost &&
           left.leaveCleared == right.leaveCleared && left.noRepeatChurn == right.noRepeatChurn;
}

} // namespace

void checkNodeLaneHoverParity(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    rig.setAutomationZoom(96.0);
    rig.setAutomationScroll(0.0);
    rig.setPersistentPencil(false);
    rig.pump();
    rig.mousePress(rig.tempoHeaderPoint());
    rig.mouseRelease(rig.tempoHeaderPoint());
    rig.pump();
    const bool tempoExpanded = rig.voiceBounds().top() > rig.geometry().addLaneStripHeight;
    check(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"));
    const auto initialTempo = rig.document().tempoPoints();
    const auto initialPan = rig.document().lanePoints(rig.pan.track, rig.pan.controller);
    std::array<Topology, kCases.size()> topologies{};
    for (std::size_t index = 0; index < kCases.size(); ++index) {
        if (kCases[index].kind == AdapterKind::Tempo && !tempoExpanded)
            continue;
        topologies[index] = runCase(rig, kCases[index], check);
        setTempoPoints(rig, initialTempo);
        setCcPoints(rig, laneValues(initialPan));
    }
    check(sameTopology(topologies.front(), topologies.back()),
          QStringLiteral("Tempo and CC hover chrome topology diverged"));
}
