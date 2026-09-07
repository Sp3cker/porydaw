#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/quickmodalhost.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include <QAction>
#include <QMenu>
#include <QPoint>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>
#include <span>
#include <utility>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

using namespace songview;
using namespace songview::detail;

namespace {

// The engine track a clip's content all came from, nullopt when the clip is
// empty or mixes tracks (multi-track clips paste back in place).
std::optional<int> singleSourceTrack(const Clip &clip)
{
    std::optional<int> source;
    for (const auto &track : clip.tracks) {
        if (source && *source != track.track)
            return std::nullopt;
        source = track.track;
    }
    for (const auto &lane : clip.lanes) {
        if (source && *source != lane.track)
            return std::nullopt;
        source = lane.track;
    }
    return source;
}

// Destination points whose exact tick a paste would overwrite. Added sets
// are tiny (one clip lane/tempo row), so a linear scan beats hashing.
void appendExactTickRemovals(std::span<const DocLanePoint> destination,
                             std::span<const SongDocument::LanePointValue> added,
                             std::vector<DocLanePoint> &removed)
{
    for (const DocLanePoint &point : destination) {
        if (std::any_of(added.begin(), added.end(),
                        [&](const SongDocument::LanePointValue &addedPoint) {
                            return addedPoint.tick == point.tick;
                        }))
            removed.push_back(point);
    }
}

void appendExactTickRemovals(std::span<const TempoPoint> destination,
                             std::span<const TempoPoint> added, std::vector<TempoPoint> &removed)
{
    for (const TempoPoint &point : destination) {
        if (std::any_of(added.begin(), added.end(), [&](const TempoPoint &addedPoint) {
                return addedPoint.tick == point.tick;
            }))
            removed.push_back(point);
    }
}

bool inRange(uint64_t tick, const SongDocument::TimeRange &range)
{
    return tick >= range.startTick && tick < range.endTick;
}

// Contents of a half-open time range gathered from the document over a
// resolved TimeScope — the scan shared by the time-selection copy, delete,
// and nudge commands, so every path collects exactly the same notes, lane
// points, and tempo. Notes are grouped per engine track and lane points per
// (track, cc), both in scope order; groups stay in the result even when
// empty, so callers that preserve the copied shape (Clip tracks/lanes) keep
// their empty segments. Points carry absolute document ticks.
struct TimeRangeContents {
    struct TrackNotes {
        int track = -1;
        std::vector<DocNote> notes;
    };
    struct TrackLane {
        int track = -1;
        uint8_t cc = 0;
        std::vector<DocLanePoint> points;
    };
    std::vector<TrackNotes> tracks;
    std::vector<TrackLane> lanes;
    std::vector<TempoPoint> tempo;
};

// Gathers every note of each scoped track (scope.tracks, in order), every
// lane point of each scoped lane identity (scope.lanes, in order; negative
// tracks skipped) with tick in [startTick, endTick), and — when
// scope.coversTempo() — the in-range tempo points.
TimeRangeContents gatherRange(const SongDocument &document, SongDocument::TimeRange range,
                              const SongDocument::TimeScope &scope)
{
    TimeRangeContents contents;
    for (const int track : scope.tracks) {
        TimeRangeContents::TrackNotes trackNotes;
        trackNotes.track = track;
        for (const DocNote &note : document.notesForTrack(track)) {
            if (inRange(note.tick, range))
                trackNotes.notes.push_back(note);
        }
        contents.tracks.push_back(std::move(trackNotes));
    }
    for (const std::pair<int, uint8_t> &lane : scope.lanes) {
        if (lane.first < 0)
            continue;
        TimeRangeContents::TrackLane trackLane;
        trackLane.track = lane.first;
        trackLane.cc = lane.second;
        for (const DocLanePoint &point : document.lanePoints(lane.first, lane.second)) {
            if (inRange(point.tick, range))
                trackLane.points.push_back(point);
        }
        contents.lanes.push_back(std::move(trackLane));
    }
    if (scope.coversTempo()) {
        for (const TempoPoint &point : document.tempoPoints()) {
            if (inRange(point.tick, range))
                contents.tempo.push_back(point);
        }
    }
    return contents;
}

// Maps a clip's source engine track to the paste destination. A single-source
// clip retargets to the selected existing track (cross-track copy);
// multi-track clips keep any engine index in the 0-15 destination range,
// including tracks the paste command must create.
class DestinationMapper
{
  public:
    DestinationMapper(SongDocument &document, const EditorSelectionModel &selection,
                      std::optional<int> singleSource)
        : m_document(document)
        , m_selection(selection)
        , m_singleSource(singleSource)
    {}

