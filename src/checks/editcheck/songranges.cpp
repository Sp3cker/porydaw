#include <vector>

#include "checks/editcheck/support.h"

namespace editcheck {
bool checkSongRangeEdits(SongEditScenario &scenario)
{
    SongDocument &doc = scenario.doc;
    const int track = scenario.track;
    const uint64_t base = scenario.base;
    const uint32_t step = scenario.step;
    bool ok = true;
    const auto fail = [&scenario](const char *what) { scenario.fail(what); };
    const auto mutateAndCheck = [&scenario, &ok](const char *what) {
        if (ok && !scenario.checkSorted(what))
            ok = false;
    };

    // Range edit: a multi-track/multi-lane batch of removals and
    // insertions must land as ONE undoable command.
    if (ok) {
        doc.addNotes(track,
                     {{base + step * 30, 60, step * 2, 90}, {base + step * 32, 62, step * 2, 90}});
        doc.addLanePoint(track, 7, base + step * 30, 80);
        doc.applyTempoEdit({{}, {tempoPoint(base + step * 31, 140)}});
        SongDocument::RangeEdit edit;
        for (const DocNote &n : doc.notesForTrack(track)) {
            if (n.tick >= base + step * 30 && n.tick < base + step * 34)
                edit.removeNotes.push_back(n);
        }
        for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
            if (p.tick == base + step * 30)
                edit.removePoints.push_back(p);
        }
        for (const TempoPoint &point : doc.tempoPoints()) {
            if (point.tick == base + step * 31)
                edit.removeTempo.push_back(point);
        }
        edit.addNotes.push_back({track, {{base + step * 40, 65, step * 2, 90}}});
        edit.addPoints.push_back({track, 7, {{base + step * 40, 70}}});
        edit.addTempo.push_back(tempoPoint(base + step * 41, 155));
        doc.applyRangeEdit(QStringLiteral("range edit"), edit);
        mutateAndCheck("events unsorted after applyRangeEdit");
        DocNote n;
        DocLanePoint p;
        if (doc.findNote(track, base + step * 30, 60, &n) ||
            doc.findNote(track, base + step * 32, 62, &n) ||
            !doc.findNote(track, base + step * 40, 65, &n) ||
            !doc.findLanePoint(track, 7, base + step * 40, &p) || p.value != 70 ||
            !containsTempoPoint(doc, tempoPoint(base + step * 41, 155))) {
            fail("range edit produced wrong content");
            ok = false;
        } else {
            doc.undoStack()->undo();
            if (!doc.findNote(track, base + step * 30, 60, &n) ||
                doc.findNote(track, base + step * 40, 65, &n)) {
                fail("applyRangeEdit was not a single undo command");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
    }

    // Range move (time-selection nudge): notes plus CC and tempo
    // points shift together by a tick delta as ONE undoable command,
    // with values intact (events move as raw bytes).
    if (ok) {
        doc.addNotes(track,
                     {{base + step * 80, 60, step * 2, 90}, {base + step * 82, 64, step * 2, 90}});
        doc.addLanePoint(track, 7, base + step * 80, 45);
        doc.applyTempoEdit({{}, {tempoPoint(base + step * 81, 140)}});
        std::vector<DocNote> moveNotes;
        for (const DocNote &n : doc.notesForTrack(track)) {
            if (n.tick >= base + step * 80 && n.tick < base + step * 84)
                moveNotes.push_back(n);
        }
        std::vector<DocLanePoint> movePoints;
        for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
            if (p.tick == base + step * 80)
                movePoints.push_back(p);
        }
        std::vector<TempoPoint> moveTempo;
        for (const TempoPoint &point : doc.tempoPoints()) {
            if (point.tick == base + step * 81)
                moveTempo.push_back(point);
        }
        doc.moveRange(moveNotes, movePoints, step * 3, moveTempo);
        mutateAndCheck("events unsorted after moveRange");
        DocNote n;
        DocLanePoint p;
        if (doc.findNote(track, base + step * 80, 60, &n) ||
            !doc.findNote(track, base + step * 83, 60, &n) || n.duration != step * 2 ||
            !doc.findNote(track, base + step * 85, 64, &n) ||
            !doc.findLanePoint(track, 7, base + step * 83, &p) || p.value != 45 ||
            !containsTempoPoint(doc, tempoPoint(base + step * 84, 140))) {
            fail("range move produced wrong content");
            ok = false;
        }
        if (ok) {
            doc.moveRange(moveNotes, movePoints, 0, moveTempo); // no-op guard
            doc.undoStack()->undo();
            if (!doc.findNote(track, base + step * 80, 60, &n) ||
                doc.findNote(track, base + step * 83, 60, &n) ||
                !doc.findLanePoint(track, 7, base + step * 80, &p) ||
                !containsTempoPoint(doc, tempoPoint(base + step * 81, 140))) {
                fail("moveRange was not a single undo command");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
    }

    // Bulk lane-point move: several automation points shift by
    // independent tick/value deltas as ONE undoable command.
    if (ok) {
        doc.addLanePoint(track, 7, base + step * 90, 20);
        doc.addLanePoint(track, 7, base + step * 91, 40);
        doc.addLanePoint(track, 7, base + step * 92, 60);
        std::vector<SongDocument::LanePointMove> moves;
        for (const DocLanePoint &p : doc.lanePoints(track, 7)) {
            if (p.tick == base + step * 90)
                moves.push_back({track, 7, p, base + step * 93, 25});
            else if (p.tick == base + step * 91)
                moves.push_back({track, 7, p, base + step * 94, 45});
        }
        const int undoBefore = doc.undoStack()->count();
        doc.moveLanePoints(moves);
        mutateAndCheck("events unsorted after moveLanePoints");
        DocLanePoint p;
        if (doc.findLanePoint(track, 7, base + step * 90, &p) ||
            doc.findLanePoint(track, 7, base + step * 91, &p) ||
            !doc.findLanePoint(track, 7, base + step * 93, &p) || p.value != 25 ||
            !doc.findLanePoint(track, 7, base + step * 94, &p) || p.value != 45 ||
            !doc.findLanePoint(track, 7, base + step * 92, &p) || p.value != 60 ||
            doc.undoStack()->count() != undoBefore + 1) {
            fail("moveLanePoints produced wrong content or undo count");
            ok = false;
        } else {
            doc.undoStack()->undo();
            if (!doc.findLanePoint(track, 7, base + step * 90, &p) || p.value != 20 ||
                !doc.findLanePoint(track, 7, base + step * 91, &p) || p.value != 40 ||
                doc.findLanePoint(track, 7, base + step * 93, &p)) {
                fail("moveLanePoints was not a single undo command");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
            if (ok) {
                doc.addLanePoint(track, 7, base + step * 95, 70);
                doc.addLanePoint(track, 7, base + step * 96, 80);
                DocLanePoint first, second;
                if (!doc.findLanePoint(track, 7, base + step * 95, &first) ||
                    !doc.findLanePoint(track, 7, base + step * 96, &second)) {
                    fail("converging move fixture was not created");
                    ok = false;
                } else {
                    const uint64_t destination = base + step * 97;
                    const int convergeUndoBefore = doc.undoStack()->count();
                    doc.moveLanePoints(
                        {{track, 7, first, destination, 71}, {track, 7, second, destination, 72}});
                    mutateAndCheck("events unsorted after converging moveLanePoints");
                    int destinationCount = 0;
                    int destinationValue = -1;
                    for (const DocLanePoint &point : doc.lanePoints(track, 7)) {
                        if (point.tick == destination) {
                            destinationCount++;
                            destinationValue = point.value;
                        }
                    }
                    if (doc.findLanePoint(track, 7, base + step * 95, &p) ||
                        doc.findLanePoint(track, 7, base + step * 96, &p) ||
                        destinationCount != 1 || destinationValue != 72 ||
                        doc.undoStack()->count() != convergeUndoBefore + 1) {
                        fail("converging move was not last-input-wins");
                        ok = false;
                    } else {
                        doc.undoStack()->undo();
                        if (!doc.findLanePoint(track, 7, base + step * 95, &p) || p.value != 70 ||
                            !doc.findLanePoint(track, 7, base + step * 96, &p) || p.value != 80 ||
                            doc.findLanePoint(track, 7, destination, &p)) {
                            fail("converging move undo did not restore both points");
                            ok = false;
                        } else {
                            doc.undoStack()->redo();
                        }
                    }
                }
            }
        }
    }

    return ok;
}

} // namespace editcheck
