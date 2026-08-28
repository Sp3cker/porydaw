#include "domains.h"

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"

// The Voice Change strip moved to its own drawer page, so the automation
// canvas now begins its CC stack at the origin. This domain guards that
// migration seam: the first CC row owns y=0, and a pencil commit onto it
// lands on that row through document rebuilds and undo exactly as before.
void checkAutomationLifecycle(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check)
{
    rig.setAutomationZoom(96.0);
    rig.setAutomationScroll(0.0);
    rig.setPersistentPencil(false);
    rig.pump();

    const auto &rows = rig.canvas().rows();
    const LaneHandle firstRowHandle{1};
    const QRect firstBody = rig.bodyFor(firstRowHandle);
    check(!rows.empty() && !firstBody.isEmpty() && firstBody.top() == 0,
          QStringLiteral("First CC row did not own the canvas origin after the voice strip "
                         "extraction"));
    if (rows.empty() || firstBody.isEmpty())
        return;

    const auto rowId = rows.front().id;
    const auto before = rig.snapshot(rowId.track, rowId.controller);

    // A pencil click whose value maps near the row top must commit one point
    // on that row; no reserved strip may absorb the gesture above it.
    rig.setPersistentPencil(true);
    rig.pump();
    const auto commitInput = rig.pointAt(firstRowHandle, 240, 112);
    rig.mousePress(commitInput.position);
    rig.mouseRelease(commitInput.position);
    rig.commitTimers();
    const auto after = rig.snapshot(rowId.track, rowId.controller);
    DocLanePoint committed{};
    const bool committedHere =
        rig.document().findLanePoint(rowId.track, rowId.controller, commitInput.mapped.point.tick,
                                     &committed) &&
        committed.value == commitInput.mapped.point.value;
    check(after.revision == before.revision + 1 && after.undoIndex == before.undoIndex + 1 &&
              committedHere,
          QStringLiteral("Pencil click near the top of the first CC row did not commit one "
                         "point there in one undo step"));

    rig.documentChanged();
    rig.pump();
    const QRect rebuiltBody = rig.bodyFor(firstRowHandle);
    check(rebuiltBody.top() == 0 && !rebuiltBody.isEmpty(),
          QStringLiteral("Document rebuild did not keep the first CC row at the origin"));

    rig.document().undoStack()->undo();
    rig.documentChanged();
    rig.pump();
    const auto restored = rig.snapshot(rowId.track, rowId.controller);
    check(restored.smf == before.smf && rig.bodyFor(firstRowHandle).top() == 0,
          QStringLiteral("Undo did not restore the committed top-row point and origin"));
}
