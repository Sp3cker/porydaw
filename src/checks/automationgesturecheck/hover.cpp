#include "domains.h"
#include "support.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <QAbstractItemModel>
#include <QDeadlineTimer>
#include <QImage>

#include <QPointF>
#include <QQuickItem>
#include <QWidget>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QRect>
#include <QRectF>
#include <QString>
#include <QtGlobal>

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

struct PreparedLane {
    LaneHandle handle;
    QRect body;
    QPointF insertionPos;
    QPointF nodePos;
    uint64_t insertionTick = 0;
    qreal insertionX = 0;
    qreal heldY = 0;
    qreal nodeX = 0;
    qreal nodeY = 0;
};

constexpr std::array kCases{
    Case{AdapterKind::Tempo, "Tempo"},
    Case{AdapterKind::Cc, "CC"},
};

constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kNodeTick = 144;
constexpr double kHeldBodyFraction = 0.25;
constexpr double kNodeBodyFraction = 0.75;
constexpr double kCursorBodyFraction = 0.50;

int valueAtBodyFraction(int minimum, int maximum, double fractionFromBottom)
{
    return minimum + int(std::lround(double(maximum - minimum) * fractionFromBottom));
}

void leaveCanvas(AutomationGestureCheckRig &rig)
{
    rig.canvas().pointerLeave();
    rig.pump();
}

struct HoverObservation {
    songview::TimelineQuickLayerData layer;
    QImage framebuffer;
    int textRows = 0;
    int valueTextRows = 0;
    int drawableValueTextRows = 0;
    int viewportValueTextRows = 0;
    QString text;
    QRectF rect;
    QRectF clip;
    bool chromeVisible = false;
    bool framebufferReady = false;
};