    std::optional<int> map(int sourceTrack) const
    {
        const int destination = m_singleSource ? m_selection.primaryTrack() : sourceTrack;
        if (destination < 0 || destination >= 16)
            return std::nullopt;
        if (m_singleSource && m_document.smfTrackFor(destination) < 0)
            return std::nullopt;
        return destination;
    }

  private:
    const SongDocument &m_document;
    const EditorSelectionModel &m_selection;
    std::optional<int> m_singleSource;
};

} // namespace

int SongView::insertTimePromptInitialBars() const noexcept
{
    return m_pendingInsertTimePrompt ? m_pendingInsertTimePrompt->initialBars
                                     : insertTimePromptMinimumBars();
}

int SongView::insertTimePromptInitialBeats() const noexcept
{
    return m_pendingInsertTimePrompt ? m_pendingInsertTimePrompt->initialBeats
                                     : insertTimePromptMinimumBeats();
}

int SongView::insertTimePromptInitialBeatFractions() const noexcept
{
    return m_pendingInsertTimePrompt ? m_pendingInsertTimePrompt->initialBeatFractions
                                     : insertTimePromptMinimumBeatFractions();
}

int SongView::insertTimePromptMaximumBeats() const noexcept
{
    if (!m_pendingInsertTimePrompt || m_pendingInsertTimePrompt->beatsPerBar == 0)
        return insertTimePromptMinimumBeats();
    const uint64_t maximumBeats = m_pendingInsertTimePrompt->beatsPerBar - 1;
    return maximumBeats > uint64_t((std::numeric_limits<int>::max)())
               ? (std::numeric_limits<int>::max)()
               : int(maximumBeats);
}

QString SongView::insertTimePromptTitle() const
{
    return tr("Insert Time");
}

