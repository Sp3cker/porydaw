#include "domains.h"

#include <QCursor>

#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"

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

    const auto pencilShown = [&rig] { return !rig.canvas().cursor().pixmap().isNull(); };
    const auto shapeIs = [&rig](Qt::CursorShape shape) {
        return rig.canvas().cursor().shape() == shape;
    };

    const QPointF plotPoint = rig.pointAt(rig.pan, 24, 64).position;
    const QPointF gutterPoint(geometry.plotOrigin / 2.0, plotPoint.y());

    rig.setPersistentPencil(true);
    rig.mouseMove(plotPoint, Qt::NoButton);
    rig.pump();
    check(pencilShown(),
          QStringLiteral("Pencil mode over an editable CC plot did not install the bitmap "
                         "pencil cursor"));

    rig.mouseMove(gutterPoint, Qt::NoButton);
    rig.pump();
    check(shapeIs(Qt::ArrowCursor),
          QStringLiteral("Pencil mode over the left gutter did not keep the arrow cursor"));

    const QRect voiceBounds = rig.voiceBounds();
    if (voiceBounds.height() > 0) {
        rig.mouseMove(QPointF(geometry.plotOrigin + 20.0,
                              qreal(voiceBounds.top() + voiceBounds.height() / 2)),
                      Qt::NoButton);
        rig.pump();
        check(shapeIs(Qt::ArrowCursor),
              QStringLiteral("Pencil mode over the voice-change lane did not keep the arrow "
                             "cursor"));
    }

    rig.mouseMove(QPointF(panBody.center().x(), qreal(panBody.bottom())), Qt::NoButton);
    rig.pump();
    check(shapeIs(Qt::SplitVCursor),
          QStringLiteral("Pencil mode over a row boundary did not keep the resize cursor"));

    if (!rig.canvas().rows().empty()) {
        const qreal addLaneY =
            qreal(rig.canvas().height()) - qreal(geometry.addLaneStripHeight) / 2.0;
        rig.mouseMove(QPointF(geometry.plotOrigin + 40.0, addLaneY), Qt::NoButton);
        rig.pump();
        check(shapeIs(Qt::ArrowCursor),
              QStringLiteral("Pencil mode over the Add Lane strip did not keep the arrow "
                             "cursor"));
    }

    rig.mouseMove(rig.tempoHeaderPoint(), Qt::NoButton);
    rig.pump();
    check(shapeIs(Qt::ArrowCursor),
          QStringLiteral("Pencil mode over the tempo header did not keep the arrow cursor"));

    check(rig.expandTempo(), QStringLiteral("Cursor fixture could not expand the tempo lane"));
    const QPointF tempoPoint = rig.tempoBodyPoint(24, 60);
    rig.mouseMove(tempoPoint, Qt::NoButton);
    rig.pump();
    check(pencilShown(),
          QStringLiteral("Pencil mode over the expanded tempo node plot did not show the "
                         "bitmap pencil cursor"));
    rig.mousePress(rig.tempoHeaderPoint());
    rig.mouseRelease(rig.tempoHeaderPoint());
    rig.pump();

    rig.setPersistentPencil(false);
    rig.mouseMove(plotPoint, Qt::NoButton);
    rig.pump();
    check(shapeIs(Qt::ArrowCursor),
          QStringLiteral("Turning Pencil mode off did not restore the arrow cursor over an "
                         "editable plot"));
}