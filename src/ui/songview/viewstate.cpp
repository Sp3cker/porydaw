#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/eventlistview.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/trackheaderpanel.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <optional>
#include <ranges>
#include <span>
#include <utility>
#include <vector>

using namespace songview;
using namespace songview::detail;

void SongView::setEditCursorTick(uint64_t tick)
{
    if (m_editCursorTick == tick)
        return;
    m_editCursorTick = tick;
    m_headers->syncVoices();
    refreshPitchEnvelopeState();
    refreshTimelineViews();
    refreshDrawerPages();
}
void SongView::commitEditCursor(uint64_t tick)
{
    setEditCursorTick(tick);
    emit editCursorMoved(tick);
}

void SongView::notifyVelocityGestureChanged()
{
    if (m_roll)
        m_roll->invalidateContent();
    if (m_editorDrawer)
        m_editorDrawer->velocityArea()->velocityGestureChanged();
}
bool SongView::beginVelocityGesture(const std::vector<DocNote> &notes)
{
    if (!m_document)
        return false;
    std::vector<NoteVelocity> targets;
    targets.reserve(notes.size());
    for (const DocNote &note : notes)
        targets.push_back({note.noteId, int(note.velocity)});
    if (!m_velocityGesture.begin(m_document->revision(), std::move(targets)))
        return false;
    notifyVelocityGestureChanged();
    return true;
}
bool SongView::updateVelocityGesture(const std::vector<NoteVelocity> &updates)
{
    if (!m_velocityGesture.update(updates))
        return false;
    notifyVelocityGestureChanged();
    return true;
}
bool SongView::updateVelocityGestureByDelta(int delta)
{
    if (!m_velocityGesture.updateByDelta(delta))
        return false;
    notifyVelocityGestureChanged();
    return true;
}
void SongView::cancelVelocityGesture()
{
    if (m_velocityGesture.cancel())
        notifyVelocityGestureChanged();
}
SongView::VelocityCommitResult SongView::commitVelocityGesture()
{
    std::optional<VelocityGestureModel::Completion> completion = m_velocityGesture.takeCompletion();
    if (!completion)
        return VelocityCommitResult::NoGesture;
    const uint64_t expectedRevision = completion->expectedRevision;
    notifyVelocityGestureChanged();
    if (!m_document)
        return VelocityCommitResult::Rejected;
    const std::optional<uint64_t> revision =
        m_document->setNotesVelocities(expectedRevision, completion->targets);
    if (!revision)
        return VelocityCommitResult::Rejected;
    if (*revision > expectedRevision)
        return VelocityCommitResult::Committed;
    if (*revision == expectedRevision)
        return VelocityCommitResult::Unchanged;
    return VelocityCommitResult::Rejected;
}
std::optional<uint8_t> SongView::previewVelocity(NoteId noteId) const
{
    return m_velocityGesture.previewVelocity(noteId);
}
void SongView::setProjectionLocked(bool locked)
{
    m_projectionLocked = locked;
}
void SongView::flushProjectionIfDirty()
{
    if (!m_projectionLocked && m_projectionDirty) {
        m_projectionDirty = false;
        rebuildProjectionWithAnchoring();
    }
}
void SongView::buildOccupancySet(std::span<bool, 128> out) const
{
    std::ranges::fill(out, false);
    for (const ViewNote &note : m_model.notes) {
        if (note.track == m_selectionModel.primaryTrack())
            out[note.key] = true;
    }
}
void SongView::rebuildProjectionWithAnchoring()
{
    m_projectionDirty = false;
    if (!m_timeline)
        return;

    const double centerY = rollViewportHeight() / 2.0;
    const int centerPitch =
        m_projection.yToPitch(centerY, m_keyHeight, m_scrollY, m_roll->devicePixelRatioF());
    updateScaleProjection();

    double newScrollY = m_scrollY;
    if (centerPitch != PitchProjection::cHiddenRow) {
        const int anchorPitch = m_projection.nearestVisiblePitch(centerPitch);
        const int anchorRow = m_projection.rowForPitch(anchorPitch);
        if (anchorRow != PitchProjection::cHiddenRow)
            newScrollY = anchorRow * m_keyHeight - centerY;
    }
    m_scrollY = std::clamp(newScrollY, 0.0, maxRollScroll());
    updateScrollbars();
    m_roll->invalidateContent();
}
void SongView::setScaleHighlight(bool enabled)
{
    if (enabled == m_scaleHighlight)
        return;
    m_scaleHighlight = enabled;
    m_roll->invalidateContent();
    emit scaleHighlightChanged();
}
void SongView::setScaleFold(bool enabled)
{
    if (enabled == m_scaleFold)
        return;
    m_scaleFold = enabled;
    rebuildProjectionWithAnchoring();
    emit scaleFoldChanged();
}
void SongView::setScaleRoot(int root)
{
    root = std::clamp(root, 0, 11);
    if (root == m_scaleRoot)
        return;
    m_scaleRoot = root;
    updateScaleMembership();
    if (m_scaleHighlight || m_scaleFold)
        m_roll->invalidateContent();
    emit scaleRootChanged();
}
void SongView::setScaleId(porydaw_scale::ScaleId id)
{
    if (id == m_scaleId)
        return;
    m_scaleId = id;
    updateScaleMembership();
    if (m_scaleHighlight || m_scaleFold)
        m_roll->invalidateContent();
    emit scaleIdChanged();
}
void SongView::updateScaleProjection()
{
    if (m_scaleFold) {
        std::array<bool, 128> occupancy{};
        buildOccupancySet(std::span<bool, 128>(occupancy));
        std::array<uint8_t, 128> visiblePitches;
        int count = 0;
        for (int pitch = 0; pitch < 128; pitch++) {
            if (occupancy[pitch])
                visiblePitches[count++] = static_cast<uint8_t>(pitch);
        }
        m_projection.buildFromPitches(std::span(visiblePitches).first(count));
    } else {
        m_projection.buildChromatic();
    }
    updateScaleMembership();
}
void SongView::updateScaleMembership()
{
    std::array<bool, 128> isScalePitch{};
    for (int pitch = 0; pitch < 128; pitch++)
        isScalePitch[pitch] = porydaw_scale::isScalePitch(m_scaleId, m_scaleRoot, pitch);
    m_projection.setScalePitchClassification(std::span<const bool, 128>(isScalePitch));
}
void SongView::setVelocityColorMode(bool on)
{
    if (m_velocityColorMode == on)
        return;
    m_velocityColorMode = on;
    m_roll->invalidateContent();
}
void SongView::setNoteNameMode(bool on)
{
    if (m_noteNameMode == on)
        return;
    m_noteNameMode = on;
    m_roll->invalidateContent();
}
void SongView::setFollowPlayhead(bool on)
{
    if (m_followPlayhead == on)
        return;
    m_followPlayhead = on;
    m_events->setFollowPlayhead(on);
    refreshDrawerPages();
}
void SongView::addEmptyLane(int track, uint8_t cc)
{
    if (track < 0 || track > 15)
        return;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), cc};
    if (m_editorViewState.emptyLanes.insert(lane).second)
        applyEditorViewState(m_editorViewState);
}
void SongView::removeEmptyLane(int track, uint8_t cc)
{
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), cc};
    if (m_editorViewState.emptyLanes.erase(lane) != 0)
        applyEditorViewState(m_editorViewState);
}
void SongView::setLaneDisplayRange(int track, uint8_t cc, int maxValue)
{
    if (track < 0 || track > 15)
        return;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), cc};
    if (maxValue > 0)
        m_editorViewState.laneRanges[lane] = uint8_t(std::clamp(maxValue, 0, 127));
    else
        m_editorViewState.laneRanges.erase(lane);
    applyEditorViewState(m_editorViewState);
}
EditorViewState SongView::editorViewState() const
{
    return m_editorViewState;
}
void SongView::setEditorViewState(const EditorViewState &state)
{
    const bool drawerChanged = m_editorViewState.drawerState() != state.drawerState();
    m_editorViewState = state;
    if (drawerChanged)
        emit editorDrawerStateChanged(m_editorViewState.drawerState());
}
void SongView::applyEditorDrawerState(const EditorDrawerState &state)
{
    if (m_editorViewState.drawerState() == state)
        return;
    EditorViewState combined = m_editorViewState;
    combined.setDrawerState(state);
    applyEditorViewState(combined);
}
void SongView::applyEditorViewState(const EditorViewState &state)
{
    const bool drawerChanged = m_editorViewState.drawerState() != state.drawerState();
    cancelActiveInteractions();
    m_editorViewState = state;
    if (m_editorDrawer)
        m_editorDrawer->setViewState(m_editorViewState);
    notifyDrawerSongChanged();
    refreshTimelineViews();
    if (drawerChanged)
        emit editorDrawerStateChanged(m_editorViewState.drawerState());
}
