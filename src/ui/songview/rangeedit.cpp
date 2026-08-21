#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"

#include <QAction>
#include <QKeyEvent>
#include <QMenu>
#include <QPoint>

#include <algorithm>
#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

using namespace songview;
using namespace songview::detail;

namespace {
std::vector<TempoPoint> tempoInRange(const SongDocument &document, uint64_t startTick,
                                     uint64_t endTick)
{
    auto points = std::vector<TempoPoint>{};
    for (const auto &point : document.tempoPoints()) {
        if (point.tick >= startTick && point.tick < endTick)
            points.push_back(point);
    }
    return points;
}
} // namespace
void SongView::announceTimeSelection()
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!selection.active() || !m_timeline)
        return;
    const double beats = double(selection.endTick - selection.startTick) /
                         double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
    QString scope;
    if (selection.scope == EditorSelectionModel::TimeSelection::Lanes) {
        const QString lanes = tr("%n lane(s)", nullptr, int(selection.lanes.size()));
        scope = selection.tempo
                    ? (selection.lanes.empty() ? tr("tempo") : tr("%1 + tempo").arg(lanes))
                    : lanes;
    } else {
        const uint32_t mask = m_selectionModel.resolvedTrackScope(usedTrackMask(m_timeline));
        int n = 0;
        for (int track = 0; track < 16; ++track)
            n += (mask >> track) & 1;
        scope = tr("%n track(s)", nullptr, n);
    }
    emit statusMessage(tr("Time selection: %1 beats · %2 · Ctrl+C/X copies, "
                          "Del clears, Ctrl+V pastes at the edit cursor")
                           .arg(beats, 0, 'g', 4)
                           .arg(scope));
}
std::optional<SongView::TimeScopeResolution> SongView::resolveTimeSelectionScope() const
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !m_timeline || !selection.active())
        return std::nullopt;
    TimeScopeResolution resolved;
    if (selection.scope == EditorSelectionModel::TimeSelection::Lanes) {
        resolved.scope.tempo = selection.tempo;
        resolved.scope.lanes = selection.lanes;
        if (resolved.scope.lanes.empty() && !resolved.scope.tempo)
            return std::nullopt;
        const QString lanes = tr("%n lane(s)", nullptr, int(resolved.scope.lanes.size()));
        resolved.label =
            resolved.scope.tempo
                ? (resolved.scope.lanes.empty() ? tr("tempo") : tr("%1 + tempo").arg(lanes))
                : lanes;
        return resolved;
    }
    resolved.scope.tracks = timeSelectionTracks();
    if (resolved.scope.tracks.empty())
        return std::nullopt;
    const uint32_t usedMask = usedTrackMask(m_timeline);
    const uint32_t scope = m_selectionModel.resolvedTrackScope(usedMask);
    resolved.scope.wholeSong = usedMask != 0 && (scope & usedMask) == usedMask;
    resolved.label = resolved.scope.wholeSong
                         ? tr("all tracks")
                         : tr("%n track(s)", nullptr, int(resolved.scope.tracks.size()));
    return resolved;
}
std::vector<int> SongView::timeSelectionTracks() const
{
    std::vector<int> tracks;
    if (!m_timeline || !m_document)
        return tracks;
    const uint32_t mask = m_selectionModel.resolvedTrackScope(usedTrackMask(m_timeline));
    for (int track = 0; track < 16; ++track) {
        if (!m_timeline->tracks[track].used || !(mask & (1u << track)))
            continue;
        if (m_document->smfTrackFor(track) < 0)
            continue;
        tracks.push_back(track);
    }
    return tracks;
}
std::vector<uint8_t> SongView::trackCcs(int track) const
{
    std::vector<uint8_t> ccs;
    for (const CcLane &lane : m_model.lanes)
        if (lane.track == track)
            ccs.push_back(lane.cc); // LANE_CC_BEND == DOC_CC_BEND
    ccs.push_back(DOC_CC_VOICE);
    return ccs;
}
void SongView::copyTimeSelection()
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active())
        return;
    const uint64_t s = selection.startTick;
    const uint64_t e = selection.endTick;
    Clip clip;
    clip.span = e - s;
    int noteCount = 0;
    int pointCount = 0;
    const auto copyLanePoints = [&](int track, uint8_t cc) {
        if (track < 0)
            return;
        ClipLane lane{track, cc, {}};
        for (const DocLanePoint &pt : m_document->lanePoints(track, cc)) {
            if (pt.tick >= s && pt.tick < e)
                lane.points.push_back({uint32_t(pt.tick - s), pt.value});
        }
        pointCount += int(lane.points.size());
        // Empty segments are kept: they carry "this span is silent" so paste
        // clears the destination range.
        clip.lanes.push_back(std::move(lane));
    };
    if (m_selectionModel.timeSelectionCoversTempo(usedTrackMask(m_timeline))) {
        for (const auto &point : tempoInRange(*m_document, s, e))
            clip.tempo.push_back({point.tick - s, point.microsecondsPerQuarterNote});
        pointCount += int(clip.tempo.size());
    }
    if (selection.scope == EditorSelectionModel::TimeSelection::Lanes) {
        for (const std::pair<int, uint8_t> &id : selection.lanes)
            copyLanePoints(id.first, id.second);
    } else {
        for (int track : timeSelectionTracks()) {
            ClipTrack ct{track, {}};
            for (const DocNote &note : m_document->notesForTrack(track)) {
                if (note.tick < s || note.tick >= e)
                    continue;
                ct.notes.push_back(
                    {uint32_t(note.tick - s), note.key,
                     note.duration ? note.duration : uint32_t(gridTicksAt(note.tick)),
                     note.velocity});
            }
            noteCount += int(ct.notes.size());
            clip.tracks.push_back(std::move(ct));
            for (uint8_t cc : trackCcs(track))
                copyLanePoints(track, cc);
        }
    }
    m_clip = std::move(clip);
    announce(tr("Copied range: %1 note(s), %2 automation point(s)").arg(noteCount).arg(pointCount));
}
void SongView::deleteTimeSelection()
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active())
        return;
    const uint64_t s = selection.startTick;
    const uint64_t e = selection.endTick;
    SongDocument::RangeEdit edit;
    const auto removeLanePoints = [&](int track, uint8_t cc) {
        if (track < 0)
            return;
        for (const DocLanePoint &pt : m_document->lanePoints(track, cc)) {
            if (pt.tick >= s && pt.tick < e)
                edit.removePoints.push_back(pt);
        }
    };
    if (selection.scope == EditorSelectionModel::TimeSelection::Lanes) {
        for (const std::pair<int, uint8_t> &id : selection.lanes)
            removeLanePoints(id.first, id.second);
    } else {
        for (int track : timeSelectionTracks()) {
            for (const DocNote &note : m_document->notesForTrack(track)) {
                if (note.tick >= s && note.tick < e)
                    edit.removeNotes.push_back(note);
            }
            for (uint8_t cc : trackCcs(track))
                removeLanePoints(track, cc);
        }
    }
    if (m_selectionModel.timeSelectionCoversTempo(usedTrackMask(m_timeline)))
        edit.removeTempo = tempoInRange(*m_document, s, e);
    if (edit.empty()) {
        announce(tr("Nothing to delete in the time selection"));
        return;
    }
    const int notes = int(edit.removeNotes.size());
    const int points = int(edit.removePoints.size() + edit.removeTempo.size());
    announce(tr("Deleted range: %1 note(s), %2 automation point(s)").arg(notes).arg(points));
}
void SongView::transposeTimeSelection(int dKey)
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active() || dKey == 0 ||
        selection.scope == EditorSelectionModel::TimeSelection::Lanes)
        return;
    const uint64_t s = selection.startTick;
    const uint64_t e = selection.endTick;
    std::vector<DocNote> notes;
    for (int t : timeSelectionTracks()) {
        for (const DocNote &note : m_document->notesForTrack(t)) {
            if (note.tick >= s && note.tick < e)
                notes.push_back(note);
        }
    }
    if (notes.empty()) {
        announce(tr("No notes in the time selection"));
        return;
    }
    for (const DocNote &note : notes) {
        const int key = int(note.key) + dKey;
        if (key < 0 || key > 127) {
            announce(tr("Transpose out of range"));
            return;
        }
    }
    m_document->moveNotes(notes, 0, dKey, /*mergeable=*/true);
    // Keep the moved notes in sight: the row the move headed toward
    // scrolls into view just enough (no re-centering).
    int edge = int(notes.front().key) + dKey;
    for (const DocNote &note : notes) {
        const int key = int(note.key) + dKey;
        edge = dKey > 0 ? std::max(edge, key) : std::min(edge, key);
    }
    ensureKeyVisible(edge);
    announce(tr("Transposed %n note(s) by %1", nullptr, int(notes.size()))
                 .arg(dKey > 0 ? QStringLiteral("+%1").arg(dKey) : QString::number(dKey)));
}
void SongView::foldTransposeSelection(int degreeDelta)
{
    if (!m_document || degreeDelta == 0)
        return;
    const auto &noteSelection = m_selectionModel.noteSelection();
    std::vector<DocNote> notes;
    for (const DocNote &note : m_document->notesForTrack(m_selectionModel.primaryTrack())) {
        const NoteId id = note.noteId;
        if (std::find(noteSelection.begin(), noteSelection.end(), id) != noteSelection.end())
            notes.push_back(note);
    }
    std::vector<uint8_t> destinations;
    if (!resolveFoldDestinations(m_scaleId, m_scaleRoot, notes, degreeDelta, destinations) ||
        !m_document->moveNotesToPitches(notes, destinations, 0, /*mergeable=*/true)) {
        return;
    }
    std::vector<NoteId> ids;
    ids.reserve(notes.size());
    for (const DocNote &note : notes)
        ids.push_back(note.noteId);
    m_selectionModel.setNoteSelection(std::move(ids));
    int edge = destinations.front();
    for (uint8_t destination : destinations)
        edge =
            degreeDelta > 0 ? std::max(edge, int(destination)) : std::min(edge, int(destination));
    ensureKeyVisible(edge);
}
void SongView::nudgeTimeSelection(bool right)
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active())
        return;
    const uint64_t s = selection.startTick;
    const uint64_t e = selection.endTick;
    const uint64_t snapped = right ? snapTickUp(double(s) + 1.0) : snapTickDown(double(s) - 1.0);
    const int64_t dTick = int64_t(snapped) - int64_t(s);
    if (dTick == 0)
        return;
    std::vector<DocNote> notes;
    std::vector<DocLanePoint> points;
    std::vector<TempoPoint> tempo;
    const auto gatherLanePoints = [&](int track, uint8_t cc) {
        if (track < 0)
            return;
        for (const DocLanePoint &pt : m_document->lanePoints(track, cc)) {
            if (pt.tick >= s && pt.tick < e)
                points.push_back(pt);
        }
    };
    if (selection.scope == EditorSelectionModel::TimeSelection::Lanes) {
        for (const std::pair<int, uint8_t> &id : selection.lanes)
            gatherLanePoints(id.first, id.second);
    } else {
        for (int track : timeSelectionTracks()) {
            for (const DocNote &note : m_document->notesForTrack(track)) {
                if (note.tick >= s && note.tick < e)
                    notes.push_back(note);
            }
            for (uint8_t cc : trackCcs(track))
                gatherLanePoints(track, cc);
        }
    }
    if (m_selectionModel.timeSelectionCoversTempo(usedTrackMask(m_timeline)))
        tempo = tempoInRange(*m_document, s, e);
    m_document->moveRange(notes, points, dTick, tempo);
    // The band follows even over empty content, so repeated nudges keep
    // aiming at the same region.
    EditorSelectionModel::TimeSelection moved = selection;
    moved.startTick = uint64_t(int64_t(s) + dTick);
    moved.endTick = uint64_t(int64_t(e) + dTick);
    m_selectionModel.setTimeSelection(moved);
    ensureRangeVisible(moved.startTick, moved.endTick, right);
}
void SongView::removeTimeSelectionContents()
{
    const auto resolved = resolveTimeSelectionScope();
    if (!resolved)
        return;
    const auto &selection = m_selectionModel.timeSelection();
    const SongDocument::TimeRange range{selection.startTick, selection.endTick};
    if (!m_document->removeTimeRange(range, resolved->scope)) {
        announce(tr("Nothing to remove in the time selection"));
        return;
    }
    // The span is gone and later content now sits under where the selection
    // was; clear it and park the edit cursor at the seam.
    m_selectionModel.clearTimeSelection();
    commitEditCursor(range.startTick);
    const double beats =
        double(range.span()) / double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
    announce(tr("Removed %1 beats on %2 — later events shifted left")
                 .arg(beats, 0, 'g', 4)
                 .arg(resolved->label));
}
void SongView::insertBlankTime()
{
    const auto resolved = resolveTimeSelectionScope();
    if (!resolved)
        return;
    const EditorSelectionModel::TimeSelection selection = m_selectionModel.timeSelection();
    const SongDocument::TimeRange range{selection.startTick, selection.endTick};
    if (!m_document->insertBlankTime(range, resolved->scope)) {
        announce(tr("Nothing to insert in the time selection"));
        return;
    }
    m_selectionModel.setTimeSelection(selection);
    commitEditCursor(range.startTick);
    const double beats =
        double(range.span()) / double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
    announce(
        tr("Inserted %1 beats of blank time on %2").arg(beats, 0, 'g', 4).arg(resolved->label));
}
void SongView::duplicateTimeSelection()
{
    const auto resolved = resolveTimeSelectionScope();
    if (!resolved)
        return;
    const auto &selection = m_selectionModel.timeSelection();
    const SongDocument::TimeRange range{selection.startTick, selection.endTick};
    if (!m_document->duplicateTimeRange(range, resolved->scope)) {
        announce(tr("Nothing to duplicate in the time selection"));
        return;
    }
    const uint64_t destinationEnd = range.endTick + range.span();
    EditorSelectionModel::TimeSelection moved = selection;
    moved.startTick = range.endTick;
    moved.endTick = destinationEnd;
    m_selectionModel.setTimeSelection(moved);
    commitEditCursor(destinationEnd);
    ensureRangeVisible(moved.startTick, moved.endTick, true);
    const double beats =
        double(range.span()) / double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
    announce(tr("Duplicated %1 beats on %2").arg(beats, 0, 'g', 4).arg(resolved->label));
}
void SongView::pasteRangeAtEditCursor()
{
    if (!m_document || m_clip.span == 0 || m_clip.empty())
        return;
    const uint64_t s = snapTick(double(m_editCursorTick));
    const uint64_t e = s + m_clip.span;

    // A clip whose content came from one track retargets to the selected
    // track (cross-track copy); multi-track clips paste back in place.
    int sole = -2;
    bool multi = false;
    const auto consider = [&](int track) {
        if (sole == -2)
            sole = track;
        else if (sole != track)
            multi = true;
    };
    for (const ClipTrack &ct : m_clip.tracks)
        consider(ct.track);
    for (const ClipLane &cl : m_clip.lanes)
        consider(cl.track);
    const auto mapTrack = [&](int track) {
        return multi ? track : m_selectionModel.primaryTrack();
    };

    SongDocument::RangeEdit edit;
    for (const ClipTrack &ct : m_clip.tracks) {
        const int t = mapTrack(ct.track);
        if (t < 0 || m_document->smfTrackFor(t) < 0)
            continue;
        // Replace: whatever notes start inside the destination span go away.
        for (const DocNote &note : m_document->notesForTrack(t)) {
            if (note.tick >= s && note.tick < e)
                edit.removeNotes.push_back(note);
        }
        if (!ct.notes.empty()) {
            SongDocument::RangeEdit::TrackNotes tn{t, {}};
            for (const ClipNote &cn : ct.notes)
                tn.notes.push_back({s + cn.relTick, cn.key, cn.duration, cn.velocity});
            edit.addNotes.push_back(std::move(tn));
        }
    }
    for (const ClipLane &cl : m_clip.lanes) {
        if (cl.track < 0)
            continue;
        const int t = mapTrack(cl.track);
        if (m_document->smfTrackFor(t) < 0)
            continue;
        for (const DocLanePoint &pt : m_document->lanePoints(t, cl.cc)) {
            if (pt.tick >= s && pt.tick < e)
                edit.removePoints.push_back(pt);
        }
        if (!cl.points.empty()) {
            SongDocument::RangeEdit::LaneWrite lw{t, cl.cc, {}};
            for (const std::pair<uint32_t, int> &pv : cl.points)
                lw.points.push_back({s + pv.first, pv.second});
            edit.addPoints.push_back(std::move(lw));
        }
    }
    const auto &selection = m_selectionModel.timeSelection();
    const bool tempoOnly = m_clip.tracks.empty() && m_clip.lanes.empty();
    const bool pasteTempo = !m_clip.tempo.empty() &&
                            (tempoOnly || !selection.active() ||
                             m_selectionModel.timeSelectionCoversTempo(usedTrackMask(m_timeline)));
    if (pasteTempo) {
        edit.removeTempo = tempoInRange(*m_document, s, e);
        for (const auto &point : m_clip.tempo)
            edit.addTempo.push_back({s + point.tick, point.microsecondsPerQuarterNote});
    }
    m_document->applyRangeEdit(tr("paste range"), edit);

    // Set up for tiling: the edit cursor advances to the end of the pasted
    // span so repeated Ctrl+V lays copies back-to-back, and the selection is
    // cleared so its band doesn't sit in the way of the next ruler click.
    m_selectionModel.clearTimeSelection();
    commitEditCursor(e);
    // Anchor on the start of the pasted span, not the advanced cursor:
    // seeing the content that just landed is what confirms the paste.
    ensureTickVisible(s);
    announce(tr("Pasted range · edit cursor moved to its end — paste again to repeat"));
}
// Maps the four transpose commands to their semitone step, 0 when the event
// matches none. Shared by the note-selection and time-selection key paths so
// a rebinding changes both at once.
int SongView::transposeStepFor(const QKeyEvent *event) const
{
    const auto &keys = keymap::Registry::instance();
    if (keys.matches(event, QStringLiteral("roll.transpose_up")))
        return 1;
    if (keys.matches(event, QStringLiteral("roll.transpose_down")))
        return -1;
    if (keys.matches(event, QStringLiteral("roll.transpose_up_octave")))
        return 12;
    if (keys.matches(event, QStringLiteral("roll.transpose_down_octave")))
        return -12;
    return 0;
}
bool SongView::handleEditKey(QKeyEvent *event)
{
    if (!m_document)
        return false;
    const auto &keys = keymap::Registry::instance();
    const bool sel = m_selectionModel.timeSelection().active();
    if (sel && keys.matches(event, QStringLiteral("roll.copy"))) {
        copyTimeSelection();
        event->accept();
        return true;
    }
    if (sel && keys.matches(event, QStringLiteral("roll.cut"))) {
        copyTimeSelection();
        deleteTimeSelection();
        event->accept();
        return true;
    }
    if (sel && keys.matches(event, QStringLiteral("roll.duplicate_time"))) {
        duplicateTimeSelection();
        event->accept();
        return true;
    }
    if (sel && keys.matches(event, QStringLiteral("roll.delete"))) {
        deleteTimeSelection();
        event->accept();
        return true;
    }
    if (sel) {
        const int transpose = transposeStepFor(event);
        if (transpose != 0) {
            transposeTimeSelection(transpose);
            event->accept();
            return true;
        }
    }
    if (sel && (keys.matches(event, QStringLiteral("roll.nudge_left")) ||
                keys.matches(event, QStringLiteral("roll.nudge_right")))) {
        nudgeTimeSelection(keys.matches(event, QStringLiteral("roll.nudge_right")));
        event->accept();
        return true;
    }
    if (keys.matches(event, QStringLiteral("roll.paste")) && m_clip.span > 0 && !m_clip.empty()) {
        pasteRangeAtEditCursor();
        event->accept();
        return true;
    }
    if (keys.matches(event, QStringLiteral("roll.mute_tracks"))) {
        toggleMuteOnSelectedTracks();
        event->accept();
        return true;
    }
    if (keys.matches(event, QStringLiteral("roll.solo_tracks"))) {
        toggleSoloOnSelectedTracks();
        event->accept();
        return true;
    }
    return false;
}
void SongView::showTimeSelectionMenu(const QPoint &globalPos)
{
    if (!m_document || !m_selectionModel.timeSelection().active())
        return;
    QMenu menu(this);
    // Display-only hints mirroring the keymap, like the note context menu.
    const auto &keys = keymap::Registry::instance();
    QAction *copy = menu.addAction(tr("Copy range"));
    copy->setShortcut(keys.bindings(QStringLiteral("roll.copy")).value(0));
    QAction *cut = menu.addAction(tr("Cut range"));
    cut->setShortcut(keys.bindings(QStringLiteral("roll.cut")).value(0));
    QAction *del = menu.addAction(tr("Delete range"));
    QAction *insertBlank = menu.addAction(tr("Insert blank time"));
    QAction *duplicate = menu.addAction(tr("Duplicate time"));
    duplicate->setShortcut(keys.bindings(QStringLiteral("roll.duplicate_time")).value(0));
    QAction *removeContents = menu.addAction(tr("Remove contents (shift left)"));
    QAction *paste = menu.addAction(tr("Paste at edit cursor"));
    paste->setShortcut(keys.bindings(QStringLiteral("roll.paste")).value(0));
    paste->setEnabled(m_clip.span > 0 && !m_clip.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(tr("Clear time selection"));
    QAction *chosen = menu.exec(globalPos);
    if (chosen == copy) {
        copyTimeSelection();
    } else if (chosen == cut) {
        copyTimeSelection();
        deleteTimeSelection();
    } else if (chosen == del) {
        deleteTimeSelection();
    } else if (chosen == insertBlank) {
        insertBlankTime();
    } else if (chosen == duplicate) {
        duplicateTimeSelection();
    } else if (chosen == removeContents) {
        removeTimeSelectionContents();
    } else if (chosen == paste) {
        pasteRangeAtEditCursor();
    } else if (chosen == clear) {
        m_selectionModel.clearTimeSelection();
    }
}
void SongView::announceNote(const ViewNote &note)
{
    if (!m_timeline)
        return;
    const bool ext = m_document && m_document->cfg().extendedClocks;
    const bool exact = m_document && m_document->cfg().exactGate;
    const int64_t ticks = int64_t(note.endTick) - int64_t(note.startTick);
    emit statusMessage(
        tr("%1 · velocity %2 → plays %3 · length %4 ticks → %5 clocks")
            .arg(keyName(note.key))
            .arg(note.velocity)
            .arg(mid2agbEffectiveVelocity(note.velocity))
            .arg(ticks)
            .arg(mid2agbEffectiveDuration(ticks, m_timeline->ticksPerBeat, ext, exact)));
}
