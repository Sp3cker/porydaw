#include "checks/visual/transportregions.h"

#include "ui/transportbar.h"

#include <QAction>
#include <QString>
#include <QWidget>

namespace checks::visual {

QList<Region> transportRegions(TransportBar &bar)
{
    QList<Region> regions;
    const auto append = [&](const char *name, QWidget *widget) {
        // Missing controls are errors, not an excuse to silently lose coverage.
        if (!widget) {
            regions.append({QString::fromLatin1(name), {}});
            return;
        }
        if (widget->isVisibleTo(&bar)) {
            const QRect bounds(widget->mapTo(&bar, QPoint()), widget->size());
            regions.append({QString::fromLatin1(name), bounds.intersected(bar.rect())});
        }
    };
    append("transport.go-to-start", bar.widgetForAction(bar.goToStartAction()));
    append("transport.play", bar.widgetForAction(bar.playAction()));
    append("transport.pause", bar.widgetForAction(bar.pauseAction()));
    append("transport.stop", bar.widgetForAction(bar.stopAction()));
    append("transport.loop", bar.widgetForAction(bar.loopAction()));
    append("transport.follow-playhead", bar.widgetForAction(bar.followPlayheadAction()));
    append("transport.resonance", bar.widgetForAction(bar.resonanceAction()));
    const struct {
        const char *name;
        const char *objectName;
    } controls[] = {
        {"transport.time", "transportTimeLabel"},
        {"transport.scale-root", "transportScaleRoot"},
        {"transport.scale-type", "transportScaleType"},
        {"transport.scale-highlight", "transportScaleHighlight"},
        {"transport.scale-fold", "transportScaleFold"},
        {"transport.master-volume-caption", "transportMasterVolumeCaption"},
        {"transport.master-volume", "transportMasterVolume"},
        {"transport.output-volume-caption", "transportOutputVolumeCaption"},
        {"transport.output-volume", "transportOutputVolume"},
    };
    for (const auto &control : controls)
        append(control.name, bar.findChild<QWidget *>(QString::fromLatin1(control.objectName)));
    return regions;
}

} // namespace checks::visual