HoverObservation observeHover(AutomationGestureCheckRig &rig)
{
    HoverObservation observation;
    QString captureError;
    observation.framebuffer = rig.renderAutomationViewport(&captureError);
    observation.framebufferReady = captureError.isEmpty() && !observation.framebuffer.isNull();
    observation.layer = rig.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    const QWidget *const viewport = rig.page().scrollViewport();
    const QRectF viewportRect(0.0, 0.0, viewport ? viewport->width() : 0.0,
                              viewport ? viewport->height() : 0.0);
    const QAbstractItemModel *const model = rig.quickScene().automationHoverTextModel();
    observation.textRows = model->rowCount();
    for (int row = 0; row < observation.textRows; ++row) {
        const QModelIndex index = model->index(row, 0);
        const QString text =
            model->data(index, songview::TimelineQuickTextModel::TextRole).toString();
        if (text.isEmpty())
            continue;
        ++observation.valueTextRows;
        observation.text = text;
        observation.rect = model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        observation.clip =
            model->data(index, songview::TimelineQuickTextModel::ClipRectRole).toRectF();
        if (!observation.rect.isEmpty() && !observation.clip.isEmpty() &&
            observation.rect.intersects(observation.clip)) {
            ++observation.drawableValueTextRows;
        }
        if (viewportRect.contains(observation.clip))
            ++observation.viewportValueTextRows;
    }
    songview::TimelineQuickView *const quickHost =
        rig.view().findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
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

bool pixelClearedAt(const QImage &idle, const QImage &cleared, const QPointF &point)
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

bool hasValueText(const HoverObservation &observation)
{
    return observation.framebufferReady && observation.valueTextRows == 1 &&
           observation.drawableValueTextRows == 1 && observation.viewportValueTextRows == 1 &&
           !observation.layer.rects.empty();
}

bool isClear(const HoverObservation &observation)
{
    return observation.framebufferReady && observation.layer.rects.empty() &&
           observation.layer.triangles.empty() && observation.textRows == 0 &&
           !observation.chromeVisible;
}

bool sameRetainedHover(const HoverObservation &left, const HoverObservation &right)
{
    return left.framebufferReady && right.framebufferReady &&
           left.framebuffer == right.framebuffer && left.textRows == right.textRows &&
           left.valueTextRows == right.valueTextRows &&
           left.drawableValueTextRows == right.drawableValueTextRows &&
           left.viewportValueTextRows == right.viewportValueTextRows && left.text == right.text &&
           left.rect == right.rect && left.clip == right.clip &&
           left.chromeVisible == right.chromeVisible;
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
    const int minimum = row.kind == AdapterKind::Tempo ? CoreTimeDefaults::kMinTempoBpm : 0;
    const int maximum = row.kind == AdapterKind::Tempo ? CoreTimeDefaults::kMaxTempoBpm : 127;
    const int held = valueAtBodyFraction(minimum, maximum, kHeldBodyFraction);
    const int node = valueAtBodyFraction(minimum, maximum, kNodeBodyFraction);
    const int cursor = valueAtBodyFraction(minimum, maximum, kCursorBodyFraction);
    if (row.kind == AdapterKind::Tempo) {
        setTempoPoints(rig, {{kHeldTick, tempoUsForBpm(held)}, {kNodeTick, tempoUsForBpm(node)}});
        lane.handle = AutomationGestureCheckRig::kTempoHandle;
    } else {
        lane.handle = rig.handleFor(rig.pan);
        if (!lane.handle.valid())
            return lane;
        setCcPoints(rig, {{kHeldTick, held}, {kNodeTick, node}});
    }
    const auto geometry = rig.geometry();
    const qreal dpr = rig.automationDpr();
    const auto projection = rig.projection();
    lane.body = rig.bodyFor(lane.handle);
    lane.insertionPos = {projection.displayX(kFixtureTick, dpr),
                         valueY(lane.body, geometry, minimum, maximum, cursor)};
    lane.heldY = valueY(lane.body, geometry, minimum, maximum, held);
    lane.nodeY = valueY(lane.body, geometry, minimum, maximum, node);
    NodeLaneHoverState insertionProbe;
    insertionProbe.hover.lane = lane.handle;
    insertionProbe.hover.pos = lane.insertionPos;
    lane.insertionTick = uint64_t(std::max(0.0, insertionProbe.insertionTick(projection, false)));
    lane.insertionX = projection.displayX(lane.insertionTick, dpr);
    lane.nodeX = projection.displayX(kNodeTick, dpr);
    lane.nodePos = QPointF(lane.nodeX, lane.nodeY);
    return lane;
}

void checkDirectHoverRoute(AutomationGestureCheckRig &rig, const PreparedLane &lane,
                           const AutomationGestureCheck &check)
{
    const Check probe{check, "direct hover"};
    songview::TimelineQuickView *const quickHost =
        rig.view().findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    probe.require(quickHost && quickHost->quickWindow(),
                  QStringLiteral("native Quick timeline host is unavailable"));
    if (!quickHost || !quickHost->quickWindow())
        return;

    probe.require(!quickHost->quickWindow()->flags().testFlag(Qt::WindowTransparentForInput),
                  QStringLiteral("native Quick timeline host accepts pointer input"));
    probe.require(!rig.automationHost().accessibilityDescription().isEmpty(),
                  QStringLiteral("attaching the input host did not publish an accessibility "
                                 "description"));

    const auto before = snapshot(rig.document());
    const auto previewUnchanged = [&](const char *label) {
        probe.require(
            isUnchanged(before, snapshot(rig.document())),
            QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
    };

    leaveCanvas(rig);
    const auto idle = rig.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    rig.mouseMove(lane.insertionPos, Qt::NoButton);
    rig.pump();
    const qreal expectedRootX = rig.view().timelinePlotOrigin() +
                                rig.view().camera().contentX(lane.insertionTick) -
                                quickHost->geometry().x();
    QDeadlineTimer timeout{1000};
    auto hoverLayer = rig.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    while ((!quickHost->hoverVisible() ||
            std::abs(quickHost->hoverRootContentX() - expectedRootX) > layout::singlePixel() ||
            hoverLayer.revision <= idle.revision) &&
           !timeout.hasExpired()) {
        rig.pump();
        hoverLayer = rig.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    }
    previewUnchanged("direct hover");
    probe.require(quickHost->hoverVisible(),
                  QStringLiteral("direct pointer move did not publish the automation hover "
                                 "guide"));
    probe.require(std::abs(quickHost->hoverRootContentX() - expectedRootX) <= layout::singlePixel(),
                  QStringLiteral("direct pointer move left the automation hover guide at x=%1, "
                                 "expected x=%2")
                      .arg(quickHost->hoverRootContentX())
                      .arg(expectedRootX));
    probe.require(hoverLayer.revision > idle.revision,
                  QStringLiteral("direct pointer move did not rebuild the automation hover "
                                 "layer"));
    const HoverObservation routed = observeHover(rig);
    const QPointF insertionCenter =
        rig.automationContentToViewport(QPointF(lane.insertionX, lane.heldY));
    probe.require(hasFilledNodeAt(routed.layer, insertionCenter),
                  QStringLiteral("direct pointer move did not render the held-value insertion "
                                 "point"));
    probe.require(hasValueText(routed),
                  QStringLiteral("direct pointer move did not render the insertion value"));

    const int cursorClearsBeforeLeave = rig.automationHost().cursorClears();
    // A direct pointer leave clears the hover chrome completely.
    leaveCanvas(rig);
    QDeadlineTimer leaveTimeout{1000};
    HoverObservation cleared = observeHover(rig);
    while (!isClear(cleared) && !leaveTimeout.hasExpired()) {
        rig.pump();
        cleared = observeHover(rig);
    }
    previewUnchanged("pointer leave");
    probe.require(isClear(cleared), QStringLiteral("hover survived its pointer leave"));
    probe.require(rig.automationHost().cursorClears() > cursorClearsBeforeLeave,
                  QStringLiteral("pointer leave did not clear the automation cursor"));

    // FocusLost is a no-op while a press is live: native menus temporarily
    // transfer focus and must not tear down gesture state.
    const int grabsBefore = rig.automationHost().grabReleases();
    rig.mousePress(lane.insertionPos);
    rig.pump();
    previewUnchanged("press");
    probe.require(rig.automationHost().focusRequests() > 0 &&
                      rig.automationHost().lastFocusReason() == Qt::MouseFocusReason,
                  QStringLiteral("handled automation press did not request input focus through "
                                 "the host"));
    rig.canvas().inputCancelled(songview::TimelineInputCancelReason::FocusLost);
    rig.pump();
    previewUnchanged("focus-lost cancellation");
    probe.require(rig.automationHost().grabReleases() == grabsBefore,
                  QStringLiteral("focus-lost cancellation released the pointer grab"));

    // Strong cancellation: releases the grab, clears hover and gesture, and
    // mutates nothing.
    rig.canvas().inputCancelled(songview::TimelineInputCancelReason::WindowDeactivated);
    rig.pump();
    previewUnchanged("window-deactivation cancellation");
    probe.require(rig.isIdle(),
                  QStringLiteral("window-deactivation cancellation left a live gesture"));
    probe.require(rig.automationHost().grabReleases() > grabsBefore,
                  QStringLiteral("window-deactivation cancellation did not release the pointer "
                                 "grab"));
    QDeadlineTimer cancelTimeout{1000};
    HoverObservation cancelled = observeHover(rig);
    while (!isClear(cancelled) && !cancelTimeout.hasExpired()) {
        rig.pump();
        cancelled = observeHover(rig);
    }
    probe.require(isClear(cancelled),
                  QStringLiteral("hover survived strong window-deactivation cancellation"));

    // Cancellation must not latch passive hover off.
    rig.mouseMove(lane.insertionPos, Qt::NoButton);
    rig.pump();
    QDeadlineTimer resumeTimeout{1000};
    hoverLayer = rig.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    while ((!quickHost->hoverVisible() ||
            std::abs(quickHost->hoverRootContentX() - expectedRootX) > layout::singlePixel() ||
            hoverLayer.revision <= cancelled.layer.revision) &&
           !resumeTimeout.hasExpired()) {
        rig.pump();
        hoverLayer = rig.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    }
    probe.require(quickHost->hoverVisible() && hoverLayer.revision > cancelled.layer.revision,
                  QStringLiteral("cancellation latched passive hover off"));

    // The remaining strong reasons cancel cleanly while idle.
    const auto idleReasonsBefore = snapshot(rig.document());
    rig.canvas().inputCancelled(songview::TimelineInputCancelReason::Hidden);
    rig.canvas().inputCancelled(songview::TimelineInputCancelReason::PointerUngrabbed);
    rig.pump();
    probe.require(
        isUnchanged(idleReasonsBefore, snapshot(rig.document())) && rig.isIdle(),
        QStringLiteral("hidden or ungrab cancellation mutated the document or left a gesture"));
    leaveCanvas(rig);
}

Topology runCase(AutomationGestureCheckRig &rig, const Case &row,
                 const AutomationGestureCheck &check)
{
    Topology topology;
    const Check probe{check, row.name};
    const auto lane = prepareLane(rig, row);
    if (!lane.handle.valid() || lane.body.isEmpty()) {
        probe.require(false, QStringLiteral("lane body is missing from the canvas stack"));
        return topology;
    }
    probe.require(lane.insertionTick != kHeldTick && lane.insertionTick != kNodeTick,
                  QStringLiteral("inter-node insertion landed on an existing node"));
    leaveCanvas(rig);
    const HoverObservation idle = observeHover(rig);
    const auto before = snapshot(rig.document());
    const auto previewUnchanged = [&](const char *label) {
        probe.require(
            isUnchanged(before, snapshot(rig.document())),
            QStringLiteral("%1 mutated SMF, revision, or undo").arg(QLatin1String(label)));
    };
    probe.require(idle.framebufferReady,
                  QStringLiteral("Quick automation framebuffer was unavailable"));
    const auto geometry = rig.geometry();
    const QPointF insertionCenter =
        rig.automationContentToViewport(QPointF(lane.insertionX, lane.heldY));
    const QPointF nodeCenter = rig.automationContentToViewport(QPointF(lane.nodeX, lane.nodeY));
    const QPointF strayGhostCenter =
        rig.automationContentToViewport(QPointF(lane.nodeX, lane.heldY));

    rig.mouseMove(lane.insertionPos, Qt::NoButton);
    rig.pump();
    const HoverObservation insertion = observeHover(rig);
    previewUnchanged("insertion preview");
    topology.insertionLine = insertion.framebufferReady && insertion.chromeVisible;
    topology.heldGhost = insertion.framebufferReady &&
                         insertion.layer.revision > idle.layer.revision &&
                         hasFilledNodeAt(insertion.layer, insertionCenter) &&
                         pixelChangedAt(idle.framebuffer, insertion.framebuffer, insertionCenter);
    topology.insertionLabel = hasValueText(insertion);
    probe.require(topology.insertionLine,
                  QStringLiteral("inter-node hover did not retain its Quick insertion line"));
    probe.require(topology.heldGhost,
                  QStringLiteral("inter-node hover did not retain its Quick held-value ghost"));
    probe.require(topology.insertionLabel,
                  QStringLiteral("inter-node hover did not retain its Quick value text"));

    rig.mouseMove(lane.insertionPos, Qt::NoButton);
    rig.pump();
    const HoverObservation repeated = observeHover(rig);
    previewUnchanged("repeat hover");
    topology.noRepeatChurn = sameRetainedHover(insertion, repeated);
    probe.require(topology.noRepeatChurn,
                  QStringLiteral("repeat hover at the same coordinate churned Quick state"));

    rig.mouseMove(lane.nodePos, Qt::NoButton);
    const auto awaitHoverRevision = [&](quint64 priorRevision) {
        QDeadlineTimer timeout{1000};
        HoverObservation observation = observeHover(rig);
        while ((!observation.framebufferReady || observation.layer.revision <= priorRevision) &&
               !timeout.hasExpired()) {
            rig.pump();
            observation = observeHover(rig);
        }
        return observation;
    };
    const HoverObservation nodeHover = awaitHoverRevision(insertion.layer.revision);
    previewUnchanged("node hover");
    topology.nodeRing =
        nodeHover.framebufferReady && nodeHover.layer.revision > insertion.layer.revision &&
        !nodeHover.layer.triangles.empty() &&
        hasAnnulusPixelChanges(insertion.framebuffer, nodeHover.framebuffer, nodeCenter,
                               nodelane::hoverRingRadius(geometry), 2 * layout::singlePixel());
    topology.nodeLabel = hasValueText(nodeHover);
    topology.noInsertionGhost = !hasFilledNodeAt(nodeHover.layer, strayGhostCenter);
    probe.require(topology.nodeRing,
                  QStringLiteral("existing-node hover did not retain its Quick node ring"));
    probe.require(topology.nodeLabel,
                  QStringLiteral("existing-node hover did not retain its Quick value text"));
    probe.require(topology.noInsertionGhost,
                  QStringLiteral("existing-node hover retained an insertion ghost"));

    leaveCanvas(rig);
    const auto awaitClear = [&] {
        QDeadlineTimer timeout{1000};
        HoverObservation observation = observeHover(rig);
        while (!isClear(observation) && !timeout.hasExpired()) {
            rig.pump();
            observation = observeHover(rig);
        }
        return observation;
    };
    const HoverObservation transitioned = awaitClear();
    previewUnchanged("lane transition");
    leaveCanvas(rig);
    const HoverObservation left = awaitClear();
    previewUnchanged("leave");
    topology.leaveCleared =
        isClear(transitioned) && isClear(left) &&
        pixelClearedAt(idle.framebuffer, nodeHover.framebuffer, insertionCenter) &&
        pixelClearedAt(idle.framebuffer, transitioned.framebuffer, insertionCenter) &&
        pixelClearedAt(idle.framebuffer, left.framebuffer, insertionCenter);
    probe.require(topology.leaveCleared,
                  QStringLiteral("lane transition or leave retained dirty Quick hover state"));
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
    const bool tempoExpanded =
        !rig.canvas().laneBody(AutomationGestureCheckRig::kTempoHandle).isEmpty();
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
    const PreparedLane directLane = prepareLane(rig, kCases[1]);
    if (directLane.handle.valid() && !directLane.body.isEmpty())
        checkDirectHoverRoute(rig, directLane, check);
    else
        check(false, QStringLiteral("CC lane was unavailable for direct hover routing"));
    setTempoPoints(rig, initialTempo);
    setCcPoints(rig, laneValues(initialPan));
}
