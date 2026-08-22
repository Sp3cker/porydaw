// Private shared support for the automation-gesture check suite. Included only
// from files in this directory; other check suites must not include it. Owns
// the std::function-based check callback plus the document snapshot helpers
// that parity/contract/crosslane/hover used to define per file.

#pragma once

#include <cmath>
#include <cstdint>
#include <functional>
#include <vector>

#include <QByteArray>
#include <QString>
#include <QStringList>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/nodelane/nodelane.h"

using AutomationGestureCheck = std::function<void(bool, const QString &)>;

// Shared gesture fixture: the suite's middle node sits at this tick. Parity
// seeds its mid-fixture node there, crosslane selects/moves it, and hover parks
// the insertion cursor between the tick-0 and kNodeTick nodes at this tick.
constexpr uint64_t kFixtureTick = 96;

// DocSnapshot captures SMF bytes, revision, and undo index at one moment.
// Rig::Snapshot additionally carries lanePoints for lifecycle/transactions and
// therefore stays in rig.h; DocSnapshot is the plain three-field variant.
struct DocSnapshot {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;
};

inline DocSnapshot snapshot(SongDocument &document)
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

inline bool isOneEdit(const DocSnapshot &before, const DocSnapshot &after)
{
    return after.revision == before.revision + 1 && after.undoIndex == before.undoIndex + 1;
}

inline bool isUnchanged(const DocSnapshot &before, const DocSnapshot &after)
{
    return after.smf == before.smf && after.revision == before.revision &&
           after.undoIndex == before.undoIndex;
}

inline bool sameNodePoints(const std::vector<NodePoint> &left, const std::vector<NodePoint> &right)
{
    if (left.size() != right.size())
        return false;
    for (auto i = std::size_t{0}; i < left.size(); ++i) {
        if (left[i].tick != right[i].tick || left[i].value != right[i].value)
            return false;
    }
    return true;
}

inline bool sameRawPoints(const std::vector<DocLanePoint> &points,
                          const std::vector<SongDocument::LanePointValue> &expected)
{
    if (points.size() != expected.size())
        return false;
    for (auto i = std::size_t{0}; i < points.size(); ++i) {
        if (points[i].tick != expected[i].tick || points[i].value != expected[i].value)
            return false;
    }
    return true;
}

inline std::vector<int> rawValuesAt(const SongDocument &document, int track, uint8_t controller,
                                    uint64_t tick)
{
    std::vector<int> values;
    for (const auto &point : document.lanePoints(track, controller)) {
        if (point.tick == tick)
            values.push_back(point.value);
    }
    return values;
}

inline int tempoBpm(uint32_t microsecondsPerQuarterNote)
{
    return int(std::lround(CoreTimeDefaults::tempoBpm(microsecondsPerQuarterNote)));
}

inline uint32_t tempoUsForBpm(int bpm)
{
    return CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm);
}

inline QString formatPoints(const std::vector<NodePoint> &points)
{
    QStringList parts;
    for (const auto &point : points)
        parts.append(QStringLiteral("{%1,%2}").arg(point.tick).arg(point.value));
    return QStringLiteral("[%1]").arg(parts.join(QStringLiteral(", ")));
}

// Check wraps the callback with a domain label so a suite can report through
// one require() call instead of a per-file report() helper. require() prefixes
// the message with "domain: ".
struct Check {
    Check(const AutomationGestureCheck &fn, const QString &domain) : m_fn(fn), m_domain(domain) {}

    void require(bool condition, const QString &message) const
    {
        m_fn(condition, QStringLiteral("%1: %2").arg(m_domain, message));
    }

  private:
    AutomationGestureCheck m_fn;
    QString m_domain;
};