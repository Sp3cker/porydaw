#pragma once

#include <QStringList>

class MidiTimeline;
class QPixmap;
class SongView;

QStringList playheadOverlayCheckFailures(SongView &view, const MidiTimeline &timeline);

#ifdef __APPLE__
QPixmap renderMacPlayheadOverlay(SongView &view, QStringList &failures);
void checkMacPlayheadLifecycle(QStringList &failures);
#endif
