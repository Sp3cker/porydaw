#include "domains.h"

#include <limits>

#include "core/timedefaults.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview.h"

void checkAutomationPencilMapping(AutomationGestureCheckRig &rig,
                                  const AutomationGestureCheck &check)
{
    rig.setAutomationZoom(96.0);
    rig.setAutomationScroll(0.0);
    rig.pump();
    const auto projection = rig.projection();
    const auto *timeline = rig.view().timeline();
    const auto finalCell =
        timeline ? projection.snapCellAt(double(timeline->lengthTicks)) : AutomationGridCell{};
    check(timeline && finalCell.tickBegin < finalCell.tickEnd &&
              finalCell.tickEnd == timeline->lengthTicks,
          QStringLiteral("Pencil snap grid did not retain the final partial timeline cell"));
    const auto checkSupportedRange = [&](const AutomationGestureCheckRig::Lane &lane, int minimum,
                                         int maximum, const QString &name) {
        const auto handle = rig.handleFor(lane);
        const QRect body = rig.bodyFor(handle);
        if (!handle.valid() || body.isEmpty()) {
            check(false, QStringLiteral("Pencil %1 lane is missing from the node stack").arg(name));
            return;
        }
        const auto minimumInput = rig.pointAt(handle, 0, minimum);
        const auto maximumInput = rig.pointAt(handle, 0, maximum);
        check(minimumInput.mapped.point.value == minimum &&
                  maximumInput.mapped.point.value == maximum &&
                  AutomationProjection::valueAtY(body, rig.geometry(), minimum, maximum,
                                                 minimumInput.position.y()) == minimum,
              QStringLiteral("Pencil %1 lane did not support and map its value range").arg(name));
    };
    checkSupportedRange(rig.pan, 0, 127, QStringLiteral("pan"));
    checkSupportedRange(rig.lfo, 0, 127, QStringLiteral("LFO"));
    // The extracted Voice Change strip left the CC stack owning the canvas
    // top: row zero begins at y=0 and a pencil press there must map onto its
    // value range instead of vanishing into a reserved inset.
    const auto &rows = rig.canvas().rows();
    const QRect firstCcBody = rig.bodyFor(LaneHandle{1});
    check(!rows.empty() && !firstCcBody.isEmpty() && firstCcBody.top() == 0,
          QStringLiteral("First CC row did not own the canvas origin after the voice strip "
                         "extraction"));
    const auto topInput = rig.pointAt(LaneHandle{1}, 48, 64);
    check(topInput.position.y() >= qreal(firstCcBody.top()) &&
              topInput.position.y() < qreal(firstCcBody.bottom()) &&
              qRound(AutomationProjection::valueAtY(firstCcBody, rig.geometry(), 0, 127,
                                                    topInput.position.y())) == 64,
          QStringLiteral("Pencil mapping at the canvas top did not resolve onto the first CC "
                         "row"));
    const auto panHandle = rig.handleFor(rig.pan);
    check(panHandle.valid(), QStringLiteral("Pencil indicator lanes are missing from the stack"));
    if (!panHandle.valid())
        return;
    const auto seed = rig.pointAt(rig.pan, 24, 72);
    const auto indicatorCell = projection.snapCellAt(seed.mapped.rawTick);
    const double indicatorTick =
        double(indicatorCell.tickBegin) + 0.4 * double(rig.view().grid().fineGridTicks());
    const auto panInput = rig.pointAt(rig.pan, indicatorTick, 72);
    NodeLaneHoverState panIndicator(rig.page().font());
    panIndicator.hover.lane = panHandle;
    panIndicator.hover.pos = panInput.position;
    const auto mappedCell = projection.snapCellAt(panInput.mapped.rawTick);
    const double panCaretTick = double(rig.view().grid().snapTick(panInput.mapped.rawTick, true));
    const QRect panBody = rig.bodyFor(panHandle);
    check(panInput.mapped.point.tick == mappedCell.tickBegin &&
              panInput.mapped.cell.tickEnd == mappedCell.tickEnd &&
              panInput.mapped.rawTick != double(panInput.mapped.point.tick) &&
              panInput.mapped.rawTick != panCaretTick &&
              qRound(AutomationProjection::valueAtY(panBody, rig.geometry(), 0, 127,
                                                    panInput.position.y())) ==
                  panInput.mapped.point.value &&
              panIndicator.insertionTick(projection, true) == double(panInput.mapped.point.tick) &&
              panIndicator.insertionTick(projection, false) == panCaretTick,
          QStringLiteral("Automation insertion indicators did not retain live lane, value, and "
                         "fine-grid timing mappings"));
    if (timeline) {
        rig.document().writeLanePoints(rig.pan.track, rig.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
        rig.documentChanged();
    }
    rig.setPersistentPencil(true);
    rig.pump();
    const auto clickInput = rig.pointAt(rig.pan, indicatorTick, 72);
    rig.mousePress(clickInput.position);
    rig.mouseRelease(clickInput.position);
    rig.commitTimers();
    DocLanePoint clickedPoint;
    const bool clickFound = rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, clickInput.mapped.point.tick, &clickedPoint);
    check(clickFound && clickedPoint.tick == clickInput.mapped.point.tick &&
              clickedPoint.value == clickInput.mapped.point.value &&
              clickInput.mapped.point.tick == clickInput.mapped.cell.tickBegin,
          QStringLiteral("Pencil click did not quantize its committed point to the mapped cell "
                         "start and value"));
    const auto boundaryProjection = rig.projection();
    const auto followingCell =
        boundaryProjection.snapCellAt(double(clickInput.mapped.cell.tickEnd));
    const auto boundaryInput = rig.pointAt(rig.pan, followingCell.tickBegin, 96);
    check(followingCell.tickBegin < followingCell.tickEnd &&
              boundaryInput.mapped.point.tick == followingCell.tickBegin &&
              boundaryInput.mapped.cell.tickBegin == followingCell.tickBegin,
          QStringLiteral("Pencil exact cell boundary did not map to the following half-open "
                         "cell"));
    rig.mousePress(boundaryInput.position);
    rig.mouseRelease(boundaryInput.position);
    rig.commitTimers();
    DocLanePoint precedingPoint;
    DocLanePoint followingPoint;
    const bool precedingFound = rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, clickInput.mapped.point.tick, &precedingPoint);
    const bool followingFound = rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, boundaryInput.mapped.point.tick, &followingPoint);
    check(precedingFound && precedingPoint.value == clickInput.mapped.point.value &&
              followingFound && followingPoint.value == boundaryInput.mapped.point.value,
          QStringLiteral("Pencil exact cell-boundary click changed the preceding cell instead "
                         "of committing the mapped following-cell value"));
}
