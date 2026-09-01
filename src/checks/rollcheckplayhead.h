#pragma once

#include <QStringList>

class MidiTimeline;
class SongView;

QStringList timelineChromeCheckFailures(SongView &view, const MidiTimeline &timeline);
