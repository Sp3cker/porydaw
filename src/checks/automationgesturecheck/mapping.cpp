#include "domains.h"

#include <algorithm>
#include <type_traits>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/voicechangelane.h"
#include "ui/songview.h"

static_assert(!std::is_base_of_v<NodeLane, VoiceChangeLane>);

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

    const auto &rows = rig.canvas().rows();
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

    const QRect voice = rig.voiceBounds();
    const bool voiceIsCcRow = std::any_of(rows.cbegin(), rows.cend(), [](const AutomationRow &row) {
        return row.id.controller == DOC_CC_VOICE;
    });
    check(!rows.empty() && !voice.isEmpty() && !voiceIsCcRow &&
              voice.bottom() < projection.rowTop(0),
          QStringLiteral("Voice Change hit-tested as a NodeLane or CC row"));
    const auto voiceBefore = rig.snapshot(rig.pan.track, rig.pan.controller);
    const QPointF voiceStart(rig.geometry().plotOrigin + 40, voice.center().y());
    const QPointF voiceEnd = voiceStart + QPointF(48, 6);
    rig.mousePress(voiceStart);
    rig.mouseMove(voiceEnd);
    rig.mouseRelease(voiceEnd);
    rig.pump();
    const auto voiceAfter = rig.snapshot(rig.pan.track, rig.pan.controller);
    check(voiceBefore.smf == voiceAfter.smf && voiceBefore.revision == voiceAfter.revision &&
              voiceBefore.undoIndex == voiceAfter.undoIndex && !rig.canvas().isPanning() &&
              !rig.canvas().bandPreviewContainsRow(0) && !rig.view().userGestureActive() &&
              !rig.view().selectionModel().timeSelection().active(),
          QStringLiteral("Voice Change entered a NodeLane gesture"));

    const int panRow = rig.rowIndex(rig.pan);
    check(panRow >= 0 && panRow < int(rows.size()),
          QStringLiteral("Pencil indicator rows are missing from the live projection"));
    if (panRow < 0 || panRow >= int(rows.size()))
        return;

    const auto seed = rig.pointAt(rig.pan, 24, 64);
    const auto indicatorCell = projection.snapCellAt(seed.mapped.rawTick);
    const double indicatorTick =
        double(indicatorCell.tickBegin) + 0.4 * double(rig.view().fineGridTicks());
    const auto panInput = rig.pointAt(rig.pan, indicatorTick, 64);
    NodeLaneHoverState panIndicator;
    panIndicator.hover.lane = LaneHandle{panRow + 1};
    panIndicator.hover.pos = panInput.position;
    const auto mappedCell = projection.snapCellAt(panInput.mapped.rawTick);
    const double panCaretTick = double(rig.view().snapTick(panInput.mapped.rawTick, true));
    check(panInput.mapped.point.tick == mappedCell.tickBegin &&
              panInput.mapped.cell.tickEnd == mappedCell.tickEnd &&
              panInput.mapped.rawTick != double(panInput.mapped.point.tick) &&
              panInput.mapped.rawTick != panCaretTick &&
              projection.valueAtY(panRow, panInput.position.y()) == panInput.mapped.point.value &&
              panIndicator.insertionTick(projection, true) == double(panInput.mapped.point.tick) &&
              panIndicator.insertionTick(projection, false) == panCaretTick,
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
