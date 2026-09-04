#include "domains.h"

#include <QCursor>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/songview/quick/timelineinputitem.h"

// The Pencil cursor is a property of the pointer location, not of Pencil mode:
// it appears only over an editable node-lane plot. Every probe moves the mouse
// first and then asserts the canvas cursor, so the assertions are driven by
// canvas state rather than by the machine pointer.
void checkAutomationPencilCursor(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check)
{
    const auto geometry = rig.geometry();
    const LaneHandle panHandle = rig.handleFor(rig.pan);
    const QRect panBody = rig.bodyFor(panHandle);
    check(panHandle.valid() && !panBody.isEmpty(),
          QStringLiteral("Pencil cursor fixture did not expose the pan lane"));
    if (!panHandle.valid() || panBody.isEmpty())
        return;

    const auto pencilShown = [&rig] { return !rig.automationCursor().pixmap().isNull(); };
    const auto plotShapeIs = [&rig](Qt::CursorShape shape) {
        return rig.automationCursor().shape() == shape;
    };
    const auto gutterShapeIs = [&rig](Qt::CursorShape shape) {
        return rig.automationGutterInput().cursor().shape() == shape;
    };

    const QPointF plotPoint = rig.pointAt(rig.pan, 24, 64).position;
    const QPointF gutterPoint(rig.automationGutterInput().bounds().center().x(), plotPoint.y());

    rig.setPersistentPencil(true);
    rig.mouseMove(plotPoint, Qt::NoButton);
    rig.pump();
    check(pencilShown(),
          QStringLiteral("Pencil mode over an editable CC plot did not install the bitmap "
                         "pencil cursor"));

    rig.gutterMouseMove(gutterPoint);
    rig.pump();
    check(gutterShapeIs(Qt::ArrowCursor),
          QStringLiteral("Pencil mode over the physical gutter did not keep the arrow cursor"));

    rig.gutterMouseMove(QPointF(gutterPoint.x(), qreal(panBody.bottom())));
    rig.pump();
    check(gutterShapeIs(Qt::SplitVCursor),
          QStringLiteral("Pencil mode over a gutter row boundary did not keep the resize cursor"));

    if (!rig.canvas().rows().empty()) {
        const qreal addLaneY =
            qreal(rig.automationContentHeight()) - qreal(geometry.addLaneStripHeight) / 2.0;
        rig.gutterMouseMove(QPointF(gutterPoint.x(), addLaneY));
        rig.pump();
        check(gutterShapeIs(Qt::ArrowCursor),
              QStringLiteral("Pencil mode over the gutter Add Lane strip did not keep the arrow "
                             "cursor"));
    }

    rig.gutterMouseMove(rig.tempoHeaderPoint());
    rig.pump();
    check(gutterShapeIs(Qt::ArrowCursor),
          QStringLiteral("Pencil mode over the tempo gutter header did not keep the arrow cursor"));

    check(rig.expandTempo(), QStringLiteral("Cursor fixture could not expand the tempo lane"));
    const QPointF tempoPoint = rig.tempoBodyPoint(24, 60);
    rig.mouseMove(tempoPoint, Qt::NoButton);
    rig.pump();
    check(pencilShown(),
          QStringLiteral("Pencil mode over the expanded tempo node plot did not show the "
                         "bitmap pencil cursor"));
    rig.gutterMousePress(rig.tempoHeaderPoint());
    rig.gutterMouseRelease(rig.tempoHeaderPoint());
    rig.pump();

    // The pencil cursor bitmap is rebuilt against the host DPR, not a widget
    // device ratio; doubling the host DPR must double the cursor's ratio.
    const qreal dpr = rig.automationDpr();
    rig.automationHost().setDevicePixelRatio(dpr * 2.0);
    rig.canvasHostAppearanceChanged();
    rig.mouseMove(plotPoint, Qt::NoButton);
    rig.pump();
    check(qFuzzyCompare(rig.automationCursor().pixmap().devicePixelRatio(), dpr * 2.0),
          QStringLiteral("Pencil cursor did not rebuild for the host device pixel ratio"));
    rig.automationHost().setDevicePixelRatio(dpr);
    rig.canvasHostAppearanceChanged();
    rig.mouseMove(plotPoint, Qt::NoButton);
    rig.pump();

    rig.setPersistentPencil(false);
    rig.mouseMove(plotPoint, Qt::NoButton);
    rig.pump();
    check(plotShapeIs(Qt::ArrowCursor),
          QStringLiteral("Turning Pencil mode off did not restore the arrow cursor over an "
                         "editable plot"));
}