QVariantMap SongView::insertTimePromptAppearance() const
{
    QVariantMap appearance;
    appearance.insert(QStringLiteral("font"), font());
    appearance.insert(QStringLiteral("background"), themes::color(themes::Role::window_background));
    appearance.insert(QStringLiteral("outline"), themes::color(themes::Role::palette_outline));
    appearance.insert(QStringLiteral("text"), themes::color(themes::Role::window_text));
    appearance.insert(QStringLiteral("focus"), themes::color(themes::Role::focus_outline));
    appearance.insert(QStringLiteral("buttonBackground"),
                      themes::color(themes::Role::button_background));
    appearance.insert(QStringLiteral("buttonText"), themes::color(themes::Role::button_text));
    appearance.insert(QStringLiteral("pressedBackground"),
                      themes::color(themes::Role::button_pressed_background));
    appearance.insert(QStringLiteral("borderWidth"), lyt::singlePixel());
    appearance.insert(QStringLiteral("radius"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("dialogPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("horizontalPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("verticalPadding"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("buttonPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("spacing"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("dragThreshold"), lyt::fontPxF(1.0));
    return appearance;
}

void SongView::openInsertTimePrompt(uint64_t cursorTick, const songview::Grid::Segment &segment)
{
    songview::TimelineQuickView *const quick = quickView();
    songview::QuickModalHost *const host = quick ? quick->modalHost() : nullptr;
    if (!m_document || !host)
        return;

    // End a previous Insert Time session before publishing this target. A
    // different owner's active modal is replaced by the shared host instead.
    if (m_pendingInsertTimePrompt)
        cancelInsertTimePromptWithoutFocus();
    else
        host->cancel();

    PendingInsertTimePrompt pending;
    pending.document = m_document;
    pending.documentRevision = m_document->revision();
    pending.cursorTick = cursorTick;
    pending.beatTicks = segment.beatTicks;
    pending.beatsPerBar = segment.beatsPerBar;
    pending.initialBars = 1;
    pending.initialBeats = 0;
    pending.initialBeatFractions = 0;
    m_pendingInsertTimePrompt = pending;
    emit insertTimePromptChanged();

    QObject::disconnect(m_insertTimePromptCancellation);
    m_insertTimePromptCancellation =
        connect(host, &songview::QuickModalHost::cancelled, this,
                [this] { clearInsertTimePrompt(/*restoreFocus=*/true); });
    if (!host->open(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/InsertTimePrompt.qml")), this,
                    insertTimePromptTitle())) {
        clearInsertTimePrompt(/*restoreFocus=*/true);
    }
}

void SongView::acceptInsertTimePrompt(int bars, int beats, int fractions)
{
    if (bars < insertTimePromptMinimumBars() || bars > insertTimePromptMaximumBars() ||
        beats < insertTimePromptMinimumBeats() || beats > insertTimePromptMaximumBeats() ||
        fractions < insertTimePromptMinimumBeatFractions() ||
        fractions > insertTimePromptMaximumBeatFractions() || !m_pendingInsertTimePrompt) {
        return;
    }

    const PendingInsertTimePrompt pending = std::move(*m_pendingInsertTimePrompt);
    m_pendingInsertTimePrompt.reset(); // Never expose a pending target while mutating its document.
    QObject::disconnect(m_insertTimePromptCancellation);
    m_insertTimePromptCancellation = {};
    emit insertTimePromptChanged();
    if (songview::TimelineQuickView *const quick = quickView())
        quick->modalHost()->close();

    SongDocument *const document = m_document;
    if (document == pending.document.data() && document->revision() == pending.documentRevision) {
        const uint64_t maximum = (std::numeric_limits<uint64_t>::max)();
        bool overflow =
            pending.beatsPerBar != 0 && pending.beatTicks > maximum / pending.beatsPerBar;
        const uint64_t measureTicks = overflow ? 0 : pending.beatTicks * pending.beatsPerBar;

        const uint64_t barCount = uint64_t(bars);
        const uint64_t beatCount = uint64_t(beats);
        const uint64_t fractionCount = uint64_t(fractions);
        overflow = overflow || (barCount != 0 && measureTicks > maximum / barCount);
        const uint64_t barTicks = overflow ? 0 : barCount * measureTicks;
        overflow = overflow || (beatCount != 0 && pending.beatTicks > maximum / beatCount);
        const uint64_t beatTicks = overflow ? 0 : beatCount * pending.beatTicks;
        const uint64_t fractionTicks = fractionCount * (pending.beatTicks / 4) +
                                       (fractionCount * (pending.beatTicks % 4) + 3) / 4;

        overflow = overflow || barTicks > maximum - beatTicks;
        const uint64_t wholeTicks = overflow ? 0 : barTicks + beatTicks;
        overflow = overflow || wholeTicks > maximum - fractionTicks;
        const uint64_t span = overflow ? 0 : wholeTicks + fractionTicks;

        if (overflow || span > maximum - pending.cursorTick) {
            announce(tr("Cannot insert time at the cursor"));
        } else {
            SongDocument::TimeScope scope;
            scope.wholeSong = true;
            if (!document->insertBlankTime({pending.cursorTick, pending.cursorTick + span}, scope))
                announce(tr("Nothing to insert at the cursor"));
            else
                announce(tr("Inserted time at the cursor"));
        }
    }
    focusActiveSurface();
}

void SongView::cancelInsertTimePrompt()
{
    if (!m_pendingInsertTimePrompt)
        return;
    if (songview::TimelineQuickView *const quick = quickView())
        quick->modalHost()->cancel();
    if (m_pendingInsertTimePrompt)
        clearInsertTimePrompt(/*restoreFocus=*/true);
}

void SongView::cancelInsertTimePromptWithoutFocus()
{
    const bool ownsModal = m_pendingInsertTimePrompt.has_value();
    m_pendingInsertTimePrompt.reset();
    // Disconnect before host cancellation so strong lifecycle cleanup never
    // restores focus through the cancelled() callback.
    QObject::disconnect(m_insertTimePromptCancellation);
    m_insertTimePromptCancellation = {};
    if (ownsModal) {
        emit insertTimePromptChanged();
        if (songview::TimelineQuickView *const quick = quickView())
            quick->modalHost()->cancel();
    }
}

void SongView::clearInsertTimePrompt(bool restoreFocus)
{
    const bool hadPending = m_pendingInsertTimePrompt.has_value();
    m_pendingInsertTimePrompt.reset();
    QObject::disconnect(m_insertTimePromptCancellation);
    m_insertTimePromptCancellation = {};
    if (hadPending)
        emit insertTimePromptChanged();
    if (hadPending && restoreFocus)
        focusActiveSurface();
}

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
    const auto scope = timeSelectionScope();
    if (!scope)
        return std::nullopt;
    TimeScopeResolution resolved;
    resolved.scope = *scope;
    if (scope->wholeSong)
        resolved.label = tr("all tracks");
    else if (!scope->tracks.empty())
        resolved.label = tr("%n track(s)", nullptr, int(scope->tracks.size()));
    else if (scope->tempo && scope->lanes.empty())
        resolved.label = tr("tempo");
    else {
        const QString lanes = tr("%n lane(s)", nullptr, int(scope->lanes.size()));
        resolved.label = scope->tempo ? tr("%1 + tempo").arg(lanes) : lanes;
    }
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
std::optional<SongDocument::TimeScope> SongView::timeSelectionScope() const
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !m_timeline || !selection.active())
        return std::nullopt;
    SongDocument::TimeScope scope;
    if (selection.scope == EditorSelectionModel::TimeSelection::Lanes) {
        scope.lanes = selection.lanes;
        scope.tempo = selection.tempo;
        if (scope.lanes.empty() && !scope.tempo)
            return std::nullopt;
    } else {
        scope.tracks = timeSelectionTracks();
        if (scope.tracks.empty())
            return std::nullopt;
        scope.wholeSong = m_selectionModel.timeSelectionCoversTempo(usedTrackMask(m_timeline));
        for (const int track : scope.tracks) {
            for (const uint8_t cc : trackCcs(track))
                scope.lanes.emplace_back(track, cc);
        }
    }
    return scope;
}
void SongView::copyTimeSelection()
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active())
        return;
    const auto scope = timeSelectionScope();
    if (!scope)
        return;
    const auto range = SongDocument::TimeRange{selection.startTick, selection.endTick};
    const TimeRangeContents contents = gatherRange(*m_document, range, *scope);
    Clip clip;
    clip.span = range.span();
    int noteCount = 0;
    int pointCount = 0;
    for (const TimeRangeContents::TrackNotes &track : contents.tracks) {
        ClipTrack ct{track.track, {}};
        for (const DocNote &note : track.notes) {
            ct.notes.push_back(
                {uint32_t(note.tick - range.startTick), note.key,
                 note.duration ? note.duration : uint32_t(m_grid.gridTicksAt(note.tick)),
                 note.velocity});
        }
        noteCount += int(ct.notes.size());
        clip.tracks.push_back(std::move(ct));
    }
    for (const TimeRangeContents::TrackLane &lane : contents.lanes) {
        ClipLane clipLane{lane.track, lane.cc, {}};
        for (const DocLanePoint &pt : lane.points)
            clipLane.points.push_back({uint32_t(pt.tick - range.startTick), pt.value});
        pointCount += int(clipLane.points.size());
        // Empty segments remain part of the copied shape. Merge paste treats
        // them as no-ops, so they never silence destination points.
        clip.lanes.push_back(std::move(clipLane));
    }
    for (const TempoPoint &point : contents.tempo) {
        clip.tempo.push_back({point.tick - range.startTick, point.microsecondsPerQuarterNote});
        ++pointCount;
    }
    writeClipboard(clip, m_timeline->ticksPerBeat);
    announce(tr("Copied range: %1 note(s), %2 automation point(s)").arg(noteCount).arg(pointCount));
}
void SongView::deleteTimeSelection()
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active())
        return;
    const auto scope = timeSelectionScope();
    if (!scope) {
        announce(tr("Nothing to delete in the time selection"));
        return;
    }
    const auto range = SongDocument::TimeRange{selection.startTick, selection.endTick};
    TimeRangeContents contents = gatherRange(*m_document, range, *scope);
    SongDocument::RangeEdit edit;
    for (const TimeRangeContents::TrackNotes &track : contents.tracks) {
        for (const DocNote &note : track.notes)
            edit.removeNotes.push_back(note);
    }
    for (const TimeRangeContents::TrackLane &lane : contents.lanes) {
        for (const DocLanePoint &point : lane.points)
            edit.removePoints.push_back(point);
    }
    edit.removeTempo = std::move(contents.tempo);
    if (edit.empty()) {
        announce(tr("Nothing to delete in the time selection"));
        return;
    }
    const int notes = int(edit.removeNotes.size());
    const int points = int(edit.removePoints.size() + edit.removeTempo.size());
    m_document->applyRangeEdit(tr("delete range"), edit);
    announce(tr("Deleted range: %1 note(s), %2 automation point(s)").arg(notes).arg(points));
}
void SongView::transposeTimeSelection(int dKey)
{
    const auto &selection = m_selectionModel.timeSelection();
    if (!m_document || !selection.active() || dKey == 0 ||
        selection.scope == EditorSelectionModel::TimeSelection::Lanes)
        return;
    const auto scope = timeSelectionScope();
    if (!scope)
        return;
    // gatherRange also collects lanes/tempo, but transpose only moves notes:
    // flatten the track groups into the scan's note list.
    const TimeRangeContents contents = gatherRange(
        *m_document, SongDocument::TimeRange{selection.startTick, selection.endTick}, *scope);
    std::vector<DocNote> notes;
    for (const TimeRangeContents::TrackNotes &track : contents.tracks) {
        for (const DocNote &note : track.notes)
            notes.push_back(note);
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
    const SongView::DocumentSwapHintScope swapHint{*this, cNoteMutationDirty};
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
    if (!m_scaleController.resolveFoldDestinations(notes, degreeDelta, destinations))
        return;
    const SongView::DocumentSwapHintScope swapHint{*this, cNoteMutationDirty};
    if (!m_document->moveNotesToPitches(notes, destinations, 0, /*mergeable=*/true))
        return;
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
    const uint64_t snapped =
        right ? m_grid.snapTickUp(double(s) + 1.0) : m_grid.snapTickDown(double(s) - 1.0);
    const int64_t dTick = int64_t(snapped) - int64_t(s);
    if (dTick == 0)
        return;
    const auto scope = timeSelectionScope();
    if (!scope)
        return;
    TimeRangeContents contents = gatherRange(*m_document, SongDocument::TimeRange{s, e}, *scope);
    std::vector<DocNote> notes;
    std::vector<DocLanePoint> points;
    std::vector<TempoPoint> tempo;
    for (const TimeRangeContents::TrackNotes &track : contents.tracks) {
        for (const DocNote &note : track.notes)
            notes.push_back(note);
    }
    for (const TimeRangeContents::TrackLane &lane : contents.lanes) {
        for (const DocLanePoint &point : lane.points)
            points.push_back(point);
    }
    tempo = std::move(contents.tempo);
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
void SongView::insertTimeAtPlaybackCursor()
{
    if (!m_document || !m_timeline)
        return;
    const uint64_t cursorTick =
        m_playing ? uint64_t(std::clamp(m_playheadTick, 0.0, double(m_timeline->lengthTicks)) + 0.5)
                  : m_editCursorTick;
    openInsertTimePrompt(cursorTick, m_grid.segmentAt(cursorTick));
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
void SongView::pasteRangeAtEditCursor(const Clip &clip)
{
    if (!m_document || !m_timeline || clip.span == 0 || clip.empty())
        return;
    const uint64_t s = m_grid.snapTick(double(m_editCursorTick));
    const uint64_t e = s + clip.span;

    // A clip whose content came from one track retargets to the selected
    // track (cross-track copy); multi-track clips paste back in place.
    const DestinationMapper destinations(*m_document, m_selectionModel, singleSourceTrack(clip));
    SongDocument::RangeEdit edit;
    for (const ClipTrack &track : clip.tracks) {
        if (track.notes.empty())
            continue;
        const std::optional<int> destinationTrack = destinations.map(track.track);
        if (!destinationTrack)
            continue;
        edit.minimumEngineTrackCount =
            std::max(edit.minimumEngineTrackCount, *destinationTrack + 1);
        SongDocument::RangeEdit::TrackNotes notes{*destinationTrack, {}};
        for (const ClipNote &note : track.notes)
            notes.notes.push_back({s + note.relTick, note.key, note.duration, note.velocity});
        edit.addNotes.push_back(std::move(notes));
    }
    for (const ClipLane &lane : clip.lanes) {
        if (lane.points.empty())
            continue;
        const std::optional<int> destinationTrack = destinations.map(lane.track);
        if (!destinationTrack)
            continue;
        edit.minimumEngineTrackCount =
            std::max(edit.minimumEngineTrackCount, *destinationTrack + 1);
        SongDocument::RangeEdit::LaneWrite write{*destinationTrack, lane.cc, {}};
        for (const auto &[relativeTick, value] : lane.points)
            write.points.push_back({s + relativeTick, value});
        appendExactTickRemovals(m_document->lanePoints(*destinationTrack, lane.cc), write.points,
                                edit.removePoints);
        edit.addPoints.push_back(std::move(write));
    }
    if (!clip.tempo.empty()) {
        for (const auto &point : clip.tempo)
            edit.addTempo.push_back({s + point.tick, point.microsecondsPerQuarterNote});
        appendExactTickRemovals(m_document->tempoPoints(), edit.addTempo, edit.removeTempo);
    }
    if (edit.empty()) {
        announce(tr("Nothing useful to paste"));
        return;
    }
    m_document->applyRangeEdit(tr("paste range"), edit);

    // Set up for tiling: advance to the clip's end while keeping the newly
    // merged content, rather than the advanced cursor, in view.
    m_selectionModel.clearTimeSelection();
    commitEditCursor(e);
    ensureTickVisible(s);
    announce(tr("Merged range · edit cursor moved to its end — paste again to repeat"));
}
void SongView::pasteFromClipboard()
{
    if (!m_document)
        return;
    auto clip = readClipboardClip();
    if (!clip)
        return;
    if (clip->span > 0) {
        if (!clip->empty())
            pasteRangeAtEditCursor(*clip);
        return;
    }
    // Plain note clip: additive paste of the clip's first track onto the
    // selected track at the edit cursor (the roll's note-paste path).
    if (clip->tracks.empty() || clip->tracks.front().notes.empty())
        return;
    const uint64_t base = m_grid.snapTick(double(m_editCursorTick));
    const int selectedTrack = m_selectionModel.primaryTrack();
    const std::vector<DocNote> before = m_document->notesForTrack(selectedTrack);
    std::vector<SongDocument::NewNote> notes;
    uint64_t end = base;
    for (const ClipNote &cn : clip->tracks.front().notes) {
        const uint64_t tick = base + cn.relTick;
        notes.push_back({tick, cn.key, cn.duration, cn.velocity});
        end = std::max(end, tick + cn.duration);
    }
    const SongView::DocumentSwapHintScope swapHint{*this, cNoteMutationDirty};
    m_document->addNotes(selectedTrack, notes);
    m_selectionModel.setNoteSelection(m_document->insertedNoteIds(selectedTrack, before));
    // Like pasteRangeAtEditCursor: advance the edit cursor past the pasted
    // notes so repeated Ctrl+V lays copies back-to-back, but keep the view
    // anchored on the content that just landed.
    commitEditCursor(end);
    ensureTickVisible(base);
    announce(tr("Pasted %n note(s)", nullptr, int(notes.size())));
}
std::optional<Clip> SongView::readClipboardClip()
{
    if (!m_timeline)
        return std::nullopt;
    bool decodeFailed = false;
    auto clip = readClipboard(m_timeline->ticksPerBeat, &decodeFailed);
    if (clip)
        return clip;
    if (decodeFailed)
        announce(tr("Cannot paste: clipboard clip could not be decoded"));
    return std::nullopt;
}
void SongView::showTimeSelectionMenu(const QPoint &globalPos)
{
    if (!m_document || !m_selectionModel.timeSelection().active())
        return;
    QMenu menu(this);
    // Copy is text only: MainWindow's native Edit menu owns its shortcut.
    const auto &keys = keymap::Registry::instance();
    QAction *copy =
        menu.addAction(contextActionText(tr("Copy range"), QStringLiteral("roll.copy")));
    QAction *cut = menu.addAction(tr("Cut range"));
    cut->setShortcut(keys.bindings(QStringLiteral("roll.cut")).value(0));
    QAction *del = menu.addAction(tr("Delete range"));
    QAction *insertBlank = menu.addAction(tr("Insert blank time"));
    QAction *duplicate = menu.addAction(tr("Duplicate time"));
    duplicate->setShortcut(keys.bindings(QStringLiteral("roll.duplicate_time")).value(0));
    QAction *removeContents = menu.addAction(tr("Remove contents (shift left)"));
    QAction *paste = menu.addAction(tr("Paste at edit cursor"));
    paste->setShortcut(keys.bindings(QStringLiteral("roll.paste")).value(0));
    const auto clipboard =
        m_timeline ? readClipboard(m_timeline->ticksPerBeat) : std::optional<Clip>{};
    paste->setEnabled(clipboard && !clipboard->empty());
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
        pasteFromClipboard();
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
