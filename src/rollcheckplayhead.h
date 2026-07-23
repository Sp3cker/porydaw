#pragma once

#include <QStringList>

class MidiTimeline;
class SongView;

QStringList playheadRenderingCheckFailures(SongView &view, const MidiTimeline &timeline);
