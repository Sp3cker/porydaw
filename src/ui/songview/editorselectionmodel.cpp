#include "ui/songview/editorselectionmodel.h"

#include "core/songdocument.h"

#include <algorithm>
#include <cstddef>
#include <utility>

namespace songview {

void EditorSelectionModel::setObserver(Observer observer)
{
    if (!canMutate())
        return;
    m_observer = std::move(observer);
}

uint32_t EditorSelectionModel::resolvedTrackScope(uint32_t usedTrackMask) const noexcept
{
    return m_trackScope & usedTrackMask & kTrackMask;
}

bool EditorSelectionModel::isNoteSelected(NoteId noteId) const noexcept
{
    return noteId.isAssigned() && std::find(m_noteSelection.cbegin(), m_noteSelection.cend(),
                                            noteId) != m_noteSelection.cend();
}

bool EditorSelectionModel::timeSelectionCoversTrack(int track,
                                                    uint32_t usedTrackMask) const noexcept
{
    if (!m_timeSelection.active() || m_timeSelection.scope == TimeSelection::Lanes || track < 0 ||
        track >= 16)
        return false;
    return (resolvedTrackScope(usedTrackMask) & (uint32_t{1} << track)) != 0;
}

bool EditorSelectionModel::timeSelectionCoversLane(int track, uint8_t controller,
                                                   uint32_t usedTrackMask) const noexcept
{
    if (!m_timeSelection.active() || track < 0 || track >= 16)
        return false;
    if (m_timeSelection.scope == TimeSelection::Lanes)
        return std::find(m_timeSelection.lanes.cbegin(), m_timeSelection.lanes.cend(),
                         std::pair{track, controller}) != m_timeSelection.lanes.cend();
    const uint32_t used = usedTrackMask & kTrackMask;
    const uint32_t selected = resolvedTrackScope(used);
    return (selected & (uint32_t{1} << track)) != 0;
}

bool EditorSelectionModel::timeSelectionCoversTempo(uint32_t usedTrackMask) const noexcept
{
    if (!m_timeSelection.active())
        return false;
    if (m_timeSelection.scope == TimeSelection::Lanes)
        return m_timeSelection.tempo;
    const uint32_t used = usedTrackMask & kTrackMask;
    const uint32_t selected = resolvedTrackScope(used);
    return used != 0 && selected == used;
}

void EditorSelectionModel::setNoteSelection(std::vector<NoteId> ids)
{
    if (!canMutate())
        return;
    std::vector<NoteId> sanitized;
    sanitized.reserve(ids.size());
    for (const NoteId id : ids) {
        if (!id.isAssigned() ||
            std::find(sanitized.cbegin(), sanitized.cend(), id) != sanitized.cend())
            continue;
        sanitized.push_back(id);
    }

    SelectionChange changes = SelectionChange::None;
    if (sanitized != m_noteSelection) {
        m_noteSelection = std::move(sanitized);
        changes = changes | SelectionChange::NoteSelection;
    }
    if (!m_noteSelection.empty() && m_timeSelection.active()) {
        m_timeSelection = TimeSelection();
        changes = changes | SelectionChange::TimeSelection;
    }
    notify(changes);
}

void EditorSelectionModel::clearNoteSelection()
{
    if (!canMutate())
        return;
    if (m_noteSelection.empty())
        return;
    m_noteSelection.clear();
    notify(SelectionChange::NoteSelection);
}

void EditorSelectionModel::setTimeSelection(TimeSelection selection)
{
    if (!canMutate())
        return;
    selection = sanitizeTimeSelection(std::move(selection));
    SelectionChange changes = SelectionChange::None;
    if (!sameTimeSelection(m_timeSelection, selection)) {
        m_timeSelection = std::move(selection);
        changes = changes | SelectionChange::TimeSelection;
    }
    if (m_timeSelection.active() && !m_noteSelection.empty()) {
        m_noteSelection.clear();
        changes = changes | SelectionChange::NoteSelection;
    }
    notify(changes);
}

void EditorSelectionModel::clearTimeSelection()
{
    if (!canMutate())
        return;
    const TimeSelection empty;
    if (sameTimeSelection(m_timeSelection, empty))
        return;
    m_timeSelection = empty;
    notify(SelectionChange::TimeSelection);
}

void EditorSelectionModel::clearBothSelections()
{
    if (!canMutate())
        return;
    SelectionChange changes = SelectionChange::None;
    if (!m_noteSelection.empty()) {
        m_noteSelection.clear();
        changes = changes | SelectionChange::NoteSelection;
    }
    const TimeSelection empty;
    if (!sameTimeSelection(m_timeSelection, empty)) {
        m_timeSelection = empty;
        changes = changes | SelectionChange::TimeSelection;
    }
    notify(changes);
}

void EditorSelectionModel::applyPrimaryTrackTransition(int track)
{
    if (!canMutate())
        return;
    if (track < 0 || track >= 16 || track == m_primaryTrack)
        return;

    SelectionChange changes = SelectionChange::PrimaryTrack;
    m_primaryTrack = track;
    const uint32_t scope = uint32_t{1} << track;
    if (m_trackScope != scope) {
        m_trackScope = scope;
        changes = changes | SelectionChange::TrackScope;
    }
    if (!m_noteSelection.empty()) {
        m_noteSelection.clear();
        changes = changes | SelectionChange::NoteSelection;
    }
    const TimeSelection empty;
    if (!sameTimeSelection(m_timeSelection, empty)) {
        m_timeSelection = empty;
        changes = changes | SelectionChange::TimeSelection;
    }
    notify(changes);
}

void EditorSelectionModel::applyTrackScopeAdjustment(int clickedTrack, uint32_t usedTrackMask,
                                                     TrackScopeAction action)
{
    if (!canMutate())
        return;
    if (clickedTrack < 0 || clickedTrack >= 16)
        return;

    const uint32_t used = usedTrackMask & kTrackMask;
    const uint32_t clickedBit = uint32_t{1} << clickedTrack;
    uint32_t scope = m_trackScope & kTrackMask;
    int primary = m_primaryTrack;
    bool clearNotes = false;
    bool clearTime = false;

    if (action == TrackScopeAction::Plain) {
        if (clickedTrack == m_primaryTrack) {
            scope = clickedBit;
            clearNotes = true;
        } else {
            primary = clickedTrack;
            scope = clickedBit;
            clearNotes = true;
            clearTime = true;
        }
    } else if (action == TrackScopeAction::Toggle) {
        scope ^= clickedBit;
        if (scope == 0)
            return;
        if ((scope & (uint32_t{1} << m_primaryTrack)) == 0) {
            primary = firstTrack(scope);
            clearNotes = true;
        }
    } else {
        const int lo = std::min(m_primaryTrack, clickedTrack);
        const int hi = std::max(m_primaryTrack, clickedTrack);
        scope = 0;
        for (int track = lo; track <= hi; ++track) {
            if (used & (uint32_t{1} << track))
                scope |= uint32_t{1} << track;
        }
        scope |= uint32_t{1} << m_primaryTrack;
    }

    if (scope == 0)
        scope = uint32_t{1} << primary;
    scope &= kTrackMask;
    scope |= uint32_t{1} << primary;

    SelectionChange changes = SelectionChange::None;
    if (primary != m_primaryTrack) {
        m_primaryTrack = primary;
        changes = changes | SelectionChange::PrimaryTrack;
    }
    if (scope != m_trackScope) {
        m_trackScope = scope;
        changes = changes | SelectionChange::TrackScope;
    }
    if (clearNotes && !m_noteSelection.empty()) {
        m_noteSelection.clear();
        changes = changes | SelectionChange::NoteSelection;
    }
    if (clearTime && !sameTimeSelection(m_timeSelection, TimeSelection())) {
        m_timeSelection = TimeSelection();
        changes = changes | SelectionChange::TimeSelection;
    }
    notify(changes);
}

void EditorSelectionModel::reconcileNoteSelection(std::span<const NoteId> validIds)
{
    if (!canMutate())
        return;
    std::vector<NoteId> surviving;
    surviving.reserve(m_noteSelection.size());
    for (const NoteId id : m_noteSelection) {
        if (std::find(validIds.begin(), validIds.end(), id) != validIds.end())
            surviving.push_back(id);
    }
    if (surviving == m_noteSelection)
        return;
    m_noteSelection = std::move(surviving);
    notify(SelectionChange::NoteSelection);
}

void EditorSelectionModel::resetForSongSwap(int firstUsedTrack)
{
    if (!canMutate())
        return;
    const int primary = std::clamp(firstUsedTrack, 0, 15);
    const uint32_t scope = uint32_t{1} << primary;
    SelectionChange changes = SelectionChange::None;
    if (primary != m_primaryTrack) {
        m_primaryTrack = primary;
        changes = changes | SelectionChange::PrimaryTrack;
    }
    if (scope != m_trackScope) {
        m_trackScope = scope;
        changes = changes | SelectionChange::TrackScope;
    }
    if (!m_noteSelection.empty()) {
        m_noteSelection.clear();
        changes = changes | SelectionChange::NoteSelection;
    }
    const TimeSelection empty;
    if (!sameTimeSelection(m_timeSelection, empty)) {
        m_timeSelection = empty;
        changes = changes | SelectionChange::TimeSelection;
    }
    notify(changes);
}

void EditorSelectionModel::clearNoteSelectionForDocumentAttachment()
{
    if (!canMutate())
        return;
    if (m_noteSelection.empty())
        return;
    m_noteSelection.clear();
    notify(SelectionChange::NoteSelection);
}

void EditorSelectionModel::applyRemap(const TrackRemap &remap)
{
    if (!canMutate())
        return;
    const auto mappedTrack = [&remap](int track) {
        if (track < 0 || static_cast<std::size_t>(track) >= remap.engineTrackMap.size())
            return -1;
        const int destination = remap.engineTrackMap[static_cast<std::size_t>(track)];
        return destination >= 0 && destination < remap.newEngineTrackCount && destination < 16
                   ? destination
                   : -1;
    };
    const int oldPrimary = m_primaryTrack;
    const int mappedPrimary = mappedTrack(oldPrimary);
    const bool primaryDeleted = mappedPrimary < 0;
    const int fallback = std::min(oldPrimary, std::max(0, remap.newEngineTrackCount - 1));
    const int newPrimary = primaryDeleted ? std::clamp(fallback, 0, 15) : mappedPrimary;

    uint32_t newScope = 0;
    for (int track = 0; track < 16; ++track) {
        if (!(m_trackScope & (uint32_t{1} << track)))
            continue;
        const int destination = mappedTrack(track);
        if (destination >= 0)
            newScope |= uint32_t{1} << destination;
    }
    newScope |= uint32_t{1} << newPrimary;

    TimeSelection newTimeSelection = m_timeSelection;
    if (primaryDeleted && newTimeSelection.scope == TimeSelection::Tracks) {
        newTimeSelection = TimeSelection();
    } else if (newTimeSelection.scope == TimeSelection::Lanes) {
        std::vector<std::pair<int, uint8_t>> lanes;
        lanes.reserve(newTimeSelection.lanes.size());
        for (const auto &lane : newTimeSelection.lanes) {
            const int destination = mappedTrack(lane.first);
            if (destination >= 0)
                lanes.emplace_back(destination, lane.second);
        }
        newTimeSelection.lanes = std::move(lanes);
        newTimeSelection = sanitizeTimeSelection(std::move(newTimeSelection));
    }

    SelectionChange changes = SelectionChange::None;
    if (newPrimary != m_primaryTrack) {
        m_primaryTrack = newPrimary;
        changes = changes | SelectionChange::PrimaryTrack;
    }
    if (newScope != m_trackScope) {
        m_trackScope = newScope;
        changes = changes | SelectionChange::TrackScope;
    }
    if (!sameTimeSelection(m_timeSelection, newTimeSelection)) {
        m_timeSelection = std::move(newTimeSelection);
        changes = changes | SelectionChange::TimeSelection;
    }
    notify(changes);
}

void EditorSelectionModel::notify(SelectionChange changes)
{
    if (changes == SelectionChange::None || !m_observer)
        return;
    m_notifying = true;
    struct NotificationGuard {
        bool &notifying;
        ~NotificationGuard() { notifying = false; }
    } guard{m_notifying};
    m_observer(changes);
}

bool EditorSelectionModel::canMutate() const noexcept
{
    return !m_notifying;
}

bool EditorSelectionModel::sameTimeSelection(const TimeSelection &a,
                                             const TimeSelection &b) noexcept
{
    return a.startTick == b.startTick && a.endTick == b.endTick && a.scope == b.scope &&
           a.lanes == b.lanes && a.tempo == b.tempo;
}

EditorSelectionModel::TimeSelection
EditorSelectionModel::sanitizeTimeSelection(TimeSelection selection)
{
    if (selection.scope == TimeSelection::Lanes) {
        std::vector<std::pair<int, uint8_t>> lanes;
        lanes.reserve(selection.lanes.size());
        for (const auto &lane : selection.lanes) {
            if (lane.first < 0 || lane.first >= 16 ||
                std::find(lanes.cbegin(), lanes.cend(), lane) != lanes.cend())
                continue;
            lanes.push_back(lane);
        }
        selection.lanes = std::move(lanes);
        if (selection.active() && selection.lanes.empty() && !selection.tempo)
            return TimeSelection();
    }
    return selection;
}

int EditorSelectionModel::firstTrack(uint32_t mask) noexcept
{
    for (int track = 0; track < 16; ++track) {
        if (mask & (uint32_t{1} << track))
            return track;
    }
    return 0;
}

} // namespace songview
