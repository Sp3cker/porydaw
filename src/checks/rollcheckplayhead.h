#pragma once

#include <QString>
#include <QStringList>

class QPixmap;

class MidiTimeline;
class SongView;

namespace songview {
class PlayheadOverlay;
}

// Quick-canvas playhead polarity: on Windows/Linux the QML
// timelineQuickRollPlayhead item carries the playhead pixels; on Apple the
// Quick canvas carries none because the CALayer path renders them natively.
#ifdef __APPLE__
inline constexpr bool kQuickCarriesPlayhead = false;
#else
inline constexpr bool kQuickCarriesPlayhead = true;
#endif

// Assert the Quick-canvas playhead polarity: each helper appends `message`
// only when the running platform's expectation is violated; the off-polarity
// one appends nothing.
inline void assertQuickPlayheadPresent(QStringList &failures, bool present, const QString &message)
{
    if (kQuickCarriesPlayhead && !present)
        failures.append(message);
}

inline void assertQuickPlayheadAbsent(QStringList &failures, bool present, const QString &message)
{
    if (!kQuickCarriesPlayhead && present)
        failures.append(message);
}

QStringList timelineChromeCheckFailures(SongView &view, const MidiTimeline &timeline);
QStringList quickScenePlayheadCheckFailures(const MidiTimeline &timeline);

#ifdef __APPLE__
QPixmap renderMacPlayheadOverlay(SongView &view, QStringList &failures);
void checkMacPlayheadLifecycle(SongView &view, songview::PlayheadOverlay &overlay,
                               QStringList &failures);
#endif
