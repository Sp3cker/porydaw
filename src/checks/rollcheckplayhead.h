#pragma once

#include <QStringList>

class QPixmap;

class MidiTimeline;
class SongView;

namespace songview {
class PlayheadOverlay;
}

QStringList timelineChromeCheckFailures(SongView &view, const MidiTimeline &timeline);
QStringList quickFallbackPlayheadCheckFailures(const MidiTimeline &timeline);
QStringList quickPositionOnlyPlayheadCheckFailures(const MidiTimeline &timeline);
QStringList quickScenePlayheadCheckFailures(const MidiTimeline &timeline);

#ifdef __APPLE__
QPixmap renderMacPlayheadOverlay(SongView &view, QStringList &failures);
void checkMacPlayheadLifecycle(SongView &view, songview::PlayheadOverlay &overlay,
                               QStringList &failures);
#endif
