#include "domains.h"

#include "rig.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationhover.h"
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

    const auto &rows = rig.area().rows();
    const auto checkSupportedRange = [&](const AutomationGestureCheckRig::Lane &lane,
                                         const QString &name) {
        const int index = rig.rowIndex(lane);
        if (index < 0 || index >= int(rows.size())) {
            check(false,
                  QStringLiteral("Pencil %1 row is missing from the live projection").arg(name));
            return;
        }
        const auto &row = rows[index];
        const int minimum = projection.rowMinimum(row);
        const int maximum = projection.rowMaximum(row);
        const auto minimumInput = rig.pointAt(lane, 0, minimum);
        const auto maximumInput = rig.pointAt(lane, 0, maximum);
        check(minimum == 0 && maximum == 127 && minimumInput.mapped.point.value == minimum &&
                  maximumInput.mapped.point.value == maximum,
              QStringLiteral("Pencil %1 row did not support and map its 0..127 value range")
                  .arg(name));
    };
    checkSupportedRange(rig.pan, QStringLiteral("pan"));
    checkSupportedRange(rig.lfo, QStringLiteral("LFO"));
    checkSupportedRange(rig.volume, QStringLiteral("volume"));
    checkSupportedRange(rig.voice, QStringLiteral("voice"));

    const int panRow = rig.rowIndex(rig.pan);
    const int voiceRow = rig.rowIndex(rig.voice);
    check(panRow >= 0 && voiceRow >= 0 && panRow < int(rows.size()) && voiceRow < int(rows.size()),
          QStringLiteral("Pencil indicator rows are missing from the live projection"));
    if (panRow < 0 || voiceRow < 0 || panRow >= int(rows.size()) || voiceRow >= int(rows.size()))
        return;

    const auto seed = rig.pointAt(rig.pan, 24, 64);
    const auto indicatorCell = projection.snapCellAt(seed.mapped.rawTick);
    const double indicatorTick =
        double(indicatorCell.tickBegin) + 0.4 * double(rig.view().fineGridTicks());
    const auto panInput = rig.pointAt(rig.pan, indicatorTick, 64);
    const auto voiceInput = rig.pointAt(rig.voice, indicatorTick, 3);
    AutomationHoverState panIndicator;
    panIndicator.hover.row = panRow;
    panIndicator.hover.pos = panInput.position;
    AutomationHoverState voiceIndicator;
    voiceIndicator.hover.row = voiceRow;
    voiceIndicator.hover.pos = voiceInput.position;
    const auto mappedCell = projection.snapCellAt(panInput.mapped.rawTick);
    const double panCaretTick = double(rig.view().snapTick(panInput.mapped.rawTick, true));
    const double voiceCaretTick = double(rig.view().snapTick(voiceInput.mapped.rawTick, true));
    check(panInput.mapped.point.tick == mappedCell.tickBegin &&
              panInput.mapped.cell.tickEnd == mappedCell.tickEnd &&
              panInput.mapped.rawTick != double(panInput.mapped.point.tick) &&
              panInput.mapped.rawTick != panCaretTick &&
              projection.valueAtY(panRow, panInput.position.y()) == panInput.mapped.point.value &&
              panIndicator.insertionTick(projection, rows[panRow], true) ==
                  double(panInput.mapped.point.tick) &&
              panIndicator.insertionTick(projection, rows[panRow], false) == panCaretTick &&
              projection.valueAtY(voiceRow, voiceInput.position.y()) ==
                  voiceInput.mapped.point.value &&
              voiceIndicator.insertionTick(projection, rows[voiceRow], true) == voiceCaretTick,
          QStringLiteral("Automation insertion indicators did not retain live row, value, and "
                         "fine-grid timing mappings"));

    rig.setPersistentPencil(true);
    rig.mousePress(panInput.position);
    rig.mouseRelease(panInput.position);
    rig.waitForTimers(0);
    DocLanePoint clickedPoint;
    const bool clickFound = rig.document().findLanePoint(rig.pan.track, rig.pan.controller,
                                                         panInput.mapped.point.tick, &clickedPoint);
    check(clickFound && clickedPoint.tick == panInput.mapped.point.tick &&
              clickedPoint.value == panInput.mapped.point.value &&
              panInput.mapped.point.tick == panInput.mapped.cell.tickBegin,
          QStringLiteral("Pencil click did not quantize its committed point to the mapped cell "
                         "start and value"));

    const auto boundaryProjection = rig.projection();
    const auto followingCell = boundaryProjection.snapCellAt(double(panInput.mapped.cell.tickEnd));
    const auto boundaryInput = rig.pointAt(rig.pan, followingCell.tickBegin, 96);
    check(followingCell.tickBegin < followingCell.tickEnd &&
              boundaryInput.mapped.point.tick == followingCell.tickBegin &&
              boundaryInput.mapped.cell.tickBegin == followingCell.tickBegin,
          QStringLiteral("Pencil exact cell boundary did not map to the following half-open "
                         "cell"));
    rig.mousePress(boundaryInput.position);
    rig.mouseRelease(boundaryInput.position);
    rig.waitForTimers(0);
    DocLanePoint precedingPoint;
    DocLanePoint followingPoint;
    const bool precedingFound = rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, panInput.mapped.point.tick, &precedingPoint);
    const bool followingFound = rig.document().findLanePoint(
        rig.pan.track, rig.pan.controller, boundaryInput.mapped.point.tick, &followingPoint);
    check(precedingFound && precedingPoint.value == panInput.mapped.point.value && followingFound &&
              followingPoint.value == boundaryInput.mapped.point.value,
          QStringLiteral("Pencil exact cell-boundary click changed the preceding cell instead "
                         "of committing the mapped following-cell value"));
}
